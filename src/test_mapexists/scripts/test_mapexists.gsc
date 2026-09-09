// ─────────────────────────────────────────────────────────────────────────────
// TEST B5 — which of the 38 map names can this install actually load?
//
// docs/notes/test-queue.md B5 · cw-builtins.md
// Hook: scripts\mp_common\bb.gsc, mode=mp
//
// ⚠ READ-ONLY. mapexists() asks; it loads nothing and tears nothing down. This
//   exists because A4 did the opposite on 2026-09-08: map( "mp_hijacked_rm" )
//   began tearing down the live map, never brought up the target, and left the
//   session glitched on the old map with no error at any point. That failure is
//   SILENT and DESTRUCTIVE, so the name has to be checked BEFORE the teardown.
//
// A name in the dump's scripts/mp/ proves a SCRIPT shipped. It does not prove the
// map is in this install. This is the difference, measured.
//
// ── HOW TO READ THE OUTPUT ────────────────────────────────────────────────────
// PROBE_ID * 100000 + VALUE, one every 5s.
//
// ⚠⚠ READ PROBE 9 FIRST. IT IS THE CONTROL, AND IF IT IS WRONG EVERYTHING ELSE
//    IS NOISE - the jump_height lesson from mp-dvars.md, and the same discipline
//    crack-cmds.py enforces by refusing to report when its controls fail.
//
//   9xxxxx  control  = mapexists(live map)*2 + mapexists("zzz_not_a_map")
//             900002  ✅ correct: knows the real one, rejects the fake one. TRUST.
//             900003  🪦 returns true for everything. USELESS - discard probes 1-3.
//             900000  🪦 returns false for everything. USELESS - discard.
//             900001  🪦 inverted or nonsense. Discard.
//
// Then three bitmasks, 15 + 15 + 8 names, bit 0 = first in each group.
// ⚠ 15 per group is deliberate: the value field must stay under 100000, and
//   2^15 = 32768 fits where 2^20 would not.
//
//   1xxxxx  group A bits 0..14   amerika apocalypse black_sea cartel cliffhanger
//                                drivein_rm dune echelon express_rm firebase
//                                hijacked_rm jungle_rm kgb mall miami
//   2xxxxx  group B bits 0..14   miami_strike moscow nuketown6 paintball_rm
//                                raid_rm russianbase_rm satellite slums_rm
//                                sm_amsterdam sm_berlin_tunnel sm_central
//                                sm_deptstore sm_finance sm_game_show
//                                sm_gas_station
//   3xxxxx  group C bits 0..7    sm_market sm_vault tank tundra village_rm
//                                zoo_rm  (+2 spare bits, always 0)
//
// ▶ The bit that settles A4: group A bit 10 = mp_hijacked_rm.
//   0 -> mapexists() would have refused it, and guard 4 covers that failure.
//   1 -> mapexists() says it is fine and the load broke anyway. Guard 4 does NOT
//        cover this, the real precondition is something else, and NO further
//        switch should be attempted until it is known.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace test_mapexists;

function private autoexec __init__system__()
{
    system::register( #"test_mapexists", &__init__, undefined, undefined, undefined );
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

    wait( 10 );

    // ── CONTROL FIRST ───────────────────────────────────────────────────────
    // The live map must exist; a made-up name must not. A builtin that answers
    // true for everything is worse than no reading at all, because it looks like
    // data.
    ctrl = 0;

    if ( is_true( mapexists( util::get_map_name() ) ) )
    {
        ctrl += 2;
    }

    if ( is_true( mapexists( "zzz_not_a_map" ) ) )
    {
        ctrl += 1;
    }

    emit( 9, ctrl );

    groupa = array( "mp_amerika", "mp_apocalypse", "mp_black_sea", "mp_cartel",
                    "mp_cliffhanger", "mp_drivein_rm", "mp_dune", "mp_echelon",
                    "mp_express_rm", "mp_firebase", "mp_hijacked_rm",
                    "mp_jungle_rm", "mp_kgb", "mp_mall", "mp_miami" );

    groupb = array( "mp_miami_strike", "mp_moscow", "mp_nuketown6",
                    "mp_paintball_rm", "mp_raid_rm", "mp_russianbase_rm",
                    "mp_satellite", "mp_slums_rm", "mp_sm_amsterdam",
                    "mp_sm_berlin_tunnel", "mp_sm_central", "mp_sm_deptstore",
                    "mp_sm_finance", "mp_sm_game_show", "mp_sm_gas_station" );

    groupc = array( "mp_sm_market", "mp_sm_vault", "mp_tank", "mp_tundra",
                    "mp_village_rm", "mp_zoo_rm" );

    emit( 1, maskof( groupa ) );
    emit( 2, maskof( groupb ) );
    emit( 3, maskof( groupc ) );
}

function private maskof( names )
{
    mask = 0;
    bit  = 1;

    foreach ( name in names )
    {
        if ( is_true( mapexists( name ) ) )
        {
            mask += bit;
        }

        bit *= 2;
    }

    return mask;
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
