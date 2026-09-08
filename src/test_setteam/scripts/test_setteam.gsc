// ─────────────────────────────────────────────────────────────────────────────
// TEST C8 — is 8 clients actually 4v4?
//
// docs/notes/test-queue.md C8 · docs/notes/cw-builtins.md §5
// Hook: scripts\mp_common\bb.gsc, mode=mp
//
// WHY. com_maxclients is read-only from script - 7 refs in the dump, all
// getdvarint, zero setdvar. TEAM ASSIGNMENT IS NOT. setteam (1 arg,
// BlackOpsColdWar.exe+3c7ca80) and getteam (0 args, +3c7cac0) are both exported.
//
// If a 3v3 Gunfight lobby's 8 clients are 6 players + 2 spectators, and a
// spectator can be put on a team, then 8 clients is exactly 4v4 - the stated
// target - from the lobby you already have, with no larger lobby at all.
//
// ⚠ Where the 6+2 split is actually ENFORCED is unestablished.
//   team_assignment.gsc:94 gates on `team_players.size >= max_players`, and
//   player_shared.gsc:1300 resolves max_players to com_maxclients (8) for a
//   two-team mode. 8 is not obviously 3-per-team. That gap is what this tests.
//
// ── THE ARGUMENT-SHAPE PROBLEM, AND HOW THIS AVOIDS IT ───────────────────────
// setteam takes ONE argument and the table says nothing about what it means. A
// team name string, a hashed name, an index and an entity are all one argument,
// and guessing is how the three game-crashing defects in src/README.md happened.
//
// So this script NEVER GUESSES. It reads a team value off a player who already
// has one, and passes THAT BACK:
//
//     donor_team = players[ 0 ] getteam();
//     target setteam( donor_team );
//
// Whatever representation the engine uses, that is the representation it gets.
// The bitmask in probe 3 additionally REPORTS which representation it is, by
// comparison rather than by display - a hashed team name cannot be rendered on
// retail, but `x == #"allies"` evaluates fine (src/README.md: literals work for
// comparison, only on-screen rendering of them fails).
//
// ── HOW TO READ THE OUTPUT ────────────────────────────────────────────────────
// PROBE_ID * 100000 + VALUE, one every 5s. 99999 = undefined.
//
//   1xxxxx  com_maxclients
//   2xxxxx  players in match
//   3xxxxx  TEAM REPRESENTATION BITMASK   1=#"allies" 2=#"axis" 4="allies" 8="axis"
//                                          0 = none matched; getteam returns
//                                          something else entirely, and THAT is the
//                                          finding. Record it and stop.
//   4xxxxx  players sharing players[0]'s team   (before)
//   5xxxxx  write attempted? 1/0          0 means read_only was left on
//   6xxxxx  DID THE TEAM CHANGE? 1/0      <- THE ANSWER
//   7xxxxx  players sharing that team     (after)
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace test_setteam;

function private autoexec __init__system__()
{
    system::register( #"test_setteam", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &on_start );
}

function private on_start()
{
    level thread run();
}

function private run()
{
    // ⚠ RUN WITH THIS AT 1 FIRST. Phase 1 writes nothing and is what settles the
    //   argument shape. Only set it to 0 once probe 3 has come back non-zero.
    //   Plain local, not a preprocessor macro - see test_addclients.gsc.
    read_only = 1;

    // on_start_gametype fires before players are in the match.
    wait( 10 );

    players = getplayers();

    emit( 1, getdvarint( #"com_maxclients", 0 ) );
    emit( 2, players.size );

    if ( players.size < 1 )
    {
        // Nothing to read a team off. Not a failure of setteam - a failure to
        // have anyone in the match. Run test_addclients first.
        emit( 3, 99999 );
        return;
    }

    donor_team = players[ 0 ] getteam();

    // Which representation is it? By comparison, never by display.
    rep = 0;
    if ( donor_team === #"allies" ) { rep += 1; }
    if ( donor_team === #"axis" )   { rep += 2; }
    if ( donor_team === "allies" )  { rep += 4; }
    if ( donor_team === "axis" )    { rep += 8; }
    emit( 3, rep );

    emit( 4, count_on_team( donor_team ) );

    if ( read_only )
    {
        emit( 5, 0 );
        return;
    }

    // ── Phase 2. WRITES. ─────────────────────────────────────────────────────
    // Pick a client who is NOT already on the donor's team - moving someone onto
    // the team they are already on proves nothing either way.
    target = undefined;
    foreach ( p in players )
    {
        if ( !( p getteam() === donor_team ) )
        {
            target = p;
            break;
        }
    }

    if ( !isdefined( target ) )
    {
        // Everyone is already on one team. Inconclusive, not negative.
        emit( 5, 1 );
        emit( 6, 99999 );
        return;
    }

    target setteam( donor_team );
    emit( 5, 1 );

    wait( 2 );

    changed = 0;
    if ( target getteam() === donor_team )
    {
        changed = 1;
    }
    emit( 6, changed );
    emit( 7, count_on_team( donor_team ) );
}

function private count_on_team( team )
{
    n = 0;
    foreach ( p in getplayers() )
    {
        if ( p getteam() === team )
        {
            n++;
        }
    }
    return n;
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
