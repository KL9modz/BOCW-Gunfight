# Fun pack — the gaps Project HiNAtyu's menu showed us. 2026-09-23

klaze (2026-09-23): *"i am also working on a fun mod menu gamemode so lets take everything we dont have.
im especially curious about Modded bullets · Change bullets type, bind no-clip, Advanced forge mode,
Super slide, Disco camouflage, model menu, vehicles menu, fast restart."*

**Status: ⚠ built 2026-09-23 in `gunfight_menu.gsc` (the FUN PACK section), NEVER RUN.** Fun pack 2
(2026-09-24: ESP, projectile method 7, cannon ride, forge spray / auto-link / spin speed, and the
round-persistence fix) is [below](#fun-pack-2--what-phas-forge-and-projectile-code-taught-2026-09-24),
same checks, same result. Offline:
`check-args.py` 0 mismatches; `check-dump.py` 37 fatal / 3 unused-by-stock — **identical to before
the change**. The 37 are words inside strings and comments that the checker reads as calls
(`vehicle()`, `you()`), and the fun pack adds none. Every builtin it calls has a stock caller. Every
function it calls is defined, brackets balance, and there is no unary minus on an expression (ACTS rejects
it). `gf-panel` builds. Stages 1–2 (ACTS compile + round-trip) still need the Windows box.

## Where it came from — and what was NOT taken

The reference is **PHA V1.00** (`ProjectHiNAtyu/T9_BOCW_GSC_Wiki`, `ModMenu/PHA_BOCW_V100/Compiled/
ProjectHiNAtyu_V1_BOCW.gscc`, 335,200 B, sha256 `9c249c6b…c456`, dated 2024-05-01). ⚠ That repo
**does** ship a ready-to-inject compiled menu; only its source is withheld.

It was read with a scratch VM38 disassembler built on ACTS's opcode table (`gsc_opcodes_t9_38.hpp`),
verified by construction: every string and import reference in a decoded function lands on a decoded
operand (1,276 / 1,276 in the menu builder, 1,974 / 1,974 in the label table). That gave the full menu tree, its
English labels and the builtins behind each feature. **Nothing is transcribed.** Every feature here
is rebuilt from stock's own call shapes and this file's helpers, and the stock precedent is cited on each.

### What the menu ALREADY had (not duplicated)
| PHA | ours, before today |
|---|---|
| Bind noclip / "all axes advanced noclip" | Movement → **Fly mode** (`fly_think`: forward follows the view pitch, so all axes). Missing: only the bind |
| Modded bullets + bullet type | Projectiles page: 9 weapons, rate, 6 spawn methods incl. explosive rounds, homing, trail (mid-diagnosis, run 2 pending) |
| Advanced forge: place / get / delete / scale / change model / trace length | Forge mode (grab/move/delete, ours or the map's) + Props build mode (preview, cycle 423 props, scale, undo, round-persistent layout) |
| Vehicles menu | Vehicles → spawner, per map, `isassetloaded`-gated, liveries, vehicle mode |
| Fast restart | Round → **Restart match** (`map_restart()`); the round replay existed only as the app verb `restartround` |
| Teleport gun, save/load location, freeze, teleport to me/him, godmode, third person, invisible, max ammo | Teleport, Players, Player, Operator pages |

## What was added

| Feature | Menu | Mechanism (stock precedent) | Unknown until run |
|---|---|---|---|
| **Fast restart** | Round → *Fast restart* | `round_restart()`: `map_restart( true )` (PHA's `map_restart( 1 )`) + stock's transition steps + the vehicle sweep — already the app's `restartround` | whether every client reloads cleanly (the F-series restart caveats apply) |
| **Fly bind** | Movement → *Fly bind: Tac + Melee* | TACTICAL + MELEE toggles `fly_think` with the menu closed; ignored while the menu is open, forging, or in a vehicle. Per player (menu target), kept across lives | whether holding Tactical starts a throw that Melee cancels cleanly (PHA ships the same combo) |
| **Slide** | Movement → *Slide* → speed 150/200/300 %, *Long slide*, *Super slide* 600/1000/1600, *No chain penalty* | `issliding()` edge per life ([[slide]] §3 lever 1, `slide_probe`'s boost + hold); super slide = PHA's idea with a fixed speed: glide along the view until JUMP (6 s cap, humans only); chain = `slide_subsequentslidescale 0` (lever 2) | slide.md's own questions: does `setvelocity` at the start stick; joiner prediction; the dvar on clients |
| **Disco camo** | Camo → *Disco camo* / *everyone* / *all OFF* | the Camo page's own `setcamo( getcurrentweapon(), id )`, a random row 1–121 every 0.2 s (PHA: 0–149 every 0.15 s) | visible flicker vs weapon-model churn; joiners see it (options are server state) |
| **Disguise** (PHA "Models menu / Set model") | Player → *Disguise* → random / next / previous / 6 quick picks / size 0.5–4x / height / OFF | Prop Hunt's recipe (`prop.gsc` `setupprop` :1932–2002): non-solid, no-collision `script_model` linked to the player, player `ghost()`ed + third person; `show()` undoes (:2695); stock spawn shows every player again (`globallogic_spawn.gsc:421`) so death only deletes the prop. Models = `prop_master()` (423 universal props, `isassetloaded`-gated) | whether the ghosted player's gun still renders; whether bullets hitting the prop hurt the player (they hit the player's own hitbox, which is where the prop is) |
| **Forge tools** | Forge mode → *Forge tools* | on the aimed prop (else our prop nearest the aim line — reaches non-solid ones — else the last placed): spin yaw/roll/pitch (`rotateyaw/roll/pitch` loop on the prop), bob up/down, slide left/right / fwd/back (`moveto` loop — moving platforms), link to previous (`linkto`, rides its spin/move), solid on/off, delete. **Tilt new props** (flat / 45 / side / upside down / nose up) feeds the preview. **Prop gun**: every shot places your forge pick where it lands, 250 ms apart, cap 200 props | whether a moving `script_model` carries a player standing on it (the elevator idiom says yes); motion + tilt are **not saved** across rounds (the layout save keeps position / yaw / scale) |
| **More modded bullets** | Projectiles → *Shots per trigger* 1/3/5/8; *Projectile* + War Machine grenade, cruise missile, Hand Cannon, Death Machine, ballistic knife, napalm bomb, artillery shell | extra spawns per trigger jittered ±6° (default 1 = the tested single spawn, unchanged); the 7 weapons are all `core_common` (bgcache: every MP map). `hero_pineapplegun` joins `proj_is_nade` (run 1: a launcher round via `magicbullet` drops at the feet) | which of the 7 fly via `magicbullet` (the M79 lesson says grenade-class ones need AUTO) |
| **Grenade swap** (PHA "Modded grenades") | Projectiles → *Grenade swap* → me / everyone / off; *Swap to* Molotov, Semtex, Frag, C4, Stun, Flash, Smoke, Hatchet, M79, War Machine, Monkey bomb ? | on `grenade_fire` (`{ projectile, weapon }`, `weaponobjects.gsc:2251`) delete the thrown grenade and `magicgrenadeplayer( w, origin, view × speed )` (stock's player-owned spawner, `dev.gsc:2570`) | C4 may sit undetonatable; the monkey bomb is a Zombies item resident in MP (`core_common`) — may be inert |
| **Model cannon** (PHA "Full customize bullets") | Projectiles → *Model cannon* (+ *Blast on impact*, *Keep landed props*, *Cannon model*: forge pick / chicken / oil drum / couch / mannequin / energy portal) | each shot launches a non-solid prop from the muzzle to the impact (`moveto`, 1500 u/s) as a level thread; blast = the explosive-rounds calls (fx + sound + `radiusdamage` + `earthquake`); vanish after 5 s unless Keep | none structural — all calls are already in the file |
| **Vehicles** | Vehicles → spawner (other residents) | 9 rows **appended** to `veh_master()` (indices 67–75, `Catalog.cs` synced): `heli_ai_mp`, `veh_missile_turret`, `veh_ultimate_turret` (all maps — [[vehicles]] §7 had named them), `hash_444804d03bdda785` "Drone squad", `hash_7dd2944ddf7cc7e9` "RC-XD streak" (all maps, PHA's names), and four Fireteam-only hashes. PHA's other ~50 rows are campaign / Zombies assets **no MP zone loads** (`docs/data/map-assets.json`) — the noise §7 already removed | every kind-1 caveat: may not be enterable |

State is per MATCH: "everyone" switches on `game.`, per-player ones in **`pers`** (`pflag`). 🪦 As first
shipped the per-player ones were entity fields (`p.gf_disco`…), and **Gunfight's round boundary is
`map_restart( 1 )`** (`globallogic.gsc:2058`), which frees every entity field — so a "me" switch lasted
one round. Fixed in fun pack 2; `pers` is what stock carries across rounds (`pers[ #"team" ]`). **No new
dvar** — the GSC-VM dvar pool is what crashed at 72 registrations.

## Test sheet — one match, host + bots, then one joiner

| # | do | expect | record |
|---|---|---|---|
| 1 | Round → *Fast restart* mid-round | the round replays, the score is unchanged, bots return | ______ |
| 2 | Movement → *Fly bind*, close the menu, hold Tactical + tap Melee, twice | fly ON then OFF, one feed line each; no grenade thrown | ______ |
| 3 | Movement → Slide → *Slide speed 200%*, sprint + slide on flat ground | clearly longer slide; then *Long slide* ON → longer still | ______ |
| 4 | *Super slide 1000*, slide, look left/right, then JUMP | you glide and steer; JUMP stops it | ______ |
| 5 | Camo → *Disco camo* | the gun cycles camos ~5×/s; no reload interruptions | ______ |
| 6 | Player → Disguise → *Chicken*, walk, crouch, look around; then *Size 2x*, *Raised 20*, *Disguise OFF* | a chicken follows you in 3rd person, you are invisible; OFF = you again, 1st person. **Does your gun float?** | ______ |
| 7 | Disguise a bot (Players → pick → Player → Disguise → *Random prop*), shoot the prop | the bot takes damage | ______ |
| 8 | Props: place a crate; Forge mode → Forge tools → *Bob up/down* while standing on it | the crate rises and falls **with you on it** | ______ |
| 9 | place a second prop, aim at it, *Link to previous*; *Spin yaw* on the first | the second rides the first's spin | ______ |
| 10 | Forge tools → *Prop gun*, shoot a few walls/floors | a prop per shot, on the floor under the impact | ______ |
| 11 | Projectiles → Shots per trigger *5*, fire mode host, RPG | 5 rockets per shot, fanned | ______ |
| 12 | Grenade swap → *Swap to* Molotov → *Swap*; throw a frag | a molotov lands where the frag would | ______ |
| 13 | Model cannon ON + *Blast on impact*, cannon model *Chicken*, fire | chickens fly and explode at the impact | ______ |
| 14 | a Collateral / Crossroads map: Vehicles → spawner → the new rows | which spawn, which are enterable | ______ |
| J | a joiner, steps 3–6, 8, 13 | what the joiner sees (props, disguise, disco, slide snap) | ______ |

## PHA features still not in the menu — the next pass
From the decoded V1.00 tree (20 top-level menus). Reachable in PHA, absent here:
- **Combat assist:** Demigod (distinct from godmode), Infinity remaining ammo (clip), Movement speed 1.25×
  (we have 50–300 %), Always normal / advanced UAV (the `g_compassShowEnemies` flag, [[hud-channels]]), Suicide.
- **Funny:** Create clone player (`cloneplayer`), Ninja mode, Save & load location **on buttons**
  (we have the menu rows).
- **Weapons:** Random camouflage / attachment toggles, Give random weapon, Take weapon / take all.
- **Custom weapons:** Rocket ride (ride your own rocket).
- **Custom killstreaks:** Kamikaze bomber (+ model / spin / random), Vanguard airstrike, Pokemon ball.
- **Game settings:** Pause timer (PHA's is a hack: `hostmigration::locktimer` + a fake
  `host_migration_end`; ours, Host → *Pause*, is stock's esports pause, built, never run — do not copy),
  **Michael Myers** (a hide-and-seek mini-mode: one hunter, unarmed survivors, 10 s to hide, the last
  survivor gets a gun).
- **Messages:** a looping broadcast (we have held banners).
- **Aimbots** (5 toggles) — ⚠ still left out pending klaze's call: in a friends' lobby it only works on
  the other players, and PHA's "stealth aiming" exists to hide it from them. (**ESP** was klaze's call
  2026-09-24 — built, fun pack 2 below.)
- PHA's rank system (Verified → Host, per-menu gating) — ours grants whole client menus instead.
- PHA carries ~80 more translated feature names (Perks / Visions / Design menus, jet pack, thunder gun,
  walking AC-130, ACE COMBAT, attractions, tactical nuke…) with **no code** — MW2019 leftovers, nothing to take.

## Fun pack 2 — what PHA's forge and projectile code taught (2026-09-24)

klaze: *"Can we learn anything from their forge mode or projectiles? Add ESP"*. **⚠ Built, NEVER RUN.**
Same offline result as the first pack: `check-args` 0 mismatches, `check-dump` the **identical** 37 / 3
set (diffed name by name against the previous commit), every call and function pointer resolves,
brackets balance, `gf-panel` builds.

### What PHA's code showed, and what was taken
Read from the decoded functions, not the labels. Four things we did not know or did not do:

| # | PHA does | the stock precedent behind it | adopted as |
|---|---|---|---|
| 1 | its weapon table types exactly four projectiles `"Missile"` — jet fighter missile, napalm bomb, artillery shell, stun grenade — and spawns them with **`magicmissile`**, never `magicbullet` | stock spawns each of those four **only** with `magicmissile`: `jetfighter.gsc:571` (unit **direction** + target — the missile flies itself), `planemortar_shared.gsc:582` (velocity `( 0, 0, -5000 )`), `napalm_strike_shared.gsc:392` (velocity), `_prop_controls.gsc:1577` (Prop Hunt's stun, `fwd * 60`) | Projectiles → Spawn method **7 magicmissile**; **AUTO** now routes those four to 7 (`proj_is_streak`) with stock's own argument shape per weapon; *Stun grenade* added to the Projectile list |
| 2 | `setteam( owner.team )` on every spawned projectile | stock does the same to its streak projectiles (`jetfighter.gsc:574-575`, napalm `:409-410`) | method 7 sets `.team` + `setteam` |
| 3 | scripts the **payload**: on `projectile_impact_explode` / `explode` / `entitydeleted` / `crashing`, the jet missile gets `radiusdamage( origin, 500, 500, 25, owner, "MOD_PROJECTILE", weapon )`; the napalm bomb gets `spawntimedfx` fire | stock's jet missile only **detonates on its locked target** (`jetfighter.gsc:587` `function_644ef4bf`); stock napalm lays `spawntimedfx` fire (`:627`) and burns through its **own** damage loop, not the weapon | `proj_impact`: jet missile = PHA's radius + our blast FX; napalm = stock's **land** fire weapon (`:583` — PHA uses `:584`, the **water** variant, a bug) for 6 s + our `radiusdamage` burn ticks, `MOD_BURNED`. Frame-polled, not `waittill` — a waittill on an entity deleted at impact never returns |
| 4 | the model cannon **rides a real rocket**: `prop linkto( projectile )`, wait for the projectile's death, unlink (its generic `f_0a3f5326`) | — (PHA's own idea) | Model cannon → **Ride a real rocket**: `magicbullet` an RPG, link the prop to it, land it where the rocket died; the tween stays the fallback |
| 5 | Advanced forge: **spawn interval** 0.01–1 s (hold to keep spawning), **auto-link on spawn**, **18 spin modes** (3 axes × ±360° × 1/2/3 s a turn), combine (link to the previous — we had it) | — | Forge tools → **Spray – hold Fire** (off / 0.5 / 0.25 / 0.1 s, quiet, capped at 200 props like the prop gun), **Auto-link new props** (a **star**: the first prop placed is the base, later ones ride it — PHA chains them, where one delete breaks the chain), **Spin speed** 1/2/3 s + **Reverse spin** |

Not taken: PHA's "Rotate X axis" (our tilt rows cover it), its "Bullet trace length" (our pin mode's
distance), and 0.01 s spray (100 props a second eats the entity pool; 0.1 s is the floor here).

### ESP — three layers, three engine paths
PHA's ESP is one call: `self killstreaks::thermal_glow( 1 )`. Reading the client side of that call showed
why it may do nothing, so the menu carries it **plus two stock layers that do not share its gate**.
Player → **ESP**: *Glow*, *Markers*, *Radar* — each for me (the menu target) or everyone (humans), and
*ESP: all OFF*; a client's page gets one **ESP** row that flips all three for that player.

| layer | mechanism | why it might fail |
|---|---|---|
| **Glow** | `killstreaks::thermal_glow( 1 )` → the `toplayer` clientfield `thermal_glow`, whose CSC callback (`killstreaks_shared.csc:131`) puts render-override bundle `#"hash_2c6fce4151016478"` on every **enemy** (the filter drops teammates — there is no all-players glow) | ⚠ the filter's gate is the engine builtin **`function_266be0d4`**, cracked here to **`islocalclientthermalallowed`** (32-bit t89scr hash, 124,509 candidates; P(false hit) ≈ 1e-4). Stock only ever sets the field **inside a streak camera** (AC-130, Cruise Missile). Whether "thermal allowed" is true in plain first person is **the test**. Also skipped client-side: enemies with `specialty_nokillstreakreticle`, under killstreak spawn protection, and caster view |
| **Markers** | Prop Hunt's player marker (`prop.gsc:4645-4646`: `objective_add( id, "active", origin, #"escort_goal" )` + `objective_onentity`), `setinvisibletoall` + `setvisibletoplayer` per viewer (`spy_skill.gsc:1777-1784`). One id per **target**, shared by every viewer on the other side; ≤ 1 per player of the 64-id pool | the `escort_goal` icon **did** render on our race gates (klaze run 1) — unknown: whether it reads well on a moving player, and whether it shows through walls (objective icons normally do) |
| **Radar** | `setclientuivisibilityflag( "g_compassShowEnemies", 2 )` — the value stock writes when forceradar is 2 (`player_connect.gsc:467`); OFF restores stock's value | Gunfight's minimap may draw enemies differently from TDM's; connect resets it every round (`:471`), so it is re-set per spawn |

⚠ **Two mechanics the glow needed that PHA does not handle:** the client **stops** the bundle on every
player that spawns (`killstreaks_shared.csc:284`) and re-applies it only when the viewer's field
**changes** — so after spawns every glow viewer gets a 0 → 1 pulse, debounced to one per round start
(0.75 s after the last spawn); and `map_restart( 1 )` resets the field each round. PHA sets it once, so
by the client code its ESP (if the gate is open at all) loses each enemy's glow at that enemy's next spawn.

⚠ **Everyone sees their own ESP only.** It is a host-granted switch in a private lobby: tell the lobby
it is on — the same courtesy as every other visible mod here. The glow and radar are client-side reads
of server state; nothing about them hides.

### The test sheet, fun pack 2 — one match, host + bots
| # | do | expect | record |
|---|---|---|---|
| E1 | Player → ESP → **Glow**, look at a wall with a bot behind it | the bot glows through the wall — **or nothing** (the `islocalclientthermalallowed` gate) | ______ |
| E2 | let a round end with Glow on; round 2 | the glow comes back on every enemy ~1 s after spawns | ______ |
| E3 | **Markers** | an icon over each enemy bot, none over teammates; follows them; gone when they die | ______ |
| E4 | **Radar** | enemies stay on the minimap without firing | ______ |
| E5 | *ESP: all OFF* | glow, icons, radar all gone | ______ |
| P1 | Projectiles → Projectile *Jet fighter missile*, method *0 AUTO*, fire at a wall near a bot | the missile flies (PROJ line `m7(auto)`), a big blast at the hit, the bot dies inside ~500 u | ______ |
| P2 | *Napalm bomb*, AUTO | fire on the ground for ~6 s that hurts a bot standing in it | ______ |
| P3 | *Artillery shell* / *Stun grenade*, AUTO | a shell / a stun flies where you aim (was magicbullet before) | ______ |
| C1 | Model cannon ON + **Ride a real rocket**, fire | the prop flies with an RPG rocket's arc and speed and lands where it exploded | ______ |
| F1 | Forge tools → Spray *Every 0.25 s*; in props mode hold Fire and sweep the floor | a prop every 0.25 s along the sweep; stops at 200 with one message | ______ |
| F2 | *Auto-link new props* ON, place 4 props, aim at the first, *Spin yaw* | all four turn together around the first | ______ |
| F3 | Spin speed *1 s*, *Reverse spin*, Spin yaw | a fast turn the other way | ______ |
| R1 | turn on *Disco camo* (me) and *Fly bind*; play into round 2 | both still on in round 2, rows still ticked (the pers fix) | ______ |
| J | a joiner with ESP granted from their page | E1–E4 on the joiner's screen | ______ |

## Untried — not ruled out
- **`thermal_glow_enemies_only`** — a second `toplayer` field (clientfield version 12000, bundle
  `#"hash_53798044d9a468d7"`), registered on both sides with **no stock caller**. Same gate; try it if E1
  shows nothing and the bundle is the suspect rather than the gate.
- A GSC-side setter for the thermal gate. One hash cracked to `client_thermalallowed_on` (`0x2ffa8aaf`, a
  1–3-arg method) but it has **no stock caller** and the name is odd — likely a false positive at that
  candidate volume (≈0.7 %). Untested either way.
- Coloured ESP markers: `objective_setteam( id, target.team )` may paint enemies red; other stock marker
  types (Spy's wanted icon `#"hash_27a9c9216bd5cfeb"`).
- Stock napalm **damage** through its own registry (`level.napalmstrike.var_9bac810c`) instead of our ticks.
- Tilt and motion **persisting** across rounds: extend the `game.gf_forge` record (the app reads it —
  version the format first).
- A second prop-gun mode that places **at** the impact (walls, ceilings) instead of floored.
- Disguise model **cycling on a button** while disguised (Prop Hunt's own change-prop key).
- The model cannon with `physicslaunch` instead of `moveto` (props that tumble and bounce).
- Grenade swap per grenade slot (lethal vs tactical) — `res.weapon` tells them apart.
