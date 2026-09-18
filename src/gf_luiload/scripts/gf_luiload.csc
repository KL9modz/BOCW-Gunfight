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

    level.gf_calling = 1;
    luiload( CHUNK );          // if this errors the thread, returned stays 0
    level.gf_returned = 1;
}

// one complete line, every ~2s
function private status_loop()
{
    level.gf_calling = 0;
    level.gf_returned = 0;
    n = 0;

    for ( ;; )
    {
        n++;
        iprintlnbold( "^3GF LUILOAD^7 n:" + n + " calling:" + level.gf_calling + " returned:" + level.gf_returned + " ^5(ESC->look for GUNFIGHT MENU LOADED)" );
        wait( 2 );
    }
}
