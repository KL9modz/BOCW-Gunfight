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

// ⚠⚠ STASH IN THE LOBBY, PRINT IN THE MATCH. The fix for the all-zeros run.
//
//    That run asked for `lobby_root` **while in a match** — because the match is
//    the only place client prints are visible (klaze saw output in-match and
//    nothing in the lobby). A lobby model tree is a LOBBY thing, so a control of
//    0 read from inside a match says nothing about whether it exists where it
//    lives. The reading was taken in the wrong place, not from the wrong VM.
//
//    Sampling and reporting are now separate: sample() runs constantly and writes
//    into dvars (setdvar is type=0 and in the CSC table, so a client script can
//    carry values across a map load exactly as the server-side P1 payload does),
//    and report() prints whatever is stashed. What the LOBBY measured is then
//    readable from inside the match.
function private watch()
{
    wait( 5 );

    while ( true )
    {
        sample();
        report();
        wait( 10 );
    }
}

// ⚠ Keeps the MAXIMUM ever seen, not the latest. If the tree exists in the lobby
//   and vanishes in the match, "latest" overwrites the real answer with a zero on
//   the way in — which is precisely how the previous run destroyed its own
//   evidence before it could be read.
function private sample()
{
    // ⚠⚠ THE TICK COUNTER IS THE POINT NOW. klaze, 2026-09-10: "i dont like that
    //    we are using the match to check the lobby." Correct - every zero so far
    //    was read in-match, and NOTHING ever confirmed this script runs in the
    //    LOBBY at all. Prints were only ever seen in a match. If the lobby half
    //    never executes, every model reading is meaningless rather than negative.
    setdvar( "gf_uc_t", getdvarint( "gf_uc_t", 0 ) + 1 );

    stash_max( "gf_uc_95", roots_defined() );
    stash_max( "gf_uc_90", control_via_lobby() );
    stash_max( "gf_uc_94", control_via_global() );
    stash_max( "gf_uc_91", maskof( group_a() ) );
    stash_max( "gf_uc_92", maskof( group_b() ) );
}

function private stash_max( key, value )
{
    if ( value > getdvarint( key, 0 ) )
    {
        setdvar( key, value );
    }
}

// probe 95 — does either ROOT resolve at all? Neither previous run asked this,
// and it is the first question: getuimodel() on an undefined root can only return
// undefined, so a 0 control never separated "no such model" from "no such root".
//   bit0 = function_5f72e972( #"lobby_root" )    bit1 = getglobaluimodel()
function private roots_defined()
{
    n = 0;

    r = function_5f72e972( #"lobby_root" );
    if ( isdefined( r ) ) { n += 1; }

    g = getglobaluimodel();
    if ( isdefined( g ) ) { n += 2; }

    return n;
}

function private control_via_lobby()
{
    n = 0;
    if ( model_exists( "room" ) )                    { n += 1; }
    if ( model_exists( "transitionMapIdOverride" ) ) { n += 2; }
    if ( model_exists( "fullscreenBlackCount" ) )    { n += 4; }
    if ( model_exists( "zzz_not_a_model" ) )         { n += 8; }
    return n;
}

// The same four names asked of the GLOBAL root. If 94 beats 90, the accessor was
// the problem all along — not the VM, not the names.
function private control_via_global()
{
    n = 0;
    if ( global_model_exists( "room" ) )                    { n += 1; }
    if ( global_model_exists( "transitionMapIdOverride" ) ) { n += 2; }
    if ( global_model_exists( "fullscreenBlackCount" ) )    { n += 4; }
    if ( global_model_exists( "zzz_not_a_model" ) )         { n += 8; }
    return n;
}

function private group_a()
{
    return array( "mapId", "mapName", "map", "selectedMap", "currentMap",
                  "mapIndex", "mapid", "mapImage", "nextMap", "mapDisplayName",
                  "transitionMapId", "mapIdOverride", "levelName", "mapList",
                  "mapCount" );
}

function private group_b()
{
    return array( "playlist", "playlistId", "playlistName", "gametype",
                  "gameMode", "gameModeName", "gametypeName", "modeId",
                  "lobbyState", "isHost", "maxPlayers", "teamSize",
                  "matchStarting", "customGame", "privateMatch" );
}

function private global_model_exists( name )
{
    g = getglobaluimodel();
    if ( !isdefined( g ) )
    {
        return false;
    }

    return isdefined( getuimodel( g, name ) );
}

// ⚠⚠ THE CHAT FEED HOLDS ABOUT THREE LINES. Measured 2026-09-10: printing five
//    probes back-to-back, klaze saw only the LAST THREE (94, 91, 92) — the two
//    that mattered, 95 and 90, had already scrolled off.
//
//    "Print them all at once" fixed the 5s-per-value problem and replaced it with
//    a scrollback one. So:
//      1. the LAST line printed is the one guaranteed to be readable, and
//      2. the critical values go in a SINGLE PACKED number, so no amount of
//         scrolling can separate them.
//
//    Packed as 99[R][LL][GG]:
//      R  = roots defined   1 lobby_root · 2 global · 3 both · 0 neither
//      LL = control via lobby_root   (2 digits, 0-15)
//      GG = control via global root  (2 digits, 0-15)
//    e.g. 9930700 = both roots resolve, lobby control 7 (the win), global 0.
// ⚠ ONE LINE. NOT THREE, NOT FIVE.
//   klaze, 2026-09-10: *"there was a new line between them. just compact"* — each
//   iprintlnbold costs TWO lines of feed, so five probes was ten lines against a
//   ~3-line window and the important ones were gone before they could be read.
//   91/92 are dropped rather than reordered: they are meaningless until the
//   control passes, so printing them at all was spending the only scarce resource
//   on the least useful values.
function private report()
{
    // ONE line, read as T-R-LL:
    //   T  ticks the sampler has run, capped at 9. **0 = the lobby half never
    //      ran, and every other digit is meaningless.** This is the digit that
    //      was missing from all three previous runs.
    //   R  roots: 1 lobby_root · 2 global · 3 both · 0 neither
    //   LL best control of the two roots (0-15). 7 = the win.
    t = getdvarint( "gf_uc_t", 0 );
    if ( t > 9 ) { t = 9; }

    best = getdvarint( "gf_uc_90", 0 );
    if ( getdvarint( "gf_uc_94", 0 ) > best ) { best = getdvarint( "gf_uc_94", 0 ); }

    emit( 99, t * 1000 + getdvarint( "gf_uc_95", 0 ) * 100 + best );
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
