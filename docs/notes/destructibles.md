# Destructibles — enumerate and detonate the map's own breakables. 2026-09-16

Mined offline from the zone manifests + `scripts/core_common/destructible.gsc`. **Nothing measured
in-game.** Unlike [[vehicles]] and [[static-props]] this is a system nothing in the project had
looked at, and it turns out to be one of the cheapest features available: **one call enumerates
every destructible on a map, and one builtin destroys one.**

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
