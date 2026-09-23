// ─────────────────────────────────────────────────────────────────────────────
// HUD PROBE — the display channels gunfight_menu does not use yet, one per stage.
//
// Hook: scripts\mp_common\bb.gsc, mode=mp  (see ../gsc.conf). Server GSC only: no client
// payload, no memory write. Inject INSTEAD of gunfight_menu for this launch.
// Write-up + RECORD SHEET: docs/notes/hud-channels.md (file:line evidence for every stage).
//
// WHY: the menu draws with the feed (iprintln), the centre line (iprintlnbold), trigger hint
// strings and three stock LUI events. The dump holds more. Every stage below is a STOCK call
// shape; the only question each one asks is "does it draw in an MP match, where, and (with
// gf_hud_all 1) does a joiner see it".
//
// STAGES — gf_hud_secs each (default 7). The feed names the stage and what to look for.
//   group S — stock MP call shapes, safe by precedent
//    1 flash       lui::screen_flash red, then blue             FullScreenBlack + RGB
//    2 veil        lui::screen_fade to 45% black with drawHUD 1  a dark backdrop, HUD on top?
//    3 lower       hud_message::setlowermessage + 8 s count     the respawn line, lower centre
//    4 announce    announcement( forfeiting_in, 20, 0 )         engine announcement + a number
//    5 alive       luinotifyevent alive banner, 4 v 3            Gunfight's own "N v M" banner
//    6 emp         openluimenu EmpRebootIndicator, 5 s           the EMP reboot overlay
//    7 marker      two objectives: progress ring + host-only     world icons, per-player
//    8 hudflags    hud_visible 0 / hardcore HUD / no mini-score  HUD declutter switches
//   group E — EVENT-BACKED luielems: no clientfields, never opened by any stock script
//    9 bar         LUIelemBar x2: solid red box + a green bar filling 0->100%
//   10 counter     LUIelemCounter: a yellow number counting 10 -> 0
//   group U — no MP stock caller; retail behaviour unknown
//   11 topright    printtoprightln (only ever tried in the LOBBY, where nothing renders)
//   12 objtext     setclientcgobjectivetext( stock key ) - hold TAB, then ESC, to find it
//   13 timer       lui::timer -> HudElementTimer
//   14 mphint      MPHintText with a stock key
//   15 tempdialog  TempDialog with RUNTIME text (stock face.gsc feeds it runtime strings)
//   group M — a MENU MADE OF WORLD MARKERS (objectives: icons, rings, states, no text), host-only
//   16 mboard      5 icons placed once ahead-right: ring / done-state / team-colour cursors,
//                  value rings, then LOOK-TO-SELECT (the icon under the crosshair lights up)
//   17 mlock       1 icon re-placed every server frame beside the crosshair: does it trail a turn?
//   18 musing      objective_setplayerusing + progress: S&D's on-screen plant bar, from script
//   group P — PLAIN text into widgets that may localize it. OPT-IN (gf_hud_plain 1), on a
//             launch you can lose: each can be FATAL the way LUIelemText's plain string was
//             (docs/notes/lui-elems.md, error_message 2nd field = hash of the string).
//   19 lower_plain   20 objtext_plain   21 mphint_plain   22 announce_plain
//   group N — OPT-IN (gf_hud_nl 1), last: newlines inside ONE print
//   23 centre_nl   one iprintlnbold with two \n - three stacked centre lines, one line, or a
//                  closed match? (a raw \n in a sethintstring closed the match, hint-panel.md);
//                  then one iprintln with a \n in the feed
//
// READOUT — one feed line, re-printed every 3 s ([[debug-feed-one-line]]):
//   GF HUD <n>/<last> <name> o:<flag> - <what to look for>
// o: = what the server can report back (elements it believes open, menu handles, objective
// ids); '-' when there is nothing to report. A screen that shows the thing is the result;
// o: alone is not (docs/notes/mp-dvars.md: a readout of your own write proves nothing).
//
// DVARS — all optional, set through the bridge before the match
//   gf_hud_from   1   first stage. After a crash AT stage k: relaunch with k+1.
//   gf_hud_to    18   last stage (22 with the plain group)
//   gf_hud_plain  0   1 = run group P as well
//   gf_hud_nl     0   1 = run stage 23 (group N) as well
//   gf_hud_all    0   1 = every human gets the per-player stages (the JOINER run)
//   gf_hud_hold   1   setgametypesetting timelimit 0, so a solo round cannot time out mid-probe
//   gf_hud_secs   7   seconds per stage (3..30)
//   gf_hud_next       internal: the resume point. Each round is a level reload
//                     (globallogic.gsc:2058 map_restart), so the probe resumes from here.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\gameobjects_shared;
#using scripts\core_common\hud_message_shared;
#using scripts\core_common\lui_shared;
#using scripts\core_common\system_shared;

#namespace hud_probe;

function private autoexec __init__system__()
{
    system::register( #"hud_probe", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &on_start );
}

// on_start_gametype fires every ROUND (game-systems.md 14b), and the level is rebuilt with it,
// so this guard only stops a double start inside one round.
function private on_start()
{
    if ( isdefined( level.hud_probe_ran ) )
    {
        return;
    }
    level.hud_probe_ran = 1;
    level.hp_line = "^3GF HUD^7 starting";
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

// Who the per-player stages act on: the host, or (gf_hud_all 1) every human in the match.
function private targets( host )
{
    t = [];
    if ( getdvarint( #"gf_hud_all", 0 ) )
    {
        foreach ( player in getplayers() )
        {
            if ( isplayer( player ) && !isbot( player ) )
            {
                t[ t.size ] = player;
            }
        }
        return t;
    }
    t[ 0 ] = host;
    return t;
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
        return; // all bots - nobody to show it to
    }
    host endon( #"disconnect" );

    // timelimit 0 = no round clock: gunfight.gsc:1139 reads the setting live every 0.25 s and
    // globallogic.gsc:3289 skips the time limit at <= 0.
    if ( getdvarint( #"gf_hud_hold", 1 ) )
    {
        setgametypesetting( #"timelimit", 0 );
    }

    plain = getdvarint( #"gf_hud_plain", 0 );
    newline = getdvarint( #"gf_hud_nl", 0 );
    top = 18;
    if ( plain )
    {
        top = 22;
    }
    if ( newline )
    {
        top = 23;
    }
    last = getdvarint( #"gf_hud_to", top );
    if ( ( plain || newline ) && last < top )
    {
        last = top;
    }
    if ( last > top )
    {
        last = top;
    }

    secs = getdvarint( #"gf_hud_secs", 7 );
    if ( secs < 3 )
    {
        secs = 3;
    }
    if ( secs > 30 )
    {
        secs = 30;
    }

    n = getdvarint( #"gf_hud_next", 0 );
    resumed = 1;
    if ( n < 1 )
    {
        n = getdvarint( #"gf_hud_from", 1 );
        resumed = 0;
    }
    if ( n < 1 )
    {
        n = 1;
    }

    level thread status_loop( host );

    wait( 6 ); // let the host spawn in and the pre-round countdown clear

    if ( resumed )
    {
        cleanup( targets( host ), n );
    }

    if ( n > last )
    {
        hdr_all( host, "^3GF HUD^7 DONE - set gf_hud_next 0 to run it again" );
        return;
    }

    hdr_all( host, "^3GF HUD^7 probe: stages " + n + ".." + last + ", " + secs + " s each - record sheet in docs/notes/hud-channels.md" );
    wait( 3 );

    while ( n <= last )
    {
        if ( stage_on( n, plain, newline ) )
        {
            setdvar( #"gf_hud_next", n );     // a round reload mid-stage re-runs this stage
            run_stage( n, last, host, secs );
            wait( 2 );                         // a gap, so each stage reads on its own
        }
        n++;
        setdvar( #"gf_hud_next", n );
    }

    hdr_all( host, "^3GF HUD^7 DONE " + last + "/" + last + " - fill the record sheet in docs/notes/hud-channels.md" );
}

// Groups P (19-22) and N (23) run only when their own opt-in is set.
function private stage_on( n, plain, newline )
{
    if ( n >= 19 && n <= 22 )
    {
        return plain;
    }
    if ( n == 23 )
    {
        return newline;
    }
    return 1;
}

function private run_stage( n, last, host, secs )
{
    tg = targets( host );

    switch ( n )
    {
        case 1:
            st_flash( n, last, tg, secs );
            break;
        case 2:
            st_veil( n, last, tg, secs );
            break;
        case 3:
            st_lower( n, last, tg, secs, #"mp/waiting_to_spawn", "lower", "lower-centre stock line 'waiting to spawn' + an 8 s countdown" );
            break;
        case 4:
            st_announce( n, last, tg, secs, #"mp/opponent_forfeiting_in", "announce", "engine announcement 'opponent forfeiting in 20' - EVERY player sees it" );
            break;
        case 5:
            st_alive( n, last, tg, secs );
            break;
        case 6:
            st_emp( n, last, tg, secs );
            break;
        case 7:
            st_marker( n, last, tg, secs, host );
            break;
        case 8:
            st_hudflags( n, last, tg, secs );
            break;
        case 9:
            st_bar( n, last, tg, secs );
            break;
        case 10:
            st_counter( n, last, tg, secs );
            break;
        case 11:
            st_topright( n, last, tg, secs );
            break;
        case 12:
            st_objtext( n, last, tg, secs, #"mp/match_starting", "objtext", "objective text = 'Match starting': hold TAB, then open ESC - where is it?" );
            break;
        case 13:
            st_timer( n, last, tg, secs );
            break;
        case 14:
            st_mphint( n, last, tg, secs, #"mp/match_starting", "mphint", "MPHintText hint box reading 'Match starting'" );
            break;
        case 15:
            st_tempdialog( n, last, tg, secs );
            break;
        case 16:
            st_mboard( n, last, host );
            break;
        case 17:
            st_mlock( n, last, host );
            break;
        case 18:
            st_musing( n, last, tg, host );
            break;
        case 19:
            st_lower( n, last, tg, secs, "GF plain lower message", "lower_plain", "PLAIN text in the lower line - may be FATAL" );
            break;
        case 20:
            st_objtext( n, last, tg, secs, "GF plain objective text", "objtext_plain", "PLAIN objective text: TAB, then ESC - may be FATAL" );
            break;
        case 21:
            st_mphint( n, last, tg, secs, "GF plain hint text", "mphint_plain", "PLAIN text in MPHintText - may be FATAL" );
            break;
        case 22:
            st_announce( n, last, tg, secs, "GF plain announcement", "announce_plain", "PLAIN text announcement, EVERY player - may be FATAL" );
            break;
        case 23:
            st_centre_nl( n, last, tg, secs );
            break;
        default:
            break;
    }
}

// ── readout ──────────────────────────────────────────────────────────────────

function private hdr( n, last, name, o, look )
{
    level.hp_line = "^3GF HUD^7 " + n + "/" + last + " ^5" + name + "^7 o:" + o + " - " + look;
    hdr_print();
}

function private hdr_all( host, line )
{
    level.hp_line = line;
    hdr_print();
}

function private hdr_print()
{
    foreach ( player in getplayers() )
    {
        if ( isplayer( player ) && !isbot( player ) )
        {
            player iprintln( level.hp_line );
        }
    }
}

// The same line every 3 s, so any screenshot during a stage carries the stage number.
function private status_loop( host )
{
    level endon( #"game_ended" );
    host endon( #"disconnect" );

    for ( ;; )
    {
        wait( 3 );
        hdr_print();
    }
}

// A round reload mid-stage can leave a stage's state behind. Undo it before resuming.
function private cleanup( tg, n )
{
    foreach ( p in tg )
    {
        elem_close_if_open( p, #"luielembar", 0 );
        elem_close_if_open( p, #"luielembar", 1 );
        elem_close_if_open( p, #"luielemcounter", 0 );

        if ( n == 8 )
        {
            p setclientuivisibilityflag( "hud_visible", 1 );
            p setclienthudhardcore( 0 );
            p setclientminiscoreboardhide( 0 );
        }
        if ( n == 12 || n == 20 )
        {
            p setclientcgobjectivetext( "" );
        }
    }
}

// ── group S: stock MP call shapes ────────────────────────────────────────────

// lui_shared.gsc:730 screen_flash -> _screen_fade (:857) opens FullScreenBlack, the luielem
// lui_shared registers on BOTH sides in every mode (:147 / lui_shared.csc:285), so a vanilla
// joiner's client already has it. RGB: :905 takes a vector (zm_tungsten_end_fight.gsc:2090).
function private st_flash( n, last, tg, secs )
{
    hdr( n, last, "flash", "-", "the screen flashes RED, then BLUE (FullScreenBlack + RGB)" );
    foreach ( p in tg )
    {
        p thread lui::screen_flash( 0.15, 0.8, 0.6, 0.55, ( 1, 0, 0 ) );
    }
    wait( 2.5 );
    foreach ( p in tg )
    {
        p thread lui::screen_flash( 0.15, 0.8, 0.6, 0.55, ( 0, 0.4, 1 ) );
    }
    wait( secs - 2.5 );
}

// drawHUD is screen_fade's 7th argument (lui_shared.gsc:758 var_b675738a -> :962 #"drawhud");
// stock precedent zm_tungsten_end_fight.gsc:2090 fades to 0.1 white with it set. The question:
// does the HUD - and this feed - draw ON TOP of the overlay, i.e. is it a readable menu backdrop.
function private st_veil( n, last, tg, secs )
{
    hdr( n, last, "veil", "-", "screen dims to 45% black - are the HUD and this feed drawn ON TOP of it?" );
    foreach ( p in tg )
    {
        p lui::screen_fade( 0.4, 0.45, 0, ( 0, 0, 0 ), 0, "default", 1 );
    }
    wait( 1.5 );
    foreach ( p in tg )
    {
        p iprintln( "^7veil test line - readable over the dark?" );
        p iprintln( "^2veil test line - colours still bright?" );
    }
    wait( secs - 1.5 );
    foreach ( p in tg )
    {
        p lui::screen_fade( 0.4, 0, 0.45, ( 0, 0, 0 ), 1, "default", 1 );
    }
    wait( 0.5 );
}

// hud_message_shared.gsc:57 setlowermessage( text, time ) = luinotifyevent #"hash_424b9c54c8bf7a82"
// with the text and a whole-second countdown - the respawn line (globallogic_spawn.gsc:1419 is this
// exact shape). clearlowermessage (:74) takes it down.
function private st_lower( n, last, tg, secs, text, name, look )
{
    hdr( n, last, name, "-", look );
    foreach ( p in tg )
    {
        p hud_message::setlowermessage( text, 8 );
    }
    wait( secs );
    foreach ( p in tg )
    {
        p hud_message::clearlowermessage();
    }
}

// globallogic_defaults.gsc:54: announcement( game.strings[ #"opponent_forfeiting_in" ], 20, 0 ),
// and game.strings[ #"opponent_forfeiting_in" ] is #"mp/opponent_forfeiting_in"
// (globallogic.gsc:5047). A level-wide builtin: every client gets it.
function private st_announce( n, last, tg, secs, text, name, look )
{
    hdr( n, last, name, "-", look );
    announcement( text, 20, 0 );
    wait( secs );
}

// player_killed.gsc:2556 - stock Gunfight fires this on every death (gunfight.gsc:45 sets the
// gate level.var_4348a050): index 2 + the two sides' alive counts. Numbers are free.
function private st_alive( n, last, tg, secs )
{
    hdr( n, last, "alive", "-", "Gunfight's alive banner reading 4 v 3 (numbers are ours)" );
    foreach ( p in tg )
    {
        p luinotifyevent( #"hash_6b67aa04e378d681", 3, 2, 4, 3 );
    }
    wait( secs );
}

// empgrenade.gsc:151-153 / status_effect_pulse.gsc:47-49: an MP menu with two numbers, closed by
// name (empgrenade.gsc:214-221 getluimenu + closeluimenu).
function private st_emp( n, last, tg, secs )
{
    o = 0;
    foreach ( p in tg )
    {
        m = p openluimenu( "EmpRebootIndicator" );
        if ( isdefined( m ) )
        {
            o++;
            now = gettime();
            p setluimenudata( m, #"endtime", now + 5000 );
            p setluimenudata( m, #"starttime", now );
        }
    }
    hdr( n, last, "emp", o, "EMP 'rebooting' overlay with a 5 s progress, then it closes" );
    wait( 5.5 );
    foreach ( p in tg )
    {
        m = p getluimenu( "EmpRebootIndicator" );
        if ( isdefined( m ) )
        {
            p closeluimenu( m );
        }
    }
    if ( secs > 6 )
    {
        wait( secs - 6 );
    }
}

// Two world icons 400 units ahead of the host. LEFT: visible to all, its progress ring fills
// (objective_setprogress, sd.gsc:918 / gunfight.gsc:1004). RIGHT: hidden from everyone but the host
// (objective_setinvisibletoall + objective_setvisibletoplayer, spy_skill.gsc:1777-1784). The id pool
// and #"escort_goal" are what gunfight_menu's race markers already use (deathicons shape).
function private st_marker( n, last, tg, secs, host )
{
    ida = gameobjects::get_next_obj_id();
    idb = gameobjects::get_next_obj_id();

    if ( !isdefined( ida ) || !isdefined( idb ) )
    {
        hdr( n, last, "marker", "x", "no free objective id - skipped" );
        wait( 2 );
        return;
    }

    ang = host getplayerangles();
    fwd = anglestoforward( ( 0, ang[ 1 ], 0 ) );
    rgt = anglestoright( ( 0, ang[ 1 ], 0 ) );
    pa = host.origin + fwd * 400 + ( 0, 0, 48 );
    pb = host.origin + fwd * 400 + rgt * 250 + ( 0, 0, 48 );

    objective_add( ida, "active", pa, #"escort_goal" );
    objective_add( idb, "active", pb, #"escort_goal" );
    objective_setinvisibletoall( idb );
    objective_setvisibletoplayer( idb, host );

    hdr( n, last, "marker", ida + "," + idb, "2 icons ahead: LEFT fills a progress ring, RIGHT is HOST-ONLY (a joiner must not see it)" );

    for ( i = 0; i <= 10; i++ )
    {
        objective_setprogress( ida, i * 0.1 );
        wait( secs * 0.1 );
    }

    objective_delete( ida );
    objective_delete( idb );
    gameobjects::release_obj_id( ida );
    gameobjects::release_obj_id( idb );
}

// setclientuivisibilityflag( "hud_visible", n ): 18 stock uses; stock restores it on connect and
// spawn (player_connect.gsc:92, globallogic.gsc:2871). setclienthudhardcore /
// setclientminiscoreboardhide: zm_player.gsc:746-747 (engine builtins, not ZM script).
function private st_hudflags( n, last, tg, secs )
{
    hdr( n, last, "hudflags", "-", "3 steps x 2 s: WHOLE HUD hidden / HARDCORE HUD / mini-scoreboard hidden" );
    wait( 1.5 );
    foreach ( p in tg )
    {
        p setclientuivisibilityflag( "hud_visible", 0 );
    }
    wait( 2 );
    foreach ( p in tg )
    {
        p setclientuivisibilityflag( "hud_visible", 1 );
        p setclienthudhardcore( 1 );
    }
    hdr( n, last, "hudflags", "-", "step 2: HARDCORE HUD - what disappeared?" );
    wait( 2 );
    foreach ( p in tg )
    {
        p setclienthudhardcore( 0 );
        p setclientminiscoreboardhide( 1 );
    }
    hdr( n, last, "hudflags", "-", "step 3: mini-scoreboard hidden?" );
    wait( 2 );
    foreach ( p in tg )
    {
        p setclientminiscoreboardhide( 0 );
    }
    hdr( n, last, "hudflags", "-", "restored - is the HUD back to normal?" );
    wait( 1 );
}

// ── group E: event-backed luielems ───────────────────────────────────────────
// luielembar.gsc / luielemcounter.gsc register NO clientfield (their setup_clientfields only numbers
// the instance, lui_shared.gsc:58) and send every field through lui::function_bb6bcb89
// (lui_shared.gsc:185, the builtin call at :209) -> function_2891bd54, the luinotifyevent sibling at exe+3d1f190. So nothing is
// added to the clientfield table a vanilla joiner must match, and there is no material to resolve.
// Unknown: whether the MP client package ships the widgets (no stock script ever opens either).
// Field numbers are the order of each element's reset list (luielembar.csc / luielemcounter.csc
// function_fa582112), 1-based; colours/alpha go pre-quantised to 0..15, bar_percent to 0..127,
// exactly what the stock setters send (int( value * ( 16 - 1 ) ), int( value * ( 128 - 1 ) )).
// x / y are 15-px units, width / height 4-px units (the stock px helpers divide by 15 and 4).

function private st_bar( n, last, tg, secs )
{
    e = #"luielembar";
    foreach ( p in tg )
    {
        p openluielem( e, 0, 0 );
        p openluielem( e, 1, 0 );
    }
    o = 0;
    foreach ( p in tg )
    {
        if ( p function_3fc81484( e, 0 ) && p function_3fc81484( e, 1 ) )
        {
            o++;
        }
    }
    hdr( n, last, "bar", o, "LUIelemBar: a solid RED box upper-left + a GREEN bar under it filling left->right" );

    foreach ( p in tg )
    {
        //                 idx  x   y   w   h  alpha r   g   b  percent
        bar_set( p, 0, 8, 8, 75, 10, 15, 15, 0, 0, 127 );
        bar_set( p, 1, 8, 12, 75, 5, 12, 0, 15, 0, 0 );
    }
    wait( 2 );

    for ( i = 1; i <= 8; i++ )
    {
        foreach ( p in tg )
        {
            p lui::function_bb6bcb89( e, 1, 10, i * 16 - 1, 0 );
        }
        wait( 0.6 );
    }
    if ( secs > 7 )
    {
        wait( secs - 7 );
    }

    foreach ( p in tg )
    {
        elem_close( p, e, 0 );
        elem_close( p, e, 1 );
    }
}

// fields: 1 x  2 y  3 width  4 height  5 fadeOverTime  6 alpha  7 red  8 green  9 blue  10 bar_percent
function private bar_set( p, idx, x, y, w, h, a, r, g, b, pct )
{
    e = #"luielembar";
    p lui::function_bb6bcb89( e, idx, 1, x, 0 );
    p lui::function_bb6bcb89( e, idx, 2, y, 0 );
    p lui::function_bb6bcb89( e, idx, 3, w, 0 );
    p lui::function_bb6bcb89( e, idx, 4, h, 0 );
    p lui::function_bb6bcb89( e, idx, 6, a, 0 );
    p lui::function_bb6bcb89( e, idx, 7, r, 0 );
    p lui::function_bb6bcb89( e, idx, 8, g, 0 );
    p lui::function_bb6bcb89( e, idx, 9, b, 0 );
    p lui::function_bb6bcb89( e, idx, 10, pct, 0 );
}

// fields: 1 x  2 y  3 height  4 fadeOverTime  5 alpha  6 red  7 green  8 blue  9 number  10 horizontal_alignment
function private st_counter( n, last, tg, secs )
{
    e = #"luielemcounter";
    foreach ( p in tg )
    {
        p openluielem( e, 0, 0 );
    }
    o = 0;
    foreach ( p in tg )
    {
        if ( p function_3fc81484( e, 0 ) )
        {
            o++;
        }
    }
    hdr( n, last, "counter", o, "LUIelemCounter: a YELLOW number counting 10 -> 0" );

    foreach ( p in tg )
    {
        p lui::function_bb6bcb89( e, 0, 1, 60, 0 );
        p lui::function_bb6bcb89( e, 0, 2, 20, 0 );
        p lui::function_bb6bcb89( e, 0, 3, 1, 0 );
        p lui::function_bb6bcb89( e, 0, 5, 15, 0 );
        p lui::function_bb6bcb89( e, 0, 6, 15, 0 );
        p lui::function_bb6bcb89( e, 0, 7, 15, 0 );
        p lui::function_bb6bcb89( e, 0, 8, 0, 0 );
        p lui::function_bb6bcb89( e, 0, 10, 1, 0 );
        p lui::function_bb6bcb89( e, 0, 9, 10, 0 );
    }
    wait( 1.5 );

    for ( v = 9; v >= 0; v-- )
    {
        foreach ( p in tg )
        {
            p lui::function_bb6bcb89( e, 0, 9, v, 0 );
        }
        wait( 1 );
    }

    foreach ( p in tg )
    {
        elem_close( p, e, 0 );
    }
}

// Mirrors cluielem::close_luielem (lui_shared.gsc:79): drop the per-player de-dup cache
// function_bb6bcb89 keeps for this instance, so a re-open re-sends every field, then close.
function private elem_close( p, e, idx )
{
    if ( isdefined( p.var_3bc46b87 ) && isdefined( p.var_3bc46b87[ e ] ) && isdefined( p.var_3bc46b87[ e ][ idx ] ) )
    {
        p.var_3bc46b87[ e ][ idx ] = undefined;
    }
    p closeluielem( e, idx );
}

function private elem_close_if_open( p, e, idx )
{
    if ( p function_3fc81484( e, idx ) )
    {
        elem_close( p, e, idx );
    }
}

// ── group U: no MP stock caller ──────────────────────────────────────────────

// printtoprightln is type 0 (retail) on the SERVER table, type 1 on the client one. The only run
// was in the pregame lobby (pregame-routes.md P7), where iprintln did not render either.
function private st_topright( n, last, tg, secs )
{
    hdr( n, last, "topright", "-", "3 yellow lines in the TOP-RIGHT corner" );
    for ( i = 1; i <= 3; i++ )
    {
        printtoprightln( "GF HUD top-right line " + i, ( 1, 1, 0 ) );
        wait( 1 );
    }
    if ( secs > 3 )
    {
        wait( secs - 3 );
    }
}

// globallogic_ui.gsc:246-275 updateobjectivetext: the per-client objective text, a localized key
// from util::setobjectivetext (prop.gsc:533, sas.gsc:358) or "" - Gunfight sets none, so its stock
// value is "". Where the CW UI shows it is the question: scoreboard header, pause menu, or nowhere.
function private st_objtext( n, last, tg, secs, text, name, look )
{
    foreach ( p in tg )
    {
        p setclientcgobjectivetext( text );
    }
    hdr( n, last, name, "-", look );
    wait( secs + 5 );
    foreach ( p in tg )
    {
        p setclientcgobjectivetext( "" );
    }
}

// lui_shared.gsc:365 timer( n_time, str_endon, x = 1080, y = 200, height = 60 ): HudElementTimer.
// Stock defaults on purpose; no MP caller, so whether the menu ships in MP is the question.
function private st_timer( n, last, tg, secs )
{
    foreach ( p in tg )
    {
        p thread lui::timer( secs, undefined, 1080, 200, 60 );
    }
    waitframe( 1 );
    o = 0;
    foreach ( p in tg )
    {
        if ( isdefined( p getluimenu( "HudElementTimer" ) ) )
        {
            o++;
        }
    }
    hdr( n, last, "timer", o, "HudElementTimer: a " + secs + " s countdown, upper right by stock default" );
    wait( secs + 0.5 );
}

// mp_common/util.gsc:924-934 show_hint_text: MPHintText + #"hint_text_line" + a play_animation.
// Its only callers are CP (with localized keys), so group U; the plain form is group P.
function private st_mphint( n, last, tg, secs, text, name, look )
{
    o = 0;
    foreach ( p in tg )
    {
        m = p openluimenu( "MPHintText" );
        if ( isdefined( m ) )
        {
            o++;
            p setluimenudata( m, #"hint_text_line", text );
            p lui::play_animation( m, "display_noblink" );
        }
    }
    hdr( n, last, name, o, look );
    wait( secs );
    foreach ( p in tg )
    {
        m = p getluimenu( "MPHintText" );
        if ( isdefined( m ) )
        {
            p closeluimenu( m );
        }
    }
}

// ai/systems/face.gsc:233-272 _temp_dialog, copied call for call: stock writes a RUNTIME-built
// string into #"dialogtext" (self.propername + ": " + str_line, and "script id: " + ... at :282) and
// plain literals into #"title" - so if the menu ships in MP, plain text is its designed input.
function private st_tempdialog( n, last, tg, secs )
{
    setdvar( #"bgcache_disablewarninghints", 1 );
    o = 0;
    foreach ( p in tg )
    {
        if ( !isdefined( p getluimenu( "TempDialog" ) ) )
        {
            p openluimenu( "TempDialog" );
        }
        m = p getluimenu( "TempDialog" );
        if ( isdefined( m ) )
        {
            o++;
            p setluimenudata( m, #"dialogtext", "GF HUD probe: runtime text, t=" + gettime() );
            p setluimenudata( m, #"title", "GF HUD PROBE" );
        }
    }
    hdr( n, last, "tempdialog", o, "TempDialog: title 'GF HUD PROBE' + a line ending in t=<number>" );
    wait( secs );
    foreach ( p in tg )
    {
        m = p getluimenu( "TempDialog" );
        if ( isdefined( m ) )
        {
            p closeluimenu( m );
        }
    }
    setdvar( #"bgcache_disablewarninghints", 0 );
}

// ── group M: a menu made of world markers ───────────────────────────────────
// A marker is an objective: engine state the server networks, so a joiner sees exactly what the
// visibility calls let him see. What one can carry: an icon per objective TYPE, a progress ring
// (objective_setprogress), a state look ("active" / "done" / "empty" / "invisible" - the four stock
// values), a team
// (objective_setteam), per-player visibility (objective_setinvisibletoall + _setvisibletoplayer) -
// and no free text. So a marker menu is a NAVIGATOR (where am I, what is on, how much); the words
// stay in the feed / centre line. #"escort_goal" is the type the race gates measured rendering
// (docs/notes/racing.md run 2). Ids come from the 64-slot gametype pool
// (gameobjects_shared.gsc:5938) and go back after each stage.

function private obj_ids( k )
{
    ids = [];
    for ( i = 0; i < k; i++ )
    {
        id = gameobjects::get_next_obj_id();
        if ( !isdefined( id ) )
        {
            break;
        }
        ids[ ids.size ] = id;
    }
    return ids;
}

function private obj_free( ids )
{
    foreach ( id in ids )
    {
        objective_delete( id );
        gameobjects::release_obj_id( id );
    }
}

function private obj_host_only( id, host )
{
    objective_setinvisibletoall( id );
    objective_setvisibletoplayer( id, host );
}

// Five icons in a column on a plane 400 units ahead of the host's eye, 150 right of the crosshair,
// 45 units apart (~6 degrees, ~110 px at 1080p) - placed ONCE, so nothing swims when he turns; a
// world-space board, the way VR menus stay readable. Four cursor looks, then look-to-select.
function private st_mboard( n, last, host )
{
    k = 5;
    ids = obj_ids( k );
    if ( ids.size < k )
    {
        obj_free( ids );
        hdr( n, last, "mboard", "x", "not enough free objective ids - skipped" );
        wait( 2 );
        return;
    }

    eye = host geteye();
    ang = host getplayerangles();
    fwd = anglestoforward( ang );
    rgt = anglestoright( ang );
    up = anglestoup( ang );
    pos = [];
    for ( i = 0; i < k; i++ )
    {
        pos[ i ] = eye + fwd * 400 + rgt * 150 + up * ( 90 - i * 45 );
        objective_add( ids[ i ], "active", pos[ i ], #"escort_goal" );
        obj_host_only( ids[ i ], host );
    }

    // A - cursor = a full progress ring (sd.gsc:918 fills the same ring while planting)
    hdr( n, last, "mboard", ids.size, "A: 5 icons ahead-right; a full RING walks down them - a readable cursor?" );
    wait( 1 );
    for ( c = 0; c < k; c++ )
    {
        for ( i = 0; i < k; i++ )
        {
            objective_setprogress( ids[ i ], ( i == c ? 1 : 0 ) );
        }
        wait( 0.8 );
    }
    for ( i = 0; i < k; i++ )
    {
        objective_setprogress( ids[ i ], 0 );
    }

    // B - cursor = the only "active" one, the rest "done"
    hdr( n, last, "mboard", ids.size, "B: the rest go 'done', the cursor stays 'active' - what does 'done' look like?" );
    wait( 1 );
    for ( c = 0; c < k; c++ )
    {
        for ( i = 0; i < k; i++ )
        {
            if ( i == c )
            {
                objective_setstate( ids[ i ], "active" );
            }
            else
            {
                objective_setstate( ids[ i ], "done" );
            }
        }
        wait( 0.8 );
    }
    for ( i = 0; i < k; i++ )
    {
        objective_setstate( ids[ i ], "active" );
        obj_host_only( ids[ i ], host );
    }

    // C - cursor = your team, the rest neutral (spawn beacons set their owner team the same way)
    hdr( n, last, "mboard", ids.size, "C: the cursor takes YOUR team, the rest neutral - colour change? (or do the rest vanish?)" );
    wait( 1 );
    for ( c = 0; c < k; c++ )
    {
        for ( i = 0; i < k; i++ )
        {
            if ( i == c )
            {
                objective_setteam( ids[ i ], host.team );
            }
            else
            {
                objective_setteam( ids[ i ], #"none" );
            }
        }
        wait( 0.8 );
    }
    for ( i = 0; i < k; i++ )
    {
        objective_setteam( ids[ i ], #"none" );
        obj_host_only( ids[ i ], host );
    }

    // D - each ring shows a value: a column of five settings at a glance
    hdr( n, last, "mboard", ids.size, "D: value rings, top 20% ... bottom 100% - could each show a setting?" );
    for ( i = 0; i < k; i++ )
    {
        objective_setprogress( ids[ i ], ( i + 1 ) * 0.2 );
    }
    wait( 4 );
    for ( i = 0; i < k; i++ )
    {
        objective_setprogress( ids[ i ], 0 );
    }

    // E - look-to-select: the icon within ~4 degrees of the crosshair gets the ring
    hdr( n, last, "mboard", ids.size, "E: AIM at the icons - the one under your crosshair should fill its ring" );
    end = gettime() + 9000;
    sel = -1;
    while ( gettime() < end )
    {
        e = host geteye();
        f = anglestoforward( host getplayerangles() );
        best = -1;
        bestdot = 0.9976;
        for ( i = 0; i < k; i++ )
        {
            d = vectordot( f, vectornormalize( pos[ i ] - e ) );
            if ( d > bestdot )
            {
                bestdot = d;
                best = i;
            }
        }
        if ( best != sel )
        {
            if ( sel >= 0 )
            {
                objective_setprogress( ids[ sel ], 0 );
            }
            if ( best >= 0 )
            {
                objective_setprogress( ids[ best ], 1 );
            }
            sel = best;
        }
        waitframe( 1 );
    }

    obj_free( ids );
}

// One icon re-placed every server frame just below-right of the crosshair. Stock moves a marker at
// the same rate (spy_skill.gsc:1830, one objective_setposition per function_60d95f53() ms). The
// question is feel: pinned while still, and how far it trails a fast turn. o: = the frame in ms.
function private st_mlock( n, last, host )
{
    ids = obj_ids( 1 );
    if ( ids.size < 1 )
    {
        hdr( n, last, "mlock", "x", "no free objective id - skipped" );
        wait( 2 );
        return;
    }
    id = ids[ 0 ];
    objective_add( id, "active", host geteye(), #"escort_goal" );
    obj_host_only( id, host );

    ms = function_60d95f53();
    hdr( n, last, "mlock", ms + "ms", "an icon glued below-right of the crosshair: hold still, then FLICK left/right, up/down - does it trail?" );
    end = gettime() + 12000;
    while ( gettime() < end )
    {
        ang = host getplayerangles();
        p = host geteye() + anglestoforward( ang ) * 300 + anglestoright( ang ) * 60 - anglestoup( ang ) * 45;
        objective_setposition( id, p );
        waitframe( 1 );
    }

    obj_free( ids );
}

// The on-screen capture bar, from script. S&D's plant bar is objective state, not a HUD call: the
// planter becomes the objective's user (sd.gsc:884 objective_setplayerusing), the fill is
// objective_setprogress (:918), objective_clearallusing (:952) ends it. Gunfight's own zone type
// (gunfight.gsc:883 #"hash_56c11247a60bfd3c") is loaded in every Gunfight match and draws a capture
// bar in stock overtime; its game-mode flags 1 / 2 are the allies / axis capture looks
// (gunfight.gsc:1008 set_flags -> gameobjects_shared.gsc:6048). Every target is made a user.
function private st_musing( n, last, tg, host )
{
    ids = obj_ids( 1 );
    if ( ids.size < 1 )
    {
        hdr( n, last, "musing", "x", "no free objective id - skipped" );
        wait( 2 );
        return;
    }
    id = ids[ 0 ];
    ang = host getplayerangles();
    objective_add( id, "active", host.origin + anglestoforward( ( 0, ang[ 1 ], 0 ) ) * 250 + ( 0, 0, 40 ), #"hash_56c11247a60bfd3c" );
    foreach ( p in tg )
    {
        objective_setplayerusing( id, p );
    }
    objective_setgamemodeflags( id, 1 );

    hdr( n, last, "musing", id, "a CAPTURE BAR on screen filling over about 7 seconds, plus the Gunfight flag icon ahead" );
    for ( i = 0; i <= 10; i++ )
    {
        objective_setprogress( id, i * 0.1 );
        wait( 0.7 );
    }
    wait( 1 );

    objective_clearallusing( id );
    objective_setprogress( id, 0 );
    obj_free( ids );
}

// ── group N: newlines inside one print (opt-in, gf_hud_nl 1) ─────────────────
// In MP, several iprintlnbold calls do not stack: the centre shows one line (recorded 2026-09-16).
// The Atian engine - and MuzzMan's copy, byte-identical - draws its menu in the centre ONLY in
// Zombies: menu_drawing_function is iprintlnbold when sessionmodeiszombiesgame(), iprintln otherwise,
// and get_menu_size_count is 5 in Zombies, 2 elsewhere (t8-atian-menu coldwar/scripts/core_common/
// menu.gsc). So multi-line centre text is the Zombies HUD, not a trick. What nobody has tried in MP is
// ONE message carrying newlines. A raw newline in a sethintstring closed the match (hint-panel.md),
// hence opt-in and last.
function private st_centre_nl( n, last, tg, secs )
{
    hdr( n, last, "centre_nl", "-", "ONE centre print with 2 newlines: 3 stacked lines, one line, or a closed match?" );
    wait( 1.5 );
    foreach ( p in tg )
    {
        p iprintlnbold( "^3GF line one\n^2GF line two\n^5GF line three" );
    }
    wait( secs );

    hdr( n, last, "centre_nl", "-", "now the FEED: one iprintln with a newline - two feed lines?" );
    wait( 1.5 );
    foreach ( p in tg )
    {
        p iprintln( "^3GF feed line A\n^2GF feed line B" );
    }
    wait( secs );
}

