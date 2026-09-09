// ─────────────────────────────────────────────────────────────────────────────
// TEST C7 — the REAL client ceiling, measured.
//
// docs/notes/test-queue.md C7 · docs/notes/cw-builtins.md §4
// Hook: scripts\mp_common\bb.gsc, mode=mp
//
// WHY. Everything this project believes about team size rests on
// getdvarint(#"com_maxclients") reading 8 in a 3v3 Gunfight lobby. That is one
// number from one source, and the "6 players + 2 spectators" reading of it is an
// INFERENCE nobody has tested.
//
// addtestclient() (BlackOpsColdWar.exe+3d3c9e0) fills the lobby until the engine
// refuses. The count where it refuses is the ceiling - measured, not read. If it
// stops at 6, the spectator slots are not player slots. If it reaches 8, they are,
// and 8 clients is 4v4.
//
// ⚠⚠ CORRECTED 2026-09-08 - this called the raw builtin addtestclient() and that was
//    a mistake. A dump grep found the ONE stock call site, and it is wrapped:
//
//      bot.gsc:137   bot = addtestclient(name, clanabbrev);
//                    if(!isdefined(bot)) return undefined;
//                    bot init_bot();                       <- SKIPPED by a raw call
//
//    The public API is bot::add_bot(team, name, clanabbrev) - it runs init_bot(),
//    sets bot.botteam, and handles class selection. Stock calls it as
//    bot::add_bot(team) from dev.gsc:1705, rat.gsc:76 and _prop_dev.gsc:1421.
//    A raw addtestclient() produces a half-initialised bot. Use the wrapper.
//
//    See docs/notes/dump-cross-check.md.
//
// ⚠ THIS WRITES TO A LIVE SESSION. Bots may not leave cleanly; `kick` (1-2 args,
//   +3b0a3a0) is the only obvious undo. Run alone. Test a lobby return after.
//
// ── HOW TO READ THE OUTPUT ────────────────────────────────────────────────────
// PROBE_ID * 100000 + VALUE, one every 5s. 99999 = undefined.
//
//   1xxxxx  com_maxclients                what the dvar claims  (expect 8 / 12)
//   2xxxxx  players BEFORE                baseline
//   3xxxxx  players AFTER the fill        <- THE ANSWER
//   4xxxxx  addtestclient calls that stuck  (3 minus 2)
//   5xxxxx  calls attempted               hit MAXTRIES? then the ceiling is higher
//                                          than this test looked - raise it and rerun
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;
#using scripts\core_common\bots\bot;

#namespace test_addclients;

// ⚠ Deliberately plain locals, not #define. src/README.md records that DIALECT
//   defects are invisible to every harness stage and caused two of the three
//   game-crashing bugs this project has had. gunfight_mod.gsc uses a plain config
//   struct for the same reason. Do not "tidy" these into preprocessor macros.

function private autoexec __init__system__()
{
    system::register( #"test_addclients", &__init__, undefined, undefined, undefined );
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
    // ⚠⚠ ONCE-GUARD, ADDED 2026-09-08 AFTER THE FIRST LIVE RUN. Without it this
    //    test invalidates its own reading.
    //
    //    on_start_gametype fires ONCE PER ROUND in round-based Gunfight (the
    //    cadence gunfight_mod.gsc records, confirmed by hello_world's counter).
    //    run() has no endon, so round 2 threaded a SECOND copy while the first
    //    was still looping, round 3 a third. They then broke each other's exit
    //    condition: thread A's add raises getplayers().size, thread B reads the
    //    rise and resets its own `stalled` counter, so no thread ever reaches
    //    `stalled < 2`. Every one of them runs to maxtries=20 instead - 20 adds
    //    per thread per round against an 8-client budget.
    //
    //    Measured 2026-09-08: bots poured in continuously, the count differed
    //    every round, and it read 4v4, then 3v3, then 2v4.
    //
    //    `game.` scope and not `level.`: level is torn down and rebuilt every
    //    round (mp_probe probe 6), so a level guard would be undefined exactly
    //    when it is needed. game. survives the round - the same property
    //    gunfight.gsc:81 relies on for game.var_96a8ff4a. It also clears on a
    //    new lobby, which is how you re-run this: take a NEW LOBBY, not a new
    //    round.
    if ( isdefined( game.var_c7_done ) )
    {
        return;
    }
    game.var_c7_done = 1;

    // Stop cleanly at round end rather than looping on into a torn-down level.
    level endon( #"game_ended" );

    // on_start_gametype fires before players are in the match.
    wait( 10 );

    // Hard cap: without it, a loop whose exit condition never trips runs forever
    // inside a live match. 20 is comfortably past any plausible MP ceiling (12).
    maxtries = 20;

    // Clients take time to connect. Reading the player count immediately after an
    // add would read it from before the join landed, and make every add look like
    // a refusal.
    settle = 2;

    maxclients = getdvarint( #"com_maxclients", 0 );
    before     = getplayers().size;

    emit( 1, maxclients );
    emit( 2, before );

    // Fill until two consecutive adds fail to raise the count. One failure alone
    // is not proof - a slow join looks identical to a refusal at this timescale.
    tries    = 0;
    stalled  = 0;
    current  = before;

    while ( tries < maxtries && stalled < 2 )
    {
        // undefined team = let team_assignment place it (autoassign). Passing a
        // team here is TEST C8's job; this one measures the TOTAL ceiling.
        bot::add_bot( undefined );
        tries++;

        wait( settle );

        now = getplayers().size;

        if ( now > current )
        {
            current = now;
            stalled = 0;
        }
        else
        {
            stalled++;
        }
    }

    emit( 3, current );
    emit( 4, current - before );
    emit( 5, tries );
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

    // 5s. At 2s the values scroll past faster than they can be written down -
    // mp_probe.gsc learned this the hard way.
    wait( 5 );
}
