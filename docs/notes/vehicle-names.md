# Vehicle names — our label vs the GSC asset vs Cold War's name vs the real vehicle (2026-09-25)

klaze, 2026-09-25: *"what is the real name of drone squad pha's name? tell me every vehicle in our spawner,
the name we wrote, vs the name in gsc, vs in game name, vs the IRL name (research online)"* and *"most of the
vehicle "alt"s dont seem different"*. The research ran in session bocw-84; no code was changed.

**Sources:**
- **F** = the Call of Duty wiki (callofduty.fandom.com, read through its API).
- **IGCD** = igcd.net's Cold War vehicle list (https://www.igcd.net/game.php?id=1000015141).
- The T9 dump (`bocw-source-main`) and Atian's name lists.

`?` means inferred, not confirmed. **Campaign-only** means the asset is in no MP zone, so it never spawns in MP (`isassetloaded` hides it).

## PHA's "Drone squad" (`#"hash_444804d03bdda785"`)

**It is `flying_camera_drone`, a camera-drone vehicle, not a drone squad.**
- **The name is proven:** fnv1a63("flying_camera_drone") = 444804d03bdda785.
- **It's loaded on every MP map:** it's in the `core_common` zone table.
- **No shipping script spawns it.** The dev-only devgui (`mp_common/devgui.gsc:1489-1520`, dvar `scr_drone_camera`) spawns a `drone_camera` vehicle 150 u above player 0 and seats them in it.
- **Its sibling, PHA's "Drone squad 2" (`hash_3effd1dd89ee3d36`), is `flying_camera_drone_wz_escape_infil`.** Fireteam spawns it on every death as an invisible reinsertion camera (`hashed/script/script_718a1198c1574851.gsc:228-243`). `wz_escape` is the codename of Black Ops 4 Blackout's Alcatraz map.
- **Where the name came from:** Atian's Black Ops 4 list calls the hash "Drone squadron (Old model)" (`enum_vehicles.gsc:137`), and PHA shortened that. Black Ops 4 had a **Drone Squad** scorestreak (`drone_squadron`: three SMG drones). Cold War does not; its `drone_squadron` stats entries are Black Ops 4 leftovers.
- **Real-world counterpart:** none. PHA's "Drone squad 3" (`hash_3a28e8bcf12e1d74`) is only in `zm_common` and did not crack.

## All 73 spawner rows (`veh_master()`)

| # | Our label | GSC name | In-game name | IRL name | Notes |
|---|---|---|---|---|---|
|1|Light buggy (FAV)|vehicle_t9_mil_fav_light|FAV (Fireteam, Outbreak)|1982 Chenowth FAV (IGCD)|Outbreak spawner uses it|
|2|Light buggy (FAV) alt|vehicle_t9_mil_fav_light_alt|FAV|Chenowth FAV|see alts|
|3|Heavy buggy (FAV)|veh_mil_ru_fav_heavy|—|?|campaign-only|
|4|Motorcycle|vehicle_motorcycle_mil_us_offroad|Dirt Bike|Hercules K 125 BW (IGCD)|MP Cartel, Fireteam, Outbreak (F)|
|5|Motorcycle alt|…offroad_alt|Dirt Bike|Hercules K 125 BW||
|6|Motorcycle (slow)|hash_4b89aa566bff8383 = …offroad_slow|Dirt Bike variant|Hercules K 125 BW|Cartel only|
|7|Quad / ATV|veh_quad_player_wz_pc|ATV (props in the Collateral Strike intro, F)|Bombardier Outlander? (IGCD)|Black Ops 4 ATV models; Collateral only|
|8|Snowmobile|vehicle_t9_mil_snowmobile|Snowmobile|unknown make|Crossroads, Alpine|
|9|Snowmobile alt|…snowmobile_alt|Snowmobile|unknown||
|10|Snowmobile (single seat)|…snowmobile_alt_single_seat|—|unknown|campaign-only|
|11|Sedan|vehicle_t9_civ_ru_sedan_80s_player|Sedan|GAZ-24 Volga (IGCD)|Fireteam / Outbreak|
|12|Sedan alt|…sedan_80s_player_alt|Sedan|GAZ-24 Volga|maybe another livery|
|13|Sedan (BO4 midsize)|hash_985b7e40ee02aa2 = vehicle_t8_soviet_civ_sedan_midsize|—|? Soviet sedan|campaign-only|
|14|Light truck|vehicle_t9_mil_ru_truck_light_player|Light Truck|1980 UAZ-469 (IGCD)||
|15|Light truck alt|…truck_light_player_alt|Light Truck|UAZ-469||
|16|Light truck (base)|hash_1bdb534f1e8e23f5 = vehicle_t9_mil_ru_truck_light|— (map / intro UAZ)|UAZ-469|PHA "Jeep"|
|17|Transport truck|vehicle_t9_mil_ru_truck_transport_player|Cargo Truck|1977 Ural-4320 (IGCD)||
|18|Transport truck alt|…transport_player_alt|Cargo Truck|Ural-4320|also Collateral|
|19|Transport truck (objective)|…transport_player_obj_sr|Cargo Truck (Outbreak objective)|Ural-4320|`_sr` = Outbreak|
|20|Tank T-72|vehicle_t9_mil_ru_tank_t72_sr|T-72 (Outbreak copy)|T-72A (IGCD)||
|21|Tank T-72 alt|…tank_t72_alt|T-72 (Crossroads Combined Arms / Fireteam)|T-72A||
|22|Tank T-72 (base)|hash_28d512b739c9d9c1 = vehicle_t9_mil_ru_tank_t72|T-72|T-72A||
|23|APC (heavy)|hash_1a60a087a340574b = vehicle_t9_mil_ru_apc_heavy|— (prop: Checkmate, Diesel)|BTR-80?|IGCD: unplayable BTR-80|
|24|APC (heavy, open turret)|hash_7c54a264a26cb1eb|— (prop)|BTR-80?|its own open-turret model|
|25|Hind gunship|hash_6595f5efe62a4ec = vehicle_t9_mil_ru_heli_gunship_hind|Hind (Fireteam, Outbreak)|Mil Mi-24 (F, IGCD)||
|26|Armada heli (campaign)|vehicle_t9_mil_us_helicopter_large_cp_armada_player|campaign player helicopter (Fracture Jaw?)|UH-1 Huey family?|campaign-only|
|27|Jetski|vehicle_t9_mil_boat_jetski|Wakerunner|Yamaha WaveRunner (IGCD)||
|28|Jetski alt|…jetski_alt|Wakerunner|Yamaha WaveRunner||
|29|Tactical raft|vehicle_t9_mil_boat_tactical_raft|Raft|inflatable boat (Zodiac-style?)||
|30|Tactical raft alt|…tactical_raft_alt|Raft|same||
|31|Tactical raft (grey)|vehicle_boct_mil_boat_tactical_raft_gry_pc|— (prop raft)|inflatable (Zodiac Mark II?)||
|32|PBR gunboat|vehicle_t9_mil_us_boat_pgb_double_gun|Gunboat|Uniflite PBR (IGCD)||
|33|PBR gunboat alt|…pgb_double_gun_alt|Gunboat|Uniflite PBR||
|34|Chopper Gunner|veh_t9_mil_us_helicopter_large_chopper_gunner|Chopper Gunner (scorestreak)|Huey family? (IGCD: Bell 412)||
|35|Care package heli|vehicle_t9_mil_helicopter_care_package|Care Package helicopter|CH-47 Chinook (F, IGCD)||
|36|Vehicle-drop heli|hash_4209c5ff3b969c7a|— (vehicle supply drop)|Soviet transport heli? (IGCD "Ka-92")||
|37|RC-XD|vehicle_t9_rcxd_racing|RC-XD (scorestreak)|RC car, International Harvester Scout body (IGCD)||
|38|RC-XD alt|hash_7dd2944ddf7cc7e9|—|RC car?|probably Black Ops 4's RC-XD: a different asset|
|39|Exfil helicopter (Fireteam)|hash_437293ae239af1ab|Zombies exfil helicopter|MH-6 Little Bird? (F)|label wrong: Zombies, not Fireteam|
|40|AC-130 gunship|veh_t8_ac130_gunship_mp|Gunship (scorestreak)|AC-130||
|41|Attack helicopter|veh_t8_helicopter_gunship_mp|Attack Helicopter (scorestreak)?|Bell AH-1 Cobra (F, IGCD)||
|42|Attack helicopter guard|veh_t8_helicopter_gunship_mp_guard|helicopter_guard (Fireteam pickup)|?||
|43|VTOL Forger|vehicle_t9_mil_ru_air_vtol_forger|VTOL Escort (scorestreak)|Yakovlev Yak-38 "Forger" (F, IGCD)||
|44|Strafe run plane|vehicle_straferun_mp|Strafe Run (scorestreak)|2× Su-25 "Frogfoot" (F, IGCD)||
|45|Air transport (intro)|vehicle_t9_mil_air_transport_hpc_intro|Fireteam intro transport plane|?||
|46|Air transport (infiltration, BO4)|vehicle_t8_mil_air_transport_infiltration|—|?|campaign-only|
|47|Mounted MG tripod|hash_536eec4bf6424551|manned MG turret|?||
|48|Express train|hash_5477254cf96259f4 = veh_boct_train|Express bullet train (map hazard)|fictional bullet train||
|49|Intro vehicle (Checkmate / Satellite)|hash_60868aaa45d05ffe|intro buggies|dune buggy / FAV?||
|50|Intro tank (Garrison / Amerika)|hash_550d303ee2de9a65 = vehicle_t9_mil_us_tank_m1a1|M1A1 Abrams (intros)|M1A1 Abrams||
|51|Intro vehicle (Garrison)|hash_4dfaa11717f3881|Garrison intro helicopter|Soviet transport heli?||
|52|Intro vehicle (Miami)|hash_1e00d92ee0b1bf4c|Miami intro van|Chevrolet Step Van? (IGCD)||
|53|Intro vehicle (Moscow cia)|hash_4c21aec4081d030d|Moscow intro van|Barkas B1000? (IGCD)||
|54|Intro vehicle (Moscow kgb)|hash_62d385495a2ba813|Moscow KGB-intro helicopter|MH-6 Little Bird||
|55|Intro helicopter (The Pines)|hash_13c60e71eef46ebb|The Pines intro helicopter|Soviet transport heli?||
|56|Intro APC (The Pines)|hash_5405b8cdc93df2b4|The Pines intro APC|BTR-40?||
|57|Intro APC (Amerika)|hash_15e59336c36ee995|Amerika intro APC|BTR-40?||
|58|Intro vehicle (Echelon)|hash_7c74af55b6caaaf5|Echelon intro helicopter|Huey family?||
|59|Intro vehicle (Yamantau)|hash_c07fec522db452c|Yamantau intro helicopter|Soviet transport heli?||
|60|Intro vehicle (Apocalypse)|hash_1c5963188cf189df|Apocalypse intro vehicle|MH-6 Little Bird?||
|61|Intro vehicle (Cartel)|hash_20966d639ebe6604 = vehicle_t9_mil_us_helicopter_large_mp_cartel_gunship|Cartel intro gunship helicopter|Huey gunship?|new crack|
|62|Intro vehicle (Collateral cia)|hash_4bfd80fe09072db3|Collateral intro vehicle|?||
|63|Intro vehicle (Collateral kgb)|hash_3efa223f4a0bffcd|Collateral intro ATVs|ATV?||
|64|Intro vehicle (Crossroads kgb)|hash_1f5c1aa7b1348d33 = vehicle_t9_mil_truck_mobile_icbm|Crossroads convoy ICBM launcher|MAZ-7917 (IGCD)?||
|65|Intro vehicle (Crossroads)|hash_3463002d802c1a98|Crossroads convoy vehicle|?||
|66|Intro vehicle (Crossroads kgb 2)|hash_581bb1b0fa4a3139|Crossroads intro UAZ (snow)|UAZ-469||
|67|Intro vehicle (Crossroads cia)|hash_61b8f8f61f4b9ce7|ICBM launcher, snow (both intros)|as row 64||
|68|AI helicopter|heli_ai_mp|— (leftover asset)|?|Atian "Helicopter (BO3)"|
|69|Drone squad - PHA's name|hash_444804d03bdda785 = flying_camera_drone|— (camera drone)|none|see above|
|70|Helicopter (Sanatorium)|hash_17e868e0ebf3c1d6 = vehicle_t9_mil_us_helicopter_light|Little Bird|MH-6 Little Bird||
|71|Fireteam reinsertion vehicle|hash_3effd1dd89ee3d36 = flying_camera_drone_wz_escape_infil|Fireteam respawn camera|none|correct|
|72|Napalm strike plane, hpc intro|hash_3d2bbfdb89093d91|Fireteam intro escort VTOL|Yak-38 Forger?|label wrong|
|73|Outro helicopter (hpc/sl)|hash_631691623ad368bd|Fireteam outro helicopter|Huey family?||

## The `_alt` rows

**The dump shows no data difference.**
- There is no `_alt` tuning bundle, model, or scriptbundle.
- No script names an `_alt`: Outbreak's spawner names only the base and `_sr` copies.

**Where they appear:** the `_alt` names sit in the MP maps' zone string tables.
- Collateral: FAV, dirt bike, cargo truck.
- Crossroads: T-72, snowmobile.
- Cartel / Diesel: dirt bike.

**Reading:** `_alt` looks like the copy the MP modes place (Combined Arms / Fireteam), and the base is the copy Zombies Outbreak spawns. The model and tuning are the same. That matches klaze's *"they dont seem different"* and the earlier in-game look at the RC-XD alt.

| Rows | Verdict |
|---|---|
| 1/2 FAV, 8/9 Snowmobile, 14/15 Light Truck, 27/28 Wakerunner, 29/30 Raft, 32/33 Gunboat | duplicates |
| 4/5 Dirt Bike, 17/18 Cargo Truck | duplicates; the alt also loads on Cartel / Collateral, so keep the alt (keeping alts never loses a map) |
| 11/12 Sedan | may be two liveries (the zones carry black + police sedans): check in game |
| 20/21/22 T-72 | three copies of one tank (`_sr` Outbreak, `_alt` Crossroads, base) |
| 23/24 APC, 41/42 helicopters, 38 vs 37 RC-XD | really different, so keep |

## Labels that are wrong or misleading (suggested)

- **Wrong identity:**
  - 69 → Camera drone
  - 39 → Zombies exfil helicopter
  - 72 → Fireteam intro escort VTOL
  - 38 → RC-XD (other model)
  - 42 → Heavy attack chopper (Fireteam)
  - 26 → Huey (Fracture Jaw, campaign)
- **Use the in-game names:**
  - Dirt Bike (4-6)
  - Cargo Truck (17-19)
  - Wakerunner (27/28)
  - VTOL Escort (43)
  - Gunship (40)
  - Strafe Run (44)
  - Little Bird (70)
- **Campaign-only, never in MP:** rows 3, 10, 13, 26, 46. `vehicles.md` §7's "resident, worth adding" for 10 / 46 counted campaign zones, so it is wrong.

## Applied 2026-09-25 (klaze: "clean up the spawner")

`veh_master()` went from 73 to **58 rows** (LIVE 8F4E2F2F). The panel's `Catalog.cs` Vehicles table was
regenerated from it; the app spawns by index, and `CatalogTests` checks the two match row for row. The row
numbers in the tables above are the OLD 73-row numbers.

- **Removed, duplicates:** the base copy of FAV, Dirt Bike, Snowmobile, Light Truck, Cargo Truck, Wakerunner, Raft,
  Gunboat, and T-72 base + `_sr`. The `_alt` copy stays; it loads on the same maps or more.
- **Removed, campaign-only:** heavy FAV, single-seat snowmobile, BO4 sedan, Armada helicopter, BO4 air transport.
- **Relabelled:** Dirt Bike, Dirt Bike (slow), Cargo Truck, Cargo Truck (objective), Wakerunner, VTOL Escort,
  Gunship, Strafe Run, Little Bird, Camera drone, Zombies exfil helicopter, Fireteam intro escort VTOL,
  RC-XD (other model), Heavy attack chopper (Fireteam), Light buggy (FAV), Snowmobile, Sedan 2, Light truck,
  Light truck (map UAZ), Tank T-72, Tactical raft, PBR gunboat.
- Kept: the Sedan pair (maybe two liveries, still unchecked in game), APC pair, both helicopters, both RC-XDs.

## MEASURED 2026-09-25 — the definitions read from the live game

klaze asked what separates the two sedans, the cargo trucks, the Zombies exfil helicopter vs the Little Bird and
the Chopper Gunner vs the outro helicopter. All of them were resident in his Sanatorium match (03:0x), so the
VehicleDefs were read from memory, read-only.

**Method:** the vehicle pool is XAsset pool 76 (`xassetpools_cw.csv`: 0x1C18-byte items). Its header is at
`exe+0x1273c9f0 + 76*0x20` (pointer, item size, count), and each item starts with its name hash (fnv1a63). An item's
asset references are found by matching every qword against the item addresses of the xmodel / fx / scriptbundle /
destructibledef / vehiclesounddef / vehiclefxdef / rumble pools. Offsets seen:
- +0x1200: sound def
- +0x1338: body model
- +0x1348: wreck model
- +0x1350: a third model (big helicopters)
- +0x0fb8 up: passenger-seat anim bundles, 0x58 apart
- +0x1aa0: custom-settings bundle
- +0x1af8: destructible def

The field NAMES of the plain numbers are unknown: no file here has the T9 VehicleDef layout.

| Pair | Identical | Different |
|---|---|---|
| Sedan vs Sedan 2 | all 45 references: body `veh_t9_civ_ru_sedan_80s_dest_blk` (black), wreck, sounds, effects, 3 passenger seats, settings bundle, destructible parts | ~12 numbers, e.g. +0x504 = 1000 vs 150 |
| Cargo Truck (`_alt`) vs Cargo Truck (objective, `_obj_sr`) | 27 of 28 references (wreck, sounds, effects, bundle, destructible) | the BODY model (hash_5d384f53b57530eb vs hash_48d577077fdc9286); +0x4e4 / +0x4e8 / +0x4f4 = 668.8 / 792 / 176 vs 774.4 / 880 / 211.2 (11-20 % higher); +0x504 = 100 vs 720 |
| Outbreak base vs `_alt` (sedan, light truck, transport truck) | all references | the same field set every time: +0x28 (set on base, 0 on alt), +0x504 (1000 / 1000 / 720 vs 150 / 160 / 100), +0x15a8, +0x15b0 (0 vs 2), +0x1838 / +0x183c, +0x1924 (0.5 / 0.5 / 1.0 vs 0.08) |
| Little Bird vs Zombies exfil helicopter | 8 of 13 references (wreck `veh_t9_mil_us_helicopter_light_dead_b`, 5 passenger seats, rumbles) | body `..._light_destructible` vs `..._light_zm_sv_intro`; its own sound def; bundle `helicopter_light_bundle_settings` vs `..._zm`; breakable parts (destructible def) only on the Little Bird; 2 extra effects on the exfil; 45 numbers (a block at +0x940-+0xa5c is set on the Little Bird and 0 on the exfil) |
| Chopper Gunner vs Outro helicopter (hpc/sl) | sound def, settings bundle (hash_65522b02cd22f91a), rumbles | body / wreck / third model `veh_t9_mil_us_helicopter_large_chopper_gunner_mp` vs `vehicle_t9_mil_us_helicopter_large_mp_intro`; 3 extra effects + a different one on the gunner; 17 numbers, incl. ~10 id-like entries set only on the gunner (+0x264-+0x318, +0x1300, +0x1458-+0x1460) |

What each one is, from stock script:
- The Zombies exfil heli is the Zombies exfil event's default ride (`level.var_4bc7192d`) and Die Maschine's quest heli.
- The outro heli's model is force-streamed for the Fireteam intro (`script_187a917a302208ec.csc`).
- The objective truck is spawned by Outbreak's Transport objective, which drives it along vehicle nodes carrying
  the rocket script model; stock swaps a damaged objective truck back to this type.

**Untried, not ruled out:** what +0x504 and the other numbers control. A shoot test (same gun, count hits on
both sedans) and a timed drive (both cargo trucks) would name them.

## Applied 2026-09-25, second pass (klaze, after the live read above)

58 -> **53 rows** (Catalog.cs regenerated; CatalogTests keeps the two in step):
- Sedan: the base copy went. Sedan 2 (`_alt`, the MP copy, like every other kept vehicle) is now "Sedan". The two
  shared every reference; their unnamed numbers are not health (+0x504 reads Hind 1000, Little Bird 60, RC-XD 200).
- Cargo Truck (objective) went; the standard Cargo Truck stays.
- Fireteam reinsertion vehicle went. It is the camera drone: the same model (hash_629e1b95760bedfb) and bundle,
  plus 2 effects and ~12 numbers.
- Fireteam intro escort VTOL and Outro helicopter (hpc/sl) went (cutscene vehicles).
- "Zombies exfil helicopter" is now **Little Bird Exfil**.

## Sedan looks: what can be controlled (read 2026-09-25, not built)

- **Store skins:** no builtin sets a vehicle's skin. The store's vehicle skins (the `veh_t9_civ_ru_sedan_80s_mpx_*`
  and `..._assembly_mpx_*` mtx items) are vehicle *assemblies* the engine applies. Script only READS
  `vehicle.vehicleassembly` (`player_vehicle.gsc:1212`, `battletracks.gsc:178`).
- **Models loaded on Sanatorium** (live xmodel pool):
  - bodies: `veh_t9_civ_ru_sedan_80s_dest` (plain), `..._dest_blk` (black, the one both sedan defs use),
    `..._dest_police`, `..._dest_police_lit`, `..._dest_police_wet_lit`;
  - attachments: `..._police_siren_dest_attach` (+ `_lit`, `_wet_lit`), `..._police_decals`, `..._logos`,
    `..._decal_dirt`, `..._dest_attach`.
  Only Sanatorium was read; other maps may load a different set.
- **Routes:**
  - **Attach** the siren bar and decals to the spawned sedan. Stock attaches models to a sedan
    (campaign escape car, `script_4fdb32cc1d125464.gsc:489`).
  - **Swap the body** with `setmodel`. Stock never does that to a drivable vehicle: untested.
  - `setvehicletype` swaps the def, but both sedan defs use the same model, so nothing visible changes.

## Applied 2026-09-25, third pass (klaze): names

- Renamed:
  - RC-XD (other model) -> **RC-XD ALT**
  - Gunship -> **AC-130 Gunship**
  - Heavy attack chopper (Fireteam) -> **Heavy attack chopper** (the only "(Fireteam)" label)
  - Air transport (intro) -> **Cargo plane**
  - Hind gunship -> **Mi-24 Hind**
  - Tank T-72 -> **T-72 Tank**
  - Care package heli -> **CH-47 Chinook**
- Still 53 rows. Vehicle mode (`veh_mode_add`) keeps its own lower-case labels.
- **Cracked:** `hash_437293ae239af1ab` = **`vehicle_t9_mil_us_helicopter_light_sv_intro`** (fnv1a63 exact; the Little
  Bird Exfil). Its body model is `veh_t9_mil_us_helicopter_light_zm_sv_intro` (live read above).
- ⚠ **A label is part of the air test.** `veh_key_text` = the row's plain name + its label. A hashed key with an
  unknown plain name only counted as an aircraft through the word "helicopter" in its OLD label. The pass-1 / pass-2
  names "Little Bird" and "Little Bird Exfil" made both spawn as ground vehicles, with "Hold to enter" instead of "fly"
  (live 8F4E2F2F-E8DF3AE6, never reported in game). Fixed: both rows now carry their real plain names
  (`vehicle_t9_mil_us_helicopter_light`, `..._light_sv_intro`), so the label no longer matters for them. A
  scratchpad check compared every row's air flag / radius / prompt verb with the committed 73-row list; all 53 match.
  (vprompt_text also keys "Hold to control" on "rc-xd" in the label - bocw-57.)

## Correction: a livery switcher already exists (VEHICLE LIVERIES, built 2026-09-21, not measured on a drivable vehicle)

"Next livery" (menu row), LB / RB in the vehicle placer, app verb `vehlivery next|prev`. It swaps the live vehicle's
model with `setmodel + setenemymodel` from a curated family list, gated by `isassetloaded`. Store skins follow the
OCCUPANT (klaze measured 09-21: the vehicle takes the equipped skin of whoever sits in it). On Sanatorium the
sedan family list has ONE resident entry, `veh_t9_civ_ru_sedan_80s_logos`. Going by its name that is a logo piece,
not a body. Meanwhile the resident bodies (`..._dest`, `..._dest_police`, `..._dest_police_lit`,
`..._dest_police_wet_lit`) are not in the list; the spawned sedan's own model is `..._dest_blk`.

## Applied 2026-09-25, fourth pass (klaze: one row per vehicle on every map; the app filters by map)

**Coverage check** (every copy of each duplicated vehicle, including the ones removed earlier, vs the copy kept;
zones from `docs/data/vehicle-assets.json`): every earlier removal kept full map coverage, except two families.
- Light truck: the kept `_player_alt` misses Cartel. Fix: fallback `hash_1bdb534f1e8e23f5` (`vehicle_t9_mil_ru_truck_light`).
- Tactical raft: the kept `_alt` misses Miami and Garrison. Fix: fallback `vehicle_boct_mil_boat_tactical_raft_gry_pc`.

**Fallback copies:**
- `veh_def( m, key, label, kind, text, alts )`: `veh_row_key( e )` returns the key if loaded, else the first loaded alt.
- `veh_row_of( type )` finds a row by its key or any alt. It serves kind, label and the air-test text.
- The spawner list, the census list and the app's `vehspawn <index>` all spawn the resolved copy.
- The two merged rows went; 51 rows.

**Intro rows renamed to what they are.** Six more names cracked (fnv1a63 exact):
- `4dfaa11717f3881` = `vehicle_t9_mil_ru_heli_transport_mp_tank_intro`
- `13c60e71eef46ebb` = `..._mp_mall_intro`
- `c07fec522db452c` = `..._mp_cliffhanger_intro`
- `1e00d92ee0b1bf4c` = `vehicle_t9_civ_us_van_miami_intro`
- `581bb1b0fa4a3139` = `vehicle_t9_mil_ru_truck_light_mp_tundra_intro_snow`
- `61b8f8f61f4b9ce7` = `vehicle_t9_mil_truck_mobile_icbm_snow`

Still unknown: the Checkmate / Satellite buggy, the Moscow van, both intro APCs, Apocalypse, Collateral cia and the
Crossroads convoy vehicle. Every cracked row now carries its plain name, which changes the air test for six intro
helicopters: Garrison, The Pines, Yamantau, Echelon, Cartel, Moscow. All are aircraft now (clear-air spawn, "fly"
prompt), and five of them used to spawn on the ground. The Pines' radius went 320 -> 600 (transport class).

**App (item 1):** `VehicleDef.Maps` (Catalog.cs, generated from the zone tables over the row's copies; null = every
map). ToolsVM lists only rows `On( current map )`, and everything with no match running. The pickers re-read only
when the map changes.

## Applied 2026-09-25, passes 5-9 (klaze, live in game on Apocalypse / Collateral)

- **Apocalypse intro = a Little Bird** (klaze). The live read agrees: the Little Bird's 5 helicopter seats, sound def,
  wreck `veh_t9_mil_us_helicopter_light_dead_b` and `helicopter_light_bundle_settings`, with its own body
  (hash_735908f1cb030512). The hashed name did not crack, so the air test also accepts "little bird" in the label.
- **Capitals:**
  - "Vehicle-drop heli" -> **Transport Helicopter**;
  - every "helicopter" -> "Helicopter", then **Title Case for every label** (acronyms kept).
- **"(Map Intro)" dropped.** Under klaze's rule "1 for each map", intro copies another row already covers went:
  - Echelon's helicopter: klaze says it is a Chopper Gunner.
  - The Garrison / The Pines / Yamantau transport helicopters: the zone tables show armed-gear / gear / winter
    bodies of the same Soviet transport airframe as the every-map Transport Helicopter.
- **Same-name intro copies merged with fallbacks:**
  - **Little Bird** = the Sanatorium one + the Moscow and Apocalypse copies;
  - **Van** = Miami + Moscow;
  - **APC** = The Pines (body `veh_t9_mil_us_apc_arv_mp_mall_intro`) + Amerika.
- **Collateral's unknown intro vehicle = an "8x8 Truck"** (klaze's in-game screenshot: a tan 8x8 cargo truck).
- **43 rows.** A per-map check found no map that shows the same label twice. The CatalogTests parse floor went 50 -> 30.
- Still unnamed by asset: the Checkmate / Satellite buggy, the Moscow van, both APCs, the ATVs, the Crossroads convoy vehicle.

- **Transport Helicopter** prefers the The Pines / Yamantau intro copies where they load (klaze: "the best version"); the vehicle-drop copy everywhere else (LIVE 17682820). `mp_sm_gas_station` = Diesel (supports every mode incl. Gunfight - klaze).

## AI Helicopter (`heli_ai_mp`), read 2026-09-25

- **Loads:** `core_common` (every map).
- **No script in the dump spawns it.** Its only mentions are client-side lookup tables:
  - a `heli_comlink_light` effect (`killstreaks/helicopter_shared.csc:298`, `killstreaks/mp/helicopter.csc:278`);
  - an empty sound case (`helicopter_sounds_shared.csc:413`).
- **"comlink" is the Attack Helicopter streak's code name:** CW's Attack Helicopter (`veh_t8_helicopter_gunship_mp`, AH-1 Cobra model) and the Heavy Attack Chopper both use `helicopter_comlink_bundle_settings`.
- **The live def is bare:**
  - a sound def (hash_4cf37bb05a19f37d) and two models (hash_5143084b2aa13fae, hash_584d18d0b1abc996), all uncracked;
  - no seats, no settings bundle, no wreck, no destructible;
  - +0x504 = 30.
- Reading: a leftover attack-helicopter vehicle type from the older Black Ops killstreak code, not a CW mode's vehicle.
- **klaze 2026-09-25: it is the Wraith from Black Ops 3** (seen in game) - kept, renamed "Wraith" (LIVE A8D9FDD2).

## Wraith pilot (built 2026-09-25, LIVE 66C8CE4F, NOT run)

klaze: *"could we fly it somehow? noclip? attach to invisible helicopter?"* -> *"try 1 with 3 as fallback"*. The
Wraith has no seat, so it is flown from a **chase camera**: a script_origin 480 u behind and 180 u above it, the pilot
`playerlinkto`'d to it the way fly mode does. The pilot is hidden, has no weapon and takes no damage.
- **Autopilot (option 1):** every frame, `setgoal( ahead along view + stick, 0 )`, plus `setspeed` 60 / 110 (sprint)
  and `settargetyaw( view yaw )`. Jump / crouch = up / down. Letting go = `setgoal( here, 1 )` (hover).
- **Direct (option 3, the fallback):** `veh linkto( mover )`, and the mover is moved like fly mode
  (`cfg_fly_speed` / `cfg_fly_fast`).
- `gf_wraith_mode`: 0 = autopilot that switches to direct when the Wraith moves under 40 u in 1.5 s of held stick;
  1 = autopilot only; 2 = direct only. App: SANDBOX -> VEHICLE MODE -> "Wraith flight".
- **Enter:** walk up + hold interact (`usebuttonpressed()` or `kb_use()`, 3 x 0.2 s in vprompt_think), or
  Vehicles > Enter vehicle. **Leave:** hold interact 0.5 s (after letting go once), or Vehicles > Leave vehicle.
  Death, the Wraith gone, fly mode or game_ended also land the pilot (`tp_floor` under the Wraith).
- menu_think's close-on-entering-a-vehicle and fly_bind_think's skip now also count `self.gf_wraith_on` (bocw-57).
- **Unmeasured:** whether `setgoal` moves a spawned heli_ai_mp; whether a vehicle can be `linkto`'d; whether the
  engine's own hold-Use does anything on it; the camera offset.
- **MEASURED 2026-09-25 (klaze, 66C8CE4F):** "i think it started on autopilot but then it switched later" - the autopilot (`setgoal`) DOES move a spawned heli_ai_mp. The late switch was the stall check firing on a working autopilot (a wall / the ground / the height limit). Fixed in LIVE 0A82A2EB: the fallback is only armed until the autopilot has moved it 250 u that flight.
- **Automatic for every seatless aircraft (klaze "yes make it automatic", LIVE 7074B5B2):** `pilot_is(v)` = menu-spawned + an air key + no seat (`veh_has_seat`: veh_free_seat's seat-exists test, cached per vehicle). Aircraft with a seat keep the engine's hold-to-enter. The chase camera scales with veh_air_radius. Stock flies its planes through the same `setspeed` / `setgoal` (ac130_shared.gsc:1153-1413, straferun.gsc:1053). Which aircraft are seatless, and how a plane handles the autopilot, is unmeasured.
- **MEASURED 2026-09-25 (klaze on 7074B5B2): "now pressing F doesnt do anything. on the wraith either".** The seat-table test (veh_free_seat's `function_dcef0ba1` / `function_defc91b2`) reports a seat on the Wraith that a player cannot use, so it is not a "player can enter" test. LIVE 9CAC902A decides by TRYING instead. At the vehicle prompt: the Wraith starts after a 0.6 s hold; any other spawned aircraft needs a 1.2 s hold with you still on foot (the engine's own hold-to-enter did not seat you). Enter vehicle: `usevehicle`, then the pilot if you are not seated 0.5 s later.
- **F vs the menu (klaze, LIVE F9F49DC1):** F keeps the game's own uses: gunner / passenger seats (the Chopper Gunner's gunner seat takes a press), RC-XD control, pickups. The pilot starts from F only after a 1.2 s hold with you still on foot. The menu's Enter vehicle is the dependable way to pilot. The prompt's reach now includes an aircraft you AIM at within 600 u (aim-only, so an F hold meant for a pickup or door is never taken), and the private hint trigger sits on the player when the ride is more than 200 u away.
