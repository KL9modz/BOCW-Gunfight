// ─────────────────────────────────────────────────────────────────────────────
// TEST A4 — do the map carry FROM SCRIPT, and delete the menu from the workflow.
//
// docs/notes/test-queue.md A4 · docs/notes/atian-menu-source.md:19
// Hook: scripts\mp_common\bb.gsc, mode=mp
//
// WHY. The hosting workflow is six steps and two of them are manual UI:
//   inject menu -> F7 -> RMB+V -> navigate -> carry -> inject mod -> F7
// The menu exists in that list for ONE reason: it is the only thing that calls
// map(). Nothing else about it is used.
//
// ▶ atian-menu-source.md:19 pins the mechanism exactly:
//     func_set_map( item, map_name )  ->  map( map_name )
//   ONE builtin. Not switchmap_load, not a sequence, not anything the menu adds.
//   Every one of its 48 map entries wires that same call.
//
// So if map() works from our own script, the whole menu step disappears and the
// workflow becomes: inject -> F7. That is the automation win the DLL route was
// chasing, and it needs no DLL at all - which matters, because BOTH DLL routes
// were closed by measurement on 2026-09-08 (D10: dcfuncscw returns an empty
// table, ACTS's cmd_function_t base is stale; D11: the lobby exports are not in
// the binary).
//
// ⚠⚠ THE FAILURE MODE HERE IS A MAP LOAD LOOP, and it would be miserable - the
//    game reloading forever with no way in. THREE independent guards, because one
//    is not enough when the cost of being wrong is a stuck game:
//
//      1. read_only        - default 1. Reports and switches nothing.
//      2. already-there    - if the live map IS the target, do nothing. This is
//                            the guard that SHOULD do all the work, since after a
//                            successful switch the comparison stops matching.
//      3. attempt counter  - game. scope, hard cap 1. Fires even if guard 2 is
//                            wrong, e.g. if map() silently fails or the name does
//                            not resolve, which would otherwise retry every round
//                            forever. THIS is the one that matters.
//
//    Guard 3 is deliberately redundant with guard 2. Do not remove it as
//    "unreachable" - it is reachable exactly when the reasoning behind guard 2 is
//    wrong, which is the only case anyone cares about.
//
// ⚠ A carry is a LOAD-TIME OVERRIDE. It does not touch the session, which is why
//   the scoreboard keeps naming the old map. That is expected and is not a bug -
//   it is the documented difference between our carry and the lobby glitch.
//
// ── HOW TO READ THE OUTPUT ────────────────────────────────────────────────────
// PROBE_ID * 100000 + VALUE, one every 5s. 99999 = undefined.
//
//   1xxxxx  is the live map already the target?   1/0
//   2xxxxx  attempts used so far (game. scope)     0 on the first round
//   3xxxxx  com_maxclients                         context, should not move
//
// Expected: round 1 reads 100000 (not there yet) and then the map loads.
//           After the load, round 1 of the NEW map reads 100001 - and that is
//           the whole result. 100001 means script carried the map on its own.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace test_mapswitch;

function private autoexec __init__system__()
{
    system::register( #"test_mapswitch", &__init__, undefined, undefined, undefined );
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
    level endon( #"game_ended" );

    // ── config ──────────────────────────────────────────────────────────────
    // Map names taken from scripts/mp/ in ate47/bocw-source. The full set:
    //   mp_amerika mp_apocalypse mp_black_sea mp_cartel mp_cliffhanger
    //   mp_drivein_rm mp_dune mp_echelon mp_express_rm mp_firebase
    //   mp_hijacked_rm mp_jungle_rm mp_kgb mp_mall mp_miami mp_miami_strike
    //   mp_moscow mp_nuketown6 mp_paintball_rm mp_raid_rm mp_russianbase_rm
    //   mp_satellite mp_slums_rm mp_sm_amsterdam mp_sm_berlin_tunnel
    //   mp_sm_central mp_sm_deptstore mp_sm_finance mp_sm_game_show
    //   mp_sm_gas_station mp_sm_market mp_sm_vault mp_tank mp_tundra
    //   mp_village_rm mp_zoo_rm
    //
    // ⚠ A name being in the dump means the SCRIPT exists, not that the map is
    //   loadable in this build. B5 (mapexists) is the cheap way to check a name
    //   before trusting it; this test is also a way to find out the hard way.
    target = "mp_hijacked_rm";

    // ⚠ RUN WITH THIS AT 1 FIRST. Reports the state, switches nothing, and
    //   confirms the name comparison behaves before anything can reload.
    read_only = 0;   // ✅ read-only run 2026-09-08 read 100000/200000: guards behave. Live now.

    // Hard cap on switch attempts, ever, for this lobby. Still a hard cap.
    //
    // ⚠ RAISED 1 -> 2 ON 2026-09-08, and the reason is a trap worth keeping:
    //   run 1 called map() with no switchmap_switch(), so nothing loaded - but the
    //   counter had ALREADY incremented past the failed call. game. scope survives
    //   the round AND a second match in the same lobby (the same property
    //   gunfight.gsc:81 relies on for game.var_96a8ff4a), so at maxattempts = 1 the
    //   retry would have been silently refused by guard 3 and looked identical to
    //   the original failure - "nothing happened", twice, for two different reasons.
    //
    //   Diagnosing that from the outside is nearly impossible, which is exactly why
    //   probe 2 emits the counter. READ IT: if probe 2 is already at the cap on
    //   round 1, the guard is what stopped the switch, not the game.
    //
    //   ⚠ A cap of 2 is still a cap. Do not raise it to "just try until it works" -
    //   the failure this guards against is an unbounded map load loop, and that
    //   remains the worst outcome available here.
    maxattempts = 2;

    wait( 10 );

    // ── guard 3 state ───────────────────────────────────────────────────────
    // game. scope survives the round (level. does not - mp_probe probe 6).
    if ( !isdefined( game.var_a4_attempts ) )
    {
        game.var_a4_attempts = 0;
    }

    live = util::get_map_name();

    // ── guard 2 ─────────────────────────────────────────────────────────────
    already = 0;
    if ( isdefined( live ) && live == target )
    {
        already = 1;
    }

    emit( 1, already );
    emit( 2, game.var_a4_attempts );
    emit( 3, getdvarint( #"com_maxclients", 0 ) );

    if ( read_only )
    {
        return;
    }

    if ( already )
    {
        return;
    }

    // ── guard 3 ─────────────────────────────────────────────────────────────
    if ( game.var_a4_attempts >= maxattempts )
    {
        return;
    }
    game.var_a4_attempts++;

    // ── THE SEQUENCE ────────────────────────────────────────────────────────
    // ⚠⚠ THREE CALLS, NOT ONE. Run 1 (2026-09-08) called map() alone and NOTHING
    //    HAPPENED - no load, no error. map() only STAGES the map;
    //    switchmap_switch() is what commits it.
    //
    //    Verbatim from t8-atian-menu@master coldwar/.../menu_funcs.gsc:357 -
    //    func_set_map(), the function all 48 of the menu's map entries wire:
    //
    //        map(map_name);
    //        wait(1);
    //        switchmap_switch();
    //
    // ⚠ atian-menu-source.md's table said "map only, via map( map_name )", which
    //   is right about WHAT it sets and lossy about HOW. That summary is what run
    //   1 was built on. The note is now corrected - and the lesson is the one this
    //   project keeps relearning: quote the source, do not paraphrase a mechanism.
    //
    // ⚠ THE WAIT IS LOAD-BEARING. ate47 on the sibling sequence: "the wait is
    //   important, I don't know why." Empirical, not understood. Do not remove it.
    //   func_set_gametype uses util::wait_network_frame(1) where this uses a plain
    //   wait(1); this mirrors func_set_map exactly rather than tidying it.
    map( target );
    wait( 1 );
    switchmap_switch();

    // Nothing after this is guaranteed to run; the map is loading. The result
    // comes from this script's NEXT on_start, on the new map.
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
