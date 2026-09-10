// ─────────────────────────────────────────────────────────────────────────────
// TEST P1 — does GSC run in the PREGAME LOBBY, and what can it see there?
//
// Hook: scripts\core_common\load_shared.gsc  ⚠ NOT bb.gsc  (see ../gsc.conf)
// Replace: scripts\core_common\clientids_shared.gsc, as always.
//
// ── WHY THIS EXISTS ──────────────────────────────────────────────────────────
// Every note in this project said "nothing GSC runs in the pregame lobby". That
// was never measured, and the CW dump says otherwise. frontend.gsc's
// gametype_init handler sets gamestate::set_state(#"pregame") - it IS the
// pregame server script - and eleven stock GSC files guard on
// util::is_frontend_map(), two of them inside system preinits (bot.gsc:39,
// player_shared.gsc:29): stock does not guard against a VM it never runs in.
// ate47's BO4 capture (t8-atian-menu docs/notes/loaded/link_frontend.txt -
// BO4, same engine lineage, NOT CW) puts numbers on it: a SERVER VM with 190
// scripts linked, among them callbacks_shared, system_shared, util_shared,
// load_shared and clientids_shared. And frontend.csc:2918-2920 calls
// getgametypesetting() from inside the lobby-pose state, so the engine keeps a
// gametype-setting store while the lobby is being configured.
//
// What nobody knows: whether that store is the one the match launches with,
// whether setgametypesetting() writes it from here, and whether the per-side
// cap the lobby enforces follows #"maxplayers" the way the match does (L6).
// If it does, team size is fixed BEFORE anyone is seated, by the stock join
// path, with no late-join hack at all. docs/notes/pregame-routes.md.
//
// ── HOW IT WORKS ─────────────────────────────────────────────────────────────
// The same payload links in the frontend AND in the match (load_shared hooks
// every VM). util::is_frontend_map() - the check stock itself uses, e.g.
// bot.gsc:38 - decides which half runs.
//
//   frontend half   samples every 10s and STASHES each reading in a dvar,
//                   gf_fe_<id>. Nothing renders in the frontend for certain,
//                   but dvars survive into the match (B4 proved they survive
//                   map_restart; a frontend→match transition is the same
//                   process). It also tries iprintlnbold on any player it
//                   finds - if that renders in the lobby, so much the better.
//   in-match half   prints the stash the way every probe here prints, then
//                   its own in-match readings.
//
// ⚠ getgametypesetting() in the frontend has a CSC precedent (frontend.csc:2918)
//   and NO GSC one - stock's one frontend-loaded GSC reader, bot.gsc:38, guards
//   it behind is_frontend_map(). Whether that guard exists because the call
//   THROWS there or because it is meaningless there is exactly what this
//   measures, so the reads are ordered safest-first and the tick counter is
//   stashed before any of them: a tick count that keeps rising while 52+ stay
//   at 99999 means the read threw, which is a finding, not a malfunction.
//
// ── PROBES (id*100000 + value; 99999 = undefined / never stashed) ───────────
//   frontend half, read back in the NEXT match:
//   50xxxxx  samples taken in the frontend. 0 = the frontend half NEVER RAN.
//            Read this first; everything below is meaningless if it is 0.
//   51xxxxx  flags at the last sample:  1 is_frontend_map   2 sessionmodeisprivate
//            4 sessionmodeismultiplayergame   8 sessionmodeisonlinegame
//            16 getplayers().size > 0   32 one of them answered ishost()
//   58xxxxx  com_maxclients as seen from the lobby (8 normal / 10 3v3 in-match, L7)
//   56xxxxx  getnumconnectedplayers()
//   55xxxxx  getlobbyclientcount()      ⚠ no stock caller anywhere
//   52xxxxx  getgametypesetting(#"maxplayers")   THE READ. 6 in a 3v3 lobby, 4
//            normal = the frontend store is the pending lobby config, exactly
//            as it reads in-match. 99999 = no value here (or it threw: see 50).
//   53xxxxx  getgametypesetting(#"timelimit")    seconds. 40 = default; whatever
//            the rules menu shows = the store follows the menu LIVE.
//   54xxxxx  getgametypesetting(#"maxsquadplayers")  control, expect 0 (L5)
//   57xxxxx  getlobbyuiscreen()   int → the value. 88888 = defined but not an
//            int (a hash or string; note it and move on). ⚠ no stock caller
//   59xxxxx  write phase: 0 off · 1 wrote · 2 wrote AND the read-back matched
//            · 3 wrote and the read-back did NOT match (rejected or clamped)
//   in-match half:
//   60xxxxx  maxplayers in the match, read before ANYTHING writes it. With the
//            write phase on, 8 here = the frontend write CARRIED into the match.
//   61xxxxx  timelimit in the match (seconds). Same test for the timer.
//   62xxxxx  adddebugcommand: 0 off · 1 canadddebugcommand() said yes
//            · 2 the dvar landed · 3 both · 4 neither (nulled, like BO4)
//            ⚠ ON by default - it is in-match only and touches nothing but a
//            private dvar, so it rides run 1 rather than costing a launch.
//
// ── PROTOCOL ─────────────────────────────────────────────────────────────────
//  1. All switches off. Inject AT THE MAIN MENU. Play or restart one match
//     (links the MP half; it prints 50 = 99999 - nothing stashed yet, that is
//     correct). Leave to the lobby. Go to Custom Games, set up the usual 3v3
//     Gunfight lobby, wait ~30s, walk the rules menu, change the timer to 60.
//     Start the match. Read 50-59: that is the whole read-only result.
//  2. write_maxplayers = 1. Same walk. In the lobby: can a 4th bot/player go on a
//     side? Does the rules menu show anything different? Then start: 60 says
//     whether it carried.
//  3. write_timelimit = 1, separately - the rules-menu row makes this one
//     visible without starting anything.
//  4. debugcmd already answers itself on run 1 (probe 62) - no separate run.
//  ⚠ Test a lobby return after every run. This payload links in the frontend;
//    that is exactly where scene_model_shared broke.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace test_frontend;

function private autoexec __init__system__()
{
    system::register( #"test_frontend", &__init__, undefined, undefined, undefined );
}

function private default_config()
{
    return {
        // The frontend half writes NOTHING with both of these at 0.
        // One at a time: a single run with both on cannot say which one mattered.
        #write_maxplayers: 1,
        #maxplayers_value: 8,
        #write_timelimit:  0,
        #timelimit_value:  60,

        // In-match only. adddebugcommand("set gf_fe_dbg 7") then read it back.
        // BO4's table says nulled (ate47: "nulled; cbuff"); CW's row is
        // unannotated and NOT dev-flagged, so it is a question, not a verdict.
        //
        // ⚠ ON BY DEFAULT, unlike every other switch in this project. It is
        //   in-match only, independent of the frontend half, and the only thing
        //   it can change is a private dvar this payload invented - so it rides
        //   the read-only run for free instead of costing a whole game launch of
        //   its own. Emitted LAST, so if it throws, everything else has printed.
        //   Set it to 0 if a run must be provably read-only end to end.
        #debugcmd:         1,

        // Frontend sample cadence. 10s is enough to catch the walk from main
        // menu to a configured lobby; the LAST sample is what gets read.
        #period:           10
    };
}

function private __init__()
{
    // Stock threads from a system preinit too (load_shared.gsc:71-77). The
    // frontend has no globallogic, so on_start_gametype never dispatches there
    // (its three dispatch sites are cp/mp/zm globallogic) - a plain thread is
    // the only trigger that fires in both VMs.
    level thread frontend_watch( default_config() );
    callback::on_start_gametype( &on_start );
}

// ── the frontend half ────────────────────────────────────────────────────────

function private frontend_watch( cfg )
{
    wait( 3 );

    if ( !util::is_frontend_map() )
    {
        return;
    }

    setdvar( #"gf_fe_50", 0 );
    setdvar( #"gf_fe_59", 0 );
    ticks = 0;

    while ( true )
    {
        ticks++;
        sample( cfg, ticks );
        wait( cfg.period );
    }
}

function private sample( cfg, ticks )
{
    // The tick count goes FIRST so a throw further down still leaves proof
    // that this ran.
    stash( 50, ticks );

    flags = 0;
    if ( util::is_frontend_map() )          { flags += 1;  }
    if ( sessionmodeisprivate() )           { flags += 2;  }
    if ( sessionmodeismultiplayergame() )   { flags += 4;  }
    if ( sessionmodeisonlinegame() )        { flags += 8;  }

    players = getplayers();
    if ( players.size > 0 )
    {
        flags += 16;

        foreach ( player in players )
        {
            if ( player ishost() )
            {
                flags += 32;
                break;
            }
        }
    }
    stash( 51, flags );

    // Safest first: a dvar read and two builtins lobby_probe already ran in-match.
    stash( 58, getdvarint( #"com_maxclients", 0 ) );
    stash( 56, getnumconnectedplayers() );

    // No stock caller. Stashed before the gametype reads only because its
    // name says it is a lobby function and this is a lobby.
    stash( 55, getlobbyclientcount() );

    // THE READS. See the header for why these may throw.
    stash( 52, getgametypesetting( #"maxplayers" ) );
    stash( 53, getgametypesetting( #"timelimit" ) );
    stash( 54, getgametypesetting( #"maxsquadplayers" ) );

    // Unknown return type. isint() is in the CW table (no stock caller).
    screen = getlobbyuiscreen();
    if ( isdefined( screen ) && isint( screen ) )
    {
        stash( 57, screen );
    }
    else if ( isdefined( screen ) )
    {
        stash( 57, 88888 );
    }
    else
    {
        stash( 57, undefined );
    }

    // ── the write phase, off by default ─────────────────────────────────────
    // Written on EVERY sample rather than once: the lobby store may be rebuilt
    // when the mode is picked or the lobby created, and a single early write
    // would just be overwritten. Read back immediately.
    if ( cfg.write_maxplayers )
    {
        stash( 59, write_and_check( #"maxplayers", cfg.maxplayers_value ) );
    }
    else if ( cfg.write_timelimit )
    {
        stash( 59, write_and_check( #"timelimit", cfg.timelimit_value ) );
    }

    // If the lobby renders this at all, the last thing on screen is the tick.
    foreach ( player in players )
    {
        player iprintlnbold( 5000000 + ticks );
    }
}

function private write_and_check( key, value )
{
    setgametypesetting( key, value );
    readback = getgametypesetting( key );

    if ( !isdefined( readback ) )
    {
        return 1;
    }
    if ( readback == value )
    {
        return 2;
    }
    return 3;
}

function private stash( id, value )
{
    // -1 stands for undefined; the in-match half prints it as 99999.
    v = -1;
    if ( isdefined( value ) )
    {
        v = value;
    }
    setdvar( "gf_fe_" + id, v );
}

// ── the in-match half ────────────────────────────────────────────────────────

function private on_start()
{
    if ( util::is_frontend_map() )
    {
        return;
    }

    level thread report( default_config() );
}

function private report( cfg )
{
    // on_start_gametype fires before players are in the match.
    wait( 8 );

    // 60/61 FIRST: read before anything in this payload (or anything else) writes.
    emit( 60, getgametypesetting( #"maxplayers" ) );
    emit( 61, getgametypesetting( #"timelimit" ) );

    // The stash, in the header's order. 50 = 99999 means the frontend half
    // never ran - or this is the first match after injecting, which is the
    // expected result for that match (see PROTOCOL step 1).
    emit( 50, unstash( 50 ) );
    emit( 51, unstash( 51 ) );
    emit( 58, unstash( 58 ) );
    emit( 56, unstash( 56 ) );
    emit( 55, unstash( 55 ) );
    emit( 52, unstash( 52 ) );
    emit( 53, unstash( 53 ) );
    emit( 54, unstash( 54 ) );
    emit( 57, unstash( 57 ) );
    emit( 59, unstash( 59 ) );

    if ( cfg.debugcmd )
    {
        emit( 62, debugcmd_test() );
    }
}

function private debugcmd_test()
{
    setdvar( #"gf_fe_dbg", 0 );

    result = 0;
    if ( canadddebugcommand() )
    {
        result += 1;
    }

    // "set" is the console's dvar setter in every engine of this lineage and is
    // on the resolved T8 list (cfuncs.csv). A private dvar is the only thing
    // this can change.
    adddebugcommand( "set gf_fe_dbg 7\n" );
    wait( 1 );

    if ( getdvarint( #"gf_fe_dbg", 0 ) == 7 )
    {
        result += 2;
    }

    if ( result == 0 )
    {
        result = 4;
    }
    return result;
}

function private unstash( id )
{
    v = getdvarint( "gf_fe_" + id, -1 );
    if ( v < 0 )
    {
        return undefined;
    }
    return v;
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
