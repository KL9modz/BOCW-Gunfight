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
// ⚠⚠ TWO WAYS THIS BITES, and BOTH HAVE NOW HAPPENED. THREE guards - and the
//    second failure mode HAS NO GUARD, see 4 below:
//
//      1. read_only        - default 1. Reports and switches nothing.
//      2. already-there    - if the live map IS the target, do nothing. Should do
//                            all the work: after a good switch it stops matching.
//      3. attempt counter  - game. scope, hard cap. Fires when guard 2's reasoning
//                            is wrong, which would otherwise retry every round
//                            forever. Guards the MAP LOAD LOOP.
//      4. mapexists()      - 🪦 REMOVED. B5 measured it returning TRUE FOR ANY
//                            NAME, including invented ones. It would have passed
//                            the map that broke the session. No guard 4 exists.
//
//    Guard 3 is deliberately redundant with guard 2 - it is reachable exactly when
//    guard 2's reasoning is wrong, which is the only case anyone cares about. Do
//    not delete it as unreachable.
//
//    ⚠⚠ A bad TARGET is a different failure from a bad LOOP, guards 1-3 do not
//       touch it, AND THERE IS NO GUARD FOR IT. On 2026-09-08 "mp_hijacked_rm" -
//       a name taken from the dump's scripts/mp/ listing - tore down the live map,
//       failed to load, and left the session glitched on the OLD map with no error.
//
//       B5 was run to build a guard for this and came back useless: mapexists()
//       answers TRUE for every name including invented ones. There is currently no
//       way to ask whether a map will load without trying it, and trying it is the
//       destructive act.
//
//    ▶ SO: DO NOT RUN THIS LIVE AGAINST AN UNVERIFIED MAP NAME. The only safe
//      targets are maps confirmed by having actually carried to them.
//
//    ⚠⚠ AND THE HIJACKED RUN CHANGED TWO VARIABLES AT ONCE, which is why it
//       explains nothing. Every successful carry on record is ZOO, VIA THE MENU.
//       The failure was HIJACKED, VIA THIS SCRIPT. Map and mechanism both moved,
//       so the break is attributable to either and to neither.
//
//       Three theories were floated for it and ALL THREE ARE DEAD:
//         - "the map is unloadable"     -> mapexists is useless, proves nothing (B5)
//         - "Hijacked never shipped"    -> it did, BOCW Season 4, 2021-06-17
//         - "the install is partial"    -> 36 maps selectable in custom games,
//                                          matching the menu's 36 exactly
//
//    ▶ THE TEST THAT ACTUALLY ISOLATES IT: run THIS SCRIPT against ZOO - the map
//      known to carry cleanly by hand. Works -> the mechanism is fine and Hijacked
//      is the problem. Fails -> the mechanism is the problem and the map never was.
//      One variable. That is the current configuration.
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
//   (probe 4 removed - mapexists is useless in this build, see B5)
//   5xxxxx  reached the switch call?             1 = called on a player, 0 = no players
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
    //    ▶ THE FAILURE IS SILENT AND DESTRUCTIVE. No error, no refusal, and no
    //      point after map() at which the script can still save the session.
    //
    //    🪦 RETRACTED: "Hijacked is BO2-era content that never shipped in CW."
    //       WRONG - it shipped in BOCW Season 4, 2021-06-17, as a 6v6 map.
    //    🪦 RETRACTED: "the install is partial, only 19 maps present."
    //       WRONG - klaze counted 36 selectable in custom games, matching the
    //       menu's 36 exactly. The install is complete and the earlier "19" was a
    //       miscount, not a filter and not missing content.
    //
    //    ⚠ So there is NO established reason why Hijacked failed. Both stories
    //      were invented to fit one observation and neither survived a check.
    //      Leave it open rather than reaching for a third.
    //
    // 🪦 **B5 ANSWERED IT, AND THE ANSWER WAS "NO GUARD IS AVAILABLE".** The open
    //    question here was whether mapexists() returns 0 for this name. It does
    //    not - B5's control read 900003, meaning it returns TRUE for the live map
    //    AND for "zzz_not_a_map", with all 38 names coming back set. So it would
    //    have passed mp_hijacked_rm straight through.
    //
    //    There is currently NO way to ask whether a map will load without loading
    //    it, and loading it is the destructive act. Until that changes, the target
    //    must be a map already confirmed by carrying to it through the menu.
    //
    // ▶ DEFAULT IS NOW A MAP KLAZE HAS ACTUALLY CARRIED TO AND PLAYED (Zoo,
    //   3v3 Gunfight, 60s rounds, 2026-09-08). Prefer a map from the Atian menu's
    //   own list over anything found only by grepping scripts/mp/.
    target = "mp_zoo_rm";

    // ⚠ RUN WITH THIS AT 1 FIRST. Reports the state, switches nothing, and
    //   confirms the name comparison behaves before anything can reload.
    read_only = 0;   // LIVE. Target is mp_zoo_rm - a map klaze has carried to and PLAYED.

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

    // ── guard 4 — 🪦 REMOVED THE DAY IT WAS ADDED. mapexists() IS USELESS HERE. ──
    //
    // It was added as "the guard that would have prevented the hang". Test B5 then
    // measured it (2026-09-08) and it **returns true for everything**:
    //
    //     control probe = mapexists( live_map )*2 + mapexists( "zzz_not_a_map" )
    //     read 900003   -> true for the real map AND for a name that cannot exist
    //     all 38 names  -> 32767 / 32767 / 63, every bit set in every group
    //
    // ⚠ So it would have returned 1 for mp_hijacked_rm and waved the destructive
    //   switch straight through. **A guard that always passes is worse than no
    //   guard**, because it manufactures confidence. Deleted rather than left in
    //   with a caveat, since a caveat in a comment does not stop the next reader
    //   trusting the code.
    //
    // ✅ B5's CONTROL is what caught this - the payload alone looked like a clean
    //   "all 38 maps are loadable" result. That is the jump_height lesson from
    //   mp-dvars.md, and the reason crack-cmds.py refuses to report when its own
    //   controls fail. Keep putting controls in probes.
    //
    // ▶ THE REAL PRECONDITION IS STILL UNKNOWN, so there is no guard 4 to replace
    //   it with. Until one exists, the ONLY safe targets are maps empirically
    //   confirmed loadable by carrying to them through the Atian Menu - whose
    //   shipped list is 19 of the source's 48, and may well BE the curated
    //   loadable set. Recording that list is test A2, and it is now load-bearing
    //   for this route rather than a curiosity.

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
    // ── RUN 4 CHANGE: run the sequence ON A PLAYER, not on level. ───────────
    //
    // ⚠ HYPOTHESIS, not a conclusion. What is actually observed so far:
    //     run 1  map() alone,     Hijacked, level thread -> nothing happened
    //     run 2  full sequence,   Hijacked, level thread -> tore the map down,
    //                                                       never loaded, glitched
    //     run 3  full sequence,   ZOO,      level thread -> nothing happened
    //
    //   Same three calls and same thread context produced two completely different
    //   outcomes on two maps. So "the mechanism is broken" does not fit, and
    //   neither does "the map was bad". Something else differs.
    //
    // ▶ The difference from the menu, missed while reading its source: func_set_map
    //   runs as a METHOD ON THE PLAYER. The line above its call is
    //   `self menu_drawing_function(...)`, so `self` is the menu's player entity and
    //   the unqualified map() inside INHERITS it. We call from a level thread where
    //   self is undefined. If map() is an entity method rather than a global
    //   builtin, that is the whole story - and ate47's table records arity and
    //   address but NOT whether a builtin needs a self.
    //
    // ⚠ getplayers()[0] is the host in a private lobby, the same role the menu runs
    //   as. Guarded because indexing an empty array would crash, and a crash
    //   mid-round is worse than another no-op.
    players = getplayers();

    if ( players.size == 0 )
    {
        emit( 5, 0 );   // nobody to run as; the call was never attempted
        return;
    }

    emit( 5, 1 );

    players[ 0 ] thread do_switch( target );

    // Nothing after this is guaranteed to run; the map is loading. The result
    // comes from this script's NEXT on_start, on the new map.
}

// Runs with self = the player, mirroring func_set_map's context exactly.
function private do_switch( target )
{
    map( target );
    wait( 1 );
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

    wait( 5 );
}
