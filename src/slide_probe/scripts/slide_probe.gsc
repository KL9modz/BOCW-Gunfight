// slide_probe — measure every slide, then try the script-side SLIDE DISTANCE levers.
//
//   .\tools\check-gsc.ps1 .\src\slide_probe\scripts\slide_probe.gsc
//   acts gscc ... + tools/strip-strhdr.ps1 -> /c/bocw/payloads/slide_probe.gscc
//
// ONE payload per launch: this runs INSTEAD of gunfight_menu (B9). Built 2026-09-20, NEVER RUN.
//
// WHAT THE ENGINE DOES (read off the live exe 2026-09-20, docs/notes/slide.md):
//   slide start:  velocity = dir * T[0].speed * weaponScale * (1 - slide_subsequentslidescale)^n
//                 n = slides chained within 1250 ms of the previous slide START (ps+0x15d4)
//   slide end:    a fixed DURATION (T[0].ms * per-player AE stat 0xc4) — or |vel| < a floor
//   in-slide:     only friction shapes the speed; nothing re-clamps it (PM_SlideMove is weapon
//                 raise timing). So a velocity boost applied right after slide_begin should carry
//                 straight into distance. THAT is what this probe measures — not assumes.
//
// LEVERS (dvars, read live, so the control app's raw `set` or a console `set` changes them mid-match):
//   gf_slide        percent of the engine's slide-start speed, applied once at slide_begin. 100 = stock
//                   (measure the stock numbers FIRST). 150 / 200 / 300 are the test points.
//   gf_slidehold    1 = re-assert the boosted horizontal speed every server frame WHILE isonslide()
//                   (counteracts friction: the slide keeps its entry speed until the engine's
//                   duration ends). 0 = one boost at the start only.
//   gf_slidechain   1 = setdvar slide_subsequentslidescale 0 (chained slides keep full speed),
//                   0 = restore the value read at match start (stock reads 0.1).
//   gf_slidephd     1 = every spawn gets setperk("specialty_mod_phdflopper") — the perk index the
//                   slide code tests (0x93): chained penalty 5% instead of 10% + a different speed
//                   floor. Answers "does the ZM perk branch apply in MP".
//
// THE LINE (host iprintln, every 2 s, one continuous line — klaze reads the screen):
//   SLIDE pct:100 hold:0 chain:0 phd:0 sub:0.10 | n:3 ev:3 poll:3 | last d:312 t:720 v0:402 v1:155 | best d:340
//     pct/hold/chain/phd  the four levers as read this tick        sub  slide_subsequentslidescale, live
//     n     slides measured this match (host only)                 ev   slide_begin NOTIFIES received
//     poll  slides detected by the isonslide() edge (ev vs poll says whether the notify reaches MP script)
//     last  distance (units, 2D), duration ms, entry speed, exit speed of the host's last slide
//     best  longest slide distance so far
//   Compare "last d" at pct 100 vs 200: if it roughly doubles, the lever is real.

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace slide_probe;

function private autoexec __init__system__()
{
    system::register( #"slide_probe", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &on_start );
    callback::on_spawned( &on_spawned );
}

function private on_start()
{
    level.sp_n = 0;
    level.sp_ev = 0;
    level.sp_poll = 0;
    level.sp_last = "-";
    level.sp_best = 0;

    // The stock value, captured once so chain:0 restores exactly what the match started with
    // (the exe registers 0.15; the live game read 0.1 on 2026-09-20 — something sets it).
    if ( !isdefined( level.sp_sub_stock ) )
        level.sp_sub_stock = getdvarfloat( #"slide_subsequentslidescale", 0.1 );

    level thread levers_think();
    level thread line_think();
}

// ── levers that are not per-slide ────────────────────────────────────────────────────────
function private levers_think()
{
    level endon( #"game_ended" );
    applied = -1;

    for ( ;; )
    {
        chain = getdvarint( #"gf_slidechain", 0 );

        if ( chain != applied )
        {
            setdvar( #"slide_subsequentslidescale", chain ? 0 : level.sp_sub_stock );
            applied = chain;
        }

        wait( 0.5 );
    }
}

function private on_spawned()
{
    if ( getdvarint( #"gf_slidephd", 0 ) )
        self setperk( "specialty_mod_phdflopper" );

    self thread slide_event_think();
    self thread slide_poll_think();
}

// ── per-slide: the engine's own notify (zm_perk_slider.gsc:197 waits on exactly this) ────
function private slide_event_think()
{
    self notify( #"sp_event_restart" );
    self endon( #"sp_event_restart" );
    self endon( #"disconnect" );
    self endon( #"death" );

    for ( ;; )
    {
        self waittill( #"slide_begin" );
        level.sp_ev++;
        self slide_boost();
    }
}

// ── per-slide: the isonslide() edge, one frame behind at worst. Also the measurer. ──────
function private slide_poll_think()
{
    self notify( #"sp_poll_restart" );
    self endon( #"sp_poll_restart" );
    self endon( #"disconnect" );
    self endon( #"death" );

    was = 0;

    for ( ;; )
    {
        on = self isonslide();

        if ( on && !was )
        {
            level.sp_poll++;
            self slide_boost();
            self thread slide_measure();
        }

        was = on;
        waitframe( 1 );
    }
}

// One boost per slide, whichever detector fires first. Horizontal only; z untouched.
function private slide_boost()
{
    if ( isdefined( self.sp_boosted ) && self.sp_boosted )
        return;

    self.sp_boosted = 1;
    pct = getdvarint( #"gf_slide", 100 );

    if ( pct <= 0 || pct == 100 )
        return;

    k = pct / 100;
    v = self getvelocity();
    self setvelocity( ( v[ 0 ] * k, v[ 1 ] * k, v[ 2 ] ) );
    self.sp_hold_speed = length( ( v[ 0 ] * k, v[ 1 ] * k, 0 ) );
}

// Measures the slide from this frame to the frame isonslide() drops (5 s cap), records the
// numbers for the line, and (gf_slidehold) re-asserts the boosted speed every frame meanwhile.
function private slide_measure()
{
    self endon( #"disconnect" );
    self endon( #"death" );

    t0 = gettime();
    o0 = self.origin;
    v = self getvelocity();
    v0 = int( length( ( v[ 0 ], v[ 1 ], 0 ) ) );

    while ( self isonslide() && gettime() - t0 < 5000 )
    {
        if ( getdvarint( #"gf_slidehold", 0 ) && isdefined( self.sp_hold_speed ) && self.sp_hold_speed > 0 )
        {
            cv = self getvelocity();
            h = length( ( cv[ 0 ], cv[ 1 ], 0 ) );

            if ( h > 1 && h < self.sp_hold_speed )
            {
                s = self.sp_hold_speed / h;
                self setvelocity( ( cv[ 0 ] * s, cv[ 1 ] * s, cv[ 2 ] ) );
            }
        }

        waitframe( 1 );
    }

    v = self getvelocity();
    v1 = int( length( ( v[ 0 ], v[ 1 ], 0 ) ) );
    d = int( distance2d( o0, self.origin ) );
    t = gettime() - t0;

    self.sp_boosted = 0;
    self.sp_hold_speed = 0;

    if ( self ishost() )
    {
        level.sp_n++;
        level.sp_last = "d:" + d + " t:" + t + " v0:" + v0 + " v1:" + v1;

        if ( d > level.sp_best )
            level.sp_best = d;
    }
}

// ── the one line ─────────────────────────────────────────────────────────────────────────
function private line_think()
{
    level endon( #"game_ended" );
    wait( 3 );

    for ( ;; )
    {
        host = util::gethostplayer();

        if ( isdefined( host ) )
        {
            host iprintln( "^3SLIDE ^7pct:" + getdvarint( #"gf_slide", 100 )
                + " hold:" + getdvarint( #"gf_slidehold", 0 )
                + " chain:" + getdvarint( #"gf_slidechain", 0 )
                + " phd:" + getdvarint( #"gf_slidephd", 0 )
                + " sub:" + getdvarfloat( #"slide_subsequentslidescale", -1 )
                + " ^5| ^7n:" + level.sp_n + " ev:" + level.sp_ev + " poll:" + level.sp_poll
                + " ^5| ^7last " + level.sp_last
                + " ^5| ^7best d:" + level.sp_best );
        }

        wait( 2 );
    }
}
