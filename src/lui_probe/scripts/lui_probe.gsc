// ─────────────────────────────────────────────────────────────────────────────
// LUI probe — the in-match pause-menu popup as a free-text channel.
//
// Hook: scripts\mp_common\bb.gsc, mode=mp  (see ../gsc.conf)
//
// THE QUESTION. docs/notes/pause-menu.md found (by decompiling the client UI —
// docs/notes/lui-source.md) that the stock popup ScriptMessageDialog_Compact draws its
// title/description through BaseUtility's localize-ONLY-IF-hash helper (lui-source,
// core_ui_1364 #hash_1993de65911eb3f), so a PLAIN GSC string should render verbatim.
// That would be a host-side free-text popup with NO client payload — a channel above
// the ~4-line feed and one-line hint the project has lived with, and the opposite of
// the LUIelemText result where a plain string is a fatal crash (lui-elems.md).
//
// It is READ, not measured. This measures it, staged so the safe cases confirm the
// mechanism before the risky one, and so a crash at the end still leaves evidence:
//
//   P1  open the popup with NO data              -> does it appear at all in MP?
//   P2  set title/description to STOCK localized keys (#"...") -> does setluimenudata
//                                                   reach the widget and localize?
//   P3  set them to PLAIN strings                -> THE TEST: renders as-is, or crashes?
//
// Everything mirrors stock lui::open_generic_script_dialog (lui_shared.gsc:1040-1057)
// except it is non-blocking (open, hold, close on a timer) so it needs no menu input
// and cannot hang. Builtins verified in reference/funcs_cw.csv (openluimenu 1-2,
// setluimenudata 3, closeluimenu 1, ishost, getplayers).
//
// ── READOUT ──────────────────────────────────────────────────────────────────
// The feed (iprintlnbold, host) carries a NUMBER per phase — the project's proven
// channel — so each phase's number confirms it RAN and did not crash getting there:
//
//   700001  host found, starting
//   700011  P1 empty popup opened            (712 = closed ok)
//   700021  P2 stock-key popup opened        (722 = closed ok)
//   700031  P3 PLAIN-string popup opened     (732 = closed ok)
//   700099  all three survived
//
// The TEXT under test is on the POPUP, watched on screen:
//   P2 should show a localized title/body (from #"mp/…").
//   P3 should show  "Gunfight Host" / "Timer 60s   4v4   Hijacked"  <- the whole point.
//
// If the game crashes at P3, the crash dump's error_message field 2 is the hash of the
// offending string (tools/crack-hash.py) — same recipe as the LUIelemText crash.
//
// After the staged run, press MELEE as host to re-open the P3 plain popup for a longer
// look. WRITES NOTHING to game state (no dvars, no stock fields); the popup is drawn by
// the client and torn down each time.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;

#namespace lui_probe;

// A localized key the MP client is guaranteed to ship: both are in globallogic.gsc's
// game.strings (:5051-5061), which is why the LUIelemText calibration used them.
#define KEY_TITLE  #"mp/waiting_for_players"
#define KEY_BODY   #"mp/match_starting"

function private autoexec __init__system__()
{
    system::register( #"lui_probe", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &on_start );
}

function private on_start()
{
    // once per match, not once per round
    if ( isdefined( level.lui_probe_ran ) )
    {
        return;
    }
    level.lui_probe_ran = 1;

    level thread run();
}

// Return the human host player, or undefined if none yet.
function private find_host()
{
    foreach ( player in getplayers() )
    {
        if ( isplayer( player ) && !isbot( player ) && player ishost() )
        {
            return player;
        }
    }
    return undefined;
}

function private run()
{
    level endon( #"game_ended" );

    // on_start fires before anyone has spawned. Wait for the host to exist and settle.
    host = undefined;
    for ( i = 0; i < 60; i++ )
    {
        host = find_host();
        if ( isdefined( host ) )
        {
            break;
        }
        wait( 1 );
    }
    if ( !isdefined( host ) )
    {
        return; // no human host this match (all bots) — nothing to show
    }

    host endon( #"disconnect" );
    wait( 4 ); // let the player finish spawning into the world

    beat( host, 700001 );

    // ── P1 — does the popup appear at all in an MP match? ──
    beat( host, 700011 );
    d = host openluimenu( "ScriptMessageDialog_Compact" );
    wait( 5 );
    if ( isdefined( d ) )
    {
        host closeluimenu( d );
    }
    beat( host, 700012 );

    // ── P2 — stock localized keys: does setluimenudata reach the widget? ──
    beat( host, 700021 );
    d = host openluimenu( "ScriptMessageDialog_Compact" );
    host setluimenudata( d, #"title", KEY_TITLE );
    host setluimenudata( d, #"description", KEY_BODY );
    wait( 5 );
    host closeluimenu( d );
    beat( host, 700022 );

    // ── P3 — PLAIN strings: the measurement ──
    beat( host, 700031 );
    d = host openluimenu( "ScriptMessageDialog_Compact" );
    host setluimenudata( d, #"title", "Gunfight Host" );
    host setluimenudata( d, #"description", "Timer 60s   4v4   Hijacked" );
    wait( 6 );
    host closeluimenu( d );
    beat( host, 700032 );

    beat( host, 700099 );

    // Retrigger the plain popup on MELEE, so klaze can watch it as long as he likes.
    for ( ;; )
    {
        if ( host meleebuttonpressed() )
        {
            d = host openluimenu( "ScriptMessageDialog_Compact" );
            host setluimenudata( d, #"title", "Gunfight Host" );
            host setluimenudata( d, #"description", "Timer 60s   4v4   Hijacked" );
            wait( 5 );
            host closeluimenu( d );
        }
        waitframe( 1 );
    }
}

// One tagged number on the host feed — the reliable channel that says a phase ran.
function private beat( host, tag )
{
    host iprintlnbold( tag );
}
