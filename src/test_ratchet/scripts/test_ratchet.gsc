// ─────────────────────────────────────────────────────────────────────────────
// TEST L8 — does com_maxclients KEEP following maxplayers? (the 6v6 question)
//
// docs/notes/test-queue.md L6 · L7 · L7b
// Hook: scripts\mp_common\bb.gsc, mode=mp
//
// WHY THIS IS THE ONE TO RUN. Measured 2026-09-08, same lobby type, same session:
//
//     standard (2v2) Gunfight, baseline     maxplayers 4  -> com_maxclients 8
//     after gunfight_mod wrote maxplayers 8 maxplayers 8  -> com_maxclients 12
//
// Input +4, output +4. That is CAUSAL, not another correlation between lobbies -
// the lobby was held fixed and the variable was moved. So com_maxclients, which
// this project recorded as unreachable from script for its entire life, is
// downstream of a setting we can write.
//
// ▶ If it keeps following, 6v6 is real. CLAUDE.md has 6v6 recorded as "not
//   script-fixable" through a chain that is entirely about setdvar ACCESS - and
//   access was never the thing that mattered.
//
// ⚠ TWO THINGS THIS FIXES ABOUT THE EARLIER MEASUREMENT:
//   1. The 12 was read by test_mapswitch, which reads com_maxclients and NOT
//      maxplayers. So "maxplayers was still 8" is inferred from what we wrote
//      rather than observed. THIS SCRIPT READS BOTH, TOGETHER, EVERY ROUND.
//   2. Nobody knows WHEN com_maxclients updates - immediately on write, at the
//      next round, or only at the next session. Probes 5 and 3 answer that by
//      reading it right after the write and again a round later.
//
// ⚠ ONE STEP AT A TIME. Target 10 (= 5 per side), not 12. clamp_team_size() in
//   gunfight_mod bounds requests at com_maxclients/2, so a growing budget loosens
//   its own clamp - that is a feedback loop and its termination is untested. Going
//   straight to 12 would make a clamp and a refusal indistinguishable.
//
// ── HOW TO READ THE OUTPUT ────────────────────────────────────────────────────
// PROBE_ID * 100000 + VALUE, one every 5s. 99999 = undefined. Emits EVERY round -
// that is the point, the round boundary is where the budget settled last time.
//
//   1xxxxx  round number (game. scope)
//   2xxxxx  maxplayers      BEFORE the write   round 1: 4 or 8. Round 2+: THE ANSWER
//   3xxxxx  com_maxclients  BEFORE the write   round 2+: did it follow?
//   4xxxxx  maxplayers      AFTER  the write   expect target. Else refused/clamped
//   5xxxxx  com_maxclients  AFTER  the write   same round - did it move IMMEDIATELY?
//
// THE READING, on round 2:
//   2=10 and 3=14  -> 🔓 IT RATCHETS. 14 clients. 6v6 is on the table, raise again.
//   2=10 and 3=12  -> maxplayers took, budget did NOT follow past 12. A ceiling
//                     exists between 12 and 14 - that is a real finding, record it.
//   2=8            -> the write did not survive the boundary this time. Compare
//                     against L6, where it did at 8. Something about 10 differs.
//   4 != 10        -> the write was refused or clamped AT WRITE TIME. Stop here;
//                     nothing downstream means anything.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace test_ratchet;

function private autoexec __init__system__()
{
    system::register( #"test_ratchet", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &on_start );
}

function private on_start()
{
    level thread run();
}

function private run()
{
    level endon( #"game_ended" );

    // 10 = 5 per side. One step up from the 8 that is already proven to land and
    // to survive a round boundary (L6). See the header on why not 12.
    target = 10;

    // 1 = report both values and write NOTHING. Useful on its own: it confirms the
    // maxplayers/com_maxclients pair in one reading, which is the thing L7b is
    // currently inferring rather than observing.
    read_only = 0;

    if ( !isdefined( game.var_l8_round ) )
    {
        game.var_l8_round = 0;
    }
    game.var_l8_round++;

    wait( 10 );

    emit( 1, game.var_l8_round );

    // ⚠ BOTH, TOGETHER, BEFORE ANY WRITE. This pair is the whole measurement -
    //   reading them in separate runs is what left L7b inferring half of it.
    emit( 2, getgametypesetting( #"maxplayers" ) );
    emit( 3, getdvarint( #"com_maxclients", 0 ) );

    if ( read_only )
    {
        return;
    }

    setgametypesetting( #"maxplayers", target );

    // Read back rather than trusting the write: a silent refusal and a clamp are
    // indistinguishable from the call site.
    emit( 4, getgametypesetting( #"maxplayers" ) );

    // Does the budget move in the SAME round, or only across a boundary? Nobody
    // knows, and it changes how gunfight_mod should apply this.
    emit( 5, getdvarint( #"com_maxclients", 0 ) );
}

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

    wait( 5 );
}
