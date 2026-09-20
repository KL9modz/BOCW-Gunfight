# Projectiles — overriding what a weapon fires, and what effects are reachable. 2026-09-15

Goal: turn bullets into rockets / crossbow bolts / anything else, plus tracer and laser effects.
Read out of the T9 dump; **nothing measured in-game yet.**

**Status: RESEARCH ONLY. The override path is clean and fully server-side. The EFFECTS half splits:
FX are reachable, tracers have no script API at all, and beams/lasers are client-side only.**
**2026-09-17: BUILT as the menu's Projectiles page (§7), never run** — weapon_fired → magicbullet,
rate-gated, nine universal projectile weapons, optional homing and trail FX; test sheet in §7.
**2026-09-20: klaze — "never worked" (ON message, then nothing). Bytecode verified = source; DIAGNOSTIC
build (§8): PROJ debug line + six spawn methods incl. EXPLOSIVE ROUNDS (no projectile), one-match test sheet.**

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


---

## 7. BUILT 2026-09-17 — the Projectiles page. Never run.

§5's residency probe is moot (§6 answered it offline), so the staged write is what got built:
Start menu → *Projectiles*, in `gunfight_menu.gsc` (payload 362,812 B; check-gsc PASS, zero notes).

### The shape

- **Hook:** the `weapon_fired` notify the engine raises on the player for every shot
  (`weapons.gsc:1034`, the event_handler that also drives `callback::on_weapon_fired`) — the same
  notify the teleport gun rides ([[teleport]]), with `.weapon` on the result (`placeables.gsc:215`
  reads it). One per-life thread per player who wants it (`proj_think`, re-armed from
  `mod_spawn_place` like the teleport threads), `endon death / disconnect`.
- **Spawn:** `magicbullet( w, start, eye + fwd * 10000, self )` — the 4-arg form of
  `remotemissile_shared.gsc:415` / `straferun.gsc:897`, owner = the shooter so the kill and the
  killcam credit him. `start` = 32 u ahead of the eye, or the eye itself when a wall is closer than
  64 u (§4 q2 — it will then go off in the shooter's face, RPG rules; God mode exists).
- **Homing:** `p missile_settarget( target, ( 0, 0, 0 ) )` (`straferun.gsc:899`'s shape) on the
  living enemy nearest the crosshair inside a ~45° cone (`vectordot` > 0.7), bots included;
  teammates excluded unless the shooter's team is `#"free"`.
- **Rate:** per-player minimum gap, `gettime()`-based, default **300 ms**; the Rate page walks it
  1000 / 600 / 300 / 150 / **0 = every shot**. That last row IS §4's question 1 (an AR at ~700 RPM
  = ~12 `magicbullet`s a second per player) — measure it last, solo first.
- **No chaining:** a shot whose `.weapon` is the projectile weapon itself is ignored, so a rocket
  launcher in hand does not double-fire.
- **Weapons** (the Projectile page; every one universal by §6, and each pick is validated against
  `level.weaponnone` before it lands): RPG rocket `launcher_freefire_t9` (default), Cigma missile
  `launcher_standard_t9`, crossbow bolt `special_crossbow_t9`, M79 grenade
  `special_grenadelauncher_t9`, combat bow arrow `sig_bow_flame`, strafe run rocket
  `straferun_rockets`, cruise missile bomblet `remote_missile_bomblet`, jet fighter missile
  `jetfighter_missile`, frag grenade `frag_grenade`.
- **Trail FX (off by default, untested):** `playfxontag( "destruct/fx8_atk_chppr_smk_trail", p,
  "tag_origin" )` — a plain path the way `infect.gsc:1229` passes one, universal by the `fx` rows.
  The rocket weapons carry their own trails; this is the one line here stock never makes on a
  magicbullet, hence the toggle.
- **Scope:** *Fire mode – host* (`player.gf_proj`), *– everyone* (`game.gf_proj_all`, humans
  only — bots never get it), *Everything OFF*. State is per match on `game.` / the player, not
  dvars: the packed config store and the app's key list are untouched.

App: *Map toys* → Projectiles `host` / `everyone` / `OFF` / `homing` / `trail FX`, a weapon picker
(`gf_cmd_action projweapon`, arg = the asset name — `getweapon` takes the string form too,
`remotemissile_shared.gsc:439`), a rate picker (`projrate`, ms).

### ⚠ Still inferred

1. **Does `magicbullet` itself raise `weapon_fired` on the owner?** If it does, the no-chaining
   check above catches it (the fired weapon would be the projectile weapon); if it raises it with
   the *held* weapon, the rate gate is the only thing between one shot and a runaway. The 300 ms
   default is chosen so a runaway is visible and survivable, not fatal.
2. **The bullet still fires** (§4 q4). This is "bullets plus rockets" until measured otherwise.
3. **Grenade-class weapons through `magicbullet`** (`frag_grenade`, the M79) — stock only fires
   rockets / missiles / bomblets this way; a grenade projectile may arc, sit, or not spawn (the
   `!isdefined( p )` guard just returns).
4. **The trail FX call** — never made on a magicbullet by stock.

### Test sheet — ONE write per match, solo first

| # | do | read |
|---|---|---|
| 1 | Projectiles → *Fire mode – host*, fire ONE shot of a pistol at a wall 20 m away | a rocket leaves with the bullet and detonates at the wall; the feed said `projectiles ON - your shots fire RPG rockets` |
| 2 | fire once with a wall < 1 m away | it explodes on you (or does not damage you — record which) |
| 3 | Projectile → *Crossbow bolt*, one shot | a bolt, not a rocket; then *M79 grenade* — does a grenade-class projectile spawn at all |
| 4 | Fill with bots, *Homing* ON, aim near a bot, one shot | the rocket bends onto the bot; the kill credits you |
| 5 | Rate → *One per 150 ms*, then *EVERY shot*, hold an AR for 2 s | frame rate / hitching; count rockets vs bullets in the killcam. This is §4 q1 |
| 6 | *Fire mode – everyone* with a joiner | the joiner's shots fire rockets; the joiner sees his own rockets (server projectile, plain replication) |
| 7 | *Smoke trail FX* ON, one shot | a second trail, or nothing (the FX call was a no-op), or a script error — record which |

Record: `______`

---

## 8. 2026-09-20 — "never worked" (klaze): ON message, then nothing on any shot. DIAGNOSTIC BUILD.

### What is now proven, offline

- **The compiled bytecode IS the source.** `acts gscd` of the live payload, `proj_think` / `proj_fire`
  read back line for line; every builtin hash resolved with the T89 script hash
  (`magicbullet` 96f15236, `bullettrace`, `geteye`, `getplayerangles`, `anglestoforward`,
  `missile_settarget`, `playfxontag`), the `weapon_fired` / `fraction` / `death` / `disconnect` hashes
  with fnv1a63. `magicbullet` is emitted as a 4-param FUNCTION call, as stock does. Not a compile bug.
- **Everything up to the `waittill` is proven by the teleport gun** (same per-life thread, same
  `endon`s, same `tp_menu_open()` gate, same `weapon_fired` notify — klaze: "teleport gun has worked").
  `getweapon( #"..." )` by hash is proven by the Weapons page (`gave EM2 -> F. Noor`, runbook M1.11).
- **The red "weapon not found" toast is NOT excluded.** `mod_host_say` → `menu_toast` → `iprintlnbold`
  fires from the thread *while the menu is still open* (the toggle runs `proj_rearm` before
  `menu_say`), and the menu's status repaint owns that region — so `getweapon( launcher )` returning
  `level.weaponnone` would have looked exactly like "ON, then nothing".
- **The engine side cannot be read at rest**: `BlackOpsColdWar.exe+3c6b290` (`magicbullet`) is
  Arxan-encrypted on disk (garbage disassembly); it needs the live process (`tools/dvar-live/disasm.py`)
  with the game up — not done this session.
- The Atian **Cold War** port ships no rocket gun (only the BO4 tree does — `launcher_standard_t8`,
  `magicbullet` from `origin + look*40 + (0,0,40)`, owner = player, "to avoid blowing up the player"),
  so there is no community-proven `magicbullet( player launcher, …, player )` on CW to lean on. Stock MP
  only fires killstreak projectile weapons this way (`remote_missile_missile` with a PLAYER owner,
  `straferun_rockets`, `flak_drone_rocket`, `remote_missile_bomblet`); CP fires a launcher
  (`launcher_standard_t9_cp_straight_shot_siege`) with `level.player`.

So the failure is at runtime, after the thread starts, in one of: the weapon lookup (hidden toast), a
runtime error at the spawn call (kills the thread silently — every later shot is "nothing"), the call
returning nothing, or a projectile that spawns and dies on frame 1 / is not drawn. Those four look
identical from the chair. **This build measures which.**

### The build (`payloads/gunfight_menu.projdiag.gscc`, 471,936 B / 2,685 strings; check-gsc PASS zero notes, check-args 0)

**PROJ debug line** — one line to the feed every 3 s, auto-ON with any fire mode (this build
measures), off with *Everything OFF* or the toggle (Projectiles → *Debug line*, Debug page, bridge
`projdbg`). No dvar: `level.gf_dbg_proj` + `level.gf_pj` counters, so the dvar pool is untouched.

```
PROJ mode:host m:1 w:ok(RPG rockets) ms:300 thr:1 shots:N menu:N chain:N gate:N fire:N ret:N threw:N ent:N none:N gave:N blast:N host alive:1 menuopen:0 want:1 last:<what the entity did>
```

| field | meaning |
|---|---|
| `mode` | off / host / all — what the toggles say |
| `m` | spawn method 1-6 (below) |
| `w` | `getweapon( chosen )` right now: `ok` / `NONE` (== `level.weaponnone`) / `undef` |
| `thr` | `proj_think` threads started (1 after the toggle; +1 per spawn) |
| `shots` | `weapon_fired` notifies the thread saw. **Frozen while you keep firing = the thread is dead** |
| `menu` / `chain` / `gate` | shots ignored: menu open / fired weapon is the projectile weapon / inside the rate gap |
| `fire` / `ret` / `threw` | `proj_fire` entered / the spawn call returned / `fire - ret` — **threw:1 = the spawn call raised a runtime error** |
| `ent` / `none` | the call returned an entity / returned undefined |
| `gave` / `blast` | method 3 gave the weapon / method 5 blasts |
| `host …` | alive, menu open, `proj_wanted` for the host |
| `last` | the last spawned entity: `m1 missile mdl:1 d1f:40 d.5s:900 alive:1 …` (classname, moved by frame 1 / 0.5 s / 2.5 s), `GONE after 1 frame`, `gone<0.5s (hit something)`, `m1 returned undefined`, `blast at x y z` |

**Spawn method** (Projectiles → *Spawn method*, bridge `projmethod <1-6>`), read live per shot:

| m | call | discriminates |
|---|---|---|
| 1 | `magicbullet( w, eye+32fwd, eye+10000fwd, self )` | the original |
| 2 | `magicbullet( w, start, end )` — no owner (cp_takedown_raid_apt.gsc:356 form) | a player-owner precondition |
| 3 | `self giveweapon( w )` (silent, no switch) then method 1 | the owner having to own the weapon |
| 4 | `self magicgrenadeplayer( w, start, fwd*1500 )` (traps_deployable.gsc:1135 form) | the other projectile spawner; frag / M79 make sense here |
| 5 | **EXPLOSIVE ROUNDS** — no projectile: `bullettrace` to the impact, `playfx( #"explosions/fx_exp_bomb_demo_mp" )` (universal `fx` row), `playsoundatposition( #"mpl_sd_exp_suitcase_bomb_main" )`, `radiusdamage( pos, 160, 130, 35, self, "MOD_EXPLOSIVE", w )` (raz.gsc:1080 shape), `earthquake` | works by construction — a blast from whatever weapon is held; if THIS does nothing the fault is upstream of the spawn and the counters say where |
| 6 | method 1 from `origin + fwd*40 + (0,0,40)` (the Atian BO4 rocket-gun start) | a projectile dying against the shooter |

The 09-17 weapon list is unchanged and is itself a variant: *Strafe run rocket* / *Cruise missile
bomblet* are weapons stock DOES fire through `magicbullet` in MP — a launcher that fails where those
work is a weapon-class answer.

### Test sheet — one match, solo, Nuketown; screenshot the PROJ line after every step

| # | do | read |
|---|---|---|
| 1 | Projectiles → *Fire mode – host*; close the menu; wait for the PROJ line | `mode:host m:1 w:ok(RPG rockets) thr:1 want:1 menuopen:0`. **`w:NONE`** → that is the bug (the name); pick *Projectile → Strafe run rocket*, re-read `w:` — stop there |
| 2 | ONE pistol shot at a wall ~20 m away | `shots:1 fire:1 ret:1` and then one of: `ent:1 last:m1 missile … alive:1 d.5s:NNN` (spawned + flying; if nothing was visible it is a render question) · `none:1 last:m1 returned undefined` (engine refused → 3) · `threw:1` (the call raised; further shots will not move `shots:` → 3) · `GONE after 1 frame` (killed on spawn → 4) |
| 3 | *Spawn method → 2*, one shot; *→ 3*, one shot; back to *1* + *Projectile → Strafe run rocket*, one shot | for each: `ent` vs `none` vs `threw`, and `last` |
| 4 | *Spawn method → 6*, one shot | as above |
| 5 | *Spawn method → 4* + *Projectile → Frag grenade*, one shot | a grenade arcs out? `last:m4 grenade …` |
| 6 | *Spawn method → 5*, one shot at the wall | a Demolition-bomb explosion at the impact, `blast:1 last:blast at x y z`; then *Everything OFF* |

Record: `______`
