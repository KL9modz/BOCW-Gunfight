// ─────────────────────────────────────────────────────────────────────────────
// BOCW Gunfight mod — additive, zero stock files modified.
//
// Hook: scripts\mp_common\bb.gsc, mode=mp  (see ../gsc.conf, docs/notes/mp-load-path.md)
// Loads via: autoexec -> system::register -> callback::on_start_gametype(&mod_apply)
//            mod_apply fires at globallogic.gsc:5536, BEFORE gunfight onstartgametype
//            (:5537) and the timer loop (:5539), and AFTER gametype_init installs the
//            stock pointer (gunfight.gsc:58) — so our reassignment wins deterministically.
//
// All line refs are against bocw-source@edd94bd. Syntax matches the compiler's own
// T9 example (no `function` keyword; `#include`; `autoexec name()`; struct shorthand).
//
// ⚠ EXPOSURE: injecting this begins host-side exposure. Read docs/notes/tac-risk-model.md
//   first. Bots before humans. Enable ONE stage at a time (config below).
//
// ⚠ COMPILE-TIME RISK: this file references stock symbols by their atian-decompiler
//   hashed names (function_c4915ac, var_31f5f23, var_a236b703, var_61952d8b). The
//   t7-compiler is expected to round-trip these back to their hashes. If any fails to
//   resolve, see the FALLBACK notes inline (the health decision can be inlined; the
//   latch-flag names can be dropped — they are cosmetic, not load-bearing).
// ─────────────────────────────────────────────────────────────────────────────

#include scripts\core_common\callbacks_shared;
#include scripts\core_common\clientfield_shared;
#include scripts\core_common\system_shared;
#include scripts\core_common\util_shared;
#include scripts\core_common\music_shared;
#include scripts\mp_common\gametypes\gunfight;

#namespace gunfight_mod;

autoexec __init__system__()
{
    system::register( "gunfight_mod", &__init__, undefined, undefined );
}

__init__()
{
    // ── Staged rollout switches (CLAUDE.md Phase 3: one change at a time) ──
    // Flip 1/0 and recompile+reinject. Recommended order, bots first:
    //   1) zones_guard only   2) + timelimit_fix (LOAD-BEARING)
    //   3) + presentation     4) timer_override only if you want >60s (Phase 0 T0.2)
    level.gfmod = {
        #zones_guard:    1,   // defensive: level.zones = [] so nothing can index it undefined
        #timelimit_fix:  1,   // LOAD-BEARING: reach function_c4915ac, skip the crashing overtime()
        #presentation:   1,   // the 5 cosmetic symptoms (latch flags, HUD, music, round_start LUI)
        #timer_override: 0,   // OFF by default — Phase 0 T0.2 may show the menu already exposes this
        #timer_minutes:  1    // used only when timer_override == 1  (range [0, 1440])
    };

    callback::on_start_gametype( &mod_apply );
}

// Runs each time the gametype starts (per round in round-based Gunfight, via map
// fast-restart — the hello-world's on_start log count confirms the cadence).
mod_apply()
{
    cfg = level.gfmod;

    // Defensive only. With timelimit_fix on, overtime() is never threaded, so the
    // level.zones[0] crash site (gunfight.gsc:944) is already unreachable — this just
    // guarantees nothing else can index level.zones undefined either.
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

    // Restore the presentation work that gunfight onstartgametype skips when it early-
    // returns on an unlocked map (gunfight.gsc:119 `if (!setupzones()) return;`).
    if ( cfg.presentation )
        mod_presentation_fixups();
}

// ── The load-bearing timer fix ───────────────────────────────────────────────
// Stock ontimelimit() (gunfight.gsc:915) threads overtime(), which dereferences
// level.zones[0] (gunfight.gsc:944) and dies before setgameendtime() on any map
// without gunfight_zone_center entities. Preserve stock overtime ONLY where a real
// zone exists; otherwise reach the stock health decision directly, one tick earlier
// than the stock crash-and-recover and without the exception.
mod_ontimelimit()
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
mod_gettimelimit()
{
    return level.gfmod.timer_minutes;
}

// ── Presentation fixes: the five symptoms of the early return ────────────────
// Replicates gunfight onstartgametype's skipped tail (gunfight.gsc:124-135).
mod_presentation_fixups()
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

mod_norespawns_hud()
{
    waitframe( 1 );
    clientfield::set_world_uimodel( "hudItems.team1.noRespawnsLeft", 1 );
    clientfield::set_world_uimodel( "hudItems.team2.noRespawnsLeft", 1 );
}
