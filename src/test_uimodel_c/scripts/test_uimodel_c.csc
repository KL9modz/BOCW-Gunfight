// ─────────────────────────────────────────────────────────────────────────────
// TEST P6b — the lobby UI model tree, asked from the CLIENT VM this time.
//
// ⚠⚠ THIS IS A .csc — A CLIENT SCRIPT. First one in this project.
// Hook:    scripts\core_common\load_shared.csc
// Replace: scripts\core_common\radiation_debug.csc
//
// ── WHY A CLIENT SCRIPT ──────────────────────────────────────────────────────
// P6a asked the same questions from a SERVER script and control probe 80 read 0
// — not even `room`, `transitionMapIdOverride` or `fullscreenBlackCount`, all
// three proven to exist by the dump. The reason was in the dump the whole time:
//
//     getuimodel callers:   31 .csc files   vs   5 .gsc
//     lobby_root uses:       3 .csc (frontend.csc, character_customization.csc)
//                            1 .gsc — cp_common/load.gsc, which is CAMPAIGN
//
// The lobby model tree belongs to the CLIENT VM. `function_5f72e972` exists in
// both builtin tables, which is what misled P6a — **a builtin existing in a VM
// does not mean the data it reaches exists there.**
//
// ── REPLACE TARGET ───────────────────────────────────────────────────────────
// `clientids_shared.csc` DOES NOT EXIST — the proven-safe server replace has no
// client counterpart. `radiation_debug.csc` is **0 bytes** in the dump, declares
// no class, and is debug-named. Five other 0-byte candidates exist if it proves
// unsafe: placeables, item_world_cleanup, traps_deployable, challenges_shared,
// string_shared (all .csc).
// ⚠ `scene_model_shared` is the standing proof that "empty" is not automatically
//   "safe to lose" — it declared a class with an empty body and the frontend
//   needed the declaration at link time. These six declare nothing at all, which
//   is a stronger claim than "the body is empty". **Still test a lobby return.**
//
// ── REPORTING ────────────────────────────────────────────────────────────────
// `iprintlnbold` is in the CSC builtin table and is called BARE in client scripts
// (battlechatter.csc:910, fx_shared.csc:758) — no player prefix, it prints
// locally. So this reports exactly like every server probe here.
//
// ── PROBES (id*100000 + value) ───────────────────────────────────────────────
//   90xxxxx  CONTROL. bit0 "room" · bit1 "transitionMapIdOverride"
//            bit2 "fullscreenBlackCount" · bit3 "zzz_not_a_model"
//            **7 = the three real resolve, the fake does not. TRUST.**
//            15 = everything resolves → useless, discard (the B5/P6a failure)
//            0  = still the wrong VM or accessor
//   91xxxxx  group A bits 0..14 — map-shaped names
//   92xxxxx  group B bits 0..14 — playlist / gametype / lobby-state names
//   93xxxxx  file I/O alive? 0 no handle · 2 handle + write + close ran.
//            PREDICTED 0 (type=1 dev family). Self-verifying: check disk
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\system_shared;

#namespace test_uimodel_c;

function private autoexec __init__system__()
{
    system::register( #"test_uimodel_c", &preinit, undefined, undefined, undefined );
}

function private preinit()
{
    level thread watch();
}

function private watch()
{
    // No is_frontend_map() guard: it is a server-side util and this VM may not
    // have it. Printing in the match too is harmless and tells us whether the
    // tree differs between lobby and match, which is itself worth knowing.
    wait( 5 );

    while ( true )
    {
        report();
        wait( 15 );
    }
}

function private report()
{
    ctrl = 0;
    if ( model_exists( "room" ) )                    { ctrl += 1; }
    if ( model_exists( "transitionMapIdOverride" ) ) { ctrl += 2; }
    if ( model_exists( "fullscreenBlackCount" ) )    { ctrl += 4; }
    if ( model_exists( "zzz_not_a_model" ) )         { ctrl += 8; }

    emit( 90, ctrl );

    groupa = array( "mapId", "mapName", "map", "selectedMap", "currentMap",
                    "mapIndex", "mapid", "mapImage", "nextMap", "mapDisplayName",
                    "transitionMapId", "mapIdOverride", "levelName", "mapList",
                    "mapCount" );

    groupb = array( "playlist", "playlistId", "playlistName", "gametype",
                    "gameMode", "gameModeName", "gametypeName", "modeId",
                    "lobbyState", "isHost", "maxPlayers", "teamSize",
                    "matchStarting", "customGame", "privateMatch" );

    emit( 91, maskof( groupa ) );
    emit( 92, maskof( groupb ) );

}

// ── probe 93 REMOVED — CALLING THE FILE I/O FAMILY CRASHES THE GAME ─────────
//
// ⚠⚠ MEASURED 2026-09-10, and worse than predicted. openfile/fprintln/closefile
//    are type=1 (dev) in the CW table, so they were expected to be nulled and
//    return undefined. They do not: the call CRASHED the process. Engine minidump
//    at 09h22m25s, and NO gf_probe.txt was ever created.
//
//    ⚠ The previous build of this exact payload ran fine and printed its probes.
//      The ONLY change was adding the file test. So this is not the client-script
//      mechanism, not the hook, and not radiation_debug.csc as a replace target -
//      all three were already working.
//
// 🪦 THE LESSON, and it cost a launch: "self-verifying and free" was half right.
//    The verification was sound; the cost was not zero. A predicted-dead DEV
//    builtin must be tested ALONE, in a payload with nothing to lose - never
//    bolted onto a working probe, where its failure mode takes the working part
//    with it.
//
// ▶ Do not retry file logging. Screen capture stays the readout.

function private model_exists( name )
{
    m = getuimodel( function_5f72e972( #"lobby_root" ), name );
    return isdefined( m );
}

function private maskof( names )
{
    mask = 0;
    bit  = 1;

    foreach ( name in names )
    {
        if ( model_exists( name ) )
        {
            mask += bit;
        }

        bit *= 2;
    }

    return mask;
}

// ⚠ NO wait() HERE — THAT IS THE WHOLE POINT.
//
//   Every probe in this project printed one value every 5s, so a ~40s round
//   showed at most 8 of them and the important ones were routinely never seen
//   (probe 62 went unread for a dozen runs; P6a's 91/92 needed frame-hunting).
//   klaze, 2026-09-10: "theres got to be a better way to debug. can u show them
//   all at once?"
//
//   Client prints go to the CHAT FEED, which keeps history — so printing the
//   whole set back-to-back puts every value on screen at once, readable in a
//   single screenshot. The 5s spacing was solving a problem the chat feed does
//   not have.
function private emit( id, value )
{
    v = 99999;
    if ( isdefined( value ) )
    {
        v = value;
    }

    // Bare, not on a player: client scripts print locally.
    iprintlnbold( id * 100000 + v );
}
