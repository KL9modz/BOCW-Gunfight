// ─────────────────────────────────────────────────────────────────────────────
// TEST — is an injected CLIENT script alive here, and is this replace target safe?
//
// The smallest possible client payload: a tick counter and a print. **It calls
// nothing else.** No UI model functions, no dev-flagged builtins, no dvar reads
// beyond its own counter.
//
// ── WHY IT EXISTS ────────────────────────────────────────────────────────────
// The match-VM model probe crashed with `load_shared.csc` (hook) + `devgui.csc`
// (replace), and the run could not say which of two things did it:
//
//   1. devgui.csc is safe to lose in the FRONTEND but not in the MATCH VM —
//      mp_common/devgui is a match script, and in the frontend run the payload
//      never executed, so its absence was the only effect and nothing exercised
//      whatever depends on it.
//   2. the model calls are fatal in the match VM — function_5f72e972/getuimodel
//      on a root that does not exist there, the way openfile was fatal rather
//      than inert earlier tonight.
//
// ▶ This payload removes hypothesis 2 entirely, so the result is unambiguous:
//     it crashes  -> the REPLACE TARGET is unsafe here (hypothesis 1)
//     it prints   -> the replace is innocent and THE MODEL CALLS are fatal (2)
//
// ⚠ Keep it this small. Every previous probe answered several questions at once
//   and every one of them produced a result that needed a follow-up launch to
//   interpret. This one answers exactly one.
//
// ── OUTPUT ───────────────────────────────────────────────────────────────────
//   88xxxxx  tick count, one line every 5s. Any number at all = it ran.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;

#namespace test_csc_alive;

function private autoexec __init__system__()
{
    system::register( #"test_csc_alive", &preinit, undefined, undefined, undefined );
}

function private preinit()
{
    // Both entry styles, because which one fires in which client VM is exactly
    // what this project keeps getting wrong. If the direct thread works, the
    // callback is harmless; if only the callback fires, the thread cost nothing.
    level thread beat( 1 );
    callback::on_localclient_connect( &on_connect );
}

function private on_connect( localclientnum )
{
    level thread beat( 2 );
}

function private beat( source )
{
    wait( 4 );

    n = 0;

    while ( true )
    {
        n++;

        // source*1000 + n : which entry point fired, and how many times.
        iprintlnbold( 88 * 100000 + source * 1000 + n );

        wait( 5 );
    }
}
