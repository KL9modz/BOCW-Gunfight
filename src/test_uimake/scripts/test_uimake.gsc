// ─────────────────────────────────────────────────────────────────────────────
// P9 — can the SERVER frontend VM CREATE the missing map model under lobby_root?
//
// Hook:    scripts\core_common\load_shared.gsc  -> FRONTEND server VM (P1).
//          Replace scripts\core_common\clientids_shared.gsc (proven safe).
//
// ── THE HYPOTHESIS ───────────────────────────────────────────────────────────
// P8: lobby_root RESOLVES in the server frontend VM but has zero children — no
// transitionMapIdOverride. Yet the same root resolves in every VM tested, which
// says it is a SHARED named root, not a per-VM copy. So the child may be absent
// only because no MP server script creates it (campaign's cp_common/load.gsc does,
// and it is not loaded in MP).
//
// createuimodel( parent, "name" ) creates a child and returns its handle — stock
// idiom is setuimodelvalue( createuimodel( parent, name ), value ) (bot.gsc:83,
// aat_shared, spray gestures). This asks the FIRST half only: can the server VM
// create `transitionMapIdOverride` under lobby_root, and does it then resolve?
//
// ⚠ CREATE ONLY. No setuimodelvalue — that is P10, and only if this resolves.
//   Staged because five crashes came from stacking. A bare createuimodel is an
//   allocation returning a handle; writing a value or notifying LUI is the part
//   more likely to touch a binding that does not exist. One step.
//
// ⚠ GUARDED ONCE (dvar). Creating every sample could leak or re-notify.
//
// ── PROBES (id*100000+value) — stash in lobby (P7), print in match ───────────
//   71xxxxx  lobby ticks. 0 = never sampled the frontend
//   74xxxxx  mask:  bit0 root defined
//                   bit1 transitionMapIdOverride resolved BEFORE create (expect 0)
//                   bit2 createuimodel returned a defined handle
//                   bit3 transitionMapIdOverride resolves AFTER create  <- THE WIN
//            e.g. 13 = root + created + now-resolves, pre-create was 0. Ideal.
//   75xxxxx  getlobbyuiscreen() (state re-read; 23 in Custom Games per P8)
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace test_uimake;

function private autoexec __init__system__()
{
    system::register( #"test_uimake", &__init__, undefined, undefined, undefined );
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
    stash_max( #"gf_mk_71", getdvarint( #"gf_mk_71", 0 ) + 1 );

    mask = 0;

    root = function_5f72e972( #"lobby_root" );
    if ( isdefined( root ) )
    {
        mask += 1;

        // Pre-create state (expect not-yet-present).
        if ( isdefined( getuimodel( root, "transitionMapIdOverride" ) ) )
        {
            mask += 2;
        }

        // Create ONCE, ever, for this process.
        if ( getdvarint( #"gf_mk_created", 0 ) == 0 )
        {
            setdvar( #"gf_mk_created", 1 );

            h = createuimodel( root, "transitionMapIdOverride" );
            if ( isdefined( h ) )
            {
                setdvar( #"gf_mk_handle", 1 );
            }
        }

        if ( getdvarint( #"gf_mk_handle", 0 ) == 1 )
        {
            mask += 4;
        }

        // Post-create: does the child resolve now?
        if ( isdefined( getuimodel( root, "transitionMapIdOverride" ) ) )
        {
            mask += 8;
        }
    }

    stash_max( #"gf_mk_74", mask );

    screen = getlobbyuiscreen();
    v = 88888;
    if ( isdefined( screen ) && isint( screen ) )
    {
        v = screen;
    }
    stash_max( #"gf_mk_75", v );
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
        emit( 71, getdvarint( #"gf_mk_71", 0 ) );
        emit( 74, getdvarint( #"gf_mk_74", 0 ) );
        emit( 75, getdvarint( #"gf_mk_75", 0 ) );
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
