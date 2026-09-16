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
// ONE labelled feed line, re-printed every 3 s for the whole round (the debug-feed
// convention: if it is not in the screenshot it is not there). Text renders fine
// once the payload has been through tools/strip-strhdr.ps1 (toolchain.md - the old
// "numbers only" finding WAS the unstripped string header; mp_probe predates the fix).
// The line format and field meanings are documented on prop_line() below.
//
// ── EVERY ROUND, EVERY MAP ────────────────────────────────────────────────────
// callback::on_start_gametype fires EVERY ROUND (mp_probe measured it: `level` is
// rebuilt, so this thread dies at the round end and starts again). The table is per
// map, not per round, so re-reporting is harmless - and the map name is in the line,
// so a mid-match map switch is its own report. ONE PAYLOAD COVERS MANY MAPS.
// (An earlier revision gated on the `mapname` dvar, which does not exist in CW -
// lobby_state LS2 measured it - so the gate never engaged anyway.)
//
// ⚠ The same read ships inside src/vehicle_probe as its second line, so both probes
//    can run in one match. prop_line() is mirrored verbatim there - edit both.
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

    line = prop_line();

    // Computed once, shown for the whole round: the feed fades in seconds, so a
    // single print is only readable if someone is staring at it 8 s into the round.
    for ( ;; )
    {
        emit( line );
        wait( 3 );
    }
}

// ── the static-prop read (src/prop_probe) ────────────────────────────────────
// Mirrored VERBATIM between prop_probe.gsc and vehicle_probe.gsc so both probes
// read in ONE match: every injection shares the same replace target, so two
// payloads cannot coexist. Edit both or neither.
//
//   PPROBE <map> tbl=n rows=n xs=n s=n m=n l=n xl=n other=n first=<model> res=n G=n
//
//   tbl    isassetloaded( "stringtable", path ) - the guard STOCK puts in front of
//          every table read it is not sure of (scoreevents_shared.gsc:502/532/537).
//          0 = no Prop Hunt table on this map; nothing else is read. That is a REAL
//          RESULT: stock itself falls back to an invisible prop.
//   rows   numrows in gamedata/tables/mp/<map>_ph.csv (prop.gsc:1850) <- THE NUMBER
//   xs..xl the size buckets, keyed off column 1 exactly as stock getpropsize does
//          (a switch on hashed literals against the runtime cell - a proven form);
//          other = rows whose size text matched none of the five.
//   first  the model name in row 0 - the map's OWN curated prop, read at runtime.
//   res    1 if that model is a resident xmodel by isassetloaded( "xmodel", name ).
//          ⚠ Only asked when tbl=1: the model is then in the map's own curated
//          table, so it exists AND is resident - the one case run 2 left safe.
//   G      bogus-asset control, hashed, form B. MUST BE 0 or res means nothing.
function private prop_line()
{
    // Built exactly as stock builds it (prop.gsc:1852-1853). Stock's getmapname() is a
    // SCRIPT function there (prop.gsc:1825, `return level.script;`), not a builtin -
    // calling it bare from another namespace crashed the game twice (runs 2 and 3).
    mapname = level.script;

    if ( !isdefined( mapname ) )
    {
        mapname = util::get_map_name();
    }

    path = "gamedata/tables/mp/" + mapname + "_ph.csv";

    bogus = 0;

    if ( isassetloaded( "xmodel", #"p9_gf_probe_nonexistent_prop" ) )
    {
        bogus += 2;
    }

    tbl = isassetloaded( "stringtable", path ) ? 1 : 0;

    if ( !tbl )
    {
        return "^3PPROBE ^7" + getdvarstring( #"sv_mapname", "?" ) + " tbl=0 G=" + bogus;
    }

    numrows = tablelookuprowcount( path );

    if ( !isdefined( numrows ) )
    {
        numrows = 0;
    }

    xsmall = 0;
    small = 0;
    medium = 0;
    large = 0;
    xlarge = 0;
    other = 0;

    for ( i = 0; i < numrows; i++ )
    {
        sizetext = table_cell( path, i, 1 );

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
                other++;
                break;
        }
    }

    first = "-";
    res = "-";

    if ( numrows > 0 )
    {
        firstmodel = table_cell( path, 0, 0 );

        if ( isdefined( firstmodel ) && firstmodel != "" )
        {
            first = firstmodel;
            res = isassetloaded( "xmodel", firstmodel ) ? 1 : 0;
        }
    }

    return "^3PPROBE ^7" + getdvarstring( #"sv_mapname", "?" )
        + " tbl=1 rows=" + numrows + " xs=" + xsmall + " s=" + small + " m=" + medium
        + " l=" + large + " xl=" + xlarge + " other=" + other
        + " first=" + first + " res=" + res + " G=" + bogus;
}

// prop.gsc:1834 - also a SCRIPT function there, not a builtin (same trap as getmapname).
// The real builtin is tablelookuprow( table, row ), which returns the row as an array.
function private table_cell( table, row, col )
{
    columns = tablelookuprow( table, row );

    if ( isdefined( columns ) && col < columns.size )
    {
        return columns[ col ];
    }

    return "";
}

// iprintln, NOT iprintlnbold: the bold window holds one message and each print
// replaces the previous; iprintln stacks in the feed, where the mod menu prints too.
function private emit( text )
{
    foreach ( player in getplayers() )
    {
        player iprintln( text );
    }
}
