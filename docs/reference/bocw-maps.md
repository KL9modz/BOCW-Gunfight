# BOCW multiplayer maps — display name ↔ map name, audited 2026-09-12

Every multiplayer map the shipped build can load, with the in-game display name next to the
engine/GSC map name (`sv_mapname`, the string `switchmap_load()` / `LobbySetMap()` take), plus the
variants that exist and **how the game actually produces each variant**. This replaces the guessed
labels the menu carried before this date (`mp_dune` was labelled "Rush", `mp_village_rm` "Village",
`mp_cliffhanger` "Checkmate", `mp_sm_finance` "Diesel" — all wrong).

## How it was verified

Three independent sources had to agree before a row is marked ✅:

1. **The dump's map table.** `tables/data/assets/core_common.csv` lists exactly **36 `mp_*`
   `maptableentry` assets** (+7 `wz_*`, 4 `zm_*`, campaign). `ddl/mp_custom_game.ddl` `enum mpmaps`
   holds the same 36 + the Fireteam maps; its two unresolved members cracked to `mp_russianbase_rm`
   (`hash_2a5c9d82575f9045`) and `mp_jungle_rm` (`hash_4f0163e68a9333ac`) with `tools/crack-hash.py`'s
   algorithm. Every `scripts/mp/mp_*.gsc` in the dump corresponds to one of those 36. **There is no
   37th map.**
2. **The CoD wiki infobox `console` field** (`callofduty.fandom.com`, MediaWiki API, all 42 pages in
   *Category:Call of Duty: Black Ops Cold War Multiplayer Maps*, fetched 2026-09-12). The wiki is
   community-edited, so it is not trusted alone.
3. **Asset fingerprints in the dump** (`tables/data/assets/<map>.csv`): the model families a map loads
   name its setting. `mp_kgb` loads 478 `*plane*`, 290 `*hangar*` and 44 `*chess*` models (Checkmate's
   hangar + mock aircraft; the name is the chess pun) and carries `cin_mp_kgb_intro_bnd` /
   `_hva` — the BND-vs-HVA faction intro only 6v6 maps have (Garrison has the same pair). Gunfight maps
   have no `cin_mp_sm_*` intro at all. `mp_sm_deptstore` is 83 license plates + US civilian cars +
   `mal_*` (mall) props — Showroom is a car showroom **inside The Pines' department store** (wiki
   trivia, and `mp_mall` = The Pines). `mp_sm_market` is `nic_palacio_int` (Nicaraguan palace
   interiors) + tropical foliage — Mansion. `mp_sm_gas_station` is 51 `gas_station` + 181 `car_`
   assets — Diesel. `mp_sm_vault` is 197 `bunker` + 23 `vault` — Gluboko ("deep"). `mp_sm_central` is
   `bunker`/`silo`/`missile`/`icbm` — ICBM. `mp_sm_finance` is `rus_bldg_office` + police fileboxes +
   `sm_fin_bookshelf` — KGB HQ offices. `mp_firebase` is `firebase`/`jungle`/`vietnam` — Deprogram's
   Vietnam firebase fragment. `mp_cliffhanger` carries 42 `yamantau` assets.

Release seasons come from the wiki articles and Activision/Treyarch season posts; they are context,
not load-bearing.

⚠ The dump has **no localisation** — the display names cannot be read out of it, only the codenames
can. That is why the web was needed at all.

## Standard 6v6 maps

| Display name | Map name | Added | Notes |
|---|---|---|---|
| Amerika | `mp_amerika` | Season 6 | |
| Apocalypse | `mp_apocalypse` | Season 2 | |
| Cartel | `mp_cartel` | Launch | also runs Combined Arms on the same layout (turrets shown only for `dom10v10 koth10v10 war12v12 tdm10v10`) |
| Checkmate | `mp_kgb` | Launch | ⚠ the codename is the faction, not the Gunfight map "KGB" |
| Deprogram | `mp_firebase` | Season 6 | |
| Diesel | `mp_sm_gas_station` | Season 3 | 6v6 **and** Gunfight/Face Off (the wiki: "designed for both standard and Gunfight matches") |
| Drive-In | `mp_drivein_rm` | Season 5 | BO1 remaster |
| Echelon | `mp_echelon` | Season 5 | |
| Express | `mp_express_rm` | Season 1 Reloaded | BO2 remaster |
| Garrison | `mp_tank` | Launch | |
| Hijacked | `mp_hijacked_rm` | Season 4 | BO2 remaster. ⚠ broke a session once (2026-09-08) — in a build later shown to garble every string literal (`tools/strip-strhdr.ps1`); the Atian carry loaded it the same day |
| Jungle | `mp_jungle_rm` | 2022-05-06 (post-season free map) | BO1 remaster |
| Miami | `mp_miami` | Launch | night layout; also the Combined Arms version |
| Miami Strike | `mp_miami_strike` | Season 2 Reloaded | **its own map file** — daytime, smaller. The only Strike that is a separate map |
| Moscow | `mp_moscow` | Launch | |
| Nuketown '84 | `mp_nuketown6` | 2020-11-24 | in the Gunfight rotation since Season 1 Reloaded |
| Raid | `mp_raid_rm` | Season 1 | BO2 remaster |
| Rush | `mp_paintball_rm` | Season 4 Reloaded | BO2 remaster |
| Satellite | `mp_satellite` | Launch | also runs Combined Arms on the same layout |
| Slums | `mp_slums_rm` | Season 5 | BO2 remaster |
| Standoff | `mp_village_rm` | Season 3 Reloaded | BO2 remaster (BO2's `mp_village`) |
| The Pines | `mp_mall` | Season 1 | |
| WMD | `mp_russianbase_rm` | 2022-03-17 (post-season free map) | BO1 remaster |
| Yamantau | `mp_cliffhanger` | Season 3 | ⚠ the shipped Atian Menu registers **`mp_clhanger`**, which exists nowhere in the dump (0 hits; `mp_cliffhanger` 552). That menu entry is a typo and cannot load |
| Zoo | `mp_zoo_rm` | Season 5 Reloaded | BO1 remaster. ✅ session-switched to, played, 6v6 filled (2026-09-12) |

## Gunfight / Face Off maps (2v2 · 3v3 · Face Off 6v6)

| Display name | Map name | Added |
|---|---|---|
| Amsterdam | `mp_sm_amsterdam` | Season 4 |
| Game Show | `mp_sm_game_show` | Season 1 |
| Gluboko | `mp_sm_vault` | Season 6 |
| ICBM | `mp_sm_central` | Season 1 |
| KGB | `mp_sm_finance` | Season 1 |
| Mansion | `mp_sm_market` | Season 2 Reloaded |
| Showroom | `mp_sm_deptstore` | Season 5 |
| U-Bahn | `mp_sm_berlin_tunnel` | Season 1 |

Plus Diesel (`mp_sm_gas_station`, above) and Nuketown '84 (`mp_nuketown6`, above), which the stock
Gunfight rotation also uses.

## The large maps and their Strike variants — ONE map file, layout chosen by the GAMETYPE string

"Crossroads" and "Crossroads Strike" are **not two maps**. Each of the three large maps is one map
file whose script picks the 12v12 or the 6v6 boundary at `level_init` by looking at `g_gametype`
(`util::get_game_type()` is `tolower( getdvarstring( #"g_gametype" ) )`). Which string you hand
`switchmap_load( map, gametype )` therefore decides which variant you get.

| Display name (12v12) | Display name (6v6) | Map name | Full layout when `g_gametype` is… | Otherwise |
|---|---|---|---|---|
| Armada | Armada Strike | `mp_black_sea` | one of `koth10v10 ctf vip conf10v10 dom10v10 tdm10v10 war12v12 zsurvival` (`mp_black_sea.gsc:130`) | Strike: `12v12_bounds` ents deleted, `pole_turret`/`zipline_flags` hidden |
| Collateral | Collateral Strike | `mp_dune` | one of `koth10v10 vip conf10v10 dom10v10 tdm10v10 war12v12 zonslaught zonslaught_lotto_loadouts zsurvival` (`mp_dune.gsc:158`) | Strike, same mechanism |
| Crossroads | Crossroads Strike | `mp_tundra` | **inverted test**: Strike when the FIRST `_`-token of the gametype is one of `koth sas spy prop control dm sd conf scream oic dom dropkick gun tdm clean infect` (`mp_tundra.gsc:106`, `function_559de4b9`) | anything else — **including `gunfight`** — gets the full 12v12 map |

**What that means under `gunfight` / `gunfight_3v3`:**

- `mp_black_sea` → **Armada Strike** (the 6v6 layout). The full Armada is unreachable under
  Gunfight: the 12v12 bounds are deleted synchronously at `level_init`, before any injected code runs.
- `mp_dune` → **Collateral Strike**. Same.
- `mp_tundra` → **the full 12v12 Crossroads**, not Crossroads Strike, because "gunfight" is not in
  Crossroads' 6v6 token list. Crossroads Strike under Gunfight would need a layout override:
  `showmiscmodels( "5v5_asset_boundary" )` at `on_start_gametype`, re-targetname the
  `5v5_asset_boundary` and `tundra_oob_clip` entities so the map's own `on_game_playing` (which
  deletes them on the full path) cannot find them, then `hidemiscmodels( "turret_model" )` +
  `exploder::exploder( "fxexp_tundra_6v6" )`. ⚠ Untried. ⚠ And the CLIENT script
  (`mp_tundra.csc:84`) picks its occluders/boundary decals from the same gametype string
  independently, so joiners would still render the 12v12 boundary visuals. Recorded as **untried — not
  ruled out**, not as a menu entry.
- `mp_miami` / `mp_miami_strike` are unaffected — two real maps.
- The **12v12 layouts with a non-Gunfight mode** are one call away: `switchmap_load( "mp_black_sea",
  "tdm10v10" )` should load the full Armada in TDM. ⚠ Whether the engine resolves the `*10v10` /
  `war12v12` gametype strings outside a matchmade playlist is untested (`gametypetableentry` assets
  `teamdeathmatch_10v10`, `domination_10v10`, `hardpoint_10v10`, `kill_confirmed_10v10`, `war_12v12`
  exist in the dump — cracked from the hashed table 2026-09-12 — so the entries are real).

Cartel, Satellite and Miami also host Combined Arms, but on the **same layout** (only vehicles /
turrets differ), so they have no separate 6v6 name.

## Nuketown '84 Holiday / Halloween — ONE map, two dvars

`mp_nuketown6.gsc` (and the client `.csc`) select the theme from two dvars read at `level_init`:

| Variant | Gate | What it does |
|---|---|---|
| Nuketown '84 Holiday | `getdvarint( #"hash_269852f320baca83" )` | `exploder( "fxexp_holiday" )`, `nt6_xmas_props` kept, `set_lighting_state( 1 )`, `skybox_mp_nuketown6_xmas_override` |
| Nuketown '84 Halloween | `getdvarint( #"hash_435b3a7c7c2f2c07" )` | `exploder( "fxexp_halloween" )`, `nt6_halloween_props` kept, `game.musicset = "_nth"`, jack-in-the-box clip kept |

Both dvar names are **unresolved**: 22,092 themed candidates (`nuketown_holiday`, `mp_holiday_event`,
`nt6_halloween`, … × prefixes × suffixes) produced **no hit** with `crack-hash.py`'s algorithm. The
wiki's `mp_nuketown6xmas` is not a map name in the dump (0 hits; the map table has one Nuketown).
⚠ Even with the names, a host-side `setdvar` reaches only the server half: the client script reads
the same dvar locally, so joiners would render stock Nuketown lighting/skybox over holiday props.
The playlist sets it for everyone; a private host cannot. **Not offered in the menu.**

## Fireteam / Multi-team maps (40 players, dedicated-server modes)

| Display name | Map name | Added |
|---|---|---|
| Alpine | `wz_ski_slopes` | Launch |
| Ruka | `wz_forest` | Launch |
| Sanatorium | `wz_sanatorium` | Season 1 |
| Golova | `wz_golova` | Season 2 Reloaded (Fireteam) |
| Duga | `wz_duga` | Season 3 Reloaded (Fireteam) |

`wz_zoo` is Outbreak-only (Zombies) and `wz_doa` is Dead Ops Arcade — both are in the map table, not
MP. `wz_russia` sits in the DDL `mpmaps` enum but has **no map table entry** — cut or renamed; not
loadable. The `wz_*` scripts `#using` only `core_common`, and `fireteam.gsc` registers `tdm` spawn
points alongside `fireteam` ones, so loading one under a 6v6 gametype is not ruled out by the
script layer. ⚠ **Never tried.** Menu entries are flagged untested.

## Not maps

- `mp_common` — the shared MP asset bundle. The shipped Atian Menu lists it; it is not loadable.
- `core_frontend` — the lobby.
- "Face Off", "24/7", "Moshpit" — playlists, not maps.

## Loaded-in-game record (what "verified" means here)

A map is verified when it has been **loaded** by one of this project's routes, not because it is in a
list (`mapexists()` returns 1 for everything — B5).

| Map | Route | Date |
|---|---|---|
| Zoo `mp_zoo_rm` | session switch (`switchmap_load`), lobby followed, 6v6 filled | 2026-09-12 |
| Hijacked `mp_hijacked_rm` | Atian Menu carry from a Mansion lobby | 2026-09-08 |
| Miami `mp_miami` | carry | 2026-09-08 |
| Mansion, KGB, ICBM, Game Show, Nuketown '84 | stock Gunfight lobbies | — |

Provenance for the wiki fetch: `Category:Call_of_Duty:_Black_Ops_Cold_War_Multiplayer_Maps` — 42
members, infobox `|console =` field per page, parsed 2026-09-12.
