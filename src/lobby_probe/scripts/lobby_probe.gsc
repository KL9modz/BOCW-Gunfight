// ─────────────────────────────────────────────────────────────────────────────
// Lobby probe — read-only. Answers, in one match, questions this project has
// been reasoning about instead of measuring.
//
// Hook: scripts\mp_common\bb.gsc, mode=mp  (see ../gsc.conf)
//
// WHY THIS EXISTS. src/mp_probe/ reads com_maxclients and concludes the lobby's
// team size from it. But com_maxclients is one of FOUR player-count builtins in
// the Cold War binary, and this project had only ever called that one:
//
//     getdvarint(#"com_maxclients")   the configured client ceiling  (known: 8 / 12)
//     getnumexpectedplayers()         BlackOpsColdWar.exe+3b09500
//     numremoteclients()              BlackOpsColdWar.exe+3c607f0
//     getnumconnectedplayers()        BlackOpsColdWar.exe+3b09cc0
//
// If any of them disagrees with com_maxclients, the "8 slots" story is more
// complicated than one dvar - and that is exactly where 4v4 would hide.
//
// The headline probe is 9: isvalidgametype() against a list of candidate
// Gunfight strings. If a larger stock variant EXISTS as a gametype, the team
// size problem may be a string rather than a lobby-config problem.
//
// ⚠ READS ONLY. No addtestclient, no setteam, no switchmap_load. All three are
//    real state changes with real failure modes; they belong in a staged test,
//    one at a time, not bundled into a diagnostic. See docs/notes/cw-builtins.md.
//
// ── HOW TO READ THE OUTPUT ────────────────────────────────────────────────────
// PROBE_ID * 100000 + VALUE, one every 5s. Strip the leading digit.
// 99999 means undefined at read time.
//
// Emitted with the two interesting ones LAST so they are the most recent text on
// screen - mp_probe learned this the hard way: at 2s spacing klaze could read two
// values out of seven.
//
//   1xxxxx  com_maxclients            control. Expect 8 in 3v3 Gunfight, 12 in TDM
//   2xxxxx  getnumexpectedplayers()   NEW. Differs from 1? Then 1 is not the whole story
//   3xxxxx  numremoteclients()        NEW
//   4xxxxx  getnumconnectedplayers()  NEW
//   5xxxxx  flags bitmask             1 = isgametypeteambased, 2 = sessionmodeisprivate
//   6xxxxx  maxsquadplayers           <- NEW. The best candidate yet for Gunfight's 3
//   9xxxxx  GAMETYPE VALIDITY BITMASK  <- the headline. See the table at its emit site
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace lobby_probe;

function private autoexec __init__system__()
{
    system::register( #"lobby_probe", &__init__, undefined, undefined, undefined );
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

    emit( 1, getdvarint( #"com_maxclients", 0 ) );
    emit( 2, getnumexpectedplayers() );
    emit( 3, numremoteclients() );
    emit( 4, getnumconnectedplayers() );

    flags = 0;
    if ( isgametypeteambased() )
    {
        flags += 1;
    }
    if ( sessionmodeisprivate() )
    {
        flags += 2;
    }
    emit( 5, flags );

    // ── maxsquadplayers ──────────────────────────────────────────────────────
    // globallogic.gsc:230 does level.var_704bcca1 = getgametypesetting(#"hash_3a4691a853585241").
    // That hash cracks to "maxsquadplayers" - FNV1a64 & MASK63, exact 63-bit match,
    // algorithm taken from ACTS hash_mini.hpp. See docs/notes/dump-cross-check.md.
    //
    // ⚠ It is a SQUAD cap, not proven to be the team cap. team_assignment.gsc:864
    //   uses it to bound squad size inside the squad-distribution path, while the
    //   actual join gate (function_efe5a681) bounds on com_maxclients instead.
    //
    //   But for Gunfight a team IS a squad, which makes this the best candidate yet
    //   for where the 3 comes from. READING 3 HERE IN A 3v3 GUNFIGHT LOBBY WOULD BE
    //   THE STRONGEST EVIDENCE THIS PROJECT HAS FOR A SETTABLE TEAM-SIZE LEVER,
    //   because setgametypesetting() is writable at runtime and already proven to
    //   land in ~0.25s for #"timelimit".
    //
    //   Reading something else - 0, 8, undefined - says it is not the lever, and
    //   that is equally worth knowing.
    emit( 6, getgametypesetting( #"maxsquadplayers" ) );

    // ── THE HEADLINE ─────────────────────────────────────────────────────────
    // isvalidgametype( name ) - BlackOpsColdWar.exe+3b0b300, 1 arg.
    //
    // Packed as a bitmask so eight yes/no answers arrive as ONE readable number,
    // rather than eight lines that scroll past faster than they can be written
    // down.
    //
    //     bit   value   string
    //      0       1    gunfight            KNOWN GOOD - must be 1
    //      1       2    tdm                 KNOWN GOOD - must be 1
    //      2       4    gunfight_3v3        known to exist in player_record.gsc
    //      3       8    gunfight_2v2
    //      4      16    gunfight_4v4        <- if this is 1, 4v4 may be a string
    //      5      32    gunfight_5v5        <-
    //      6      64    gunfight_6v6        <-
    //      7     128    zzz_not_a_gametype  NEGATIVE CONTROL - must be 0
    //
    // ⚠⚠ READ THE CONTROLS FIRST, BEFORE ANY CONCLUSION.
    //    If bit 7 is SET (value >= 128) then isvalidgametype returns true for
    //    everything and THE WHOLE PROBE IS MEANINGLESS - discard it.
    //    If bits 0 and 1 are CLEAR then it returns false for everything, and the
    //    probe is equally meaningless.
    //    A valid reading has bits 0 and 1 set and bit 7 clear, i.e. 3..127.
    //
    //    This is the jump_height lesson from mp_dvars.md: a readout that is true
    //    and meaningless costs more than no readout at all.
    //
    // Expected if only the two known strings exist:  1 + 2 + 4 = 7
    // Anything above 7 (excluding 128) is a gametype nobody in this project knew
    // about, and is the most valuable number this probe can produce.
    mask = 0;
    if ( isvalidgametype( "gunfight" ) )           { mask += 1;   }
    if ( isvalidgametype( "tdm" ) )                { mask += 2;   }
    if ( isvalidgametype( "gunfight_3v3" ) )       { mask += 4;   }
    if ( isvalidgametype( "gunfight_2v2" ) )       { mask += 8;   }
    if ( isvalidgametype( "gunfight_4v4" ) )       { mask += 16;  }
    if ( isvalidgametype( "gunfight_5v5" ) )       { mask += 32;  }
    if ( isvalidgametype( "gunfight_6v6" ) )       { mask += 64;  }
    if ( isvalidgametype( "zzz_not_a_gametype" ) ) { mask += 128; }
    emit( 9, mask );
}

function private emit( id, value )
{
    v = 99999;
    if ( isdefined( value ) )
    {
        v = value;
    }

    tagged = id * 100000 + v;

    foreach ( player in getplayers() )
    {
        player iprintlnbold( tagged );
    }

    // 5s, not 2s. See mp_probe.gsc - at 2s the values scroll past faster than
    // they can be read and written down.
    wait( 5 );
}
