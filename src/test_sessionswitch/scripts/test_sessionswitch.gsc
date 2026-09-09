// ─────────────────────────────────────────────────────────────────────────────
// TEST B1 — switch map with the builtin STOCK uses, and watch the SESSION.
//
// Hook: scripts\mp_common\bb.gsc, mode=mp  (see ../gsc.conf)
//
// ── WHY THIS EXISTS ──────────────────────────────────────────────────────────
// After the carry, "everywhere the map is written still says the last map -
// menu, scoreboard, friend list, activity, everything" (klaze, 2026-09-09).
//
// The carry is the Atian Menu's func_set_map:
//     map( name );  wait 1;  switchmap_switch();
// map() takes ONE argument and has ZERO stock callers anywhere in the dump. It
// cannot tell the session what gametype it is loading, and nothing in the game
// calls it.
//
// The same menu ships two variants it never wires to a map entry, and both pass
// the gametype. So do three stock systems:
//     cp_common/load.gsc:412         switchmap_load( map, level.gametype )  -> switch
//     callbacks_shared.gsc:2227      switchmap_preload( name, game_type )   -> switch
//     zm_utility_zsurvival.gsc:153   switchmap_load( map, "" ) -> waittilltimeout( 25,
//                                    #"switchmap_preload_finished" ) -> switch
//
// Campaign additionally tells the UI FIRST (cp_common/load.gsc:398):
//     setuimodelvalue( getuimodel( <lobby_root>, "transitionMapIdOverride" ), hash( map ) );
//
// ── THE CRITERION IS PRESENCE, AND HERE IS WHY THAT IS CLEAN ─────────────────
// Friend list and activity are platform presence - what Battle.net tells other
// people you are playing. Nothing in GSC writes them: the engine table's only
// presence-shaped builtin is resetinactivitytimer. So they can change ONLY when
// the engine's own session record changes. That makes them a binary readout of
// exactly the thing this test is asking about, and it is observable from any
// friend's screen or a second account.
//
//     presence shows the new map        -> the session moved. Goal B closes.
//     in-match UI new, presence old     -> reached the match, not the session. Its own row.
//     nothing changes, no load          -> read probe 41 first; the load may never have started.
//
// ── THE TWO WAITS THAT MATTER ────────────────────────────────────────────────
// 1. switchmap_load is ASYNC. It signals #"switchmap_preload_finished" as a level
//    notify; zombies waits on it with a 25s timeout. The menu waits one network
//    frame, which may be why A4's earlier runs staged a load that never committed.
// 2. The thread must NOT carry level endon( #"game_ended" ). A4 found that map()
//    fires that notify mid-sequence and the endon killed the thread inside the
//    wait, so switchmap_switch() never ran. This file's run() has no endon.
//
// ── PROBES (id*100000 + value; 99999 = undefined) ────────────────────────────
//   40xxxxx  transitionMapIdOverride, READ BEFORE anything is written.
//            99999 = the model does not exist on the MP side; the accessor chain
//            below is inferred from stock's pattern, not read, and this is the
//            check on it. Anything else = a real model and the chain is right.
//   41xxxxx  seconds until #"switchmap_preload_finished" signalled, x10.
//            99999 = it never signalled within 25s and the load did not start.
//            READ THIS BEFORE JUDGING PRESENCE. A load that never began proves
//            nothing about the session.
//   42xxxxx  1 = read_only, switched nothing. 2 = ran the live sequence.
//
// ── PROTOCOL ─────────────────────────────────────────────────────────────────
//  1. read_only = 1. Inject, restart. Read 40 and 42. Nothing else happens.
//  2. read_only = 0, target = a map ALREADY CARRIED TO. Inject, restart.
//  3. Read 41. Then look at: scoreboard, pause menu, AAR, and a friend's view of
//     your activity. Write down which say the NEW map and which say the OLD.
//  4. ⚠ Test a lobby return.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace test_sessionswitch;

function private autoexec __init__system__()
{
    system::register( #"test_sessionswitch", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &on_start );
}

function private default_config()
{
    return {
        // 1 = report the model and stop. Run this first; it is what validates the
        //     accessor chain before anything is written.
        #read_only:  1,

        // ⚠ ONLY a map already carried to. mapexists() returns 1 for everything (B5),
        //   loading an unloadable map hung the game once (A4), and there is no guard
        //   that can tell you in advance.
        #target:     "mp_zoo_rm",

        // 1 = also write transitionMapIdOverride first, the way campaign does.
        //     0 = switchmap_load alone. Two runs, one per value, separate the two
        //     hypotheses; a single run with both on cannot say which one mattered.
        #tell_ui:    1
    };
}

function private on_start()
{
    // NOT `level thread run()` under an endon. See the header - the sequence has to
    // outlive #"game_ended", which map-switching itself fires.
    level thread run( default_config() );
}

function private run( cfg )
{
    wait( 12 );

    // Already there? Then the live sequence would just reload the same map, and a
    // "presence updated" reading would mean nothing. Refuse rather than mislead.
    current = tolower( getdvarstring( #"sv_mapname" ) );

    // ── Probe 40: does the UI model exist on the MP side? ──────────────────────
    // Inferred chain: stock reaches named roots via getglobaluimodel() and reads
    // children with getuimodel( root, name ). The campaign accessor is a hashed
    // helper whose body was not found; this is the pattern every located caller
    // uses. 99999 here means the chain is wrong and tell_ui cannot work.
    root = getuimodel( getglobaluimodel(), "lobby_root" );
    model = undefined;
    before = undefined;

    if ( isdefined( root ) )
    {
        model = getuimodel( root, "transitionMapIdOverride" );

        if ( isdefined( model ) )
        {
            before = getuimodelvalue( model );
        }
    }

    emit( 40, before );

    if ( cfg.read_only )
    {
        emit( 42, 1 );
        return;
    }

    if ( current == cfg.target )
    {
        // 42 = 3: refused, already on the target. Change the target.
        emit( 42, 3 );
        return;
    }

    emit( 42, 2 );

    // ── The stock sequence ─────────────────────────────────────────────────────
    if ( cfg.tell_ui && isdefined( model ) )
    {
        // cp_common/load.gsc:399 - hash() of the map name, before the switch.
        setuimodelvalue( model, hash( cfg.target ) );
    }

    // The CURRENT gametype, read at runtime - util_shared.gsc:5873 is stock's own
    // accessor. Not a guess between "gunfight" and "gunfight_3v3".
    gametype = tolower( getdvarstring( #"g_gametype" ) );

    t0 = gettime();
    switchmap_load( cfg.target, gametype );

    // Zombies' wait, not the menu's. The load is asynchronous and signals when it
    // is ready; one network frame is a race that may have already cost A4 three
    // runs.
    level waittilltimeout( 25, #"switchmap_preload_finished" );
    elapsed = gettime() - t0;

    if ( elapsed >= 25000 )
    {
        // Never signalled. Do not switch onto a load that did not happen - that is
        // the "staged, never committed" state A4 left the session in.
        emit( 41, undefined );
        return;
    }

    emit( 41, int( elapsed / 100 ) );   // tenths of a second, so 41x00023 = 2.3s
    switchmap_switch();
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

    wait( 4 );
}
