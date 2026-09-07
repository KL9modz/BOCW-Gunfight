// ─────────────────────────────────────────────────────────────────────────────
// Hello-world: prove the MP injection path before building the real mod.
//
// Hook: scripts\mp_common\bb.gsc, mode=mp  (see ../gsc.conf)
// Model: mirrors the toolchain's own T9 example AND stock bb.gsc:
//        autoexec -> system::register -> callback::on_start_gametype
//        (t7-compiler-custom dev_csc_inj@4de00c8 Default Project/T9/scripts/headers.gsc;
//         bocw-source@edd94bd scripts/mp_common/bb.gsc:12)
//
// Changes NO gameplay. It only logs, and probes that level.ontimelimit is
// reassignable, restoring it immediately. Syntax matches the compiler's example
// (no `function` keyword; `#include`; `autoexec name()`).
// ─────────────────────────────────────────────────────────────────────────────

#include scripts\core_common\callbacks_shared;
#include scripts\core_common\system_shared;
#include scripts\core_common\util_shared;

#namespace gunfight_hello;

// (1) Fires the instant the injected script is linked into the MP VM — exactly as
//     stock bb.gsc:12 (`autoexec __init__system__`) does for itself.
autoexec __init__system__()
{
    logprint( "[GFHELLO] 1/4 autoexec fired: injected script linked into MP VM\n" );
    system::register( "gunfight_hello", &__init__, undefined, undefined );
}

// (2) Called by the system framework after registration; wire runtime callbacks.
__init__()
{
    logprint( "[GFHELLO] 2/4 __init__ fired: system::register callback ran\n" );
    callback::on_start_gametype( &on_start );
    callback::on_connect( &on_player_connect );
}

// (3) Fires at globallogic.gsc:5536 — BEFORE gunfight onstartgametype (:5537) and the
//     timer loop (:5539). This is exactly where the real mod reassigns level.ontimelimit.
//     NOTE: log once per firing. If this prints more than once per match, on_start_gametype
//     is per-ROUND (map fast-restart) — record that; the real mod relies on it.
on_start()
{
    logprint( "[GFHELLO] 3/4 on_start_gametype fired\n" );

    if ( isdefined( level.ontimelimit ) )
    {
        logprint( "[GFHELLO] 4/4 level.ontimelimit defined here -> reassignable. Probing (no-op).\n" );
        saved = level.ontimelimit;
        level.ontimelimit = &noop_probe;   // set ...
        level.ontimelimit = saved;         // ... and restore. Zero behavior change.
    }
    else
    {
        logprint( "[GFHELLO] WARNING: level.ontimelimit UNDEFINED at on_start_gametype\n" );
    }
}

noop_probe() { }

// On-screen confirmation for testers without console-log access.
on_player_connect()
{
    self thread hello_banner();
}

hello_banner()
{
    self endon( #"disconnect" );
    waitframe( 30 );   // let the player finish connecting
    self iprintlnbold( "^2[GFHELLO] MP injection hook is live" );
}
