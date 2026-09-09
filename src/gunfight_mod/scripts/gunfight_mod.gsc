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
        // ── All four VERIFIED IN-GAME 2026-09-08 ────────────────────────────────
        // 3v3 Gunfight carried onto Zoo, 60s rounds, round timed out cleanly,
        // correct HUD, clean return to lobby. See docs/notes/menu-map.md.
        #zones_guard:    1,   // level.zones = [] so nothing can index it undefined
        #timelimit_fix:  1,   // LOAD-BEARING: reach function_c4915ac, skip the crashing overtime().
                              // ✅ VERIFIED: a round ran to zero and ended on the health decision.
                              // First time that path was ever exercised - every prior clean match
                              // ended by elimination and never reached expiry.
        #presentation:   1,   // the 5 symptoms (latch flags, HUD, music, round_start LUI). ✅ HUD
                              // confirmed. Overtime is absent and that is CORRECT - timelimit_fix
                              // deliberately skips the crashing overtime().
        #timer_override: 1,   // ON. The old comment said "only needed above 60s, the rules menu
                              // exposes 0/20/30/40/50/60s" - true in a plain lobby, FALSE once the
                              // map is carried. Measured: a carry RESETS the rules-menu value to 30,
                              // because it re-initialises gametype settings. The override survives
                              // because mod_apply() reruns on every on_start_gametype. Under a carry
                              // it is needed at ANY value, including ones the menu offers.
        #timer_minutes:  1,   // 1 minute = 60s. gettimelimit() returns MINUTES; range [0, 1440]

        // ── TEAM SIZE ── ✅ VERIFIED IN-GAME 2026-09-08 (test L6, run 2) ────────
        // 4v4 filled with bots and SURVIVED the round boundary - the boundary that
        // had been reverting every earlier attempt back to 3v3.
        //
        // `maxplayers` is a plain-named gametype setting reading 2x the per-side
        // size (measured: 6 in a 3v3 lobby, 4 in a normal one). It has NO rules-menu
        // row in Gunfight - L1 walked every page - so setgametypesetting() is the
        // only way to reach it.
        //
        // ⚠ This supersedes `maxsquadplayers`, which the project chased for a long
        //   time and which probes 6 and 12 both measured at 0 in every Gunfight
        //   lobby. It is unused here. Do not re-open it.
        //
        // ⚠ BOUNDED BY com_maxclients, which is NOT 8 and NOT fixed - it tracks the
        //   playlist. Measured: 10 in a 3v3 lobby, 8 in a normal one. So the ceiling
        //   depends on which lobby you started in:
        //     3v3 Gunfight lobby (com_maxclients 10) -> 5 per side, zero casters
        //     normal Gunfight lobby (com_maxclients 8) -> 4 per side, zero casters
        //   Casters spend from the same budget, at most 2. clamp_team_size() below
        //   enforces this against the live dvar rather than a hardcoded number.
        #team_size_override: 1,
        #team_size:          4   // PER SIDE. 4 = 4v4. See the clamp above before raising.
    };
}

// Never ask the session for more clients than it has slots for. com_maxclients is
// read-only from script (7 refs, all getdvarint) but it is READABLE, so the bound
// is measured at runtime instead of assumed - which is precisely the mistake that
// had "com_maxclients == 8" recorded as a law for most of this project's life.
function private clamp_team_size( per_side )
{
    budget = getdvarint( #"com_maxclients", 0 );

    if ( budget <= 0 )
    {
        return per_side;   // unreadable: trust the caller rather than clamp to zero
    }

    ceiling = int( budget / 2 );

    if ( per_side > ceiling )
    {
        return ceiling;
    }

    return per_side;
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

    // Team size. Re-applied on every on_start_gametype, exactly like the timer
    // override and for the same reason: a map carry re-initialises gametype
    // settings, and mod_apply() running per round is what makes the value stick.
    //
    // ✅ L6 measured that the setting itself SURVIVES a round boundary unaided
    //    (probe 3 read 8 on round 2 with no write that round). Re-applying is
    //    therefore belt-and-braces against the CARRY, not against the boundary.
    if ( cfg.team_size_override )
        setgametypesetting( #"maxplayers", clamp_team_size( cfg.team_size ) * 2 );

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
