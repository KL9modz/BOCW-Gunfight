// ─────────────────────────────────────────────────────────────────────────────
// Static-prop probe — read-only. Answers, per map, in one screenshot:
//
//     Does this map ship a curated Prop Hunt prop table, how big is it, what
//     shape is it, and is the first model in it actually resident?
//
// Hook: scripts\mp_common\bb.gsc, mode=mp  (see ../gsc.conf)
//
// WHY THIS EXISTS. Prop Hunt reads a per-map curated prop table at
// mp_common/gametypes/prop.gsc:1850:
//
//     mapname = getmapname();
//     path    = "gamedata/tables/mp/" + mapname + "_ph.csv";
//     numrows = tablelookuprowcount( path );
//
// Eleven columns: model, size text, scale, offset xyz, rotation xyz, height, range.
// That is a hand-curated list of props resident on that map, already tuned with
// placement offsets. It is exactly what a prop menu wants, and it is READABLE AT
// RUNTIME — the CSV is not in the dump, and does not need to be. See [[static-props]].
//
// ⚠ Prop Hunt did not ship on every map. Stock's own fallback (prop.gsc:1910) is
//    `if ( numrows == 0 )` -> add "tag_origin", an INVISIBLE model. So the row count
//    per map is the single number that decides whether this feature is free on a
//    given map or needs a hand-built list. This probe's job is to collect it.
//
// ⚠ READS ONLY. No spawn, no setmodel, no state writes beyond its own map marker
//    dvar. Table lookups and isassetloaded calls only.
//
// ── HOW TO READ THE OUTPUT ────────────────────────────────────────────────────
// Retail renders NUMBERS ONLY (see ../mp_probe/scripts/mp_probe.gsc), so every
// answer is a digit. THREE LINES, printed back-to-back with no wait, via iprintln
// (the STACKING feed) rather than iprintlnbold (which replaces). One screenshot
// captures the run.
//
// Fields are FIXED WIDTH and zero-padded, so a leading zero never collapses the
// line. Read in 3-digit groups after the first digit.
//
//   1 NNN AAA BBB    N = numrows in <map>_ph.csv   ⬅ THE NUMBER
//                    A = xsmall bucket count
//                    B = small  bucket count
//
//   2 FFF CCC DDD    F = flags, see below. MUST have bit 4 CLEAR.
//                    C = medium bucket count
//                    D = large  bucket count
//
//   3 EEE            E = xlarge bucket count
//
// FLAGS (field F) are additive:
//    +1  row-0 model IS resident, form A: isassetloaded( #"xmodel", name )
//    +2  row-0 model IS resident, form B: isassetloaded(  "xmodel", name )
//    +4  ⚠ THE BOGUS CONTROL FIRED — a name no asset can have reported as loaded.
//        Non-zero here means isassetloaded is not answering the question we think
//        it is, and EVERY residency reading in this run is void.
//
// So a healthy map with a real table reads something like
//   1042005012 / 2003018004 / 3003   =  42 rows, 5 xsmall, 12 small, flags 3,
//                                       18 medium, 4 large, 3 xlarge
// and a map with no table reads
//   1000000000 / 2000000000 / 3000.
//
// ⚠ N = 0 is a REAL RESULT, not a failure: that map has no Prop Hunt table and
//    stock itself would fall back to an invisible prop. Distinguish it from a
//    broken run by field F — a broken run also fails the bogus control or reads 0
//    on both residency bits for a map that clearly has rows.
//
// ⚠ Flags bits 1 and 2 are the CALL-FORM discriminator for the asset-type argument,
//    the same open question [[vehicles]] carries. If they disagree, every future
//    isassetloaded call in the project must use the winning form.
//
// ── ONCE PER MAP, NOT ONCE PER ROUND ─────────────────────────────────────────
// callback::on_start_gametype fires EVERY ROUND (mp_probe probe 6 measured it), and
// `level` is rebuilt each round, so the marker has to live in a dvar. `gf_pprobe_map`
// holds the last map reported. ⚠ ONE PAYLOAD THEREFORE COVERS MANY MAPS — switch maps
// in-game and each reports once, cleanly, with no relink. To force a re-read of a map
// already seen, set gf_pprobe_map to anything else.
//
// ⚠ Deliberately a DIFFERENT dvar from vehicle_probe's gf_vprobe_map, so the two
//    probes can never gate each other if both are ever present.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace prop_probe;

function private autoexec __init__system__()
{
    system::register( #"prop_probe", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &on_start );
}

function private on_start()
{
    level thread report();
}

function private report()
{
    // on_start_gametype fires before players are in the match.
    wait( 8 );

    curmap = getdvarstring( #"sv_mapname", "" );

    // Empty mapname means the gate cannot work; report anyway rather than going
    // silent. A probe that quietly does nothing is the worst failure mode here.
    if ( curmap != "" )
    {
        if ( curmap == getdvarstring( #"gf_pprobe_map", "" ) )
        {
            return;
        }

        setdvar( #"gf_pprobe_map", curmap );
    }

    // Built exactly as stock builds it (prop.gsc:1852-1853). getmapname() rather
    // than the mapname dvar read above, so this matches stock's path byte for byte
    // even if the two ever diverge.
    path = "gamedata/tables/mp/" + getmapname() + "_ph.csv";
    numrows = tablelookuprowcount( path );

    if ( !isdefined( numrows ) )
    {
        numrows = 0;
    }

    // Bucket counts, keyed off column 1 exactly as stock's getpropsize does
    // (prop.gsc:2189-2205) — a SWITCH on HASHED literals. The table cell is a
    // runtime string and stock compares it against #"xsmall" etc., so that
    // comparison form is proven rather than assumed.
    xsmall = 0;
    small = 0;
    medium = 0;
    large = 0;
    xlarge = 0;

    for ( i = 0; i < numrows; i++ )
    {
        sizetext = tablelookupbyrow( path, i, 1 );

        switch ( sizetext )
        {
            case #"xsmall":
                xsmall++;
                break;
            case #"small":
                small++;
                break;
            case #"medium":
                medium++;
                break;
            case #"large":
                large++;
                break;
            case #"xlarge":
                xlarge++;
                break;
            default:
                break;
        }
    }

    // ── flags ────────────────────────────────────────────────────────────────
    // Residency of the FIRST model in the table. This single reading confirms two
    // things at once: that the runtime table read returned a usable name, and that
    // the name resolves to a resident xmodel. Reading it from the table rather than
    // from a hardcoded literal is the point — it is the map's OWN curated prop.
    flags = 0;

    if ( numrows > 0 )
    {
        firstmodel = tablelookupbyrow( path, 0, 0 );

        if ( isdefined( firstmodel ) && firstmodel != "" )
        {
            if ( isassetloaded( #"xmodel", firstmodel ) )
            {
                flags += 1;
            }

            if ( isassetloaded( "xmodel", firstmodel ) )
            {
                flags += 2;
            }
        }
    }

    // ⚠ THE CONTROL. A name no asset can have. If either form claims it is loaded,
    // isassetloaded is not answering the question we think it is and the residency
    // bits above mean nothing.
    if ( isassetloaded( #"xmodel", #"p9_gf_probe_nonexistent_prop" ) || isassetloaded( "xmodel", #"p9_gf_probe_nonexistent_prop" ) )
    {
        flags += 4;
    }

    // Three lines, no waits between them, so they land in the feed together.
    line( 1, numrows, xsmall, small );
    line( 2, flags, medium, large );

    // ⚠ Line 3 is deliberately SHORT (4 digits). See the ceiling note on line().
    emitraw( 3000 + clamp999( xlarge ) );
}

// Pack three fixed-width zero-padded fields behind a line id:  <id>AAABBBCCC.
// Fixed width is what makes a leading zero survive — a 0 in the first field must
// not collapse the line to fewer digits, or the groups misalign.
//
// ⚠⚠ SIGNED 32-BIT CEILING — an invariant for anyone editing the field order.
//    Max is 2,147,483,647. Worst cases as shipped:
//        line 1   1,999,999,999   (id 1, any fields)             always safe
//        line 2   2,007,999,999   (id 2, field A = flags, max 7) safe
//    Line 2 is the tight one: WITH ID 2, FIELD A MAY NOT EXCEED 146. That is why
//    `flags` (bounded 0-7) is field A on line 2 and never a bucket count, which is
//    unbounded in principle. **Do not reorder line 2's fields.** clamp999 protects
//    each FIELD, not the SUM, so there is no runtime guard against this.
function private line( id, a, b, c )
{
    emitraw( id * 1000000000 + clamp999( a ) * 1000000 + clamp999( b ) * 1000 + clamp999( c ) );
}

// Every field is 3 digits wide. A value that cannot fit would shift every field to
// its left and silently corrupt the line, so clamp rather than overflow — 999 is
// visibly wrong, a shifted line is not.
function private clamp999( v )
{
    if ( !isdefined( v ) )
    {
        return 999;
    }

    if ( v > 999 )
    {
        return 999;
    }

    if ( v < 0 )
    {
        return 999;
    }

    return v;
}

// iprintln, NOT iprintlnbold: the bold window holds one message and each print
// replaces the previous, so three bold lines would leave only the last on screen.
function private emitraw( value )
{
    foreach ( player in getplayers() )
    {
        player iprintln( value );
    }
}
