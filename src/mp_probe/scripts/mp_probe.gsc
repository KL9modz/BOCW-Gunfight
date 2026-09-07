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
// ⚠⚠ A NUMBER IS NOT AUTOMATICALLY EVIDENCE. On a platform where numbers are the only
//    channel, it is easy to mistake a readout for a result. Distinguish two kinds:
//
//      ENGINE-OWNED state  — com_maxclients, getgametypesetting, entity counts, player
//                            counts. We did not author these. Reading them is evidence.
//      SELF-WRITTEN state  — anything this script set. Reading it back is a CLOSED LOOP:
//                            it proves the write landed, and nothing else.
//
//    Probes 1-5 and 7 are engine-owned. **Probe 6 (level.probe_runs) is self-written** —
//    it is a valid cadence measure only because the VALUE OF INTEREST is how many times
//    the engine called us, not the number itself.
//
//    This is not hypothetical. A jump-height experiment on 2026-09-07 set #"jump_height"
//    to 780, read it back as 780, and changed nothing in game — that dvar is consulted
//    only by cp_common and zm_common, never by MP movement. The readout was true and
//    meaningless. Only a human watching the actual jump caught it. See [[mp-dvars]].
//
// ── HOW TO READ THE OUTPUT ────────────────────────────────────────────────────
// Values print one every 5s as a tagged number:  PROBE_ID * 100000 + VALUE
// So 100012 is probe 1, value 12. Strip the leading digit; the rest is the answer.
// 99999 as the value means UNDEFINED at read time.
//
// Emitted in this order, with the two live questions LAST so they stay on screen:
//
//   1xxxxx  com_maxclients               per-playlist client count. 8 in a 3v3 Gunfight lobby
//                                        (6 players + 2 spectators). Read 12 in a Faceoff lobby
//                                        to confirm it is playlist config, not an engine ceiling.
//   2xxxxx  getgametypesetting timelimit  round timer in SECONDS. 0 = no limit. Observed 0 and 30.
//   7xxxxx  players currently in match
//   5xxxxx  gunfight_zone_center count   0 on both stock Gunfight maps tested. Kept to classify
//                                        any new map or lobby type.
//   6xxxxx  on_start firing count        AMBIGUOUS ON PURPOSE — see the note at the emit site.
//
// Probes 3 and 4 (timelimitmin=0 / timelimitmax=1440) were removed once confirmed stable.
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

    // ⚠ ORDER AND PACING ARE DELIBERATE. The first version emitted seven values at 2s
    // apart and klaze could read only two of them — iprintlnbold lines scroll, and 14
    // seconds of unlabelled digits is not a readable instrument. Fixes: fewer values,
    // 5s spacing, and the two live questions emitted LAST so they are the most recent
    // text on screen when the player looks up.
    //
    // Probes 3 and 4 (timelimitmin / timelimitmax) were REMOVED. They read 0 and 1440,
    // are confirmed and stable, and cost 4 seconds of attention every round for nothing.

    // getdvarint takes a HASHED name plus a default — stock form, gunfight.gsc:160 and
    // team_assignment.gsc:1302. Script only ever reads this dvar; it is set by the engine
    // at session creation. Reading 12 in a Faceoff lobby confirms it is per-playlist.
    emit( 1, getdvarint( #"com_maxclients", 0 ) );

    // globallogic.gsc:305 clamps this into [timelimitmin, timelimitmax] for the round
    // timer. Stored in SECONDS — gettimelimit() divides by 60 (gunfight.gsc:1139) and the
    // clamp bounds are minutes. Observed 0 (no limit) and 30 (30s rounds) in two lobbies,
    // both menu values, so the setting is live and settable.
    emit( 2, getgametypesetting( #"timelimit" ) );

    emit( 7, getplayers().size );

    // ── The two live questions, emitted last so they linger on screen ──

    // gunfight.gsc:813. Confirmed 0 on two stock Gunfight maps; kept so any NEW map or
    // lobby type can be classified in one number.
    zones = getentarray( "gunfight_zone_center", "targetname" );
    emit( 5, zones.size );

    // ⚠ READ THIS ONE CAREFULLY, it is ambiguous by design and the ambiguity is the point.
    //   climbs 600001 -> 600002 -> 600003   level persists; only on_start re-fires per round
    //   stays 600001 on EVERY round         level itself is torn down and rebuilt each round
    // The second case breaks gunfight_mod: its latch flags and level.zones would not
    // survive a round boundary and would need re-applying on every on_start.
    emit( 6, level.probe_runs );
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

    // 5s, not 2s. At 2s the values scroll past faster than they can be read and written
    // down — verified the hard way: klaze caught two of seven on the first run.
    wait( 5 );
}
