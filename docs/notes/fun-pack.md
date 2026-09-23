# Fun pack — the gaps Project HiNAtyu's menu showed us. 2026-09-23

klaze (2026-09-23): *"i am also working on a fun mod menu gamemode so lets take everything we dont have.
im especially curious about Modded bullets · Change bullets type, bind no-clip, Advanced forge mode,
Super slide, Disco camouflage, model menu, vehicles menu, fast restart."*

**Status: ⚠ built 2026-09-23 in `gunfight_menu.gsc` (the FUN PACK section), NEVER RUN.** Offline:
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

State is per MATCH on `game.` / player fields (the projectile / teleport-gun convention). **No new
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
- **Aimbots** (5 toggles) and **ESP** — ⚠ left out on purpose pending klaze's call: in a friends' lobby
  they only work on the other players, and "stealth aiming" exists to hide it from them.
- PHA's rank system (Verified → Host, per-menu gating) — ours grants whole client menus instead.
- PHA carries ~80 more translated feature names (Perks / Visions / Design menus, jet pack, thunder gun,
  walking AC-130, ACE COMBAT, attractions, tactical nuke…) with **no code** — MW2019 leftovers, nothing to take.

## Untried — not ruled out
- Tilt and motion **persisting** across rounds: extend the `game.gf_forge` record (the app reads it —
  version the format first).
- A second prop-gun mode that places **at** the impact (walls, ceilings) instead of floored.
- Disguise model **cycling on a button** while disguised (Prop Hunt's own change-prop key).
- The model cannon with `physicslaunch` instead of `moveto` (props that tumble and bounce).
- Grenade swap per grenade slot (lethal vs tactical) — `res.weapon` tells them apart.
