// ─────────────────────────────────────────────────────────────────────────────
// LUI probe v2 — one dismissable pause-menu popup, host-GSC free text.
//
// Hook: scripts\mp_common\bb.gsc, mode=mp  (see ../gsc.conf)
//
// WHAT v1 ESTABLISHED (measured 2026-09-17, klaze):
//   - ScriptMessageDialog_Compact RENDERS full-screen in an MP match (openluimenu works).
//   - Plain strings in it do NOT crash (survived:1) — opposite of LUIelemText (lui-elems.md).
//   - BUT closeluimenu closes the SERVER handle and leaves the CLIENT overlay drawn, and the
//     dialog blockDuplicateInstance's — so v1's three staged popups masked each other and only
//     the empty first one ever showed. My title/description never rendered because that popup
//     had no data; P2/P3 were blocked behind it. And there was no way to dismiss it (force-close
//     doesn't run the client's close handler).
//
// v2 FIXES: exactly ONE popup, our text set from the start, and dismissed the RIGHT way — by the
// player pressing the dialog's Back button, which fires a menuresponse the client's close handler
// consumes (the same thing stock lui::open_generic_script_dialog waits for). This asks two things:
//   Q1  does our text render?  -> the popup should read "GUNFIGHT HOST" / "Timer 60s ... Hijacked".
//                                 Field names #"title"/#"description" are confirmed against the
//                                 decompiled frame (lui-source core_ui_1151: #Title/#Description via
//                                 the localize-if-hash helper; those xhashes == #"title"/#"description").
//   Q2  is it dismissable from GSC?  -> press the popup's BACK button. If the readout's resp: climbs
//                                       and closed:1, the Back menuresponse reached the server = the
//                                       dialog is interactive from GSC. If resp stays 0 whatever you
//                                       press ON THE POPUP, it is not GSC-dismissable.
//
// ── READOUT — the one-line debug-feed convention ([[debug-feed-one-line]]) ────
//   GF LUI host:1 open:1 set:1 resp:0 closed:0 waited:8s now:<instruction/state>
// A single screenshot of this line + the popup is the whole result.
//
// SAFETY: the popup stays up until you close it or 45s passes, then a force closeluimenu runs.
// If Back does not work and it lingers, open ESC -> Quit Match / restart to clear it (input is not
// hard-locked — ESC still opens the pause menu, as seen in v1). WRITES NOTHING to game state.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;

#namespace lui_probe;

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
    if ( isdefined( level.lui_probe_ran ) )
    {
        return;
    }
    level.lui_probe_ran = 1;

    level.lp = spawnstruct();
    level.lp.now     = "boot";
    level.lp.host    = 0;
    level.lp.open    = 0;
    level.lp.set     = 0;
    level.lp.resp    = 0;
    level.lp.closed  = 0;
    level.lp.waited  = 0;

    level thread run();
}

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
        return; // all bots — nobody to show it to
    }
    host endon( #"disconnect" );

    level.lp.host = 1;
    level thread status_loop( host );
    level thread wait_for_close( host );

    wait( 4 ); // let the host finish spawning in

    // ── ONE popup, our text set from the start ──
    level.lp.now = "opening popup";
    d = host openluimenu( "ScriptMessageDialog_Compact" );
    level.lp.open = isdefined( d ) ? 1 : 0;
    host setluimenudata( d, #"title", "GUNFIGHT HOST" );
    host setluimenudata( d, #"description", "Timer 60s   4v4   Hijacked" );
    level.lp.set = 1;
    level.lp.now = "SHOWING - press the popup BACK button to close";

    // Wait for the player to dismiss it (menuresponse), or 45s, whichever first.
    for ( t = 0; t < 45 && !level.lp.closed; t++ )
    {
        level.lp.waited = t;
        wait( 1 );
    }

    host closeluimenu( d ); // safety; does not run the client close handler
    if ( level.lp.closed )
    {
        level.lp.now = "you closed it - DISMISSABLE (good)";
    }
    else
    {
        level.lp.now = "timeout - Back never registered; ESC->Quit/restart to clear";
    }
}

// ANY menuresponse the host produces after the popup opened counts as an interaction reaching the
// server. Press the popup's Back specifically: if resp climbs, its Back button talks to GSC.
function private wait_for_close( host )
{
    level endon( #"game_ended" );
    host endon( #"disconnect" );

    for ( ;; )
    {
        host waittill( #"menuresponse" );
        level.lp.resp = level.lp.resp + 1;
        level.lp.closed = 1;
    }
}

// ONE complete line, every data point, every 2s.
function private status_loop( host )
{
    level endon( #"game_ended" );
    host endon( #"disconnect" );

    for ( ;; )
    {
        s = level.lp;
        line = "^3GF LUI^7 host:" + s.host
             + " open:" + s.open + " set:" + s.set
             + " resp:" + s.resp + " closed:" + s.closed
             + " waited:" + s.waited + "s ^5now:^7" + s.now;
        host iprintln( line );
        wait( 2 );
    }
}
