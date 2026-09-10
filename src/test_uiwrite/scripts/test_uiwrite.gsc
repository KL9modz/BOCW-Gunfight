// ─────────────────────────────────────────────────────────────────────────────
// P10 — WRITE the map model and notify LUI. The payoff, and the only GSC->LUI
//        map bridge that exists.
//
// Hook:    scripts\core_common\load_shared.gsc  -> FRONTEND server VM.
//          Replace scripts\core_common\clientids_shared.gsc (proven).
//
// ── WHY THIS IS THE LAST MAP TEST ────────────────────────────────────────────
// The Custom Games map picker, its map<->mode compatibility gate ("Choosing this
// map will automatically change your mode selection"), and the scoreboard map
// text are ALL LUI. frontend.gsc:on_menu_response proves GSC does not participate
// in map selection — it handles three unrelated events and nothing map-shaped.
// So the ONLY bridge from a VM we own (server frontend GSC) to LUI's map display
// is a UI MODEL that LUI binds to. We know exactly ONE such name:
// `transitionMapIdOverride`, which cp_common/load.gsc:398-399 writes as
//     setuimodelvalue( getuimodel( lobby_root, "transitionMapIdOverride" ), hash( map ) );
//
// P9 proved we can create it under lobby_root and it persists (mask 15, clean
// lobby return). P10 does the second, precedented half: set its value + notify.
//
// ── VALUE ────────────────────────────────────────────────────────────────────
// hash( "mp_miami" ) — a map the picker WARNS is Gunfight-incompatible, so any
// visible response (selection highlight, scoreboard text, load screen, or even
// the compatibility auto-mode-switch firing) is unmistakable against a Gunfight
// lobby. Exactly the stock call shape.
//
// ── WATCH THE SCREEN, not just the probe ─────────────────────────────────────
// The probe only confirms the calls RAN. The finding is what klaze SEES: does the
// map-select highlight, the scoreboard "Gunfight on X", the loading transition, or
// presence move? transitionMapIdOverride is the transition-time map, so the
// realistic best case is the load screen; anything in the lobby proper is a bonus
// and would be a major result.
//
// ── PROBES ───────────────────────────────────────────────────────────────────
//   71xxxxx  lobby ticks
//   76xxxxx  write mask: bit0 model resolved · bit1 setuimodelvalue returned
//            (we got past it, no crash) · bit2 readback == hash · bit3 forcenotify
//            returned. 15 = every call completed cleanly.
//   77xxxxx  low 5 digits of the readback hash (sanity the value stuck)
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace test_uiwrite;

function private autoexec __init__system__()
{
    system::register( #"test_uiwrite", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
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
    stash_max( #"gf_wr_71", getdvarint( #"gf_wr_71", 0 ) + 1 );

    root = function_5f72e972( #"lobby_root" );
    if ( !isdefined( root ) )
    {
        return;
    }

    // Do the write ONCE, ever.
    if ( getdvarint( #"gf_wr_done", 0 ) == 0 )
    {
        setdvar( #"gf_wr_done", 1 );

        mask = 0;

        // Match cp_common exactly: get (creating if needed), set, notify.
        m = getuimodel( root, "transitionMapIdOverride" );
        if ( !isdefined( m ) )
        {
            m = createuimodel( root, "transitionMapIdOverride" );
        }

        if ( isdefined( m ) )
        {
            mask += 1;

            wantval = hash( "mp_miami" );

            setuimodelvalue( m, wantval );
            mask += 2;                       // reached here => setuimodelvalue did not crash

            readback = getuimodelvalue( m );
            if ( isdefined( readback ) && readback === wantval )
            {
                mask += 4;
            }
            if ( isdefined( readback ) )
            {
                setdvar( #"gf_wr_77", readback % 100000 );
            }

            forcenotifyuimodel( m );
            mask += 8;                       // reached here => forcenotify did not crash
        }

        setdvar( #"gf_wr_76", mask );
    }
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
        emit( 71, getdvarint( #"gf_wr_71", 0 ) );
        emit( 76, getdvarint( #"gf_wr_76", 0 ) );
        emit( 77, getdvarint( #"gf_wr_77", 0 ) );
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
