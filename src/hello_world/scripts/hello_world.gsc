// ─────────────────────────────────────────────────────────────────────────────
// Hello-world: prove the MP injection path before building the real mod.
//
// Hook: scripts\mp_common\bb.gsc, mode=mp  (see ../gsc.conf)
// Model: mirrors stock bb.gsc exactly (bocw-source@edd94bd scripts/mp_common/bb.gsc:12):
//        function private autoexec __init__system__ -> system::register (5 args, hashed name)
//        -> callback::on_start_gametype / on_connect
//
// Changes NO gameplay. It only logs, and probes that level.ontimelimit is
// reassignable, restoring it immediately.
//
// ⚠ REWRITTEN 2026-09-07 after the first injection crashed the game 1-2s into a
//    Gunfight map load with a ~21-deep recursion signature. The previous version was
//    authored in t7-compiler-custom dialect and built with ACTS. Three defects, all
//    confirmed against the dump:
//      1. It called logprint(), which does NOT EXIST in T9 — zero occurrences across
//         the entire dump. It was the FIRST statement of the autoexec, i.e. the first
//         thing to run at script link. This is the prime suspect for the crash.
//      2. Its autoexec was public. All 859 stock __init__system__ are `private`.
//      3. system::register was passed 4 args; the signature takes 5 and 857 of 859
//         stock calls pass 5.
//    The offline harness passed it anyway — stage 3 only checked namespace::function
//    calls and never looked at bare builtins like logprint. Harness now has a stage 4.
//
// ✅ HOOK CONFIRMED IN-GAME 2026-09-07. The fixed build injected at the frontend and a
//    private Gunfight match loaded with NO crash — the exact sequence that crashed on the
//    logprint build. Controlled comparison: same box, same injector, same hook point, same
//    map; only the logprint calls differ. The MP injection path works end to end on retail.
//
// ⚠⚠ RETAIL RENDERS NUMBERS ONLY. This is a PLATFORM CONSTRAINT, not a bug in this file,
//    and it governs every on-screen instrument this project will ever write.
//      - Literal script strings are compiled out of ship builds. All 401 stock literal
//        iprintlnbold call sites decompile to "<dev string:xNN>" — the content is not in
//        the retail binary. Our banner read "^2[GFHELLO] hook live - on_start fired 1x"
//        and rendered on screen as the single character "1".
//      - Runtime VALUES do render — stock has 66 variable call sites, e.g.
//        iprintlnbold( numshots ).
//      - Hashed refs (#"mp/...") render only if already in the localization table. You
//        cannot add one.
//      - println/logprint are unreadable: retail writes no log file anywhere. Confirmed
//        twice on the test box across the install dir and both profile trees.
//    So: NUMERIC iprintlnbold is the only observability channel this platform gives us.
//    Encode findings as numbers. Do not write a label and expect to see it.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace gunfight_hello;

// (1) Fires the instant the injected script is linked into the MP VM — exactly as
//     stock bb.gsc:12 does for itself. `private` matches all 859 stock instances.
function private autoexec __init__system__()
{
    println( "[GFHELLO] 1/4 autoexec fired: injected script linked into MP VM" );
    system::register( #"gunfight_hello", &__init__, undefined, undefined, undefined );
}

// (2) Called by the system framework after registration; wire runtime callbacks.
function private __init__()
{
    println( "[GFHELLO] 2/4 __init__ fired: system::register callback ran" );
    callback::on_start_gametype( &on_start );
    callback::on_connect( &on_player_connect );
}

// (3) Fires at globallogic.gsc:5536 — BEFORE gunfight onstartgametype (:5537) and the
//     timer loop (:5539). This is exactly where the real mod reassigns level.ontimelimit.
function private on_start()
{
    if ( !isdefined( level.gfhello_starts ) )
    {
        level.gfhello_starts = 0;
    }
    level.gfhello_starts++;

    // THE cadence instrument. Announce from on_start itself, every firing — the
    // on_connect banner samples once at connect during round 1, where the value is 1
    // under BOTH hypotheses, so it cannot discriminate.
    //   shows 1 and never again  -> per-MATCH
    //   shows 1, 2, 3 ...        -> per-ROUND (map fast-restart re-links)
    level thread announce_starts( level.gfhello_starts );

    println( "[GFHELLO] 3/4 on_start_gametype fired" );

    if ( isdefined( level.ontimelimit ) )
    {
        println( "[GFHELLO] 4/4 level.ontimelimit defined here -> reassignable. Probing (no-op)." );
        saved = level.ontimelimit;
        level.ontimelimit = &noop_probe;   // set ...
        level.ontimelimit = saved;         // ... and restore. Zero behavior change.
    }
    else
    {
        println( "[GFHELLO] WARNING: level.ontimelimit UNDEFINED at on_start_gametype" );
    }
}

function private noop_probe() { }

// ⚠ RETAIL RENDERS NUMBERS ONLY — see the header. `n` is printed bare, with no label,
// because a literal prefix would render as nothing and make the digit look unexplained.
// on_start_gametype fires before players are in the match, so wait for them rather than
// printing into an empty player list. On round 2+ they are already connected.
function private announce_starts( n )
{
    wait( 8 );
    foreach ( player in getplayers() )
    {
        player iprintlnbold( n );
    }
}

// On-screen confirmation. Retail BOCW has no dev console, so iprintlnbold is the ONLY
// observable signal here — println goes somewhere we cannot read. The banner reports
// level.gfhello_starts so the per-match vs per-round cadence is visible without logs.
function private on_player_connect()
{
    self thread hello_banner();
}

function private hello_banner()
{
    self endon( #"disconnect" );
    waitframe( 30 );   // let the player finish connecting

    starts = 0;
    if ( isdefined( level.gfhello_starts ) )
    {
        starts = level.gfhello_starts;
    }
    // Bare number, no label. The "^2[GFHELLO] hook live - on_start fired ...x" version of
    // this line rendered on retail as the single character "1" — the literal text is
    // stripped from ship builds and only the runtime integer survives. Printing it bare is
    // honest about what the player will actually see.
    self iprintlnbold( starts );
}
