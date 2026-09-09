// ─────────────────────────────────────────────────────────────────────────────
// TEST B9 — does a map_restart() LINK A NEWLY INJECTED payload?
//
// docs/notes/test-queue.md B4 · "Unattended operation"
// Hook: scripts\mp_common\bb.gsc, mode=mp
//
// THE LAST GATE ON UNATTENDED OPERATION, and the whole test is one number.
//
// B4 proved (2026-09-09) that map_restart() restarts a match from inside an
// injected script, and that the script re-links and re-runs afterwards. But the
// script that re-ran was ALREADY LINKED. Linking a *fresh* injection needs the map
// load to re-read the scriptparsetree pool - the same mechanism F7 uses. Likely,
// but three wrong conclusions in one night started from "likely".
//
// ── THE METHOD: a version stamp ──────────────────────────────────────────────
// This file carries a VERSION constant that is the ONLY difference between two
// builds. Sequence:
//
//   1. build with VERSION = 1, inject, link it with ONE F7
//   2. it emits 100001, waits, and calls map_restart()
//   3. DURING that wait, inject the VERSION = 2 build over it
//   4. the restart lands. Read the next 1xxxxx:
//
//        100002  🔓 the NEW payload was linked by a script-driven restart.
//                   Unattended operation works: inject -> restart -> linked, with
//                   no keyboard and no human.
//        100001  the old payload re-ran from the already-linked copy. A fresh
//                   injection needs something a map_restart does not do, and
//                   autonomy still needs F7 pressed by a person.
//
// ⚠ ONE F7 TOTAL, at step 1. Every restart after that is the script's own.
//
// ⚠ SAME once-guard discipline as B4, and for the same reason: without it this is
//   an infinite restart loop that reveals itself only by working. Two carriers,
//   since neither game. scope nor a dvar is known to survive a map_restart - B4
//   showed one of them does, not which.
//
// ── HOW TO READ THE OUTPUT ────────────────────────────────────────────────────
//   1xxxxx  VERSION of the build that is running   <- THE ANSWER
//   2xxxxx  1 = this run fired a restart, 0 = guard held and it stopped
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace test_relink;

function private autoexec __init__system__()
{
    system::register( #"test_relink", &__init__, undefined, undefined, undefined );
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

    // ⚠⚠ THE ONLY LINE THAT DIFFERS BETWEEN THE TWO BUILDS. Everything else is
    //    byte-identical, so the number on screen can only come from which build
    //    the VM actually linked.
    version = 1;

    wait( 10 );

    emit( 1, version );

    // ── once-guard, both carriers. See B4: without this it is an infinite
    //    restart loop that reveals itself only by succeeding.
    if ( isdefined( game.var_b9_fired ) || getdvarint( #"scr_gf_b9_fired", 0 ) == 1 )
    {
        emit( 2, 0 );        // guard held - this run does not restart
        return;
    }

    game.var_b9_fired = 1;
    setdvar( #"scr_gf_b9_fired", 1 );

    emit( 2, 1 );

    // Window for the v2 injection to land before the reload.
    wait( 5 );

    map_restart();
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
