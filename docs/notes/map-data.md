# Per-map data — proper S&D / TDM spawns, and the vehicle + prop list of every map. 2026-09-15

klaze: *"we need to determine how to use proper sd or tdm spawns on each map and get a full list of
vehicles and props on each map so we can use this data to automatically setup matches and pools and
options."* This note is the answer for all three, and what was built on it.

**Status 2026-09-16: BUILT, payload `gunfight_menu.gscc` 287,676 B / 1,808 strings (backups
`pre-groups.bak` 285,137, `pre-namedstarts.bak` 283,546, `pre-mapdata.bak` 269,790). Standoff MEASURED good on the
named starts (§1.4b); Raid / Amerika reads and the S&D spawn-group source in §1.4c. Spawn keys read from the dump and compiled (a probe compiles the field
names to the engine's hashes — §1.3); the STARTS tally, the AUTO family and the per-map Vehicles page
are UNTESTED in-game. The vehicle table (§2) is offline data that matched the one in-game census it
has been checked against (Standoff).**

---

## 1. Spawns — the keys the engine actually reads

### 1.1 The model (hashed spawning scripts, `#namespace spawning`)

`globallogic.gsc:5008` → `spawning::addspawns()` (`hashed/script/script_335d0650ed05d36d.gsc:273`)
builds the engine's spawn lists at every level start:

1. `rawspawns = struct::get_array( "mp_spawn_point", "targetname" )` (`:185`, the default source;
   TDM / Gunfight install `function_90dee50d` = the same set filtered by territory).
2. `function_beae80f9( rawspawns )` (`:194`): a struct is kept only if **a registered type's flag
   field is true** on it (`function_7309b6b3` → `function_82ca1565( spawn, type )`,
   `script_44b0b8420eabacad.gsc:306`). Then it is sorted into the **`start_spawn`** list if its start
   flag is set, `hq` if `.ishqspawn`, else `auto_normal` — grouped by **`.group_index`**, and
   `addspawnpoints( function_3ea24e49( group ), points, listname )` adds each group as a team
   (`function_3ea24e49` swaps 1↔2 when `game.switchedsides`).
3. Legacy entity families (`script_3e196d275a6fb180.gsc:22`): `mp_tdm_spawn_allies_start` /
   `mp_tdm_spawn_axis_start` (start, groups 1 / 2) and `mp_tdm_spawn` (group 0) are read by targetname,
   force-flagged `.tdm = 1`, and fed through the same sorter — **only when "tdm" is registered.**
4. The start picker stock calls at `spawning_shared.gsc:470`, `function_77b7335( team, "start_spawn" )`,
   draws from that `start_spawn` list.

### 1.2 The three fields, and the mode flags

| what | field on the `mp_spawn_point` struct | evidence |
|---|---|---|
| mode flag | `.tdm` `.sd` `.ctf` `.control` `.domination` `.hardpoint` `.ffa` `.base` `.demolition` `.gg` `.infiltration` `.uplink` `.kc` `.frontline` `.ct` `.escort` `.bounty` `.fireteam` `.vip` `.war` `.dropkick` `.spy` … | `function_82ca1565` switch, `script_44b0b8420eabacad.gsc:306-412` |
| team | `.group_index` — 1 = allies, 2 = axis, 0 = either | `#group_index:1` / `2` in `function_f210e027` (`script_3e196d275a6fb180.gsc:35-36`), `function_4277fa85` |
| START flag | field hash **0xa3c53936**, printed by ACTS as **`_human_were`** | `function_beae80f9`: `if ( is_true( spawn._human_were ) ) → "start_spawn"`; `function_361ca7c0`: `spawn._human_were = isstartspawn` |
| HQ flag | `.ishqspawn` (ACTS printed `var_4a7883fa`; cracked with the T8/T9 script hash) | `function_beae80f9` → `"hq"` |

⚠ `_human_were` is a **dictionary alias**, not the Radiant KVP's real name — ACTS names a field by
whatever string in its table hashes to the same 32-bit value (the same mechanism gives
`control_defend_add_a` the alias `registerlast_mapshouldstun` in the same switch). It does not
matter: **the alias compiles back to the same hash**, so `s._human_were` in our source reads exactly
the field the engine reads. Verified: a scratch probe compiled by ACTS decompiles to
`s.var_a3c53936` / `s.var_575417a4` (`group_index`) / `s.var_846c64db` (`sd`), and those three values
are the T8/T9 script hash (Jenkins one-at-a-time, IV `0x4B9ACE2F`, `0x8001 * ((9h) ^ ((9h) >> 11))`)
of the three names. 22,736 guesses at the real name behind 0xa3c53936 (start/spawn/initial/… ×
is/use/has prefixes) found nothing; `ishqspawn` was found by the same method, so the analog is
probably not `isstartspawn` (hash `b8543545`). Unresolved, harmless.

Two of the menu's guessed names were wrong: Domination's flag is `.domination` (not `.dom`) and
Hardpoint's is `.hardpoint` (not `.koth`) — `mod_marker_has` now reads both.

### 1.3 What this means for "proper" spawns

**Authored team starts of a mode = `flag && start && group_index ∈ {1,2}`.** Those are the exact points
stock S&D / TDM open a round on. No geometry, no guessed side field, every one designer-placed — the
thing the Family option approximated with a geometric two-sides search since 2026-09-14.

Hijacked's FLAGS census (`spawn-system.md`, 2026-09-15: `tdm=78 ctf=78 control=78 ffa=86`, nothing
else) now reads cleanly: **that map ships no `sd` set at all**, so S&D markers do not exist on it and
TDM's authored starts are the right fallback — klaze's priority order ("if a map doesn't have sd
spawns we should use tdm spawns") is exactly what the data supports. Standoff's `family=sd sd:none`
is the same fact. Which maps DO ship `sd` starts is what the STARTS tally measures (§1.5).

### 1.4 Built — `gf_spawn_family` value 8 = AUTO, now the DEFAULT

`mod_spawn_build` (SPAWN GUARD block): with a family set, it first collects that family's authored
starts (`mod_family_starts`: flag + start + group) and, when both sides have at least one, arms the
guard with them **as they are** (`mod_anchor_authored` keeps the designer's angles). Only when a side
has nothing authored does the old side-field / geometric search run. Family **AUTO (8)** resolves to
S&D when the map authors S&D starts on both sides, else TDM (`mod_family_auto`); a map with neither
authored resolves to tdm and gets exactly the old geometric default — AUTO cannot do worse than the
2026-09-15 "measured very good" setting. Default changed in `cfg_spec`, `cfg_spawn_family()` and the
app (`Spawns → Spawn family`); the Spawns page has the row *Family: AUTO - authored S&D starts, else
TDM starts*. FAMILIES shows `family=sd sd:40 starts 6/6` when authored starts armed it.

Round-robin, side swap on `game.switchedsides`, the pre-spawn override and FORCE/AUTO guard modes
are unchanged (`spawn-system.md`).

### 1.4b MEASURED — Standoff, first STARTS read (klaze, 2026-09-15 late)

```
STARTS tdm=29/0(0+0+0) dom=16/0(0+0+0) ctf=92/0(0+0+0) control=66/0(0+0+0) dm=37/8(1+1+6) hq=0
FAMILIES ... mp_spawn_point=427 mp_tdm_spawn_team1_start=6 mp_tdm_spawn_team2_start=6 ... family=auto tdm:29 nosides->geo | guard armed 6+6
```

- The keys read (a `.domination` count appears for the first time; `dm` starts exist with group
  1 / 2 / 0) — but on this remaster **no team-mode marker carries the start flag at all**, and the
  engine never reads `mp_tdm_spawn_team1_start` / `team2_start` (`gettdmstartspawnname` has no
  caller). So retail's `start_spawn` list is EMPTY here for tdm: `function_77b7335` returns nothing
  and stock falls to the scored selector for every Gunfight spawn — **that is klaze's "people spawn
  on the wrong side of the map"**, measured from the other end. AUTO correctly resolved to tdm and,
  finding no authored starts, ran the geometric split (`nosides->geo`, 6+6) — the old default.
- **The remasters keep their TDM starts under the BO2 NAMES** — 6 + 6 structs by targetname. Built
  (payload **285,137 B / 1,800 strings**, backup `pre-namedstarts.bak` 283,546): `mod_named_side` maps `mp_tdm_spawn_{allies,team1}_start` → side 1,
  `{axis,team2}_start` → side 2 (and `mp_sd_spawn_attacker/defender`, `mp_dom_spawn_*_start`,
  `mp_ctf_spawn_*`), `mod_family_starts` merges them with the flagged starts, read from the FULL
  pool (a named start carries no mode flag), and a side needs **2+** anchors. Standoff should now
  arm `tdm:29 starts 6/6`. The tally moved to its own **STARTS** feed line (the FAMILIES line was cut
  at `sep=` with it appended) and ends with `| NAMED tdm=6/6 sd=0/0 dom=0/0 ctf=0/0`.

### 1.4c MEASURED — Raid, Amerika, and where S&D really opens (2026-09-16)

```
Raid     STARTS tdm=62/0  dom=31/0 ctf=68/0  control=53/0 dm=74/8(1+1+6)  hq=0 | NAMED tdm=0/0 sd=0/0 dom=0/0 ctf=0/0
Amerika  STARTS tdm=103/0 dom=22/0 ctf=106/0 control=72/0 dm=111/8(1+1+6) hq=0 | NAMED tdm=0/0 sd=0/0 dom=0/0 ctf=0/0
Standoff (285,137, named starts armed): klaze - "spawns on standoff look nice"
```

- Three maps, one remaster with named starts, one without, one T9-native: **no team mode has a
  start-flagged marker anywhere, no map has an `sd` flag anywhere**, and the same 8 start-flagged
  `ffa` markers (1 + 1 + 6 by group) appear on every map — a template, not FFA starts (unresolved,
  harmless). So the engine's `start_spawn` list is empty for tdm on all of them: **retail TDM opens
  on the scored selector**, and Standoff's named 6 + 6 are a remaster leftover the engine ignores.
- **Retail S&D opens elsewhere: spawn GROUPS.** `userspawnselection.gsc:793` reads
  `getentarray( "spawn_group_marker", "classname" )` — one entity per selectable group, `.script_team`
  = `sidea` / `sideb` (→ attackers / defenders via `util::get_team_mapping`, swapped on
  `game.switchedsides`), `.target` = the `groupname` of its point structs
  (`struct::get_array( target, "groupname" )` — a different key from `targetname`, which is why the
  flag census never saw them), `.spawnlist` the engine list it fills. The player picks a group on the
  map at round start (`spawnselectenabled` / `usespawngroups` gametype settings, off under Gunfight)
  and the engine scores a point inside it. The entities and structs are in the map under every
  gametype.
- **Built (payload 287,676 B / 1,808 strings, backup `pre-groups.bak` 285,137):** `mod_spawn_groups`
  reads them; for family S&D `mod_family_starts` returns the **largest group per side** (2+ points)
  before looking at flags / names, so AUTO now resolves to S&D on every map that ships groups and
  arms the guard with a real S&D base a side (`family=sd sd:0 group 6/6`). The STARTS line ends with
  `| GROUPS n=<markers> a=<groups>(<points>,…) b=…` (`u=` = markers whose side/points could not be
  read). ✅ **Run by klaze 2026-09-16 on 287,676: "nice this looks good"** — the spawn-group opening
  works as the S&D source (the STARTS/GROUPS line of that run was not pasted; capture it via
  `mapdata_scan.py` on the next play).

### 1.5 The STARTS tally (its own feed line)

The `STARTS` line (printed under the *spawn families* toggle, after FAMILIES) reads `STARTS tdm=78/12(6+6+0) ctf=78/12(6+6+0) … hq=0 | NAMED tdm=6/6 sd=0/0 dom=0/0 ctf=0/0` — per mode flag
`markers/starts(group1+group2+either)`, modes with no marker omitted. One read per map answers: does
this map author S&D starts (`sd=…/N(a+b)` with a,b ≥ 1)? how many TDM starts a side? Also published
to the app (§3).

**Untried — not ruled out:** the engine-list route. `dev_spawn.gsc:110-118` is Treyarch's own tool
for this: `spawning::clear_spawn_points()` + `spawning::function_c40af6fa()` (reset types) +
`spawning::addsupportedspawnpointtype( flag )` + `spawning::addspawns()` rebuilds the engine lists
from another mode's markers at runtime, after which the stock picker (`function_77b7335`) and the
guard's engine path serve that mode's starts with the engine's own visibility / consumption logic.
It needs `#using script_335d0650ed05d36d;` — ACTS compiles that include (scratch probe
`probe_using.gsc` compiled and decompiled correctly), and `addspawns()` does NOT clear `start_spawn`
(only `auto_normal` / `fallback`), so `clearspawnpoints( "start_spawn" )` (builtin, 0-1 args) must
precede it. Not built: the marker route above needs no engine call and reuses the measured guard.

---

## 2. Vehicles — the per-map list is in the dump after all

`vehicles.md` §3 said the dump cannot say which maps carry which vehicles. **It can**, one directory
over from the scripts: `bocw-source-main/tables/bgcache/<zone>.csv` is the zone's precache list
(`type,name` rows, 362 `vehicle` rows across all zones) and `tables/data/assets/<zone>.csv` is the
full asset manifest (the two agree on every MP zone's vehicle rows). Under MP a map runs with
`core_bootstrap` + `core_common` + `mp_common` + its own zone, so:

**resident vehicle assets on a map = the `vehicle` rows of those four zones.**

Checked against the only in-game census run with the 154-name list so far: Standoff
(`VEHICLES mp_village_rm … M=4[82:chopper gunner, 134:care package heli, 135:vehicle-drop heli,
143:rcxd racing]`) — `mp_village_rm.csv` has **zero** vehicle rows and those four are exactly the
common-zone rows the candidate list contained. ✅ One map; the next census on a vehicle map is the
real test (prediction in §2.2).

### 2.1 The table — `tools/mapdata-extract.py` → `docs/data/map-assets.json`

Every MP map's own vehicle rows (the common four streaks — Chopper Gunner, care-package heli,
vehicle-drop heli, RC-XD — plus AC-130 / attack heli / VTOL / exfil chopper are on every map and
omitted here):

| map | own vehicle assets |
|---|---|
| Armada `mp_black_sea` | jetski (+alt), tactical raft (+alt, grey, grey_pc), PBR gunboat (+alt), 7 manned MG tripods, exfil heli |
| Crossroads `mp_tundra` | T-72 `_sr` / `_alt` / base, snowmobile (+alt), 3 MG tripods, exfil heli, 4 intro-cinematic vehicles |
| Collateral `mp_dune` | FAV light (+alt), motorcycle (+alt), quad `veh_quad_player_wz_pc`, transport truck `_alt` / `_obj_sr`, Hind, exfil heli, 2 intro vehicles |
| Cartel | light truck (base), motorcycle `_alt` / `_slow`, MG tripod, intro vehicle |
| Checkmate `mp_kgb` | APC heavy (+open turret), intro vehicle |
| Diesel `mp_sm_gas_station` | APC heavy (+open turret), motorcycle (+alt) |
| Garrison `mp_tank` | tactical raft grey (+pc), intro tank + intro vehicle |
| Miami | tactical raft grey (+pc), intro vehicle |
| Amerika | intro APC + intro tank |
| The Pines `mp_mall` | intro helicopter + intro APC |
| Moscow / Echelon / Yamantau / Apocalypse / Satellite | one intro-cinematic vehicle each |
| Express | the train `veh_boct_train` |
| every other 6v6 / Gunfight map (Hijacked, Standoff, Nuketown, Raid, Slums, Zoo, Rush, Jungle, Drive-In, WMD, Deprogram, Miami Strike, all `mp_sm_*` but Diesel) | **none** |
| Fireteam `wz_*` (Ruka, Duga, Golova, Sanatorium, Alpine, zoo) | 14-24 each: sedan, FAV, motorcycle, light + transport trucks, T-72, Hind, snowmobile (Alpine), boats (Sanatorium), reinsertion vehicle, exfil heli, cinematic vehicles |

Hashed rows: 81 of 147 resolved by FNV1a64 against vehicle-name vocabulary (`tank_t72`, `hind`,
`apc_heavy`, the tripods, the train, `vehicle_drop`…); the 15 single-map ones are the map's
**pre-match intro cinematic vehicle** (`scriptbundle/scene/cin_mp_<map>_intro_*.json` references
`vehicle#hash_…`), `437293ae239af1ab` is `"exfil_heli"` (`zm_silver_main_quest.gsc:3031`),
`3effd1dd89ee3d36` the Fireteam reinsertion vehicle, `58cc8ce25d32031f` the VIP exfil chopper
(`vip.gsc:125`). Unresolved hashes are still usable — `spawnvehicle( #"hash_…" )` is stock syntax —
so the menu offers them by hash, labelled by their scene. ACTS's community index has none of them.

### 2.2 Built — the Vehicles page is now per map

`veh_master()` carries the union of every MP / Fireteam zone's vehicle rows (75 entries, plain or
hashed, labelled, kind drivable / other); `veh_page_build()` asks `isassetloaded( "vehicle", key )`
for each at menu build and lists only what is resident: drivables on **Vehicles**, streaks / intro
vehicles / turrets on **Vehicles → Other resident vehicles (untested)**. A map with nothing drivable
says so. `veh_spawn` is unchanged (250 u ahead, `makeusable`, the residency safety net).

**Prediction for the next census / page view:** Crossroads lists Tank T-72 (+alt, +base) and
Snowmobile (+alt); Collateral lists FAV (+alt), Motorcycle (+alt), Quad, Transport truck alt /
objective, Hind; Armada lists Jetski, Tactical raft, PBR gunboat; Standoff / Hijacked list nothing
drivable. If a listed vehicle is NOT resident the bgcache model is wrong for that zone — record it.

⚠ Gate 2 of `vehicles.md` (clientfield symmetry for vanilla joiners) is unchanged and untested.
Intro-cinematic vehicles are scene props by construction — expect "spawns but is not enterable".

---

## 3. Props, and the GAME→APP map census

Props have no offline source: the Prop Hunt tables (`gamedata/tables/mp/<map>_ph.csv`,
`static-props.md`) are not in the dump and not in the asset manifests. The manifest gives only the
resident xmodel pool per map (`prop_models` in `map-assets.json`: 214 on ICBM … 2,329 on Miami, the
`p9_/p8_/p7_` families) — the uncurated superset.

So the curated list is read **in-game**, and now filed automatically. `mapdata_publish()` (threaded
from `mod_apply`, every gametype, once per level, 6 s after start) keeps three marked strings alive:

```
GFMAPVEH|<map>|<gametype>|<drivable keys>|<other keys>|END
GFMAPPROP|<map>|tbl=1|rows=13|<model>:<size>,...|END        (first 48 rows; tbl=0 = no table)
GFMAPSPAWN|<map>|<STARTS tally>|<family note>|END
GFMAPDEST|<map>|n=<count>|kinds=<k>|<def>x<count>,...|END       (2026-09-17: the destructibles, REAL def names)
```

`tools/gf-control/mapdata_scan.py` (roster_scan's sibling, same read-only sweep) finds them and
merges each map into `tools/gf-control/mapdata/<map>.json` — vehicles, props (model + size), spawn
keys, gametype, capture time. `--loop` files every map as it gets played; `--show` prints the
database. That JSON + `docs/data/map-assets.json` are the "data to automatically set up matches,
pools and options" — the next step is the consumer (per-map presets in the app / menu).

---

## 4. Test sheet

| # | on | do | read | expect |
|---|---|---|---|---|
| M1 | any 6v6 map | Display → Debug feed → *Spawn families + guard state* | FAMILIES `… STARTS …` | `tdm=N/S(a+b+0)` with a,b ≈ 6; `sd=` present only on a map that ships S&D |
| M2 | same | Spawns page: *Family: AUTO* is current | FAMILIES `family=… starts a/b`, `guard armed a+b` | authored starts armed; every spawn on a designer start, teams on opposite sides, sides swap with the loadout rotation |
| M3 | Standoff / Hijacked | as M2 | `family=tdm tdm:78 starts 6/6` | AUTO fell back to TDM starts (no `sd`) |
| M4 | a map with `sd=` in M1 | as M2 | `family=sd sd:N starts a/b` | S&D's authored bases |
| M5 | Crossroads / Collateral / Armada | Vehicles page | rows | the §2.2 prediction; spawn one, enter it |
| M6 | any | `python tools/gf-control/mapdata_scan.py` with the game up | filed `mapdata/<map>.json` | all four kinds present (`destructibles` since 2026-09-17, [[destructibles]] §8) |
| M7 | Standoff | Vehicles page | "(no drivable vehicle assets on this map)" + Other page: chopper gunner / care package / vehicle drop / RC-XD / exfil chopper |

If M2 places people badly on some map, the row *Family: TDM (measured good)* is the 2026-09-15
default back, one click.

**Untried — not ruled out:** the engine-list route (§1.5); a per-map preset consumer; naming the
unresolved vehicle hashes by spawning them (the label is whatever it turns out to be); reading the
`_ph.csv` tables' remaining columns (scale / offset / rotation) into the props channel.

---

## 4. What is answerable OFFLINE, and what is not. 2026-09-16

A sweep of every offline source, to stop future work probing for things the dump already answers.

| question | offline? | source |
|---|---|---|
| Which **vehicles** are resident per map | ✅ **fully** | `tables/bgcache/<zone>.csv` `vehicle,` rows — see [[vehicles]] §6, all 36 MP maps |
| Which **xmodels / props** are resident per map | ✅ **fully** | `tables/data/assets/<zone>.csv` `xmodel,` rows — see [[static-props]] §5b |
| Which **weapons / characters / fx / destructibles** per map | ✅ | the same two manifests (`weapon,` `character,` `fx,` `destructible,` rows) — ⚠ destructible NAMES are all hashed there; the `DESTRUCT` census / `GFMAPDEST` channel reads the real ones ([[destructibles]] §8) |
| Which **radiant exploders** per map | ✅ **fully** | `tables/bgcache/<zone>.csv` `radiant_exploder,` rows → `tools/exploders-gen.py` → `docs/data/map-exploders.json` + the menu's generated table; hashed, and the API takes the hash ([[destructibles]] §7) |
| Prop **scale / offset / rotation** | ❌ runtime | `gamedata/tables/mp/<map>_ph.csv` is not in the dump; `tablelookuprow` reads it live |
| **Spawn points** — positions, mode flags, group_index, START flag | ❌ **runtime only** | map entity data, compiled into the map `.ff` |

⚠ **Spawns are the one of the three that cannot go offline, and this is why.** `mp_spawn_point`
structs live in the map's compiled entity data. The dump's `radiant/` directory holds a single
988-line `keys.txt` (a Radiant KVP *reference*, mostly campaign/AI keys), and neither `tables/` nor
`gamedata/` contains any `mp_spawn_point` reference. §1 reverse-engineers the *reading* code and the
field names correctly; the *values* per map still need the STARTS tally (§1.5) in game.

That makes the split clean: **assets are a table read, spawns are a probe.** Any future "what does
this map have" question should check the two manifests first — the vehicle census probe was written
before this was known, and the answer it returned (§[[vehicles]] 5) is one row of a table that was
already on disk.
