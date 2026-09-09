// ─────────────────────────────────────────────────────────────────────────────
// TEST L6 — `maxplayers`, the team-size setting. Write it and watch the round
// boundary.
//
// docs/notes/test-queue.md L6 · L7 · C7
// Hook: scripts\mp_common\bb.gsc, mode=mp
//
// WHY. lobby_probe measured `maxplayers` at 6 in a 3v3 Gunfight lobby and 4 in a
// normal one - exactly 2x the per-side size, both times. It is plain-named, it is
// a gametype setting, and L1 walked the rules menu and found NO ROW for it in
// Gunfight, so setgametypesetting() is the only way in.
//
// C7 separately measured that a Gunfight ROUND BOUNDARY restores the team size
// from the session layer - it put bots on a team to 4v4, and the next round start
// took them back to 3v3. Three script-side explanations for that were ruled out by
// grep (every remove_bot site in MP is Type: dev; the NOTSPAWNED kick returns early
// on sessionmodeisprivate(); autoassign bots fall to function_650d105d, which picks
// the smaller team with no cap).
//
// ▶ SO THE QUESTION IS: does the boundary restore FROM `maxplayers`? If it does,
//   the thing that has been UNDOING 4v4 starts RESTORING it, and the team-size goal
//   is one setgametypesetting call.
//
// ⚠ THIS IS THE SAME CLASS OF WRITE AS B6/B7 - a gametype setting, which
//   gunfight.gsc:104 and :106 already do to Gunfight itself. It reverts by not
//   injecting. It is NOT a session write like C7's bot fill.
//
// ── HOW TO READ THE OUTPUT ────────────────────────────────────────────────────
// PROBE_ID * 100000 + VALUE, one every 5s. 99999 = undefined.
// It emits on EVERY on_start_gametype - that is the point, you want one set per
// round so the boundary is visible.
//
//   1xxxxx  round number, 1-based       game. scope, so it counts rounds
//   2xxxxx  com_maxclients              10 in 3v3, 8 in 2v2 (L7)
//   3xxxxx  maxplayers BEFORE the write on round 1 expect 6 (3v3) / 4 (2v2)
//                                        ⚠ ON ROUND 2+ THIS IS THE ANSWER:
//                                          8 = the write SURVIVED the boundary
//                                          6 = the boundary reverted it
//   4xxxxx  maxplayers AFTER the write  expect 8. Anything else = write refused
//   5xxxxx  players in the match now
//   6xxxxx  allies*100 + axis           604 04 is 4v4
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;
#using scripts\core_common\bots\bot;

#namespace test_maxplayers;

function private autoexec __init__system__()
{
    system::register( #"test_maxplayers", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &on_start );
}

function private on_start()
{
    level thread run();
}

function private config()
{
    return {
        // The value to write. 8 = 4v4 in a 2-team mode, if the model holds.
        // ⚠ Do not go past com_maxclients (L7: 10 in a 3v3 lobby) on the first
        //   run - overshooting makes a refusal indistinguishable from a clamp.
        #target: 8,

        // 1 = report only, write nothing. RUN THIS FIRST. It confirms the
        // per-round read cadence and the baseline without spending a match.
        #read_only: 0,

        // 1 = also fill with bots, so there is something for the boundary to
        // revert. ⚠ SECOND RUN ONLY. Leave 0 for the first: a clean write test
        // and a session write in the same match makes a failure unattributable,
        // which is the one-write-per-match rule.
        #fill_bots: 0
    };
}

function private run()
{
    level endon( #"game_ended" );

    // game. scope survives the round; level. is torn down and rebuilt every round
    // (mp_probe probe 6). This is the counter that makes the boundary visible.
    if ( !isdefined( game.var_l6_round ) )
    {
        game.var_l6_round = 0;
    }
    game.var_l6_round++;

    cfg = config();

    // on_start_gametype fires before players are in the match.
    wait( 10 );

    emit( 1, game.var_l6_round );
    emit( 2, getdvarint( #"com_maxclients", 0 ) );

    // ⚠ THE LOAD-BEARING READ. On round 1 this is the baseline. On round 2+ it is
    //   the answer to the whole test: it reports what the setting held when the
    //   round STARTED, i.e. after the boundary had its say.
    before = getgametypesetting( #"maxplayers" );
    emit( 3, before );

    if ( !cfg.read_only )
    {
        setgametypesetting( #"maxplayers", cfg.target );
    }

    // Read back rather than trusting the write. A setting that silently refuses
    // and a setting that clamps look identical from the call site.
    emit( 4, getgametypesetting( #"maxplayers" ) );

    if ( cfg.fill_bots )
    {
        fill();
    }

    emit( 5, getplayers().size );
    emit( 6, getplayers( #"allies" ).size * 100 + getplayers( #"axis" ).size );
}

// Deliberately a trimmed copy of C7's fill rather than a call into it: the two
// tests inject one at a time (same replace target), so sharing code between them
// is not possible and pretending otherwise would be worse than the duplication.
function private fill()
{
    maxtries = 12;
    tries    = 0;
    stalled  = 0;
    current  = getplayers().size;

    while ( tries < maxtries && stalled < 2 )
    {
        bot::add_bot( undefined );
        tries++;

        wait( 2 );

        now = getplayers().size;

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
