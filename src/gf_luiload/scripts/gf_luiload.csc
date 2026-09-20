// ─────────────────────────────────────────────────────────────────────────────
// gf_luiload — CLIENT: does luiload() load our injected luafile-pool chunk into the LUI VM?
//
// Hook: scripts\core_common\load_shared.csc, mode=mp  (see ../gsc.conf)
//
// THE QUESTION (docs/notes/lui-dll-re.md): the pause menu is Lua and GSC/CSC can't modify it, but the
// engine has a CSC builtin `luiload` (exe+0xa403a00, funcs_cw.csv). If `luiload("x64:HEX.lua")` loads
// our injected pool chunk (gf_loadtest, compiled by tools/lui/lj2t9.py, injected by tools/lui/luapool.py
// as name x64:6766100000000001.lua), our chunk's StartMenu_Main override runs and draws "GUNFIGHT MENU
// LOADED" in the ESC menu — the integrated pause-menu tab route with NO DLL. If luiload no-ops or takes
// a different arg form, we fall back to the lua-loader-hook DLL (same lj2t9 bytecode).
//
// ⚠ luiload's arg semantics are unproven (zero stock callers). This tries the require-style name
// "x64:HEX.lua" (name = FNV1a(".lua", HEX) & MASK63, what luapool --inject --as HEX gives it).
//
// READOUT — one continuous line (the debug-feed convention, [[debug-feed-one-line]]):
//   GF LUILOAD n:N calling:1 returned:R  (R=1 once luiload returns without erroring the client thread)
// The real signal is VISUAL: open ESC and look for "GUNFIGHT MENU LOADED". A single screenshot of the
// line + the ESC menu is the result. If `calling:1 returned:0` sticks, luiload errored the thread on
// that arg form. WRITES NOTHING (no clientfields, no models) — joiners untouched by construction.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\system_shared;

#namespace gf_luiload;

#define CHUNK "x64:6766100000000001.lua"

function private autoexec __init__system__()
{
    system::register( #"gf_luiload", &preinit, undefined, undefined, undefined );
}

function private preinit()
{
    level thread status_loop();
    level thread loader();
}

function private loader()
{
    wait( 6 ); // let the LUI VM finish loading its own chunks first

    // MEASURED 2026-09-18: luiload() on a chunk that is NOT in the pool HARD-CRASHES the game (it does
    // not error cleanly). So we NEVER call luiload until the pool chunk is definitely injected. Gate on
    // the dvar gf_luiload_go: the operator injects the pool chunk (luapool.py --inject) FIRST, then sets
    // `gf_luiload_go 1`, and only then do we fire luiload ONCE, on a rising edge (0->1). Reset it to 0 to
    // arm another attempt (e.g. after re-injecting the pool). One call per edge = at most one crash-risk
    // per deliberate trigger.
    fired = 0;
    for ( ;; )
    {
        go = getdvarint( #"gf_luiload_go", 0 );
        if ( go && !fired )
        {
            fired = 1;
            level.gf_attempt++;
            level thread try_luiload();
        }
        else if ( !go )
        {
            fired = 0;            // falling edge re-arms
        }
        wait( 1 );
    }
}

function private try_luiload()
{
    luiload( CHUNK );          // hard-crashes if CHUNK is not a loadable pool entry; else returns
    level.gf_returned++;       // only reached when luiload returns without crashing/erroring
}

// one complete line, every ~2s (the debug-feed convention)
function private status_loop()
{
    level.gf_attempt = 0;
    level.gf_returned = 0;

    for ( ;; )
    {
        iprintlnbold( "^3GF LUILOAD^7 go:" + getdvarint( #"gf_luiload_go", 0 ) + " att:" + level.gf_attempt + " ok:" + level.gf_returned + " ^5(pool-inject, THEN set gf_luiload_go 1)" );
        wait( 2 );
    }
}
