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
// ▶ t8-atian-menu@master coldwar/scripts/core_common/menu_funcs.gsc:357, verbatim -
//   func_set_map(), which all 48 of the menu's map entries wire:
//
//     map(map_name);
//     wait(1);
//     switchmap_switch();
//
//   THREE calls. map() only STAGES the load; switchmap_switch() commits it.
//   ⚠ An earlier version of this header said "ONE builtin, not a sequence",
//     paraphrasing atian-menu-source.md's summary table instead of the source.
//     Run 1 called map() alone and nothing happened at all. Both the note and this
//     header are now corrected from the source.
//
// So if map() works from our own script, the whole menu step disappears and the
// workflow becomes: inject -> F7. That is the automation win the DLL route was
// chasing, and it needs no DLL at all - which matters, because BOTH DLL routes
// were closed by measurement on 2026-09-08 (D10: dcfuncscw returns an empty
// table, ACTS's cmd_function_t base is stale; D11: the lobby exports are not in
// the binary).
//
// ⚠⚠ TWO WAYS THIS BITES, and BOTH HAVE NOW HAPPENED. FOUR guards:
//
//      1. read_only        - default 1. Reports and switches nothing.
//      2. already-there    - if the live map IS the target, do nothing. Should do
//                            all the work: after a good switch it stops matching.
//      3. attempt counter  - game. scope, hard cap. Fires when guard 2's reasoning
//                            is wrong, which would otherwise retry every round
//                            forever. Guards the MAP LOAD LOOP.
//      4. mapexists()      - ⚠ ADDED AFTER THE HANG. Guards the UNLOADABLE MAP.
//
//    Guard 3 is deliberately redundant with guard 2 - it is reachable exactly when
//    guard 2's reasoning is wrong, which is the only case anyone cares about. Do
//    not delete it as unreachable.
//
//    ⚠ Guard 4 exists because a bad TARGET is a different failure from a bad LOOP,
//      and guards 1-3 do not touch it. On 2026-09-08 "mp_hijacked_rm" - a name
//      taken from the dump's scripts/mp/ listing - HUNG THE GAME mid-load. The
//      working set fell 8.2 GB -> 5.0 GB, so the load genuinely started and never
//      finished. The caveat "a name in the dump proves the SCRIPT shipped, not that
//      the map loads" was already written in this file, and was ignored anyway.
//      Ask the engine (B5), do not trust the listing.
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
//   4xxxxx  mapexists( target )                    1 = loadable, 0 = REFUSED, no switch
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
    // ⚠⚠ BROKE THE SESSION ON 2026-09-08 WITH "mp_hijacked_rm". What ACTUALLY
    //    happened, after two wrong readings of it:
    //
    //      - working set fell 8.2 GB -> 5.0 GB and the game stopped responding
    //      - it came back on its own after minutes
    //      - it came back STILL ON THE OLD MAP (KGB), in a glitched state
    //
    //    So it is neither a hang nor a slow load nor a clean refusal. map() +
    //    switchmap_switch() began TEARING DOWN the current map, failed to bring up
    //    the target, and left the session half-transitioned. ⚠ I called it "hung"
    //    from a stale RSS reading and then "a slow load" when it recovered; both
    //    were wrong. Record the behaviour, not the first plausible story.
    //
    //    ▶ THE FAILURE IS SILENT AND DESTRUCTIVE, which is why guard 4 has to run
    //      BEFORE anything is torn down. There is no error, no refusal, and no
    //      point after map() at which the script can still save the session.
    //
    //    Hijacked is BO2-era content. Its script is in the dump; that only proves
    //    the SCRIPT shipped, which is the exact caveat written three lines below
    //    this before the run and ignored while picking a name off the listing.
    //
    //    ⚠ UNKNOWN, and do not assume: whether mapexists() actually returns 0 for
    //      this name. If it returns 1 and the load still breaks, guard 4 does not
    //      cover this case and the real precondition is something else. B5 over
    //      the full 38-name list answers it read-only, and should be run FIRST.
    //
    // ▶ DEFAULT IS NOW A MAP KLAZE HAS ACTUALLY CARRIED TO AND PLAYED (Zoo,
    //   3v3 Gunfight, 60s rounds, 2026-09-08). Prefer a map from the Atian menu's
    //   own list over anything found only by grepping scripts/mp/.
    target = "mp_zoo_rm";

    // ⚠ RUN WITH THIS AT 1 FIRST. Reports the state, switches nothing, and
    //   confirms the name comparison behaves before anything can reload.
    read_only = 1;   // ⚠ FORCED INERT 2026-09-08 after the KGB glitch - see notes below.

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

    // ── guard 4 — ADDED AFTER THE 2026-09-08 HANG. mapexists() before map(). ──
    // ⚠ This is the guard that would have PREVENTED the hang, and it was already
    //   written down as test B5 while this script was being built. A map name in
    //   scripts/mp/ proves a SCRIPT shipped, not that the map is loadable in this
    //   install - so ask the engine instead of trusting the dump listing.
    //
    //   mapexists: 1 arg, BlackOpsColdWar.exe+3b0b2d0 (ate47's CW table).
    //   Read-only, and cheap enough that there is no reason ever to skip it.
    //
    //   Emitted as probe 4 so a refusal is VISIBLE. A silent skip and a hung load
    //   are the two outcomes here, and they must never look the same again.
    exists = mapexists( target );

    if ( !is_true( exists ) )
    {
        emit( 4, 0 );
        return;
    }
    emit( 4, 1 );

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
