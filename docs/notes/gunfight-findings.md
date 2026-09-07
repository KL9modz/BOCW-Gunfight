# Gunfight on non-Gunfight maps

All line numbers refer to `bocw-source-main\scripts\mp_common\gametypes\gunfight.gsc`
unless stated. Gametype string is **`gunfight`** (enum `0x2f`).

## Headline: one hard map dependency

Gunfight needs the overtime capture zone. Nothing else about it is map-specific.

```gsc
// gunfight.gsc:119, inside onstartgametype()
if ( !setupzones() )
{
    return;              // :121  bails out of the whole function
}
```

`setupzones()` (`:827`) returns false when `getentarray("gunfight_zone_center","targetname")`
is empty — true of every map that isn't a shipped Gunfight map.

## This is almost certainly the round-timer bug — DERIVED

Observed in-game: *"on a non-standard map I had no control of the round timer
even though there's a menu option for it."* The early return at `:121` skips
everything below it:

| Skipped | Line | Effect |
|---|---|---|
| `level.zones = zones;` | :907 | **`level.zones` stays undefined all match** |
| `music::setmusicstate("gunfight_roundstart")` | :126 | no round-start music |
| `function_8cac4c76()` | :129 | `noRespawnsLeft` UI models never set |
| per-team `var_a236b703` / `var_61952d8b` | :131-135 | suppressed "last man" VO comes back |
| `luinotifyevent( #"round_start" )` | :137 | **the round-start LUI event never fires** |
| `function_d33c99f8()` (pushes `timeremaining`) | :145 | tournament HUD never initialised |

Then at time expiry it gets worse. `ontimelimit()` (`:915`) threads `overtime()`,
which does:

```gsc
zone = level.zones[ 0 ];                                     // :944  undefined
if ( zone.gameobject gameobjects::function_339d0e91() > 0 )  // :946  DEREFERENCES IT
    pause_time();

setgameendtime( gettime() + int( level.extratime * 1000 ) ); // :951  never reached
thread globallogic::timelimitclock();                        // :953  never reached
level.usingextratime = 1;                                    // :954  never reached
...
if ( !isdefined( zone ) )                                    // :958  UNREACHABLE DEAD CODE
{ function_c4915ac(); return; }
```

The thread dies at `:946`, before the clock is ever set up. The `isdefined` guard
sits 14 lines too late. Net effect: no round-start event, no overtime clock.

**The round still resolves.** `checktimelimit()` (`globallogic.gsc:3272`) re-fires
while `timeleft <= 0`; `level.var_31f5f23` is already 1, so `ontimelimit()` takes
its else branch straight to the HP tiebreaker `function_c4915ac()` (`:1090`),
which sums `player.health` per team and calls `endround(team, 1)`.

Also unguarded: `ongameplaying()` at `:213` iterates `level.zones` with no
`isdefined` check, and if it throws, `:222-225` never clears the
`gunfight_pregame_rob` clientfield — so the pregame render override sticks on
players. (The client-side twin at `gunfight.csc:147` *is* guarded.)

## DANGER — do not half-build a zone

Zero zone entities is **safe** (clean early return). A `gunfight_zone_center`
*without* a properly overlapping `gunfight_zone_trigger` is **fatal**:

```gsc
globallogic_utils::add_map_error( "Zone at ... is not inside any \"zonetrigger\" trigger" );  // :865
...
if ( globallogic_utils::print_map_errors() ) { return false; }                                 // :902
```

`print_map_errors()` (`globallogic_utils.gsc:634`) calls `callback::abort_level()`,
which nulls `callbackstartgametype`, `callbackplayerconnect`, `callbackplayerdamage`,
`callbackplayerkilled` — a dead, unplayable match. Note `:845` uses
`zone istouching( trigs[j] )`, so the center must be *physically inside* the trigger.

## What already works on any map

- **Spawns.** `:77` `spawning::addsupportedspawnpointtype( "tdm" )` — byte-identical
  to `tdm.gsc:39-41`. There is no gunfight spawn type anywhere. Any TDM-capable map
  works. Caveat: `:100` sets `level.alwaysusestartspawns = 1`, so both teams use the
  fixed TDM start clusters every round — long walk-ups on a big map, not a failure.
- **Loadouts.** `getscriptbundle("gunfightloadoutlist")` → `mp_gunfight_loadout_default`
  / `_snipers` / `_blueprints` / `_melee`. Pure weapon/attachment refs, zero geometry.
  Rotated in `onendround()` (`:388`) every `level.gunfightroundsperloadout` rounds.
- **Round wins.** Last-team-standing via `level.takelivesondeath = 1` (`:50`) and
  `ondeadevent()` (`:357`). No map assets involved.
- **No map-name checks.** Grepping gunfight.gsc/.csc for `mapname`, `g_gametype`,
  `getdvarstring`, `level.script` returns zero hits.

## Fix sketch — UNVERIFIED, not yet written

Cleanest without editing the map, all in an injected script:

1. Set `level.zones = []` unconditionally so nothing dereferences undefined.
2. Guard the `foreach` at `:213`.
3. Replay the block skipped after `:121` — most importantly `luinotifyevent( #"round_start" )`.
4. Let the HP tiebreaker stand in for overtime, or override `level.ontimelimit`.

Because `injectcw` can't detour, do this from `callback::on_start_gametype`,
which runs after Gunfight's own `gametype_init`. Ordering is **UNVERIFIED**.
