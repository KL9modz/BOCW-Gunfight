// ─────────────────────────────────────────────────────────────────────────────
// LOBBY STATE PROBE — read-only. Captures what the session says the match IS.
//
// Hook: scripts\mp_common\bb.gsc, mode=mp  (see ../gsc.conf)
//
// ── WHY ──────────────────────────────────────────────────────────────────────
// 2026-09-11: gunfight_menu's SESSION map method (switchmap_load + switchmap_switch)
// switched the map and the LOBBY followed — the thing the Atian carry never did
// ("the scoreboard lies", menu-map.md). This probe records the resulting state so
// it can be told apart from a fluke, and so the next lobby can be compared to it.
//
// ── HOW TO RUN ───────────────────────────────────────────────────────────────
//   inject.sh lobby_state  ->  start the match FROM THE LOBBY  ->  read the pages
// The lobby route is the point: it reloads whatever the lobby believes the map is.
//
// ── HOW TO READ ──────────────────────────────────────────────────────────────
// Labelled text, 3 lines per page, one page every 5s, looping for the whole round.
// Every value is printed through s(): "?" means UNDEFINED, "-" or -1 means the dvar
// is not set. Line numbers LS1..LS12 are stable so a photo of any page is unambiguous.
//
// Text renders because tools/strip-strhdr.ps1 removed the 3-byte header ACTS puts
// in front of every string literal — the header the engine reads as "encrypted" and
// turns into garbage. That is the same fix that made the map name reach the engine.
// The com_maxclients line is ALSO emitted as mp_probe's 1xxxxx tag at the end of each
// pass, so the one number the notes key on survives even if text does not.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;

#namespace lobby_state;

function private autoexec __init__system__()
{
    system::register( #"lobby_state", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &on_start );
}

function private on_start()
{
    level thread readout_loop();
}

function private readout_loop()
{
    level endon( #"game_ended" );

    // Let globallogic finish populating level.* and the gametype settings.
    wait( 2 );

    for ( pass = 1; ; pass++ )
    {
        // Page 1 — the map, by every name the engine keeps for it.
        say( "LS1 sv_mapname=" + s( getdvarstring( #"sv_mapname", "-" ) ) );
        say( "LS2 mapname=" + s( getdvarstring( #"mapname", "-" ) ) + " ui_mapname=" + s( getdvarstring( #"ui_mapname", "-" ) ) );
        say( "LS3 rootmap=" + s( getrootmapname() ) );
        wait( 5 );

        // Page 2 — the gametype, by every name.
        say( "LS4 g_gametype=" + s( getdvarstring( #"g_gametype", "-" ) ) + " ui_gametype=" + s( getdvarstring( #"ui_gametype", "-" ) ) );
        say( "LS5 level.gametype=" + s( level.gametype ) + " teambased=" + s( isgametypeteambased() ) );
        say( "LS6 timelimit=" + s( getgametypesetting( #"timelimit" ) ) + " roundwinlimit=" + s( getgametypesetting( #"roundwinlimit" ) ) );
        wait( 5 );

        // Page 3 — the slot budget. com_maxclients is the number that decides 6v6.
        say( "LS7 com_maxclients=" + s( getdvarint( #"com_maxclients", -1 ) ) + " sv_maxclients=" + s( getdvarint( #"sv_maxclients", -1 ) ) );
        say( "LS8 maxplayers=" + s( getgametypesetting( #"maxplayers" ) ) + " teamcount=" + s( level.teamcount ) + " maxteam=" + s( level.maxteamplayers ) );
        say( "LS9 players all=" + s( getplayers().size ) + " allies=" + s( getplayers( #"allies" ).size ) + " axis=" + s( getplayers( #"axis" ).size ) );
        wait( 5 );

        // Page 4 — session mode, and what the menu had been set to when this ran.
        say( "LS10 private=" + s( sessionmodeisprivate() ) + " online=" + s( sessionmodeisonlinegame() ) + " mode=" + s( sessionmodeabbreviation() ) );
        say( "LS11 gf_map_method=" + s( getdvarint( #"gf_map_method", -1 ) ) + " gf_team_size=" + s( getdvarint( #"gf_team_size", -1 ) ) + " gf_timer=" + s( getdvarint( #"gf_timer_seconds", -1 ) ) );
        say( "LS12 pass=" + pass );
        wait( 5 );

        // Numeric fallback, mp_probe's convention: 100008 = 8 slots, 100012 = 12.
        bold( 100000 + getdvarint( #"com_maxclients", 0 ) );
        wait( 5 );
    }
}

// Every value goes through this so an undefined read prints "?" instead of killing
// the thread mid-page.
function private s( v )
{
    if ( !isdefined( v ) )
    {
        return "?";
    }

    return "" + v;
}

function private say( txt )
{
    foreach ( player in getplayers() )
    {
        player iprintln( txt );
    }
}

function private bold( v )
{
    foreach ( player in getplayers() )
    {
        player iprintlnbold( v );
    }
}
