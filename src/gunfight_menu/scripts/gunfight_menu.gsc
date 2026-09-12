// ─────────────────────────────────────────────────────────────────────────────
// GUNFIGHT HOST MENU — the in-match control surface. Roadmap Goal A, item A1.
//
// Hook: scripts\mp_common\bb.gsc, mode=mp  (see ../gsc.conf)
//
// ── WHAT THIS IS ─────────────────────────────────────────────────────────────
// gunfight_mod (all four fixes + team size, verified in-game) PLUS a mod menu on
// top, in ONE payload. B9 measured that a payload cannot be hot-swapped under a
// live one, so the host cannot inject the mod and then the menu: whatever the
// host needs must be in the file that gets injected once per game launch.
// gunfight_mod.gsc is untouched and remains the no-menu variant.
//
// ── WHERE THE MENU ENGINE COMES FROM, AND WHY IT IS REWRITTEN NOT COPIED ─────
// The engine is a translation of ate47/t8-atian-menu's coldwar/scripts/core_common/
// {menu,keymanager}.gsc - the same menu klaze already drives for the map carry, so
// every key and every screen behaves the way he already knows.
//
// ⚠ It could NOT be copied. The Atian Menu is built with shiversoftdev's
//   debugcompiler in #include / bare `autoexec` / #ifdef dialect - the exact dialect
//   this project's history records as crashing the game at script link under ACTS
//   (hello_world, 2026-09-07). This file is ACTS dialect throughout: #using,
//   `function` on every definition, `function private autoexec`, system::register
//   with five args and a hashed name, no preprocessor, one file.
//
// ── WHERE SETTINGS LIVE, AND WHY IT IS DVARS ─────────────────────────────────
// `level` is torn down every round (measured, mp_probe) - gunfight_mod re-creates
// its config from defaults on each on_start_gametype for exactly that reason. A
// menu that wrote into level.* would silently revert at every round boundary.
// `game.` survives rounds but resets at match end. A DVAR survives both: B4
// measured one carried across a map_restart. So every host setting is a dvar
// with a default, and mod_apply() reads them fresh every round:
//
//     gf_team_size      per side, default 4
//     gf_timer_seconds  default 60
//     gf_loadout        0 default / 1 snipers / 2 blueprints / 3 melee
//     gf_spyplane       0 off / 1 on / 3 shared (the value the menu hides)
//     gf_map_method     1 session (switchmap_load - the lobby FOLLOWS, verified 2026-09-12, default)
//                       0 carry   (map() - the Atian load-time override; lobby stays stale. fallback)
//     gf_spawn_guard    0 off (default) / 1 on - reposition to central real spawns (untested)
//     gf_spawn_diag     1 on (default) - emit 60=armed(N) / 61=inert via iprintlnbold
//     gf_roundwinlimit  -1 leave stock (default) / N first-to-N rounds
//     gf_roundlimit     -1 leave stock (default) / N round cap
//     gf_rounds_loadout -1 leave stock (default) / N rounds per loadout rotation
//     gf_menu_lines     visible item rows in the panel window, default 7 (was 2)
//     gf_menu_region    0 lower-left feed (default) / 1 center screen - which text
//                       region holds the PANEL; toasts go to the other one. Flip it
//                       in-game if one region clips the panel on this build.
//     gf_feed_lines     how many lines the lower-left feed shows at once, default 14.
//                       This is the stock dvar com_gameMsgWindow1LineCount (ships at
//                       ~4-5) - the feed capped the panel until we raised it. Host-
//                       local, so joiners are unaffected. Lower it if the feed spills
//                       into other HUD; 0 leaves the stock value alone.
//
// Set once, they hold until the game is restarted - at which point the payload
// has to be re-injected anyway.
//
// ── KEYS (identical to the shipped Atian Menu) ───────────────────────────────
//     open    ADS + melee     (RMB + V)
//     back    melee           (V)
//     up      ADS             (RMB)
//     down    attack          (LMB)
//     select  reload          (R)
//
// ── WHAT IS PROVEN AND WHAT IS NOT ───────────────────────────────────────────
//     zones_guard / timelimit_fix / presentation / timer_override   ✅ in-game
//     team size via maxplayers                                        ✅ L6 4v4; 6v6 filled 2026-09-12 (bots, 12-slot session)
//     bot fill via bot::add_bot                                       ✅ C7
//     map_restart()                                                   ✅ B4
//     map carry via map() + switchmap_switch()                        ✅ the Atian carry (load-time only)
//     move a player via [[ level.autoassign ]]                        ⚠ C11 built, never run
//     loadout set via gunfightloadoutindex                            ⚠ B6 never run
//     spy plane value 3                                               ⚠ B7 never run
//     #spawn_guard central real-spawn reposition                      ⚠ NEVER ACTUALLY RAN before 2026-09-12:
//                                                                       its targetnames were garbled by the ACTS
//                                                                       string header, so it gathered 0 and no-op'd
//                                                                       (probe 61). First real test is still ahead.
//     gametype switch via switchmap_load( map, gametype )             ⚠ built 2026-09-12, untested. mod_apply is
//                                                                       gated on gunfight/gunfight_3v3 for it
//     match limits roundwinlimit/roundlimit/roundsperloadout          ✅ keys verified in source
//     move/spectate guard level.autoassign / level.spectator          ✅ hardened
//     map via switchmap_load( map, gametype )                         ✅ 2026-09-12: the SESSION moves.
//                                                                       lobby-route restart reloaded Zoo,
//                                                                       com_maxclients read 12. Needs the
//                                                                       string-header strip (tools/) or the
//                                                                       map name reaches the engine garbled -
//                                                                       which is why bbf94f9 called it inert.
//                                                                       docs/notes/session-switch.md
//
// ⚠ ONE CONTRADICTION THIS FILE HAD TO ROUTE AROUND. A4 diagnosed its map-switch
//   failure as `level endon( #"game_ended" )` killing the thread inside wait(1).
//   But the shipped Atian Menu's menu_think carries the SAME endon, its map action
//   runs INSIDE that thread with the same wait(1), and it works - klaze uses it.
//   So the endon cannot be the whole story. Rather than pick a theory, every map
//   switch here is threaded off onto the PLAYER with no endons at all, which
//   satisfies both the endon theory and A4 run 4's self=player theory at once.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\array_shared;
#using scripts\core_common\callbacks_shared;
#using scripts\core_common\clientfield_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;
#using scripts\core_common\struct;
#using scripts\core_common\music_shared;
#using scripts\core_common\bots\bot;
// globallogic, NOT gunfight: the menu links into TDM/etc. for the gametype switch, and
// gunfight.gsc is ABSENT from a non-Gunfight match's link set - a gunfight:: import there
// is a fatal link error ("error loading match", 2026-09-12). globallogic loads in every
// MP match, and it carries the round-end the health decision needs. See mod_ontimelimit.
#using scripts\mp_common\gametypes\globallogic;

#namespace gunfight_menu;

function private autoexec __init__system__()
{
    system::register( #"gunfight_menu", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &mod_apply );
    callback::on_connect( &on_player_connect );
    callback::on_spawned( &mod_spawn_place );
}

// ═════════════════════════════════════════════════════════════════════════════
// SETTINGS — dvar-backed, so they survive rounds and matches
// ═════════════════════════════════════════════════════════════════════════════

function private cfg_team_size()     { return getdvarint( #"gf_team_size", 4 ); }
function private cfg_timer_seconds() { return getdvarint( #"gf_timer_seconds", 60 ); }
function private cfg_loadout()       { return getdvarint( #"gf_loadout", 0 ); }
function private cfg_spyplane()      { return getdvarint( #"gf_spyplane", 0 ); }
function private cfg_map_method()    { return getdvarint( #"gf_map_method", 1 ); }
function private cfg_menu_lines()    { return getdvarint( #"gf_menu_lines", 3 ); }
function private cfg_menu_region()   { return getdvarint( #"gf_menu_region", 0 ); }
function private cfg_feed_lines()    { return getdvarint( #"gf_feed_lines", 14 ); }

// #spawn_guard (ported from gunfight_mod, adapted to dvars). Default OFF - test solo first.
function private cfg_spawn_guard()   { return getdvarint( #"gf_spawn_guard", 0 ); }
function private cfg_spawn_diag()    { return getdvarint( #"gf_spawn_diag", 1 ); }

// Match-length knobs. Sentinel -1 = leave the lobby's value untouched (only an explicit
// menu pick asserts control). Keys verified against gunfight.gsc / globallogic.gsc.
function private cfg_roundwinlimit()  { return getdvarint( #"gf_roundwinlimit", -1 ); }
function private cfg_roundlimit()     { return getdvarint( #"gf_roundlimit", -1 ); }
function private cfg_rounds_loadout() { return getdvarint( #"gf_rounds_loadout", -1 ); }

// Movement. bg_gravity is engine-consumed in MP (docs/notes/mp-dvars.md, verified
// 2026-09-07; stock 800). Jump uses the setjumpheight BUILTIN - the jump_height DVAR
// is a campaign/ZM dead end in MP - and -1 leaves the engine default untouched.
function private cfg_gravity()  { return getdvarint( #"gf_gravity", 800 ); }
function private cfg_jump()     { return getdvarint( #"gf_jump", -1 ); }

// Never ask the session for more clients than it has slots for. com_maxclients is
// read-only from script but READABLE - 10 in a 3v3 lobby, 8 in a normal one - so the
// bound is measured live rather than assumed. Copied from gunfight_mod.
function private clamp_team_size( per_side )
{
    budget = getdvarint( #"com_maxclients", 0 );

    if ( budget <= 0 )
    {
        return per_side;
    }

    ceiling = int( budget / 2 );

    if ( per_side > ceiling )
    {
        return ceiling;
    }

    return per_side;
}

// ═════════════════════════════════════════════════════════════════════════════
// THE MOD — gunfight_mod's verified fixes, applied every on_start_gametype
// ═════════════════════════════════════════════════════════════════════════════

// The menu can now switch GAMETYPE, so it gets linked into TDM/DM/etc. matches too.
// Everything below the gate is Gunfight's and would wreck another mode: ontimelimit
// becomes the health decision, gettimelimit clamps the match to the Gunfight timer,
// the HUD latch says "no respawns left". Only the menu itself runs everywhere.
function private mod_is_gunfight()
{
    gt = tolower( getdvarstring( #"g_gametype", "" ) );
    return gt == "gunfight" || gt == "gunfight_3v3";
}

function private mod_apply()
{
    // Movement mods apply in EVERY gametype, so they run before the Gunfight gate.
    mod_movement();

    if ( !mod_is_gunfight() )
    {
        mod_menu_restart_all();
        return;
    }

    // ✅ Necessary, not defensive: level.zones is assigned only on setupzones()'s
    // success path (gunfight.gsc:907) and stays undefined for the whole match on
    // every custom-lobby map, stock ones included.
    if ( !isdefined( level.zones ) )
    {
        level.zones = [];
    }

    // THE load-bearing fix: reach the health decision without the overtime() thread
    // that dereferences level.zones[0] and dies.
    level.ontimelimit = &mod_ontimelimit;

    // Round timer. gettimelimit() returns MINUTES, range [0, 1440]; a carry resets the
    // rules-menu value, and this re-applying per round is what makes it stick.
    level.gettimelimit = &mod_gettimelimit;

    // Team size. maxplayers = 2 x per side; L6 measured it survives the round boundary,
    // so this is belt-and-braces against the CARRY, which re-initialises settings.
    setgametypesetting( #"maxplayers", clamp_team_size( cfg_team_size() ) * 2 );

    // Loadout set and spy plane - written every round from the dvars. Harmless when
    // unchanged. The loadout LATCH (game.var_96a8ff4a) is cleared only by the menu
    // action, once, so a change takes effect next round without re-randomising every
    // round.
    setgametypesetting( #"gunfightloadoutindex", cfg_loadout() );
    setgametypesetting( #"gunfightspyplane", cfg_spyplane() );

    // Match-length knobs - sentinel -1 leaves the lobby value alone. Re-applied every round
    // like the timer/team so a menu pick self-heals across the round boundary and a carry.
    if ( cfg_roundwinlimit() >= 0 )
        setgametypesetting( #"roundwinlimit", cfg_roundwinlimit() );
    if ( cfg_roundlimit() >= 0 )
        setgametypesetting( #"roundlimit", cfg_roundlimit() );
    if ( cfg_rounds_loadout() >= 0 )
        setgametypesetting( #"gunfightroundsperloadout", cfg_rounds_loadout() );

    mod_presentation_fixups();

    // #spawn_guard: rebuild the central-spawn anchors each round (level is torn down per
    // round). No-op inside unless the flag is on; the on_spawned handler reads the result.
    if ( cfg_spawn_guard() )
        mod_spawn_build();

    mod_menu_restart_all();
}

// Belt and braces for the menu across round boundaries: the Atian Menu's own
// loop survives rounds in klaze's hands (game_ended fires once, at match end -
// globallogic.gsc:2374), but level is rebuilt per round and this costs nothing.
// menu_think endons on gfmenu_restart, so an old loop dies before a new one runs.
function private mod_menu_restart_all()
{
    foreach ( player in getplayers() )
    {
        if ( player ishost() && isdefined( player.gfmenu ) )
        {
            player thread menu_restart();
        }
    }
}

// The health decision, reached WITHOUT importing gunfight.gsc. mod_apply installs this
// only in a Gunfight match, but the menu now also links into TDM for the gametype switch,
// where a gunfight:: import is a fatal link error. globallogic::function_a3e3bd39 is
// exactly what gunfight::endround threaded (score + round::set_winner + end_round), and
// globallogic loads in every MP match. Overtime is dropped on purpose: it is the crashing
// path this fix exists to avoid (level.zones[0] on an undefined array), and the design
// skips it regardless of this (docs/notes/gunfight-findings.md - "overtime is absent, and
// that is correct").
// bg_gravity: verified engine-consumed in MP. setjumpheight: a real builtin, distinct
// from the dead jump_height dvar - UNTESTED here, so it only fires when the host picks
// a value (sentinel -1 = leave the engine default). Both re-asserted each round so a
// menu pick self-heals across the round boundary and a map switch.
function private mod_movement()
{
    setdvar( #"bg_gravity", cfg_gravity() );

    if ( cfg_jump() >= 0 )
        setjumpheight( cfg_jump() );
}

function private mod_ontimelimit()
{
    // One-shot. checktimelimit() re-invokes level.ontimelimit every 0.25s while the timer
    // reads expired; gunfight's re-entrancy latch lived in gunfight::endround, which we no
    // longer call, so own it here. level is rebuilt per round, so this resets each round.
    if ( isdefined( level.gfmenu_round_ended ) && level.gfmenu_round_ended )
        return;
    level.gfmenu_round_ended = 1;

    allies_health = 0;
    foreach ( p in getplayers( #"allies" ) )
        allies_health += p.health;

    axis_health = 0;
    foreach ( p in getplayers( #"axis" ) )
        axis_health += p.health;

    if ( allies_health > axis_health )
        globallogic::function_a3e3bd39( #"allies", 1 );
    else if ( axis_health > allies_health )
        globallogic::function_a3e3bd39( #"axis", 1 );
    else
        thread globallogic::end_round( 2 );
}

function private mod_gettimelimit()
{
    // seconds -> minutes, fractional is fine: the DDL field is fixed<8,2>.
    return cfg_timer_seconds() / 60;
}

function private mod_presentation_fixups()
{
    if ( !util::isfirstround() )
    {
        music::setmusicstate( "gunfight_roundstart" );
    }

    if ( isdefined( level.teams ) )
    {
        foreach ( team, _ in level.teams )
        {
            level.var_a236b703[ team ] = 1;
            level.var_61952d8b[ team ] = 1;
        }
    }

    thread mod_norespawns_hud();
    luinotifyevent( #"round_start" );
}

function private mod_norespawns_hud()
{
    waitframe( 1 );
    clientfield::set_world_uimodel( "hudItems.team1.noRespawnsLeft", 1 );
    clientfield::set_world_uimodel( "hudItems.team2.noRespawnsLeft", 1 );
}

// ═════════════════════════════════════════════════════════════════════════════
// SPAWN GUARD — ported from gunfight_mod (game-systems sec 16b), dvar-driven here.
// Fixes combined-arms/large-variant OOB / odd spawns by repositioning each player
// onto a CENTRAL, real spawn struct for their team. Only ever uses EXISTING structs,
// so every destination is designer-placed and mesh-valid. Fails safe (< 2 points =>
// no-op, stock spawns stand). ⚠ UNTESTED — validate SOLO first (watch where you spawn).
// ═════════════════════════════════════════════════════════════════════════════

function private mod_spawn_build()
{
    pts = mod_gather_spawns();

    if ( !isdefined( pts ) || pts.size < 2 )
    {
        level.gfmenu_spawn = undefined;
        if ( cfg_spawn_diag() )
            mod_gf_emit( 61, isdefined( pts ) ? pts.size : 0 );   // inert: too few points
        return;
    }

    center = mod_centroid( pts );

    // Enough central points that each side gets one PER PLAYER with a few spare -
    // at 6v6 the old fixed 12 left ~6 a side and the random pick below then doubled
    // players up on the same struct.
    k = cfg_team_size() * 2 + 4;
    if ( k < 12 )
        k = 12;
    central = mod_nearest_k( pts, center, k );   // the most central real spawn structs

    // Split the central cluster into two sides along whichever axis the cluster is
    // longer on, so the teams are separated but close. Always-X put both teams in one
    // pile on maps whose central corridor runs north-south.
    ax = mod_spread_axis( central );
    med = mod_median_axis( central, ax );
    team1 = [];
    team2 = [];
    foreach ( p in central )
    {
        if ( mod_coord( p, ax ) <= med )
            team1[ team1.size ] = p;
        else
            team2[ team2.size ] = p;
    }
    if ( team1.size == 0 )
        team1 = central;
    if ( team2.size == 0 )
        team2 = central;

    // Shuffled once per round; mod_spawn_place hands them out in order so no two
    // players of a side land on the same struct (a telefrag at worst, a pile at best).
    level.gfmenu_spawn = { #team1:mod_shuffle( team1 ), #team2:mod_shuffle( team2 ), #next1:0, #next2:0 };

    if ( cfg_spawn_diag() )
        mod_gf_emit( 60, pts.size );   // armed, N spawn points gathered
}

// Fires on every spawn (registered in __init__). No-op unless the flag is on and anchors
// were built this round. Repositions the player onto a central spawn for their team.
function private mod_spawn_place()
{
    // Host player tools that need re-asserting each spawn (both reset on respawn).
    if ( isdefined( self.gf_god ) && self.gf_god )
        self enableinvulnerability();
    if ( isdefined( self.gf_tp ) && self.gf_tp )
        self setclientthirdperson( 1 );

    if ( !cfg_spawn_guard() )
        return;

    if ( !isdefined( level.gfmenu_spawn ) )
        return;

    if ( !isplayer( self ) || !isdefined( self.team ) )
        return;

    // Round-robin through the side's shuffled list: distinct struct per player.
    if ( self.team == #"axis" )
    {
        list = level.gfmenu_spawn.team2;
        idx = level.gfmenu_spawn.next2;
        level.gfmenu_spawn.next2 = idx + 1;
        side = "team2";
    }
    else
    {
        list = level.gfmenu_spawn.team1;
        idx = level.gfmenu_spawn.next1;
        level.gfmenu_spawn.next1 = idx + 1;
        side = "team1";
    }

    if ( !isdefined( list ) || list.size == 0 )
        return;

    slot = idx % list.size;
    pt = list[ slot ];

    if ( !isdefined( pt ) || !isdefined( pt.origin ) )
        return;

    self setorigin( pt.origin );

    if ( isdefined( pt.angles ) )
        self setplayerangles( pt.angles );

    // Per-player receipt, so "odd spawn" reports can say whether the guard placed them.
    if ( cfg_spawn_diag() )
        self iprintln( "spawn guard: " + side + " anchor " + slot + "/" + list.size );
}

// Fisher-Yates on a copy.
function private mod_shuffle( arr )
{
    out = [];
    foreach ( p in arr )
        out[ out.size ] = p;

    for ( i = out.size - 1; i > 0; i-- )
    {
        j = randomint( i + 1 );
        t = out[ i ];
        out[ i ] = out[ j ];
        out[ j ] = t;
    }

    return out;
}

// 0 = X, 1 = Y: whichever the cluster spans more of.
function private mod_spread_axis( pts )
{
    minx = pts[ 0 ].origin[ 0 ]; maxx = minx;
    miny = pts[ 0 ].origin[ 1 ]; maxy = miny;

    foreach ( p in pts )
    {
        if ( p.origin[ 0 ] < minx ) minx = p.origin[ 0 ];
        if ( p.origin[ 0 ] > maxx ) maxx = p.origin[ 0 ];
        if ( p.origin[ 1 ] < miny ) miny = p.origin[ 1 ];
        if ( p.origin[ 1 ] > maxy ) maxy = p.origin[ 1 ];
    }

    return ( ( maxy - miny ) > ( maxx - minx ) ) ? 1 : 0;
}

// []-construction, NOT bare array(): keys_init above documents why array() is a link-time
// risk in this file (zero precedent in stock MP scripts). Same rule applies here.
function private mod_gather_spawns()
{
    pts = [];

    foreach ( n in mod_spawn_families() )
    {
        arr = struct::get_array( n, "targetname" );

        if ( isdefined( arr ) )
        {
            foreach ( s in arr )
            {
                if ( isdefined( s ) && isdefined( s.origin ) )
                    pts[ pts.size ] = s;
            }
        }
    }

    return pts;
}

// ⚠ These are string literals handed to the engine. Every build before 2026-09-12 shipped
// them with the ACTS string header the engine reads as "encrypted" (tools/strip-strhdr.ps1),
// so get_array matched NOTHING and the guard no-op'd with probe 61 every time - which is
// what sent the desktop hunting for a "missing family". The families were never the miss.
function private mod_spawn_families()
{
    names = [];

    // GENERIC map spawns - the most common targetname family in the source, and what the
    // maps that "don't use tdm spawns" actually place: mp_cartel / mp_slums_rm /
    // mp_village_rm / mp_miami_strike all move_spawn_point() these. This is the set the
    // first pass was missing, so it gathered <2 and no-oped. The game's own
    // function_d400d613 reads them with the same struct::get_array( name, "targetname" ).
    names[ names.size ] = "mp_spawn_point";
    names[ names.size ] = "mp_spawn_point_allies";
    names[ names.size ] = "mp_spawn_point_axis";

    // DM / FFA and TDM.
    names[ names.size ] = "mp_dm_spawn";
    names[ names.size ] = "mp_tdm_spawn";
    names[ names.size ] = "mp_tdm_spawn_allies_start";
    names[ names.size ] = "mp_tdm_spawn_axis_start";
    names[ names.size ] = "mp_tdm_spawn_team1_start";
    names[ names.size ] = "mp_tdm_spawn_team2_start";

    // Combined Arms / Team War - the large-format layout that leaves you OOB in the first
    // place. Gather them too; mod_nearest_k still extracts the central cluster from them,
    // which is exactly what a small mode needs.
    names[ names.size ] = "mp_twar_spawn";
    names[ names.size ] = "mp_twar_spawn_allies_start";
    names[ names.size ] = "mp_twar_spawn_axis_start";

    return names;
}

// Spawns -> "Spawn report": what this map actually places, and what the guard built from
// it. Three lines a page so it can be read. Zero counts are skipped.
function private spawn_report()
{
    self endon( #"disconnect" );

    n = 0;
    foreach ( name in mod_spawn_families() )
    {
        arr = struct::get_array( name, "targetname" );

        if ( !isdefined( arr ) || arr.size == 0 )
            continue;

        self iprintln( name + " = " + arr.size );
        n++;

        if ( n % 3 == 0 )
            wait( 4 );
    }

    if ( n == 0 )
        self iprintln( "^1no spawn structs found by any known targetname" );

    if ( isdefined( level.gfmenu_spawn ) )
    {
        c1 = mod_centroid( level.gfmenu_spawn.team1 );
        c2 = mod_centroid( level.gfmenu_spawn.team2 );
        sep = int( sqrt( mod_dist2d_sq( c1, c2 ) ) );
        self iprintln( "guard armed: " + level.gfmenu_spawn.team1.size + " + " + level.gfmenu_spawn.team2.size + " anchors, sides " + sep + " apart" );
    }
    else
    {
        self iprintln( "guard not armed this round (" + ( cfg_spawn_guard() ? "too few points" : "switched off" ) + ")" );
    }
}

function private mod_centroid( pts )
{
    sum = ( 0, 0, 0 );

    foreach ( p in pts )
        sum += p.origin;

    return sum / pts.size;
}

function private mod_nearest_k( pts, center, k )
{
    scored = [];

    foreach ( p in pts )
        scored[ scored.size ] = { #pt:p, #d:mod_dist2d_sq( p.origin, center ) };

    for ( i = 0; i < scored.size; i++ )
    {
        for ( j = i + 1; j < scored.size; j++ )
        {
            if ( scored[ j ].d < scored[ i ].d )
            {
                tmp = scored[ i ];
                scored[ i ] = scored[ j ];
                scored[ j ] = tmp;
            }
        }
    }

    out = [];
    n = ( scored.size < k ) ? scored.size : k;

    for ( i = 0; i < n; i++ )
        out[ out.size ] = scored[ i ].pt;

    return out;
}

// Vector components by CONSTANT index only - a variable index into a vector has no
// stock precedent, and this file does not gamble links.
function private mod_coord( p, ax )
{
    if ( ax == 1 )
        return p.origin[ 1 ];

    return p.origin[ 0 ];
}

function private mod_median_axis( pts, ax )
{
    xs = [];

    foreach ( p in pts )
        xs[ xs.size ] = mod_coord( p, ax );

    for ( i = 0; i < xs.size; i++ )
    {
        for ( j = i + 1; j < xs.size; j++ )
        {
            if ( xs[ j ] < xs[ i ] )
            {
                t = xs[ i ];
                xs[ i ] = xs[ j ];
                xs[ j ] = t;
            }
        }
    }

    return xs[ int( xs.size / 2 ) ];
}

function private mod_dist2d_sq( a, b )
{
    dx = a[ 0 ] - b[ 0 ];
    dy = a[ 1 ] - b[ 1 ];
    return dx * dx + dy * dy;
}

function private mod_gf_emit( id, value )
{
    foreach ( player in getplayers() )
        player iprintlnbold( id * 100000 + value );
}

// ═════════════════════════════════════════════════════════════════════════════
// MENU BOOTSTRAP — host only, on connect (the Atian Menu's proven entry point)
// ═════════════════════════════════════════════════════════════════════════════

function private on_player_connect()
{
    self endon( #"disconnect" );

    if ( !self ishost() )
    {
        return;
    }

    if ( isdefined( self.gfmenu ) )
    {
        return;
    }

    self menu_init( "Gunfight Host" );
    self keys_init();
    self build_tree();

    self thread menu_think();
    self thread cmd_poll();
}

// ═════════════════════════════════════════════════════════════════════════════
// COMMAND POLLER — lets the Windows control app (tools/gf-control) drive actions
// ═════════════════════════════════════════════════════════════════════════════
// The app writes CONFIG dvars (gf_team_size, gf_timer_seconds, ...) which mod_apply
// already re-reads every round - those need nothing here. ACTIONS (map/gametype
// switch, bots, restart) are one-shots, so the app stages them as gf_cmd_* dvars and
// raises gf_cmd_go; this poller runs the operation host-side and clears the flag.
// Runs on the host player (started in on_player_connect), endon disconnect so it
// survives the round boundary (game_ended is match-end, not per round).
function private cmd_poll()
{
    self endon( #"disconnect" );

    for ( ;; )
    {
        if ( getdvarint( #"gf_cmd_go", 0 ) == 1 )
        {
            setdvar( #"gf_cmd_go", 0 );   // clear FIRST so a slow action cannot re-fire
            self cmd_dispatch();
        }

        wait( 0.25 );
    }
}

// One command per gf_cmd_go pulse. Bots/restart take priority; otherwise a map and/or
// gametype present means a SESSION switch (the app's proper path - the map() carry
// cannot carry a gametype). Each trigger is cleared as it is consumed.
function private cmd_dispatch()
{
    if ( getdvarint( #"gf_cmd_fillbots", 0 ) )
    {
        setdvar( #"gf_cmd_fillbots", 0 );
        self thread fill_bots();
        return;
    }

    if ( getdvarint( #"gf_cmd_removebots", 0 ) )
    {
        setdvar( #"gf_cmd_removebots", 0 );
        bot::remove_bots( #"allies" );
        bot::remove_bots( #"axis" );
        self menu_say( "^2app: bots removed" );
        return;
    }

    if ( getdvarint( #"gf_cmd_restart", 0 ) )
    {
        setdvar( #"gf_cmd_restart", 0 );
        self menu_say( "^3app: restarting..." );
        map_restart();
        return;
    }

    map = tolower( getdvarstring( #"gf_cmd_map", "" ) );
    gt  = tolower( getdvarstring( #"gf_cmd_gametype", "" ) );

    if ( map == "" && gt == "" )
    {
        return;
    }

    setdvar( #"gf_cmd_map", "" );
    setdvar( #"gf_cmd_gametype", "" );

    if ( map == "" )
    {
        map = tolower( getdvarstring( #"sv_mapname", "" ) );
    }

    if ( gt == "" )
    {
        gt = tolower( getdvarstring( #"g_gametype", "" ) );
    }

    // Same guard the in-game gametype action uses: refuse a name the engine rejects
    // rather than hand switchmap_load a bad gametype and find out live.
    if ( !isvalidgametype( gt ) )
    {
        self menu_say( "^1app: engine rejects gametype " + gt );
        return;
    }

    self menu_say( "^3app: switching to " + map + " / " + gt + "..." );
    self thread do_session_switch( map, gt );
}

function private menu_restart()
{
    self notify( #"gfmenu_restart" );
    waitframe( 1 );
    self thread menu_think();
}

// ═════════════════════════════════════════════════════════════════════════════
// MENU ENGINE — translated from t8-atian-menu menu.gsc
// ═════════════════════════════════════════════════════════════════════════════

function private menu_init( title )
{
    self.gfmenu = {
        #current: "",
        #menus: []
    };

    self menu_add( "start_menu", title, "" );
}

// BOCW gives a host-only SERVER script exactly two text regions, and no more: the
// lower-left notification feed (iprintln) and the center of the screen (iprintlnbold).
// Both take ^N colors and both FADE, which is why menu_think repaints. The live PANEL
// goes to one region; transient confirmations ("toasts") go to the OTHER, so a
// confirmation never scribbles across the panel. gf_menu_region flips which is which -
// the two regions cap visible line counts differently and only an in-game look tells
// you which one shows the whole panel cleanly on a given build.
// The lower-left feed shows only com_gameMsgWindow1LineCount lines at once (~4-5
// stock), which clipped the panel to its last few rows. Raising it grows the feed on
// the HOST's own client only - it is a com_ display dvar the local HUD reads, not a
// replicated gametype setting, so joiners keep their stock feed. Re-applied on every
// repaint because it costs nothing and self-heals if anything resets it. 0 = leave
// the stock value untouched.
function private menu_feed_height()
{
    n = cfg_feed_lines();

    if ( n <= 0 )
        return;

    // iprintln might feed a different window index than the cfg's #1; set them all.
    setdvar( #"com_gameMsgWindow0LineCount", n );
    setdvar( #"com_gameMsgWindow1LineCount", n );
    setdvar( #"com_gameMsgWindow2LineCount", n );
    setdvar( #"com_gameMsgWindow3LineCount", n );
}

function private menu_paint( txt )
{
    if ( cfg_menu_region() == 1 )
        self iprintlnbold( txt );
    else
        self iprintln( txt );
}

function private menu_toast( txt )
{
    if ( cfg_menu_region() == 1 )
        self iprintln( txt );
    else
        self iprintlnbold( txt );
}

// The names the rest of the file already calls. menu_draw = the panel region,
// menu_say = the toast (opposite) region.
function private menu_draw( txt ) { self menu_paint( txt ); }
function private menu_say( txt )  { self menu_toast( txt ); }

// A page. create_switch = 1 also adds an item in the parent that opens it.
// enter_func, if given, runs with (menu) every time the page is entered - the
// Players page uses it to rebuild itself from getplayers().
function private menu_add( id, name, parent_id, create_switch = 0, enter_func = undefined )
{
    menu = {
        #id: id,
        #cursor: 0,
        #name: name,
        #parent_id: parent_id,
        #enter_func: enter_func,
        #items: []
    };

    self.gfmenu.menus[ id ] = menu;

    if ( create_switch )
    {
        self menu_item( parent_id, name, &menu_switch, id );
    }

    return menu;
}

// An item. action is called as  self [[ action ]]( item, data1, data2 ).
// Return false from an action to close the menu; anything else keeps it open.
function private menu_item( menu_id, name, action, data1 = undefined, data2 = undefined, group = undefined, gval = undefined )
{
    if ( !isdefined( self.gfmenu.menus[ menu_id ] ) )
    {
        self menu_say( "^1menu bug: no page " + menu_id );
        return undefined;
    }

    item = {
        #name: name,
        #action: action,
        #activated: 0,
        #data1: data1,
        #data2: data2,
        #group: group,   // dvar this choice writes (for the live "current" marker)
        #gval: gval       // the value this choice represents
    };

    // Bind the &array param to a struct FIELD the way the Atian source does
    // (array::add( parent.sub_menus, item )), not to a nested index expression.
    parent = self.gfmenu.menus[ menu_id ];
    array::add( parent.items, item );
    return item;
}

function private menu_clear_items( menu_id )
{
    if ( isdefined( self.gfmenu.menus[ menu_id ] ) )
    {
        self.gfmenu.menus[ menu_id ].items = [];
        self.gfmenu.menus[ menu_id ].cursor = 0;
    }
}

function private menu_switch( item, menu_id )
{
    if ( !isdefined( menu_id ) )
    {
        menu_id = "";
    }

    self.gfmenu.current = menu_id;
    menu = self.gfmenu.menus[ menu_id ];

    if ( isdefined( menu ) )
    {
        menu.cursor = 0;

        if ( isdefined( menu.enter_func ) )
        {
            self [[ menu.enter_func ]]( menu );
        }
    }

    return true;
}

function private menu_current()
{
    return self.gfmenu.menus[ self.gfmenu.current ];
}

function private menu_run_item( item )
{
    if ( !isdefined( item.action ) )
    {
        return true;
    }

    if ( isdefined( item.data2 ) )
    {
        return self [[ item.action ]]( item, item.data1, item.data2 );
    }

    if ( isdefined( item.data1 ) )
    {
        return self [[ item.action ]]( item, item.data1 );
    }

    return self [[ item.action ]]( item );
}

function private menu_think()
{
    self endon( #"disconnect" );
    self endon( #"gfmenu_restart" );
    level endon( #"game_ended" );

    lines = cfg_menu_lines();

    // Panel is 1 header + <lines> item rows. Prime the region with that many blanks
    // so the first real paint lands as a stable block. Kept small on purpose: the
    // lower-left feed only shows a handful of lines and the dvar that sizes it
    // (com_gameMsgWindow1LineCount) is latched at HUD build, not honored mid-match.
    for ( i = 0; i < lines + 1; i++ )
    {
        self menu_draw( "" );
    }

    ts = 0;

    for ( ;; )
    {
        m = self.gfmenu;

        if ( m.current !== "" && !isdefined( m.menus[ m.current ] ) )
        {
            m.current = "";
        }

        render = 0;

        if ( m.current == "" )
        {
            if ( self key_pressed( #"open_menu", 1 ) )
            {
                m.current = "start_menu";
                self menu_toast( "^7RMB^8 up  ^7LMB^8 down  ^7R^8 select  ^7V^8 back" );
                render = 1;
            }
            else
            {
                waitframe( 1 );
                continue;
            }
        }
        else if ( self key_pressed( #"parent_page", 1 ) )
        {
            menu = self menu_current();
            m.current = isdefined( menu ) ? menu.parent_id : "";
            render = 1;
        }
        else if ( self key_pressed( #"last_item", 1 ) )
        {
            menu = self menu_current();

            if ( isdefined( menu ) )
            {
                if ( menu.cursor == 0 || menu.cursor >= menu.items.size )
                {
                    menu.cursor = menu.items.size - 1;
                }
                else
                {
                    menu.cursor--;
                }

                render = 1;
            }
        }
        else if ( self key_pressed( #"next_item", 1 ) )
        {
            menu = self menu_current();

            if ( isdefined( menu ) )
            {
                if ( menu.cursor < menu.items.size - 1 )
                {
                    menu.cursor++;
                }
                else
                {
                    menu.cursor = 0;
                }

                render = 1;
            }
        }
        else if ( self key_pressed( #"select_item", 1 ) )
        {
            menu = self menu_current();

            if ( isdefined( menu ) )
            {
                item = menu.items[ menu.cursor ];

                if ( isdefined( item ) )
                {
                    res = self menu_run_item( item );

                    if ( isdefined( res ) && !res )
                    {
                        m.current = "";
                    }
                }
                else
                {
                    m.current = "";
                }

                render = 1;
            }
        }
        else
        {
            // Nothing pressed: redraw every 5s so iprintln does not fade the menu.
            nts = gettime();

            if ( nts > ts )
            {
                ts = nts + 2000;
                render = 1;
            }
            else
            {
                waitframe( 1 );
                continue;
            }
        }

        if ( render )
        {
            self menu_render( lines );
        }

        waitframe( 1 );
    }
}

// The panel. Fixed height every frame (1 header + <lines> rows + 3 footer) so a
// repaint lands as one stable block instead of a jittering pile. The item list is a
// WINDOW that scrolls with the cursor - 28 maps read as one smooth list, not 14 pages
// of two. Header carries the breadcrumb + position; footer carries live match state
// and the key legend, so the host always sees what is actually set.
// The panel, compact so it survives the ~4-line feed. Exactly 1 header + <lines>
// item rows every frame (default lines=3, cursor centered as prev/here/next). The
// header does double duty: on the ROOT page it is the full state readout klaze
// wanted to keep; on a sub-page it is page name + position + a short state tail, so
// one line still says both "where am I" and "what is set". The divider/state/legend
// footer of the tall version is gone - it pushed the list off the top of the feed.
function private menu_render( lines )
{
    menu = self menu_current();

    if ( !isdefined( menu ) )
    {
        for ( i = 0; i < lines + 1; i++ )
            self menu_draw( "" );
        return;
    }

    n = menu.items.size;

    start = 0;
    if ( n > lines )
    {
        start = menu.cursor - int( lines / 2 );
        if ( start < 0 )
            start = 0;
        if ( start > n - lines )
            start = n - lines;
    }
    end = int( min( start + lines, n ) );

    pos = ( n == 0 ) ? "-/-" : ( "" + ( menu.cursor + 1 ) + "/" + n );

    // Root header = the full state readout klaze wanted kept; sub-page header =
    // page name + position + short state tail. The position counter is the scroll
    // indicator (no caret/arrow glyphs - they do not render reliably in this font).
    if ( menu.id == "start_menu" )
        self menu_draw( self menu_state_line() );
    else
        self menu_draw( "^5" + menu.name + " ^7" + pos + "  ^8> ^7" + self menu_state_compact() );

    if ( n == 0 )
    {
        self menu_draw( "     ^8(empty)" );
        for ( i = 1; i < lines; i++ )
            self menu_draw( "" );
    }
    else
    {
        for ( i = start; i < end; i++ )
            self menu_draw( self menu_item_line( menu, i ) );
        for ( i = end - start; i < lines; i++ )
            self menu_draw( "" );
    }
}

// One rendered row. Cursor row is bright with a > caret; other rows dim. A choice
// that matches its live dvar gets a ^2* and trailing <; a sub-page gets a ^5> ; an
// .activated toggle shows [ON].
function private menu_item_line( menu, i )
{
    it = menu.items[ i ];
    cur = ( menu.cursor == i );

    // menu_switch stores the target page id in data1, so data1 naming a real page
    // means this row opens a submenu.
    submenu = isdefined( it.data1 ) && isdefined( self.gfmenu.menus[ it.data1 ] );

    active = 0;
    if ( isdefined( it.group ) && isdefined( it.gval ) )
        active = ( getdvarint( it.group, -2147483647 ) == it.gval );
    else if ( menu.id == "gametype" && isdefined( it.data1 ) )
        active = ( tolower( getdvarstring( #"g_gametype", "" ) ) == it.data1 );

    mark = "  ";
    if ( active )
        mark = "^2*";
    else if ( submenu )
        mark = "^5>";

    body = it.name;
    if ( it.activated )
        body += " ^2[ON]";
    if ( active )
        body += " ^2<";

    if ( cur )
        return "^2> " + mark + " ^7" + body;

    return "   " + mark + " ^8" + body;
}

// Short state tail for sub-page headers: team size, timer, gametype - the three
// most-changed settings, kept short so the header never wraps.
function private menu_state_compact()
{
    ts = cfg_team_size();
    return ts + "v" + ts + " " + cfg_timer_seconds() + "s " + getdvarstring( #"g_gametype", "?" );
}

// Start > Map > 6v6 maps  - walk parent_id up to the root.
function private menu_breadcrumb( menu )
{
    trail = menu.name;
    p = menu.parent_id;

    for ( guard = 0; guard < 12 && p != ""; guard++ )
    {
        par = self.gfmenu.menus[ p ];
        if ( !isdefined( par ) )
            break;
        trail = par.name + " ^5> ^3" + trail;
        p = par.parent_id;
    }

    return trail;
}

// The always-on state readout: team size, timer, current map+gametype, seated
// players against the client budget, and the map method. Everything the host would
// otherwise have to trigger something to find out.
function private menu_state_line()
{
    ts = cfg_team_size();
    seated = getplayers( #"allies" ).size + getplayers( #"axis" ).size;
    budget = getdvarint( #"com_maxclients", 0 );
    map = getdvarstring( #"sv_mapname", "?" );
    gt = getdvarstring( #"g_gametype", "?" );
    meth = cfg_map_method() ? "SESSION" : "carry";

    return "^7" + ts + "v" + ts + " ^8| ^7" + cfg_timer_seconds() + "s ^8| ^7" + map + " ^8| ^7" + gt + " ^8| ^7" + seated + "/" + budget + " ^8| ^7" + meth;
}

// ═════════════════════════════════════════════════════════════════════════════
// KEYS — translated from t8-atian-menu keymanager.gsc, same bindings
// ═════════════════════════════════════════════════════════════════════════════

// Combos are built with [] and index assignment rather than bare array( ... ).
// ⚠ Not because array() is missing: the engine table lists it (array, 0-100
// args). But stock MP scripts contain ZERO bare array() calls - every stock use
// is the array:: namespace - so under ACTS it is a builtin with no precedent in
// the code we link against, and a link-time failure on a key table would take
// the whole menu with it. [] construction is the form that cannot fail either
// way. (A commit message once said "array is a namespace under T9" as if that
// were the whole story; it is a namespace AND a builtin.)
function private keys_init()
{
    self.gfkeys = [];

    open = [];
    open[ 0 ] = #"ads";
    open[ 1 ] = #"melee";
    self.gfkeys[ #"open_menu" ] = open;

    self.gfkeys[ #"parent_page" ] = key_single( #"melee" );
    self.gfkeys[ #"last_item" ]   = key_single( #"ads" );
    self.gfkeys[ #"next_item" ]   = key_single( #"attack" );
    self.gfkeys[ #"select_item" ] = key_single( #"reload" );
}

function private key_single( key )
{
    combo = [];
    combo[ 0 ] = key;
    return combo;
}

// All keys of the combo down; with wait_release, also wait until they are all up,
// so one press is one action.
function private key_pressed( id, wait_release = 0 )
{
    combo = self.gfkeys[ id ];

    if ( !isdefined( combo ) )
    {
        return false;
    }

    for ( i = 0; i < combo.size; i++ )
    {
        if ( !self key_down( combo[ i ] ) )
        {
            return false;
        }
    }

    if ( !wait_release )
    {
        return true;
    }

    for ( ;; )
    {
        any_down = 0;

        for ( i = 0; i < combo.size; i++ )
        {
            if ( self key_down( combo[ i ] ) )
            {
                any_down = 1;
            }
        }

        if ( !any_down )
        {
            break;
        }

        waitframe( 1 );
    }

    return true;
}

function private key_down( key )
{
    switch ( key )
    {
        case #"ads":    return self adsbuttonpressed();
        case #"attack": return self attackbuttonpressed();
        case #"melee":  return self meleebuttonpressed();
        case #"reload": return self reloadbuttonpressed();
        case #"use":    return self usebuttonpressed();
        default:        return false;
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// THE TREE
// ═════════════════════════════════════════════════════════════════════════════

function private build_tree()
{
    // ── Teams ────────────────────────────────────────────────────────────────
    self menu_add( "teams", "Teams", "start_menu", 1 );
    self menu_item( "teams", "2v2", &act_team_size, 2, undefined, #"gf_team_size", 2 );
    self menu_item( "teams", "3v3", &act_team_size, 3, undefined, #"gf_team_size", 3 );
    self menu_item( "teams", "4v4", &act_team_size, 4, undefined, #"gf_team_size", 4 );
    self menu_item( "teams", "5v5", &act_team_size, 5, undefined, #"gf_team_size", 5 );
    // 6v6 = 12 clients = exactly the com_maxclients lobby_state read in a Gunfight session
    // after a SESSION map switch (2026-09-12). clamp_team_size() bounds it at budget/2, so
    // in an 8- or 10-slot lobby this item degrades to 4v4 / 5v5 and says so.
    self menu_item( "teams", "6v6", &act_team_size, 6, undefined, #"gf_team_size", 6 );
    self menu_item( "teams", "Fill with bots", &act_fill_bots );
    self menu_item( "teams", "Remove all bots", &act_remove_bots );

    // ── Players — rebuilt from getplayers() every time the page opens ────────
    self menu_add( "players", "Players", "start_menu", 1, &players_enter );

    // ── Round ────────────────────────────────────────────────────────────────
    self menu_add( "round", "Round", "start_menu", 1 );
    self menu_item( "round", "Timer 20s", &act_timer, 20, undefined, #"gf_timer_seconds", 20 );
    self menu_item( "round", "Timer 30s", &act_timer, 30, undefined, #"gf_timer_seconds", 30 );
    self menu_item( "round", "Timer 40s", &act_timer, 40, undefined, #"gf_timer_seconds", 40 );
    self menu_item( "round", "Timer 60s", &act_timer, 60, undefined, #"gf_timer_seconds", 60 );
    self menu_item( "round", "Timer 90s", &act_timer, 90, undefined, #"gf_timer_seconds", 90 );
    self menu_item( "round", "Timer 120s", &act_timer, 120, undefined, #"gf_timer_seconds", 120 );
    self menu_item( "round", "Restart match", &act_restart );

    // ── Loadout set — B6, never run ──────────────────────────────────────────
    self menu_add( "loadout", "Loadout", "start_menu", 1 );
    self menu_item( "loadout", "Default", &act_loadout, 0, undefined, #"gf_loadout", 0 );
    self menu_item( "loadout", "Snipers", &act_loadout, 1, undefined, #"gf_loadout", 1 );
    self menu_item( "loadout", "Blueprints", &act_loadout, 2, undefined, #"gf_loadout", 2 );
    self menu_item( "loadout", "Melee", &act_loadout, 3, undefined, #"gf_loadout", 3 );

    // ── Spy plane — value 3 is the one the rules menu hides. B7, never run ───
    self menu_add( "spyplane", "Spy plane", "start_menu", 1 );
    self menu_item( "spyplane", "Off", &act_spyplane, 0, undefined, #"gf_spyplane", 0 );
    self menu_item( "spyplane", "On", &act_spyplane, 1, undefined, #"gf_spyplane", 1 );
    self menu_item( "spyplane", "Shared - hidden value", &act_spyplane, 3, undefined, #"gf_spyplane", 3 );

    // ── Spawns — #spawn_guard. Default OFF, UNTESTED: test SOLO first ─────────
    self menu_add( "spawns", "Spawns", "start_menu", 1 );
    self menu_item( "spawns", "Spawn guard OFF", &act_spawn_guard, 0, undefined, #"gf_spawn_guard", 0 );
    self menu_item( "spawns", "Spawn guard ON (test solo)", &act_spawn_guard, 1, undefined, #"gf_spawn_guard", 1 );
    self menu_item( "spawns", "Spawn report", &act_spawn_report );

    // ── Match — first-to / round cap / loadout rotation. Keys verified in source ─
    self menu_add( "match", "Match", "start_menu", 1 );
    self menu_item( "match", "First to 2", &act_roundwinlimit, 2, undefined, #"gf_roundwinlimit", 2 );
    self menu_item( "match", "First to 4", &act_roundwinlimit, 4, undefined, #"gf_roundwinlimit", 4 );
    self menu_item( "match", "First to 6", &act_roundwinlimit, 6, undefined, #"gf_roundwinlimit", 6 );
    self menu_item( "match", "First to 10", &act_roundwinlimit, 10, undefined, #"gf_roundwinlimit", 10 );
    self menu_item( "match", "Round cap 6", &act_roundlimit, 6, undefined, #"gf_roundlimit", 6 );
    self menu_item( "match", "Round cap 10", &act_roundlimit, 10, undefined, #"gf_roundlimit", 10 );
    self menu_item( "match", "Loadout rotate 1", &act_rounds_loadout, 1, undefined, #"gf_rounds_loadout", 1 );
    self menu_item( "match", "Loadout rotate 2", &act_rounds_loadout, 2, undefined, #"gf_rounds_loadout", 2 );
    self menu_item( "match", "Loadout rotate 3", &act_rounds_loadout, 3, undefined, #"gf_rounds_loadout", 3 );

    // ── Movement — gravity (verified) + jump (untested builtin) ──────────────
    self menu_add( "movement", "Movement", "start_menu", 1 );
    self menu_item( "movement", "Gravity normal 800", &act_gravity, 800, undefined, #"gf_gravity", 800 );
    self menu_item( "movement", "Gravity low 400", &act_gravity, 400, undefined, #"gf_gravity", 400 );
    self menu_item( "movement", "Gravity moon 200", &act_gravity, 200, undefined, #"gf_gravity", 200 );
    self menu_item( "movement", "Gravity floaty 100", &act_gravity, 100, undefined, #"gf_gravity", 100 );
    self menu_item( "movement", "Gravity space 40", &act_gravity, 40, undefined, #"gf_gravity", 40 );
    self menu_item( "movement", "Jump: leave stock", &act_jump, -1, undefined, #"gf_jump", -1 );
    self menu_item( "movement", "Jump 40", &act_jump, 40, undefined, #"gf_jump", 40 );
    self menu_item( "movement", "Jump 70", &act_jump, 70, undefined, #"gf_jump", 70 );
    self menu_item( "movement", "Jump 120", &act_jump, 120, undefined, #"gf_jump", 120 );
    self menu_item( "movement", "Jump 200", &act_jump, 200, undefined, #"gf_jump", 200 );

    // ── Vehicles — drivable, Combined-Arms/12v12-layout maps only ────────────
    self menu_add( "vehicles", "Vehicles", "start_menu", 1 );
    self menu_item( "vehicles", "Spawn snowmobile", &veh_spawn, "vehicle_t9_mil_snowmobile" );
    self menu_item( "vehicles", "Spawn light truck", &veh_spawn, "vehicle_t9_mil_ru_truck_light_player" );
    self menu_item( "vehicles", "Spawn sedan", &veh_spawn, "vehicle_t9_civ_ru_sedan_80s_player" );
    self menu_item( "vehicles", "Spawn care-package heli", &veh_spawn, "vehicle_t9_mil_helicopter_care_package" );
    self menu_item( "vehicles", "Enter vehicle I am aiming at", &veh_enter );

    // ── Player tools — host only ─────────────────────────────────────────────
    self menu_add( "player", "Player", "start_menu", 1 );
    self menu_item( "player", "Godmode", &act_godmode );
    self menu_item( "player", "Third person", &act_thirdperson );
    self menu_item( "player", "Give max ammo", &act_maxammo );
    self menu_item( "player", "Drop weapon", &act_dropweapon );
    self menu_item( "player", "Unlock all (best-effort)", &act_unlockall );

    // ── Weapons — give a gun (real T9 names from the dump) ────────────────────
    self menu_add( "weapons", "Weapons", "start_menu", 1 );
    self menu_item( "weapons", "XM4 (AR)", &act_giveweapon, #"ar_standard_t9", "XM4" );
    self menu_item( "weapons", "Krig 6 (AR)", &act_giveweapon, #"ar_accurate_t9", "Krig 6" );
    self menu_item( "weapons", "AK-47 (AR)", &act_giveweapon, #"ar_damage_t9", "AK-47" );
    self menu_item( "weapons", "MP5 (SMG)", &act_giveweapon, #"smg_standard_t9", "MP5" );
    self menu_item( "weapons", "Milano (SMG)", &act_giveweapon, #"smg_handling_t9", "Milano" );
    self menu_item( "weapons", "MAC-10 (SMG)", &act_giveweapon, #"smg_fastfire_t9", "MAC-10" );
    self menu_item( "weapons", "M16 (Tactical Rifle)", &act_giveweapon, #"tr_powerburst_t9", "M16" );
    self menu_item( "weapons", "Pelington (Sniper)", &act_giveweapon, #"sniper_standard_t9", "Pelington" );
    self menu_item( "weapons", "LW3 Tundra (Sniper)", &act_giveweapon, #"sniper_quickscope_t9", "LW3 Tundra" );
    self menu_item( "weapons", "M82 (Sniper)", &act_giveweapon, #"sniper_powersemi_t9", "M82" );
    self menu_item( "weapons", "Stoner63 (LMG)", &act_giveweapon, #"lmg_light_t9", "Stoner63" );
    self menu_item( "weapons", "Hauer 77 (Shotgun)", &act_giveweapon, #"shotgun_pump_t9", "Hauer 77" );
    self menu_item( "weapons", "Gallo SA12 (Shotgun)", &act_giveweapon, #"shotgun_fullauto_t9", "Gallo SA12" );
    self menu_item( "weapons", "Magnum (Pistol)", &act_giveweapon, #"pistol_revolver_t9", "Magnum" );
    self menu_item( "weapons", "Diamatti (Pistol)", &act_giveweapon, #"pistol_burst_t9", "Diamatti" );

    // ── Camo — applied to the current weapon, ownership ignored ───────────────
    self menu_add( "camo", "Camo", "start_menu", 1 );
    self menu_item( "camo", "Gold", &act_camo, 61 );
    self menu_item( "camo", "Diamond", &act_camo, 62 );
    self menu_item( "camo", "DM Ultra", &act_camo, 63 );
    self menu_item( "camo", "Gold (Zombies)", &act_camo, 64 );
    self menu_item( "camo", "Diamond (Zombies)", &act_camo, 65 );
    self menu_item( "camo", "Dark Aether", &act_camo, 66 );
    self menu_item( "camo", "Pack-a-Punch 1", &act_camo, 67 );
    self menu_item( "camo", "Pack-a-Punch 2", &act_camo, 68 );
    self menu_item( "camo", "Pack-a-Punch 3", &act_camo, 69 );
    self menu_add( "camo_byid", "Camo by ID (0-149)", "camo", 1 );
    for ( ci = 0; ci < 150; ci++ )
        self menu_item( "camo_byid", "Camo " + ci, &act_camo, ci );

    // ── Operator (skin) ───────────────────────────────────────────────────────
    self menu_add( "operator", "Operator", "start_menu", 1 );
    self menu_item( "operator", "Invisible", &act_skin, 0 );
    self menu_item( "operator", "Adler", &act_skin, 1 );
    self menu_item( "operator", "Portnova", &act_skin, 2 );
    self menu_item( "operator", "Garcia", &act_skin, 3 );
    self menu_item( "operator", "Baker", &act_skin, 4 );
    self menu_item( "operator", "Sims", &act_skin, 5 );
    self menu_item( "operator", "Hunter", &act_skin, 6 );
    self menu_item( "operator", "Vargas", &act_skin, 7 );
    self menu_item( "operator", "Stone", &act_skin, 8 );
    self menu_item( "operator", "Song", &act_skin, 9 );
    self menu_item( "operator", "Powers", &act_skin, 10 );
    self menu_item( "operator", "Baker (2)", &act_skin, 11 );
    self menu_item( "operator", "Zeyna", &act_skin, 12 );
    self menu_item( "operator", "Wolf", &act_skin, 13 );
    self menu_item( "operator", "Beck", &act_skin, 14 );
    self menu_item( "operator", "Knight", &act_skin, 15 );
    self menu_item( "operator", "Antonov", &act_skin, 16 );
    self menu_item( "operator", "Park", &act_skin, 17 );
    self menu_item( "operator", "Stitch", &act_skin, 18 );
    self menu_item( "operator", "Bulldozer", &act_skin, 19 );
    self menu_item( "operator", "CDL 1", &act_skin, 20 );
    self menu_item( "operator", "CDL 2", &act_skin, 21 );
    self menu_item( "operator", "Woods", &act_skin, 22 );
    self menu_item( "operator", "Rivas", &act_skin, 23 );
    self menu_item( "operator", "Naga", &act_skin, 24 );
    self menu_item( "operator", "Maxis", &act_skin, 25 );
    self menu_item( "operator", "John Doe", &act_skin, 26 );
    self menu_item( "operator", "Jane Doe", &act_skin, 27 );
    self menu_item( "operator", "Base (M)", &act_skin, 28 );
    self menu_item( "operator", "Base (F)", &act_skin, 29 );
    self menu_item( "operator", "Wraith", &act_skin, 30 );
    self menu_item( "operator", "Baker (3)", &act_skin, 31 );
    self menu_item( "operator", "Park (2)", &act_skin, 32 );
    self menu_item( "operator", "Price", &act_skin, 33 );
    self menu_item( "operator", "John McClane", &act_skin, 34 );
    self menu_item( "operator", "Rambo", &act_skin, 35 );
    self menu_item( "operator", "Weaver", &act_skin, 36 );
    self menu_item( "operator", "Jackal", &act_skin, 37 );
    self menu_item( "operator", "Salah", &act_skin, 38 );
    self menu_item( "operator", "Kitsune", &act_skin, 39 );
    self menu_item( "operator", "Stryker", &act_skin, 40 );
    self menu_item( "operator", "Arthur Kingsley", &act_skin, 41 );
    self menu_item( "operator", "Hudson", &act_skin, 42 );
    self menu_item( "operator", "Mason", &act_skin, 43 );
    self menu_item( "operator", "Scream", &act_skin, 44 );
    self menu_item( "operator", "Fuze", &act_skin, 45 );
    self menu_item( "operator", "Zombie (F)", &act_skin, 46 );
    self menu_item( "operator", "Zombie (M)", &act_skin, 47 );
    self menu_item( "operator", "Lazar", &act_skin, 48 );

    // ── Outfit — by id (per-operator outfits) ─────────────────────────────────
    self menu_add( "outfit", "Outfit", "start_menu", 1 );
    for ( oi = 0; oi < 24; oi++ )
        self menu_item( "outfit", "Outfit " + oi, &act_outfit, oi );

    // ── Map ──────────────────────────────────────────────────────────────────
    // Every label is "<in-game display name>  [<map name>]". Names audited 2026-09-12
    // against the dump's map table (36 mp_* maptableentry assets, no 37th), the CoD
    // wiki's per-map `console` field, and per-map asset fingerprints; the table with
    // the provenance is docs/reference/bocw-maps.md. The labels this file carried
    // before were guesses and several were wrong (mp_dune is Collateral, not Rush;
    // mp_village_rm is Standoff; mp_cliffhanger is Yamantau; mp_kgb is Checkmate).
    self menu_add( "map", "Map", "start_menu", 1 );
    // (ON) = SESSION, the default: the lobby follows the switch. Off = the old Atian
    // load-time carry. Seeded from the dvar so the marker is right on first open.
    it = self menu_item( "map", "Session switch (lobby follows)", &act_map_method );
    it.activated = cfg_map_method();
    self menu_item( "map", "Zoo - verified  [mp_zoo_rm]", &act_map, "mp_zoo_rm" );
    self menu_add( "map_6v6", "6v6 maps", "map", 1 );
    self menu_add( "map_gf", "Gunfight maps", "map", 1 );
    self menu_add( "map_large", "12v12 layouts - TDM 10v10", "map", 1 );
    self menu_add( "map_ft", "Fireteam maps - untested", "map", 1 );

    // 6v6 maps. The three large maps are ONE file each whose script picks the 12v12 or
    // the Strike boundary from the g_gametype string at level_init (bocw-maps.md):
    // under gunfight, mp_black_sea and mp_dune come up as their STRIKE layouts and
    // mp_tundra comes up as the FULL 12v12 map ("gunfight" is not in Crossroads' 6v6
    // token list). The labels say which layout the switch will actually produce.
    self menu_item( "map_6v6", "Amerika  [mp_amerika]", &act_map, "mp_amerika" );
    self menu_item( "map_6v6", "Apocalypse  [mp_apocalypse]", &act_map, "mp_apocalypse" );
    self menu_item( "map_6v6", "Armada Strike  [mp_black_sea]", &act_map, "mp_black_sea" );
    self menu_item( "map_6v6", "Cartel  [mp_cartel]", &act_map, "mp_cartel" );
    self menu_item( "map_6v6", "Checkmate  [mp_kgb]", &act_map, "mp_kgb" );
    self menu_item( "map_6v6", "Collateral Strike  [mp_dune]", &act_map, "mp_dune" );
    self menu_item( "map_6v6", "Crossroads - full 12v12 layout  [mp_tundra]", &act_map, "mp_tundra" );
    self menu_item( "map_6v6", "Deprogram  [mp_firebase]", &act_map, "mp_firebase" );
    self menu_item( "map_6v6", "Diesel  [mp_sm_gas_station]", &act_map, "mp_sm_gas_station" );
    self menu_item( "map_6v6", "Drive-In  [mp_drivein_rm]", &act_map, "mp_drivein_rm" );
    self menu_item( "map_6v6", "Echelon  [mp_echelon]", &act_map, "mp_echelon" );
    self menu_item( "map_6v6", "Express  [mp_express_rm]", &act_map, "mp_express_rm" );
    self menu_item( "map_6v6", "Garrison  [mp_tank]", &act_map, "mp_tank" );
    self menu_item( "map_6v6", "Hijacked  [mp_hijacked_rm]", &act_map, "mp_hijacked_rm" );
    self menu_item( "map_6v6", "Jungle  [mp_jungle_rm]", &act_map, "mp_jungle_rm" );
    self menu_item( "map_6v6", "Miami  [mp_miami]", &act_map, "mp_miami" );
    self menu_item( "map_6v6", "Miami Strike  [mp_miami_strike]", &act_map, "mp_miami_strike" );
    self menu_item( "map_6v6", "Moscow  [mp_moscow]", &act_map, "mp_moscow" );
    self menu_item( "map_6v6", "Nuketown '84  [mp_nuketown6]", &act_map, "mp_nuketown6" );
    self menu_item( "map_6v6", "Raid  [mp_raid_rm]", &act_map, "mp_raid_rm" );
    self menu_item( "map_6v6", "Rush  [mp_paintball_rm]", &act_map, "mp_paintball_rm" );
    self menu_item( "map_6v6", "Satellite  [mp_satellite]", &act_map, "mp_satellite" );
    self menu_item( "map_6v6", "Slums  [mp_slums_rm]", &act_map, "mp_slums_rm" );
    self menu_item( "map_6v6", "Standoff  [mp_village_rm]", &act_map, "mp_village_rm" );
    self menu_item( "map_6v6", "The Pines  [mp_mall]", &act_map, "mp_mall" );
    self menu_item( "map_6v6", "WMD  [mp_russianbase_rm]", &act_map, "mp_russianbase_rm" );
    self menu_item( "map_6v6", "Yamantau  [mp_cliffhanger]", &act_map, "mp_cliffhanger" );
    self menu_item( "map_6v6", "Zoo  [mp_zoo_rm]", &act_map, "mp_zoo_rm" );

    // Gunfight / Face Off maps, plus the two the stock Gunfight rotation borrows.
    self menu_item( "map_gf", "Amsterdam  [mp_sm_amsterdam]", &act_map, "mp_sm_amsterdam" );
    self menu_item( "map_gf", "Diesel  [mp_sm_gas_station]", &act_map, "mp_sm_gas_station" );
    self menu_item( "map_gf", "Game Show  [mp_sm_game_show]", &act_map, "mp_sm_game_show" );
    self menu_item( "map_gf", "Gluboko  [mp_sm_vault]", &act_map, "mp_sm_vault" );
    self menu_item( "map_gf", "ICBM  [mp_sm_central]", &act_map, "mp_sm_central" );
    self menu_item( "map_gf", "KGB  [mp_sm_finance]", &act_map, "mp_sm_finance" );
    self menu_item( "map_gf", "Mansion  [mp_sm_market]", &act_map, "mp_sm_market" );
    self menu_item( "map_gf", "Nuketown '84  [mp_nuketown6]", &act_map, "mp_nuketown6" );
    self menu_item( "map_gf", "Showroom  [mp_sm_deptstore]", &act_map, "mp_sm_deptstore" );
    self menu_item( "map_gf", "U-Bahn  [mp_sm_berlin_tunnel]", &act_map, "mp_sm_berlin_tunnel" );

    // The full 12v12 layouts of the large maps. Same files as above; the map scripts
    // open the 12v12 boundary only when g_gametype is a 10v10/12v12 string, so these
    // switch the SESSION to map + "tdm10v10" (gametypetableentry teamdeathmatch_10v10
    // exists in the dump). Not Gunfight, and not yet run: the *10v10 strings have only
    // been seen inside matchmade playlists. Crossroads' full layout is what gunfight
    // already gets (above); it is here so all three read the same way.
    self menu_item( "map_large", "Armada 12v12 - TDM 10v10  [mp_black_sea]", &act_map_gt, "mp_black_sea", "tdm10v10" );
    self menu_item( "map_large", "Collateral 12v12 - TDM 10v10  [mp_dune]", &act_map_gt, "mp_dune", "tdm10v10" );
    self menu_item( "map_large", "Crossroads 12v12 - TDM 10v10  [mp_tundra]", &act_map_gt, "mp_tundra", "tdm10v10" );

    // Fireteam / Multi-team maps (40-player, dedicated-server modes). The wz_* scripts
    // link core_common only and fireteam.gsc registers tdm spawn points, so a 6v6 mode
    // is not ruled out by the script layer - but nobody has loaded one this way.
    self menu_item( "map_ft", "Alpine  [wz_ski_slopes]", &act_map, "wz_ski_slopes" );
    self menu_item( "map_ft", "Duga  [wz_duga]", &act_map, "wz_duga" );
    self menu_item( "map_ft", "Golova  [wz_golova]", &act_map, "wz_golova" );
    self menu_item( "map_ft", "Ruka  [wz_forest]", &act_map, "wz_forest" );
    self menu_item( "map_ft", "Sanatorium  [wz_sanatorium]", &act_map, "wz_sanatorium" );

    // ── Gametype — the SESSION switch with the gametype swapped and the map kept ─
    // The Atian source's dead func_set_gametype(), wired in. Strings are the gametype
    // SCRIPT names (scripts/mp_common/gametypes/<name>.gsc). Workflow this enables:
    // create the lobby under TDM (any map is selectable there, 12 slots), start, then
    // switch to gunfight here; the map and the session stay. The Gunfight fixes in
    // mod_apply are gated on the gametype, so the menu is safe to link into TDM.
    self menu_add( "gametype", "Gametype", "start_menu", 1 );
    self menu_item( "gametype", "Gunfight", &act_gametype, "gunfight" );
    self menu_item( "gametype", "Gunfight 3v3", &act_gametype, "gunfight_3v3" );
    self menu_item( "gametype", "TDM", &act_gametype, "tdm" );
    self menu_item( "gametype", "Free-for-all", &act_gametype, "dm" );
    self menu_item( "gametype", "Domination", &act_gametype, "dom" );
    self menu_item( "gametype", "Hardpoint", &act_gametype, "koth" );
    self menu_item( "gametype", "Search & Destroy", &act_gametype, "sd" );
    self menu_item( "gametype", "Kill Confirmed", &act_gametype, "conf" );
    self menu_item( "gametype", "Control", &act_gametype, "control" );
    self menu_item( "gametype", "Capture the Flag", &act_gametype, "ctf" );
    self menu_item( "gametype", "Demolition", &act_gametype, "dem" );
    self menu_item( "gametype", "Infected", &act_gametype, "infect" );
    self menu_item( "gametype", "Gun Game", &act_gametype, "gun" );
    self menu_item( "gametype", "Prop Hunt", &act_gametype, "prop" );
    self menu_item( "gametype", "Sticks and Stones", &act_gametype, "sas" );
    self menu_item( "gametype", "One in the Chamber", &act_gametype, "oic" );
    self menu_item( "gametype", "Dropkick", &act_gametype, "dropkick" );
    self menu_item( "gametype", "VIP Escort", &act_gametype, "vip" );
    self menu_item( "gametype", "Team War", &act_gametype, "war" );
    self menu_item( "gametype", "Cranked", &act_gametype, "cranked" );
}

// ═════════════════════════════════════════════════════════════════════════════
// ACTIONS
// ═════════════════════════════════════════════════════════════════════════════

// ── Teams ────────────────────────────────────────────────────────────────────

function private act_team_size( item, per_side )
{
    clamped = clamp_team_size( per_side );
    setdvar( #"gf_team_size", clamped );
    setgametypesetting( #"maxplayers", clamped * 2 );

    if ( clamped < per_side )
    {
        self menu_say( "^3team size " + clamped + "v" + clamped + " - lobby budget is " + getdvarint( #"com_maxclients", 0 ) + " clients" );
    }
    else
    {
        self menu_say( "^2team size " + clamped + "v" + clamped );
    }

    return true;
}

function private act_fill_bots( item )
{
    self thread fill_bots();
    return true;
}

function private fill_bots()
{
    self endon( #"disconnect" );

    target = cfg_team_size();
    added = 0;

    teams = [];
    teams[ 0 ] = #"allies";
    teams[ 1 ] = #"axis";

    foreach ( team in teams )
    {
        need = target - getplayers( team ).size;

        for ( i = 0; i < need; i++ )
        {
            b = bot::add_bot( team );

            if ( !isdefined( b ) )
            {
                self menu_say( "^1bot refused at " + getplayers( #"allies" ).size + "v" + getplayers( #"axis" ).size + " - client budget hit" );
                return;
            }

            added++;
            waitframe( 1 );
        }
    }

    self menu_say( "^2" + added + " bots added: " + getplayers( #"allies" ).size + "v" + getplayers( #"axis" ).size );
}

function private act_remove_bots( item )
{
    bot::remove_bots( #"allies" );
    bot::remove_bots( #"axis" );
    self menu_say( "^2bots removed" );
    return true;
}

// ── Players ──────────────────────────────────────────────────────────────────

function private players_enter( menu )
{
    self menu_clear_items( "players" );

    foreach ( player in getplayers() )
    {
        if ( isbot( player ) )
        {
            continue;
        }

        label = player.name + "  ^0" + team_tag( player );
        self menu_item( "players", label, &act_player_page, player );
    }
}

function private team_tag( player )
{
    t = player.pers[ #"team" ];

    if ( !isdefined( t ) )
    {
        return "?";
    }

    if ( t == #"spectator" )
    {
        return "spec";
    }

    if ( t == #"allies" )
    {
        return "allies";
    }

    if ( t == #"axis" )
    {
        return "axis";
    }

    return "?";
}

function private act_player_page( item, player )
{
    if ( !isdefined( player ) )
    {
        self menu_say( "^1player left" );
        return true;
    }

    id = "player_" + player getentitynumber();
    self menu_add( id, player.name, "players", 0 );
    self menu_clear_items( id );
    self menu_item( id, "To Allies", &act_move, player, #"allies" );
    self menu_item( id, "To Axis", &act_move, player, #"axis" );
    self menu_item( id, "To Spectator", &act_spectate, player );

    return self menu_switch( undefined, id );
}

// ⚠ C11's mechanism, never run in-game. [[ level.autoassign ]]( 0, team ) with
// comingfrommenu = 0 lands in team_assignment.gsc:419, which uses the team verbatim
// with no fullness check - the branch klaze already sees fire when "a spot is open
// on the join". comingfrommenu MUST be 0; 1 skips that branch.
function private act_move( item, player, team )
{
    if ( !isdefined( player ) )
    {
        self menu_say( "^1player left" );
        return true;
    }

    // Harden C11: guard the function-pointer deref so a build without level.autoassign
    // fails with a message instead of a runtime error, and no-op if already on the team.
    if ( !isdefined( level.autoassign ) )
    {
        self menu_say( "^1move unavailable (level.autoassign undefined)" );
        return true;
    }

    name = ( team == #"allies" ) ? "allies" : "axis";

    if ( isdefined( player.team ) && player.team == team )
    {
        self menu_say( "^3" + player.name + " already on " + name );
        return true;
    }

    player [[ level.autoassign ]]( 0, team, undefined );
    self menu_say( "^2" + player.name + " -> " + name );
    return true;
}

function private act_spectate( item, player )
{
    if ( !isdefined( player ) )
    {
        self menu_say( "^1player left" );
        return true;
    }

    if ( !isdefined( level.spectator ) )
    {
        self menu_say( "^1spectate unavailable (level.spectator undefined)" );
        return true;
    }

    player [[ level.spectator ]]();
    self menu_say( "^2" + player.name + " -> spectator" );
    return true;
}

// ── Round ────────────────────────────────────────────────────────────────────

function private act_timer( item, seconds )
{
    setdvar( #"gf_timer_seconds", seconds );
    // Lands within ~0.25s: updategametypedvars() re-reads gettimelimit every loop.
    self menu_say( "^2round timer " + seconds + "s" );
    return true;
}

function private act_restart( item )
{
    self menu_say( "^3restarting..." );
    map_restart();
    return false;
}

// ── Loadout ──────────────────────────────────────────────────────────────────

function private act_loadout( item, index )
{
    setdvar( #"gf_loadout", index );
    setgametypesetting( #"gunfightloadoutindex", index );

    // gunfight.gsc:81 picks the loadout set only while game.var_96a8ff4a is
    // undefined. Clear the latch once so the NEXT round re-picks from the new set.
    game.var_96a8ff4a = undefined;

    self menu_say( "^2loadout set " + index + " - takes effect next round" );
    return true;
}

// ── Spy plane ────────────────────────────────────────────────────────────────

function private act_spyplane( item, value )
{
    setdvar( #"gf_spyplane", value );
    setgametypesetting( #"gunfightspyplane", value );
    self menu_say( "^2spy plane " + value + " - next round" );
    return true;
}

// ── Spawns ─────────────────────────────────────────────────────────────────

function private act_spawn_report( item )
{
    self thread spawn_report();
    return true;
}

function private act_spawn_guard( item, value )
{
    setdvar( #"gf_spawn_guard", value );

    if ( value )
    {
        // Build the anchors now so the guard also applies to THIS round's respawns, not
        // only from next round's mod_apply. Safe from a player context - mod_spawn_build
        // only touches level.* and getplayers().
        mod_spawn_build();
        self menu_say( "^3spawn guard ON - test SOLO; full effect next round" );
    }
    else
    {
        self menu_say( "^2spawn guard OFF - stock spawns" );
    }

    return true;
}

// ── Match-length knobs. Verified stock keys; sentinel -1 elsewhere = untouched. ──

function private act_roundwinlimit( item, value )
{
    setdvar( #"gf_roundwinlimit", value );
    setgametypesetting( #"roundwinlimit", value );
    self menu_say( "^2first to " + value + " rounds - applies next round" );
    return true;
}

function private act_roundlimit( item, value )
{
    setdvar( #"gf_roundlimit", value );
    setgametypesetting( #"roundlimit", value );
    self menu_say( "^2round cap " + value + " - applies next round" );
    return true;
}

function private act_rounds_loadout( item, value )
{
    setdvar( #"gf_rounds_loadout", value );
    setgametypesetting( #"gunfightroundsperloadout", value );
    self menu_say( "^2loadout rotates every " + value + " round(s) - next round" );
    return true;
}

// ── Movement ───────────────────────────────────────────────────────────────

function private act_gravity( item, value )
{
    setdvar( #"gf_gravity", value );
    setdvar( #"bg_gravity", value );
    self menu_say( "^2gravity " + value + ( value == 800 ? " (normal)" : "" ) );
    return true;
}

function private act_jump( item, value )
{
    setdvar( #"gf_jump", value );

    if ( value >= 0 )
    {
        setjumpheight( value );
        self menu_say( "^3jump height " + value + " - untested builtin, watch your jump" );
    }
    else
    {
        self menu_say( "^2jump left at engine default" );
    }

    return true;
}

// ── Vehicles ───────────────────────────────────────────────────────────────
// Spawn a drivable vehicle ahead of the host. The mechanism is the shipped Atian
// menu's (menu_funcs.gsc func_spawn_vehicle): spawnvehicle + makeusable, with physics
// and helicopter handling. ⚠ Vehicle ASSETS only exist on maps that ship them - the
// Combined-Arms / 12v12-layout maps - so isassetloaded() gates it and says so on a
// Gunfight map instead of failing. ⚠ Whole feature UNTESTED in this project.

function private veh_spawn( item, type )
{
    if ( !isassetloaded( "vehicle", type ) )
    {
        self menu_say( "^1no vehicle assets on this map - try a 12v12-layout map" );
        return true;
    }

    ang = self getplayerangles();
    flat = ( 0, ang[ 1 ], 0 );                                   // level, keep the yaw
    spot = self.origin + vectorscale( anglestoforward( flat ), 250 ) + ( 0, 0, 25 );

    veh = spawnvehicle( type, spot, flat );

    if ( !isdefined( veh ) )
    {
        self menu_say( "^1spawn failed" );
        return true;
    }

    veh makeusable();

    if ( isdefined( veh.isphysicsvehicle ) && veh.isphysicsvehicle )
        veh setbrake( 1 );

    if ( isairborne( veh ) )
        veh setrotorspeed( 1.0 );

    self menu_say( "^2vehicle spawned ahead - walk into it and hold Use" );
    return true;
}

function private veh_enter( item )
{
    eye = self geteye();
    tr = bullettrace( eye, eye + vectorscale( anglestoforward( self getplayerangles() ), 400 ), 1, self );
    ent = tr[ #"entity" ];

    if ( isdefined( ent ) && isvehicle( ent ) )
    {
        ent usevehicle( self, 0 );
        self menu_say( "^2entering" );
    }
    else
    {
        self menu_say( "^1look right at a vehicle first" );
    }

    return true;
}

// ── Player tools ─────────────────────────────────────────────────────────────
// Host-only (self = the host). Godmode/third person are re-applied on spawn by
// mod_spawn_place. Same builtins the Atian menu uses (menu_funcs.gsc).

function private act_godmode( item )
{
    if ( !isdefined( self.gf_god ) )
        self.gf_god = 0;
    self.gf_god = !self.gf_god;
    item.activated = self.gf_god;

    if ( self.gf_god )
    {
        self enableinvulnerability();
        self menu_say( "^2godmode ON" );
    }
    else
    {
        self disableinvulnerability();
        self menu_say( "^2godmode OFF" );
    }

    return true;
}

function private act_thirdperson( item )
{
    if ( !isdefined( self.gf_tp ) )
        self.gf_tp = 0;
    self.gf_tp = !self.gf_tp;
    item.activated = self.gf_tp;
    self setclientthirdperson( self.gf_tp );
    self menu_say( self.gf_tp ? "^2third person" : "^2first person" );
    return true;
}

function private act_maxammo( item )
{
    w = self getcurrentweapon();
    if ( isdefined( w ) )
        self givemaxammo( w );
    self menu_say( "^2max ammo" );
    return true;
}

function private act_dropweapon( item )
{
    w = self getcurrentweapon();
    if ( isdefined( w ) && self hasweapon( w ) )
        self takeweapon( w );
    self menu_say( "^2dropped" );
    return true;
}

// ── Weapons ──────────────────────────────────────────────────────────────────
// data1 is the weapon's hashed name (#"ar_standard_t9" etc. - real T9 names from the
// dump), data2 the label. getweapon takes the hash, giveweapon + switch to it.

function private act_giveweapon( item, whash, label )
{
    w = getweapon( whash );

    if ( isdefined( w ) )
    {
        self giveweapon( w );
        self switchtoweapon( w );
        self menu_say( "^2gave " + label );
    }
    else
    {
        self menu_say( "^1weapon not found: " + label );
    }

    return true;
}

// ── Cosmetics — force-applied via builtins, so they work regardless of whether
//    the item is actually unlocked/owned (that is the point of the menu). ──────

function private act_camo( item, id )
{
    w = self getcurrentweapon();
    if ( isdefined( w ) )
        self setcamo( w, id );
    self menu_say( "^2camo " + id + " on current weapon" );
    return true;
}

// Clear the per-slot customization so an operator/outfit change looks clean. All
// confirmed builtins; mirrors the Atian menu's func_skin/func_outfit.
function private cos_clear()
{
    self function_ab96a9b5( "head", 0 );
    self function_ab96a9b5( "headgear", 0 );
    self function_ab96a9b5( "arms", 0 );
    self function_ab96a9b5( "torso", 0 );
    self function_ab96a9b5( "legs", 0 );
    self function_ab96a9b5( "palette", 0 );
    self function_ab96a9b5( "warpaint", 0 );
    self function_ab96a9b5( "decal", 0 );
}

function private act_skin( item, id )
{
    self setspecialistindex( id );
    self setcharacteroutfit( 0 );
    self setcharacterwarpaintoutfit( 0 );
    self cos_clear();
    self menu_say( "^2operator " + id );
    return true;
}

function private act_outfit( item, id )
{
    self setcharacteroutfit( id );
    self setcharacterwarpaintoutfit( 0 );
    self cos_clear();
    self menu_say( "^2outfit " + id );
    return true;
}

// loot_fakeall is the engine dvar cwpatch sets at launch to fake-unlock loot; it is
// NOT in the dump, so a mid-match set is best-effort and mostly touches frontend menus.
// The camo/operator/outfit pages already apply any item regardless of ownership, which
// is the real in-match "use anything". Full unlock = cwpatch / CW_Soft_Unlock.dll
// (docs/notes/unlock-dlls.md).
function private act_unlockall( item )
{
    setdvar( #"loot_fakeall", 1 );
    self menu_say( "^3loot_fakeall=1 - best-effort; cwpatch does the real unlock" );
    return true;
}


// ── Map ──────────────────────────────────────────────────────────────────────

function private act_map_method( item )
{
    method = cfg_map_method() ? 0 : 1;
    setdvar( #"gf_map_method", method );
    item.activated = method;
    self menu_say( method ? "^2map method: SESSION - lobby follows, restart via lobby or F7" : "^3map method: CARRY - load-time only, lobby stays stale, F7 ONLY" );
    return true;
}

function private act_map( item, map_name )
{
    current = tolower( getdvarstring( #"sv_mapname" ) );

    if ( current == map_name )
    {
        self menu_say( "^3already on " + map_name );
        return true;
    }

    self menu_say( "^3loading " + map_name + "..." );

    // Threaded onto the PLAYER with no endons. See the header: this satisfies
    // both the endon theory (A4) and the self=player theory (A4 run 4) at once,
    // without deciding between them.
    self thread do_map_switch( map_name );
    return false;
}

// Map AND gametype in one SESSION switch - the "12v12 layouts" entries, whose map
// scripts only open the large boundary for a 10v10/12v12 gametype string. Always the
// session route: the map() carry cannot carry a gametype at all (roadmap Goal B).
function private act_map_gt( item, map_name, gametype )
{
    self menu_say( "^3loading " + map_name + " as " + gametype + "..." );
    self thread do_session_switch( map_name, gametype );
    return false;
}

function private do_map_switch( map_name )
{
    if ( cfg_map_method() == 0 )
    {
        // The legacy carry - the Atian Menu's func_set_map, call for call. Load-time
        // only: the lobby keeps its old map and a lobby-route restart discards it.
        map( map_name );
        wait( 1 );
        switchmap_switch();
        return;
    }

    // Keep the current gametype, change the map.
    do_session_switch( map_name, tolower( getdvarstring( #"g_gametype" ) ) );
}

// ✅ VERIFIED 2026-09-12 (docs/notes/session-switch.md): what stock's own transitions
// call. The SESSION moves - lobby, scoreboard and slot budget follow - which the map()
// carry never did. Runs on the PLAYER with no endons (see the header). The wait is
// the one Zombies uses rather than the single network frame the Atian menu uses.
function private do_session_switch( map_name, gametype )
{
    switchmap_load( map_name, gametype );
    level waittilltimeout( 25, #"switchmap_preload_finished" );
    switchmap_switch();
}

// ── Gametype ─────────────────────────────────────────────────────────────────

function private act_gametype( item, gt )
{
    current = tolower( getdvarstring( #"g_gametype", "" ) );

    if ( current == gt )
    {
        self menu_say( "^3already " + gt );
        return true;
    }

    // Real engine builtin, no stock caller (cw-builtins.md sec 2); lobby_probe linked
    // and ran with it. Refusing here beats handing switchmap_load a name the engine
    // does not know and finding out what that does to a live session.
    if ( !isvalidgametype( gt ) )
    {
        self menu_say( "^1engine rejects gametype " + gt );
        return true;
    }

    map_name = tolower( getdvarstring( #"sv_mapname", "" ) );
    self menu_say( "^3switching to " + gt + " on " + map_name + "..." );
    self thread do_session_switch( map_name, gt );
    return false;
}
