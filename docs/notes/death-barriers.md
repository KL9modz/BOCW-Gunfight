# Death barriers — the map's kill volumes, and the `gf_deathbarrier` switch (2026-09-19)

> **Status: researched + built, NOT run in-game.** Side payload
> `C:\bocw\payloads\gunfight_menu.deathbarrier.gscc` (397,995 B / 2,265 strings, check-gsc PASS zero
> notes, check-args 0 mismatches). The live slot `gunfight_menu.gscc` is still 454705d (391,566 B).
> Which of the three "off" mechanisms the engine honours is a MEASUREMENT this note is waiting for —
> §5 is the one-match test sheet.

klaze, 2026-09-19: *"we already have a toggle for oob but not for the real death barriers. god mode
doesn't prevent them."* Two facts in one line: [[game-systems]] §14d's `gf_oob` (the restricted-area
warning + countdown + kill) is a different system from the instant death off a ledge / into water /
under the floor, and `enableinvulnerability()` does not save a player from the latter.

## 1. What a death barrier is in this engine (dump facts)

| Fact | Where |
|---|---|
| The kill volumes are **engine entities of classname `trigger_hurt`**; stock's own word for them is *kill brush* | `weapons/weaponobjects.gsc:2969` `deleteonkillbrush` fetches `getentarray( "trigger_hurt", "classname" )`; `killstreaks/qrdrone.gsc:662` same; `killstreaks/mp/supplydrop.gsc:199` caches them as `.hurttriggers` |
| They carry a `dmg` key and the ordinary trigger enable state | `mp/mp_black_sea.gsc:119` reads `self.dmg` off `fire_trigger_hurt`; `weaponobjects.gsc:2940/2983` skips a kill brush that is `!istriggerenabled()` — stock's own predicate for "this one is inert" |
| A death by one reports `MOD_TRIGGER_HURT` with the trigger entity as the attacker | `player/player_killed.gsc:658/1175/1293` (`attacker.classname == "trigger_hurt"`), `gametypes/gun.gsc:162`, `player_killed.gsc:2722` (`MOD_TRIGGER_HURT && !isonground()` = the mid-air death) |
| **No MP script kills a player at a map edge.** Every `suicide()` outside Zombies: `oob.gsc:873` (the restricted-area kill, which `gf_oob` already silences), `globallogic_ui.gsc:207/353/403` (menu picks), `spy.gsc`, `teams.gsc:290` (team change), `player_killed.gsc:2162` (team-kill punishment), `mp/mp_express_rm_train.gsc:229` (the train crusher: a `"touch"` waittill on the train + `MOD_CRUSH` + `suicide()`) | grep of `suicide()` over `core_common` / `mp_common` / `mp` / `killstreaks` / `weapons` |
| No MP "fell out of the world" monitor exists; Zombies' `player_out_of_playable_area_monitor` is `zm_common/zm_player.gsc:1128` only | grep `playable_area` / `out_of_world` / `killz` |
| Vehicles get a script `"touch"` notify for `trigger_hurt` / `trigger_out_of_bounds` and self-destruct (killstreak vehicles only) | `killstreaks/killstreak_vehicle.gsc:594` |

So the "real death barrier" is the engine's own `trigger_hurt` handling. The script side only ever
*reads* these entities; nothing stock arms or disarms them at map load.

## 2. Why god mode does not save you (what is measured, what is inferred)

- **Measured (klaze):** `enableinvulnerability()` (the menu's Godmode) does not survive a death barrier.
- **Dump fact:** the MP player-damage callback returns at once for an invulnerable player —
  `player/player_damage.gsc:53` `if ( self getinvulnerability() ) return;` — before anything else,
  `MOD_TRIGGER_HURT` included (`:862` `should_allow_postgame_damage` names the MOD, so the callback
  does expect to see it).
- **Inference, not measured:** therefore the barrier kill does not depend on the script callback's
  verdict — the engine lands it regardless (a *no-protection* hurt, the Quake-lineage `trigger_hurt`
  spawnflag). ⚠ The Zombies Onslaught gametype reads `params.eattacker.classname === "trigger_hurt"`
  inside its `on_player_damage` callback (`zm_common/gametypes/zonslaught.gsc:345`), so at least some
  hurt-trigger damage *does* reach script callbacks — which volumes bypass the veto and which do not
  is exactly what the BARRIER line's `last:` field will show (`god:1` on a `TRIGGER_HURT` death =
  the veto was bypassed).
- **Consequence for the design:** a `level.onplayerdamage` gate (the fall-damage layer,
  `mod_onplayerdamage`) is the wrong tool here. The switch acts on the entities instead.

## 3. The switch — `gf_deathbarrier`, Movement → Death barriers, app Movement row

Plain dvar (not the packed store — inserting a packed key shifts chunk positions for a stale app,
the `gf_oob` precedent). Default **0 = stock**: a player who leaves the map with barriers off falls
until something stops him, so this is opt-in, unlike `gf_oob`. Applied from `mod_movement()` — every
round (the level is rebuilt per round) and live from Apply-now (scope `move`).

| Mode | What it does | Reversible? | Stock precedent |
|---|---|---|---|
| 1 disabled | `triggerenable( 0 )` on every `trigger_hurt` that is enabled; each one marked `gf_kb_off` | yes — "stock" re-enables exactly the marked ones | `!istriggerenabled()` = inert kill brush (`weaponobjects.gsc:2940/2983`); nothing stock disables a hurt trigger at load, so the flag is ours |
| 2 deleted | `delete()` every `trigger_hurt` | next round (level rebuild) | the BO1/BO2 mod-menu shape; stock deletes brush triggers freely (`mp_black_sea.gsc:136` `12v12_bounds`). Stock readers re-fetch the array each pass (`weaponobjects.gsc:2978`) or `isdefined()` a cached one (`:2938`); `supplydrop.gsc:199` / `qrdrone.gsc:667` hold a cached list on killstreak paths a Gunfight match does not run |
| 3 sunk | `.origin -= (0,0,40000)`; start origin kept in `gf_kb_org` | yes — "stock" puts them back | `mp/mp_russianbase_rm.gsc:91` parks its train hurt trigger by writing `.origin` |

Try them **in that order** — 1 is the clean one if the engine's hurt touch honours the trigger-enabled
flag, 2 is the fallback if it does not, 3 is the fallback if a delete upsets something. Not touched
on purpose: the Express train crusher (a script kill, §1), vehicles, AI.

Bridge: `set gf_deathbarrier 1` (21 B) then `apply move` — or the app row + Apply now.

## 4. The BARRIER debug line — `gf_dbg_barrier` (Display → Debug feed, the Death barriers page, app)

One host feed line every 3 s ([[debug-feed-one-line]]):

```
BARRIER mode:1 n:14 ena:0 off:14 del:0 sunk:0 tn:1 nw:0 dmg:100000x13,5x1  host in:1 alive:1 god:0 z:-612  last:klaze TRIGGER_HURT by:trigger_hurt god:1 z:-640
```

- `n` trigger_hurt count on the map · `ena` how many are enabled right now · `off/del/sunk` what the
  switch holds · `tn/nw` how many carry a `targetname` / `script_noteworthy` (the named ones are the
  scripted hazards — Black Sea's fire, the trains) · `dmg` the distinct `dmg` values × count.
- `host in:N` = the host is standing inside N hurt volumes right now (`istouching`, which ignores the
  enabled flag) · `alive` · `god` · `z`. **`in:1 alive:1` held for several ticks is the proof the
  switch works** — no aim, no timing, one screenshot.
- `last:` the last death of ANY player (a `callback::on_player_killed` record): name, MOD (prefix
  stripped), attacker classname, whether the victim was invulnerable, his z. This is what says what
  killed someone: `TRIGGER_HURT by:trigger_hurt` = a death barrier; `FALLING by:none` = fall damage;
  `SUICIDE` = a script kill (oob / train / team-kill); `CRUSH by:script_model` = the Express train.

## 5. Test sheet — one match (klaze; nothing here is autonomous, it needs a body at a ledge)

1. Inject `gunfight_menu.deathbarrier.gscc` (swap it into the live slot first, or point the watcher at
   it), then **restart the match (F7)** so `mod_apply` runs — klaze's own step.
2. Movement → Death barriers → *Debug line* ON. Read the first line: `n` > 0 says the map has
   `trigger_hurt` volumes at all (if `n:0` on a map that still kills, the kill is something else —
   screenshot the `last:` field after dying once and stop).
3. Baseline, mode 0: Godmode ON, walk off the edge that kills. Expected from klaze's report: death,
   `last: … TRIGGER_HURT by:trigger_hurt god:1`. That single field confirms §2 (the kill bypasses the
   script veto) — or refutes it (`god:0` = the god toggle was not actually on; `FALLING` = it was fall
   damage all along; `SUICIDE` = a script kill).
4. Mode 1 (disabled): same edge. Alive + `in:1 alive:1` on the line = mode 1 works — **done**.
   Dead with `TRIGGER_HURT` again = the engine ignores the enabled flag for hurt triggers → mode 2.
5. Mode 2 (deleted): same edge. Alive = works (note `n:0` on the line, back next round). A crash →
   read the crash dump (`%LOCALAPPDATA%\Activision\Call Of Duty Black Ops Cold War\crash_reports`)
   before blaming the delete, then mode 3.
6. Mode 3 (sunk): same edge.
7. Whatever worked: switch back to stock, walk the edge again — death returns (1 and 3 at once; 2 at
   the next round). Then leave it OFF for a full round change and confirm it re-arms (`mod_movement`
   runs each round).

Record the working mode here and in the memory note; then the default question (stock vs off) is
klaze's call — with barriers off, a fall off the map never ends on its own; Teleport → *me to centre*
is the way back.

## Untried — not ruled out
- Which volumes (if any) still reach the script damage callback — the `last:` field on a mode-0 death.
- A per-player "immune" variant (keep the barriers for bots, free the host) — would need the engine to
  consult the callback, which §2 says it does not; not built.
- The `dmg` key as a live knob (`t.dmg = 0`) — whether the engine reads the entity field each touch or
  a cached spawn value is unknown; not built (three mechanisms already cover the outcomes).
