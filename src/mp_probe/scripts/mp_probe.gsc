// ─────────────────────────────────────────────────────────────────────────────
// MP probe — answers several open questions per match, read-only.
//
// Hook: scripts\mp_common\bb.gsc, mode=mp  (see ../gsc.conf)
// Requires: hello_world must have confirmed the hook first. It has (2026-09-07).
//
// WHY THIS EXISTS. Retail renders NUMBERS ONLY — literal script strings are compiled
// out of ship builds and no log file is written anywhere (see ../README.md). So every
// question worth asking has to be one whose answer is a number. Several of the
// project's open questions are exactly that shape, and this reads them all in one
// match instead of inferring them from menus.
//
// READS ONLY. The single value it writes is its own level.probe_runs counter. It does
// not touch level.ontimelimit, level.zones, or any stock state. Nothing here changes
// gameplay.
//
// ── HOW TO READ THE OUTPUT ────────────────────────────────────────────────────
// Values print one every 2s as a tagged number:  PROBE_ID * 100000 + VALUE
// So 100012 is probe 1, value 12. Strip the leading digit; the rest is the answer.
// 99999 as the value means UNDEFINED at read time (e.g. 399999 = probe 3 undefined).
//
//   1xxxxx  com_maxclients            <- the team-size ceiling. THE Phase 1 question.
//   2xxxxx  getgametypesetting timelimit  <- live round timer. THE Phase 0 T0.2 question.
//   3xxxxx  level.timelimitmin        <- expect 0
//   4xxxxx  level.timelimitmax        <- expect 1440, confirming the clamp is not the constraint
//   5xxxxx  gunfight_zone_center count <- THE map dependency. 0 = unlocked map, >0 = stock zoned
//   6xxxxx  on_start firing count     <- 1 then never = per-match; 1,2,3 = per-round
//   7xxxxx  players currently in match
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace mp_probe;

function private autoexec __init__system__()
{
    system::register( #"mp_probe", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &on_start );
}

function private on_start()
{
    if ( !isdefined( level.probe_runs ) )
    {
        level.probe_runs = 0;
    }
    level.probe_runs++;

    level thread report();
}

// on_start_gametype fires before players are in the match, so wait for them rather
// than printing into an empty player list.
function private report()
{
    wait( 8 );

    // getdvarint takes a HASHED name plus a default — stock form, gunfight.gsc:160 and
    // team_assignment.gsc:1302. Script only ever reads this dvar; it is set by the engine
    // at session creation. If this changes after a mode switch, 6v6 is reachable.
    emit( 1, getdvarint( #"com_maxclients", 0 ) );

    // globallogic.gsc:305 clamps this into [timelimitmin, timelimitmax] for the round timer.
    emit( 2, getgametypesetting( #"timelimit" ) );
    emit( 3, level.timelimitmin );
    emit( 4, level.timelimitmax );

    // gunfight.gsc:813 — the ONLY hard map dependency in the gametype. Counting it here
    // classifies any map in one number, without needing the round to play out.
    zones = getentarray( "gunfight_zone_center", "targetname" );
    emit( 5, zones.size );

    emit( 6, level.probe_runs );
    emit( 7, getplayers().size );
}

// Tagged so values are distinguishable with no labels — a literal label would render
// as nothing on retail and make the digits look unexplained.
function private emit( id, value )
{
    v = 99999;
    if ( isdefined( value ) )
    {
        v = value;
    }

    tagged = id * 100000 + v;

    foreach ( player in getplayers() )
    {
        player iprintlnbold( tagged );
    }

    wait( 2 );
}
