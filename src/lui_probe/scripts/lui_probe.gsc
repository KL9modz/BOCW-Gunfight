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
// mechanism before the risky one:
//   P1  open the popup with NO data              -> does it appear at all in MP?
//   P2  set title/description to STOCK localized keys (#"...") -> does setluimenudata
//                                                   reach the widget and localize?
//   P3  set them to PLAIN strings                -> THE TEST: renders as-is, or crashes?
//
// Mirrors stock lui::open_generic_script_dialog (lui_shared.gsc:1040-1057) but
// non-blocking, so it needs no menu input and cannot hang. Builtins verified in
// reference/funcs_cw.csv.
//
// ── READOUT — the DEBUG-FEED convention (klaze, 2026-09-14) ───────────────────
// ONE complete line, every data point, printed continuously on the host feed, so any
// single screenshot captures the whole state. NO tagged-number drip (that is the
// deprecated mp_probe pattern — klaze does not read those). The line:
//
//   GF LUI  host:1  now:P3-PLAIN  P1empty open:1 close:1  P2stockkey open:1 close:1 set:1
//           P3plain open:1 close:1 set:1  survived:1  [melee=re-pop plain]
//
// open:1  = openluimenu returned a defined handle (the popup was created)
// close:1 = closeluimenu ran without the match dying
// set:1   = setluimenudata ran on the title+description
// The TEXT under test is on the POPUP, watched on screen: P3 should read
// "Gunfight Host" / "Timer 60s   4v4   Hijacked". A screenshot of that popup + this
// line (now:P3-PLAIN open:1) is the whole result.
//
// If the game crashes, the LAST line on screen shows which phase reached it; the crash
// dump's error_message field 2 is the hash of the offending string (tools/crack-hash.py).
//
// After the staged run it parks: press MELEE as host to re-open the plain popup. WRITES
// NOTHING to game state (no dvars, no stock fields).
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;

#namespace lui_probe;

// A localized key the MP client is guaranteed to ship (globallogic.gsc game.strings
// :5051-5061, the keys the LUIelemText calibration used).
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
    if ( isdefined( level.lui_probe_ran ) )
    {
        return;
    }
    level.lui_probe_ran = 1;

    // one flat state struct the status line reads and the phases write
    level.lp = spawnstruct();
    level.lp.now = "boot";
    level.lp.host = 0;
    level.lp.p1o = 0; level.lp.p1c = 0;
    level.lp.p2o = 0; level.lp.p2c = 0; level.lp.p2s = 0;
    level.lp.p3o = 0; level.lp.p3c = 0; level.lp.p3s = 0;
    level.lp.survived = 0;

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
        return; // all bots this match — nobody to show it to
    }
    host endon( #"disconnect" );

    level.lp.host = 1;
    level thread status_loop( host );   // the one continuous line starts now

    wait( 4 ); // let the host finish spawning into the world

    // ── P1 — empty popup: does it appear in an MP match? ──
    level.lp.now = "P1-empty";
    d = host openluimenu( "ScriptMessageDialog_Compact" );
    level.lp.p1o = isdefined( d ) ? 1 : 0;
    wait( 5 );
    if ( isdefined( d ) ) { host closeluimenu( d ); }
    level.lp.p1c = 1;

    // ── P2 — stock localized keys ──
    level.lp.now = "P2-stockkey";
    d = host openluimenu( "ScriptMessageDialog_Compact" );
    level.lp.p2o = isdefined( d ) ? 1 : 0;
    host setluimenudata( d, #"title", KEY_TITLE );
    host setluimenudata( d, #"description", KEY_BODY );
    level.lp.p2s = 1;
    wait( 5 );
    host closeluimenu( d );
    level.lp.p2c = 1;

    // ── P3 — PLAIN strings: the measurement ──
    level.lp.now = "P3-PLAIN";
    d = host openluimenu( "ScriptMessageDialog_Compact" );
    level.lp.p3o = isdefined( d ) ? 1 : 0;
    host setluimenudata( d, #"title", "Gunfight Host" );
    host setluimenudata( d, #"description", "Timer 60s   4v4   Hijacked" );
    level.lp.p3s = 1;
    wait( 6 );
    host closeluimenu( d );
    level.lp.p3c = 1;

    level.lp.survived = 1;
    level.lp.now = "done(melee=re-pop)";

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

// ONE complete line, every data point, every 2s — the debug-feed convention. A single
// screenshot at any moment captures the full state.
function private status_loop( host )
{
    level endon( #"game_ended" );
    host endon( #"disconnect" );

    for ( ;; )
    {
        s = level.lp;
        line = "^3GF LUI^7 host:" + s.host + " now:" + s.now
             + " ^5P1empty^7 open:" + s.p1o + " close:" + s.p1c
             + " ^5P2key^7 open:" + s.p2o + " set:" + s.p2s + " close:" + s.p2c
             + " ^5P3plain^7 open:" + s.p3o + " set:" + s.p3s + " close:" + s.p3c
             + " survived:" + s.survived;
        host iprintln( line );
        wait( 2 );
    }
}
