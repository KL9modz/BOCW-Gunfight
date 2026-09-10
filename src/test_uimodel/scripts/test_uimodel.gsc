// ─────────────────────────────────────────────────────────────────────────────
// TEST P6a — enumerate the LOBBY'S UI MODEL TREE. Read-only.
//
// Hook: scripts\core_common\load_shared.gsc  (FRONTEND — see ../gsc.conf)
// docs/notes/pregame-routes.md P6
//
// ── WHY THIS IS THE LAST ROUTE STANDING ──────────────────────────────────────
// Seven routes to the pregame MAP are closed (see pregame-routes.md): no map
// gametype setting exists, every playlist/lobby/session builtin in the 4,481-row
// table is read-only, the per-map array sits outside gametypesettings, the save
// is cloud, adddebugcommand is nulled (probe 62 = 4), the DLL console is blocked
// by D10, and switchmap_load from the frontend crashes (B2).
//
// The LUI channel is the one nobody looked at — and LUI is the layer that OWNS
// the map picker.
//
// ── THE CHAIN IS STOCK, AND IT IS A BUILTIN ──────────────────────────────────
// cp_common/load.gsc:398, verbatim:
//     var_31924550 = getuimodel( function_5f72e972( #"lobby_root" ), "transitionMapIdOverride" );
//     setuimodelvalue( var_31924550, hash( var_83104433 ) );
//
// function_5f72e972 is a BUILTIN (1 arg, BlackOpsColdWar.exe+9715b00) present in
// BOTH the GSC and CSC tables, so an injected server script can reach it. Model
// names are PLAIN STRINGS, not hashes — which is why they can be guessed at all.
//
// ── WHAT THIS DOES ───────────────────────────────────────────────────────────
// Asks the lobby root for a list of candidate child models and reports which
// EXIST, as bitmasks. Nothing is written. This is B5's sweep shape applied to a
// different namespace.
//
// ⚠⚠ CONTROLS FIRST, AND B5 IS EXACTLY WHY. `mapexists()` looked like a perfect
//    guard until its control showed it returns true for EVERY name including
//    invented ones — an entire payload of 38 "results" that were noise. So probe
//    80 carries three knowns and one fake, and **if it does not read 7, every
//    bitmask below it is discarded, not interpreted.**
//
// ── PROBES (id*100000 + value) ───────────────────────────────────────────────
//   80xxxxx  CONTROL. bit0 "room" · bit1 "transitionMapIdOverride" ·
//            bit2 "fullscreenBlackCount" · bit3 "zzz_not_a_model"
//            **7 = the three real ones exist and the fake does not. TRUST.**
//            15 = everything "exists" → useless, discard the rest (the B5 failure)
//            0  = nothing resolves → the root or the accessor is wrong
//   81xxxxx  group A bits 0..14  (map-shaped names)
//   82xxxxx  group B bits 0..14  (playlist / gametype / lobby-state names)
//   83xxxxx  value of "transitionMapIdOverride" if it is an int, else 88888
//
// Names per group are listed beside each array below — bit 0 is the first entry.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace test_uimodel;

function private autoexec __init__system__()
{
    system::register( #"test_uimodel", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    level thread lobby_watch();
    callback::on_start_gametype( &on_start );
}

function private lobby_watch()
{
    wait( 3 );

    if ( !util::is_frontend_map() )
    {
        return;
    }

    ticks = 0;

    while ( true )
    {
        ticks++;
        setdvar( #"gf_um_79", ticks );

        // Sample repeatedly: the lobby tree may only be populated once the
        // player is actually in a configured lobby rather than the main menu.
        sample();

        wait( 8 );
    }
}

function private sample()
{
    // ── the control ─────────────────────────────────────────────────────────
    ctrl = 0;
    if ( model_exists( "room" ) )                    { ctrl += 1; }
    if ( model_exists( "transitionMapIdOverride" ) ) { ctrl += 2; }
    if ( model_exists( "fullscreenBlackCount" ) )    { ctrl += 4; }
    if ( model_exists( "zzz_not_a_model" ) )         { ctrl += 8; }
    setdvar( #"gf_um_80", ctrl );

    // group A — map-shaped
    groupa = array( "mapId", "mapName", "map", "selectedMap", "currentMap",
                    "mapIndex", "mapid", "mapImage", "nextMap", "mapDisplayName",
                    "transitionMapId", "mapIdOverride", "levelName", "mapList",
                    "mapCount" );

    // group B — playlist / gametype / lobby state
    groupb = array( "playlist", "playlistId", "playlistName", "gametype",
                    "gameMode", "gameModeName", "gametypeName", "modeId",
                    "lobbyState", "isHost", "maxPlayers", "teamSize",
                    "matchStarting", "customGame", "privateMatch" );

    setdvar( #"gf_um_81", maskof( groupa ) );
    setdvar( #"gf_um_82", maskof( groupb ) );

    v = 88888;
    m = getuimodel( function_5f72e972( #"lobby_root" ), "transitionMapIdOverride" );
    if ( isdefined( m ) )
    {
        raw = getuimodelvalue( m );
        if ( isdefined( raw ) && isint( raw ) )
        {
            v = raw;
        }
    }
    setdvar( #"gf_um_83", v );
}

function private model_exists( name )
{
    m = getuimodel( function_5f72e972( #"lobby_root" ), name );
    return isdefined( m );
}

function private maskof( names )
{
    mask = 0;
    bit  = 1;

    foreach ( name in names )
    {
        if ( model_exists( name ) )
        {
            mask += bit;
        }

        bit *= 2;
    }

    return mask;
}

// ── in-match half: print the stash ───────────────────────────────────────────

function private on_start()
{
    level thread report();
}

function private report()
{
    wait( 10 );

    // Control FIRST. If it is not 7, stop reading.
    emit( 80, getdvarint( #"gf_um_80", 99999 ) );
    emit( 81, getdvarint( #"gf_um_81", 99999 ) );
    emit( 82, getdvarint( #"gf_um_82", 99999 ) );
    emit( 83, getdvarint( #"gf_um_83", 99999 ) );
    emit( 79, getdvarint( #"gf_um_79", 0 ) );
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

    wait( 5 );
}
