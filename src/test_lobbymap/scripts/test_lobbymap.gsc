// ─────────────────────────────────────────────────────────────────────────────
// TEST B2 — set the map FROM THE PREGAME LOBBY, with the builtin stock uses.
//
// Hook: scripts\core_common\load_shared.gsc  (FRONTEND — see ../gsc.conf)
// docs/notes/pregame-routes.md · B1 (src/test_sessionswitch/) · A4
//
// ── WHAT IS NEW HERE ─────────────────────────────────────────────────────────
// B1 runs the same sequence IN-MATCH, hooked at bb.gsc. This runs it in the
// PREGAME LOBBY, which only became possible when P1 measured that a server VM
// executes in the frontend (probe 51 = 63: is_frontend_map, private, MP, online,
// players present, one answering ishost()).
//
// That matters because klaze's goal is to pick the map *from the lobby*, and
// because there is NO map gametype-setting to write: the only map-shaped setting
// script reads anywhere is `allowmapscripting`, and the per-map bool array in
// mp_custom_game.ddl (`bool hash_3d4fd60ba0b69eb[mpmaps]`, 43 bits, one per map)
// is a SIBLING of `gametypesettings`, not inside it — so setgametypesetting()
// cannot reach it and the team-size save route does not generalise to the map.
//
// ── WHY switchmap_load AND NOT map() ─────────────────────────────────────────
// A4 used the Atian Menu's `map( name ); wait 1; switchmap_switch()` and never
// produced a clean switch. B1 established why: **map() takes one argument and has
// ZERO stock callers anywhere in the dump** — it cannot tell the session what
// gametype it is loading. Three stock systems use the two-argument form instead:
//     cp_common/load.gsc:412      switchmap_load( map, level.gametype )
//     callbacks_shared.gsc:2227   switchmap_preload( name, game_type )
//     zm_utility_zsurvival:153    switchmap_load( map, "" ) -> wait signal -> switch
//
// ⚠ NO `level endon( #"game_ended" )` ANYWHERE IN THE SWITCH PATH. A4 measured
//   that the load fires that notify mid-sequence and an endon kills the thread
//   inside the wait, so the commit never runs. That bug cost four runs.
//
// ── GUARDS, because A4 left a session half-torn-down ─────────────────────────
//   1. read_only   — default 1. Reports and switches nothing.
//   2. once-guard  — game. scope AND a dvar, capped at one attempt ever.
//   3. known map   — mp_zoo_rm, one klaze has carried to and PLAYED.
//      ⚠ mapexists() is USELESS as a guard (B5: it returns true for every name,
//        including invented ones), so the target must be known-good by history.
//
// ── PROBES (id*100000 + value; 99999 = undefined) ────────────────────────────
//   70xxxxx  frontend ticks. 0 = the frontend half never ran; read this FIRST
//   71xxxxx  attempts used (game. scope)
//   72xxxxx  1 = read_only, switched nothing · 2 = ran the live sequence
//   73xxxxx  seconds x10 until #"switchmap_preload_finished". 99999 = never
//            signalled inside the timeout, so the load never started and
//            NOTHING below it means anything
//
// ⚠ Stashed to dvars, not printed: the lobby may render nothing. The in-match
//   half prints the stash on the next match, exactly like test_frontend.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace test_lobbymap;

function private autoexec __init__system__()
{
    system::register( #"test_lobbymap", &__init__, undefined, undefined, undefined );
}

function private default_config()
{
    return {
        // ⚠ RUN AT 1 FIRST. Confirms the frontend half runs and the guards behave
        //   before anything can tear a session down.
        #read_only: 1,

        // ⚠ A map already carried to and played. B5 proved mapexists() cannot
        //   screen this for us.
        #target:    "mp_zoo_rm",

        // The gametype the session should be told it is loading. This is the whole
        // point of the two-argument form — map() could not say it.
        #gametype:  "gunfight",

        // Seconds to wait for #"switchmap_preload_finished". Zombies uses 25.
        #timeout:   25,

        // How long to sit in the lobby before acting, so the lobby is actually
        // configured rather than mid-transition.
        #settle:    20
    };
}

function private __init__()
{
    // A plain thread, not on_start_gametype: the frontend has no globallogic, so
    // that callback never dispatches there (test_frontend, P1).
    level thread lobby_watch( default_config() );
    callback::on_start_gametype( &on_start );
}

// ── the frontend half — this is the test ─────────────────────────────────────

function private lobby_watch( cfg )
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
        setdvar( #"gf_lm_70", ticks );

        if ( !isdefined( game.var_b2_fired ) && getdvarint( #"gf_lm_fired", 0 ) == 0 )
        {
            setdvar( #"gf_lm_71", 0 );
        }
        else
        {
            setdvar( #"gf_lm_71", 1 );
        }

        // Let the lobby settle before touching it.
        if ( ticks * 5 >= cfg.settle )
        {
            attempt( cfg );
            return;
        }

        wait( 5 );
    }
}

function private attempt( cfg )
{
    if ( cfg.read_only )
    {
        setdvar( #"gf_lm_72", 1 );
        return;
    }

    // ── once-guard, two carriers (B4's pattern). A switch loop in the FRONTEND
    //    would be worse than in-match: it would fire on every return to the lobby
    //    with no match to interrupt it.
    if ( isdefined( game.var_b2_fired ) || getdvarint( #"gf_lm_fired", 0 ) == 1 )
    {
        setdvar( #"gf_lm_72", 1 );
        return;
    }

    game.var_b2_fired = 1;
    setdvar( #"gf_lm_fired", 1 );
    setdvar( #"gf_lm_72", 2 );

    level thread do_switch( cfg );
}

// ⚠⚠ NO endon IN THIS FUNCTION. See the header — that is the A4 bug.
function private do_switch( cfg )
{
    start = gettime();

    switchmap_load( cfg.target, cfg.gametype );

    // switchmap_load is ASYNC and signals when the preload completes. Zombies
    // waits on exactly this with a 25s timeout (zm_utility_zsurvival.gsc:153).
    // The Atian menu waited one network frame instead, which is a candidate
    // explanation for A4 staging a load that never committed.
    // ⚠ VERBATIM from stock — zm_utility_zsurvival.gsc:154 is
    //     level waittilltimeout( 25, #"switchmap_preload_finished" );
    //   `waittilltimeout` is a BUILTIN called on level, not a util:: helper. An
    //   earlier draft of this file invented `util::waittill_notify_or_timeout`,
    //   which does not exist — the kind of name that compiles against nothing and
    //   dies at link. Copy the stock line; do not paraphrase it.
    level waittilltimeout( cfg.timeout, #"switchmap_preload_finished" );

    elapsed = int( ( gettime() - start ) / 100 );
    setdvar( #"gf_lm_73", elapsed );

    switchmap_switch();
}

// ── the in-match half — prints the stash ─────────────────────────────────────

function private on_start()
{
    level thread report();
}

function private report()
{
    wait( 10 );

    emit( 70, getdvarint( #"gf_lm_70", 0 ) );
    emit( 71, getdvarint( #"gf_lm_71", 99999 ) );
    emit( 72, getdvarint( #"gf_lm_72", 99999 ) );
    emit( 73, getdvarint( #"gf_lm_73", 99999 ) );
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
