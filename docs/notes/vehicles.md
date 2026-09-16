# MP vehicles — what is spawnable, and what gates it per map. Dump research 2026-09-15

Goal: support **every spawnable vehicle, per map type**. This note is the static half, read entirely
out of `bocw-source-main` (T9 dump). **Nothing here is measured in-game yet** — every claim is a
source reference, and the one question that actually decides the feature (per-map asset residency)
is *not answerable from the dump at all*. The probe that answers it is specified at the bottom.

**Status 2026-09-15: PROBE RAN (§5).** Run 1: the hashed-type form of `isassetloaded` is VOID (yes to
everything); by the plain-string form **one** of the 105 `veh_t9_*` model names IS a resident vehicle
asset on `mp_sm_gas_station` — the namespaces share names. Runs 2–3 crashed the game at link time —
our bug (two prop.gsc *script* functions called as builtins; the validator hole that let it through
is fixed). v4 RAN CLEAN: the resident vehicle is the Chopper Gunner streak vehicle by name. Two spawn paths identified, one of them dead in stock MP; 30
vehicle behaviour types enumerated; the gate is asset residency + clientfield symmetry.**

---

## 1. There are two spawn paths, and stock MP starts neither by default

### Path A — map-baked spawners (`mp_common/vehicle.gsc`)

`vehiclemainthread()` (`mp_common/vehicle.gsc:104`) drives the whole stock MP vehicle system off
**map entity data**:

```gsc
spawn_nodes   = struct::get_array( "veh_spawn_point", "targetname" );
veh_name      = spawn_node.script_noteworthy;          // which vehicle
time_interval = int( spawn_node.script_parameters );   // respawn interval
thread vehiclespawnthread( veh_name, spawn_node.origin, spawn_node.angles, time_interval );
```

and `vehiclespawnthread` (`:124`) then needs a **second** baked entity:

```gsc
veh_spawner = getent( veh_name + "_spawner", "targetname" );
vehicle     = veh_spawner spawnfromspawner( veh_name, 1, 1, 1 );
```

So Path A requires *both* a `veh_spawn_point` struct **and** a `<veh_name>_spawner` entity compiled
into the map. Same shape as BO1's `mp_wager_spawn`: map data, not script.

> ⚠ **`initvehiclemap()` IS NEVER CALLED.** `grep -rn "initvehiclemap" .` over the **entire
> 566 MB dump** returns exactly one line: its own definition at `mp_common/vehicle.gsc:86`.
> `veh_spawn_point` likewise appears once, at `:104`, inside the function that entry point threads.
> So no stock MP gametype, map script or system in the dump activates this. Either a map-side `.gsc`
> compiled into a `.ff` calls it (not visible here), or it is legacy. **Do not assume Path A runs on
> any map** until something in-game proves it.

### Path B — direct, map-independent

`vehicle_shared.gsc` exposes a plain spawn with no map entity involved:

```gsc
function spawn( *modelname, targetname, vehicletype, origin, angles )   // :2849
{
    return spawnvehicle( vehicletype, origin, angles, targetname );
}
```

and the one that also seats the caller — the primitive this feature wants:

```gsc
function function_fa8ced6e( v_origin, v_angles, str_vehicle )           // :5523
{
    if ( self isinvehicle() ) { return self getvehicleoccupied(); }
    var_80730518 = spawnvehicle( str_vehicle, v_origin, v_angles, "player_spawned_vehicle" );
    var_80730518 usevehicle( self, 0 );                                  // seat 0 = driver
    return var_80730518;
}
```

`spawnvehicle` is overloaded — 4 args (`vehicle_shared:2855`), 6 (`killstreak_vehicle.gsc:213`, adds
owner), 9 (`scene_vehicle_shared.gsc:44`). `usevehicle( player, seat )` is confirmed at 8 stock call
sites including `bots/bot.gsc:1249`, so **bots can be seated too**.

`player_is_driver()` (`mp_common/vehicle.gsc:60`) defines driver as `getoccupantseat( player ) == 0`.

---

## 2. The 30 vehicle behaviour types

A spawned vehicle asset is bound to its behaviour by **type string**, via
`vehicle::add_main_callback( "<type>", &fn )`. Full set registered anywhere in the dump:

| Class | Types |
|---|---|
| **Drivable, ground** | `player_atv` `player_btr40` `player_fav_light` `hemtt_wz` `player_motorcycle_2wd` `player_sedan` `player_snowmobile` `player_tank` `player_truck_transport` `player_uaz` `player_van` |
| **Drivable, air** | `player_vtol` `helicopter_heavy` `player_large_helicopter_armada` `air_vehicle1` |
| **Drivable, water** | `player_jetski` `player_pbr` `tactical_raft_wz` |
| **Turrets** | `auto_turret` `emp_turret` `microwave_turret` |
| **Drones / streaks** | `raps` `rcxd` (+ `vehicle_t9_rcxd_racing{,_mq,_zm}`) `repulsor_drone` `siegebot` `wasp` `veh_flak_drone_mp` `xbot` |

⚠ **Read the mode suffixes as scope hints, not guarantees.** `hemtt_wz` / `tactical_raft_wz`
are Warzone-named, `veh_flak_drone_mp` is MP-named, `..._zm` is Zombies. A `_wz` type may still be
resident on an MP map — that is exactly what the probe must settle, not something to infer.

Backing scripts live in `scripts/core_common/vehicles/` (43 files, `.gsc` + `.csc` pairs).

⚠⚠ **A TYPE IS NOT A SPAWN ARGUMENT.** Dispatch happens on **`self.vehicletype`**
(`globallogic_vehicle.gsc:37`, fallback `self.scriptvehicletype` at `:41`) — a field *inside the
spawned asset*. So `player_tank` is a behaviour key the asset declares, **not** a name you can hand
to `spawnvehicle`. Do not build a candidate list out of this table.

### The candidate-list problem — ⚠ THIS IS THE ACTUAL BLOCKER

`spawnvehicle` takes a **`vehicle#` asset name**, and that namespace is nearly absent from the dump:

- **`veh_t9_*` is the WRONG namespace.** All 342 of those strings are **xmodels** — they appear as
  `"model#veh_t9_mil_ru_tank_t72_turret_dead"` in `scriptbundle/vehiclecustomsettings/`. An earlier
  revision of this note listed them as "MP-plausible candidates". **Disregard that.** (Note also
  `veh_t8_mil_atv_recon_*` in the ATV bundle — BO4 assets are reused, so even the prefix is not a
  reliable family marker.)
- **Only 68 unique `vehicle#hash_*` references exist in the whole dump, and every one is in
  `scriptbundle/scene/`** — campaign cutscene vehicles. Zero MP vehicles.
- **The one field that feeds `spawnvehicle` for streaks is stripped.** `killstreak_vehicle.gsc:213`
  spawns `bundle.ksvehicle`; every `ksvehicle` value in the dump is the bare string `"vehicle#"`
  with nothing after the prefix.

**Cracking was attempted and failed: 0 of 68** against a 439-name pool (all `veh_t8/t9_*` model names
plus every `vehiclecustomsettings` basename, with and without the `_settings` / `_bundle_settings`
suffixes). Algorithm verified first against the project's own known crack —
`maxsquadplayers` → `hash_3a4691a853585241`, exact, FNV1a64 & MASK63.

**The ACTS community hash index is now set up, tested, and does NOT contain them — 0 of 68.**
Runbook, because this capability is reusable project-wide and took a few wrong turns to reach:

```
acts download_hash_index      # 51 MB of .cdb, incl. hashes-scr-bocw.cdb
acts merge_hash_index         # REQUIRED -> package_index/merged_hash.acef (44 MB)
acts lookup <bare hex hash>   # NOT hash_xxx, NOT #"...", NOT vehicle#... - bare hex only
```

⚠ **`merge_hash_index` is the step that makes `lookup` work**, and nothing says so — before it,
every lookup returns `can't be find`, which reads identically to a genuine miss.
⚠ **`hashreplacer` never matched anything** in any syntax tried, including the verified control.
Use `lookup`.
⚠ Control the tool before trusting a miss: `lookup 6bada5168620c5fe` must print `=default`
(hash of the literal string `default`). With that control passing, **all 68 vehicle hashes miss** —
so the community index genuinely lacks them. The project's own `maxsquadplayers` crack also misses,
which is consistent: it was cracked here, not contributed upstream.

Prefix compression is why a plain `grep` over the `.cdb` looks empty: the header is `PNDB`, strings
follow in plaintext but share prefixes with their predecessor (`$default`, `+actionslot 1`, then
bare `2`, `3`, `4`), so only the first entry of a run greps.

### ⚠ But cracking is the WRONG TARGET — guesses are testable in-game for free

`isassetloaded` takes a name and lets the **engine** resolve it. A guessed name that is wrong simply
returns false. So the probe does **not** need cracked names, and does not need the fastfile
extraction to *start*: it can test **guessed** names directly, and a GSC loop can test hundreds in a
frame when the output is only a count.

That makes the 342 `veh_t9_*` model names useful again — not as known vehicle assets (they are not),
but as **342 free guesses** at naming parity between the `model#` and `vehicle#` namespaces. Parity
is plausible and costs nothing to test.

**If any count comes back non-zero, parity holds and the list is essentially solved.** If every
count is zero, parity is dead and the authoritative list must come from the shipped fastfiles (ACTS
reads them; needs a machine with BOCW installed — a **one-time offline extraction, not a match**).

Tuning bundles in `scriptbundle/vehiclecustomsettings/` (45 files) remain the best human-readable
index of what Treyarch built — `tank_t9_mil_ru_t72_settings`, `tank_t9_mil_us_m1a1_settings`,
`player_ground_vehicle_settings_{atv,btr40,hemtt,snowmobile,uaz,van,...}` — but they are **settings,
not spawn names**, and the mapping between the two is exactly what is missing.

---

## 3. What gates a vehicle on a given map — TWO gates, not one

### Gate 1 — asset residency, and the runtime test for it

`spawnvehicle()` needs the vehicle asset **loaded in the current map's zone**. The dump cannot answer
which maps carry which vehicles: map `.ff` contents are not in it.

🪦 **RETRACTED 2026-09-15 — it can, one directory over from the scripts.** `tables/bgcache/<zone>.csv` is
each zone's precache list and `tables/data/assets/<zone>.csv` its full manifest; a map's resident vehicle
assets = the `vehicle` rows of core_bootstrap + core_common + mp_common + the map's zone, and that
reproduces Standoff's census exactly. The per-map table and the Vehicles page built from it: [[map-data]]. But the engine can, and **stock
already performs this exact check**:

```gsc
if ( isassetloaded( "vehicle", _s.model ) )      // scene_vehicle_shared.gsc:43
{
    _e = spawnvehicle( _s.model, ... );
}
```

`isassetloaded` is confirmed in the dump (also used with `"aitype"`, `"xanim"`, `"stringtable"`), and
`check-gsc` stage 4 already resolves it as a real T9 builtin. **This is the mechanism the feature
should be built on**: probe per map, offer only what is resident. Strictly better than a hardcoded
map-to-vehicle table, which would rot on every content patch.

### Gate 2 — clientfield symmetry. THE ONE THAT CAN KILL IT

`player_tank.gsc:24` shows a drivable is **not** just a spawn:

```gsc
function private preinit()
{
    vehicle::add_main_callback( "player_tank", &function_c0f1d81b );
    clientfield::register( "scriptmover", "tank_deathfx",      1, 1, "int" );
    clientfield::register( "vehicle",     "tank_shellejectfx", 1, 1, "int" );
}
```

Cross-reference [[game-systems]]: **clientfields are symmetric** — a vanilla joiner runs stock `.csc`
and registers only the fields that build registers. So vehicle FX work for a joiner **iff the stock
vehicle system is registered in the running mode on that map**. A server-only mod cannot add a
clientfield a vanilla client will read.

This splits the feature cleanly, and the split should drive test order:

- **System already registered in MP** — spawning is plausibly a pure server-side call, joiner-safe.
- **System not registered** — the vehicle may spawn and drive but render wrong for un-modded clients
  (missing death FX, no shell eject, no light toggle). Same failure class the project already
  documented for clientfields.

Note `mp_common/vehicle.gsc` registers a system (`system::register( #"vehicle", ... )`, `:14`) whose
`preinit` is **empty** (`:22`). So the MP vehicle *system* exists on every MP map while its *map
loop* (Path A) never starts. Understand that asymmetry before designing around it.

---

## 4. Next steps — in dependency order

**Step 1 — the PARITY probe. Buildable now, no fastfile extraction needed.** Per §2 the engine
resolves guessed names for free, so the first probe's job is to answer *one* question: is there any
overlap between the `model#` names we have and the `vehicle#` names we need? Emit three counts —
the 342 `veh_t9_*` guesses, the 30 behaviour-type strings, the 68 known scene hashes — plus the
controls. **Any non-zero count essentially solves the candidate list.** All-zero sends us to the
fastfiles, and that is worth knowing before spending a game session on extraction.

⚠ This reverses an earlier revision of this note, which said the probe was blocked on step 1.
It is not: guessing is free, and the parity question is cheaper to answer than the extraction.

**Step 2 — the residency probe (only meaningful once step 1 finds a live namespace).** Design
constraints are already fixed by
`mp_probe`: retail renders **numbers only**, read off-screen at 5s spacing. So residency must be
emitted as counts and bitmasks, not names. A **16-bit mask fits the 5-digit value field exactly**, so
16 candidates per emitted number. Include a **call-form control** (both `#"vehicle"` and `"vehicle"`
as the type argument, plus one deliberately bogus asset that must read 0) — without it, an all-zero
result cannot distinguish "nothing resident" from "wrong call form".

**Step 3 — run it. The first TWO maps are the valuable ones**, because they settle the
common-set-vs-per-map question cheaply: identical resident count *and* fingerprint across two
different maps means a common/mode zone and the matrix collapses to a handful of runs; divergence
means it is genuinely per-map and the full pass is 40 maps.

**Step 4 — the remaining runtime questions:**

1. **Per map, which vehicle assets are resident?** Loop the step-1 candidate list through
   `isassetloaded( <type>, <asset> )` at `on_start_gametype` and emit counts + bitmasks. Read-only,
   no spawn, no risk — and it produces the map-to-vehicle table the feature is defined by.
   ⚠ Candidates are passed as **hashes, not names** (`#"hash_..."`, the form
   `getgametypesetting( #"hash_3a4691a853585241" )` already proves works), so residency is testable
   even for assets whose names are never recovered. Names are needed only for menu *labels*.
2. **Does a resident asset actually spawn and drive** via `spawnvehicle` + `usevehicle( player, 0 )`
   on a non-Combined-Arms map?
3. **Does a vanilla joiner see it correctly** (Gate 2), or only the modded host?
4. **Is Path A reachable at all** — does any MP map ship `veh_spawn_point` structs?
   `struct::get_array( "veh_spawn_point", "targetname" ).size` answers that in one line.

Q1 and Q4 are both read-only census calls and belong in the **same** probe, modelled on the existing
`src/mp_probe/` and `src/test_mapexists/`. Q1's output is the deliverable: the real per-map vehicle
matrix, measured rather than inferred.

⚠ Do not build the spawn UI before Q1 returns. "Every spawnable vehicle depending on map
type" is *defined* by that table, and guessing it from asset names is exactly the mistake the
`_wz` / `_mp` suffixes invite.

---

## 5. MEASURED — 2026-09-15, the parity probe ran

**Run 1** (`src/vehicle_probe/` v1, `mp_sm_gas_station`, Gunfight, host only), one line every 3 s:

```
VPROBE mp_sm_gas_station A=105 B=1 H=68 T=29 G=1 S=0 N=202
```

Decoded in the order the probe's own reading guide demands:

- **G=1 → form A is VOID.** The `+1` bit is form A (`#"vehicle"`, a *hashed* type argument) claiming
  the bogus name is loaded — and A=105, H=68, T=29 are every candidate in every set. The hashed-type
  form of `isassetloaded` answers **yes to everything**. It is not a residency test. Stock never uses
  it (all 10 stock call sites pass the plain string: `"vehicle"`, `"xanim"`, `"aitype"`,
  `"stringtable"`). ⚠ **Every future `isassetloaded` call in the project uses the plain-string type
  argument.** The `+2` bit is clear, so form B passed its control.
- **B=1 → the namespaces DO share names.** By the valid form, exactly **one** of the 105 `veh_t9/t8_*`
  xmodel-style names is a resident `vehicle` asset on this map. That closes step 1: the `model#`
  names are usable candidates for `vehicle#`, and what limits the count on a Gunfight map is
  per-map residency, not the naming. (v2, below, prints *which*.)
- **S=0** — no `veh_spawn_point` structs; stock Path A is unreachable here, as expected.
- **N=202** build control correct.

**Two corrections to §4 made by this run:**

1. Step 2's design constraint ("retail renders numbers only, so emit counts and bitmasks") is
   **retracted** — that finding was the unstripped ACTS string header ([[toolchain]]); with
   `tools/strip-strhdr.ps1` the probe prints labelled text, and v2 prints resident asset **names**
   directly. No bitmasks needed.
2. The probe gated its once-per-map report on the `mapname` dvar, which **does not exist in CW**
   ([[session-switch]] LS2); it now reads `sv_mapname` and simply re-prints every round (the counts
   are per map, and the map name is in the line).

**v2** (same payload name) tests form B only and prints: `Ms` = hits by **name** over the 105 as
plain strings, `Mh` = the same 105 as `#"hashed"` names by list index (the two must agree — a
string-vs-hash discrepancy would be its own finding), `H`/`T` by the valid form, `S`, `N`, and a
second line `PPROBE` carrying the [[static-props]] table read so both probes run in one match
(they share the injection target and cannot coexist).

### Runs 2 and 3 — v2 and v3 CRASHED the game at LINK time. Cause found: the validator's hole

Both crashes identical (`BlackOpsColdWar.20260916-014558.zip`, `...-015433.zip`; a copy of the
first is `payloads/vehicle_probe.v2-crash-20260916-014558.zip`): `error_message
0x6394f836,0000000000000001,`, raised from the server-frame → script-VM chain after a routine
recursed 23 frames deep, **5–6 s after the map switch — before the probe's 8 s wait had ended**. So
nothing in `report()` ran; the script died while the engine was *linking* it. That is the
`logprint()` signature `tools/check-gsc.ps1` already documents ("crashed 1–2 s into a map load").

**The cause: two calls the probe made as bare builtins are SCRIPT functions.** `prop_probe`'s
table read was copied from `prop.gsc:1850` — but `getmapname()` is defined *in that file*
(`prop.gsc:1825`, `return level.script;`) and so is `tablelookupbyrow( table, row, col )`
(`prop.gsc:1834`, a wrapper over the real builtin `tablelookuprow( table, row )`). Neither is in
the engine's builtin table (`C:\bocw\reference\funcs_cw.csv`, 4,481 rows read off the live exe).
Compiled fine; the linker could not resolve the imports; the game died. v1 had no prop line, which
is the only reason it survived.

**Why the validator said `ok`:** stage 4 only checked that a bare name is *called* somewhere in the
dump — and prop.gsc calls its own local functions. Fixed 2026-09-15: stage 4 now (1) strips string
literals before scanning (the old `all()` / `unavailable()` false positives are gone), (2) accepts
any name in the engine table as a builtin, and (3) reports **`SCRIPT FUNCTION name() - defined in
file:line`** as fatal for a bare name the dump defines with `function` and the engine table does
not list. `gunfight_menu.gsc` passes with zero notes; both probes now pass and are rebuilt.

⚠ Retraction of what an earlier revision of this section said: the crash was **not** an
`isassetloaded` on an existing-but-not-resident asset. That case is simply **unmeasured** — not
suspect. The `vehicle/default_engine.graph` string on the captured stack was the level loader's
own work (vehicle assets link during the load), not anything the probe asked for. The candidate
sets v2 dropped (campaign hashes, type strings, plain-string names) were dropped for a wrong
reason and can go back in — one set per run, so a real finding stays attributable.

**v4** (built as `payloads/vehicle_probe.gscc`, 16,207 B): v3 with `level.script` in place of
`getmapname()` and a local `table_cell()` over `tablelookuprow`. Prints `VPROBE3 <map> G= M=[i:name]
S= N=105` + the guarded `PPROBE` line.

### Run 4 — v4 ran clean (mp_sm_gas_station). The diagnosis holds, and the hit has a name

```
VPROBE3 mp_sm_gas_station G=0 M=1[82:veh_t9_mil_us_helicopter_large_chopper_gunner] S=0 N=105
PPROBE  mp_sm_gas_station tbl=1 rows=13 xs=0 s=4 m=5 l=4 xl=0 other=0 first=p8_wz_foliage_cactus_cardon_lrg_optimized res=1 G=0
```

- v4 is v3 minus the two script-function calls, and it **linked and ran** — the crash was those
  calls, nothing else. (The `PPROBE` line is [[static-props]]' result; recorded there.)
- **The one resident vehicle on Gas Station is the Chopper Gunner streak vehicle**, found by its
  xmodel-style name `veh_t9_mil_us_helicopter_large_chopper_gunner` through
  `isassetloaded( "vehicle", #"…" )`. Step 1 is closed with a name: the 105 `model#` names are a
  working candidate list for `vehicle#`, and the residency census (step 2) is just this probe
  run per map.
- `S=0` again: no `veh_spawn_point` structs — stock Path A is unreachable here.
- The hit is a **scorestreak** vehicle, and none of the other streak vehicles in the list (spy
  plane, counter-spy plane, gunship, VTOL…) read resident. The obvious explanation is that T9
  streams streak assets per the loadouts present in the match, so **what is resident is partly
  decided by the players' classes**. Untested; the test is free: swap Chopper Gunner out of every
  class for Spy Plane / RC-XD, restart, re-read `M`. If `M` follows the loadouts, the feature can
  *choose* what to make spawnable by what the host equips.

**Next runs, in order:** (1) the loadout test above; (2) a multi-map walk to settle common-set vs
per-map for both lines; (3) the sets v2 dropped, one per run: campaign hashes (`H`), type strings
(`T`), plain-string names (`Ms` vs `Mh`).

### The menu can spawn them (2026-09-15, klaze: "just add the vehicles, it has a safety net")

Start_menu -> Vehicles: 16 `veh_spawn` items over the real vehicle# names (buggies, quad,
motorcycle, snowmobile, sedan, light/transport trucks, T-72 + base tank, Hind, Armada heli,
care-package heli, prototype plane, jetski, PBR boat) + "Enter vehicle I am aiming at". The
mechanism is the shipped Atian menu's func_spawn_vehicle: `spawnvehicle( type, ahead, flat )` +
`makeusable()`, `setbrake(1)` for physics vehicles, `setrotorspeed(1)` if airborne; `veh_enter`
bullettraces and `usevehicle( self, 0 )`. **Safety net (already present):** each item gates on
`isassetloaded( "vehicle", type )` and says "no vehicle assets on this map" rather than failing, and
bails if `spawnvehicle` returns undefined - so the full list is safe on any map. UNTESTED which
names actually spawn; the census M= line predicts it per map (only the Chopper Gunner on the 6v6/
Fireteam maps measured so far, so expect most to report "no assets" until a 12v12-layout map).

### Run 5 — Fireteam maps (wz_forest/Ruka, wz_duga) under TDM: still just the Chopper Gunner

```
VEHICLES wz_forest G=0 M=1[82:veh_t9_mil_us_helicopter_large_chopper_gunner] S=0 N=105
PROPS    wz_forest tbl=0 G=0
```

klaze: "just the chopper gunner is wrong, I know there are many vehicles on this map." Both true.
The map *ships* ATVs, trucks, snowmobiles, a Hind - but those are spawned by the **Fireteam
gametype** from Radiant `*_spawner` ents (mp_common/vehicle.gsc `vehiclespawnthread` ->
`spawnfromspawner`; wz_forest.gsc only registers a per-vehicle debug callback). Under TDM/Gunfight
that code never runs, so the map's vehicles are neither entities nor resident assets - the engine
streams only what the active mode needs, and the one resident vehicle is the loadout/streak Chopper
Gunner. `tbl=0`: Ruka ships no Prop Hunt table (first measured "no" - so prop tables ARE per-map).

**Batch 2 added (index 105+):** the real `vehicle_t9_*` / `veh_quad_player_wz_*` / Hind / snowmobile
names + their hashed siblings, harvested from the wz map scripts' vehicletype arrays and the
spawnvehicle call sites (49 names, list now 154). And an **`E=` field**: the vehicle ENTITIES live
in the level now (`getvehiclearray`), as index:namexcount. So the next run separates "resident asset"
(M) from "actually spawned" (E). A Fireteam-mode launch is the real test for both - not reachable via
the Case-B path yet.

⚠ **Batch 2 first shipped a DEV-ONLY call and crashed on load** - the E= tally used
`function_9e72a96()` to stringify the vehicletype hash; that builtin is `funcs_cw.csv` type=1, refused
by retail outside a devblock ("Dev only calls must be wrapped in a devblock", error 0x6394f836). Fixed
by matching `.vehicletype` against the candidate list by index instead; check-gsc now flags type=1
builtins. See the [[gsc-builtin-trap]] memory / this note's sibling in check-gsc.

### The probe is now a menu tool: `gf_dbg_assets` (2026-09-15, klaze: "3")

The standalone payloads cannot coexist with `gunfight_menu` (one replace target), which made a map
walk two injections per map. So the same two reads live in the mod's debug feed as **Display →
Debug feed → "Asset census: vehicles + props"** (`gf_dbg_assets`, app: Config → Debug): lines
`VEHICLES <map> G= M=n[i:name] S= N=105` and `PROPS <map> tbl= rows= xs= s= m= l= xl= other= first=
res= G=`, every 3 s while on, computed once per round. Same candidate list, same order (index 82 =
Chopper Gunner), same controls. Map changes now go through the menu's own Stage / Switch NOW, and
the census follows. `src/vehicle_probe/` and `src/prop_probe/` stay as the standalone forms.

---

## 6. ⭐ OFFLINE — the complete per-map vehicle matrix, no probing. 2026-09-16

`tables/bgcache/<zone>.csv` carries a `vehicle,#<name>` row per resident vehicle asset. A map's set =
the map zone + the always-loaded `core_bootstrap` + `core_common` + `mp_common`. That answers "which
vehicles on which map" for all 36 MP maps **with no map loads at all** — the probe's residency
question is offline data.

**Universe: 205 vehicle names across the 68 zones — 58 plaintext, 147 hashed.**

### The 20 universal vehicles (every MP map, 15 named + 5 hashed)

```
defaultvehicle_mp                              veh_ultimate_turret
fake_vehicle                                   veh_ultimate_turret_wz
heli_ai_mp                                     vehicle_straferun_mp
veh_missile_turret                             vehicle_t9_mil_helicopter_care_package
veh_t8_ac130_gunship_mp                        vehicle_t9_mil_ru_air_vtol_forger
veh_t8_helicopter_gunship_mp                   vehicle_t9_rcxd_racing
veh_t8_helicopter_gunship_mp_guard             vehicle_t9_rcxd_racing_alt
veh_t9_mil_us_helicopter_large_chopper_gunner
```

⭐ **This explains run 4 exactly.** The one resident vehicle the probe found by name was the Chopper
Gunner — and it sits in **both** `core_common` and `mp_common`, i.e. universal. The probe was not
finding a Gas Station vehicle; it was finding the killstreak baseline every MP map carries.

⚠ These are **streak / system** vehicles, not drivables. Availability everywhere is not the same as
being useful everywhere.

### Per-map additions (map zone only, minus universal)

| map | extra | the named ones |
|---|---|---|
| `mp_black_sea` | 15 | jetski, jetski_alt, tactical_raft (+_alt), `veh…boat_pgb_double_gun` (+_alt), `boct…raft_gry_pc` |
| `mp_tundra` | 13 | ⭐ `vehicle_t9_mil_ru_tank_t72` (+`_alt`, `_sr`), `vehicle_t9_mil_snowmobile` (+`_alt`) |
| `mp_dune` | 11 | `veh_quad_player_wz_pc`, motorcycle (+`_alt`), `mil_fav_light` (+`_alt`), `truck_transport_player_alt`, `…_obj_sr` |
| `mp_cartel` | 5 | `vehicle_motorcycle_mil_us_offroad_alt` |
| `mp_tank` | 4 | `boct_mil_boat_tactical_raft_gry_pc` |
| `mp_sm_gas_station` | 4 | `vehicle_motorcycle_mil_us_offroad` (+`_alt`) |
| `mp_miami` | 3 | `boct_mil_boat_tactical_raft_gry_pc` |
| `mp_kgb` | 3 | (hashed only) |
| `mp_amerika` `mp_mall` `mp_moscow` | 2 | (hashed only) |
| `mp_apocalypse` `mp_cliffhanger` `mp_echelon` `mp_express_rm` `mp_satellite` | 1 | (hashed only) |

**18 of the 36 MP maps add NOTHING beyond universal** — Nuketown, Hijacked, Raid, Zoo, Village, Slums,
Drive-In, Firebase, Jungle, Paintball, Russian Base, Miami Strike and every `mp_sm_*` except Gas
Station. On those maps the only vehicles that exist are the 20 streak/system ones.

⚠ **Gas Station ships a motorcycle**, and the probe did not find it — because the probe's candidates
were 105 `veh_t9_*` **xmodel** names and the asset is `vehicle_motorcycle_mil_us_offroad`. A reminder
that the parity finding (§5) is real but **partial**: some vehicle assets share an xmodel name, most
do not.

### ⚠ The menu's vehicle list, cross-checked

Of the **144** `#"veh…"` / `#"vehicle…"` names in `gunfight_menu.gsc`, **18 exist anywhere in the
205-name universe**; the other 126 are the probe's xmodel candidate list still present as display
data. The 18 real ones:

```
veh_mil_ru_fav_heavy                     vehicle_t9_mil_ru_tank_t72_sr
veh_t9_mil_us_helicopter_large_chopper_gunner   vehicle_t9_mil_ru_truck_light_player
vehicle_motorcycle_mil_us_offroad        vehicle_t9_mil_ru_truck_transport_player
vehicle_t8_mil_air_transport_infiltration  vehicle_t9_mil_ru_truck_transport_player_obj_sr
vehicle_t9_civ_ru_sedan_80s_player       vehicle_t9_mil_snowmobile
vehicle_t9_mil_air_transport_hpc_intro   vehicle_t9_mil_us_helicopter_large_cp_armada_player
vehicle_t9_mil_fav_light                 vehicle_t9_mil_us_truck_m35_canvas_cp / _cargo_cp / _tanker_cp
vehicle_t9_mil_helicopter_care_package   vehicle_t9_rcxd_racing
```

⚠ **Only 2 of those 18 are universal** (`chopper_gunner`, `care_package`, plus `rcxd_racing`). Several
are **`_cp`** — campaign-only, resident on no MP zone — and `tank_t72_sr` / `snowmobile` are
**Tundra-only**, `mil_fav_light` **Dune-only**, `motorcycle` **Gas Station / Cartel / Dune only**.
So the page should gate per map off this table, or most rows will fail on most maps.

### ⚠ Hash resolution is dead, second confirmation

All 147 hashed vehicle names through the ACTS index (§2's runbook): **1 of 147**
(`3effd1dd89ee3d36` = `flying_camera_drone_wz_escape_infil`). The community index does not carry
BOCW vehicle names. The 58 plaintext names are what we have, and per the matrix above they are
enough for every MP map.
