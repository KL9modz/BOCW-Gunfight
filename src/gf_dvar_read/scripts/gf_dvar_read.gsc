// ─────────────────────────────────────────────────────────────────────────────
// gf_dvar_read — a SERVER-side readout for values a CLIENT script stashed.
//
// Hook:    scripts\mp_common\bb.gsc            (the proven MP hook)
// Replace: scripts\core_common\clientids_shared.gsc  (the proven-safe replace)
//
// ── WHY THIS EXISTS ──────────────────────────────────────────────────────────
// The client probe hooked at frontend.csc runs in the LOBBY — which is where the
// UI model tree lives — but client prints do not render in the lobby, so it has
// no way to report. Hooked at load_shared.csc instead it reported fine but only
// ever ran IN THE MATCH, which is why every model reading came back zero: the
// sampler never sampled. Two hooks, each with exactly the half we needed.
//
// ▶ So: the CLIENT payload samples and stashes into dvars in the lobby, and THIS
//   server payload prints the stash in the match. Dvars are process-wide and
//   survive a map load (B4 proved that for map_restart; a lobby→match transition
//   is the same process).
//
// ⚠⚠ TWO PAYLOADS AT ONCE, WHICH IS NORMALLY FORBIDDEN — and this is the
//    exception the rule actually allows. B9 measured that a second injection
//    breaks the link when both share a REPLACE target, because injectcw
//    overwrites that script's buffer. These two do not share one:
//
//      client:  frontend.csc          -> radiation_debug.csc   (0 bytes)
//      server:  bb.gsc                -> clientids_shared.gsc  (proven safe)
//
//    ⚠ Untested in combination. If the client payload stops running when this is
//      injected, that is the finding — record it and go back to one at a time.
//    ⚠ scene_model_shared is the standing warning about second replace targets,
//      but it failed because the FRONTEND needed a class it declared;
//      radiation_debug.csc declares nothing and is 0 bytes.
//
// ── OUTPUT ───────────────────────────────────────────────────────────────────
// One line, 99TRLL, the same packing the client used:
//   T   sampler ticks in the LOBBY, capped at 9. **0 = the lobby half never ran**
//   R   roots: 1 lobby_root · 2 global · 3 both · 0 neither
//   LL  best control of the two roots (0-15). 7 = the win
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;

#namespace gf_dvar_read;

function private autoexec __init__system__()
{
    system::register( #"gf_dvar_read", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &on_start );
}

function private on_start()
{
    level thread report_loop();
}

function private report_loop()
{
    wait( 8 );

    while ( true )
    {
        t = getdvarint( #"gf_uc_t", 0 );
        if ( t > 9 )
        {
            t = 9;
        }

        best = getdvarint( #"gf_uc_90", 0 );
        if ( getdvarint( #"gf_uc_94", 0 ) > best )
        {
            best = getdvarint( #"gf_uc_94", 0 );
        }

        // 99 P T R LL  — P is the new digit:
        //   0 preinit never ran · 1 preinit ran · 2 on_localclient_connect fired
        packed = getdvarint( #"gf_uc_p", 0 ) * 10000
               + t * 1000
               + getdvarint( #"gf_uc_95", 0 ) * 100
               + best;

        foreach ( player in getplayers() )
        {
            player iprintlnbold( 99 * 100000 + packed );
        }

        wait( 10 );
    }
}
