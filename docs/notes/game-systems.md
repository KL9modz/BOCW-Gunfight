# BOCW game systems — reference for mod expansion (research 2026-09-11)

Static analysis of the decompiled dump (`bocw-source-main/scripts`, 1806 gsc + 1022 csc). Purpose: a
working model of how the game works, so `gunfight_mod` can be expanded on solid ground, plus a running
inventory of map-selection avenues.

## 1. Gunfight gametype anatomy — `scripts/mp_common/gametypes/gunfight.gsc` (1306 lines)
⚠ `gun.gsc` is **Gun Game** (weapon progression, `gun_rambo`) — NOT Gunfight. The real one is `gunfight.gsc`,
built on the shared `gametypes/gametype` base (as are `fireteam`, `dropkick`, `dem`), while most modes use
`globallogic`.

- **Entry:** `event_handler[gametype_init] main()` — calls `globallogic::init()`, then installs the whole
  callback surface on `level.*`:
  `onstartgametype, givecustomloadout, onendround, ononeleftevent, ondeadevent, ontimelimit, gettimelimit`
  and event callbacks `callback::on_game_playing/on_connect/on_spawned/on_disconnect`,
  `player::function_cf3aa03d` (onplayerkilled). **These are the hook points a mod overrides** (the mod
  already reassigns `level.ontimelimit`/`level.gettimelimit`).
- **The map-crash source (exact):** `onstartgametype()` line 119 `if ( !setupzones() ) return;`.
  `setupzones()` (827) reads `gunfight_zone_trigger` entities; `getzonearray()` (811) reads
  `gunfight_zone_center`. **Off-Gunfight maps have neither** → `level.zones` stays undefined → `overtime()`
  (931) dereferences `level.zones[0]` and kills its thread. `gunfight_mod` guards this (`level.zones = []`)
  and replaces `ontimelimit` to skip the crashing `overtime()`. So "Gunfight plays fine on any map UNTIL a
  round reaches overtime" — the mod's timelimit_fix is load-bearing exactly on that round.
- **Loadouts:** fixed rotating set from scriptbundle `gunfightloadoutlist` → `mp_gunfight_loadout_default`,
  randomized into `game.var_96a8ff4a`. If `disablecustomcac != 1`, `onstartgametype` flips to custom
  classes (`setgametypesetting(disableclassselection,0)`, `perksenabled 1`, clears `givecustomloadout`).
- **Tunable settings** (via `setgametypesetting`, mod-writable): `timelimit, capturetime, extratime,`
  `gunfightroundsperloadout, gunfightspyplane`, plus hashed ones. Team size = `maxplayers`/`teamcount` in
  the gametypesettings blob (the 4v4 win). `getgametypesetting` takes 1–10 args (unusual — worth probing).

## 2. clientfield — the server→client sync channel (KEY for reaching vanilla joiners)
`scripts/core_common/clientfield_shared.gsc`. The host is the P2P server, so anything the mod pushes here
reaches **every client, including un-modded joiners** — no client injection needed.
- `register(pool, name, version, bits, type)` — declare. Scopes in use: `toplayer`(50) `allplayers`(43)
  `scriptmover`(34) `world`(28) `vehicle` `missile` `playercorpse` `actor`.
- `set / set_to_player / set_world_uimodel / set_player_uimodel` — push values (bit-packed, versioned).
- `register_clientuimodel` / `register_luielem` — drive LUI/HUD from server gameplay.
- ⚠⚠ **Mod-expansion CONSTRAINT (corrected 2026-09-11):** clientfields are SYMMETRIC — the client reads
  each via its own registered HANDLER in `gunfight.csc` (e.g. `activeTrigger`→`function_f789a70b`). A
  VANILLA joiner runs STOCK `gunfight.csc`, which registers ONLY the stock fields (`activeTrigger`,
  `scriptid`, `gunfight_pregame_rob`) with stock handlers. So a server-only mod can drive joiner-visible
  behaviour **only through clientfields/uimodels the STOCK client already registers** (repurpose those +
  the stock HUD uimodels). It CANNOT invent a new synced field and have a vanilla joiner react — there is
  no client handler for it. ⚠ WORSE: registering EXTRA clientfields server-side shifts the field
  count/version and can **desync or crash vanilla joiners**. Rule: with vanilla joiners present, do NOT add
  clientfields — only `set()` existing stock ones. Genuinely new synced mechanics require a matching `.csc`
  mod on every client, which vanilla joiners by definition lack. (This bounds "server-only mod features
  reach joiners": true for repurposed stock channels, false for new ones.)

## 3. Session / map / gametype builtins (levers, from cw-builtins.md + dump usage)
- `switchmap_load(map, gametype?)` +3b7c710 · `switchmap_preload` +3b7c6e0 · `switchmap_switch` +3b7c780 —
  **coordinated two-phase map change stock uses in-match; clients follow** (see the PRIORITY AVENUE in
  pregame-routes.md — the untested joiner-safe map change).
- `map_restart` (0–1 args) +3b0a5c0 — restart current map, maybe without a lobby round.
- `isvalidgametype(str)` +3b0b300, `getgametypeenumfromname(name,hc)` +3bd0d20 — read-only gametype tests
  (`gunfight` enum ~0x2f). `mapexists` +3b0b2d0 — ⚠ **B5: returns TRUE for any name, even invented** (useless
  as a guard).
- `forcegamemodemappings(localclient, "default")` — **client** builtin loading a named gametype↔map mapping
  set; only used in campaign `load.csc:85` with the hardcoded restrictive "default". No permissive named set
  or MP call site found in the dump → weak lever, but a cheap probe (call with other set-name strings).
- `sessionmodeisprivate()` +3ce9830 (+ …onlinegame/…systemlink) — the mod can mechanically verify the
  private-match ground rule instead of trusting it.
- `g_gametype` is a **dvar** (`callbacks_shared.gsc:abort_level` sets it before `exitlevel`).

## 4. Map-avenue status (running tally)
| Avenue | Verdict |
|---|---|
| **`switchmap_load` in-match + joiner** | ▶ **UNTESTED, top priority** — coordinated load, host-inject only, fits the requirement |
| Carry (`map()`+`switchmap_switch`) | 🪦 desyncs/crashes connected clients (measured) |
| `forcegamemodemappings` | ⚠ campaign-only, hardcoded "default", no permissive set found — cheap probe at best |
| compat model (C memory) | 🪦 not a hash list, not adjacent to map records, not a scannable flag — Lua-internal |
| compat model (GSC uimodel) | 🪦 P11: unreachable from any injectable VM (client-frontend LUI) |
| CE watchpoint on compat check | pending — CE built, attach-gate cleared |

## 5. How the mod hooks in (mechanism, for expansion)
`autoexec` → `system::register(#"name", &__init__, ...)` in a payload hooked at `load_shared.gsc`
(all VMs) or `bb.gsc` (MP match). `__init__` threads work and registers `callback::on_start_gametype`
(fires per map load — survives a carry, re-applies each round). `injectcw` replaces `clientids_shared.gsc`
(the one known-safe replace target). One payload at a time (shared replace target). Server-side GSC only;
joiners inherit via clientfields (§2).

## 6. Mod-expansion opportunities found in the source
- **Synthesize the overtime zone on any map.** Off-Gunfight maps lack `gunfight_zone_center`/`_trigger`,
  so stock `setupzones()` fails. But **script CAN spawn trigger volumes** (`spawn("trigger_radius")` — 33
  stock uses; `spawn("trigger_box")` — 1). So the mod could spawn a trigger at map centre + a
  `script_model` zone entity + `gameobjects::create_use_object` and set `level.zones` itself — giving
  **real Gunfight overtime on any map**, not just the current guard-and-skip. Bigger than the current mod.
- **No-zone tiebreak is already sane.** The path the mod reaches via timelimit_fix, `function_c4915ac()`,
  breaks a tied round by **total remaining team health** (sum `player.health` allies vs axis). So the
  simple guard path is functional and fair; zone-synthesis is a fidelity upgrade, not a correctness fix.
- **Bots:** `addtestclient()` is the only bot-add builtin. The mod fills teams with it, hard-bounded by
  `com_maxclients` (session-controlled, script-read-only — the real 6v6 ceiling; not raisable from script).
- **Delivery to joiners:** ONLY via stock clientfields/uimodels the vanilla client already handles (§2 caveat) — repurpose existing channels; new synced fields need a client-side mod joiners lack, and adding fields can crash them. Server-only
  install.

## 7. Event / lifecycle system (mod hook points)
Engine fires `event_handler[name]` handlers at lifecycle points. Registration via `system::register` /
`callback::*`; dispatch is engine-side (hashed `function_d8abfc3d`/`function_52ac9652`). Relevant events:
`gametype_precache → gametype_init → gametype_start`, `level_preinit → level_init → level_finalizeinit`,
`maprestart`, `hostmigration_setupgametype` (state to rebuild on host migration — worth reading if the mod
ever needs migration resilience). ⚠ `sidemission_launch` (the campaign event that triggers switchmap) is
engine-fired in CP only — a script can't dispatch it in MP, so it is NOT a back-door to a clean switch;
call the `switchmap_*` builtins directly (§3 / pregame-routes PRIORITY AVENUE).

## 8. Map-selection avenue sweep — FINAL (GSC/dvar/data layer exhausted)
After a full source pass, the only live GSC-layer map lever is **`switchmap_load` in-match** (untested for
joiners — the priority). Everything else is confirmed closed at this layer:
- No map-unlock / allow-all-maps dvar exists (searched). Custom-match map-offering is `gamemodeismode(1|7)`
  → resolved entirely in **client LUI**, no server/dvar input.
- `com_maxclients` (team ceiling) is session-set, script-read-only — the glitch changes it via playlist
  reconfig; script cannot.
- `g_gametype` is a writable dvar, but changing gametype needs a map reload to take (→ switchmap path).
- The compat/allowed-map set is the client-LUI `uimodeldatastruct #hash_109ccf57a41ffd82` — reachable only
  by client memory (CE, pending), not by any injectable GSC VM (P11).
▶ So at the script layer, the map problem reduces to ONE experiment (in-match `switchmap_load` + joiner)
  and ONE deeper tool (CE on the client LUI compat state). No third GSC avenue remains unexamined.

## 9. Concrete gunfight_mod expansion roadmap (grounded in §1–8 + current mod)
Current mod (`src/gunfight_mod`, 267 lines): config-driven, self-healing (`mod_apply` reruns every round
via `on_start_gametype`), server-side GSC. Flags: zones_guard, timelimit_fix, presentation, timer_override/
timer_minutes, team_size_override/team_size (clamped to `com_maxclients`). Grounded next steps:

1. **Real overtime on any map (`#synth_zones`).** Instead of guard-and-skip, spawn a `trigger_radius` at a
   map-derived centre + a `script_model` zone + `gameobjects::create_use_object`, and set `level.zones`
   yourself (§6). Gives faithful Gunfight overtime (capturable flag) on off-Gunfight maps. Medium effort;
   the stock `setupzones()` (gunfight.gsc:827) is the exact template.
2. **Custom loadout rotation (`#loadout_override`).** Gunfight pulls the round weapon set from scriptbundle
   `gunfightloadoutlist`→`mp_gunfight_loadout_default` into `game.var_96a8ff4a` (gunfight.gsc:80-88). The
   mod can override `level.givecustomloadout` / `setloadout` to inject a chosen weapon rotation. Low-med.
3. **Expose the stock settings the gametype already reads:** `capturetime`, `extratime`, `gunfightspyplane`
   (0/1/2), `gunfightroundsperloadout` — all via `setgametypesetting` like timer/team already are. Trivial.
4. **Map control (`#map_target`)** — pending the PRIORITY AVENUE test: if in-match `switchmap_load(target,
   level.gametype)` is joiner-safe, a flag that coordinated-switches to a verified map at match start is the
   whole lobby-map solution, delivered from the mod. Gate on a verified-safe map list (mapexists lies).
5. **Round/score tuning:** score/round limits via `globallogic`/`util::registerscorelimit`; the no-zone
   tiebreak is total team health (`function_c4915ac`) — could be swapped for round-time or kills if desired.

⚠ Cross-cutting rules for ALL joiner-facing expansion: (a) only drive STOCK clientfields/uimodels — never
register new ones with vanilla joiners present (§2 CONSTRAINT — can crash them); (b) team size ≤
`com_maxclients/2`; (c) any map target must be a verified-loadable name; (d) keep it in `mod_apply` so it
self-heals each round; (e) one payload at a time (shared `clientids_shared` replace target).

## 10. The complete injection surface (server + client VMs) — definitive
Synthesis of P6a/P6c/P7/P11 + frontend-link-set.md. This bounds EVERYTHING the mod can do and settles the
compat-model question from both sides.

| VM | Injectable? | How | What lives there |
|---|---|---|---|
| **Server, all-VM** | ✅ | `load_shared.gsc` hook, replace `clientids_shared.gsc` | runs in frontend AND match (server side) |
| **Server, MP-match** | ✅ | `bb.gsc` hook, replace `clientids_shared.gsc` | the match; **gunfight_mod + the switchmap test live here** |
| **Client, MP-match** | ✅ | `load_shared.csc` hook, replace `radiation_debug.csc` | HOST's client during a match; UI-model API works, `lobby_root` resolves (P6c) but holds none of the frontend children |
| **Client, FRONTEND** | 🪦 **NO** | 3 replace targets tried, all fail/crash (frontend-link-set) | **the map picker + the compat `uimodeldatastruct #hash_109ccf57a41ffd82`** |

▶ **The compat/allowed-map model lives ONLY in the client frontend VM, which is the one VM nothing can
inject into.** Confirmed from BOTH directions: server-frontend VM can't resolve it (P11), client-frontend
VM can't be injected at all (frontend-link-set). So the picker gate is **definitively injection-unreachable**
— CE (client memory) or the `switchmap_load` bypass are the only routes. Not a gap in coverage; a proven wall.

### What this means for mod features (host vs joiner reach)
- **Server GSC (match):** the mod's home. Governs gameplay for everyone (host is the P2P server).
- **Client CSC (match):** injectable, but only on the **HOST's** client. A CSC mod feature (custom client HUD,
  input handling, client VFX) runs for the host only — **joiners run stock CSC**, so client-side mod features
  do NOT reach joiners. Joiners get server effects + stock-clientfield/uimodel updates only (§2 constraint).
- **Client frontend:** unreachable — no menu/picker modding by injection, ever.
▶ Rule of thumb: a mod feature reaches JOINERS iff it is (server GSC gameplay) OR (a value pushed on a
  clientfield/uimodel the STOCK client already handles). Everything else is host-only or impossible.

## 11. Custom loadouts — concrete override (supersedes roadmap #2 sketch)
Gunfight assigns the round weapon via `givecustomloadout()` → `setloadout( game.var_96a8ff4a[ game.var_b6beb735 ] )`:
- `game.var_96a8ff4a` = `array::randomize( bundle.defaultloadouts )` — the shuffled loadout list (game-scope,
  built once at gametype_init).
- `game.var_b6beb735` = current index into the rotation (advances every `gunfightroundsperloadout` rounds).
- Bundle chosen by `getscriptbundle("gunfightloadoutlist").var_d6f55369[bundle_index].loadout`, bundle_index
  from gametype setting `#"hash_3b05ecbff72f1065"` (default → `mp_gunfight_loadout_default`).

**The game already ships themed sets:** `mp_gunfight_loadout_default`, `_melee`, `_snipers`,
`_blueprints`. So three easy tiers of custom-loadout mod feature:
1. **Themed (trivial):** `setgametypesetting(#"hash_3b05ecbff72f1065", N)` to select melee/snipers/etc. from
   the shipped list — one line, no loadout data to author. "Gunfight: Snipers" for free.
2. **Custom array (medium):** at gametype_init, set `game.var_96a8ff4a` = your own array of loadout structs
   (same shape as `defaultloadouts`: talents, primary/secondary + attachments — via `getscriptbundle` on a
   set you point to, or built in script). Overrides the rotation entirely.
3. **Per-round control (medium):** override `level.givecustomloadout` to pick loadouts by any rule (round #,
   team, random each life). ⚠ `onstartgametype` CLEARS `level.givecustomloadout` when `disablecustomcac != 1`
   (custom classes on) — so a loadout-mod must set `disablecustomcac = 1` OR re-install the hook AFTER
   onstartgametype runs. `mod_apply` (on_start) runs at the right time to do the latter.
⚠ All joiner-safe: loadouts are server-assigned (`setloadout`), so joiners get them with nothing installed.

## 12. Host-side client (CSC match VM) capability map
The one injectable client surface (`load_shared.csc` → replace `radiation_debug.csc`, per §10). Runs on the
**HOST's client during a match**. Full capability inventory from the dump:

**Hook** — a CSC payload registers via `system::register` + `callback::*`, and can attach to the whole
client-side match lifecycle: `on_localclient_connect`, `on_localplayer_spawned`, `on_spawned`,
`on_gameplay_started`, `on_start_gametype`, `on_end_game`, `on_killcam_begin`/`on_killcam_end`,
`on_team_change`, `on_weapon_change`, `on_player_killed`, `on_laststand`, `on_ping`. (Same callback module
as server, client side.)

**Read** — `localclientnum` (the client identity, threaded everywhere), `getlocalplayers`,
`getcurrentweapon`, entity state, **server→client clientfields** via `clientfield::get` / the registered
handler (this is how the stock client reacts to server state — §2), and crucially **player INPUT**:
`buttonpressed` / `isbuttonpressed` / `attackbuttonpressed` / `getstance`. Input-reading is what makes
host-side interactive tools work (it's how `gunfight_menu`'s RMB+V navigation reads the pad).

**Present** — `luinotifyevent(#"event")` is the dominant lever (223 stock uses): fire LUI/HUD notifications,
splashes, timers — repurposable stock events include `announcement_event`, `score_event`,
`show_gametype_objective_hint`, `create_prematch_timer`, `round_start`, `show_outcome`, `killstreak_received`,
`waypoint_captured`. Plus `hudelem` HUD elements (87 uses), `playfx`/`playfxontag` world VFX (77),
`objective_add` world markers. UI-model API works here too (P6c: `function_5f72e972(#"lobby_root")`
resolves in this VM — though the frontend children do not).

**⚠ THE BOUNDING CONSTRAINT — host-only.** Injection runs on the HOST's client only; **joiners run stock
CSC**. So every custom client feature here (custom HUD, VFX, overlays, input tools) is **host-only** — a
joiner never sees it. Joiners see only: server-GSC gameplay + their stock client's reactions to stock
clientfields/uimodels the server sets (§2).

**▶ What the CSC match VM is FOR (given host-only):**
- Host-side **dev/debug overlays** — read client state, print diagnostics (the project's P-series probes
  ran here via `iprintlnbold`), visualize spawns/zones while developing.
- Host-side **interactive tools** — input-driven menus like `gunfight_menu` (RMB+V), a map-carry trigger, a
  mod control panel. All host-only, which is fine for a host-operated control surface.
- Host-side **polish the host alone needs** — a custom scoreboard/timer overlay for the host's own view.
**▶ What it is NOT for:** anything a JOINER must see or do. Those MUST be server-GSC + stock clientfields.
This is why the switchmap map change (server GSC) and gunfight_mod (server GSC) are the right layer for the
multiplayer goal, and CSC is reserved for host-operated controls and dev tooling.

## 13. Persistence / save system sweep (P5 mechanics)
The custom-game save is the `mp_custom_game.ddl` root blob. Fields: `gametype` (string32), `gametypesettings`
(the settings struct — `maxplayers`, `timelimit`, `teamcount`, …), `bool[mpmaps]` (43 per-map enable flags),
`gamename`/`gamedescription`/`createtime`/`inuse`/`downloaded`/`loadoutinitialized`. **No single
"selected-map" field.**

### How P5 works (pregame write vs in-match write — the crux)
- An **in-match** write (on_start_gametype) is DISCARDED on return to lobby (measured, Q0.1). Cannot reach a save.
- A **pregame (frontend-VM) write** — `setgametypesetting` in the lobby before launch — lands in the
  **pending-lobby config store**, which is *exactly* what `gametypesettings` serialises. So **Save Custom
  Game captures it.** Proven: `test_frontend_maxp` wrote `maxplayers=8` in the lobby; saved; relaunched
  fully vanilla (no injection, stock DLL, different pid); loaded → **4v4 from the save.** `maxplayers` has
  no menu row, so an 8 is unforgeable.
- Save button is gated on a **UI dirty flag** — you must hand-edit some other row to un-grey Save; the GSC
  write reaches the value store but not that flag.

### Properties (measured)
- **Cloud / account-bound.** Nothing custom-game-shaped in `Documents\...\player\<id>` after a save → no
  local file to offline-edit. Durable (survived 2 game restarts). **Per-account:** a joiner inherits the
  host's live 4v4 (P2P) but their OWN save does NOT capture it — only the host's pregame write did.
- **Workflow:** one pregame-injection setup per *hosting* account bakes a modded save; injection becomes a
  one-time config step, not per-session. Joiners need nothing.

### ▶ Does the save help the MAP problem? NO — the write path is missing.
The blob DOES hold `bool[mpmaps]`, so in principle a saved enable-array could carry map state like it
carries settings. But:
- **No GSC setter for it.** No `setmapenabled`/`selectmap`/`enablemap`/`setgametype` exists, and
  `setgametypesetting` writes INTO `gametypesettings` (offset 0x760) while `bool[mpmaps]` is at ROOT offset
  0x66293, *outside* that struct — structurally unreachable. So there is **no pregame GSC write to capture**
  (unlike maxplayers). The enable array is set only by the client-LUI picker.
- Even with a setter, `bool[mpmaps]` is the enabled/rotation list among ALREADY-COMPATIBLE maps; the compat
  gate (client-LUI) decides what is offered, upstream of it. Enabling ≠ making Miami selectable.
- The save is cloud → no offline craft either.
🪦 **So persistence carries SETTINGS (the 4v4 win) but cannot carry a MAP.** Confirmed closed — consistent
with the whole map problem living in client-LUI, which this route also cannot write.

### Persistence as a mod-expansion lever (settings only)
Any `gametypesettings` value a **frontend-VM** payload writes can be baked into a vanilla-loadable save:
team size, timer, and (per §11) the loadout-bundle index / other Gunfight settings. So a "modded Gunfight
preset" (4v4, 60s, snipers, …) is bakeable **once** per hosting account with zero per-session injection —
the strongest low-exposure delivery the project has. Bounded to `gametypesettings` fields only.

## 14. Scoring / round-flow internals
Gunfight is round-based on the `gametypes/gametype` base (§1). The flow per round and how a match ends:

### Round decision (Gunfight callbacks, all `level.*`-overridable)
- **`ondeadevent(team)`** — a team fully eliminated → the OTHER team wins the round:
  `winningteam = (losingteam == game.attackers) ? game.defenders : game.attackers`, awarded via
  `globallogic::function_a3e3bd39(winningteam, 6)`. Latched by `level.var_c7cce1ff = 1` so it fires once/round.
- **`ononeleftevent(team)`** — last-man-standing event.
- **`ontimelimit()`** — round hit the timer → `overtime()` (capturable zone) on the FIRST expiry, else
  `function_c4915ac()` = **decide by total team health** (allies vs axis sum of `player.health`). The mod's
  timelimit_fix routes here (skips the crashing overtime on off-Gunfight maps).
- **`onendround()`** — post-round: updates scores; advances the loadout rotation every
  `gunfightroundsperloadout` rounds (`game.var_b6beb735++` wrap → `gametype::on_round_switch()`).

### Match-end / limits (globallogic)
- Match ends when `util::hitroundlimit()` OR `util::hitroundwinlimit()` (globallogic.gsc:1987).
- Defaults: `registerroundlimit(0,10)`, `registerroundwinlimit(0,10)`, `registerroundswitch(0,9)`. Both
  limits are **gametype settings**: `roundlimit = clamp(getgametypesetting(#"roundlimit"), min, max)` — so
  `setgametypesetting(#"roundlimit"/#"roundwinlimit", N)` changes them. `level.scoreroundwinbased` flags
  whether score is round-win-based.

### Scoring API (globallogic_score.gsc)
`giveplayerscore(event, player, …)`, `giveteamscore(event, team)`, `giveteamscoreforobjective(team, score)`,
`setpointstowin(points)`/`givepointstowin(points)`, `updatecustomgamewinner(outcome)`, resets
(`resetteamscores`/`resetplayerscores`/`resetallscores`), plus the score-chain/momentum subsystem.

### ▶ Mod-expansion implications (all server-side → joiner-safe)
1. **Tune the match length trivially:** `setgametypesetting(#"roundlimit", N)` / `#"roundwinlimit"` → "first
   to N". Mod-writable like maxplayers/timer, and **bakeable into a save** (§13, they are gametypesettings).
2. **Custom round rules:** override `level.ondeadevent` / `level.onendround` / `level.ononeleftevent`
   (the mod already overrides `level.ontimelimit`/`gettimelimit`) — e.g., different win awards, sudden-death,
   swap the health tiebreak for round-time or kills.
3. **Custom scoring:** `giveteamscore`/`setpointstowin` for bespoke score rules.
4. **Loadout-rotation cadence:** `gunfightroundsperloadout` setting controls how often weapons rotate (§11).
⚠ Same guard as always: override in `mod_apply` (per-round self-heal), and only drive stock clientfields/
uimodels toward joiners (§2). Round/score state is server-authoritative, so joiners get the modded flow free.

## 15. Weapon / attachment / loadout-struct internals (authoring custom loadouts)
A Gunfight loadout is a struct. Fields (from the bundle + `function_44244433`/`function_d98e2783`):

| Field | Meaning |
|---|---|
| `primary` / `secondary` | weapon ref (e.g. `#"<weapon>"`) |
| `primaryattachments` / `secondaryattachments` | array of attachment refs (`#reddot`, `#suppressed2`, `#extclip2`, …) |
| `primarygrenade` / `secondarygrenade` | equipment/grenade refs (lethal/tactical) |
| `talents` | array of perk/talent refs (`#talent_flakjacket`, …) — applied by `givetalents` |
| `bonuscards` / `bonuscard` | wildcards |
| `killstreak` / `killstreaks` | scorestreaks |
| `var_26b5c8ef` / `var_4c0d0c4b` | OPTIONAL blueprint index for primary/secondary (default 0). If `> -1` it resolves a blueprint variant via `function_f62a996b`; if absent/`-1` it builds raw from attachments |

### Apply path (`function_44244433`, per player each round)
`givetalents(loadout.talents, …)` → `function_d98e2783(loadout,"primary")` → `giveweapon`+`givestartammo`+
`switchtoweapon` (fallback `getweapon(#"bare_hands")`) → same for secondary → grenades. So a loadout needs
at minimum a `primary`; everything else is optional.

### The build primitive (script-buildable — no bundle needed)
- **`getweapon( weaponref, attachmentsArray )`** — the one call that turns a ref + attachment-hash array into
  a weapon object. `function_8fdeea14(loadoutattachments)` resolves the ref array to hashes; `#"dw"` in it
  means dual-wield (`weaponref + "_dw"`). Then `self giveweapon( weapon, undefined, … )`.
- `getitemindexfromref` resolves a ref → item index (used for pre-spawn HUD, `function_1f551f49`).

### ▶ Two ways to author custom Gunfight loadouts (both server-side → joiner-safe)
1. **Script-built structs (no data authoring):** in a `gametype_init`/`mod_apply` hook, set
   `game.var_96a8ff4a` to an array of loadout structs you construct in code
   (`{ #primary: <ref>, #primaryattachments: [...], #secondary: <ref>, #talents: [...], #primarygrenade: <ref> }`),
   mirroring the fields above. Overrides the rotation entirely. Use `getweapon(ref, attachments)` semantics.
   ⚠ `onstartgametype` clears `level.givecustomloadout` unless `disablecustomcac == 1` — set that or re-install
   the hook after onstartgametype (mod_apply timing works).
2. **Bundle (data):** author a scriptbundle shaped like `mp_gunfight_loadout_default` (`defaultloadouts: [ … ]`),
   and point `gunfightloadoutlist` at it via the bundle-index gametype setting (§11). The shipped `_melee` /
   `_snipers` / `_blueprints` bundles are ready-made examples/targets.

Since `setloadout`/`giveweapon` are server-side and applied per player, **joiners get the custom loadouts
with nothing installed** — this is a clean, high-value mod feature squarely inside the joiner-safe envelope.

## 16. Spawning / team-assignment — full control for Gunfight on ANY map
The critical system for any-map Gunfight. Good news up front: **it already works on every MP map**, and the
mod has clean hooks for *total* placement control.

### Why Gunfight spawns on any map at all
`main()` registers `spawning::addsupportedspawnpointtype("tdm")` and the entity type is **`mp_tdm_spawn`**
(`gettdmstartspawnname` → `getteamstartspawnname(team, "mp_tdm_spawn")`). TDM is a launch mode, so
**every standard MP map ships `mp_tdm_spawn` team-start entities** — the spawn points Gunfight needs exist
everywhere. `onstartgametype` sets `level.alwaysusestartspawns = 1` (use fixed team start spawns, not scored
dynamic respawns) and `level.graceperiod = 3` (3s spawn protection). This is why the carry/glitch can put
Gunfight on off-Gunfight maps: spawns are satisfied, only the OVERTIME ZONES are missing (§1, guarded by the mod).

### The spawn pipeline (spawning_shared.gsc)
- `add_default_spawnlist(spawnlist)` → pushes onto `level.default_spawn_lists` (the candidate pool).
- `init_teams()` builds `spawnsystem.ispawn_teammask[team]` bitmasks for team filtering.
- `onspawnplayer(predictedspawn)`:
  1. **`level.var_cda5136b`** — a per-player spawn OVERRIDE callback. If defined and it returns true, default
     selection is SKIPPED — the override placed the player. ← **the total-control hook.**
  2. else `spawn = function_89116a1e(predictedspawn)` — scored selection from the spawn lists (influencer
     model: enemies, teammates, recent deaths).
  3. **if no valid `spawn.origin` → `callback::abort_level()`** — the hard spawn-failure abort.
- Gunfight further overrides selection via `spawning::function_32b97d1b(&function_90dee50d)` +
  `function_adbbb58a(&function_c24e290c)` and uses TDM start spawns.

### ▶ Full mod control on any map (all server-side → joiner-safe)
1. **Place players anywhere:** set `level.var_cda5136b` to a callback that positions `self` at chosen
   origins and returns true. Bypasses the map's spawn layout entirely — put Gunfight's 1v1/2v2 spawns at
   close-quarters points on a huge 6v6 map, guarantee valid spawns, avoid bad TDM layouts. This is "full
   control", and it's one `level.*` assignment.
2. **Custom spawn set:** `add_default_spawnlist()` with script-created spawn structs (origins/angles you
   pick) → feeds the scored selector your points instead of (or with) the map's.
3. **Override Gunfight's selectors** (`function_32b97d1b`/`function_adbbb58a`) the same way the mod overrides
   round callbacks, for Gunfight-tuned placement rules.
⚠ **Guard the abort:** the no-valid-origin path calls `abort_level()`. A robust any-map mod should provide
guaranteed spawns (option 1 or 2) so a map with sparse/hostile TDM starts can never hit that abort. This is
the spawn analog of the mod's zones_guard — worth adding for true "Gunfight on every map".

### Team assignment
Teams come from `level.teams` (masked in `init_teams`); size is bounded by `maxplayers`/`com_maxclients`
(§1, §13). Team-change/assignment is `gamemodeismode(1|7)`-aware for custom matches (globallogic). For 4v4+
the ceiling is the session's `com_maxclients` — not a spawn limit.

### 16b. 🐛 The combined-arms / large-variant spawn bug (klaze report, 2026-09-11)
**Symptom:** on SOME carried maps, players spawn out of bounds or in odd spots, "as if using the combined
arms playlist version of the map."

**Root cause (strong hypothesis, evidence-backed):** map scripts branch on `util::get_game_type()` and
toggle map features — spawn sets, bounds/clip volumes, cover props — per mode. Proof of the pattern:
`mp_cartel.gsc:213` keys off `array("dom10v10","koth10v10","war12v12","tdm10v10")` (the large/Combined-Arms
= `war12v12` configs) and toggles map state when the gametype is/ isn't one of them. **Gunfight is in NONE
of these lists**, so on maps whose script only provisions a small-format spawn/bounds config for specific
recognized modes, Gunfight falls into a branch that leaves the LARGE-format state active (or fails to
enable the small-format clips). Gunfight then uses `mp_tdm_spawn_<team>_start` (§16) — which on that
config are positioned for the 12v12 layout → spread out / staging areas / outside the small-format bounds.
It is map-specific ("some maps") because each map's script has its own mode branching.

⚠ Distinct from the overtime-zones crash: that is a CRASH guarded by zones_guard; this is a spawn-POSITION
bug and is currently UNGUARDED. The mod does not touch spawns yet.

**The fix — a spawn override, the spawn analog of zones_guard (server-side → joiner-safe):**
Set `level.var_cda5136b` (§16) to a callback that places `self` at a guaranteed-good origin and returns
true, bypassing the map's spawn selection entirely. This works **regardless of the exact per-map branch** —
it takes placement out of the map's hands. Implementation options, cheapest first:
1. **Central-cluster placement (no per-map data):** gather all `mp_tdm_spawn_*_start` (and/or all spawn
   ents), compute a robust centre (median position, or the tightest cluster), and place the two teams a
   short fixed distance apart there, facing each other. Fixes OOB by construction and suits Gunfight's
   close format. Validate the origin is on the playable mesh before using it.
2. **Per-map known-good origins** for the specific problem maps — reliable, tedious; only needed if (1)'s
   auto-centre lands somewhere bad on a given map.
3. **Filter the existing set:** keep only `mp_tdm_spawn` points within the actual play bounds / near the
   cluster centroid, discard the far large-format outliers, then let stock selection run on the survivors.

▶ Recommended: add a `#spawn_guard` flag to gunfight_mod doing option 1, guarded like zones_guard/
timelimit_fix, re-applied in `mod_apply`. That is the concrete "Gunfight on EVERY map" hardening, and it
directly answers klaze's any-map control goal.

**To pin the exact cause per map (optional):** read the problem map's `.gsc` mode-branch (like
`mp_cartel.gsc`), find what its gametype list gates, and confirm whether Gunfight's `get_game_type()` value
is absent — but the fix above does not require this.

## 17. Perk / talent / gadget model (completes loadout authoring with §15)
How Gunfight applies the non-weapon half of a loadout, via `givetalents(talents, extra1, extra2)`:
- `self cleartalents(); self clearperks();` — wipe first.
- optional two extra talents from the flags (hashed refs) get appended.
- for each entry: `self addtalent( talent.talent + level.game_mode_suffix )` — the loadout's `talents` array
  is `[ { #talent: <talentref> }, … ]` (e.g. `#talent_flakjacket`); `level.game_mode_suffix` selects the
  mode-specific talent variant.
- then `perks = self getloadoutperks( 0 )` → `self setperk( perk )` for each — **perks are engine-derived
  from the loadout**, not hand-listed; talents are what the loadout specifies.
- `perks::monitorgpsjammer()` threads a perk monitor.

**API is thin (mostly builtins):** `addtalent` / `cleartalents` / `clearperks` / `setperk` / `getloadoutperks`
/ `getitemindexfromref`. The script's job is to supply the refs; the engine resolves and applies them.

### ▶ For custom loadouts (extends §15)
A full custom loadout struct is: weapons (`primary`/`secondary` + `*attachments`, §15) + grenades
(`primarygrenade`/`secondarygrenade`) + **`talents: [ { #talent: <ref> }, … ]`** (perks). Build it in script,
set `game.var_96a8ff4a`, and `function_44244433` applies weapons+grenades while `givetalents` applies the
talents/perks — all server-side, so **joiners get the full loadout (weapons, attachments, perks) with
nothing installed**. Gunfight loadouts are weapons+grenades+talents(+optional streak/bonuscard); there is no
separate field-upgrade/gadget key in the Gunfight loadout struct — perks come through talents. `game_mode_
suffix` matters: pass the base talent ref and let the engine add the suffix (givetalents already does), don't
pre-suffix.
