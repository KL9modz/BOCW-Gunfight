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
//     gf_map_method     0 carry (map, the proven Atian call) / 1 session (switchmap_load)
//     gf_spawn_guard    0 off (default) / 1 on - reposition to central real spawns (untested)
//     gf_spawn_diag     1 on (default) - emit 60=armed(N) / 61=inert via iprintlnbold
//     gf_roundwinlimit  -1 leave stock (default) / N first-to-N rounds
//     gf_roundlimit     -1 leave stock (default) / N round cap
//     gf_rounds_loadout -1 leave stock (default) / N rounds per loadout rotation
//     gf_menu_lines     items per page, default 2 (what the Atian author chose for MP)
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
//     team size via maxplayers                                        ✅ L6, bots
//     bot fill via bot::add_bot                                       ✅ C7
//     map_restart()                                                   ✅ B4
//     map carry via map() + switchmap_switch()                        ✅ the Atian carry
//     move a player via [[ level.autoassign ]]                        ⚠ C11 built, never run
//     loadout set via gunfightloadoutindex                            ⚠ B6 never run
//     spy plane value 3                                               ⚠ B7 never run
//     #spawn_guard central real-spawn reposition                      ⚠ ported, untested - solo first
//     match limits roundwinlimit/roundlimit/roundsperloadout          ✅ keys verified in source
//     move/spectate guard level.autoassign / level.spectator          ✅ hardened
//     map via switchmap_load( map, gametype )                         ⚠ B1 never run
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
#using scripts\mp_common\gametypes\gunfight;

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
function private cfg_map_method()    { return getdvarint( #"gf_map_method", 0 ); }
function private cfg_menu_lines()    { return getdvarint( #"gf_menu_lines", 2 ); }

// #spawn_guard (ported from gunfight_mod, adapted to dvars). Default OFF - test solo first.
function private cfg_spawn_guard()   { return getdvarint( #"gf_spawn_guard", 0 ); }
function private cfg_spawn_diag()    { return getdvarint( #"gf_spawn_diag", 1 ); }

// Match-length knobs. Sentinel -1 = leave the lobby's value untouched (only an explicit
// menu pick asserts control). Keys verified against gunfight.gsc / globallogic.gsc.
function private cfg_roundwinlimit()  { return getdvarint( #"gf_roundwinlimit", -1 ); }
function private cfg_roundlimit()     { return getdvarint( #"gf_roundlimit", -1 ); }
function private cfg_rounds_loadout() { return getdvarint( #"gf_rounds_loadout", -1 ); }

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

function private mod_apply()
{
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

    // Belt and braces for the menu across round boundaries: the Atian Menu's own
    // loop survives rounds in klaze's hands (game_ended fires once, at match end -
    // globallogic.gsc:2374), but level is rebuilt per round and this costs nothing.
    // menu_think endons on gfmenu_restart, so an old loop dies before a new one runs.
    foreach ( player in getplayers() )
    {
        if ( player ishost() && isdefined( player.gfmenu ) )
        {
            player thread menu_restart();
        }
    }
}

function private mod_ontimelimit()
{
    if ( level.var_31f5f23 !== 1 )
    {
        level.var_31f5f23 = 1;

        if ( isdefined( level.zones ) && level.zones.size > 0
             && isdefined( level.zones[ 0 ] ) && isdefined( level.zones[ 0 ].gameobject ) )
        {
            thread gunfight::overtime();
            return;
        }
    }

    gunfight::function_c4915ac();
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
    central = mod_nearest_k( pts, center, 12 );   // the most central real spawn structs

    // Split the central cluster into two sides by X so the teams are separated but close.
    xmed = mod_median_x( central );
    team1 = [];
    team2 = [];
    foreach ( p in central )
    {
        if ( p.origin[ 0 ] <= xmed )
            team1[ team1.size ] = p;
        else
            team2[ team2.size ] = p;
    }
    if ( team1.size == 0 )
        team1 = central;
    if ( team2.size == 0 )
        team2 = central;

    level.gfmenu_spawn = { #team1:team1, #team2:team2 };

    if ( cfg_spawn_diag() )
        mod_gf_emit( 60, pts.size );   // armed, N spawn points gathered
}

// Fires on every spawn (registered in __init__). No-op unless the flag is on and anchors
// were built this round. Repositions the player onto a central spawn for their team.
function private mod_spawn_place()
{
    if ( !cfg_spawn_guard() )
        return;

    if ( !isdefined( level.gfmenu_spawn ) )
        return;

    if ( !isplayer( self ) || !isdefined( self.team ) )
        return;

    if ( self.team == #"axis" )
        list = level.gfmenu_spawn.team2;
    else
        list = level.gfmenu_spawn.team1;

    if ( !isdefined( list ) || list.size == 0 )
        return;

    pt = list[ randomint( list.size ) ];

    if ( !isdefined( pt ) || !isdefined( pt.origin ) )
        return;

    self setorigin( pt.origin );

    if ( isdefined( pt.angles ) )
        self setplayerangles( pt.angles );
}

// []-construction, NOT bare array(): keys_init above documents why array() is a link-time
// risk in this file (zero precedent in stock MP scripts). Same rule applies here.
function private mod_gather_spawns()
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

    pts = [];

    foreach ( n in names )
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

function private mod_median_x( pts )
{
    xs = [];

    foreach ( p in pts )
        xs[ xs.size ] = p.origin[ 0 ];

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

function private menu_draw( txt )
{
    self iprintln( txt );
}

function private menu_say( txt )
{
    self iprintlnbold( txt );
}

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
function private menu_item( menu_id, name, action, data1 = undefined, data2 = undefined )
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
        #data2: data2
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
                ts = nts + 5000;
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

function private menu_render( lines )
{
    menu = self menu_current();

    if ( !isdefined( menu ) )
    {
        for ( i = 0; i < lines + 1; i++ )
        {
            self menu_draw( "" );
        }

        return;
    }

    if ( menu.items.size == 0 )
    {
        self menu_draw( "^1---- " + menu.name + " (empty) ----" );
        index_end = 1;
    }
    else
    {
        page = int( menu.cursor / lines );
        maxpage = int( ( menu.items.size - 1 ) / lines ) + 1;
        self menu_draw( "^1---- " + menu.name + " (" + ( page + 1 ) + "/" + maxpage + ") ----" );

        index_start = lines * page;
        index_end = int( min( lines * ( page + 1 ), menu.items.size ) );

        for ( i = index_start; i < index_end; i++ )
        {
            it = menu.items[ i ];
            prefix = ( menu.cursor == i ) ? "^2-> ^1" : "^1- ";
            suffix = it.activated ? "^0 (ON)" : "";
            self menu_draw( prefix + it.name + suffix );
        }
    }

    end_space = lines - ( index_end % lines );

    if ( end_space != lines )
    {
        for ( i = 0; i < end_space; i++ )
        {
            self menu_draw( "" );
        }
    }
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
    self menu_item( "teams", "2v2", &act_team_size, 2 );
    self menu_item( "teams", "3v3", &act_team_size, 3 );
    self menu_item( "teams", "4v4", &act_team_size, 4 );
    self menu_item( "teams", "5v5", &act_team_size, 5 );
    self menu_item( "teams", "Fill with bots", &act_fill_bots );
    self menu_item( "teams", "Remove all bots", &act_remove_bots );

    // ── Players — rebuilt from getplayers() every time the page opens ────────
    self menu_add( "players", "Players", "start_menu", 1, &players_enter );

    // ── Round ────────────────────────────────────────────────────────────────
    self menu_add( "round", "Round", "start_menu", 1 );
    self menu_item( "round", "Timer 20s", &act_timer, 20 );
    self menu_item( "round", "Timer 30s", &act_timer, 30 );
    self menu_item( "round", "Timer 40s", &act_timer, 40 );
    self menu_item( "round", "Timer 60s", &act_timer, 60 );
    self menu_item( "round", "Timer 90s", &act_timer, 90 );
    self menu_item( "round", "Timer 120s", &act_timer, 120 );
    self menu_item( "round", "Restart match", &act_restart );

    // ── Loadout set — B6, never run ──────────────────────────────────────────
    self menu_add( "loadout", "Loadout", "start_menu", 1 );
    self menu_item( "loadout", "Default", &act_loadout, 0 );
    self menu_item( "loadout", "Snipers", &act_loadout, 1 );
    self menu_item( "loadout", "Blueprints", &act_loadout, 2 );
    self menu_item( "loadout", "Melee", &act_loadout, 3 );

    // ── Spy plane — value 3 is the one the rules menu hides. B7, never run ───
    self menu_add( "spyplane", "Spy plane", "start_menu", 1 );
    self menu_item( "spyplane", "Off", &act_spyplane, 0 );
    self menu_item( "spyplane", "On", &act_spyplane, 1 );
    self menu_item( "spyplane", "Shared - hidden value", &act_spyplane, 3 );

    // ── Spawns — #spawn_guard. Default OFF, UNTESTED: test SOLO first ─────────
    self menu_add( "spawns", "Spawns", "start_menu", 1 );
    self menu_item( "spawns", "Spawn guard OFF", &act_spawn_guard, 0 );
    self menu_item( "spawns", "Spawn guard ON (test solo)", &act_spawn_guard, 1 );

    // ── Match — first-to / round cap / loadout rotation. Keys verified in source ─
    self menu_add( "match", "Match", "start_menu", 1 );
    self menu_item( "match", "First to 2", &act_roundwinlimit, 2 );
    self menu_item( "match", "First to 4", &act_roundwinlimit, 4 );
    self menu_item( "match", "First to 6", &act_roundwinlimit, 6 );
    self menu_item( "match", "First to 10", &act_roundwinlimit, 10 );
    self menu_item( "match", "Round cap 6", &act_roundlimit, 6 );
    self menu_item( "match", "Round cap 10", &act_roundlimit, 10 );
    self menu_item( "match", "Loadout rotate 1", &act_rounds_loadout, 1 );
    self menu_item( "match", "Loadout rotate 2", &act_rounds_loadout, 2 );
    self menu_item( "match", "Loadout rotate 3", &act_rounds_loadout, 3 );

    // ── Map ──────────────────────────────────────────────────────────────────
    self menu_add( "map", "Map", "start_menu", 1 );
    self menu_item( "map", "Method: carry / session", &act_map_method );
    self menu_item( "map", "Zoo - verified", &act_map, "mp_zoo_rm" );
    self menu_add( "map_all", "All maps", "map", 1 );

    // docs/reference/atian-menu-maps.txt. ⚠ Not a safety list: Hijacked broke the
    // session once for a reason nobody has established, and mapexists() cannot
    // guard it (returns 1 for everything - B5).
    self menu_item( "map_all", "Amerika", &act_map, "mp_amerika" );
    self menu_item( "map_all", "Apocalypse", &act_map, "mp_apocalypse" );
    self menu_item( "map_all", "Armada", &act_map, "mp_black_sea" );
    self menu_item( "map_all", "Cartel", &act_map, "mp_cartel" );
    self menu_item( "map_all", "Checkmate", &act_map, "mp_clhanger" );
    self menu_item( "map_all", "Drive-In", &act_map, "mp_drivein_rm" );
    self menu_item( "map_all", "Rush", &act_map, "mp_dune" );
    self menu_item( "map_all", "Echelon", &act_map, "mp_echelon" );
    self menu_item( "map_all", "Express", &act_map, "mp_express_rm" );
    self menu_item( "map_all", "Firebase Z", &act_map, "mp_firebase" );
    self menu_item( "map_all", "^3! Hijacked", &act_map, "mp_hijacked_rm" );
    self menu_item( "map_all", "Jungle", &act_map, "mp_jungle_rm" );
    self menu_item( "map_all", "KGB", &act_map, "mp_kgb" );
    self menu_item( "map_all", "Mall", &act_map, "mp_mall" );
    self menu_item( "map_all", "Miami", &act_map, "mp_miami" );
    self menu_item( "map_all", "Miami Strike", &act_map, "mp_miami_strike" );
    self menu_item( "map_all", "Moscow", &act_map, "mp_moscow" );
    self menu_item( "map_all", "Nuketown", &act_map, "mp_nuketown6" );
    self menu_item( "map_all", "Paintball", &act_map, "mp_paintball_rm" );
    self menu_item( "map_all", "Raid", &act_map, "mp_raid_rm" );
    self menu_item( "map_all", "WMD", &act_map, "mp_russianbase_rm" );
    self menu_item( "map_all", "Satellite", &act_map, "mp_satellite" );
    self menu_item( "map_all", "Slums", &act_map, "mp_slums_rm" );
    self menu_item( "map_all", "Amsterdam", &act_map, "mp_sm_amsterdam" );
    self menu_item( "map_all", "U-Bahn", &act_map, "mp_sm_berlin_tunnel" );
    self menu_item( "map_all", "Mansion", &act_map, "mp_sm_central" );
    self menu_item( "map_all", "Dept Store", &act_map, "mp_sm_deptstore" );
    self menu_item( "map_all", "Diesel", &act_map, "mp_sm_finance" );
    self menu_item( "map_all", "Game Show", &act_map, "mp_sm_game_show" );
    self menu_item( "map_all", "Gas Station", &act_map, "mp_sm_gas_station" );
    self menu_item( "map_all", "Market", &act_map, "mp_sm_market" );
    self menu_item( "map_all", "Vault", &act_map, "mp_sm_vault" );
    self menu_item( "map_all", "Garrison", &act_map, "mp_tank" );
    self menu_item( "map_all", "Crossroads", &act_map, "mp_tundra" );
    self menu_item( "map_all", "Village", &act_map, "mp_village_rm" );
    self menu_item( "map_all", "Zoo", &act_map, "mp_zoo_rm" );
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

// ── Map ──────────────────────────────────────────────────────────────────────

function private act_map_method( item )
{
    method = cfg_map_method() ? 0 : 1;
    setdvar( #"gf_map_method", method );
    item.activated = method;
    self menu_say( method ? "^3map method: SESSION (switchmap_load - B1, unverified)" : "^2map method: CARRY (map - verified)" );
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

function private do_map_switch( map_name )
{
    if ( cfg_map_method() == 0 )
    {
        // The proven carry - the Atian Menu's func_set_map, call for call.
        map( map_name );
        wait( 1 );
        switchmap_switch();
        return;
    }

    // B1's candidate: what stock's own transitions call, with the gametype, and
    // with the wait Zombies uses rather than the one network frame the menu uses.
    gametype = tolower( getdvarstring( #"g_gametype" ) );
    switchmap_load( map_name, gametype );
    level waittilltimeout( 25, #"switchmap_preload_finished" );
    switchmap_switch();
}
