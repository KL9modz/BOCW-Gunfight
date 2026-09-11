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
