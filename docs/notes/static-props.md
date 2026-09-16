# Static props — spawning them, and where the per-map list already exists. 2026-09-15

Goal: a prop page in the menu — spawn static props, ideally a set that works on **most** maps plus a
few map-specific ones. Read out of the T9 dump; **nothing measured in-game yet.**

**Status 2026-09-15: MEASURED on mp_sm_gas_station (bottom of this note) — the table exists there, 13 rows, row 0 resident. The headline is that Treyarch already solved the per-map list problem and
the answer is readable at RUNTIME, so unlike [[vehicles]] this does not need an offline asset dump.**

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

## 5. ⚠ The dump's model list is NOT a prop catalogue

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
