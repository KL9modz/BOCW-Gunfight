// ─────────────────────────────────────────────────────────────────────────────
// TEST — in-match switchmap_load + JOINER FOLLOW (the priority avenue)
//
// Hook: scripts\mp_common\bb.gsc  → MP MATCH server VM (the DEFAULT inject pair,
//       replace scripts\core_common\clientids_shared.gsc). NOT a frontend payload.
//
// ── THE QUESTION ─────────────────────────────────────────────────────────────
// The carry (`map()` + switchmap_switch) desyncs and CRASHES connected clients.
// switchmap_load(map, gametype) + switchmap_switch() is the COORDINATED two-phase
// load stock uses IN-MATCH (cp_common/load.gsc:412, zm_utility_zsurvival:153) where
// clients FOLLOW. B2 only proved it crashes from the FRONTEND VM (mis-aimed). This
// runs it from the in-match server VM — where stock calls it — and asks:
//   B) does an in-match switchmap even change the map without crashing the host?
//   C) does a CONNECTED FRIEND FOLLOW onto the new map instead of crashing?
// If C is yes → real Gunfight, any map, joiner-safe, host-inject only. Requirement met.
//
// ── STAGED SAFETY (flip read_only, recompile+reinject — gunfight_mod's pattern) ──
//   Phase A: read_only=1            → diagnostics only, NEVER switches. Zero risk.
//   Phase B: read_only=0, min=1     → HOST ALONE. Does in-match switchmap work at all?
//   Phase C: read_only=0, min=2     → friend joined + launched. Does the friend follow?
//   Phase D (LATER, in gunfight_mod): target an INCOMPATIBLE map with the mod's guards.
//
// ── GUARDS (load-bearing, from test_mapswitch's scars) ───────────────────────
//   • ONCE-ONLY via dvar #"gf_sw_done" — set BEFORE the call, SURVIVES the reload,
//     so the switch fires exactly once ever (else on_start on the new map re-fires
//     → infinite reload loop).
//   • target_map must be a VERIFIED-LOADABLE name. mapexists() LIES (B5). A bad name
//     tears the session down with no error. "mp_kgb" is a native Gunfight map — safe.
//   • startup_delay lets the match fully settle before switching (mid-load = crash).
//   • visible countdown so klaze/friend can back out if anything looks wrong.
//
// ── OUTPUT (id*100000+value, iprintlnbold) ───────────────────────────────────
//   70xxxxx  reporter: level.gametype defined (1/0)
//   71xxxxx  reporter: player count
//   72xxxxx  reporter: read_only flag
//   73xxxxx  reporter: gf_sw_done guard.  ★ 7300001 SEEN ON A MAP YOU DID NOT LAUNCH
//            = the switch fired and the new map's match VM is alive = SUCCESS
//   90xxxxx  countdown seconds before firing
//   91xxxxx  FIRING switchmap_load NOW (value = player count at fire)
//   92xxxxx  returned from switchmap_switch still alive (unexpected)
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace test_switchmap;

function private autoexec __init__system__()
{
    system::register( #"test_switchmap", &__init__, undefined, undefined, undefined );
}

function private config()
{
    return {
        #read_only:     1,          // 1 = diagnostics only, NEVER switch. Flip to 0 to arm.
        #target_map:    "mp_kgb",   // VERIFIED-LOADABLE ONLY. Host on a DIFFERENT compatible map.
        #min_players:   1,          // 1 = solo (Phase B). 2 = require the friend (Phase C).
        #startup_delay: 4,          // seconds into a round before arming. Kept short: a round can end fast
                                    // by elimination, killing this thread; it self-retries next round
                                    // until ONE round lasts long enough. Let a round breathe to fire.
        #countdown:     3           // visible seconds before the switch fires
    };
}

function private __init__()
{
    level.gfsw = config();
    level thread reporter();
    callback::on_start_gametype( &on_start );
}

function private on_start()
{
    level thread maybe_switch();
}

function private maybe_switch()
{
    cfg = level.gfsw;

    if ( cfg.read_only )
    {
        return;                                  // Phase A: never switch
    }

    if ( getdvarint( #"gf_sw_done", 0 ) != 0 )
    {
        return;                                  // already fired (we are on the NEW map now)
    }

    wait cfg.startup_delay;                       // let the match fully load and settle

    if ( getplayers().size < cfg.min_players )
    {
        return;                                   // not enough players — relaunch with the friend in
    }

    for ( i = cfg.countdown; i > 0; i-- )
    {
        emit( 90, i );
        wait 1;
    }

    if ( getplayers().size < cfg.min_players )
    {
        return;                                   // someone left during the countdown — abort
    }

    setdvar( #"gf_sw_done", 1 );                  // GUARD FIRST — survives the reload, no re-fire
    emit( 91, getplayers().size );

    m = getrootmapname( cfg.target_map );
    switchmap_load( m, level.gametype );          // level.gametype carries the LIVE Gunfight code
    level waittilltimeout( 25, #"switchmap_preload_finished" );  // wait for the LOAD to finish before committing
    switchmap_switch();

    emit( 92, 1 );                                // only if the VM somehow survives the switch
}

function private reporter()
{
    wait 5;

    while ( true )
    {
        cfg = level.gfsw;
        emit( 70, isdefined( level.gametype ) ? 1 : 0 );
        emit( 71, getplayers().size );
        emit( 72, cfg.read_only );
        emit( 73, getdvarint( #"gf_sw_done", 0 ) );
        wait 4;
    }
}

function private emit( id, value )
{
    v = 99999;

    if ( isdefined( value ) )
    {
        v = value;
    }

    foreach ( player in getplayers() )
    {
        player iprintlnbold( id * 100000 + v );
    }
}
