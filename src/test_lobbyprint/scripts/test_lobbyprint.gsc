// ─────────────────────────────────────────────────────────────────────────────
// TEST P7 — can the LOBBY talk back? Three print surfaces, tried from the
//           frontend server VM.
//
// Hook: scripts\core_common\load_shared.gsc  (FRONTEND — P1's proven hook)
// docs/notes/pregame-routes.md
//
// ── WHY ──────────────────────────────────────────────────────────────────────
// klaze, 2026-09-10: *"i dont like that we are using the match to check the
// lobby"*, and later: *"there is a text chat in the lobby that sometimes shows
// console messages"*.
//
// Every lobby measurement tonight was stashed to a dvar and read back inside a
// match, because nothing was known to render in the lobby. That indirection is
// what made three separate all-zeros results ambiguous — a zero could mean "no
// data" or "the sampler never ran", and it took four launches to tell those
// apart. **A direct lobby readout removes that whole class of ambiguity.**
//
// ✅ The server VM DOES run in the lobby — P1 measured it (probe 51 = 63:
//    is_frontend_map, private, multiplayer, online, players present, one
//    answering ishost()). So this payload will run. The only question is whether
//    anything it prints is visible.
//
// ── WHAT IS TRIED, AND WHY THESE THREE ───────────────────────────────────────
// All three are type=0 (live) in ate47's CW table for GSC:
//
//   1. player iprintlnbold()   the project's standard probe channel. P1 already
//                              tried this in the lobby and klaze saw nothing —
//                              retried here only as a control, so a total blank
//                              is distinguishable from "this one surface fails".
//   2. iprintln()              plain, unbold, level-scoped. Different code path
//                              from iprintlnbold and the likeliest candidate for
//                              the chat feed klaze describes.
//   3. printtoprightln()       a DIFFERENT UI SURFACE entirely (top-right), and
//                              type=0 for GSC where the CSC version is type=1.
//
// ⚠⚠ NOT TRIED: print() and println(). Both are **type=1**, the same dev flag as
//    openfile/fprintln/closefile — and calling that family CRASHED the game
//    earlier tonight rather than returning harmlessly. A dev-flagged builtin is
//    now treated as hostile, not inert. That lesson cost a launch; it is not
//    being re-learned here.
//
// ── HOW TO READ IT ───────────────────────────────────────────────────────────
// Sit in the lobby. Each surface prints a DISTINCT number every 5s, so whichever
// appears identifies which call works:
//
//   7710001   player iprintlnbold   — the control
//   7720002   iprintln
//   7730003   printtoprightln       — look TOP-RIGHT, not centre
//
// Nothing at all = the lobby has no GSC-reachable text surface, and stash-then-
// read-in-match stays the only channel. That is a real answer too.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace test_lobbyprint;

function private autoexec __init__system__()
{
    system::register( #"test_lobbyprint", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    // Plain thread, not on_start_gametype: the frontend has no globallogic, so
    // that callback never dispatches there (P1).
    level thread lobby_talk();
}

function private lobby_talk()
{
    wait( 4 );

    if ( !util::is_frontend_map() )
    {
        return;
    }

    while ( true )
    {
        // 1 — the control. Player-scoped, the channel every probe here uses.
        foreach ( player in getplayers() )
        {
            player iprintlnbold( 7710001 );
        }

        wait( 5 );

        // 2 — plain iprintln, level-scoped.
        iprintln( 7720002 );

        wait( 5 );

        // 3 — a different surface: top-right.
        printtoprightln( 7730003 );

        wait( 5 );
    }
}
