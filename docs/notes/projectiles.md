# Projectiles — overriding what a weapon fires, and what effects are reachable. 2026-09-15

Goal: turn bullets into rockets / crossbow bolts / anything else, plus tracer and laser effects.
Read out of the T9 dump; **nothing measured in-game yet.**

**Status: RESEARCH ONLY. The override path is clean and fully server-side. The EFFECTS half splits:
FX are reachable, tracers have no script API at all, and beams/lasers are client-side only.**

---

## 1. You do not override the weapon — you intercept the shot

There is no "set this weapon's projectile" call in T9. `setweapontracer`, `launchprojectile` and
`spawnprojectile` all return **zero hits** in the dump. The community-staple approach is the one the
engine actually supports: hook the shot, then fire your own projectile along the same line.

### The hook — `callback::on_weapon_fired`

`callbacks_shared.gsc:899` exposes it, and stock registers it **per player** in
`globallogic_score.gsc:58-66`, inside `playerspawn()`:

```gsc
self callback::on_weapon_change( &on_weapon_change );
self callback::on_weapon_fired( &on_weapon_fired );
self callback::on_grenade_fired( &on_grenade_fired );
```

The handler receives a params struct and reads `params.weapon` (`globallogic_score.gsc:82-85`). Being
registered by core MP scoring is what proves it is live in MP for players — not inferred.

Four callbacks exist in this family, and no more:

| callback | payload |
|---|---|
| `on_weapon_fired` | `params.weapon` |
| `on_grenade_fired` | `params.weapon`, **`params.projectile`** — the entity |
| `on_offhand_fire` | — |
| `on_weapon_change` | — |

⚠ `on_grenade_fired` handing over `params.projectile` is the one place stock gives you a live
projectile entity for free (`globallogic_score.gsc:124` threads it into a `waittilltimeout(10, #"death")`).

### The spawn — `magicbullet`

```gsc
rocket = magicbullet( weapon, startpos, endpos, owner );          // 4-arg
rocket = magicbullet( weapon, startpos, endpos, owner, target );  // 5-arg, HOMING
```

⭐ **It returns the projectile entity** — confirmed at five call sites that assign it
(`killstreaks/straferun.gsc:897`, `remotemissile_shared.gsc:415` and `:775`,
`helicopter_shared.gsc:3276`, `flak_drone.gsc:226`). That return value is what makes effects
possible at all (§3).

⭐ **The 5th argument is a homing target.** `helicopter_shared.gsc:3276` passes `etarget`,
`flak_drone.gsc:226` passes `missile`. Heat-seeking bullets are a free variant of this feature, not
extra work.

The aim vector comes from builtins already verified live in `gunfight_menu`:
`geteye()` + `anglestoforward( getplayerangles() ) * <range>`.

⚠ The damage system knows about these: the inflictor carries `.ismagicbullet`
(`killcam_shared.gsc:1250`, `cp_common/globallogic_player.gsc:2389`), which stock consults when
attributing kills. Worth reading before assuming score/killcam behave normally.

## 2. The weapon namespace is plaintext — unlike vehicles

**342 plaintext `getweapon( #"..." )` names vs only 64 hashed.** The inverse of `vehicle#`
([[vehicles]]), and the same happy situation as `model#` ([[static-props]]). The candidate list is
simply in the dump.

Concrete projectile weapons worth trying:

| weapon | note |
|---|---|
| `launcher_standard_t9` | the MP rocket launcher — the obvious first test |
| `launcher_standard_t8` | BO4 variant |
| `crossbow_special_t8` | bolts |
| `hero_flamethrower`, `hero_bowlauncher` | specialist weapons |
| `remote_missile`, `gunship_missile_armada`, `flak_drone_rocket` | killstreak projectiles |
| `frag_grenade`, `concussion_grenade`, `incendiary_grenade` | thrown |
| `ray_gun`, `raygun_mark2`, `ray_gun_upgraded`, `avogadro_bolt` | ⚠ **Zombies assets** — almost certainly not resident on an MP map |

### Testing whether a weapon exists here — use stock's own sentinel

⚠ `isassetloaded` is used in stock with exactly four asset types — `aitype`, `stringtable`,
`vehicle`, `xanim`. **There is no `"weapon"` and no `"xmodel"` in that list**, so do not assume
either string is valid.

For weapons the proven test is stock's own, used throughout `challenges.gsc`:

```gsc
w = getweapon( #"launcher_standard_t9" );
if ( w != level.weaponnone ) { ... }      // level.weaponnone is the invalid sentinel
```

That is better than `isassetloaded` for this purpose: it is the exact comparison shipped code makes,
at `challenges.gsc:1473`, `:2404`, `:3321`, `:3903`, `:4173` and more.

⚠ **This also applies to [[static-props]]'s probe**, which guesses `isassetloaded( "xmodel", ... )`.
That guess is unverified. Its bogus control catches a *broken* call, but if `"xmodel"` is simply not
a valid type string, both residency bits read 0 and look identical to "model not resident". The
disambiguator is already documented there: a map with rows whose row-0 model reads 0 on **both**
forms means the type string is wrong, not that Treyarch curated a missing asset.

## 3. Effects — this is where it splits three ways

**FX: reachable, server-side. ✅** `playfx` is called from MP gametype `.gsc` files
(`prop.gsc:4336`, `vip.gsc:688`, `dem.gsc:1292` via `spawnfx`, `dropkick.gsc:865`), so a server-only
mod can create networked FX. Effects resolve either by hash (`#"hash_..."`) or by **plaintext path**
through `level._effect[] ` + `fx::get()` — e.g. `prop.gsc:511` sets
`level._effect[#"propdeathfx"] = "destruct/fx9_dest_prop_md"`. Combined with `magicbullet`'s returned
entity, attaching a trail to your own projectile is the realistic route to a "tracer" look.

**Tracers: NO script API. ❌** `setweapontracer` does not exist in T9 (0 hits), and every "tracer"
string in the dump is `traceresult` / `traceresults` — raycasts, not bullet tracers. Tracer style is
a weapon-file property, and weapon files are assets we cannot author. So a tracer is only obtainable
two ways: pick a projectile weapon that already has a visible trail, or attach your own FX to the
projectile entity `magicbullet` hands back.

**Beams / lasers: ⚠ CLIENT-SIDE ONLY — the blocker.** The beam system is
`scripts/core_common/beam_shared.csc`. **There is no `.gsc`**, and every consumer is a `.csc`
(`gadget_tripwire.csc`, `ammomod_deadwire.csc`, `zm_grappler.csc`, the ZM quest scripts).

That puts beams squarely behind **Gate 2, clientfield symmetry** ([[vehicles]] §3, [[game-systems]]):
a vanilla joiner runs stock `.csc` and registers only stock handlers, so a server-only mod cannot
drive a beam that an un-modded client will draw. Same wall the vehicle FX hit, and the opposite of
[[static-props]], where the prop is a plain replicated entity and Gate 2 does not apply.

⚠ So "lasers" as a literal beam is likely **host-only** on this architecture. An FX-based
approximation along the projectile path is the server-side alternative, and it is not the same thing.

## 4. What is genuinely unknown

1. **Does `on_weapon_fired` fire per SHOT on full-auto, and does replacing each one with a rocket
   survive it?** An AR at ~700 RPM is ~12 `magicbullet` calls a second, per player. Nothing in the
   dump bounds that. This is the single biggest risk to the whole feature and it is a measurement,
   not a reasoning problem.
2. **Self-damage.** A rocket spawned at `geteye()` travelling forward may detonate on the shooter's
   own geometry. `.ismagicbullet` suggests stock already reasons about attribution; whether the
   blast hurts the owner is untested.
3. **Which weapons are resident on an MP map.** `level.weaponnone` answers it per weapon per map,
   cheaply, and is the natural probe.
4. **Does the original bullet still fire?** The hook is a notification, not a replacement — the
   real bullet almost certainly still travels. "Turning bullets into rockets" may in practice be
   "bullets **plus** rockets" unless the base weapon is neutered another way.

## 5. Next step — a weapon-residency probe

Same shape as `src/vehicle_probe/` and `src/prop_probe/`: read-only, numbers out, map-gated by its
own dvar. Loop the 342 plaintext weapon names through `getweapon( ... ) != level.weaponnone` and emit
the count, plus per-family counts for the projectile weapons in §2, plus a bogus-name control.

⚠ Do **not** bundle the `magicbullet` test into that probe. Firing projectiles is a **write**, and
this project's convention is one writing test per match (`src/README.md`). Residency first, then a
separate staged test that fires a single rocket on a single shot with the rate-of-fire question in §4
explicitly in view.

---

## 6. ⭐ OFFLINE — weapon residency, answered from the zone manifests. 2026-09-16

§4's open question 3 ("which weapons are resident on an MP map") is a table read, not a probe.
`tables/bgcache/<zone>.csv` carries a `weapon,#<name>` row per resident weapon; a map's set = the
map zone + `core_bootstrap` + `core_common` + `mp_common` (same model as [[vehicles]] §6).

### ⭐ 331 weapons are UNIVERSAL — every projectile this feature wanted, on every map

```
launcher_standard_t9        the rocket launcher       special_crossbow_t9    bolts
launcher_freefire_t9        free-fire launcher        sig_bow_flame          flame bow
special_grenadelauncher_t9  grenade launcher          hero_flamethrower
remote_missile (+_missile, +_bomblet)                 jetfighter_missile
straferun_rockets                                     missile_turret
```

**So "turn bullets into rockets or crossbow bolts" needs no per-map gating at all.** Both the rocket
launcher and the crossbow are in the always-loaded zones. `mp_nuketown6` adds **zero** weapons beyond
universal; Gas Station and Tundra add only hashed ones. The weapon side of this feature is uniform
across all 36 MP maps — unlike vehicles, where 18 maps carry nothing but the streak baseline.

### ⚠ CORRECTION — `crossbow_special_t8` does not exist

§2's table lists `crossbow_special_t8`, harvested from a `getweapon( #"..." )` call in the dump.
**It is in ZERO zones** — a dead reference in script (almost certainly a BO4 leftover; the dump
contains calls for assets Cold War does not ship). The real asset is **`special_crossbow_t9`**,
resident in **19** zones including the universal three.

⚠ Generalise this: §2's list came from `getweapon()` *call sites*, which prove only that some script
mentions a name. **Residency comes from the manifests.** Re-check any weapon in that table against
`bgcache` before building on it — `ray_gun` / `raygun_mark2` / `avogadro_bolt` were already flagged
there as probably-ZM, and this is the mechanism that settles such questions.

### ⚠ FX names are mostly hashed — this constrains the tracer work

`core_bootstrap + core_common + mp_common` carry **1,364 fx / client_fx** rows, but only **66 are
plaintext**; the rest are `hash_*`. So §3's "attach your own FX to the projectile entity" has a much
smaller *named* palette than the raw count suggests, and picking a trail by name means working from
those 66 or resolving hashes (which the ACTS index cannot do for this game — [[vehicles]] §6, 1 of
147). The named universal ones that look trail-shaped are few:
`destruct/fx8_atk_chppr_smk_trail`, `destruct/fx8_atk_chppr_exp_trail`,
`killstreaks/fx8_mortar_jet_contrails`.

⚠ This does not block the feature — `playfx` takes a hash literal exactly as `vip.gsc:688` does
(`playfx( #"hash_6c0862bb0e561d0d", ... )`) — but choosing a *good-looking* trail from hashes is
trial and error, not selection.
