// ─────────────────────────────────────────────────────────────────────────────
// GUNFIGHT LOBBY — the lobby half of team size.
//   klaze 2026-09-24: "build maxplayers into the main mod, adjustable from the app, default
//   12 with spectators" + "make default team size for Gunfight 6v6".
//
// Hook: scripts\core_common\load_shared.gsc (every VM - the lobby AND the match)
// Replace: scripts\core_common\containers_shared.gsc  ⚠ NOT clientids_shared (see ../gsc.conf)
//
// ── WHY THIS IS NOT INSIDE gunfight_menu ─────────────────────────────────────
// The pregame lobby's client count is set by the lobby UI, not by the match.
// lui-source core_common_0025:154-167 (Lobby.PartyPrivacy.OnGametypeSettingsChange) sets it
// to maxPlayers + maxCodcasterClients (4, director_online_custom.json) when allowSpectating
// is on, and the engine launches the match with com_maxclients = min(46, that lobby number)
// (read off the live exe 2026-09-24 - docs/notes/team-sizes.md). Gunfight's preset is
// maxPlayers 4 -> 8 clients. Only a write made IN THE LOBBY reaches that store (P2/P5,
// pregame-routes.md), and gunfight_menu never runs there: it hooks bb.gsc (match VM only) and
// #uses mp_common, which the lobby does not load. So the lobby write lives here, core_common
// only, on its own replace target so both payloads stay injected together.
//
// ── WHAT IT DOES ─────────────────────────────────────────────────────────────
// In the lobby (util::is_frontend_map) and on the host only, every 2 s:
//   maxplayers      <- gf_lobby_maxp  (default 12 = 6v6; 0 = leave the lobby alone)
//   allowspectating <- 1 while gf_lobby_spec is 1 (default) - the +4 caster slots need it
// Idempotent (test_frontend's measured write_and_check): read first, write only on a
// difference, so it never races the rules menu; a mode pick reloads the preset (maxPlayers 4)
// and the next tick puts the value back. In a match VM it returns after 3 s - gunfight_menu
// owns the match (team size x 2 + spectator slots, capped at com_maxclients).
//
// ⚠ THE LOBBY RECOUNTS ITS SLOTS ONLY ON A UI SETTINGS EVENT. After the write: open Custom
//   Game Rules, change any row, back out and answer YES on "Leave Custom Game Rules". The
//   lobby's player count then reads N/16 (12 + 4). A mode pick resets it: redo that step.
// ⚠ Keep gf_lobby_maxp at 12 or below: above 12 the lobby UI greys out Add Bot and strips the
//   bots on a mode change (core_ui_1414:3493 / :3806-3815). The spectator room comes from the
//   +4, never from maxplayers.
//
// ── READBACK (the panel's GFLOBBY channel; stamped like GFSTATE) ─────────────
//   GFLOBBY|<getrealtime>|v=1|t=<ticks>|mp=<maxplayers>|as=<allowspectating>|want=<gf_lobby_maxp>
//          |spec=<gf_lobby_spec>|wm=<code>|ws=<code>|h=<host 0/1>|n=<lobby clients>|gt=<g_gametype>|END
//   codes: 0 off · 1 wrote, no readback · 2 wrote + read back · 3 wrote, readback differs
//          · 4 already correct, nothing written · 5 skipped (not the host yet)
//   "-" = undefined. The marker literal is split so the payload's own string table never
//   holds a whole "GFLOBBY|" for the memory sweep to find.
//
// ⚠ Every rule in .claude/CLAUDE.md "GSC crash rules" applies: strings stay short (one
//   ~170-char line), #using covers every namespace call, builtins only, no dvar writes.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace gunfight_lobby;

function private autoexec __init__system__()
{
    system::register( #"gunfight_lobby", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    // A plain thread: the lobby has no globallogic, so on_start_gametype never dispatches
    // there (test_frontend's measured pattern).
    level thread lobby_watch();
}

function private lobby_watch()
{
    wait( 3 );

    if ( !util::is_frontend_map() )
    {
        return;
    }

    ticks = 0;

    while ( true )
    {
        ticks++;
        lobby_tick( ticks );
        wait( 2 );
    }
}

function private lobby_tick( ticks )
{
    want = getdvarint( #"gf_lobby_maxp", 12 );
    spec = getdvarint( #"gf_lobby_spec", 1 );

    // 18 + 4 casters = 22 = the rules menu's own bound (maxClients 26 - 4 casters).
    if ( want > 18 )
    {
        want = 18;
    }

    host = lobby_is_host();
    wm = 0;
    ws = 0;

    if ( want >= 2 )
    {
        wm = 5;

        if ( host )
        {
            wm = write_and_check( #"maxplayers", want );
        }
    }

    if ( spec == 1 )
    {
        ws = 5;

        if ( host )
        {
            ws = write_and_check( #"allowspectating", 1 );
        }
    }

    body = "v=1|t=" + ticks + "|mp=" + num_or_dash( getgametypesetting( #"maxplayers" ) ) + "|as=" + num_or_dash( getgametypesetting( #"allowspectating" ) );
    body += "|want=" + want + "|spec=" + spec + "|wm=" + wm + "|ws=" + ws + "|h=" + ( host ? 1 : 0 );
    body += "|n=" + num_or_dash( getlobbyclientcount() ) + "|gt=" + getdvarstring( #"g_gametype", "" );
    level.gf_lobby_pub = "GF" + "LOBBY|" + getrealtime() + "|" + body + "|" + "END";
}

// The lobby's settings are the host's to change. P1 measured a local player answering
// ishost() in the frontend (flags 32); with nobody seated yet this waits for the next tick.
function private lobby_is_host()
{
    foreach ( player in getplayers() )
    {
        if ( player ishost() )
        {
            return true;
        }
    }

    return false;
}

// test_frontend's write_and_check, unchanged in behaviour: returns 4 when the store already
// holds the value (nothing written), else writes and reads back (2 matched / 3 differs /
// 1 undefined).
function private write_and_check( key, value )
{
    before = getgametypesetting( key );

    if ( isdefined( before ) && before == value )
    {
        return 4;
    }

    setgametypesetting( key, value );
    readback = getgametypesetting( key );

    if ( !isdefined( readback ) )
    {
        return 1;
    }

    if ( readback == value )
    {
        return 2;
    }

    return 3;
}

function private num_or_dash( v )
{
    if ( !isdefined( v ) )
    {
        return "-";
    }

    return "" + v;
}
