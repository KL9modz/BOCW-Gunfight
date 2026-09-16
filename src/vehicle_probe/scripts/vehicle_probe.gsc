// ─────────────────────────────────────────────────────────────────────────────
// Vehicle PARITY probe — read-only. Answers ONE question:
//
//     Is there any overlap between the asset names we HAVE and the vehicle asset
//     names we NEED?
//
// Hook: scripts\mp_common\bb.gsc, mode=mp  (see ../gsc.conf)
//
// WHY THIS EXISTS. spawnvehicle() takes a `vehicle#` asset name, and the T9 dump
// contains almost none of them: only 68 `vehicle#hash_*` references exist, ALL in
// campaign scriptbundle/scene/, and the one field that feeds spawnvehicle for
// streaks (bundle.ksvehicle) is stripped to the bare string "vehicle#". The ACTS
// community hash index does not have them either — 0 of 68, verified against a
// working control (`acts lookup 6bada5168620c5fe` -> `default`). See [[vehicles]].
//
// But isassetloaded() hands the name to the ENGINE to resolve, and a wrong guess
// simply returns false. So guessing is FREE, and a GSC loop can test hundreds of
// candidates in a frame when the output is only a count. That is this probe.
//
// Three candidate sets, three counts:
//   MODELS  105  `veh_t8/t9_*` xmodel names from the dump. These are the WRONG
//                namespace (they appear as "model#veh_t9_..."), so a non-zero
//                count here means the model# and vehicle# namespaces SHARE NAMES
//                — which would essentially solve the candidate list.
//   HASHES   68  the known campaign `vehicle#hash_*`. Non-zero = campaign vehicle
//                assets are resident on an MP map (interesting, but not the goal).
//   TYPES    29  the vehicle::add_main_callback behaviour strings. These are
//                dispatch keys read off self.vehicletype (globallogic_vehicle.gsc:37),
//                NOT asset names — so this is expected to read 0. It is included
//                because "expected 0" is only worth anything if it is measured.
//
// ⚠ READS ONLY. No spawnvehicle, no usevehicle, no setteam. Nothing here changes
//    gameplay or touches stock state. The heavy work is a few hundred isassetloaded
//    calls in one frame, once, 8s after gametype start.
//
// ⚠ ALL-ZERO IS A REAL RESULT, NOT A FAILURE — but only if probe 2 proves the call
//    form works. Read that one first. If every count including the controls is 0,
//    the call form is wrong and the run says nothing about residency.
//
// ── HOW TO READ THE OUTPUT ────────────────────────────────────────────────────
// Retail renders NUMBERS ONLY (see ../mp_probe/scripts/mp_probe.gsc), so every
// answer is a digit. THREE LINES, printed back-to-back with no wait, via iprintln
// (the STACKING feed) rather than iprintlnbold (which replaces). One screenshot
// captures the whole run — no transcribing seven scrolling values, which is what
// cost mp_probe five of its seven readings on the first attempt.
//
// Each line is  <LINE-ID><3 digits><3 digits><3 digits>  — fields are FIXED WIDTH
// and zero-padded, so a leading zero never collapses and the line always has the
// same length. Read it in 3-digit groups after the first digit.
//
//   1 AAA BBB HHH    A = MODELS resident, form A (#"vehicle")   ⬅ THE ANSWER
//                    B = MODELS resident, form B ("vehicle")
//                    H = HASHES resident (campaign scene vehicles)
//
//   2 YYY GGG SSS    Y = TYPES resident        expected 0
//                    G = bogus-asset control   MUST BE 0 — see below
//                    S = veh_spawn_point structs on this map
//
//   3 TTT            T = total candidates tested. BUILD CONTROL, must read 202.
//                        Anything else means a different build is running than
//                        the one this comment describes.
//
// So `1000000000` is the all-zero result and `1105098068` would be A=105 B=98 H=68.
//
// ⚠ READ FIELD G FIRST. It tests a name no asset can have, in both call forms
//    (+1 = form A claimed it is loaded, +2 = form B did). Non-zero means
//    isassetloaded is not answering the question we think it is and the ENTIRE RUN
//    IS VOID. All-zero counts are only meaningful once G reads 0.
//
// ⚠ A vs B is the CALL-FORM discriminator. If they disagree, the type argument's
//    form matters and every future isassetloaded call must use the winning one.
//
// ⚠ Field A is the decision:
//       >0  the model# and vehicle# namespaces share names. The candidate list is
//           essentially solved and step 2 (the residency probe) can be built.
//        0  parity is dead; the authoritative list has to come out of the shipped
//           fastfiles with ACTS on the game machine.
//
// ⚠ Field S: is stock Path A reachable on this map at all? mp_common/vehicle.gsc:104
//    reads these structs, and its entry point initvehiclemap() has ZERO callers in
//    the whole dump. Expect 0. A non-zero would be a genuine surprise worth chasing.
//
// ── ONCE PER MAP, NOT ONCE PER ROUND ─────────────────────────────────────────
// callback::on_start_gametype fires EVERY ROUND, not just every map load —
// mp_probe measured exactly that (its probe 6 reads 1 every round because `level`
// is rebuilt). Left alone this probe would redump its three lines mid-match, every
// round, and nothing in the output would distinguish "new map" from "next round".
//
// So the last reported map is stashed in the dvar `gf_vprobe_map`. Dvars survive
// rounds AND matches (the same property gunfight_menu relies on for its config),
// while `level` does not — so a dvar is the only thing that can carry this.
//
// ⚠ This means ONE PAYLOAD COVERS MANY MAPS. on_start_gametype re-fires on a map
//    change, so a single injection plus in-game map switches reports once per map,
//    cleanly, without relinking. That is what collapses a 40-map matrix into a
//    handful of game launches.
// ⚠ To force a re-read of a map already seen, set gf_vprobe_map to anything else.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\struct;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace vehicle_probe;

function private autoexec __init__system__()
{
    system::register( #"vehicle_probe", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &on_start );
}

function private on_start()
{
    level thread report();
}

// ── candidate sets ───────────────────────────────────────────────────────────
// Built as c[c.size] = ... rather than array( ... ) deliberately: the arg-count
// limit of array() on this compiler is unknown and a 105-arg call is not the place
// to find out. This form is what stock uses and cannot hit one.

function private models()
{
    c = [];
    c[c.size] = #"veh_t8_drone_hunter_mp_light";
    c[c.size] = #"veh_t8_drone_raps";
    c[c.size] = #"veh_t8_drone_recon_cp_light_small";
    c[c.size] = #"veh_t8_drone_siege_arm_d";
    c[c.size] = #"veh_t8_drone_siege_minigun_d";
    c[c.size] = #"veh_t8_drone_siege_rocket_d";
    c[c.size] = #"veh_t8_drone_wasp_piece_body_mp";
    c[c.size] = #"veh_t8_drone_wasp_piece_wing_rocket_left_mp";
    c[c.size] = #"veh_t8_drone_wasp_piece_wing_rocket_right_mp";
    c[c.size] = #"veh_t8_mil_air_gunship";
    c[c.size] = #"veh_t8_mil_air_jet_fighter_mp_dark";
    c[c.size] = #"veh_t8_mil_air_jet_fighter_mp_light";
    c[c.size] = #"veh_t8_mil_boat_tactical_raft";
    c[c.size] = #"veh_t8_mil_helicopter_light_debris_fastrope_bar";
    c[c.size] = #"veh_t8_mil_helicopter_light_debris_skids";
    c[c.size] = #"veh_t8_mil_helicopter_light_debris_tail";
    c[c.size] = #"veh_t8_mil_jet_cargo_gunship_pickup";
    c[c.size] = #"veh_t8_soviet_civ_sedan_midsize_dest_vehicle";
    c[c.size] = #"veh_t8_vintage_gaz66_troopbed";
    c[c.size] = #"veh_t9_civ_eu_2dr_wagon_blue";
    c[c.size] = #"veh_t9_civ_eu_2dr_wagon_red";
    c[c.size] = #"veh_t9_civ_eu_bicycle";
    c[c.size] = #"veh_t9_civ_eu_sedan_50s";
    c[c.size] = #"veh_t9_civ_eu_van_work";
    c[c.size] = #"veh_t9_civ_eu_wagon_50s";
    c[c.size] = #"veh_t9_civ_hatchback_80s_tan";
    c[c.size] = #"veh_t9_civ_hatchback_80s_tan_eu_tkd";
    c[c.size] = #"veh_t9_civ_ru_bus_large";
    c[c.size] = #"veh_t9_civ_ru_sedan_60s_vista";
    c[c.size] = #"veh_t9_civ_ru_sedan_80s";
    c[c.size] = #"veh_t9_civ_ru_sedan_80s_base";
    c[c.size] = #"veh_t9_civ_ru_sedan_80s_cp";
    c[c.size] = #"veh_t9_civ_ru_sedan_80s_cp_wet";
    c[c.size] = #"veh_t9_civ_ru_sedan_80s_kgb_cp";
    c[c.size] = #"veh_t9_civ_ru_sedan_80s_police_lit";
    c[c.size] = #"veh_t9_civ_ru_truck_light_hardtop_cp";
    c[c.size] = #"veh_t9_civ_us_station_wagon_vista_wht";
    c[c.size] = #"veh_t9_civ_us_truck_4x4_cp_duga";
    c[c.size] = #"veh_t9_civ_us_truck_4x4_cp_turkey";
    c[c.size] = #"veh_t9_civ_us_van_vista_window";
    c[c.size] = #"veh_t9_drone_rcxd_pickup";
    c[c.size] = #"veh_t9_mil_air_flogger_fly_napalm";
    c[c.size] = #"veh_t9_mil_air_flogger_pickup";
    c[c.size] = #"veh_t9_mil_air_transport_cp";
    c[c.size] = #"veh_t9_mil_gaz66_riders";
    c[c.size] = #"veh_t9_mil_helicopter_gunship_riders";
    c[c.size] = #"veh_t9_mil_remote_missile";
    c[c.size] = #"veh_t9_mil_remote_missile_pickup";
    c[c.size] = #"veh_t9_mil_ru_air_awacs_gear_down";
    c[c.size] = #"veh_t9_mil_ru_air_counter_spyplane_mp";
    c[c.size] = #"veh_t9_mil_ru_air_counter_spyplane_mp_friendly";
    c[c.size] = #"veh_t9_mil_ru_air_counter_spyplane_pickup";
    c[c.size] = #"veh_t9_mil_ru_air_flogger_flight";
    c[c.size] = #"veh_t9_mil_ru_air_frogfoot_mp";
    c[c.size] = #"veh_t9_mil_ru_air_frogfoot_pickup";
    c[c.size] = #"veh_t9_mil_ru_air_spyplane_friendly_mp";
    c[c.size] = #"veh_t9_mil_ru_air_spyplane_mp";
    c[c.size] = #"veh_t9_mil_ru_air_spyplane_pickup";
    c[c.size] = #"veh_t9_mil_ru_air_vtol_forger_cockpit";
    c[c.size] = #"veh_t9_mil_ru_air_vtol_forger_flight";
    c[c.size] = #"veh_t9_mil_ru_air_vtol_forger_pickup";
    c[c.size] = #"veh_t9_mil_ru_heli_gunship_hind";
    c[c.size] = #"veh_t9_mil_ru_heli_gunship_hind_yam";
    c[c.size] = #"veh_t9_mil_ru_truck_50s_cargo_delivery_tenla_market";
    c[c.size] = #"veh_t9_mil_ru_truck_light_base";
    c[c.size] = #"veh_t9_mil_ru_truck_light_mp_tundra";
    c[c.size] = #"veh_t9_mil_ru_truck_transport";
    c[c.size] = #"veh_t9_mil_snowmobile_spawn_medpack";
    c[c.size] = #"veh_t9_mil_snowmobile_spawn_ski";
    c[c.size] = #"veh_t9_mil_us_air_aurora_spyplane_friendly";
    c[c.size] = #"veh_t9_mil_us_air_napalm_bomb_projectile";
    c[c.size] = #"veh_t9_mil_us_air_napalm_bomb_projectile_lrg";
    c[c.size] = #"veh_t9_mil_us_air_napalm_strike";
    c[c.size] = #"veh_t9_mil_us_air_napalm_strike_pickup";
    c[c.size] = #"veh_t9_mil_us_air_napalm_strike_vista";
    c[c.size] = #"veh_t9_mil_us_air_snake";
    c[c.size] = #"veh_t9_mil_us_air_snake_finish_move_vehicle";
    c[c.size] = #"veh_t9_mil_us_air_snake_pickup";
    c[c.size] = #"veh_t9_mil_us_air_snake_riders";
    c[c.size] = #"veh_t9_mil_us_air_transport_hpc_intro";
    c[c.size] = #"veh_t9_mil_us_air_transport_static_ground";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_armada_turret_base";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_chopper_gunner";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_cp_armada";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_cp_armada_02";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_cp_prisoner_dest";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_cp_takedown";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_pickup";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_riders";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_riders_armada_ai";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_riders_armada_player";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_static";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_vip_settings";
    c[c.size] = #"veh_t9_mil_us_helicopter_light_zm_sv_intro_static";
    c[c.size] = #"veh_t9_mil_us_turret_lmg_stationary_cp";
    c[c.size] = #"veh_t9_mphd_uaz_riders";
    c[c.size] = #"veh_t9_mphd_uaz_riders_amk";
    c[c.size] = #"veh_t9_mphd_uaz_riders_takedown";
    c[c.size] = #"veh_t9_rcxd_finish_prop_fin_move";
    c[c.size] = #"veh_t9_sv_atv_payload";
    c[c.size] = #"veh_t9_sv_truck_hemtt_payload_delivery";
    c[c.size] = #"veh_t9_turret_m60_riders";
    c[c.size] = #"veh_t9_turret_mg_riders";
    c[c.size] = #"veh_t9_zm_arc_xd";
    c[c.size] = #"veh_t9_zm_ndu_mil_tank_tiger";
    return c;
}

function private scenehashes()
{
    c = [];
    c[c.size] = #"hash_111730ae6dcbc586";
    c[c.size] = #"hash_13ba9174c27237b";
    c[c.size] = #"hash_13c60e71eef46ebb";
    c[c.size] = #"hash_1465fc41ab88939";
    c[c.size] = #"hash_15e59336c36ee995";
    c[c.size] = #"hash_16d38c1f1db587be";
    c[c.size] = #"hash_17e868e0ebf3c1d6";
    c[c.size] = #"hash_19a7610c6357620";
    c[c.size] = #"hash_1a60a087a340574b";
    c[c.size] = #"hash_1bdb534f1e8e23f5";
    c[c.size] = #"hash_1c5963188cf189df";
    c[c.size] = #"hash_1e00d92ee0b1bf4c";
    c[c.size] = #"hash_1e4b2ebe1fd4fa4";
    c[c.size] = #"hash_1f5c1aa7b1348d33";
    c[c.size] = #"hash_20966d639ebe6604";
    c[c.size] = #"hash_20e7b5f57aaa9ee4";
    c[c.size] = #"hash_23e5c1239feb3a5f";
    c[c.size] = #"hash_2a648336db6d465d";
    c[c.size] = #"hash_2ed1cf0a9a3c0624";
    c[c.size] = #"hash_3061aec11377f525";
    c[c.size] = #"hash_308369147254321b";
    c[c.size] = #"hash_32fd84f720fa8002";
    c[c.size] = #"hash_3463002d802c1a98";
    c[c.size] = #"hash_37c73ce15aabb343";
    c[c.size] = #"hash_3b8ba30888baf51e";
    c[c.size] = #"hash_3d2bbfdb89093d91";
    c[c.size] = #"hash_3efa223f4a0bffcd";
    c[c.size] = #"hash_3f0737088e8a4d33";
    c[c.size] = #"hash_3f8c4e1a10327ae3";
    c[c.size] = #"hash_41ba5d07050a929e";
    c[c.size] = #"hash_423271dd4886e7b6";
    c[c.size] = #"hash_437293ae239af1ab";
    c[c.size] = #"hash_46249425f37afc74";
    c[c.size] = #"hash_464fbee7a41c7f8f";
    c[c.size] = #"hash_4bfd80fe09072db3";
    c[c.size] = #"hash_4c21aec4081d030d";
    c[c.size] = #"hash_4dfaa11717f3881";
    c[c.size] = #"hash_51c4f4dc2591b475";
    c[c.size] = #"hash_53c596704f007063";
    c[c.size] = #"hash_5405b8cdc93df2b4";
    c[c.size] = #"hash_5477254cf96259f4";
    c[c.size] = #"hash_550d303ee2de9a65";
    c[c.size] = #"hash_581bb1b0fa4a3139";
    c[c.size] = #"hash_58cc8ce25d32031f";
    c[c.size] = #"hash_5c374aecf501acfd";
    c[c.size] = #"hash_60868aaa45d05ffe";
    c[c.size] = #"hash_61b8f8f61f4b9ce7";
    c[c.size] = #"hash_62d385495a2ba813";
    c[c.size] = #"hash_631691623ad368bd";
    c[c.size] = #"hash_651ba81a7ca235ef";
    c[c.size] = #"hash_653e1d46cd298e05";
    c[c.size] = #"hash_6595f5efe62a4ec";
    c[c.size] = #"hash_67b0ecffae4660e6";
    c[c.size] = #"hash_67f8285741e2ff4b";
    c[c.size] = #"hash_75cd743f7ce45c03";
    c[c.size] = #"hash_78b4d74a45945568";
    c[c.size] = #"hash_7b5b5a302a2fd586";
    c[c.size] = #"hash_7c54a264a26cb1eb";
    c[c.size] = #"hash_7c74af55b6caaaf5";
    c[c.size] = #"hash_7d6b94652ad8c0e1";
    c[c.size] = #"hash_8343e51833c1331";
    c[c.size] = #"hash_8ffa37a1df9d511";
    c[c.size] = #"hash_985b7e40ee02aa2";
    c[c.size] = #"hash_a74a0cbdfa84dbe";
    c[c.size] = #"hash_b71765a3bf22ce7";
    c[c.size] = #"hash_c07fec522db452c";
    c[c.size] = #"hash_d51aef98cfc8f9b";
    c[c.size] = #"hash_d51aff98cfc914e";
    return c;
}

function private typenames()
{
    c = [];
    c[c.size] = #"air_vehicle1";
    c[c.size] = #"auto_turret";
    c[c.size] = #"emp_turret";
    c[c.size] = #"helicopter_heavy";
    c[c.size] = #"hemtt_wz";
    c[c.size] = #"microwave_turret";
    c[c.size] = #"player_atv";
    c[c.size] = #"player_btr40";
    c[c.size] = #"player_fav_light";
    c[c.size] = #"player_jetski";
    c[c.size] = #"player_large_helicopter_armada";
    c[c.size] = #"player_motorcycle_2wd";
    c[c.size] = #"player_pbr";
    c[c.size] = #"player_sedan";
    c[c.size] = #"player_snowmobile";
    c[c.size] = #"player_tank";
    c[c.size] = #"player_truck_transport";
    c[c.size] = #"player_uaz";
    c[c.size] = #"player_van";
    c[c.size] = #"player_vtol";
    c[c.size] = #"raps";
    c[c.size] = #"rcxd";
    c[c.size] = #"repulsor_drone";
    c[c.size] = #"siegebot";
    c[c.size] = #"tactical_raft_wz";
    c[c.size] = #"wasp";
    c[c.size] = #"xbot";
    c[c.size] = #"veh_flak_drone_mp";
    c[c.size] = #"vehicle_t9_rcxd_racing";
    return c;
}

// ── counters. Two call forms, identical otherwise. ───────────────────────────

function private count_a( list )
{
    n = 0;

    for ( i = 0; i < list.size; i++ )
    {
        if ( isassetloaded( #"vehicle", list[ i ] ) )
        {
            n++;
        }
    }

    return n;
}

function private count_b( list )
{
    n = 0;

    for ( i = 0; i < list.size; i++ )
    {
        if ( isassetloaded( "vehicle", list[ i ] ) )
        {
            n++;
        }
    }

    return n;
}

function private report()
{
    // on_start_gametype fires before players are in the match.
    wait( 8 );

    // ── once per MAP, not once per round ─────────────────────────────────────
    // `level` is wiped every round (mp_probe probe 6 measured it), so the marker
    // has to live somewhere that survives — a dvar. Empty mapname would make every
    // round look like a new map, so treat that as "cannot gate" and report anyway
    // rather than going silent.
    curmap = getdvarstring( #"mapname", "" );

    if ( curmap != "" )
    {
        if ( curmap == getdvarstring( #"gf_vprobe_map", "" ) )
        {
            return;
        }

        setdvar( #"gf_vprobe_map", curmap );
    }

    m = models();
    h = scenehashes();
    t = typenames();

    // ⚠ THE CONTROL. A name no asset can have, in both call forms. Read this
    // field before believing any other number in the run.
    bogus = 0;

    if ( isassetloaded( #"vehicle", #"veh_t9_gf_probe_nonexistent_asset" ) )
    {
        bogus += 1;
    }

    if ( isassetloaded( "vehicle", #"veh_t9_gf_probe_nonexistent_asset" ) )
    {
        bogus += 2;
    }

    // Path A reachability. struct::get_array can return undefined; guard the .size
    // read rather than assume, since an undefined here would kill the thread and
    // silently truncate the whole report.
    nodes = struct::get_array( "veh_spawn_point", "targetname" );
    spawnpoints = 0;

    if ( isdefined( nodes ) )
    {
        spawnpoints = nodes.size;
    }

    // Three lines, no waits between them, so they land in the feed together and a
    // single screenshot captures the run.
    line( 1, count_a( m ), count_b( m ), count_a( h ) );
    line( 2, count_a( t ), bogus, spawnpoints );

    // ⚠ Line 3 is deliberately SHORT (4 digits, e.g. 3202). The 10-digit packing
    //    used above tops out at 1,105,105,068 for line 1 and 2,029,003,999 for
    //    line 2, both inside signed 32-bit range — but a leading 3 would make
    //    3,202,000,000 and OVERFLOW. Do not "make it consistent".
    emitraw( 3000 + clamp999( m.size + h.size + t.size ) );
}

// Pack three fixed-width zero-padded fields behind a line id:  <id>AAABBBCCC.
// Fixed width is what makes a leading zero survive — a value of 0 in the first
// field must not collapse the line to fewer digits, or the groups misalign and
// the screenshot is unreadable.
//
// ⚠⚠ SIGNED 32-BIT CEILING — an invariant for anyone growing a candidate list.
//    Max is 2,147,483,647. Worst cases as shipped:
//        line 1   1,105,105,068   (id 1, fields ≤ 105 / 105 / 68)   headroom ~1.04e9
//        line 2   2,029,003,999   (id 2, fields ≤  29 /   3 / 999)  headroom ~1.18e8
//    Line 2 is the tight one: with id 2, FIELD A MAY NOT EXCEED 146 before the
//    line overflows and silently reports a wrong number. Field A on line 2 is the
//    TYPES count, bounded by typenames().size — currently 29. **If that list ever
//    grows past ~146, this packing breaks.** Line 1's fields are bounded by
//    models()/scenehashes() sizes and have far more room, but the same logic applies.
//    There is no runtime guard for this: clamp999 protects each FIELD, not the SUM.
function private line( id, a, b, c )
{
    emitraw( id * 1000000000 + clamp999( a ) * 1000000 + clamp999( b ) * 1000 + clamp999( c ) );
}

// Every field is 3 digits wide. A value that cannot fit would shift every field to
// its left and silently corrupt the whole line, so clamp rather than overflow —
// 999 is visibly wrong, a shifted line is not.
function private clamp999( v )
{
    if ( !isdefined( v ) )
    {
        return 999;
    }

    if ( v > 999 )
    {
        return 999;
    }

    if ( v < 0 )
    {
        return 999;
    }

    return v;
}

// iprintln, NOT iprintlnbold: the bold window holds one message and each print
// replaces the previous, so three bold lines would leave only the last on screen.
// iprintln stacks in the feed, which is the whole point of packing into 3 lines.
function private emitraw( value )
{
    foreach ( player in getplayers() )
    {
        player iprintln( value );
    }
}
