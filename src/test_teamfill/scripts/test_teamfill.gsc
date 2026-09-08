// ─────────────────────────────────────────────────────────────────────────────
// TEST C8 — can FOUR players stand on one team? (8 clients = 4v4?)
//
// docs/notes/test-queue.md C8 · docs/notes/dump-cross-check.md
// Hook: scripts\mp_common\bb.gsc, mode=mp
//
// ⚠ THIS REPLACES test_setteam, WHICH WAS BUILT ON A WRONG PREMISE.
//   setteam has 55 stock call sites and every one sets the team of a WORLD OBJECT
//   - grenades, supply pods, vehicles, turrets, helicopters, mines, tear gas,
//   trophy systems. The single player-ish case (prop.gsc:4686) is Prop Hunt
//   converting a player INTO a prop, alongside setplayercollision(0),
//   makesentient() and setscale(2). It is not a team-assignment call.
//
// ── WHAT THE DUMP ACTUALLY SAYS, AND WHY THIS TEST IS NOW CHEAPER ────────────
// The 3-per-team limit is NOT enforced by team assignment.
//
//   player_shared.gsc  function_d36b6597()
//       returns com_maxclients whenever teamcount > 0 and com_maxclients !=
//       teamcount. Gunfight is teamcount 2 with com_maxclients 8, so it
//       returns 8.
//
//   team_assignment.gsc:95  function_efe5a681( team )
//       max_players  = function_d36b6597()          -> 8
//       team_players = getplayers( team )
//       if ( team_players.size >= max_players ) return false;
//
// A team is refused only at EIGHT players. Nothing in that path says three.
// So 4v4 inside 8 client slots is not blocked at the script layer - what is
// blocked is a NINTH client, and 4v4 needs only eight.
//
// This test asks the engine directly: put bots on one team until it refuses, and
// see where the refusal lands.
//
// ── WHY bot::add_bot AND NOT addtestclient ───────────────────────────────────
// bot.gsc:137 wraps the builtin: addtestclient(name, clanabbrev), then a null
// check, then `bot init_bot()`. A raw builtin call skips init_bot and produces a
// half-initialised client. bot::add_bot(team, name, clanabbrev) is the public API,
// it sets bot.botteam, and stock calls it as bot::add_bot(team) - dev.gsc:1705,
// rat.gsc:76, _prop_dev.gsc:1421.
//
// team_assignment.gsc:107 then gates bot placement on
//     getplayers( self.botteam ).size < max_players
// which is the same cap, reached through the bot path.
//
// ── HOW TO READ THE OUTPUT ────────────────────────────────────────────────────
//   1xxxxx  com_maxclients                      expect 8 in 3v3 Gunfight
//   2xxxxx  players on the target team BEFORE
//   3xxxxx  players on the target team AFTER    <- THE ANSWER
//   4xxxxx  total players in the match AFTER    did the total cap bite first?
//   5xxxxx  add attempts made
//
// 3xxxxx reading 4 or more = a team holds four, and 8 clients is 4v4.
// 3xxxxx stopping at 3     = something enforces three that the dump does not show,
//                            and THAT is the finding - record it, do not conclude
//                            the goal is unreachable.
// 4xxxxx hitting com_maxclients first = the TOTAL cap bit before the team cap, so
//                            this run says nothing about the per-team limit. Free
//                            up client slots and rerun.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;
#using scripts\core_common\bots\bot;

#namespace test_teamfill;

function private autoexec __init__system__()
{
    system::register( #"test_teamfill", &__init__, undefined, undefined, undefined );
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
    // ── config. Plain locals, not preprocessor macros - see test_addclients.gsc.

    // ⚠ RUN WITH THIS AT 1 FIRST. Reports the team distribution and adds nothing,
    //   which confirms the team value below is the right representation.
    read_only = 1;

    // The team to fill. Hashed form, which is what stock uses everywhere -
    // vehicle.gsc:230 `setteam(#"neutral")`, globallogic_spawn.gsc compares
    // self.pers[#"team"] against #"spectator".
    team = #"allies";

    // One more than we expect to fit, so a refusal is visible rather than inferred
    // from running out of attempts.
    maxtries = 6;

    // Bots take time to connect; measuring immediately reads the count from before
    // the join landed and makes every add look like a refusal.
    settle = 3;

    wait( 10 );

    emit( 1, getdvarint( #"com_maxclients", 0 ) );

    before = getplayers( team ).size;
    emit( 2, before );

    if ( read_only )
    {
        emit( 3, before );
        emit( 4, getplayers().size );
        emit( 5, 0 );
        return;
    }

    tries   = 0;
    stalled = 0;
    current = before;

    while ( tries < maxtries && stalled < 2 )
    {
        bot::add_bot( team );
        tries++;

        wait( settle );

        now = getplayers( team ).size;

        if ( now > current )
        {
            current = now;
            stalled = 0;
        }
        else
        {
            stalled++;
        }
    }

    emit( 3, current );
    emit( 4, getplayers().size );
    emit( 5, tries );
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
