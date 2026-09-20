# Vehicle racing modes — scope of the tools (2026-09-19)

> **Status: prototype 1 BUILT (2026-09-19), NOT run in-game.** Side payload
> `C:\bocw\payloads\gunfight_menu.race.gscc` (421,687 B / 2,383 strings after run 1 fix, check-gsc PASS zero notes,
> check-args 0 mismatches; it also carries the death-barrier switch). The live slot is untouched.
> §7 says what is in it and how to test; every mechanism below is a stock shape found in the dump
> or a builtin in the engine table, with the file:line that vouches for it; the column *needs
> measuring* is what the first match has to prove. Reuses the menu's vehicle tools
> ([[vehicle-mode]], [[vehicles]]), teleport ([[teleport]]) and the round-end path the timer already uses.

klaze: *"lets look into creating some fun vehicle racing modes. lets start with scoping the tools
needed. how could we craft a race track boundary and have a finish line decide the result?"*

## 0. The shape in one paragraph

A race is a **Free-for-all (`dm`) match** — see §6 for why not a Gunfight round: klaze wants the
stock FFA victory screen (1st / 2nd / 3rd), and FFA is the mode whose placement is per player. The
menu reaches it through its own session switch (*Free-for-all* is on the gametype page) and already
runs in every MP gametype (movement, vehicle mode, bots, the bridge). A **track** is an ordered list of **gates** — a gate is
two posts (a segment across the road) — the first gate is start/finish, the rest are checkpoints.
The **boundary** is the corridor between consecutive gate centres, a width per segment; leaving it
is "off track". The **finish line decides the result** by geometry: each racer's position is
checked every server frame against the next gate's segment, a sign flip with the crossing inside the
segment = gate passed; passing gate 0 after the last checkpoint = lap; lap N = finished. The first
finish starts the **finish timer**; the match ends when everyone has finished or that timer runs
out, through stock's own score-limit ending (§6), so the stock FFA end screen shows the placement.
**Zero map entities are required** for
any of that — it is arithmetic on `.origin` — which matters because bocw-c2 is chasing a Miami
resource-limit crash and every spawned entity/string is a suspect. Markers, walls and kill zones are
optional decoration on top, each with a stock spawnable behind it.

## 1. Tool inventory

| # | Tool | Stock mechanism | Precedent (file:line) | Needs measuring |
|---|---|---|---|---|
| T1 | **Where is the racer** | rider → `player getvehicleoccupied()` (the vehicle entity) else the player himself; `.origin` each frame; speed `veh getspeedmph()` for the HUD | `player_snowmobile.gsc:61`, menu `tp_place` (`getvehicleoccupied`) | nothing — all in use already |
| T2 | **Gate crossing** (finish line, checkpoints) | pure math: side = sign of the 2-D cross product of (B−A) × (P−A); a flip from behind to ahead with the projection of P inside [A,B] = crossed. Sub-frame time: interpolate the flip fraction between the two frames' positions | none needed; the overtime zone already does `istouching` on a spawned `trigger_radius` (`gunfight_menu.gsc mod_zone_synthesize`, `ctf.gsc:637` shape) as the entity alternative | frame rate of the check: 50 ms server frame vs a bike at ~1000 u/s ≈ 50 u/frame — the sign flip cannot miss it, only the timestamp needs the interpolation |
| T2b | Gate crossing, entity variant | `spawn( "trigger_box", origin, spawnflags, width, length, height )` or `trigger_radius` + `istouching` / `waittill( "trigger" )`; vehicles do get trigger touches (`killstreak_vehicle.gsc:591` `waittill( #"touch" )`) | `mechz.gsc:1363` (box), `ctf.gsc:637` (radius) | whether a spawned box can be rotated (none of the callers rotate one) — the math gate has no such limit, so T2b is the fallback, not the plan |
| T3 | **Boundary** = corridor math | distance from P to the segment between gate centres i and i+1 (plus the two adjacent segments) > half-width → off track. Response ladder: warning line → countdown → **reset to the last gate** (T6) or slow (`setmaxspeedscale`, `amws.gsc:149-154`) | none needed | the width that feels right (400–800 u on a road) |
| T3b | Boundary = stock OOB kill zones | `trigger = spawn( "trigger_radius_out_of_bounds", origin, 0, radius, height ); trigger thread oob::run_oob_trigger();` — the stock "RETURN TO THE COMBAT AREA" warning + countdown + kill, at runtime, one per infield / corner-cut zone. Needs `gf_oob` = 0 for the race | `mp_nuketown6.gsc:35-36`, `mp_raid_rm.gsc:26`, `mp_miami_strike.gsc:22` | only radius zones exist in the dump (no box OOB spawn seen); one **shadow trigger per racer** moved under him while T3 says "off track" would put the stock HUD on the math boundary — untried |
| T3c | Boundary = physical walls | `spawncollision( "collision_clip_wall_256x256x10", "collider", origin, angles )` — 44 collision models resident in every match (`tables/bgcache/core_common.csv`): clip / physics / bullet / nosight walls 32–512 u, blocks, ramps, spheres, cylinders | `mp_hijacked_rm.gsc:15-18`, `mp_nuketown6.gsc:34`, `mp_raid_rm.gsc:31-34`, `mp_slums_rm.gsc:18-22`; builtin `spawncollision` 4 args | **which family stops a Havok vehicle** — `collision_clip_*` (player clip) vs `collision_physics_wall_*`; and the entity budget: a 3000 u corridor walled both sides at 256 u = ~24 entities |
| T3d | Boundary look | Props page models that read as a track: `p9_rm_zoo_hay_bale_sqr`, `p9_nt6_barricade_tire_01`, `p9_ger_kgb_mount_barrier_concrete_144`, `p9_rus_oil_drum_01`, `p9_lat_hedgehog_metal_snow`, `p9_usa_street_light_01` (all `isassetloaded`-gated, [[static-props]]) — visual only unless paired with T3c | menu Props page | whether a spawned `script_model` collides with a vehicle at all (Prop Hunt props are `notsolid()`d on purpose, so assume not) |
| T4 | **HUD** | the persistent hint banner (`broadcast_hint_make`, per player, free text): `LAP 2/3  P1  0:42.1`; `iprintlnbold` for 3-2-1-GO and "FINISH — name"; `iprintln` ranking at the end; 3-D / compass markers on the next gate: `objective_add( id, "active", origin, icon )` with `gameobjects::get_next_obj_id()` | `deathicons.gsc:96-98` (`#"headicon_dead"`, proven every match), `prop.gsc:4645` (`#"escort_goal"`), `sd.gsc:724` (`#"sd_waypoint" + label`), `gunfight.gsc:1004` `objective_setprogress` | which icon names render for us; `objective_setvisibletoplayer` per racer so each sees his own next gate |
| T5 | **Start** | grid = rows behind gate 0 along its normal; one vehicle per racer `spawnvehicle( key, spot, angles )` + `usevehicle( player, 0 )` (vehicle mode's exact shape); hold: `setbrake( 1 )` / `setmaxspeedscale( 0.1 )` until GO, or the pause's `freezecontrols` layer | `gunfight_menu.gsc` `cmd_vehspawn` / `mod_spawn_vehicle`, `spawning_squad.gsc:1578`, `amws.gsc:154` | whether `freezecontrols` holds a driver (or only the brake does) |
| T6 | **Reset / respawn to last gate** | a vehicle is a plain entity to `util::teleport`: `.origin = pos; .angles = ang` (`util_shared.gsc:7120-7121`) + `setvehvelocity( (0,0,0) )` (`exfil_chopper.gsc:162`); the rider moves with his seat | | an occupied physics vehicle moved by `.origin` — never done here; fallback = dismount, `tp_place` the player, respawn a vehicle (all in use) |
| T7 | **Result** | placement = finishing order, written into the fields stock's FFA placement sort reads (`pointstowin`, then `score`), then stock's own score-limit ending: `round::function_870759fb(); thread globallogic::end_round( 3 );` — byte for byte what `default_onscorelimit` does (`globallogic_defaults.gsc:209-219`). §3 has the whole flow | `globallogic.gsc:3548-3600` `updateplacement` (FFA sorts by `pointstowin` desc, then fewer deaths, then later `lastkilltime`); `globallogic_score.gsc:1129` `setpointstowin`, `:1025` `_setplayerscore`; `dm.gsc:62-71` `onendgame` → `match::set_winner( top player )`; `display_transition.gsc:605-625` the TopSquad row = `getplayers( winner's team )` sorted by `.score`, top 6 (5 shown, `lui-source mp_common_1177_028d0c80.lua:30` `setHorizontalCount(5)`) | that synthetic scores drive the stock FFA end screen exactly like kills do (step 1 of the prototype); the FFA time limit must not expire mid-race (the `gettimelimit` hook, installed for `dm` too) |
| T8 | **Track authoring** | in-game: drive to a spot, one menu press = gate at the vehicle, perpendicular to its yaw, width W (default 600); undo / clear / show. Store: `game.` for the match + one dvar per gate for the launch (`gf_gate0..15`, ~"x,y,z,yaw,w" ≤ 40 chars, 16 dvars is nothing against the 4096 pool) + publish as a `GFTRACK` marked string for the app (the `GFMAP`/`GFCFG` channel shape, `mapdata_publish`), and the app pushes a saved track back one gate per bridge command (`set gf_cmd_arg "x,y,z,yaw,w"` < 47 B, [[bridge-command-limit]]) | [[map-data-spawn-keys]] channel, [[hud-and-control-app]] bridge | dvar string length for a gate (unknown ceiling; keep each ≤ 40 chars) |

Not in the inventory on purpose: bots cannot drive (`drivepath` is AI-vehicle node-path driving,
`vehicle_shared.gsc:825` — a scripted pace car is conceivable, not a racer); the map's own vehicle
node paths are for scripted vehicles, not roads.

## 2. Boundary — the recommendation

**Corridor math (T3) as the rule, walls (T3c) only where a corner needs a physical stop, OOB zones
(T3b) for cut-through infields.** Reasons: zero entities; works for any vehicle, on foot and in fly
mode (the mechanic is entity-agnostic, so foot races come free); no dependence on which collision
family stops a vehicle; the response is ours (warning → reset to last gate, like every arcade racer)
instead of the stock death. Walls are the visible, satisfying option for a few key spots — add them
after T3c's collision test says which model family a bike bounces off.

The reset (T6) is the one piece with no stock precedent on an occupied vehicle, so the prototype
carries the fallback (dismount → `tp_place` → fresh vehicle) and the test says which survives.

## 3. Finish line — how the result is decided (klaze's spec, 2026-09-19)

*"a timer begins when the first person crosses the finish line and the match ends when either
everyone crossed or the timer ends. the results would show like a free for all style victory
screen showing 1st 2nd and 3rd."*

1. Gate 0 is start/finish. Each racer holds `lap`, `next_gate`, `last_gate_pos`, `last_side`.
2. Every server frame: `side = cross2d( B - A, P - A )` for the next gate; if `last_side < 0 &&
   side >= 0` and the projection `t` of P on AB is within [0,1] (plus half a vehicle length of
   slack) → gate passed: `next_gate++`; if it wrapped to 0 → `lap++`, lap time from the
   interpolated crossing.
3. `lap == laps` → **finished**: place = finish order, time = interpolated crossing. Bold print
   `P1 NAME 1:23.4` to everyone; the banner keeps the running top three.
4. **The first finish starts the finish timer** (`gf_race_grace`, say 45 s). It is shown on the
   stock match clock: the menu's `level.gettimelimit` hook (today Gunfight-only) is installed for
   `dm` too and its cache is set to *elapsed + grace* at that moment, so the HUD clock drops to the
   grace countdown and stock's own `checktimelimit` fires `level.ontimelimit` at zero — no timer
   thread of ours. Before the first finish the cache holds a far value so the FFA time limit cannot
   end the race early.
5. **Race over** = everyone finished, or `level.ontimelimit` fires (the grace ran out), or nobody is
   left driving. Then, in this order: unfinished racers get a progress rank (laps, gates, distance
   to the next gate); every racer's `pointstowin` and `score` are set so the order is strict
   (1st highest, last >= 1 — `gethighestscoringplayer` ignores 0, `globallogic_score.gsc:419`);
   `round::function_870759fb()` (winner = highest `pointstowin`) and `thread
   globallogic::end_round( 3 )` — stock's score-limit ending. `dm.gsc onendgame` sets the winner
   from the top of placement, the outcome screen runs, the **TopSquad row** shows the top five by
   score left to right, the scoreboard lists everyone in finishing order.
6. `level.scorelimit = 0` for the race (a level var, `checkscorelimit` returns on `<= 0`,
   `globallogic.gsc:3335`) so the points written in step 5 cannot trigger the stock ending a frame
   early with a half-written table; written once, then the ending is ours to call.
7. Wrong-way and gate-skipping fall out of the ordered `next_gate`: crossing a later gate does
   nothing; crossing the next gate backwards (a `>= 0 → < 0` flip) does nothing.

**What "1st / 2nd / 3rd" will look like:** the stock FFA end screen, driven by the same placement
fields kills drive — that is the point of racing in `dm`. Which of its elements say the place
(outcome text, TopSquad row, scoreboard) is klaze's own experience of FFA, not something the dump
settles (`hud_message.gsc:436-451` picks winner/loser text; the LUI reads placement client-side).
Belt and braces: the banner shows `1st NAME 1:23.4 · 2nd NAME · 3rd NAME` from the first finish
until the screen, so the podium is on screen either way.

Modes this covers with one parameter set: **Circuit** (laps N), **Sprint** (laps 1, finish = the last
gate, no wrap), **Time trial** (host alone, best lap), **Elimination** (last through gate 0 each lap
is out — spectated), **Relay** (a lap per team member — the one mode that wants a team gametype).

**FFA housekeeping the race needs:** combat off by default (`player.candocombat = 0` on every
racer — `should_do_player_damage` returns 0 for a victim or attacker with it, `player_damage.gsc:1214-1220`;
vehicles are a separate damage path, left stock so a crash still hurts); `gf_race_combat` 1 = keep
the guns for a combat race. Deaths/respawns do not disturb placement once the points are written
(deaths only break `pointstowin` ties). Bots are on foot and rank last.

## 4. Budget and risk (bocw-c2's Miami abort, 2026-09-19)

The core loop adds no entities and one string-table entry per HUD phrase. Optional pieces cost:
markers 1 objective id per racer (64 reserved gametype ids, `gameobjects_shared.gsc:5940`), walls 1
entity per 256 u, props 1 entity each, OOB zones 1 entity each. Everything spawned must be swept on
round end AND before every level transition ([[vehicle-mode]]'s rule), and a race build stays a
SIDE payload until the Miami crash is closed.

## 5. Prototype order (each step is one match to measure)

1. **Finish line + podium** — in a `dm` match (session switch), gate 0 only, laps 1, no boundary:
   three racers (host + a joiner + bots on foot) cross; the finish timer shows on the match clock;
   the match ends through the score-limit path and the FFA end screen shows the finishing order.
   Proves T1, T2, T7 and the whole §3 flow in one go — and whether synthetic points drive the
   screen like kills do.
2. **Gates + laps + HUD** — the banner shows lap / position / time; markers on the next gate
   (`#"headicon_dead"` first, it is the icon proven every match; then the others).
3. **Boundary + reset** — corridor width, warning, T6 reset; measure the occupied-vehicle move.
4. **Editor + app** — record a track by driving it; publish; reload from the app next launch.
5. **Decoration** — the T3c collision test (clip vs physics wall against a bike), hay bales, OOB
   infields.

## 6. Why a Free-for-all match and not a Gunfight round

- **Placement is per player only when `level.teambased` is off**: `updateplacement`
  (`globallogic.gsc:3548-3600`) sorts by `pointstowin` in FFA and by team `.score` inside teams
  otherwise; the outcome, TopSquad and scoreboard all read that list.
- **The winner of a team match is a team**: `function_a3e3bd39( team )` (the Gunfight round-end path)
  gives the *team* the win, and the TopSquad row shows the winning team's players — a racer on the
  other team can never be "2nd" on screen.
- FFA in a private match is one round, its end screen is the one klaze described, and the menu's
  session switch already offers it (`Free-for-all` → `dm`). Everything the race needs from the menu
  (vehicle spawn/seat, banner, teleport, bridge, memory channels) runs in every gametype
  (`mod_apply` applies movement/bots/periods before the Gunfight gate).
- Cost: the race build must install its `gettimelimit` / `ontimelimit` hooks for `dm` (today those
  are behind `mod_is_gunfight()`), and a race day is a session switch away from the Gunfight lobby.

## 7. Prototype 1 — what was built (2026-09-19, never run)

In `gunfight_menu.gsc` (the RACE block after the death-barrier block; menu **start_menu → Race**;
bridge verb `race <start|stop|gate|undo|clear|load|markers>`; app: Config → Race + an Actions
"Race" box; `gf_dbg_race` debug line). Three new `#using`s, all in every MP link set:
`globallogic_score` (`setpointstowin`), `round` (`function_870759fb`), `gameobjects_shared` (ids).

| Piece | Built as |
|---|---|
| Track | `game.gf_race_gates` (survives rounds) mirrored to dvars `gf_gate_map` / `gf_gate_n` / `gf_gate0..15` = `"x,y,z,yaw,w"` (survive matches within a launch; reloaded on the same map). **Gate here** = the host's position (his vehicle when riding) across his yaw, width `gf_race_width`; undo / clear / load. |
| Crossing | `race_think`, one pass per server frame: `side = dot( pos - c, fwd )`, `lat = abs( dot( pos - c, right ) )`; crossed when side flips `< 0 → >= 0` with `lat <= w/2 + 64`; the crossing time is interpolated inside the frame (`function_60d95f53()` = the frame ms). The side reading is re-seated on the next gate at once. |
| Course | circuit (gate 0 ends a lap, `gf_race_laps`) or sprint (`gf_race_sprint` 1: the last gate is the finish). With one gate the whole race is "get behind it and cross it". |
| Start | racers = everyone not spectating; hold = `freezecontrols_allowlook` value layer + `setbrake( 1 )` on a rider's vehicle; bold 3-2-1-GO; first side reading taken at GO so nobody is credited for standing past a gate. |
| Finish timer | `race_gettimelimit` installed as `level.gettimelimit` (previous pointer saved): 0 = no clock until the first finish, then a fixed `end_minutes` = (elapsed at that finish + `gf_race_grace`)/60 → stock's `updategametypedvars` copies it every 0.25 s and `checktimelimit` drives the HUD clock and fires `level.ontimelimit` = `race_ontimelimit` at zero. |
| Result | `race_end` latches, `race_finish` ranks (finishers in order, then by laps / gates / distance), writes `pointstowin` + `score` = N‥1, prints `RACE OVER  1st … 2nd … 3rd …` to every feed + a bold, waits 3 s, then FFA: `round::function_870759fb(); thread globallogic::end_round( 3 )`; team modes: `function_a3e3bd39( winner.team, 1 )`. `level.endgameonscorelimit = 0` from start to end (restored after). |
| HUD | per-racer feed line every 3 s (lap, gate, elapsed, "ends in N s"); bold per finish `P1 NAME 1:23.4`. No hint banner — the banner channel measured dead on 09-18/19 ([[app-broadcast-bug]]). |
| Markers | `objective_add( id, "active", gate + 48z, #"escort_goal" )` per gate, ids from `gameobjects::get_next_obj_id`, released on hide/stop. **Off by default** until the icon is seen (Race → markers show/hide). |
| Combat | `player.candocombat = 0` on every racer for the race (undefined after) unless `gf_race_combat` 1. |
| Cancel | Stop restores the three hooks/flags, releases holds, clears combat + markers. |

**Test sheet (one FFA match, host + a joiner or a second body; bots stand still and rank last):**
1. Inject `gunfight_menu.race.gscc`, restart the match; Session → Free-for-all → Switch NOW (or
   start the lobby in FFA). Vehicles: Vehicle mode or the Vehicles page as usual.
2. Race → Debug line ON. Drive to the start line facing along the course, **Gate here**; drive
   the course, Gate here at two or three corners. The line shows `gates:N`, and for the host
   `side:` negative when he is behind the next gate, `lat:` within the width.
3. Race → START. Expect 3-2-1-GO bolds, everyone held for 3 s (measure: does the hold stop a
   driver — brake alone, freeze alone, both?), then the per-racer feed lines.
4. Drive the lap. With laps 1 the first crossing of gate 0 after the last gate is the finish:
   bold `1st NAME 0:41.3`, feed "RACE ends in 45 s", and the stock clock appears and counts down
   from 45.
5. Second racer finishes → bold `2nd …`; when everyone is in (or the clock hits zero): feed
   `RACE OVER  1st … 2nd … 3rd …`, bold, 3 s, then the stock FFA end screen. **Screenshot that
   screen**: does it show the finishing order (outcome text / TopSquad row / scoreboard)?
6. Negative checks: cross gate 0 backwards (nothing), skip a gate (nothing), Stop mid-race (holds
   released, clock back to the FFA limit).
7. Markers: Race → markers show/hide with the debug line's `mk:N` — do icons appear at the gates?

## 8. Run log

**Run 1 — 2026-09-19, Satellite, FFA, klaze solo on foot, build 22:56 (pre-Miami-fix).** The RACE line
at the end read `st:3 gates:5 laps:1 sprint:0 grace:45 w:600 racers:1 fin:1 tl:8.615 mk:5 host lap:1
next:0 side:5221 lat:2313 place:1 veh:0 last:8bit g0 0:44.7`. So: five gates placed and saved,
markers shown (`mk:5` — the objective icons allocate; whether they RENDER is still klaze's eyes),
the whole lap detected gate by gate, the finish credited at 0:44.7 with place 1, `end_minutes`
computed (8.615 = the finish at 7.9 min + 45 s), race state 3. **What did not happen:** no RACE
OVER line, no bold, and the match kept running — the GFCFG tick was still advancing 4 minutes after
the finish (691900 → 725900), and `end_round` fires `game_ended` synchronously
(`globallogic.gsc:2374` via `function_4720c07f`), which would have killed that publisher.
**Cause (code, then fixed):** `race_end` did `level notify( #"gf_race_stop" )` BEFORE
`level thread race_finish()`; its caller `race_think` endon's that event, and a notify ends its own
notifier's thread on the spot, so the thread line never ran — state 3 with nothing after it, exactly
the line above. Fixed 23:31 (thread first, notify second) + a `stage:` field on the RACE line
(rank / points / printed / ending / ended) so the next failure names its step. Payload rebuilt:
`gunfight_menu.race.gscc` 421,687 B / 2,383 strings (with the Miami census fix).

**Run 2 — 2026-09-19, same track, build 23:31.** klaze: *"it works"* — the race ended the match and
the FFA end screen showed. ✅ The whole §3 flow is measured once, solo. Also measured: the
`#"escort_goal"` gate icons render (he missed them after a restart — markers live in the level and
must be re-shown; now they default on at race start). Still open from run 2: the finish timer with a
second racer, the start hold on a driver, vehicles at all.

## 9. Added the same night (builds 23:46 – 00:01, NOT run)

| Piece | Built as |
|---|---|
| **Keep playing** (`gf_race_end` 0) | the race prints podium + `STANDINGS` and hands the match back; points ADD (`givepointstowin`, score += pts) so the standings are a championship; `level.endgameonscorelimit` stays 0 for the session; Race → **End match now** = the stock podium with the totals. Default 1 = end the match. |
| **A to B course** | the earlier sprint switch, relabelled: gate 0 = start line (never crossed), the last gate placed = finish; the feed drops the lap counter. |
| **Track boundary** (`gf_race_corridor` 1600, 0 = off) | corridor half-width around the centreline from the previous gate centre to the next (and the leg before, `race_corridor_dist` / `race_seg_dist`); before the first gate the leg starts 1500 u behind gate 0 so a grid is on track. Off it: bold `OFF TRACK - reset in N` each second, then **reset** (`gf_race_reset` 5 s; 0 = warn only). |
| **Reset** (`race_reset`) | to the last gate passed (gate 0 before any), 64 u past its line, floored (`tp_floor`), facing its yaw: a rider's vehicle is moved (`.origin` / `.angles` + `setvehvelocity( 0 )` — the T6 unmeasured piece; also levels a flipped vehicle), a runner is `tp_place`d; the side reading is re-seated so the move is never a crossing. Race → **Reset me** / bridge `race resetme` for a flipped or stuck vehicle. |
| **Gate posts** (`gf_race_posts` 1) | klaze: *"palm trees on each end of every checkpoint width"* — a `script_model` at posts a and b of every gate, floored, `p9_foliage_tree_palm_coconut_lrg_01` where resident else street light / tire barricade / oil drum / hedgehog (`isassetloaded`-gated, the Props page shape); shown and hidden with the markers, which now stay up after a race (Clear / hide / the level end remove them). RACE line `posts:Nxmodel`. |

RACE line additions: `bound:W/Rs`, `posts:`, host `cd:<dist>/<half> off:<s> rst:<n>`, `stage:`.
Payload `gunfight_menu.race.gscc` 431,908 B / 2,427 strings, check-gsc PASS zero notes, check-args 0.

**Test sheet for §9:** (1) restart, markers show → palm trees at both ends of every gate (Satellite has
no palms: expect the first fallback, the line names it). (2) START, drive well off the line between
two gates: `cd:` climbs past the half-width, OFF TRACK bolds count down, at 0 you are back at the last
gate facing the course — on foot first, then in a vehicle (the unmeasured move). (3) Keep-playing:
finish → podium + STANDINGS, match continues, START again, End match now → podium with totals.
(4) A to B: two gates, START behind gate 0, cross gate 1 = finish.

## 10. Start grid + saved tracks (2026-09-20 00:11 – 00:48, NOT run)

| Piece | Built as |
|---|---|
| **Start grid** (`gf_race_grid` 1) | at START every living racer is placed in rows behind gate 0: columns at `gf_race_grid_gap` (220) across the gate, rows 300 u apart from 200 u behind the line, floored, facing the gate's yaw; a rider brings his vehicle (the `.origin`/`.angles` move), a runner is `tp_place`d and, for `gf_race_vehicle` (the vehicle-mode class id, 9 = AUTO = bikes / snowmobiles / quads / cars / tanks / care heli, first resident; resolver `race_resolve` mirrors `veh_mode_resolve` without the cache), a ride is spawned at the slot and he is seated the vehicle mode's way (`spawnvehicle` + stock's spawn-in-vehicle flag `var_5a44792f` + `usevehicle`, `race_ride`); grid rides carry `gf_spawned` so every existing sweep removes them; bots stay on foot; RACE line `grid:placed/seated/fail ride`. |
| **Editor shows as it builds** | "Gate here" now `race_markers_show()`s at once: icon + the two posts = the width (klaze's question). |
| **Saved tracks** (T8) | the gates ride in the GFCFG marker as `trk=map;n;x,y,z,yaw,w;...` (`race_track_text`, from `config_publish`); `config_scan.read_track()` pulls them read-only; the app's Race box **Save track from game** stores them in `tools/gf-control/tracks.json` keyed by map + name; **Load into game** sends `racetrack <map>` (the GSC clears the track only when the map matches, else refuses the gates) then one `racegate x,y,z,yaw,w` per gate, 0.5 s apart (the GSC consumes one `gf_cmd_go` per 0.25 s poll), each ≤ 43 B; every accepted gate saves to the dvars and re-shows the markers. Delete removes a saved entry. |

Payload `gunfight_menu.race.gscc` 439,585 B / 2,460 strings, check-gsc PASS zero notes, check-args 0.

## Untried — not ruled out
- A rotated `trigger_box` (no caller rotates one; irrelevant while T2 is math).
- The shadow-OOB trick: one `trigger_radius_out_of_bounds` per racer, parked away and moved under
  him while off track, to get the stock HUD/countdown/kill on the math boundary.
- Which of the 44 resident collision models a Havok vehicle respects.
- AI pace car via `drivepath` on a node path the track editor also writes (`getvehiclenode` family).
- `luinotifyevent` for a stock countdown/timer element instead of prints ([[lui-source]] knows the
  pause-menu Lua; a match HUD element for laps would be the same route).
