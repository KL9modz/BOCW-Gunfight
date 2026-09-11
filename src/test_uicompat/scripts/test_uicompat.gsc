// ─────────────────────────────────────────────────────────────────────────────
// P11 — does the map↔mode COMPATIBILITY model resolve in a VM we control?
//
// Hook:    scripts\core_common\load_shared.gsc  -> SERVER FRONTEND VM (P1: runs in
//          the lobby). Replace scripts\core_common\clientids_shared.gsc (proven safe).
//
// ── WHY THIS, AND WHY IT IS NEW ───────────────────────────────────────────────
// Research (2026-09-10) traced the picker's "map not compatible with the selected
// mode" gate to a LUI UI-MODEL: `uimodeldatastruct #hash_109ccf57a41ffd82`, linked
// from the `arena_playlist_game_modes_maps` datasource (core_frontend.csv:67980).
// That is the thing the lobby glitch reconfigures.
//
// Every prior UI-model probe (P8–P10) failed because it used INVENTED model names.
// This uses the REAL hash. And the dump shows hash-named models are fetched as
// ROOTS:  function_5f72e972( #"hash_410fe12a68d6e801" )  — exactly this shape. So
// the one question:
//
//   ▶ Does  function_5f72e972( #"hash_109ccf57a41ffd82" )  resolve here?
//     If yes, we have reached the compat/playlist model from an injectable VM —
//     the exact state the glitch changes — and a follow-up can read/write it.
//
// ── RESOLVE-ONLY. P-series discipline: change one thing, prove it, no crashes. ──
// Only function_5f72e972 + getuimodel + isdefined — all type=0, all exercised safely
// in P6c/P8. No getglobaluimodel (the P6c crash suspect). No writes. No new builtins.
//
// ── STASH IN LOBBY, PRINT IN MATCH (P7: the lobby has no text surface) ─────────
//
// ── OUTPUT (id*100000+value) ─────────────────────────────────────────────────
//   71xxxxx  lobby ticks. 0 = never sampled the frontend -> everything else moot
//   72xxxxx  mask:  bit0  function_5f72e972(#"hash_109ccf57a41ffd82") resolves  <- THE WIN
//                   bit1  lobby_root resolves (sanity; P8 = yes)
//                   bit2  getuimodel(lobby_root, #"hash_109ccf57a41ffd82") resolves
//                   bit3  getuimodel(lobby_root,"zzz_not_a_model") resolves (fake; expect 0)
//            ideal 3 (root+sanity, fake 0) or 7 (also a child); 8-bit set = no discrimination
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace test_uicompat;

function private autoexec __init__system__()
{
    system::register( #"test_uicompat", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    level thread lobby_watch();
    callback::on_start_gametype( &on_start );
}

function private lobby_watch()
{
    wait( 3 );

    while ( true )
    {
        if ( util::is_frontend_map() )
        {
            sample();
        }

        wait( 6 );
    }
}

function private sample()
{
    stash_max( #"gf_uc_71", getdvarint( #"gf_uc_71", 0 ) + 1 );

    mask = 0;

    // THE probe: the compat/playlist model as a named root, by its REAL hash.
    m = function_5f72e972( #"hash_109ccf57a41ffd82" );
    if ( isdefined( m ) )
    {
        mask += 1;
    }

    // Sanity + alternate access path via lobby_root (P8 proved lobby_root resolves).
    lr = function_5f72e972( #"lobby_root" );
    if ( isdefined( lr ) )
    {
        mask += 2;

        if ( isdefined( getuimodel( lr, #"hash_109ccf57a41ffd82" ) ) )
        {
            mask += 4;
        }

        // Discrimination: a name that cannot exist must NOT resolve (P6c: safe, returns undef).
        if ( isdefined( getuimodel( lr, "zzz_not_a_model" ) ) )
        {
            mask += 8;
        }
    }

    stash_max( #"gf_uc_72", mask );
}

function private stash_max( key, value )
{
    if ( value > getdvarint( key, 0 ) )
    {
        setdvar( key, value );
    }
}

function private on_start()
{
    level thread report();
}

function private report()
{
    wait( 10 );

    while ( true )
    {
        emit( 71, getdvarint( #"gf_uc_71", 0 ) );
        emit( 72, getdvarint( #"gf_uc_72", 0 ) );
        wait( 5 );
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

    wait( 5 );
}
