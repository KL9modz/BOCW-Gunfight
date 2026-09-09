// ─────────────────────────────────────────────────────────────────────────────
// TEST C11 — seat a spectator on a team, from script, with no menu involved.
//
// Hook: scripts\mp_common\bb.gsc, mode=mp  (see ../gsc.conf)
//
// ── WHY THIS SUPERSEDES C10 ──────────────────────────────────────────────────
// C10 breaks function_a3e209ba so a JOINING player is not shunted to spectator.
// That works only at the instant of joining, and only if the joiner arrives while
// the mod is loaded. C11 acts on anyone who is ALREADY sitting in spectator, for
// any reason, at any point in the match - which is the situation klaze actually
// has: people rejoin, get forced to spectate, and stay there.
//
// And it needs no override at all. level.autoassign is a function pointer
// (globallogic_ui.gsc:39 -> &menuautoassign). Call it with a team:
//
//     player [[ level.autoassign ]]( 0, #"allies", undefined );
//                                    ^comingfrommenu = 0
//
// That reaches team_assignment.gsc:419:
//
//     else if ( teamname !== #"none" && !comingfrommenu ) { assignment = teamname; }
//
// **Used verbatim.** No fullness check, no function_a3e209ba, no spectator branch,
// no forceautoassign, no predicate override. It is the exact branch klaze already
// watches fire every time "a spot is open on the join" - we are simply handing it
// the answer instead of letting getassignedteamname() supply it.
//
// ⚠ comingfrommenu MUST be 0. Passing 1 skips branch :419 entirely.
//
// menuautoassign then runs the whole stock seat-and-respawn path -
// teams::function_dc7eaabd (three script fields, nothing the engine can refuse),
// squads, objective text, function_466d8a4b, end_respawn, beginclasschoice. Same
// path a normal joiner takes, which klaze confirms "get treated properly".
//
// ── WHY THE MENU IS NOT THE ROUTE ────────────────────────────────────────────
// klaze measured that Allow In-Game Team Change is ON BY DEFAULT in custom
// matches - so level.allow_teamchange is already 1 and the ChangeTeam menu is
// already reachable - and a spectator STILL cannot take a team that way; they
// have to leave and rejoin.
//
// So the block is not level.allow_teamchange and it is not menuteam(), which has
// no cap check at all (globallogic_ui.gsc:331). It is not level.var_fb99ff98
// either: that flag is never set anywhere in the dump and self.var_77d6602a is
// never read, so menus.gsc:181 is dead code in retail.
//
// ⚠ By elimination the block is CLIENT-SIDE - the LUI team screen refusing to
//   offer a full team. That is unreachable from GSC and this test does not try.
//   It does not need to: the LUI decides what a player may CLICK. Script does not
//   click. Same lesson as the rules menu publishing 6 of 20 timer values while
//   setgametypesetting takes any of them.
//
// ── SAFETY: DO NOT DRAG CASTERS ONTO TEAMS ───────────────────────────────────
// A CoD Caster is a spectator too, and casters are how klaze gets the 7th and 8th
// bodies into a lobby. Yanking them onto teams would break his hosting workflow,
// not help it.
//
// iscodcaster is a METHOD builtin - BlackOpsColdWar.exe+461eeb0, 0 args, called on
// a player. ⚠ NO STOCK GSC CALLS IT (only the CSC side, via
// codcaster::function_b8fe9b52). Same category as isvalidgametype: real address,
// no precedent, and the first thing to suspect if the script dies. That is exactly
// why the counts are emitted BEFORE any seating happens.
//
// ── PROTOCOL ─────────────────────────────────────────────────────────────────
// PASS 1 — read_only = 1. Seats nobody.
//   Host 3v3 Gunfight. Fill 3 v 3. A 7th player joins mid-match and is forced to
//   spectate. Read:
//     21xxxxx  spectators found            expect 1
//     22xxxxx  of those, casters           expect 0 for a plain rejoin, 2 if the
//                                          caster slots are filled
//     23xxxxx  allies*100 + axis           expect 300 + 3 = 30003 -> 2300303
//   ⚠ If 22 reads 99999 the iscodcaster call returned undefined; if the script
//     dies before 23 prints, iscodcaster is the suspect. Either way set
//     skip_casters = 0 and re-run to get the rest of the readings.
//
// PASS 2 — read_only = 0, target = 4.
//   Same setup. The spectator should be seated on the smaller team at the next
//   grace period. 23xxxxx should read 2000403 then 2000404.
//
//   ⚠ TEST A LOBBY RETURN. That is the check that caught scene_model_shared.
//
// ── HONEST CEILING ───────────────────────────────────────────────────────────
// 4v4. Eight clients, zero casters, because com_maxclients is 8 and casters spend
// from the same budget. 5v5 needs ten and nothing here touches that.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace test_seatspectator;

function private autoexec __init__system__()
{
    system::register( #"test_seatspectator", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &on_start );
}

function private default_config()
{
    return {
        // PASS 1 leaves this at 1: count and report, seat nobody. The counts are
        // what tell you whether iscodcaster survives the call at all.
        #read_only:     1,

        // Fill each team up to this and no further. A cap, not a target - it is
        // what stops a runaway if the spectator list is longer than expected.
        #target:        4,

        // Never seat a CoD Caster. Turn this OFF only to isolate an iscodcaster
        // failure, never for a real run - casters are how the 7th and 8th players
        // get into the lobby.
        #skip_casters:  1,

        // Only seat while level.ingraceperiod is set. Gunfight is round-based and
        // one-life; dropping someone into a live round gives them a spawn in a
        // round they should already be dead for. Rounds are 40-60s, so waiting for
        // the next grace period costs almost nothing.
        #grace_only:    1
    };
}

function private on_start()
{
    level thread watch_spectators( default_config() );
}

function private watch_spectators( cfg )
{
    level endon( #"game_ended" );

    wait( 15 );

    for ( ;; )
    {
        // PASS 1: gather WITHOUT touching iscodcaster, and emit. check-dump.py flags
        // iscodcaster as unused-by-stock, and its rule is "emit it LAST so the probes
        // before it have already printed if it throws". So 21 and 23 are on screen
        // before the untested builtin is ever called.
        all_spectators = [];

        foreach ( player in getplayers() )
        {
            if ( player.pers[ #"team" ] === #"spectator" )
            {
                all_spectators[ all_spectators.size ] = player;
            }
        }

        allies = getplayers( #"allies" ).size;
        axis = getplayers( #"axis" ).size;

        emit( 21, all_spectators.size );
        emit( 23, allies * 100 + axis );

        // PASS 2: now the untested builtin. If the script dies here, 21 and 23 have
        // already printed and you know exactly which call did it.
        spectators = [];
        casters = 0;

        foreach ( player in all_spectators )
        {
            if ( cfg.skip_casters && player iscodcaster() )
            {
                casters++;
                continue;
            }

            spectators[ spectators.size ] = player;
        }

        emit( 22, casters );

        if ( !cfg.read_only && ( !cfg.grace_only || is_true( level.ingraceperiod ) ) )
        {
            foreach ( player in spectators )
            {
                allies = getplayers( #"allies" ).size;
                axis = getplayers( #"axis" ).size;

                if ( allies >= cfg.target && axis >= cfg.target )
                {
                    break;
                }

                team = #"allies";

                if ( allies > axis || allies >= cfg.target )
                {
                    team = #"axis";
                }

                // comingfrommenu = 0 is load-bearing. With 1, team_assignment.gsc:419
                // is skipped and the team we pass is ignored.
                player [[ level.autoassign ]]( 0, team, undefined );

                // Let the seat-and-respawn path finish before recounting, or the
                // next iteration's getplayers() reads a stale team.
                wait( 1 );
            }
        }

        wait( 10 );
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

    wait( 3 );
}
