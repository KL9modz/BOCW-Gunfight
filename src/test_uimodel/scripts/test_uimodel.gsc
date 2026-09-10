// ─────────────────────────────────────────────────────────────────────────────
// P8 — does `lobby_root`'s MAP model resolve in the SERVER FRONTEND VM?
//
// Hook:    scripts\core_common\load_shared.gsc  -> FRONTEND server VM (P1: runs
//          in the lobby, probe 51 = 63). Replace clientids_shared.gsc (proven).
//
// ── WHY THIS, AND WHY NOW ────────────────────────────────────────────────────
// P6c corrected a mistake: in the MATCH client VM `function_5f72e972(#"lobby_root")`
// RESOLVES (probe 96 = 1) and getuimodel discriminates (fake name -> 0). The old
// zeros meant "wrong names", not "no API". The names were the problem, and they
// were pure invention — dump-wide, `lobby_root` has exactly THREE known children:
//     "room"  "transitionMapIdOverride"  "fullscreenBlackCount"
// Nothing else this project guessed appears in the dump at all.
//
// The SAME mistake was made on the server side (P6a read control = 0) and never
// corrected — that probe used the junk names and had no root-resolves digit. So
// the real question was never asked:
//
//   ▶ In the SERVER FRONTEND VM — the one VM that BOTH runs in the lobby AND is
//     reliably injectable — does getuimodel(lobby_root, "transitionMapIdOverride")
//     resolve?
//
// That model is the map-transition override. `cp_common/load.gsc:398` — a SERVER
// GSC script — does exactly:
//     m = getuimodel( function_5f72e972( #"lobby_root" ), "transitionMapIdOverride" );
//     setuimodelvalue( m, hash( map ) );
// to set the campaign's transitioning map. If the model resolves here, that write
// is stock-precedented and reachable from a VM we own, in the lobby. That is the
// whole map route, and this read is its gate.
//
// ── READ-ONLY. Discipline from five crashes: change one thing, prove it. ──────
// No write. No getglobaluimodel (unproven + the prime crash suspect). No
// dev-flagged builtins. Only function_5f72e972 + getuimodel + isdefined, all
// type=0 and all exercised safely already, plus getlobbyuiscreen (0-arg, type=0).
//
// ── STASH IN LOBBY, PRINT IN MATCH (P7: the lobby has no text surface) ────────
// The server VM runs in BOTH; is_frontend_map() gates sampling to the lobby only.
// Stash the MAX seen so a lobby hit survives the transition into the match, where
// the same models may read 0.
//
// ── OUTPUT (id*100000+value; read via screen capture across frames) ──────────
//   71xxxxx  lobby ticks. 0 = never sampled in the frontend -> everything else moot
//   72xxxxx  resolve mask:  bit0 root defined
//                           bit1 "transitionMapIdOverride"  <- THE MAP MODEL
//                           bit2 "room"
//                           bit3 "fullscreenBlackCount"
//            15 = all four resolve; 1 = root only, no children (populated elsewhere)
//   73xxxxx  getlobbyuiscreen() — the lobby's UI-screen enum. No stock caller ever
//            read it; klaze's "lobby state" intuition. 88888 = defined non-int
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
    // Plain thread: the frontend has no globallogic, so on_start_gametype never
    // dispatches there (P1). callback for the in-match report half.
    level thread lobby_watch();
    callback::on_start_gametype( &on_start );
}

function private lobby_watch()
{
    wait( 3 );

    while ( true )
    {
        if ( util::is_frontend_map() )
        {
            sample();
        }

        wait( 6 );
    }
}

function private sample()
{
    stash_max( #"gf_um_71", getdvarint( #"gf_um_71", 0 ) + 1 );

    mask = 0;

    root = function_5f72e972( #"lobby_root" );
    if ( isdefined( root ) )
    {
        mask += 1;

        // getuimodel on a DEFINED root — P6c proved this is safe and discriminating.
        if ( isdefined( getuimodel( root, "transitionMapIdOverride" ) ) ) { mask += 2; }
        if ( isdefined( getuimodel( root, "room" ) ) )                    { mask += 4; }
        if ( isdefined( getuimodel( root, "fullscreenBlackCount" ) ) )    { mask += 8; }
    }

    stash_max( #"gf_um_72", mask );

    screen = getlobbyuiscreen();
    v = 88888;
    if ( isdefined( screen ) && isint( screen ) )
    {
        v = screen;
    }
    stash_max( #"gf_um_73", v );
}

function private stash_max( key, value )
{
    if ( value > getdvarint( key, 0 ) )
    {
        setdvar( key, value );
    }
}

function private on_start()
{
    level thread report();
}

function private report()
{
    wait( 10 );

    while ( true )
    {
        emit( 71, getdvarint( #"gf_um_71", 0 ) );
        emit( 72, getdvarint( #"gf_um_72", 0 ) );
        emit( 73, getdvarint( #"gf_um_73", 0 ) );
        wait( 5 );
    }
}

function private emit( id, value )
{
    v = 99999;
    if ( isdefined( value ) )
    {
        v = value;
    }

    foreach ( player in getplayers() )
    {
        player iprintlnbold( id * 100000 + v );
    }

    wait( 5 );
}
