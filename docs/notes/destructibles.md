# Destructibles — enumerate and detonate the map's own breakables. 2026-09-16

Mined offline from the zone manifests + `scripts/core_common/destructible.gsc`. **Nothing measured
in-game.** Unlike [[vehicles]] and [[static-props]] this is a system nothing in the project had
looked at, and it turns out to be one of the cheapest features available: **one call enumerates
every destructible on a map, and one builtin destroys one.**

**Status 2026-09-17: BUILT, never run (§8)** — the `DESTRUCT` census line (which also recovers the
real destructible names the manifests hash), the Destructibles page (break aimed / near / all), and
the radiant-exploder walker over a generated per-map table (`tools/exploders-gen.py`, 699 rows,
34 named). Test sheet at the bottom.

---

## 1. Enumeration is a single call

`destructible::preinit` (`destructible.gsc:21-25`) does exactly this at level start:

```gsc
destructibles = getentarray( "destructible", "targetname" );
...
if ( getsubstr( destructibles[ i ].destructibledef, 0, 4 ) == "veh_" ) { ... car_death_think() }
if ( destructibles[ i ].destructibledef == "fxdest_upl_metal_tank_01" ) { ... }
```

So every breakable on the map is one `getentarray` away, and each entity carries
**`.destructibledef`** — the asset name, readable at runtime. Stock itself branches on that string,
which means the naming is stable enough to key behaviour off.

⚠ `getentarray` is already used in `gunfight_menu.gsc` and passes `check-gsc`. Nothing new is needed.

## 2. Destroying one is `dodamage`

`breakafter( time, damage, piece )` (`destructible.gsc:613`) is the stock wrapper, and its payload is
one line:

```gsc
self dodamage( piece, self.origin, undefined, undefined );
```

`dodamage` is a **server builtin** already verified in the menu's stage-4 list. So "blow up every
destructible on this map" is a loop over the `getentarray` result. Richer stock behaviours are
available on the same entity: `simple_explosion( attacker )` (`:210`),
`simple_timed_explosion( event, attacker )` (`:235`), `complex_explosion( attacker, max_radius )`
(`:277`), `car_explosion( attacker, physics_explosion )` (`:305`).

## 3. ⚠ The explosion VISUAL is a clientfield — the destruction is not

`physics_explosion_and_rumble` (`:51`) ends in:

```gsc
self clientfield::set( "start_destructible_explosion", radius );   // registered :23
```

So **Gate 2 applies to the explosion FX** ([[vehicles]] §3): a vanilla joiner runs stock `.csc`, and
that field IS stock-registered, so the joiner *does* draw it — this is the good case, not the
blocked one. The field belongs to stock's own system, not ours, so driving it through stock's
functions is joiner-safe in a way a bespoke clientfield would not be.

⚠ Do not register a new clientfield for this. Use stock's path and the symmetry holds.

## 4. Per-map data — almost entirely map-specific

Universal (`core_bootstrap + core_common + mp_common`): **9 rows, only 2 plaintext** —
`defaultdestructible` and `wpn_t8_smartcover_cover_destructible_blue`. So essentially **nothing is
universal**; destructibles are a property of the map.

| map | destructibles |
|---|---|
| `mp_miami` | **30** |
| `mp_sm_gas_station` | 21 |
| `mp_sm_deptstore` / `mp_moscow` / `mp_mall` | 15 |
| `mp_nuketown6` / `mp_miami_strike` | 13 |
| `mp_paintball_rm` | 12 |
| `mp_firebase` | 11 |
| `mp_dune` | 10 |
| `mp_village_rm` / `mp_raid_rm` | 9 |

⚠ These are counts of **asset definitions**, not instances. A map with 13 defs may place dozens of
entities using them — the runtime `getentarray` is what gives the real count, and it is free.

## 5. Why this is worth doing

- **No per-map gating needed.** Unlike vehicles, the feature reads whatever the map has. A map with
  zero destructibles simply yields an empty array.
- **No asset residency question at all.** We are not spawning anything; the entities already exist.
  Both gates that complicate [[vehicles]] are absent.
- **Server-side.** `getentarray` + `dodamage` are both server builtins.
- **Nuketown has 13** — so even the maps with no vehicles have something here.

## 6. Next step

A read-only census first, in the `gf_dbg_assets` feed line's style: `getentarray( "destructible",
"targetname" ).size` plus a few `.destructibledef` values. That is one number and a few strings, and
it settles whether def counts (§4) predict instance counts.

⚠ Then the write is genuinely destructive and permanent for the round — blowing the map's cover apart
changes the match. It belongs behind the same "never run in-game" protocol as the Players page
([[client-control]]), and it is a **one-write-per-match** staged test by the `src/README.md` rule.

---

## 7. Radiant exploders — the adjacent system, and it is bigger

`radiant_exploder` rows are the map's own authored explosion/effect triggers. **Zero are universal** —
entirely per-map, like destructibles, but the counts are larger:

| map | exploders | | map | exploders |
|---|---|---|---|---|
| `mp_tundra` | **71** | | `mp_firebase` / `mp_echelon` | 22 |
| `mp_black_sea` | 46 | | `mp_mall` / `mp_dune` | 21 |
| `mp_miami` | 34 | | `mp_cartel` | 18 |
| `mp_moscow` | 32 | | `mp_sm_gas_station` / `mp_express_rm` | 16 |
| `mp_apocalypse` | 26 | | `mp_satellite` | 25 |
| `mp_cliffhanger` | 24 | | | |

⚠ **Every radiant_exploder name in the manifests is HASHED** — every one of Gas Station's 16 reads
`hash_*`. That is fine here and it is the useful part: the API takes them.

### Two namespaces, one entry point

`exploder::exploder( exploder_id )` (`exploder_shared.gsc:278`) branches on the argument type:

```gsc
if ( isint( exploder_id ) ) { activate_exploder( exploder_id ); return; }   // SCRIPT exploders, integer
activate_radiant_exploder( exploder_id );                                    // RADIANT, by name/hash
```

- **Script exploders** take an **integer** — discoverable only by walking 1..N in game.
- **Radiant exploders** take the name — and **the bgcache hashes are exactly that**, so a per-map
  list is available offline with no cracking. The project already passes `#"hash_..."` literals
  elsewhere, so `exploder( #"hash_a7bb341b0967857" )` is the shape.

⭐ This is the one place the hashed-name problem that blocked [[vehicles]] **does not hurt**: we never
need the plaintext, because the hash is the argument.

⚠ `gunfight_menu.gsc` already calls `exploder::exploder` and passes `check-gsc` stage 3.

### ⚠ Joiner visibility — stock's own path, so probably symmetric

`activate_radiant_exploder` (`:731`) ends in **`activateclientradiantexploder( string )`** — the name
says client. It is stock's own server→client mechanism with stock's own handlers, so a vanilla joiner
should see it, the same favourable case as the destructible clientfield in §3. **Not measured.**

⚠ `activate_individual_exploder` (`:748`) guards on **`level.clientscripts`**, so the script-exploder
path has a client-script dependency worth understanding before relying on it.

### What this is good for

A per-map "detonate exploder N" control is a genuinely cheap spectacle feature: the list is offline,
the argument is a hash we already have, and the entry point is one stock call the menu already links
against. Tundra's 71 and Black Sea's 46 are the maps to try it on.

⚠ Same caution as §6 — firing exploders is a **write** and changes the match. One per match, behind
the never-run-in-game protocol.


---

## 8. BUILT 2026-09-17 — the census line, the Destructibles page, the exploder walker. Never run.

Everything §6 and §7 asked for is in `gunfight_menu.gsc` (payload `gunfight_menu.gscc`, 362,812 B,
2,078 strings; check-gsc PASS with zero notes, check-args 0 mismatches). Nothing has run in-game.

### The read — `DESTRUCT`, the third `gf_dbg_assets` feed line

```
DESTRUCT <map> n=N kinds=K veh=V unnamed=U X=E [<def>x<count>,...]
```

`n` = destructible ENTITIES in the level (`getentarray( "destructible", "targetname" )`, §1),
`kinds` = distinct `.destructibledef` names among them with the first 10 listed, `veh` = how many are
cars (def starts `veh_`, stock's own test), `X` = how many radiant exploders the OFFLINE table
(§7, below) lists for this map — a 0 there with exploders expected means the generator's map name
does not match `sv_mapname`. Display → Debug feed → *Asset census*, or the row on the page itself.

⭐ **This line is the answer to §4's hashing problem.** The manifests hash every destructible name;
`.destructibledef` at runtime is the real string, so one census on each map recovers the plaintext
names the dump lost — and it goes to the app too: a fourth GAME→APP channel,
`GFMAPDEST|<map>|n=<count>|kinds=<k>|<def>x<count>,...|END`, filed by
`tools/gf-control/mapdata_scan.py` into `mapdata/<map>.json` as `destructibles` next to the vehicles,
props and spawn keys ([[map-data]]).

### The write — Start menu → *Destructibles + exploders*

Rebuilt on entry (the header row is the live count):

| row | does |
|---|---|
| `(N destructibles here, K kinds, V cars)` | the census, on the page |
| Break the one I am looking at | `bullettrace` → the hit entity if it carries `.destructibledef`, else the nearest destructible within 160 u of the impact point; `dodamage( 20000, origin + 5z, host )` — `simple_explosion`'s own shape (`destructible.gsc:227`), attacker = host so a kill by the blast credits |
| Break everything within 600 u of me | the same, filtered by `distancesquared`, 6 per server frame |
| Break EVERY destructible on the map | the whole array, 6 per frame |
| Census line to the feed | the `gf_dbg_assets` toggle |
| Radiant exploders (N listed) | the walker page |

App: *Map toys* → Destructibles `break aimed` / `break near me` / `break ALL` (`gf_cmd_action destruct`,
arg `aim` / `near` / `all`).

### The exploder walker — Start menu → Destructibles → *Radiant exploders*

`tools/exploders-gen.py` reads every `radiant_exploder` row of `tables/bgcache/mp_*.csv` and
`wz_*.csv` and writes them INTO the GSC between `// [exploders-gen BEGIN]` / `END` markers — one
`exp_rows_<map>()` per map, dispatched by `exp_table()` on `sv_mapname` — plus
`docs/data/map-exploders.json`. **699 rows over 32 maps** (mp_common carries none, so nothing is
universal; the nine `mp_sm_*` Gunfight maps other than Diesel and Game Show list none), in manifest
order so an index is stable until the dump changes.

**34 of the 699 have a name** — cracked against every string literal the mp / mp_common / core_common /
wz / killstreaks scripts spell out (FNV1a64 & MASK63, `tools/crack-hash.py`'s algorithm):
Nuketown's `fxexp_holiday` / `fxexp_halloween`, Crossroads' `fxexp_tundra_6v6` + `exp_lgt_12v12`,
Armada's `fxexp_main_ship_oil_fire_level`, Express' 14 train debris / sparks / gate-dust triggers,
WMD's 8 room light states + `fxexp_glass_shatter` + `fxexp_center_event`, Deprogram's two red-door
enters, Game Show's `fxexp_flag_confetti`, Sanatorium's `lgtexp_lightstate2`. Those are passed as
plain strings, the form every map script uses; the other 665 as `#"hash_..."` literals — the form
`frontend.csc:3881` passes to the same function, and `"" + #"hash"` (the notify
`activate_radiant_exploder` builds first) is a stock idiom (`archetype_avogadro.gsc:49`).

| row | does |
|---|---|
| `(N radiant exploders listed for this map)` | the offline count |
| Fire NEXT / Fire PREVIOUS / Fire the current one again | `exploder::exploder( key )`; the index lives on `level`, so the walk restarts at 1 each round; the feed prints `fired exploder 12/71 (unnamed - map-exploders.json #12)` or the cracked name |
| Stop the current one | `deactivateclientradiantexploder( key )`, the builtin called direct — stock's `delete_exploder_on_clients` (`exploder_shared.gsc:858`) only reaches it for a string, ours are hashes |
| Fire ALL, one every 0.5 s | a `level` thread; *Stop the walk* notifies it dead |
| Fire 12: fxexp_holiday … | one row per NAMED exploder on this map |

App: *Map toys* → Exploders `fire next` / `previous` / `again` / `stop current` / `fire all` /
`stop walk` (`gf_cmd_action exploder`, arg = the verb).

### ⚠ What is inferred, not measured

1. **A hash into `activateclientradiantexploder`.** Stock's server side only ever passes strings
   (map scripts); the hash form is proven on the CLIENT side (`frontend.csc:3881` →
   `playradiantexploder( localclientnum, hash )`, and `stop_exploder` tests `ishash()` on its input).
   The engine's radiant-exploder lookup is by name and the bgcache stores names as hashes, so a
   pre-hashed argument is the expected shape — but the first *unnamed* row to fire is the
   measurement. The 34 named rows use the proven string form, so **fire a named one first**
   (Nuketown `fxexp_holiday`, Crossroads `fxexp_tundra_6v6`).
2. **What an unnamed exploder does** — a light state, a sound, an FX burst, a brush swap. Many are
   lighting (`exp_lgt_12v12` is one of the named ones); a walk through Crossroads' 71 will change
   the map's look. *Stop the current one* is the undo; a round boundary resets everything.
3. **`dodamage` on a destructible whose def is a vehicle (`veh_*`)** — stock's `car_death_think`
   owns those; the damage should route through the same state machine, but the burning-car
   sequence has its own timers and may not fire from a single hit.
4. **`.destructibledef` as a hash** — if the census prints `unnamed=N` with `kinds=0`, the field is a
   hash on this VM and `destruct_def()` needs `"" + def` instead of `isstring()`.

### Test sheet — ONE write per match, lobby return after each

| # | on | do | read |
|---|---|---|---|
| 1 | Nuketown '84 | Display → Debug feed → *Asset census* ON | `DESTRUCT mp_nuketown6 n=? kinds=? ... X=10` — `n` vs the manifest's 13 defs settles §4's def-vs-instance question; `kinds` names them |
| 2 | Nuketown '84 | Destructibles → *Break the one I am looking at* on a car / barrel | it breaks; the feed names the def; a joiner (if present) sees the same explosion |
| 3 | Diesel | *Break everything within 600 u of me* | only nearby ones go; count in the feed |
| 4 | Miami | *Break EVERY destructible* (30 defs, the richest 6v6 map) | everything breaks over a few frames; no hitch worth noting |
| 5 | Nuketown '84 | Exploders → *Fire 6: fxexp_holiday* (the string form) | Christmas lights / holiday dressing appears — proves the call path; then *Stop the current one* |
| 6 | Nuketown '84 | *Fire NEXT* from 1 (a hash row) | ANY visible/audible change proves the hash form; nothing = go to inference 1 |
| 7 | Crossroads | *Fire ALL* | a 35 s light-and-effects show; *Stop the walk* mid-way |

Record on the row: `______`
