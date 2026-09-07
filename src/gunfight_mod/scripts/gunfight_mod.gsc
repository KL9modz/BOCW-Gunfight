// ─────────────────────────────────────────────────────────────────────────────
// BOCW Gunfight mod — additive, zero stock files modified.
//
// Hook: scripts\mp_common\bb.gsc, mode=mp  (see ../gsc.conf, docs/notes/mp-load-path.md)
// Loads via: autoexec -> system::register -> callback::on_start_gametype(&mod_apply)
//            mod_apply fires at globallogic.gsc:5536, BEFORE gunfight onstartgametype
//            (:5537) and the timer loop (:5539), and AFTER gametype_init installs the
//            stock pointer (gunfight.gsc:58) — so our reassignment wins deterministically.
//
// All line refs are against bocw-source@edd94bd.
//
// ⚠ PORTED TO T9 DIALECT 2026-09-07. This file was written in t7-compiler-custom
//   dialect (#include, no `function` keyword, bare `autoexec name()`) and is built with
//   ACTS. hello_world.gsc carried the same defects and crashed the game at script link.
//   Structure now mirrors stock bb.gsc:12 exactly:
//     #using / `function` on every definition / `function private autoexec` /
//     system::register with FIVE args and a HASHED name.
//   Stock uses `private` on all 859 __init__system__ precisely so identically-named
//   autoexecs cannot collide; ours was the only non-private one in the process.
//
// ⚠ EXPOSURE: injecting this begins host-side exposure. Read docs/notes/tac-risk-model.md
//   first. Bots before humans. Enable ONE stage at a time (config below).
//
// ⚠ NOT YET INJECTED. hello_world.gsc must confirm the hook fires in a custom Gunfight
//   lobby first. The compile-time risk over the hashed stock names (function_c4915ac,
//   var_31f5f23, var_a236b703, var_61952d8b) is CLOSED — ACTS 3.3.0 resolves them against
//   dump edd94bd on both machines — but resolving is not running. The inline FALLBACK
//   notes are kept as insurance against a dump or ACTS version bump.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\clientfield_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;
#using scripts\core_common\music_shared;
#using scripts\mp_common\gametypes\gunfight;

#namespace gunfight_mod;

function private autoexec __init__system__()
{
    system::register( #"gunfight_mod", &__init__, undefined, undefined, undefined );
}

// ── Staged rollout switches (CLAUDE.md Phase 3: one change at a time) ──
// Flip 1/0 and recompile+reinject. Recommended order, bots first:
//   1) zones_guard only   2) + timelimit_fix (LOAD-BEARING)
//   3) + presentation     4) timer_override only if you want >60s
//
// ⚠ This is a FUNCTION, not a one-time assignment in __init__, and that is load-bearing.
//    See mod_apply().
function private default_config()
{
    return {
        #zones_guard:    1,   // level.zones = [] so nothing can index it undefined
        #timelimit_fix:  1,   // LOAD-BEARING: reach function_c4915ac, skip the crashing overtime()
        #presentation:   1,   // the 5 symptoms (latch flags, HUD, music, round_start LUI)
        #timer_override: 0,   // OFF — the rules menu already exposes 0/20/30/40/50/60s. Only
                              // needed above 60s. Phase 0 T0.2 confirmed the menu setting is live.
        #timer_minutes:  1    // used only when timer_override == 1  (range [0, 1440])
    };
}

function private __init__()
{
    level.gfmod = default_config();
    callback::on_start_gametype( &mod_apply );
}

// Runs each time the gametype starts (per round in round-based Gunfight, via map
// fast-restart — the hello-world's on-screen counter confirms the cadence).
function private mod_apply()
{
    // ⚠⚠ SELF-HEAL, DO NOT REMOVE. `level` is torn down and rebuilt every round — measured
    //    2026-09-07 with src/mp_probe/: a level.* counter guarded by !isdefined reads 1 on
    //    EVERY round, so it is undefined at each round start.
    //
    //    If the config were assigned only in __init__ (which runs once at script link), it
    //    would be undefined from round 2 onward, `cfg` would be undefined, and every
    //    cfg.* check below would silently no-op — including timelimit_fix, whose absence
    //    is only felt on the exact round where the crashing overtime() path fires.
    //    A silent round-2 regression in the load-bearing switch is the worst available
    //    failure mode, so re-establish the config here rather than trusting __init__.
    //
    //    Guarded rather than unconditional so a deliberate runtime override survives.
    //    ⚠ UNRESOLVED: whether the script RE-LINKS each round (in which case __init__ re-runs
    //    and this guard is redundant) or links once (in which case it is essential). This
    //    costs nothing either way. src/mp_probe/ probe 8 distinguishes them.
    if ( !isdefined( level.gfmod ) )
    {
        level.gfmod = default_config();
    }

    cfg = level.gfmod;

    // ✅ VERIFIED NECESSARY, not merely defensive. `level.zones = zones` is assigned at
    // gunfight.gsc:907 and NOWHERE ELSE — on the success path only, after the size check.
    // When setupzones() returns false, level.zones is never assigned and stays UNDEFINED
    // for the entire match. Measured 2026-09-07: a stock Gunfight map (ICBM) returned zero
    // zone entities, so that path is live on shipping maps, not just modded ones.
    if ( cfg.zones_guard && !isdefined( level.zones ) )
        level.zones = [];

    // THE fix. Stock installed &ontimelimit at gunfight.gsc:58 during gametype_init;
    // we overwrite it here, before the timer loop starts at globallogic.gsc:5539.
    if ( cfg.timelimit_fix )
        level.ontimelimit = &mod_ontimelimit;

    // Optional: widen the round timer beyond the menu's published 0/20/30/40/50/60s.
    // Stock gettimelimit (gunfight.gsc:1137) clamps to [level.timelimitmin, timelimitmax]
    // = [0, 1440] minutes, so anything in range is accepted.
    if ( cfg.timer_override )
        level.gettimelimit = &mod_gettimelimit;

    // Restore the presentation work that gunfight onstartgametype skips at
    // gunfight.gsc:119 (`if (!setupzones()) return;`).
    //
    // ⚠ This was described as the "unlocked map" case. That was WRONG — it early-returns
    // ALWAYS in custom matches. Measured 2026-09-07: two stock Gunfight maps, ICBM and
    // Amsterdam, both report ZERO gunfight_zone_center entities in a private lobby, so
    // setupzones() returns false on stock maps too. This switch is therefore not polish for
    // modded maps — it is what makes custom Gunfight presentationally correct at all, on
    // every map.
    if ( cfg.presentation )
        mod_presentation_fixups();
}

// ── The load-bearing timer fix ───────────────────────────────────────────────
// Stock ontimelimit() (gunfight.gsc:915) threads overtime(), which dereferences
// level.zones[0] (gunfight.gsc:944) and dies before setgameendtime() on any map
// without gunfight_zone_center entities. Preserve stock overtime ONLY where a real
// zone exists; otherwise reach the stock health decision directly, one tick earlier
// than the stock crash-and-recover and without the exception.
function private mod_ontimelimit()
{
    if ( level.var_31f5f23 !== 1 )
    {
        level.var_31f5f23 = 1;

        if ( isdefined( level.zones ) && level.zones.size > 0
             && isdefined( level.zones[ 0 ] ) && isdefined( level.zones[ 0 ].gameobject ) )
        {
            thread gunfight::overtime();   // zoned (stock) map: leave stock overtime intact
            return;
        }
        // unlocked map: no zone -> fall through and decide now
    }

    // function_c4915ac (gunfight.gsc:1090): sums each team's player.health, endround()s
    // the higher side, handles the draw. Non-private, no args. DO NOT rewrite this.
    // FALLBACK if `gunfight::function_c4915ac` will not resolve at compile time: inline it —
    //   a = 0; foreach (p in getplayers(#"allies")) a += p.health;
    //   b = 0; foreach (p in getplayers(#"axis"))   b += p.health;
    //   if (a > b) { endround(#"allies", 1); return; }
    //   if (a < b) { endround(#"axis", 1);   return; }
    //   thread gunfight::function_c4915ac();  // or replicate the draw branch
    gunfight::function_c4915ac();
}

// ── Optional round-timer override ────────────────────────────────────────────
function private mod_gettimelimit()
{
    return level.gfmod.timer_minutes;
}

// ── Presentation fixes: the five symptoms of the early return ────────────────
// Replicates gunfight onstartgametype's skipped tail (gunfight.gsc:124-135).
function private mod_presentation_fixups()
{
    // Round-2+ round-start music (gunfight.gsc:124-127).
    if ( !util::isfirstround() )
        music::setmusicstate( "gunfight_roundstart" );

    // One-shot latches that pre-suppress Control-mode mechanics (gunfight.gsc:131-135).
    // Consumed by player_killed.gsc:2483/2503 (no-lives / low-lives VO + HUD) and
    // player_utils.gsc:151 (selects the lives-HUD data source). NOT vestigial.
    if ( isdefined( level.teams ) )
    {
        foreach ( team, _ in level.teams )
        {
            level.var_a236b703[ team ] = 1;
            level.var_61952d8b[ team ] = 1;
        }
    }

    // "No respawns left" HUD init (gunfight.gsc:129 -> private function_8cac4c76,
    // body replicated here because it is private and cannot be called cross-script).
    thread mod_norespawns_hud();

    // Round-start UI event (gunfight.gsc:137).
    luinotifyevent( #"round_start" );
}

function private mod_norespawns_hud()
{
    waitframe( 1 );
    clientfield::set_world_uimodel( "hudItems.team1.noRespawnsLeft", 1 );
    clientfield::set_world_uimodel( "hudItems.team2.noRespawnsLeft", 1 );
}
