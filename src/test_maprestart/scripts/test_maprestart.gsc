// ─────────────────────────────────────────────────────────────────────────────
// TEST B4 — does map_restart() keep the carried map?
//
// docs/notes/test-queue.md B4 · docs/notes/cw-builtins.md §6
// Hook: scripts\mp_common\bb.gsc, mode=mp
//
// WHY THIS IS WORTH A MATCH. Unlike C6/C7/C8 this answers nothing about team size.
// It answers whether the HOSTING PROCEDURE can lose a prerequisite. Step 7 of
// menu-map.md's recipe must be F7 (cwpatch full_restart) because the lobby route
// discards the map carry - so cwpatch is required for the workflow to complete at
// all, and Battle.net's repair silently restores the stock discord_game_sdk.dll,
// turning F4-F7 off with no error and no obvious cause.
//
// map_restart (0-1 args, BlackOpsColdWar.exe+3b0a5c0) may do the same job from
// inside the script that is already injected.
//
// ── THE MEASUREMENT PROBLEM, AND THE DVAR ────────────────────────────────────
// To answer "did the carried map survive", the script must compare the map BEFORE
// the restart with the map AFTER it. But `level` is rebuilt per round (mp_probe
// probe 6, answered), so level.* cannot carry a value across the restart, and
// whether __init__ state survives is still probe 8's open question.
//
// So the previous map name is parked in a dvar, which is process-level and
// outlives a map load.
//
// ⚠ This is NOT the closed loop mp_probe.gsc warns about. We write map A, the
//   engine reloads, and we compare our stored A against a FRESH util::get_map_name()
//   from the engine. The comparison is against engine-owned state, so it is
//   evidence. Reading back only what we wrote would prove nothing.
//
// ⚠ Map names never render on retail (literals display as nothing), so this
//   reports the COMPARISON as 1/0 rather than the names. Same technique as
//   test_teamfill.gsc.
//
// ── HOW TO READ THE OUTPUT ────────────────────────────────────────────────────
// This emits on EVERY on_start_gametype. You want two readings.
//
//   1xxxxx  is there a stored previous map?   1/0
//   2xxxxx  SAME MAP AS THE PREVIOUS RUN?     1/0   <- THE ANSWER, on run 2
//   3xxxxx  restart attempted? 1/0            0 means read_only was left on
//
// Expected sequence, run AFTER carrying to a map:
//   RUN 1   100000 / 200000 / 300001    nothing stored yet; restart fired
//   RUN 2   100001 / 200001             <- carried map SURVIVED. cwpatch can go
//       or  100001 / 200000             <- it reloaded the lobby's own map. F7 stays
//       or  100000 / 2xxxxx             <- the dvar did NOT survive the restart.
//                                          That is a result about dvar lifetime, not
//                                          about the map. Record it; the test needs a
//                                          different carrier before it can answer B4.
//   no RUN 2 at all                     <- map_restart did not restart anything, or
//                                          the script did not re-link. Check the hook
//                                          before concluding the call failed.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace test_maprestart;

function private autoexec __init__system__()
{
    system::register( #"test_maprestart", &__init__, undefined, undefined, undefined );
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
    // ── config. Plain locals, not preprocessor macros - see test_addclients.gsc.

    // ⚠ RUN WITH THIS AT 1 FIRST. It reports the map comparison and restarts
    //   nothing, which confirms the dvar carrier works before you spend a restart.
    read_only = 1;

    // map_restart is 0-1 args and the table says nothing about what the argument
    // means. 0 = call the no-argument form, the only one that cannot be wrong about
    // an argument. Set to 1 only if tools/dump-grep.sh shows stock passing one.
    pass_arg  = 0;
    arg_value = 0;

    wait( 10 );

    current = util::get_map_name();
    prev    = getdvarstring( #"scr_gf_prevmap", "" );

    had_prev = 0;
    if ( prev != "" )
    {
        had_prev = 1;
    }
    emit( 1, had_prev );

    same = 0;
    if ( had_prev && prev == current )
    {
        same = 1;
    }
    emit( 2, same );

    // Park the current map for the next run to compare against. Our own dvar name,
    // not a game one - nothing in the dump reads scr_gf_prevmap.
    setdvar( #"scr_gf_prevmap", current );

    if ( read_only )
    {
        emit( 3, 0 );
        return;
    }

    emit( 3, 1 );

    // ⚠⚠⚠ ONCE-GUARD. ADDED 2026-09-09, BEFORE THIS WAS EVER RUN LIVE.
    //
    //   Without it this test is an INFINITE RESTART LOOP BY CONSTRUCTION, and it
    //   would reveal that only by SUCCEEDING: map_restart() works -> the match
    //   restarts -> on_start_gametype fires -> run() -> map_restart() -> forever.
    //   The game becomes unusable with no way in and the only exit is killing the
    //   process. Strictly worse than A4's map-load failure, which stopped by itself.
    //
    //   ⚠ TWO carriers, deliberately, because EITHER MAY NOT SURVIVE A RESTART and
    //     that is the very thing this test exists to measure:
    //       - game. scope survives a ROUND, but a map_restart is not a round
    //         boundary and nobody knows whether it clears game.
    //       - a dvar is process-level and survives more - which is why this test
    //         already uses scr_gf_prevmap as its carrier - but probe 1 is what
    //         MEASURES that, so it cannot be assumed here either.
    //     Neither alone is trustworthy. Both together fail only if both reset, and
    //     probe 1 reports it when they do.
    //
    //   ⚠ DO NOT REMOVE THIS TO "SEE IF IT LOOPS". The loop IS the failure, not the
    //     measurement. One restart is all the evidence needed - the second reading
    //     arrives from the next on_start either way.
    if ( isdefined( game.var_b4_fired ) || getdvarint( #"scr_gf_b4_fired", 0 ) == 1 )
    {
        emit( 4, 1 );        // guard held: a restart already fired, stopping here
        return;
    }

    game.var_b4_fired = 1;
    setdvar( #"scr_gf_b4_fired", 1 );

    emit( 4, 0 );            // first and only attempt

    // Give the emits above time to be read before the screen goes away.
    wait( 5 );

    if ( pass_arg )
    {
        map_restart( arg_value );
    }
    else
    {
        map_restart();
    }

    // Nothing after this line is guaranteed to run - the match is restarting. The
    // second reading comes from this script's NEXT on_start, not from here.
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
