# BOCW Gunfight — modded Gunfight for Black Ops Cold War private matches

Unlock **any map**, **6v6**, and an **editable round timer** for BOCW's stock Gunfight gametype (T9),
for private/custom lobbies hosted from the owner's machine.

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

| Goal | Lives in | Reachable from GSC? |
|---|---|---|
| Round timer | `timeLimit` gametype setting | **yes** |
| Any map | `gunfight_zone_center` map entities | **yes** (bypass) |
| 6v6 | `com_maxclients`, set at lobby creation | **NO** |

**Timer** — `gunfight.gsc:1137` `gettimelimit()` reads `getgametypesetting(#"timelimit") / 60` and
clamps to `[level.timelimitmin, level.timelimitmax]`. Those come from
`globallogic.gsc:365` → `util::registertimelimit( 0, 1440 )` → `util.gsc:790` sets min 0 / max **1440
MINUTES**. The clamp is not a constraint. The only cap is the menu: `time_limit_seconds.json` declares
20 values but publishes 6 (`"optionscount": 6` → 0/20/30/40/50/60s). **40 is `value4`, the default.**

**Maps** — `onstartgametype()` does `if ( !setupzones() ) { return; }`. `setupzones()` calls
`getzonearray()` → `getentarray( "gunfight_zone_center", "targetname" )` and returns false on
`zones.size == 0`. The 10 "supported" maps are simply where Treyarch placed the flag entities; it was
never an arbitrary whitelist. ⚠ **All four map-entity lookups in the whole gametype are inside the zone
code** (`gunfight.gsc:813, 836, 874, 875`). Bypass them and the per-map dependency count is **zero**.
✅ Spawns are NOT a problem: `gunfight.gsc:77` `spawning::addsupportedspawnpointtype( "tdm" )` — every
MP map ships TDM spawn points.

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

Every iteration reverts by simply not injecting.

---

## 🛑 Confirmed dead ends — do NOT re-research

- **`timelimit_override` dvar** — real, but inside `/# … #/` **dev-only blocks**, stripped from retail.
  Doubly useless: `gunfight.gsc` overrides `level.gettimelimit`, so `default_gettimelimit()` never runs
  for Gunfight anyway.
- **`level.maxteamplayers`** — multiteam-only, see above. Not the 6v6 lever.
- **`com_maxclients` from script** — read-only, 7 refs, zero writes. Not the 6v6 lever either.
- **`xensik/gsc-tool` for T9** — support is marked **WIP**. Not the toolchain.
- **`ProjectDonetsk/T9` (Defcon)** — archived, unmaintained. Its named successor **`xifil/t9-mod` 404s**.
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
| [`AuroraDoesCode/t7-compiler-custom`](https://github.com/AuroraDoesCode/t7-compiler-custom) | **Compiler + injector.** Branch **`dev_csc_inj`**, install `t7c_installer.exe` from Releases |

**Test PC** (secondary): BOCW via Battle.net, throwaway account, the compiler's injector component.

⚠ **Upstream `t7-compiler` is ARCHIVED** — AuroraDoesCode's fork is the live one, and its README credits
*"Ate47 for his work adding ColdWar injection support"*. ate47 is upstream of effectively the whole stack.

⚠ **Do not vendor `bocw-source` into this repo** (618 MB). Pull it to a sibling folder; `.gitignore`
covers the common paths.

Lower-value references: `shiversoftdev/t9-src` (alternate dump, more hashed — cross-check only),
`ModzCentral01/Cold-war-Mods` (working example of the load path; Zombies-weighted),
`ProjectHiNAtyu/T9_BOCW_GSC_Wiki` (notes only, withholds usable files).

⚠ **Every public BOCW GSC workflow primes through a ZOMBIES match** (`scripts/zm_common/load.gsc`).
The MP path is the undocumented one. **Validate it with a hello-world before writing the real mod.**

---

## Test plan

Ordered so the cheapest tests kill the most expensive work.

### Phase 0 — no tools, no exposure (~1 hr) ← **START HERE**
- **T0.1** Count total lobby slots on TDM vs Gunfight. **That number is `com_maxclients`.**
- **T0.2** Walk every Gunfight rules page. Is a time-limit field present? Does it offer 20/30/40/50/60?
  → **If yes, the timer needs no mod at all.**

### Phase 1 — the 6v6 hypothesis (~30 min, 2 people) ← **the gate**
Create the lobby under a **12-player mode** (TDM), confirm 12 slots, then apply the existing
map/mode carry glitch to bring Gunfight *into that lobby* (inverse of the current technique, which
starts from a Gunfight search).
- Slots retained + teams fill past 3v3 → **6v6 solved with no code.** Then start a 12-player match on a
  large map and watch spawns (the `alwaysusestartspawns = 1` question).
- Slots collapse to 6 → `com_maxclients` re-evaluates on mode change; 6v6 is unreachable. Drop it.

### Phase 2 — baseline (~20 min)
Reproduce the five presentation symptoms above on a glitched map. All five matching validates the
code reading end-to-end. Any divergence = re-trace that path before building.

### Phase 3 — the mod (exposure begins here)
Hello-world first, then one change at a time: zones guard → latch flags → `ontimelimit` → timer.
Bots before humans.

---

## Open questions
- **Does `com_maxclients` survive a mode change in a custom lobby?** (Phase 1 — gates all 6v6 work)
- **Is the Gunfight timer field exposed in the rules menu?** (Phase 0 — may moot the timer work)
- **Spawn density at 12 players with `alwaysusestartspawns = 1`.** Gated behind Phase 1
- **MP injection priming sequence** — undocumented; every public guide uses Zombies
