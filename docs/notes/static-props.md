# Static props — spawning them, and where the per-map list already exists. 2026-09-15

Goal: a prop page in the menu — spawn static props, ideally a set that works on **most** maps plus a
few map-specific ones. Read out of the T9 dump; **nothing measured in-game yet.**

**Status 2026-09-15: MEASURED on mp_sm_gas_station (bottom of this note) — the table exists there, 13 rows, row 0 resident. The headline is that Treyarch already solved the per-map list problem and
the answer is readable at RUNTIME, so unlike [[vehicles]] this does not need an offline asset dump.**
**2026-09-17: the Props page is BUILT (§8), never run** — this map's `_ph.csv` rows + a 48-model
universal set, every row `isassetloaded`-gated, placed where the host looks.

---

## 1. The spawn primitive is trivial

Prop Hunt's `setupprop()` (`mp_common/gametypes/prop.gsc:1922`, the model set at `:1946`) is the
whole recipe:

```gsc
self.prop = spawn( "script_model", self.propent.origin );
self.prop.targetname = "prop";
self.prop setmodel( propinfo.modelname );
self.prop setscale( propinfo.propscale );
self.prop setcandamage( 1 );
self.prop setowner( self );
```

`spawn( "script_model", origin )` + `setmodel( name )` + optional `setscale`. No spawner entity, no
asset-type gating, no `vehicletype` indirection. Compare [[vehicles]], where the equivalent needed a
`vehicle#` asset name that the dump does not contain.

## 2. ⭐ Treyarch ships a CURATED PROP TABLE PER MAP

`populateproplist()` (`prop.gsc:1850`) is the find:

```gsc
mapname = getmapname();
var_a01224f2 = "gamedata/tables/mp/" + mapname + "_ph.csv";
numrows = tablelookuprowcount( var_a01224f2 );
```

Eleven columns, read by `tablelookupbyrow( path, row, col )`:

| col | field | note |
|---|---|---|
| 0 | `modelname` | the xmodel to `setmodel` |
| 1 | size text | `xsmall` \| `small` \| `medium` \| `large` \| `xlarge` |
| 2 | `propscale` | 0 or absent → treated as 1 |
| 3-5 | offset x/y/z | |
| 6-8 | rotation x/y/z | |
| 9 | `propheight` | blank → derived from size |
| 10 | `proprange` | blank → derived from size |

This is a **hand-curated, per-map list of props that are resident on that map, already tuned with
scale, offset and rotation.** It is exactly the deliverable, authored by the people with the source
art. Columns 2-8 in particular are work we would otherwise have to redo by eye, per prop, per map.

### ⚠ The table is NOT in the dump — and that does not matter

`gamedata/tables/mp/` in `bocw-source-main` holds only `mp_unlockmapping.csv` and `scoreinfo/`; a
`find` for `*_ph.csv` returns **0**. The dump is a *script* dump.

But `tablelookuprowcount` / `tablelookupbyrow` are **GSC builtins that read the shipped CSV at
runtime**, and both appear in MP script. So a mod can enumerate the current map's prop table in-game
and never needs the file offline:

```gsc
path = "gamedata/tables/mp/" + getmapname() + "_ph.csv";
n    = tablelookuprowcount( path );
for ( i = 0; i < n; i++ )
{
    modelname = tablelookupbyrow( path, i, 0 );
    ...
}
```

⚠ **This is the whole feature, and it is self-configuring per map.** "Universal vs map-specific"
stops being a question we answer offline: each map reads its own table. The menu can be built from
whatever that map curates.

### ⚠ Which maps have one — the number that actually matters

Prop Hunt did not ship on every map, and stock handles absence explicitly (`prop.gsc:1910`):

```gsc
if ( numrows == 0 )
{
    addproptolist( "tag_origin", 150, ( 0, 0, 0 ), ( 0, 0, 0 ), "medium", 1, ... );
}
```

`tag_origin` is an **invisible** model — stock's fallback for "this map has no prop table" is a prop
you cannot see. So `tablelookuprowcount()` per map is the single highest-value reading available, it
is **one integer**, and it suits the numbers-only readout channel perfectly. Maps reading 0 need
their prop list built some other way; maps reading >0 are free.

## 3. Size buckets and weights

`getpropsize()` (`prop.gsc:2178`) maps the text to a number, and `organizeproplist()` (`:1716`)
weights random selection across the buckets:

| size text | value | selection weight |
|---|---|---|
| `xsmall` | 50 | 10 |
| `small` | 75 | 30 |
| `medium` | 150 | 40 |
| `large` | 250 | 20 |
| `xlarge` | 350 | 10 |

Weights are conditional on the bucket being populated (`10 * isdefined( level.proplist[ 50 ] )`), so
a map whose table has no xlarge entries simply never rolls one. Reading the **per-bucket counts** is
therefore a cheap second number and tells you the shape of a map's table, not just its size.

## 4. The two gates — and ⭐ only one applies

[[vehicles]] established two gates. Props inherit one and escape the other:

- **Gate 1, asset residency — APPLIES.** `setmodel` needs the xmodel in the client's loaded zone.
  But note this gate is *already satisfied by construction* for anything in that map's `_ph.csv`:
  Treyarch curated those entries against that map.

  ⚠ **`isassetloaded( "xmodel", ... )` is a GUESS, added 2026-09-15 from [[projectiles]].** Stock
  calls `isassetloaded` with exactly four asset types — `aitype`, `stringtable`, `vehicle`, `xanim`.
  **`"xmodel"` is not among them.** If it is not a valid type string, both residency bits in
  `src/prop_probe/` read 0 and look identical to "model not resident". The disambiguator: a map with
  `numrows > 0` whose row-0 model reads 0 on **both** call forms means the TYPE STRING is wrong, not
  that Treyarch curated a missing asset. Treat the first such reading as a probe bug, not a finding.
- **Gate 2, clientfield symmetry — DOES NOT APPLY.** ⭐ This is the structural difference.
  `prop.gsc` registers 11 clientfields (`:193-204`) but **every one is Prop Hunt gameplay** —
  `hideTeamPlayer`, `PROP.cameraHeight`, `PROP.change_prop`, the `hudItems.*` counters. **None of
  them render the prop.** The prop is a plain `script_model` whose model replicates by the ordinary
  entity path, so a vanilla joiner sees it with no registered handler.

That inverts the risk profile versus vehicles: the thing that could have made vehicles host-only eye
candy has no equivalent here. ⚠ Stated from the source, **not yet measured with a real joiner.**

## 5b. ⭐ RETRACTION 2026-09-16 — the dump DOES enumerate props, per map, offline

§5 below says static props are "largely invisible to this dump". **That is wrong**, and it was wrong
when written: it scanned `scripts/` + `scriptbundle/` only. The per-zone asset manifests answer it
directly, and they were in the tree the whole time:

| file | what it is | Gas Station |
|---|---|---|
| `tables/bgcache/<zone>.csv` | **gameplay** manifest — `vehicle` `model` `weapon` `character` `fx` `destructible` `scriptbundle` rows | 206 `model`, 4 `vehicle` |
| `tables/data/assets/<zone>.csv` | **full render** manifest — every `xmodel` in the zone | **4,333 `xmodel`** |

A map's resident model set = the map zone + the always-loaded `core_bootstrap` + `core_common` +
`mp_common` (the model `map-assets.json` already uses for vehicles).

### The universal prop set — on EVERY MP map

`core_bootstrap + core_common + mp_common` carry **20,572 xmodels** (19,620 plaintext). ⚠ Almost all
of that is loadout, not scenery, and the split is the useful part:

| family | count | what it is |
|---|---|---|
| `attach_*` | 11,179 | weapon attachments |
| `c_*` | 3,864 | characters |
| `wpn_*` | 3,402 | weapons |
| **`p9_*`** | **338** | ⭐ **the actual T9 props** |
| `wrist_*` | 290 | watches |
| `veh_*` | 198 | vehicle models |

So the universal prop set is **~338 models**, and they are real recognisable objects, available on
every map with no per-map check: `p9_usa_bench_01`, `p9_usa_bicycle_01`, `p9_usa_dumpster_01_full`,
`p9_usa_couch_04`, `p9_nt6_arcade_game`, `p9_nt6_chair_wood`, `p9_nt6_machine_washing_dirty`,
`p9_mal_arcade_cabinet_08`, `p9_mal_bean_bag_chair_sml`, `p9_ger_tank_barrel_metal_01`,
`p9_rus_amk_telephonebooth_01_closed_v2_wet`, `p9_ger_kgb_mount_barrier_concrete_144`.

### ⭐ The 12 `_prophunt` models — purpose-built, and universal

Twelve xmodels carry a literal `_prophunt` suffix, and **all twelve are in `mp_common`**, so they are
resident on every MP map:

```
p9_barrel_metal_rusted_01_prophunt        p9_nt6_abandoned_mattress_01_prophunt
p9_krail_concrete_worn_01_prophunt        p9_nt6_mannequin_clothes_female_02_dmg_full_prophunt
p9_rm_rai_dub_vase_prophunt               p9_nt6_mannequin_clothes_female_03_dirty_full_prophunt
p9_ang_satellite_panel_02_prophunt        p9_nt6_mannequin_clothes_male_01_dirty_full_prophunt
p9_ang_satellite_panel_03_prophunt        p9_ger_tank_computer_server_diagnostic_01_silver_prophunt
p9_ang_satellite_capsule_plate_02_prophunt  p9_ger_tank_tank_tread_rolls_01_prophunt
```

Treyarch authored these *for* Prop Hunt — presumably the ones needing bespoke collision or scale.
Twelve is not the mode's whole roster (the `_ph.csv` tables are), but it is a **known-good, known-
universal starter set that needs no table read and no probe.**

### Map-specific props

Gas Station's own zone adds **1,144** usable models once the loadout families are excluded
(`attach_*`, `c_*`, `wpn_*`, `wrist_*`), led by `veh_t9_*` 194, `p9_usa_*` 50, `p8_wz_*` 30.
So the per-map layer is ~1,000 models, and §6's "intersect the tables across maps" can now be done
**entirely offline** against these manifests rather than one map load at a time.

⚠ What this does NOT replace: the `_ph.csv` tables still carry **scale, offset and rotation** per
prop (§2). The manifests answer *what is resident*; the CSV answers *how to place it well*. Both are
worth having, and only the CSV needs a runtime read.

---

## 5. ⚠ The dump's model list is NOT a prop catalogue — ⚠ SUPERSEDED, see §5b

3,324 plaintext `model#` names exist in `scripts/` + `scriptbundle/` (vs only 451 hashed — the
inverse of the `vehicle#` situation, where everything was hashed). Tempting, but check what they are:

| family | count | what it is |
|---|---|---|
| `p9_zm_*` | 651 | Zombies props |
| `attach_t9_*` | 504 | weapon attachments and charms |
| `wrist_watch*` | 286 | watches |
| `p9_fxanim_*` | 281 | animated FX models |
| `c_t9_*` | 225 | characters |

⚠ **Static map props are placed in Radiant and never named in script**, so they are largely *invisible*
to this dump. A keyword sweep for generic objects (barrel/crate/box/chair/table/...) returns 174 hits
and **most are weapon charms** (`attach_t9_charm_chemical_barrel_ms`). The genuine prop-looking names
that do surface carry no prefix convention at all — `car_table_01`,
`cardboard_box_damaged_01_small`, `container_armory_crate_01_dust_dustable`,
`ger_crate_ammo_closed_02_dirty`, `ger_jerry_can_01_gas`.

So the dump can seed a *universality* experiment, but it cannot enumerate props. The `_ph.csv` route
is not merely easier — it is the only one with real coverage.

## 6. Answering the two asks

**"Props that work on most maps."** Two routes, and they answer different questions:
- **Intersect the `_ph.csv` tables across maps at runtime.** Gives props Treyarch curated *and* that
  recur. Highest quality, and the offsets come free. Needs one read per map.
- **Test a generic-name pool with `isassetloaded( "xmodel", ... )` per map.** Answers universality
  directly, including props no `_ph.csv` lists, but gives no scale/offset tuning and the candidate
  pool is weak (§5).

Start with the first. The second only earns its place if many maps read `numrows == 0`.

**"A few unique ones from certain maps."** Native — each map's table *is* its unique list. No extra
work beyond reading it.

## 7. Next step — one probe, same shape as `src/vehicle_probe/`

Everything below is one read-only payload, reported as numbers, gated to one burst per map by the
same `gf_vprobe_map` dvar trick:

1. **`tablelookuprowcount( "gamedata/tables/mp/<map>_ph.csv" )`** — ⬅ THE NUMBER. Does this map have
   a curated prop table, and how big?
2. **Per-bucket counts** (xsmall/small/medium/large/xlarge) — the table's shape.
3. **A residency control** — `isassetloaded( "xmodel", <name from row 0> )` against a name read out
   of the table itself. Confirms the runtime read works *and* that the listed model is really
   resident, in one reading.
4. **A generic-pool count** — how many of a bare-name candidate set are resident, for the
   universality question, and only worth carrying if (1) reads 0 on real maps.

⚠ Do not carry model names into the payload as literals when the table can be read at runtime. That
is the mistake [[vehicles]] was forced into by a hashed namespace, and props do not have that problem.

---

## MEASURED — 2026-09-15, `prop_probe` ran (inside the `vehicle_probe` payload, mp_sm_gas_station)

```
PPROBE mp_sm_gas_station tbl=1 rows=13 xs=0 s=4 m=5 l=4 xl=0 other=0 first=p8_wz_foliage_cactus_cardon_lrg_optimized res=1 G=0
```

- **Gas Station ships a curated Prop Hunt table**: `gamedata/tables/mp/mp_sm_gas_station_ph.csv`
  exists (`tbl=1` = `isassetloaded( "stringtable", path )`, the guard stock uses at
  `scoreevents_shared.gsc:502`), **13 rows**: 4 small, 5 medium, 4 large, no xsmall/xlarge, every
  size cell matched one of the five stock buckets (`other=0`).
- Row 0 is `p8_wz_foliage_cactus_cardon_lrg_optimized` (a BO4 Blackout foliage model, read live off
  the table) and it **is a resident xmodel** (`res=1`; the bogus-asset control read 0). So the
  runtime read works end to end: table → row → model name → residency.
- The read is per map and free; the same payload re-links on every map load, so the per-map
  `rows` census is a walk through the map list with no re-inject.

⚠ Two of the calls copied from `prop.gsc:1850` — `getmapname()` and `tablelookupbyrow()` — are
**script functions defined in prop.gsc**, not builtins; calling them bare crashed the game at link
time twice ([[vehicles]] §5, runs 2–3). The probe now uses `level.script` and a local wrapper over
the real builtin `tablelookuprow( table, row )`. `tools/check-gsc.ps1` catches the class now.

The same read is now the `PROPS` line of the mod's debug feed (`gf_dbg_assets`, Display → Debug
feed → "Asset census: vehicles + props"), so the per-map `rows` census is a map walk with the menu
in — see [[vehicles]] §5.


---

## 8. BUILT 2026-09-17 — the Props page. Never run.

The goal at the top of this note — "a prop page in the menu: a set that works on most maps plus a
few map-specific ones" — is Start menu → *Props* in `gunfight_menu.gsc` (payload 362,812 B;
check-gsc PASS, zero notes). Both halves of §6 are on it, and both are self-configuring:

| page | rows | source |
|---|---|---|
| *This map's Prop Hunt set (N)* | one `Place <model> (<size>)` row per table row, with the table's own `propscale` | `gamedata/tables/mp/<map>_ph.csv` read at runtime (§2), first 64 rows; the map-specific half, hand-tuned by Treyarch |
| *Universal props* | 48 rows: the 12 `*_prophunt` models (§5b, all in `mp_common`) + 36 hand-picked `p9_*` scenery models from the universal 338 (bench, bicycle, couch, dumpster, mailbox, street light, soda machine, target dummy, arcade game, washing machine, fridge, snowman, kiddie rocket ride, scissor lift, phone booth, oil drum, server, concrete barrier, gas pump, sandbags, Czech hedgehog, ammo crate, hay bale, spool, water cooler, palm tree, pot of gold, dirty bomb, 155 mm gun…) | `tables/data/assets/{core_bootstrap,core_common,mp_common}.csv` — resident on every MP map by construction |
| Remove the last prop I placed / Remove every prop | `delete()` over `level.gf_props` | — |

**Every row is gated by `isassetloaded( "xmodel", model )` at page build**, so a model that is not
resident is simply not offered — the guess §4 flagged is now a measurement: the 2026-09-15 census
read `res=1` for Diesel's row-0 model with the bogus-name control at 0, so `"xmodel"` IS a valid
type string for `isassetloaded`.

The spawn is `setupprop()`'s recipe (`prop.gsc:1946`) minus the player linkage: `spawn(
"script_model", spot )` → `setmodel( model )` → `setscale( scale )` when the table says so →
`.angles` turned to face the host. `spot` is where the host is looking (the teleport's trace),
pushed 24 u off the surface and dropped to the floor with `playerphysicstrace` (`tp_floor`); a shot
into the sky puts it 200 u ahead. A plain replicated entity — Gate 2 does not apply (§4), a vanilla
joiner sees it. Props are tracked on `level.gf_props` and die with the level, so a round boundary
clears them (Gunfight rebuilds `level` per round — [[mp-dvars]]).

App: *Map toys* → Props: a universal-prop picker (`gf_cmd_action prop`, arg = the label in quotes
— the GSC matches label or model name, and a label stays inside the 47-byte bridge slot where a
model name like `p9_ger_tank_computer_server_diagnostic_01_silver_prophunt` would not), `propundo`,
`propclear`.

### ⚠ Still inferred

1. **Collision.** A bare `script_model` collides only if the xmodel ships collision; the `_prophunt`
   twelve presumably do (that is what Prop Hunt needed them for), the scenery models may not — a
   prop players walk through is cosmetic, not cover. `setcandamage(1)` is not set, so nothing shoots
   it apart.
2. **Scale from the table** applies the `_ph.csv` `propscale`; the table's offsets and rotations
   (columns 3-8) are Prop Hunt's player-anchor tuning and are not applied to a free-standing prop.
3. **`isassetloaded( "xmodel", … )` reading 1 for a model the CLIENT has not loaded.** The check is
   host-side; residency is per zone and the zone is the same for everyone, so a joiner has it too —
   inferred from the zone model, not measured with a joiner.

### Test sheet — ONE write per match

| # | on | do | read |
|---|---|---|---|
| 1 | Diesel (table measured: 13 rows) | Props → *This map's Prop Hunt set* | 13 rows offered (or fewer — each is a residency read); pick the cactus (row 0) | 
| 2 | Diesel | *Place …* it while looking at the floor 5 m away | the model appears there, upright, facing you; feed says `placed … (1 this round)` |
| 3 | any | *Universal props* → Snowman, then Park bench, then Target dummy | each appears; walk into one — does it collide |
| 4 | any | *Remove the last prop*, then *Remove every prop* | they vanish in that order |
| 5 | Ruka (measured tbl=0) | *This map's Prop Hunt set* | `(no Prop Hunt table on this map - use Universal)`; Universal still offers rows |
| 6 | with a joiner | place one | the joiner sees it where you see it |

Record: `______`
