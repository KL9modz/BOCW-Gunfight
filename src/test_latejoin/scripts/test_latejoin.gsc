// ─────────────────────────────────────────────────────────────────────────────
// TEST C10 — make a late joiner land on a TEAM, not in spectator.
//
// Hook: scripts\mp_common\bb.gsc, mode=mp  (see ../gsc.conf)
//
// ── WHY THIS EXISTS ──────────────────────────────────────────────────────────
// Every team-size route this project has tried attacks the PREGAME lobby, where
// com_maxclients is fixed and script cannot reach. This one does not. It attacks
// the moment a player joins a match that is ALREADY RUNNING - which is script
// territory, and which klaze already exercises by hand every time he hosts.
//
// klaze's measured hosting workflow (2026-09-09):
//   a 3v3 Gunfight pregame lobby assigns 3 + 3 to teams and up to 2 CoD Casters.
//   3 + 3 + 2 = 8 = com_maxclients, which is what that number has always been.
//   Extra players cannot be assigned and the host cannot start with too many
//   casters, so the extras LEAVE, the host starts, and the extras REJOIN. The
//   game accepts them - as spectators.
//
// ── WHY THEY BECOME SPECTATORS, AND WHY THAT IS ONE CONDITION ────────────────
// team_assignment.gsc:600-656, function_a3e209ba(), returns TRUE - meaning "send
// this player to spectator" - only when EVERY one of these holds:
//
//     !level.rankedmatch                      private match: true
//     !level.inprematchperiod                 the match has started: true
//     teamname == #"none"                     no team came with them: true
//     !comingfrommenu                         auto-assign, not a menu pick: true
//     !self ishost()                          they are not the host: true
//     !level.forceautoassign          <-- LEVER 1
//     !isbot( self )                          they are a person: true
//     !self issplitscreen()                   true
//     [[ level.var_a3e209ba ]]()      <-- LEVER 2
//
// Nine ANDs. Break ANY one and the player is not sent to spectator - they fall
// through to function_bec6e9a() -> function_650d105d(), which is:
//
//     count the teams, put the player on the smaller one.
//
// ⚠⚠ THAT PATH HAS NO PER-TEAM CAP CHECK AT ALL. Not maxsquadplayers, not
//    com_maxclients, not the 3 the lobby enforced. It counts and balances. The
//    only ceiling left is the engine refusing a 9th client, and 4v4 needs 8.
//
// ── WHICH LEVER, AND WHY ─────────────────────────────────────────────────────
// LEVER 2 is the default here because it is surgical. level.var_a3e209ba is a
// gametype-overridable predicate (team_assignment.gsc:27-29 installs the default
// only `if ( !isdefined( ... ) )`, and the default - function_321f8eb5 - is
// literally `return true;`). It is consulted in ONE place: the last line of
// function_a3e209ba. Overriding it changes nothing else in the game.
//
// LEVER 1, level.forceautoassign, is the bigger hammer. It is a stock, shipped
// configuration - Zombies runs with it at 1 (zm_gametype.gsc:87) - but in MP it
// has a SECOND consumer, globallogic_ui.gsc:194:
//
//     if ( assignment === #"spectator" && !level.forceautoassign ) { ...; return; }
//
// With it on, a player who DELIBERATELY picks spectator skips the spectator setup
// call and falls through. ⚠ That may break choosing spectator on purpose - which
// matters, because casters are how klaze gets 7 and 8 into the lobby in the first
// place. Try lever 2 first; keep lever 1 as the fallback if lever 2 misses.
//
// ── HONEST CEILING ───────────────────────────────────────────────────────────
// This reaches 4v4 and stops. 8 clients, zero casters. 5v5 needs ten clients and
// com_maxclients is still 8 - untouched by this and still lobby-side. 4v4 is
// inside the stated target (4v4-5v5); 5v5 is not solved here and this test does
// not claim it.
//
// ── PROTOCOL ─────────────────────────────────────────────────────────────────
//  1. Inject. Host a 3v3 Gunfight private lobby. Fill both teams: 3 v 3.
//  2. Two more players in the pregame lobby LEAVE (klaze's normal workaround).
//  3. Start the match.
//  4. Those two REJOIN while the match is running.
//  5. Watch where they land.
//
//     on a team      -> 4v4, and the team-size goal is reached with one line
//     spectator      -> lever 2 did not fire. Flip to lever 1 and run it again
//     cannot rejoin  -> a session-layer refusal, nothing to do with this script.
//                       Record it: it is a fact about the 8-client budget, and it
//                       says the 2 caster slots were already spent
//
//  6. ⚠ TEST A LOBBY RETURN. That is the check that caught scene_model_shared.
//
// ⚠ Probe 20xxxxx prints the per-team counts every 10s so the result is a number
//   on screen and not a recollection. 20xxxxx = allies*100 + axis.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace test_latejoin;

function private autoexec __init__system__()
{
    system::register( #"test_latejoin", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &on_start );
}

// Which lever to pull. ONE PER MATCH - if both are on and the result is good you
// do not know which one did it, and if the result is bad you do not know which one
// broke it. That is the same discipline the rest of band C runs under.
function private default_config()
{
    return {
        #predicate:      1,   // LEVER 2. Surgical. Try this first.
        #forceautoassign: 0,  // LEVER 1. Bigger blast radius - see the header.
        #report:         1    // print the team counts every 10s
    };
}

function private on_start()
{
    cfg = default_config();

    if ( cfg.predicate )
    {
        // Runs AFTER team_assignment::preinit (a system::register preinit, so it has
        // already installed function_321f8eb5), which is why this is a plain
        // assignment and not an isdefined guard - we are deliberately replacing it.
        level.var_a3e209ba = &never_force_spectator;
    }

    if ( cfg.forceautoassign )
    {
        level.forceautoassign = 1;
    }

    if ( cfg.report )
    {
        level thread report_teams();
    }
}

// The replacement predicate. Same shape as stock function_321f8eb5( *player ),
// which is `return true;` - the * marks the parameter unused, and ours is too.
function private never_force_spectator( *player )
{
    return false;
}

function private report_teams()
{
    level endon( #"game_ended" );

    // Let the match settle before the first reading; a joiner needs a respawn
    // before getplayers() sees them on a team.
    wait( 15 );

    for ( ;; )
    {
        allies = getplayers( #"allies" ).size;
        axis = getplayers( #"axis" ).size;

        // allies*100 + axis, tagged 20. So 20xxxxx reading 2000403 is 4 v 3.
        // Kept on one line because two numbers five seconds apart is how mp_probe
        // lost half its readings.
        tagged = 20 * 100000 + allies * 100 + axis;

        foreach ( player in getplayers() )
        {
            player iprintlnbold( tagged );
        }

        wait( 10 );
    }
}
