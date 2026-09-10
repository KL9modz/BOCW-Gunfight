// ─────────────────────────────────────────────────────────────────────────────
// P6c — the payload that PRINTED, plus exactly ONE addition.
//
// Hook:    scripts\core_common\load_shared.csc      -> the MATCH client VM
// Replace: scripts\core_common\radiation_debug.csc  -> safe there (ran and printed)
//
// ── WHY THIS IS A REWRITE AND NOT AN EDIT ────────────────────────────────────
// Five crashes on 2026-09-10 all came from stacking changes onto a payload whose
// last-known-good state had drifted. The version that ran cleanly:
//   - threaded DIRECTLY from preinit (no callback registration)
//   - printed immediately (no dvar stash)
//   - used ONLY function_5f72e972 (no getglobaluimodel)
// Everything added after that either crashed or could not be attributed, so this
// file is reset to that state and ONE thing is added.
//
// 🪦 getglobaluimodel() is DELIBERATELY ABSENT. It did not exist in the version
//    that ran, it was present in the version that crashed, and this game has
//    already shown that an unavailable builtin CRASHES rather than returning
//    undefined (openfile, earlier the same night). It is the prime suspect and it
//    does not come back until something else is ruled out.
//
// ── THE ONE ADDITION: does the ROOT resolve? ─────────────────────────────────
// The working run read control = 0, which was recorded as "no models". Whether
// the ROOT itself resolves was never established - and
// getuimodel( undefined, name ) can only ever return undefined, so a 0 control
// never separated:
//
//     "the root exists, none of these names are under it"   <- one finding
//     "the root does not exist in this VM at all"           <- a different one
//
// Probe 96 answers that with a single isdefined().
//
// ── OUTPUT - two lines every 10s ─────────────────────────────────────────────
//   96xxxxx  1 = function_5f72e972( #"lobby_root" ) returned a value
//            0 = it did not, so control-0 meant NO ROOT rather than no models
//   90xxxxx  control: bit0 "room" - bit1 "transitionMapIdOverride"
//            bit2 "fullscreenBlackCount" - bit3 "zzz_not_a_model"
//
// ⚠ Two lines only. The chat feed holds ~3 and each print costs two.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\system_shared;

#namespace test_uimodel_c;

function private autoexec __init__system__()
{
    system::register( #"test_uimodel_c", &preinit, undefined, undefined, undefined );
}

// Direct thread - exactly as in the version that printed. No
// callback::on_localclient_connect: that was added later, never demonstrated to
// help, and is one of the changes present in a build that crashed.
function private preinit()
{
    level thread watch();
}

function private watch()
{
    wait( 5 );

    while ( true )
    {
        report();
        wait( 10 );
    }
}

function private report()
{
    root_ok = 0;
    r = function_5f72e972( #"lobby_root" );
    if ( isdefined( r ) )
    {
        root_ok = 1;
    }

    ctrl = 0;
    if ( model_exists( "room" ) )                    { ctrl += 1; }
    if ( model_exists( "transitionMapIdOverride" ) ) { ctrl += 2; }
    if ( model_exists( "fullscreenBlackCount" ) )    { ctrl += 4; }
    if ( model_exists( "zzz_not_a_model" ) )         { ctrl += 8; }

    iprintlnbold( 96 * 100000 + root_ok );
    iprintlnbold( 90 * 100000 + ctrl );
}

function private model_exists( name )
{
    m = getuimodel( function_5f72e972( #"lobby_root" ), name );
    return isdefined( m );
}
