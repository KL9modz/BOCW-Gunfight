// ─────────────────────────────────────────────────────────────────────────────
// subtitle_probe_c — does the SUBTITLE channel take our text?
//
// Hook:    scripts\core_common\load_shared.csc      -> the MATCH client VM (the host's client)
// Replace: scripts\core_common\radiation_debug.csc  -> the pair gunfight_menu_c ran on
// Write-up: docs/notes/hud-channels.md §9. ⚠ Turn Settings -> Subtitles ON before the match.
//
// WHY: subtitleprint( localClientNum, msec, text ) is a retail CLIENT builtin (funcs_cw.csv, type 0,
// exe+2ab2460) with no stock caller in Cold War; Black Ops 3's script docs describe the same
// three-argument call as "print to the subtitle channel". Its sibling flushsubtitles( lcn ) is
// stock (scene_shared.csc:2410, :2560). Stock subtitle TEXT is always a localized key
// (scriptbundle/collectible "subtitle": "localized18#hash_…"), so the one thing to learn before
// risking free text is whether this channel prints a string RAW or localizes it - LUIelemText
// localized, and a plain string there was a FATAL LUI error (lui-elems.md).
//
// STEPS (a numbered centre line names each one):
//   1 keyname  the key NAME as a plain string, "mp/match_starting". Crash-safe either way:
//              - bottom centre reads "Match starting"      -> the channel LOCALIZES by key. Stop:
//                free text would hit the LUIelemText crash. Stock keys only.
//              - bottom centre reads "mp/match_starting"   -> the channel prints RAW text. Free
//                text is on: relaunch with gf_sub_plain 1.
//              - nothing                                   -> Subtitles setting off, or the channel
//                                                            does not draw in MP.
//   2 hold     hudItems.subtitles.noAutoHide = 1 (Campaign's dialog-tree switch,
//              cp_common/dialog_tree.gsc:777) and a 1-second line: does it outlive its 1 s?
//              Then flushsubtitles: does it clear? The model is set back to 0 afterwards.
//   gf_sub_plain 1 only (a launch you can lose - only after step 1 read RAW):
//   3 plain    "GF subtitle free text t=<ms>" - runtime-built text
//   4 styled   colour codes + a ~140-character line: colours? wrap or clip?
//   5 newline  "GF line one" + \n + "GF line two" - ONLY with gf_sub_nl 1 as well: a raw \n
//              closed the match in the hint widget (hint-panel.md)
//
// DVARS (bridge, before the match): gf_sub_delay 20 (seconds after load before step 1; 260 runs it
// after hud_probe's ~4 minutes in the same launch) · gf_sub_plain 0 · gf_sub_nl 0.
// A crash: read crash_reports/…/info.json first - a script error (sre_stack) means the builtin
// rejected the argument; a LUI Error localizeentry means the text went through the localizer.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\system_shared;

#namespace subtitle_probe_c;

function private autoexec __init__system__()
{
    system::register( #"subtitle_probe_c", &preinit, undefined, undefined, undefined );
}

function private preinit()
{
    level thread probe();
}

function private say( line )
{
    iprintlnbold( "^3GF SUB^7 " + line );
}

function private probe()
{
    delay = getdvarint( #"gf_sub_delay", 20 );
    if ( delay < 5 )
    {
        delay = 5;
    }
    wait( delay );

    lcn = 0;
    plain = getdvarint( #"gf_sub_plain", 0 );
    newline = getdvarint( #"gf_sub_nl", 0 );

    // 1 - the key NAME as a plain string: raw or localized?
    say( "1 keyname - bottom centre: 'Match starting' = localized, 'mp/match_starting' = RAW" );
    wait( 2 );
    subtitleprint( lcn, 6000, "mp/match_starting" );
    wait( 8 );

    // 2 - a line that should not auto-hide, then the stock flush
    say( "2 hold - a 1 s line with noAutoHide set: still up after 1 s?" );
    wait( 2 );
    hold = createuimodel( function_5c2e399f(), "hudItems.subtitles.noAutoHide" );
    setuimodelvalue( hold, 1 );
    subtitleprint( lcn, 1000, "mp/match_starting" );
    wait( 6 );
    say( "2 hold - flushsubtitles now: did it clear?" );
    flushsubtitles( lcn );
    wait( 3 );
    setuimodelvalue( hold, 0 );

    if ( !plain )
    {
        say( "DONE, safe steps. RAW at step 1? relaunch with gf_sub_plain 1" );
        return;
    }

    // 3 - runtime-built free text
    say( "3 plain - free text with a timestamp" );
    wait( 2 );
    subtitleprint( lcn, 6000, "GF subtitle free text t=" + gettime() );
    wait( 8 );

    // 4 - colour codes and a long line: colours? wrap or clip?
    say( "4 styled - colours, and a long line: wrap or clip?" );
    wait( 2 );
    subtitleprint( lcn, 7000, "^3yellow ^7white ^1red ^2green ^7- then a long line to find the width: 0123456789 0123456789 0123456789 0123456789 0123456789 0123456789 END" );
    wait( 9 );

    // 5 - a newline, only on request
    if ( newline )
    {
        say( "5 newline - two lines, or a closed match?" );
        wait( 2 );
        subtitleprint( lcn, 6000, "GF line one\nGF line two" );
        wait( 8 );
    }

    flushsubtitles( lcn );
    say( "DONE - fill the subtitle rows in docs/notes/hud-channels.md" );
}
