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
// ── RUN 1 (2026-09-15, mp_sm_gas_station) settled the call form ──────────────
//   VPROBE mp_sm_gas_station A=105 B=1 H=68 T=29 G=1 S=0 N=202
// G=1 is the +1 bit: form A (#"vehicle", a HASHED type argument) said "loaded" for
// the bogus name - and for all 105 models, all 68 hashes and all 29 types. Form A
// answers yes to everything and is VOID. Form B ("vehicle", the plain string, the
// only form stock ever uses) passed its control and found exactly ONE resident model
// name. So the namespaces DO share names; v2 below says which.
//
// ── RUNS 2 AND 3 (v2, v3) CRASHED THE GAME AT LINK TIME - our bug, not the engine ──
// Both 5-6 s after the map switch, BEFORE the 8 s wait ended: nothing in report()
// ran. The prop line, copied from prop.gsc:1850, called getmapname() and
// tablelookupbyrow() as builtins - both are SCRIPT functions defined in prop.gsc
// (1825, 1834), absent from the engine table, so the linker could not resolve the
// imports and the game died (the logprint signature check-gsc.ps1 describes).
// check-gsc stage 4 now catches this class ("SCRIPT FUNCTION ... defined in file:line").
// An earlier revision blamed isassetloaded on an existing non-resident asset - that
// case is UNMEASURED, not suspect; the campaign hashes / type strings / plain-string
// names dropped from v2 can go back in, one set per run. See docs/notes/vehicles.md §5.
//
// ── HOW TO READ THE OUTPUT (v3) ───────────────────────────────────────────────
// v3 runs only what v1 proved safe - the 105 #"hashed" model names through the
// plain-string type form - and names the hit from a display-only list (no lookup
// on strings). ONE labelled line, re-printed every 3 s for the whole round, plus
// the PPROBE line (guarded, see prop_line).
//
//   VPROBE3 <map> G=n M=n[i:name i:name] S=n N=105
//
//   G   bogus-asset control (hashed, form B). MUST BE 0 or the run is void.
//   M   MODELS resident by isassetloaded( "vehicle", #"name" ) - hits as index:name
//   S   veh_spawn_point structs on this map (stock Path A) - expected 0
//   N   candidates tested. BUILD CONTROL, must read 105.
//
// scenehashes() and typenames() are kept as the documented candidate sets but are
// NOT CALLED - see run 2. Index lists stop after 24 entries with ",...".
//
// ── EVERY ROUND, EVERY MAP ────────────────────────────────────────────────────
// callback::on_start_gametype fires EVERY ROUND (mp_probe measured it: `level` is
// rebuilt, so this thread dies at the round end and starts again). The counts are
// per map, not per round, so re-reporting is harmless - and the map name is in the
// line, so a mid-match map switch is its own report. ONE PAYLOAD COVERS MANY MAPS:
// inject once, switch maps in game, read the line on each.
// (An earlier revision gated on the `mapname` dvar, which does not exist in CW -
// lobby_state LS2 measured it - so the gate never engaged anyway.)
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

// The same 105 names as plain strings, SAME ORDER (Mh indices refer to this order).
// Stock hands isassetloaded plain-string names too (an xanim name at
// script_2e03cad685678246.gsc:681), so this is a legal form, and a hit prints
// as text instead of needing an index lookup.
function private model_names()
{
    c = [];
    c[c.size] = "veh_t8_drone_hunter_mp_light";
    c[c.size] = "veh_t8_drone_raps";
    c[c.size] = "veh_t8_drone_recon_cp_light_small";
    c[c.size] = "veh_t8_drone_siege_arm_d";
    c[c.size] = "veh_t8_drone_siege_minigun_d";
    c[c.size] = "veh_t8_drone_siege_rocket_d";
    c[c.size] = "veh_t8_drone_wasp_piece_body_mp";
    c[c.size] = "veh_t8_drone_wasp_piece_wing_rocket_left_mp";
    c[c.size] = "veh_t8_drone_wasp_piece_wing_rocket_right_mp";
    c[c.size] = "veh_t8_mil_air_gunship";
    c[c.size] = "veh_t8_mil_air_jet_fighter_mp_dark";
    c[c.size] = "veh_t8_mil_air_jet_fighter_mp_light";
    c[c.size] = "veh_t8_mil_boat_tactical_raft";
    c[c.size] = "veh_t8_mil_helicopter_light_debris_fastrope_bar";
    c[c.size] = "veh_t8_mil_helicopter_light_debris_skids";
    c[c.size] = "veh_t8_mil_helicopter_light_debris_tail";
    c[c.size] = "veh_t8_mil_jet_cargo_gunship_pickup";
    c[c.size] = "veh_t8_soviet_civ_sedan_midsize_dest_vehicle";
    c[c.size] = "veh_t8_vintage_gaz66_troopbed";
    c[c.size] = "veh_t9_civ_eu_2dr_wagon_blue";
    c[c.size] = "veh_t9_civ_eu_2dr_wagon_red";
    c[c.size] = "veh_t9_civ_eu_bicycle";
    c[c.size] = "veh_t9_civ_eu_sedan_50s";
    c[c.size] = "veh_t9_civ_eu_van_work";
    c[c.size] = "veh_t9_civ_eu_wagon_50s";
    c[c.size] = "veh_t9_civ_hatchback_80s_tan";
    c[c.size] = "veh_t9_civ_hatchback_80s_tan_eu_tkd";
    c[c.size] = "veh_t9_civ_ru_bus_large";
    c[c.size] = "veh_t9_civ_ru_sedan_60s_vista";
    c[c.size] = "veh_t9_civ_ru_sedan_80s";
    c[c.size] = "veh_t9_civ_ru_sedan_80s_base";
    c[c.size] = "veh_t9_civ_ru_sedan_80s_cp";
    c[c.size] = "veh_t9_civ_ru_sedan_80s_cp_wet";
    c[c.size] = "veh_t9_civ_ru_sedan_80s_kgb_cp";
    c[c.size] = "veh_t9_civ_ru_sedan_80s_police_lit";
    c[c.size] = "veh_t9_civ_ru_truck_light_hardtop_cp";
    c[c.size] = "veh_t9_civ_us_station_wagon_vista_wht";
    c[c.size] = "veh_t9_civ_us_truck_4x4_cp_duga";
    c[c.size] = "veh_t9_civ_us_truck_4x4_cp_turkey";
    c[c.size] = "veh_t9_civ_us_van_vista_window";
    c[c.size] = "veh_t9_drone_rcxd_pickup";
    c[c.size] = "veh_t9_mil_air_flogger_fly_napalm";
    c[c.size] = "veh_t9_mil_air_flogger_pickup";
    c[c.size] = "veh_t9_mil_air_transport_cp";
    c[c.size] = "veh_t9_mil_gaz66_riders";
    c[c.size] = "veh_t9_mil_helicopter_gunship_riders";
    c[c.size] = "veh_t9_mil_remote_missile";
    c[c.size] = "veh_t9_mil_remote_missile_pickup";
    c[c.size] = "veh_t9_mil_ru_air_awacs_gear_down";
    c[c.size] = "veh_t9_mil_ru_air_counter_spyplane_mp";
    c[c.size] = "veh_t9_mil_ru_air_counter_spyplane_mp_friendly";
    c[c.size] = "veh_t9_mil_ru_air_counter_spyplane_pickup";
    c[c.size] = "veh_t9_mil_ru_air_flogger_flight";
    c[c.size] = "veh_t9_mil_ru_air_frogfoot_mp";
    c[c.size] = "veh_t9_mil_ru_air_frogfoot_pickup";
    c[c.size] = "veh_t9_mil_ru_air_spyplane_friendly_mp";
    c[c.size] = "veh_t9_mil_ru_air_spyplane_mp";
    c[c.size] = "veh_t9_mil_ru_air_spyplane_pickup";
    c[c.size] = "veh_t9_mil_ru_air_vtol_forger_cockpit";
    c[c.size] = "veh_t9_mil_ru_air_vtol_forger_flight";
    c[c.size] = "veh_t9_mil_ru_air_vtol_forger_pickup";
    c[c.size] = "veh_t9_mil_ru_heli_gunship_hind";
    c[c.size] = "veh_t9_mil_ru_heli_gunship_hind_yam";
    c[c.size] = "veh_t9_mil_ru_truck_50s_cargo_delivery_tenla_market";
    c[c.size] = "veh_t9_mil_ru_truck_light_base";
    c[c.size] = "veh_t9_mil_ru_truck_light_mp_tundra";
    c[c.size] = "veh_t9_mil_ru_truck_transport";
    c[c.size] = "veh_t9_mil_snowmobile_spawn_medpack";
    c[c.size] = "veh_t9_mil_snowmobile_spawn_ski";
    c[c.size] = "veh_t9_mil_us_air_aurora_spyplane_friendly";
    c[c.size] = "veh_t9_mil_us_air_napalm_bomb_projectile";
    c[c.size] = "veh_t9_mil_us_air_napalm_bomb_projectile_lrg";
    c[c.size] = "veh_t9_mil_us_air_napalm_strike";
    c[c.size] = "veh_t9_mil_us_air_napalm_strike_pickup";
    c[c.size] = "veh_t9_mil_us_air_napalm_strike_vista";
    c[c.size] = "veh_t9_mil_us_air_snake";
    c[c.size] = "veh_t9_mil_us_air_snake_finish_move_vehicle";
    c[c.size] = "veh_t9_mil_us_air_snake_pickup";
    c[c.size] = "veh_t9_mil_us_air_snake_riders";
    c[c.size] = "veh_t9_mil_us_air_transport_hpc_intro";
    c[c.size] = "veh_t9_mil_us_air_transport_static_ground";
    c[c.size] = "veh_t9_mil_us_helicopter_large_armada_turret_base";
    c[c.size] = "veh_t9_mil_us_helicopter_large_chopper_gunner";
    c[c.size] = "veh_t9_mil_us_helicopter_large_cp_armada";
    c[c.size] = "veh_t9_mil_us_helicopter_large_cp_armada_02";
    c[c.size] = "veh_t9_mil_us_helicopter_large_cp_prisoner_dest";
    c[c.size] = "veh_t9_mil_us_helicopter_large_cp_takedown";
    c[c.size] = "veh_t9_mil_us_helicopter_large_pickup";
    c[c.size] = "veh_t9_mil_us_helicopter_large_riders";
    c[c.size] = "veh_t9_mil_us_helicopter_large_riders_armada_ai";
    c[c.size] = "veh_t9_mil_us_helicopter_large_riders_armada_player";
    c[c.size] = "veh_t9_mil_us_helicopter_large_static";
    c[c.size] = "veh_t9_mil_us_helicopter_large_vip_settings";
    c[c.size] = "veh_t9_mil_us_helicopter_light_zm_sv_intro_static";
    c[c.size] = "veh_t9_mil_us_turret_lmg_stationary_cp";
    c[c.size] = "veh_t9_mphd_uaz_riders";
    c[c.size] = "veh_t9_mphd_uaz_riders_amk";
    c[c.size] = "veh_t9_mphd_uaz_riders_takedown";
    c[c.size] = "veh_t9_rcxd_finish_prop_fin_move";
    c[c.size] = "veh_t9_sv_atv_payload";
    c[c.size] = "veh_t9_sv_truck_hemtt_payload_delivery";
    c[c.size] = "veh_t9_turret_m60_riders";
    c[c.size] = "veh_t9_turret_mg_riders";
    c[c.size] = "veh_t9_zm_arc_xd";
    c[c.size] = "veh_t9_zm_ndu_mil_tank_tiger";
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

// ── hit list. Form B ("vehicle") only - form A is void (run 1). ─────────────

// hashed list -> "n[i:name,j:name]" - names come from the parallel display list
// and are never passed to the engine (run 2)
function private hits( list, names )
{
    n = 0;
    txt = "";

    for ( i = 0; i < list.size; i++ )
    {
        if ( isassetloaded( "vehicle", list[ i ] ) )
        {
            n++;

            if ( n <= 24 )
            {
                txt += ( n > 1 ? "," : "" ) + i + ":" + names[ i ];
            }
        }
    }

    return n + "[" + txt + ( n > 24 ? ",..." : "" ) + "]";
}

function private report()
{
    // on_start_gametype fires before players are in the match.
    wait( 8 );

    names = model_names();
    m = models();

    // ⚠ THE CONTROL. A name no asset can have, hashed, form B - the exact call v1
    // proved safe. Read this field before believing any other number in the run.
    bogus = 0;

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

    line = "^3VPROBE3 ^7" + getdvarstring( #"sv_mapname", "?" )
        + " G=" + bogus + " M=" + hits( m, names ) + " S=" + spawnpoints
        + " N=" + m.size;

    pline = prop_line();

    // Computed once, shown for the whole round: the feed fades in seconds, so a
    // single print is only readable if someone is staring at it 8 s into the round.
    // Two lines per tick: this payload also carries the static-prop read, so both
    // probes land in one match (see prop_line).
    for ( ;; )
    {
        emit( line );
        emit( pline );
        wait( 3 );
    }
}

// ── the static-prop read (src/prop_probe) ────────────────────────────────────
// Mirrored VERBATIM between prop_probe.gsc and vehicle_probe.gsc so both probes
// read in ONE match: every injection shares the same replace target, so two
// payloads cannot coexist. Edit both or neither.
//
//   PPROBE <map> tbl=n rows=n xs=n s=n m=n l=n xl=n other=n first=<model> res=n G=n
//
//   tbl    isassetloaded( "stringtable", path ) - the guard STOCK puts in front of
//          every table read it is not sure of (scoreevents_shared.gsc:502/532/537).
//          0 = no Prop Hunt table on this map; nothing else is read. That is a REAL
//          RESULT: stock itself falls back to an invisible prop.
//   rows   numrows in gamedata/tables/mp/<map>_ph.csv (prop.gsc:1850) <- THE NUMBER
//   xs..xl the size buckets, keyed off column 1 exactly as stock getpropsize does
//          (a switch on hashed literals against the runtime cell - a proven form);
//          other = rows whose size text matched none of the five.
//   first  the model name in row 0 - the map's OWN curated prop, read at runtime.
//   res    1 if that model is a resident xmodel by isassetloaded( "xmodel", name ).
//          ⚠ Only asked when tbl=1: the model is then in the map's own curated
//          table, so it exists AND is resident - the one case run 2 left safe.
//   G      bogus-asset control, hashed, form B. MUST BE 0 or res means nothing.
function private prop_line()
{
    // Built exactly as stock builds it (prop.gsc:1852-1853). Stock's getmapname() is a
    // SCRIPT function there (prop.gsc:1825, `return level.script;`), not a builtin -
    // calling it bare from another namespace crashed the game twice (runs 2 and 3).
    mapname = level.script;

    if ( !isdefined( mapname ) )
    {
        mapname = util::get_map_name();
    }

    path = "gamedata/tables/mp/" + mapname + "_ph.csv";

    bogus = 0;

    if ( isassetloaded( "xmodel", #"p9_gf_probe_nonexistent_prop" ) )
    {
        bogus += 2;
    }

    tbl = isassetloaded( "stringtable", path ) ? 1 : 0;

    if ( !tbl )
    {
        return "^3PPROBE ^7" + getdvarstring( #"sv_mapname", "?" ) + " tbl=0 G=" + bogus;
    }

    numrows = tablelookuprowcount( path );

    if ( !isdefined( numrows ) )
    {
        numrows = 0;
    }

    xsmall = 0;
    small = 0;
    medium = 0;
    large = 0;
    xlarge = 0;
    other = 0;

    for ( i = 0; i < numrows; i++ )
    {
        sizetext = table_cell( path, i, 1 );

        switch ( sizetext )
        {
            case #"xsmall":
                xsmall++;
                break;
            case #"small":
                small++;
                break;
            case #"medium":
                medium++;
                break;
            case #"large":
                large++;
                break;
            case #"xlarge":
                xlarge++;
                break;
            default:
                other++;
                break;
        }
    }

    first = "-";
    res = "-";

    if ( numrows > 0 )
    {
        firstmodel = table_cell( path, 0, 0 );

        if ( isdefined( firstmodel ) && firstmodel != "" )
        {
            first = firstmodel;
            res = isassetloaded( "xmodel", firstmodel ) ? 1 : 0;
        }
    }

    return "^3PPROBE ^7" + getdvarstring( #"sv_mapname", "?" )
        + " tbl=1 rows=" + numrows + " xs=" + xsmall + " s=" + small + " m=" + medium
        + " l=" + large + " xl=" + xlarge + " other=" + other
        + " first=" + first + " res=" + res + " G=" + bogus;
}

// prop.gsc:1834 - also a SCRIPT function there, not a builtin (same trap as getmapname).
// The real builtin is tablelookuprow( table, row ), which returns the row as an array.
function private table_cell( table, row, col )
{
    columns = tablelookuprow( table, row );

    if ( isdefined( columns ) && col < columns.size )
    {
        return columns[ col ];
    }

    return "";
}

// iprintln, NOT iprintlnbold: the bold window holds one message and each print
// replaces the previous; iprintln stacks in the feed, where the mod menu prints too.
function private emit( text )
{
    foreach ( player in getplayers() )
    {
        player iprintln( text );
    }
}
