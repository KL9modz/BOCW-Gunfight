# BOCW Gunfight — modded Gunfight for Black Ops Cold War private matches

Unlock **any map**, **larger teams**, and an **editable round timer** for BOCW's stock Gunfight
gametype (T9), for private/custom lobbies hosted from the owner's machine.

**Status: map and timer are CLOSED and confirmed in-game. Teams are at 3v3; the target is 4v4-5v5.**
The working recipe is [[menu-map]] → *PROCEDURE*. Read that before anything else here.

⚠ **Do not record an untried route as a limitation.** "We measured X" belongs in this file. "Therefore
Y is impossible" does not — every such conclusion in this project's history has had to be walked back
(see `README.md`'s retraction notices). Each note carries an **Untried — not ruled out** list; add to
it rather than closing a question.

> This file is the agent operating manual: goal, what has been PROVEN against the decompiled source,
> the confirmed dead ends, and the test plan. It **summarizes and points** — exhaustive per-finding
> depth lives in `docs/notes/`. Keep it present-tense; do not append dated changelog entries.
> ⚠ Every code claim below carries a `file:line` against `ate47/bocw-source`. **Verify before trusting** —
> the dump is a merge across patches.

---

## Ground rules

- **Private matches only.** Never public lobbies, never matchmaking.
- **Platform: Battle.net, secondary PC, throwaway account.** The Steam build stacks **VAC** on top of
  TAC; Battle.net exposes one enforcement system instead of two. ⚠ This does **not** reduce detection
  probability — TAC is identical on both. It reduces blast radius only.
- **No anti-cheat evasion work.** Not hiding the injector, not spoofing, not hardware ban avoidance.
  Out of scope by decision, not by oversight.
- ⚠ **Joiners' exposure is UNKNOWN.** Injected GSC runs host-side and TAC's documented detections are
  local (hooks, debuggers, overlays), so joiners are *expected* to be unexposed. Nobody outside
  Activision can verify server-side telemetry. **Tell participants; it's their accounts.**

## Anti-cheat reality

| Layer | Battle.net | Steam | Notes |
|---|---|---|---|
| **TAC** (Treyarch Anti-Cheat) | yes | yes | **user-mode only, no kernel driver** |
| **VAC** | no | **yes** | permanent, public on profile, non-appealable |
| **Arxan** | yes | yes | EXE obfuscation + runtime API hashing |
| **Ricochet** | **NO** | **NO** | BOCW is absent from the Ricochet title list |

TAC detects API hooks, debugger artifacts, and overlays. Activision bans read *"unauthorized software
and manipulation of game data"*, are account-wide and permanent, and appeals are auto-rejected.

---

## Architecture — what is PROVEN

### Custom games are host-authoritative P2P
Confirmed empirically (host ping 0, all clients connect to host, lobby dies when host leaves) and by
reporting: BOCW reserves dedicated servers for Combined Arms and Fireteam: Dirty Bomb, and runs
standard MP P2P where "that specific multiplayer match is being hosted by one of the players." A
4-player custom game is neither large mode, so **the host runs the gametype logic**. This is the
precondition for everything here.

### The gametype mirrors the BO1 mod's architecture, name for name
`scripts/mp_common/gametypes/gunfight.gsc` (1,306 lines, fully name-resolved) installs
`level.onstartgametype`, `level.givecustomloadout`, `level.onendround`, `level.ononeleftevent`,
`level.ondeadevent`, `level.ontimelimit`, `level.gettimelimit`, plus `globallogic::init()`,
`gameobjects::create_use_object()`, `level.graceperiod`, `level.alwaysusestartspawns`. T9 renamed
almost nothing structurally vs T5 — **BO1 Gunfight experience transfers directly.**

### The three restrictions live in three different layers

| Goal | Lives in | Status |
|---|---|---|
| Round timer | `timeLimit` gametype setting | ✅ **CLOSED** — `timer_override`, 60s, survives a map carry |
| Any map | the lobby's map, overridden at load time | ✅ **CLOSED** — Atian Menu carry, no DLL. [[menu-map]] |
| Team size | `com_maxclients`, fixed at lobby creation | ⚠️ **3v3 working.** Script only ever *reads* the dvar — but `switchmap_load` may reach the layer that sets it, untested: [[atian-menu-source]] |

⚠ The map row said `gunfight_zone_center` map entities through 2026-09-07. **That was wrong** — every
stock Gunfight map reads zero of them, so it distinguishes nothing. See [[gunfight-findings]].

Per-restriction depth: the map dependency and the round-timer link in [[gunfight-findings]], the
enforcement chain and what is actually overridable in [[team-sizes]].

**Timer** — `gunfight.gsc:1137` `gettimelimit()` reads `getgametypesetting(#"timelimit") / 60` and
clamps to `[level.timelimitmin, level.timelimitmax]`. Those come from
`globallogic.gsc:365` → `util::registertimelimit( 0, 1440 )` → `util.gsc:790` sets min 0 / max **1440
MINUTES**. The clamp is not a constraint. The only cap is the menu: `time_limit_seconds.json` declares
20 values but publishes 6 (`"optionscount": 6` → 0/20/30/40/50/60s). **40 is `value4`, the default.**
✅ **The timer is LIVE-WRITABLE mid-round.** `globallogic.gsc` `updategametypedvars()` loops at **0.25s**
and every iteration calls `[[ level.gettimelimit ]]()` (which re-reads `getgametypesetting(#"timelimit")`
fresh) then assigns `level.timelimit` on change. `setgametypesetting()` is writable at runtime —
Gunfight calls it on itself at `gunfight.gsc:104` and `:106`. So
`setgametypesetting( #"timelimit", N )` lands within ~0.25s with **no restart and no pre-match menu
value required.**

**Maps** — `onstartgametype()` does `if ( !setupzones() ) { return; }`. `setupzones()` calls
`getzonearray()` → `getentarray( "gunfight_zone_center", "targetname" )` and returns false on
`zones.size == 0`. The 10 "supported" maps are simply where Treyarch placed the flag entities; it was
never an arbitrary whitelist. ⚠ **All four map-entity lookups in the whole gametype are inside the zone
code** (`gunfight.gsc:813, 836, 874, 875`). Bypass them and the per-map dependency count is **zero**.
✅ Spawns are NOT a problem: `gunfight.gsc:77` `spawning::addsupportedspawnpointtype( "tdm" )` — every
MP map ships TDM spawn points.

🔓 **✅ THE MAP GOAL IS CLOSED.** The **Atian Menu** — an injected GSC mod menu, not stock UI — changes
the map mid-match while the gametype rides along. Confirmed end to end 2026-09-08: **3v3 Gunfight on
Zoo, 60-second rounds, correct HUD, clean lobby return.** The barrier was never `gunfight.gsc`; it is
the playlist layer, and the carry overrides the map at load time underneath it.

⚠ It is **not** free and **not** stock: it is our injection, it does not survive a game restart, and
the carry **resets gametype settings** (a menu-set timer reverts to 30 — which is why
`timer_override` is ON). ⚠ An earlier version of this paragraph claimed the carry used "no GSC, no
DLL, no injector." **Wrong — it is entirely GSC and the injector.** Procedure, the three traps and
the evidence: [[menu-map]].

### Start spawns — script-safe at any team size; the residual risk is engine-side
`usestartspawns()` (`hashed/script/script_44b0b8420eabacad.gsc:504` — the file `gunfight.gsc` pulls in
via `#using script_44b0b8420eabacad`) returns true whenever `level.alwaysusestartspawns` is set, and
Gunfight pins it to 1 at `gunfight.gsc:100`. So **Gunfight uses start spawns for EVERY spawn,
permanently**, not just the first.

`spawning_shared.gsc:295` is the selection, and it has a **fallback**:
```
if ( usestartspawns() ) { spawn = self function_f53e594f(); }
if ( squad_spawn::function_403f2d91( self ) ) { spawn = squad_spawn::getspawnpoint( self ); }
if ( !isdefined( spawn ) ) { spawn = function_99ca1277( self, predictedspawn ); }
```
Exhausted start spawns degrade to normal selection against `level.default_spawn_lists`, which every map
has. **No early return, no failure branch — the script layer cannot break at 12 players.**

⚠ **The residual risk is not readable from the dump.** `function_f53e594f()` →
`function_77b7335( self.team, "start_spawn" )`, which is **called in 3 places and defined nowhere** —
an engine builtin. Whether it returns `undefined` on exhaustion (graceful) or hands back an occupied
point (telefrag) is engine-internal. **Only the Phase 1 live test answers this.**

**6v6** — the chain, and why it is not script-fixable:
1. `team_assignment.gsc:94` `function_efe5a681( team )`:
   `if ( team_players.size >= max_players && max_players != 0 ) return false;`
2. `player_shared.gsc:1300` `function_d36b6597()` — for a 2-team mode (`level.teamcount == 2`) the
   `maxteamplayers` branch fails and it falls to `else if ( level.teamcount > 0 )` → **returns
   `com_maxclients`**.
3. `com_maxclients` has **7 references in the entire dump, all `getdvarint`, zero `setdvar`.**
   Script only ever observes it. It is set by the engine at session creation and bites at *join* time,
   before the gametype script exists.

⚠ **`level.maxteamplayers` is a red herring** — `globallogic.gsc:240` sets it, but
`function_d36b6597()` only consults it when `teamcount == 0` or `max_clients == teamcount`, i.e.
**multiteam only** (`team_assignment.gsc:352`: `if ( level.multiteam && level.maxteamplayers > 0 )`).
It also has **no gamesettings bundle** (no menu row) and is **absent from `custom_games.ddl`**.

### The health decision already exists — do not write it
`gunfight.gsc` `function_c4915ac()` sums each team's `player.health`, `endround()`s the higher side,
and handles the draw. Identical to the BO1 rule. Stock already calls it as the post-overtime fallback;
the mod only needs to reach it one step earlier.

### Why the current glitched maps "work"
Not by design — **by a crashed thread**:
1. Timer expires → `checktimelimit()` (`globallogic.gsc:3276`, called every iteration of the
   `updategametypedvars()` while-loop) invokes `level.ontimelimit`.
2. `ontimelimit()` sets `var_31f5f23 = 1` and threads `overtime()`.
3. `overtime()` does `zone = level.zones[ 0 ]` then dereferences `zone.gameobject`. `level.zones` is
   **undefined** (assigned only at the END of `setupzones()`, past the early return) → **thread dies**,
   *before* its `setgameendtime()` call, so the clock is never extended.
4. Next loop iteration: `timeleft <= 0` still → `ontimelimit()` again → `var_31f5f23 === 1` → falls
   through to `function_c4915ac()` → health decision. Correct outcome, one tick late, via an exception.

⚠ `overtime()`'s own `if ( !isdefined( zone ) )` guard sits **below** the dereference and is unreachable.

### The five presentation bugs, all from that one early return
| Symptom | Skipped work |
|---|---|
| No round-start music from round 2 | `music::setmusicstate( "gunfight_roundstart" )` |
| "No respawns left" HUD never initializes | `function_8cac4c76()` (sets `hudItems.team{1,2}.noRespawnsLeft`) |
| Round-start UI event missing | `luinotifyevent( #"round_start" )` |
| Wrong-mode announcer VO (`controlNoLives`, `controlLowLives`) | `var_a236b703` / `var_61952d8b` left at 0 |
| Lives counter shows wrong number | same — `player_utils.gsc:151` picks `game.lives[]` instead of `level.playerlives[]` |

⚠ **Those two flags are NOT vestigial.** They are one-shot latches Gunfight/SD/VIP set to 1 up front to
**pre-suppress Control-mode mechanics**. Three consumers: `player_killed.gsc:2483` (no-lives VO + HUD +
LUI event), `player_killed.gsc:2503` (low-lives VO), `player_utils.gsc:151` (**selects the lives-HUD data
source**).

---

## The fix — additive hooks, ZERO stock files modified

The injector loads a script into the running VM; it does not replace stock gametype files. It does not
need to, because `level.ontimelimit` is a **function pointer** (`gunfight.gsc:58`). Reassign it — the
same `level.on*` pattern the BO1 mod uses. Shape:

```
on round start:
    if ( !isdefined( level.zones ) ) level.zones = [];
    foreach team: level.var_a236b703[team] = 1; level.var_61952d8b[team] = 1;
    clientfield::set_world_uimodel( "hudItems.team1.noRespawnsLeft", 1 );
    clientfield::set_world_uimodel( "hudItems.team2.noRespawnsLeft", 1 );
    luinotifyevent( #"round_start" );
    level.ontimelimit = &my_health_decision;   // -> function_c4915ac()
```

⚠ The `level.zones = []` guard alone is **not sufficient** — `overtime()` would still index `[0]` on an
empty array and dereference undefined. **The `ontimelimit` reassignment is mandatory, not optional.**

### Skipping `overtime()` is clean — verified, no side effects
Both overtime flags are **gametype-local with no consumers outside `gunfight.gsc`**:

| Flag | Written | Read |
|---|---|---|
| `level.usingextratime` | `:43` (0), `:953` (1, inside `overtime()`) | `:1150` only, in `gettimelimit()` |
| `level.var_31f5f23` | `:917`, `:919` (the latch itself) | `:185` only, gated on `level.tournamentmatch === 1` |

Never calling `overtime()` leaves `usingextratime` at 0 and `gettimelimit()` returns the base limit.
⚠ `control.gsc` and `dem.gsc` declare their own independent variables of the same names — a grep hit
there is NOT a dependency. `function_c4915ac()` routes through the **same `endround()`** the OT capture
path uses.

### ✅ The fix needs NO re-entrancy guard — stock already has one
`checktimelimit()` invokes `level.ontimelimit` on **every** iteration of the 0.25s
`updategametypedvars()` loop while `timeleft <= 0`, so the reassigned handler fires repeatedly. That is
harmless, because `level.var_c7cce1ff` (the round-already-ended latch) is checked at the top of **both**
`function_c4915ac()` (`:1092`) and `endround()` (`:1165`), and set by `endround()` (`:1175`). First call
ends the round and latches; every later call early-returns. **Do not add a guard of your own here** — it
would be redundant and would obscure that stock owns this invariant.

Every iteration reverts by simply not injecting.

---

## 🛑 Measured and settled — do NOT re-research

⚠ **Every entry here is a measurement, not a verdict.** They record *what was checked and what came
back*, so the same ground is not walked twice. None of them says a goal is unreachable — where a route
is merely untried, it belongs in a note's **Untried — not ruled out** list instead.

- **`timelimit_override` dvar** — real, but inside `/# … #/` **dev-only blocks**, stripped from retail.
  Doubly useless: `gunfight.gsc` overrides `level.gettimelimit`, so `default_gettimelimit()` never runs
  for Gunfight anyway.
- **`level.maxteamplayers`** — multiteam-only, see above. Not the 6v6 lever.
- **`com_maxclients` from script** — read-only, 7 refs, zero writes. Not the 6v6 lever either.
- **`xensik/gsc-tool` for T9** — support is marked **WIP**. Not the toolchain.
- **`ProjectDonetsk/T9` (Defcon)** — archived, unmaintained. Its named successor **`xifil/t9-mod` 404s**.
- **A gametype control in the Atian Menu's CW menu tree** — walked in full: four root pages plus the
  `Map` submenu, nothing. ⚠ **But the function exists** — `func_set_gametype()` is defined in the CW
  source and simply never wired in, and its builtins are in `BlackOpsColdWar.exe`. Do not re-walk the
  menu for it; **do** call the builtins directly. [[atian-menu-source]]
- **`scene_model_shared.gsc` as an injection replace target** — leaving a match hung forever on
  "connecting to lobby". Its `class cscenemodel` body is empty but the frontend needs the declaration
  at link time. `clientids_shared.gsc` is the one known-safe replace; test a **lobby return** before
  trusting any other. [[menu-map]]
- **`level.maxteamplayers` for a two-team mode** — both consumers are gated on `multiteam`
  (`teamcount > 2`), and Gunfight is two-team, so it is never enforced. Overwriting it does nothing.
- **BOCW front-end / playlist data** — **not in any public dump.** The UI is compiled LUA; `bocw-source`'s
  `ui/` holds only two graphics cfgs. `arena_playlist_game_modes_maps.json` is almost entirely hashed and
  just points at another bundle by hash. This is where the map list and per-mode `com_maxclients` live,
  and it is the FNV1a64 wall.

---

## Toolchain

**Dev PC** (main machine, no game installed, zero exposure):

| Tool | Purpose |
|---|---|
| [`ate47/bocw-source`](https://github.com/ate47/bocw-source) | **Primary reference.** Name-resolved T9 dump, unknowns under `hashed/`. ~103 MB tar, ~618 MB extracted |
| [`ate47/atian-cod-tools`](https://github.com/ate47/atian-cod-tools) | Decompiler, fastfile/XAsset dumper, CDB/WNI hash storage. Produced the dump above |
| VS Code + `vscode-txgsc-1.0.8.vsix` | Editor, extension ships inside the compiler repo |

⚠ **The compiler and injector are ACTS, not `t7-compiler-custom`.** That fork was the original plan
and this section named it through 2026-09-06; the toolchain actually in use — and the one
`tools/check-gsc.ps1` invokes — is `acts gscc` / `acts gscd` / `acts injectcw`, pinned at v3.3.0.
Commands, the script skeleton and the per-mode hook scripts: [[toolchain]]. Bootstrapping it on a
fresh machine: [[setup-new-pc]].

```powershell
acts gscc script.gsc -g cw -p pc -o script    # compile (VM38)
acts injectcw script.gscc scripts\mp_common\bb.gsc scripts\core_common\clientids_shared.gsc
```

⚠ **MP hook point — `scripts\mp_common\bb.gsc`, MP VM (`mode=mp`).** The injector *hooks* that stock
script rather than overwriting it: when `bb.gsc` runs in the MP VM, the injected script's `autoexec`
runs too. Established against `t7-compiler-custom@4de00c8` and carried into the `injectcw` invocation
above — the hook point is the same for either injector, only the build step differs. The `gsc.conf`
files under `src/` record this hook per project. Survey of the six candidate tool repos and how the
hook point was pinned down: [[pipeline-toolchain-survey]].

**Test PC** (secondary): BOCW via Battle.net, throwaway account, the compiler's injector component.

⚠ **Upstream `t7-compiler` is ARCHIVED** — AuroraDoesCode's fork is the live one, and its README credits
*"Ate47 for his work adding ColdWar injection support"*. ate47 is upstream of effectively the whole stack.

⚠ **Do not vendor `bocw-source` into this repo** (618 MB). Pull it to a sibling folder; `.gitignore`
covers the common paths.

⚠ **`bocw-source` is not the only reference, and it cannot answer everything.** It shows what *stock
script* calls. [`ate47/t8-atian-menu`](https://github.com/ate47/t8-atian-menu) carries
`docs/notes/funcs_cw.csv` — **4,481 Cold War builtins with argument counts and addresses in
`BlackOpsColdWar.exe`**, including functions no stock script uses. Several bear directly on open
questions here: `isvalidgametype`, `addtestclient`, `setteam`, `map_restart`, and three player-count
builtins beyond `com_maxclients`. Survey and staged test plan: [[cw-builtins]]. Its GSC source also
carries the gametype switch: [[atian-menu-source]].

Lower-value references: `shiversoftdev/t9-src` (alternate dump, more hashed — cross-check only),
`ModzCentral01/Cold-war-Mods` (working example of the load path; Zombies-weighted),
`ProjectHiNAtyu/T9_BOCW_GSC_Wiki` (notes only, withholds usable files).

⚠ **Every public BOCW GSC workflow primes through a ZOMBIES match** (`scripts/zm_common/load.gsc`).
The MP path is the undocumented one. **Validate it with a hello-world before writing the real mod.**

---

## DLL-level tooling — a separate track from the GSC work

None of this is needed for the mod. It is here because it shares the process and the anti-cheat
surface, and because one piece of it is directly useful.

- **Forcing gametype/map without the menu glitch** — `acts cwdllgt gunfight mp_moscow`, which needs
  ACTS's `acts-bocw.dll` deployed as `powrprof.dll`. Why LoadLibrary injection cannot work for it:
  [[dll-proxy]].
- **Starting the match once forced** — the cwpatch `discord_game_sdk.dll` binds **F4** to
  `lobbylaunchgame`, plus F6/F7 for `fast_restart` / `full_restart`. That is the missing half of the
  above, and it re-runs a match without leaving the lobby. Different DLL slot, so the two coexist.
- **Unlocks** — cwpatch sets the dvar `loot_fakeall`; `CW_Soft_Unlock.dll` separately forges the
  inventory table. `tools/cw-loader-shim/` merges both into the single usable DLL slot so neither
  needs Process Hacker. Full teardown: [[unlock-dlls]].

⚠ **`BlackOpsColdWar.exe` is encrypted at rest.** Signature scans only match against the decrypted
image in memory, so you cannot check statically whether any of these tools still fits your build —
only an in-game test settles it.

---

## Test plan

Ordered so the cheapest tests kill the most expensive work. The four test layers, including the
offline harness that needs no game running: [[testing]].

Step-by-step protocol, with record sheets and decision tables, for Phases 0–1:
[[phase-0-1-test-protocol]].

Test-box build (headless closet PC, RDP from the dev PC), account setup, and the toolchain mirror:
[[test-pc-setup]]. ⚠ It carries its own gate — **confirm BOCW launches and is watchable over RDP
before Phase 1**, since Phase 2's music/VO/HUD checks depend on it.

### Phase 0 — no tools, no exposure (~1 hr) ← **START HERE**
- **T0.1** Count total lobby slots on TDM vs Gunfight. **That number is `com_maxclients`.**
- **T0.2** Walk every Gunfight rules page. Is a time-limit field present? Does it offer 20/30/40/50/60?
  → **If yes, the timer needs no mod at all.**

### Phase 1 — larger teams (~30 min) ← **the gate**
Target is **4v4-5v5**; the 12-slot TDM lobby over-delivers and is fine.

**▶ Cheapest test first — `switchmap_load`, and it needs no second person.** [[atian-menu-source]]
confirms `func_set_gametype()` exists in the Atian Menu's CW source (dead code, never wired) and that
its builtins are present in `BlackOpsColdWar.exe`. So from inside the **12-slot private TDM lobby**:

```gsc
switchmap_load( util::get_map_name(), "gunfight_3v3" );
wait( 1 );          // load-bearing per ate47; reason unknown
switchmap_switch();
```

then read `src/mp_probe/` probe `1xxxxx`. **`12`** = it reaches the playlist layer and larger teams
are script-reachable. **`8`** = it re-derived the lobby from the gametype, like the map carry does.

⚠ **The map carry is NOT a route to this.** It starts *in a Gunfight lobby* and only overrides the map
at load time, so the slots were fixed before it acts.

**Fallback — the lobby glitch.** Create the lobby under a **12-player mode** (TDM), confirm 12 slots, then apply the existing
map/mode carry glitch to bring Gunfight *into that lobby* (inverse of the current technique, which
starts from a Gunfight search).
- Slots retained + teams fill past 3v3 → **6v6 solved with no code.** Then start a 12-player match on a
  large map and watch spawns (the `alwaysusestartspawns = 1` question).
- Slots collapse to 6 → `com_maxclients` re-evaluates on mode change; 6v6 is unreachable. Drop it.

### Phase 2 — baseline (~20 min)
Reproduce the five presentation symptoms above on a glitched map. All five matching validates the
code reading end-to-end. Any divergence = re-trace that path before building.

### Phase 3 — the mod ✅ DONE 2026-09-08
All four `gunfight_mod` switches verified in-game: 3v3 Gunfight on Zoo, 60-second rounds, a round that
timed out cleanly (the first time that path was ever exercised), correct HUD, clean lobby return.

### Phase 4 — the builtin sweep ← **where the untested work now is**
Seven staged tests, ordered by risk, in [[cw-builtins]]. The first three are **read-only**:
`lobby_probe` (four player counts + an `isvalidgametype` bitmask over candidate Gunfight strings),
`getgametypeenumfromname`, `mapexists`. Then the writes, **one per match**: `map_restart` (may drop the
cwpatch/F7 dependency), `switchmap_load` (the team-size question), `addtestclient` (the real client
ceiling, measured instead of read — and the mechanism "bots before humans" always assumed), `setteam`
(whether 8 clients can be 4v4).

⚠ Test a **lobby return** after every write. That is the check that caught `scene_model_shared`.

---

## Open questions

⚠ **All three require the GAME. None are answerable from the dump** — that work is done. Do not go
looking for them in `bocw-source`; the front end is compiled LUA and the spawn resolver is an engine
builtin (see the two notes above).

- **Does `switchmap_load( map, gametype )` reconfigure the session, or only override the map?** This
  is now *the* team-size question — it decides whether `com_maxclients` can be reached from script at
  all. One probe run answers it: [[atian-menu-source]]. ← **highest value, cheapest**
- **Does `com_maxclients` survive the map/mode carry glitch?** The glitch is a genuine playlist
  reconfiguration where our carry is not. Needs the glitch to work once. [[menu-map]]
- **Does the engine's `function_77b7335` telefrag or return undefined when start spawns run out?**
  (only bites above 3v3; the script layer is proven safe)

⚠ **`com_maxclients` is read-only *from script*** — 7 refs, all `getdvarint`. That is a statement about
the dvar, **not** a statement that team size is unreachable. `switchmap_load` and the lobby glitch both
act on the layer that *sets* it, and neither has been tested.

✅ **Answered.** *Is the Gunfight timer field exposed in the rules menu?* — **yes**, 0/20/30/40/50/60s,
and it is live-settable. But it **does not survive a map carry**, so `timer_override` is required
anyway. *Are the five presentation symptoms real?* — yes, and `presentation: 1` clears them.

### Resolved by tracing, confirmation still wanted
- **MP injection priming sequence** — **RESOLVED** from source + toolchain (`edd94bd` / `4de00c8`),
  superseding the earlier "undocumented; every public guide primes through Zombies". Inject `mode=mp`
  hooking `scripts\mp_common\bb.gsc`; the injected `autoexec` → `system::register` →
  `callback::on_start_gametype(&f)` reassigns `level.ontimelimit` at `globallogic.gsc:5536`, before
  `onstartgametype` (`:5537`) and the timer loop (`:5539`) — the same model stock `bb.gsc` uses. Only a
  confirming hello-world remains: does the hook fire in a *custom Gunfight* lobby. Full path:
  [[mp-load-path]]

### Closed by tracing (do not re-open)
- ~~Spawn density breaks the script at 12 players~~ → **no**, `spawning_shared.gsc:295` has a fallback
- ~~Skipping `overtime()` may desync the round state machine~~ → **no**, both flags are gametype-local
- ~~The `ontimelimit` hook needs a re-entrancy guard~~ → **no**, `level.var_c7cce1ff` already is one
- ~~The timer may need a pre-match menu value~~ → **no**, `setgametypesetting` lands live in ~0.25s
