# Vehicle mode — everyone spawns already riding. Built 2026-09-17, never run.

klaze, 2026-09-17: *"i'd like to create some fun alternative "modes" for gunfight. on maps with
motorcycles, players spawn already driving one and cannot get off it, so it's a gunfight on bikes.
and maybe gunfight in attack helicopters."*

**Status: BUILT** as the menu's Vehicles → *Vehicle MODE* page + the app's *Vehicle mode* section, in
`gunfight_menu.gsc` (payload `payloads/gunfight_menu.vehmode.gscc`, **384,115 B / 2,194 strings**,
check-gsc PASS zero notes, check-args zero mismatches). ⚠ Built to a SIDE name because
`gunfight_menu.gscc` (365,638 B) was under test at the time; it becomes the payload when that session is
over. **Nothing here has run in-game.** Every mechanism is a stock shape read out of the dump; the two
"cannot get off" layers are the part with no stock precedent for a *player* and are the first thing the
test sheet measures. The static half (which vehicle exists on which map) is [[vehicles]] §6–7 /
`docs/data/map-assets.json`.

---

## 1. The shape — stock's own spawn-in-vehicle, applied to everyone

Fireteam's squad spawn puts a respawning player straight into a teammate's vehicle. The whole thing
is three lines (`spawning_squad.gsc:1578` `spawninvehicle`, reached from `spawning_shared.gsc:250`
right after `self spawn( origin, angles )`):

```gsc
vehicle::function_bc2025e( player );              // = player.var_5a44792f = 1   (vehicle_shared.gsc:6160)
vehicle usevehicle( player, player.spawn.vehicleseat );
```

`var_5a44792f` is read once, by vehicle_shared's `enter_vehicle` event handler
(`vehicle_shared.gsc:5362` `codecallback_vehicleenter`): set, the handler clears it and returns
**before the enter animation** — the rider is simply in the seat. ACTS compiles the `var_<hash>` field
name to the same hash the dump shows, the way the file already uses `level.var_d1455682`.

So per player, in an `on_spawned` handler (`mod_spawn_vehicle`, registered after `mod_spawn_movement`
so the rider's speed / OOB / fall-damage state is already in place), `veh_mode_ride`:

1. **resolve the ride** — `veh_mode_resolve()` walks the configured class's ORDERED candidate list and
   takes the first key that is `isassetloaded( "vehicle", key )` — the **plain-string** type argument
   ([[vehicles]] §5: the hashed form says yes to everything). Cached on `level` for the round
   (`mod_apply` → `veh_mode_announce` re-resolves every round and tells the host what everyone rides,
   or that nothing of that class is resident and everyone is on foot).
2. **spawn it** — `spawnvehicle( key, spot, ( 0, yaw, 0 ) )`, Path B ([[vehicles]] §1), at the
   rider's own spawn point + 12 u, facing the way the spawn faces. Hashed keys are stock syntax
   (`vip.gsc:125`) and every hashed key in the class table hashes back to the plain name it is
   commented with (FNV1a64 & MASK63 — all of `veh_master`'s hashed labels verified exactly).
3. **seat him** — `self.var_5a44792f = 1; veh usevehicle( self, 0 )`, then one frame later confirm
   `self isinvehicle()`. A confirmed seat starts the hold / lock / cleanup threads below.
4. **a refused seat retires the key** for the match (`game.gf_veh_dead[ class*100 + index ]`), the
   vehicle is deleted, the host is told once, and the next round falls through to the class's next
   candidate (or on foot). This is what makes the untested candidates (the streak gunship, the APCs)
   cost one round rather than a match.

### Ground vs air

- **Ground** rides spawn at spawn time, so the riders sit mounted through the pre-round countdown.
  Stock's enter handler **releases** the brake on entry (`player_vehicle.gsc:1266` `setbrake( 0 )`),
  so `veh_mode_hold` re-sets `setbrake( 1 )` after the seat (physics vehicles only, the `veh_spawn`
  guard) and releases it when `level.inprematchperiod` clears (globallogic.gsc:4889, the same flag
  the mod's overtime code waits on).
- **Air** rides (Hind, care package heli, the streak gunship) spawn **at GO** instead — a heli with a
  frozen pilot would drift into the map during the countdown — `gf_veh_alt` (300) above the rider's
  spawn point, capped by an upward `bullettrace` with 120 u of clearance, `setrotorspeed( 1.0 )`
  (the `veh_spawn` shape). An indoor spawn still gets its heli, just low.

### "Cannot get off" — two layers, neither measured

- **(a) the usability layer.** Leaving a vehicle is a hold-Use action (`vehicle.showHoldToExitPrompt`
  / `holdToExitProgress`, `vehicle_shared.gsc:90-91`), and the registered player value
  `disable_usability` (`values_shared.gsc:59` → `disableusability()`) is what Fireteam's parachute
  insertion sets while the player is in the air (`player_insertion.gsc:2464`). Layered on the rider
  under our own id `gf_veh` **after** the seat (usevehicle is a script entry, not a Use action, but
  no point risking it). Stock `val::nuke`s every layer per spawn (`globallogic_spawn.gsc:612`), so it
  is set per life. Whether the engine's exit check honours it is the measurement.
- **(b) the re-seat watcher** (`veh_mode_lock_think`, per life): every frame, if the rider is out of
  the vehicle and seat 0 is empty, `var_5a44792f = 1; usevehicle( self, 0 )` again. ⚠ `usevehicle`
  **toggles** — on a seated player it is the exit, which is exactly how stock ejects occupants
  (`vehicle_death_shared.gsc:307`, `bot_devgui.gsc:935`) — so the watcher only fires while seat 0 is
  actually empty, waits out a mid-exit frame where the engine still counts him aboard, hops him back
  from the passenger seat (exit this frame, re-enter seat 0 the next), and **gives up after 20
  re-seats in one life** rather than fight the engine every frame (host feed line names him).
  Reads `gf_veh_lock` live, so the host can free everyone mid-round.

### Deaths, wrecks, cleanup

- A player vehicle kills its occupants when it dies: `player_vehicle.gsc:101` sets
  `vehkilloccupantsondeath = 1` on every `isplayervehicle` at spawn, and `death_radius_damage`
  (`vehicle_death_shared.gsc:1434`) adds the explosion. So a downed Hind is an elimination with
  stock attribution; a rider shot off a bike is a plain player death.
- `veh_mode_life` (on the vehicle): rider dies or leaves → the empty ride is deleted 3 s later. A
  DESTROYED vehicle ends that thread first (`endon death`), so stock's wreck handling owns wrecks.
- A Gunfight round is a `map_restart`, which clears script-spawned entities anyway.
- `veh_mode_dismount` (mode switched off / re-applied): lock layer reset, `usevehicle` toggle out,
  delete once empty.

### The round-timer tiebreak

`mod_ontimelimit` sums each side's player health. A rider's armour is his ride, so each rider adds
his vehicle's health **fraction × 100** (`veh_mode_hp_bonus`) — otherwise a Hind at 5 % and a Hind at
100 % tie. Riders on bikes (exposed hitbox, bike health irrelevant) still get the bonus; it is
symmetric, so it only matters when one side has lost rides.

---

## 2. Classes — what each mode rides, and where it exists (offline, [[vehicles]] §6–7)

`gf_vehmode` picks a class; the class is an ordered candidate list and the first resident key wins.

| mode | class | candidates (in order) | resident on |
|---|---|---|---|
| 1 | **BIKES** | `vehicle_motorcycle_mil_us_offroad`, `_alt`, `#…_slow` | Diesel (Gas Station), Cartel (alt + slow only), Collateral, every Fireteam map |
| 2 | **ATTACK HELIS** | `#vehicle_t9_mil_ru_heli_gunship_hind` | Collateral, Fireteam maps (Duga, Ruka, Golova, Sanatorium, Alpine) |
| 3 | **HELIS ANY MAP** | `vehicle_t9_mil_helicopter_care_package` | every MP map (core_common); klaze flew it on every map 2026-09-16. Unarmed |
| 4 | **SNOWMOBILES** | `…snowmobile_alt_single_seat`, `…snowmobile`, `…_alt` | Crossroads, Alpine |
| 5 | **QUADS + BUGGIES** | `veh_quad_player_wz_pc`, `vehicle_t9_mil_fav_light`, `_alt`, `veh_mil_ru_fav_heavy` | Collateral, Fireteam maps |
| 6 | **TANKS + APCS** | T-72 `_sr` / base / `_alt`, `#…apc_heavy`, `#…apc_heavy_open_turret` | Crossroads; APCs on Diesel + Checkmate |
| 7 | **CARS + TRUCKS** | sedan (+alt), light truck player (+alt), `#…truck_light`, transport truck (+alt) | Cartel (light truck), Fireteam maps |
| 8 | **STREAK GUNSHIP** | `veh_t8_helicopter_gunship_mp`, `_guard` | every MP map — but AI-flown in stock; **whether seat 0 takes a player is the test.** A refused seat retires it in one round |
| 9 | **AUTO** | classes 1, 4, 5, 7, 6, 3 in that order | every map ends on the care package heli at worst |

Excluded on purpose: boats (they spawn on land at a spawn point), the campaign-only `_cp` helis
(resident on no MP zone), the intro-cinematic vehicles (not player vehicles).

**Options:** `gf_veh_lock` 1/0 (locked in / free), `gf_veh_hp` percent of the asset's default health
(100 stock; 25 makes a Hind killable by rifles, 400 makes bikes tanky — `healthdefault` scaled into
`.health` + `.maxhealth`, the pair `player_vehicle.gsc:1301` keeps), `gf_veh_alt` (300), `gf_dbg_veh`.
All **plain dvars** — not the packed store, whose key order a stale app depends on ([[hud-and-control-app]]).
Readback: `GFCFG` carries `|veh=<mode>,<lock>,<hp>,<alt>` and `config_scan.py` files it.

**Menu:** Start → Vehicles → *Vehicle MODE – everyone spawns riding* (the ten modes + *Apply to everyone
alive NOW*) → *Vehicle mode options* (lock, HP 25–400 %, height 150–1000, the debug line).
**App:** Config → *Vehicle mode* (same five fields); *Apply now* carries the `veh` live scope
(`cmd_apply_live` → `veh_mode_refresh`: everyone alive dismounts and remounts the re-resolved ride).

---

## 3. What is inferred, not measured

1. **Does `disable_usability` stop the hold-to-exit?** If not, layer (b) shows up as `exits` /
   `reseat` climbing in the debug line and the rider flickering out and back in; if the engine refuses
   the re-seat 20 times the watcher lets him go and says so.
2. **Can the bike's driver fire his own weapon?** Asset-defined (no script gate exists — `player_vehicle`
   never touches the rider's weapons). `shots:` in the debug line counts `weapon_fired` from seated
   riders. If drivers cannot fire, "gunfight on bikes" needs a different seat model (passenger +
   AI/parked driver) — not built.
3. **Does a frozen pilot's heli hold position?** Avoided rather than answered: air rides spawn at GO.
4. **`healthdefault` is defined at spawn time** (before the first enter). If it is not, `gf_veh_hp`
   silently does nothing (the guard returns) — `lastvhp:` in the line tells.
5. **The streak gunship's seat** (class 8) and **whether a Hind pilot has weapons at seat 0** (in
   Fireteam the pilot fires rockets, the gunner seat has the cannon — from play, not the dump).
6. **Spawn-point geometry**: a bike spawned 12 u above a doorway spawn point clips into the frame and
   physics pops it; a heli spawns low under a ceiling. Both are visible, neither is fatal.
7. **Joiners** (Gate 2, [[vehicles]] §3): the vehicle system registers in every MP mode
   (`mp_common/vehicle.gsc:14`), so a spawned player vehicle should replicate to a vanilla client
   like any stock Fireteam vehicle; the seat FX / HUD of the streak gunship on a client is the open
   question. Untested, as everything above.

---

## 4. Test sheet — ONE write per match, solo first, Diesel (mp_sm_gas_station) or Collateral

Turn on **Vehicle mode options → Debug line** first. It prints ONE line every 3 s:

```
VEHMODE BIKES motorcycle res:1 air:0 riding:1/1 vehs:1 lastvhp:1000 spawned:1 seated:1 fail:0 exits:0 reseat:0 gaveup:0 shots:0 pre:0 lock:1 hp:100% alt:300
```

`res` = a key resolved for this map · `riding:n/alive` · `vehs` = `getvehiclearray().size` ·
`lastvhp` = the last rider's vehicle health · `spawned / seated / fail` = this round's seats ·
`exits / reseat / gaveup` = layer (b)'s work · `shots` = weapon_fired from seated riders · `pre` = still
in the pre-round countdown.

| # | do | read |
|---|---|---|
| 1 | Diesel, Gunfight, solo. Vehicles → Vehicle MODE → *Motorcycles*, restart | at the pre-round you are ON a bike at your spawn, braked; host feed said `vehicle mode BIKES -> motorcycle (locked in)`. Line: `res:1 seated:1 fail:0 pre:1` |
| 2 | at GO drive | the brake is off (`pre:0`), the bike moves |
| 3 | hold Use (exit) for 3 s | **nothing happens** = layer (a) holds (`exits:0`); OR you pop out and straight back in (`exits` / `reseat` climb) = layer (b) is doing it; OR you get off (`gaveup:1`) = both failed — record which |
| 4 | fire your weapon while riding | `shots` climbs and rounds land = drivers can shoot (**the mode works**); no shot at all = asset forbids driver fire (§3 q2) |
| 5 | Fill with bots (Teams page) | every bot is seated on its own bike at its spawn (`riding:n/n`), sitting still; shoot one off — plain kill, its bike deleted ~3 s later (`vehs` drops) |
| 6 | let the timer run out with two bots left | the HP tiebreak ends the round as before (the bonus is symmetric) |
| 7 | *Vehicle mode options → Free – may get off*, then hold Use | you get off; `exits` climbs, no re-seat |
| 8 | Collateral, *Attack helicopters*, restart | on foot through the countdown; at GO you are IN a Hind ~300 u over your spawn (`air:1`), rotor running; fly, fire the pilot weapons |
| 9 | *Vehicle HP 25 %*, next round, get a bot to shoot you / shoot a bot's Hind | `lastvhp` reads ~a quarter of stock; the Hind dies to rifle fire and its pilot with it (kill feed credits the shooter) |
| 10 | Nuketown, *Helicopters ANY map* | a care package heli each, at GO, over the spawns; the trace kept them under any roof |
| 11 | Nuketown, *Streak gunship heli* | either seated in the streak gunship (record: controls? weapons?) or `fail:1` + host feed `would not seat ... retired for this match` and the next round on foot |
| 12 | *AUTO* on Crossroads / Collateral / Nuketown | snowmobile / motorcycle / care package heli respectively |
| 13 | app: Vehicle mode → Motorcycles, *Apply now* mid-round | everyone alive dismounts and remounts on bikes (`veh` scope; the feed says `config applied live`) |

Record: `______`

## 5. App parity + air spawn — 2026-09-18 (source committed, NOT yet in a payload)

klaze: *"i want everything in the app"* and *"make it so air vehicles spawn above my head so they aren't
stuck in the ground"* (the Vehicles-page spawn put a heli 250 u ahead at +25, i.e. in the ground).

- **App → Actions → Vehicles box**: *Spawn ahead of me* (drivable combobox), *Spawn (untested)*
  (streak / intro rows), *Enter the vehicle I aim at*, *Remove empty spawned vehicles*. The verbs are
  `gf_cmd_action vehspawn <i>` / `vehenter` / `vehclear`; `<i>` is the vehicle's INDEX in
  `veh_master()` because an asset name does not fit the 47-byte bridge slot ([[bridge-command-limit]]).
  The app parses the master list out of `gunfight_menu.gsc` at startup (baked fallback for the frozen
  exe), so the index cannot drift.
- **`veh_spawn` (page rows + the app verb)**: an aircraft — judged by name, `veh_is_air_key`: heli /
  chopper / gunship / vtol / plane / air_transport / ac130 / straferun — now spawns at
  `veh_mode_air_spot( host + 120 u ahead, gf_veh_alt )`: above the host's head, ceiling-traced, a
  little ahead so a descending heli does not land on him. Ground vehicles keep the 250-ahead spot.
  Vehicle mode's air rides already used the same helper.
- `vehclear` / the page row *Remove empty spawned vehicles*: deletes every vehicle this menu spawned
  (`gf_spawned` from the page, `gf_veh_mode` from the mode) that nobody sits in; stock's own vehicles
  carry neither tag and are left alone.

⚠ Held out of the injected payload on purpose: the 2026-09-18 in-match crash on Miami (err
`0x91f84370`, sig `C55D66DA`, round-transition-timed) was being isolated by bocw-0f / bocw-85 when this
landed — the next injected build is theirs (the spawn fix), these verbs ride the rebuild after it.

## Untried — not ruled out

- A passenger-seat model for two-per-bike (driver + shooter) if drivers cannot fire.
- `setvehmaxspeed` / `setmaxspeedscale` per class as a "bike speed %" option.
- Spawning the ride at an authored **vehicle** spawn struct where a map has them (`veh_spawn_point`,
  none found on the maps probed so far — [[vehicles]] §5).
- The Hind's gunner seat for a second player (`change_seat` is what the watcher currently undoes).
