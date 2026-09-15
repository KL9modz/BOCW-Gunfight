// ─────────────────────────────────────────────────────────────────────────────
// gunfight_menu_c — LUI-element probe (client-local form)
//
// Hook:    scripts\core_common\load_shared.csc      -> the MATCH client VM
// Replace: scripts\core_common\radiation_debug.csc  -> safe there (2026-09-10)
//
// STAGE 1 (text) DONE: LUIelemText renders stock localized KEYS; a plain string is
//   a FATAL LUI error. docs/notes/lui-elems.md. Two text rows kept as an alive-label.
//
// STAGE 2 (boxes) — LUIelemImage opens but will not FILL:
//   - rgba alone (material #"")            -> nothing (78110005, 2026-09-14)
//   - material = hash("white")             -> nothing, no crash (78111nn)
//   hash is the right FORM (text proved it) and #"white" is a real fill shader
//   (stock setshader( #"white" ), 31 sites) — so it null-resolved. The material
//   field is bgcache-backed; a material must be PRECACHED into the client element's
//   bgcache, which the bare openluielem path never does, and no stock code sets a
//   LUIelemImage material to ride on.
//
// ── THE ONE SWING (this build): does ANY other value FORM fill a box? ─────────
//   A vertical column of test boxes at x 25, each a thin bar, 4 y-units apart.
//   Whichever one FILLS names the value form the material field wants:
//     boxes 0..7  material = the INT INDEX 0..7   (WHITE tint)  -- "bgcache index" hypothesis
//     box  8      material = the STRING "white"   (RED tint)    -- "raw string name" hypothesis
//     box  9      material = the STRING "$white"  (RED tint)    -- alt raw name
//   All safe: a bad material null-resolved (no crash) last time; these are small
//   ints / short strings, same no-op class.
//
//   READING (top of the column is index 0, counting down):
//     a WHITE bar appears at position k  -> material wants an INT INDEX; k is a live
//                                           index. Boxes/bars WORK -> build the panel.
//     a RED bar appears                  -> material wants a RAW STRING name
//                                           ("white" = the upper red, "$white" = lower).
//     NOTHING fills (only the 2 text rows)-> no value form resolves from the bare-open
//                                           path; boxes are BLOCKED on bgcache precache.
//                                           Stop here; the answer is recorded.
//
// ── OUTPUT — 78 T B nn ───────────────────────────────────────────────────────
//   78  tag · T = both text rows open · B = how many of the 10 boxes opened (0..10,
//   shown as-is; 10 prints as "10") · nn = tick.  e.g. 7811005 -> T1, 10 boxes, tick 5.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\system_shared;

#namespace gunfight_menu_c;

function private autoexec __init__system__()
{
    system::register( #"gunfight_menu_c", &preinit, undefined, undefined, undefined );
}

function private preinit()
{
    level thread probe();
}

function private probe()
{
    wait( 5 );

    lcn   = 0;
    telem = hash( "LUIelemText" );
    ielem = hash( "LUIelemImage" );

    n = 0;

    while ( true )
    {
        n++;

        // stage 1 — the two proven text rows (stock keys ONLY)
        row( lcn, telem, 0, 40, 48, 1, 1, 1, #"mp/match_starting" );
        row( lcn, telem, 1, 50, 52, 1, 1, 0, #"mp/waiting_for_players" );

        text_ok = 0;
        if ( isluielemopen( lcn, telem, 0 ) && isluielemopen( lcn, telem, 1 ) ) { text_ok = 1; }

        // stage 2 — the material-form column. box( idx, x, y, w, h, r,g,b,a, material )
        // indices 0..7 as INT material values, white tint:
        box( lcn, ielem, 0, 25, 12, 40, 3, 1, 1, 1, 1, 0 );
        box( lcn, ielem, 1, 25, 16, 40, 3, 1, 1, 1, 1, 1 );
        box( lcn, ielem, 2, 25, 20, 40, 3, 1, 1, 1, 1, 2 );
        box( lcn, ielem, 3, 25, 24, 40, 3, 1, 1, 1, 1, 3 );
        box( lcn, ielem, 4, 25, 28, 40, 3, 1, 1, 1, 1, 4 );
        box( lcn, ielem, 5, 25, 32, 40, 3, 1, 1, 1, 1, 5 );
        box( lcn, ielem, 6, 25, 36, 40, 3, 1, 1, 1, 1, 6 );
        box( lcn, ielem, 7, 25, 40, 40, 3, 1, 1, 1, 1, 7 );
        // raw STRING material names, red tint:
        box( lcn, ielem, 8, 25, 44, 40, 3, 1, 0, 0, 1, "white" );
        box( lcn, ielem, 9, 25, 48, 40, 3, 1, 0, 0, 1, "$white" );

        b = 0;
        for ( i = 0; i < 10; i++ )
        {
            if ( isluielemopen( lcn, ielem, i ) ) { b++; }
        }

        // 78 T B nn
        iprintlnbold( 78000000 + text_ok * 100000 + b * 1000 + ( n % 100 ) );

        wait( 5 );
    }
}

function private row( lcn, elem, idx, x, y, r, g, b, key )
{
    if ( !isluielemopen( lcn, elem, idx ) )
    {
        openluielem( lcn, elem, idx );
        text_defaults( lcn, elem, idx );
        function_bcc2134a( lcn, elem, idx, "x", x );
        function_bcc2134a( lcn, elem, idx, "y", y );
        function_bcc2134a( lcn, elem, idx, "red", r );
        function_bcc2134a( lcn, elem, idx, "green", g );
        function_bcc2134a( lcn, elem, idx, "blue", b );
    }

    function_bcc2134a( lcn, elem, idx, "text", key );
}

// One box: open, size/placement/colour/alpha, then the material VALUE under test
// (an int index or a raw string — passed straight through). Material set every tick.
function private box( lcn, elem, idx, x, y, w, h, r, g, b, a, mat )
{
    if ( !isluielemopen( lcn, elem, idx ) )
    {
        openluielem( lcn, elem, idx );
        image_defaults( lcn, elem, idx );
        function_bcc2134a( lcn, elem, idx, "x", x );
        function_bcc2134a( lcn, elem, idx, "y", y );
        function_bcc2134a( lcn, elem, idx, "width", w );
        function_bcc2134a( lcn, elem, idx, "height", h );
        function_bcc2134a( lcn, elem, idx, "red", r );
        function_bcc2134a( lcn, elem, idx, "green", g );
        function_bcc2134a( lcn, elem, idx, "blue", b );
        function_bcc2134a( lcn, elem, idx, "alpha", a );
    }

    function_bcc2134a( lcn, elem, idx, "material", mat );
}

function private text_defaults( lcn, elem, idx )
{
    function_bcc2134a( lcn, elem, idx, "x", 0 );
    function_bcc2134a( lcn, elem, idx, "y", 0 );
    function_bcc2134a( lcn, elem, idx, "height", 0 );
    function_bcc2134a( lcn, elem, idx, "fadeOverTime", 0 );
    function_bcc2134a( lcn, elem, idx, "alpha", 1 );
    function_bcc2134a( lcn, elem, idx, "red", 1 );
    function_bcc2134a( lcn, elem, idx, "green", 1 );
    function_bcc2134a( lcn, elem, idx, "blue", 1 );
    function_bcc2134a( lcn, elem, idx, "text", #"" );
    function_bcc2134a( lcn, elem, idx, "horizontal_alignment", 0 );
}

function private image_defaults( lcn, elem, idx )
{
    function_bcc2134a( lcn, elem, idx, "x", 0 );
    function_bcc2134a( lcn, elem, idx, "y", 0 );
    function_bcc2134a( lcn, elem, idx, "width", 0 );
    function_bcc2134a( lcn, elem, idx, "height", 0 );
    function_bcc2134a( lcn, elem, idx, "fadeOverTime", 0 );
    function_bcc2134a( lcn, elem, idx, "alpha", 0 );
    function_bcc2134a( lcn, elem, idx, "red", 0 );
    function_bcc2134a( lcn, elem, idx, "green", 0 );
    function_bcc2134a( lcn, elem, idx, "blue", 0 );
    function_bcc2134a( lcn, elem, idx, "material", #"" );
}
