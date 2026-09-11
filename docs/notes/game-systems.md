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
