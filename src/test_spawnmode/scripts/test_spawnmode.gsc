// ─────────────────────────────────────────────────────────────────────────────
// TEST B8 — Gunfight's spawns above 3 per side. The cause is Gunfight's, not the map's.
//
// Hook: scripts\mp_common\bb.gsc, mode=mp  (see ../gsc.conf)
//
// ── THE DIAGNOSIS, AND KLAZE SUPPLIED THE CONTROL ────────────────────────────
// klaze, 2026-09-09: a lobby glitch he cannot reproduce has already put FOUR
// players on a Gunfight team, and it "causes other glitches such as incorrect
// spawns" - which he found odd, because "gunfight maps can support other modes
// like faceoff 6v6 and support proper spawns for those large lobbies."
//
// ✅ That is the control, and it is decisive. Same map, same spawn entities, 12
//    players, correct spawns. So the map is not the problem.
//
// Exactly four gametypes pin the flag:
//     prop.gsc:73  ·  sd.gsc:228  ·  gunfight.gsc:100  ·  vip.gsc:99
// The global default is 0 (globallogic.gsc:5146). Face Off is not among them.
//
// spawning::usestartspawns() (hashed/script/script_44b0b8420eabacad.gsc:504):
//     if ( is_true( level.alwaysusestartspawns ) ) return true;      <- Gunfight short-circuits HERE
//     if ( !is_true( level.usestartspawns ) )      return false;
//     return true;
//
// ⚠ Two facts make this bite Gunfight and nothing else:
//   1. Every other mode clears the per-round flag once the grace wave is over -
//      tdm.gsc:83 is the canonical line, and dm/conf/clean/infect/prop/dropkick/
//      fireteam all carry it. Gunfight has NO onspawnplayer at all, so it never
//      clears anything.
//   2. Gunfight is one-life-per-round, so EVERY spawn is a round-start spawn.
//      There is no "later spawn" that would ever fall through to normal selection.
//
//   Result: every player, every round, is drawn from a start-spawn list Treyarch
//   sized for 2 or 3 per side.
//
// ── AND KLAZE HAS ANSWERED AN OPEN QUESTION WITHOUT MEANING TO ───────────────
// .claude/CLAUDE.md asks: does the engine's function_77b7335( team, "start_spawn" )
// return undefined when start spawns run out (graceful - spawning_shared.gsc:295
// then falls through to normal selection) or hand back a bad point?
//
// ✅ ANSWERED: it does NOT return undefined. klaze saw WRONG spawns, not FAILED
//    spawns, and the fallback at spawning_shared.gsc:295 only fires
//    `if ( !isdefined( spawn ) )`. A wrong spawn means something was returned.
//    ⚠ Recorded as a measurement. "Wrong" has not been characterised further -
//    enemy start position, outside the play zone, and stacked-on-another-player
//    are all still open, and they are not the same bug.
//
// ── ⚠ THE CONTROL IS ALREADY RUN. klaze measured both halves. ───────────────
// Asked what "wrong" looked like, and then asked again because a first reading of
// "outside the play zone" suggested the start_spawn list might simply contain
// far-away entries meant for a bigger mode:
//
//   "It spawns people out of bounds when the team size is exceeded on gunfight
//    not tdm. When I play TDM face off on gunfight maps, the spawns are all good
//    and valid. That's why I said using tdm spawns for gunfight would be good."
//
// ✅ **Same maps. 12 players. All spawns valid.** So the TDM/default lists on those
//    maps are not the out-of-bounds ones - they are the known-good ones. The bad
//    points are specific to the path Gunfight takes, and only once the team size
//    is exceeded.
//
// ⚠ A previous revision of this file weakened mode 2 on the theory that the
//   default lists would carry the same far-flung points. **That theory is refuted
//   by the Face Off half of klaze's own observation** and has been removed rather
//   than left standing. Mode 2 is the fix, and it is the default below.
//
// ⚠ DO NOT RE-RUN MODE 0 AS A CONTROL. It has been run, twice over: Gunfight
//   breaks above 3 per side, Face Off on the same map at 6v6 does not. Mode 0 is
//   kept only to reproduce the failure deliberately if a later change needs a
//   baseline again.
//
// ── THE MODES ────────────────────────────────────────────────────────────────
//   0  off              stock. Control run - confirm the breakage before fixing it
//   1  tdm_style        clear the per-round flag after grace, exactly tdm.gsc:83.
//                       ⚠ Predicted NOT to fix it: Gunfight is one-life, so the
//                       grace wave IS every spawn. Included because if it DOES
//                       help, the model above is wrong and that matters more than
//                       the fix
//   2  fully_dynamic    ⬅ DEFAULT, AND THE FIX. Never use start spawns. All spawns
//                       go through function_99ca1277 against
//                       level.default_spawn_lists - the lists klaze has directly
//                       watched carry 12 players on these maps with no bad points.
//                       ⚠ Costs Gunfight's fixed symmetric openings. klaze has
//                       accepted that trade explicitly ("tdm spawns for gunfight
//                       would be good"); it is still a change in how the mode
//                       plays, not a free repair.
//   3  pin_to_team      FALLBACK. Cannot land outside the play zone, by construction.
//                       Places the overflow player next to a teammate who has
//                       already spawned, via self.var_b7cc4567 - a stock spawn
//                       override read at spawning_shared.gsc:290, BEFORE
//                       usestartspawns() is consulted, with precedent at
//                       warzone.gsc:336. The point is derived from where the team
//                       actually is, so it is in the zone whatever the map's
//                       spawn structs say.
//                       ⚠ Bunched, not pretty, and it can put someone in geometry
//                       if the offset direction is bad. It degrades gracefully:
//                       with no spawned teammate it does nothing and stock runs.
//
// ⚠ MODE 2 CHANGES HOW GUNFIGHT FEELS, and that is klaze's call, not this file's.
//   Gunfight's fixed symmetric openings are a design choice; dynamic spawns are
//   TDM's. At 4v4 on a Gunfight map dynamic is arguably what you want anyway, but
//   it is a trade and it should be made knowingly.
//
// ── HOW THE FLAG IS HELD ─────────────────────────────────────────────────────
// level.alwaysusestartspawns is set at gunfight.gsc:100, inside onstartgametype()
// (:97). Our hook fires at globallogic.gsc:5536 - BEFORE onstartgametype at :5537 -
// so a plain assignment in on_start_gametype would be overwritten one line later.
//
// So we wrap level.onspawnplayer instead. Default is
// &spawning::onspawnplayer (globallogic.gsc:523) and Gunfight never replaces it,
// so the wrapper is additive. It is invoked from globallogic_spawn.gsc:601.
//
// ⚠ spawning_squad.gsc:172 ALSO assigns level.onspawnplayer, and this project has
//   not traced whether that init runs before or after ours. If it runs after, our
//   wrapper is silently bypassed - which is exactly what probe 31 exists to catch.
//   Do not interpret "no change" as "the fix does not work" until 31 has printed.
//
// ── PROTOCOL ─────────────────────────────────────────────────────────────────
//  1. mode 2 (the default). Get 4 on a side - C7 bots are the cheap way - and
//     watch the spawns. They should look like Face Off does on that map.
//  2. ⚠ READ PROBE 31 FIRST. It counts wrapper invocations. A zero means
//     level.onspawnplayer was reassigned after us (spawning_squad.gsc:172 is the
//     suspect) and NOTHING here was ever in effect - which is not the same result
//     as "the fix did not work", and must not be recorded as one.
//  3. Still out of bounds with 31 counting up? Then the default lists are not the
//     answer either. Go to mode 3, which derives the point from where the team
//     actually is and cannot land outside the zone whatever the lists hold.
//  4. ⚠ Test a lobby return.
//
// Once mode 2 is confirmed this belongs in gunfight_mod as a switch, not here.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;
#using scripts\core_common\spawning_shared;
// ⚠ usestartspawns() and function_7a87efaa() are in the HASHED half of the
//   spawning namespace (script_44b0b8420eabacad.gsc), not in spawning_shared.gsc.
//   gunfight.gsc:3 and :16 pull in BOTH for exactly this reason - mirror it rather
//   than rely on transitive resolution through the #using at spawning_shared.gsc:3.
#using script_44b0b8420eabacad;

#namespace test_spawnmode;

function private autoexec __init__system__()
{
    system::register( #"test_spawnmode", &__init__, undefined, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &on_start );
}

function private default_config()
{
    return {
        // 0 = reproduce the failure · 1 = tdm_style · 2 = FIX · 3 = fallback
        // Defaults to 2. The control does not need re-running - klaze has measured
        // both halves of it (Gunfight breaks above 3, Face Off at 6v6 on the same
        // map does not), and making him reproduce a known failure costs a session
        // for nothing.
        #mode:   2,
        #report: 1
    };
}

function private on_start()
{
    cfg = default_config();

    level.var_gf_spawnmode = cfg.mode;
    level.var_gf_spawnhits = 0;

    // Capture whatever pointer is installed right now and call through it, rather
    // than assuming it is &spawning::onspawnplayer. If something replaced it before
    // us, this preserves that instead of silently dropping it.
    level.var_gf_prevspawn = level.onspawnplayer;
    level.onspawnplayer = &wrapped_onspawnplayer;

    if ( cfg.report )
    {
        level thread report();
    }
}

function private wrapped_onspawnplayer( predictedspawn )
{
    level.var_gf_spawnhits++;

    if ( level.var_gf_spawnmode === 3 )
    {
        // Only act on the overflow. Players 1..3 keep their stock start spawns, so
        // a map where the list is fine is left completely alone.
        mates = [];

        foreach ( other in getplayers( self.team ) )
        {
            if ( other != self && isalive( other ) )
            {
                mates[ mates.size ] = other;
            }
        }

        if ( mates.size >= 3 )
        {
            anchor = mates[ 0 ];

            // 48 units to the anchor's right. Far enough not to telefrag, close
            // enough that it is unambiguously the same spawn cluster.
            right = anglestoright( anchor.angles );

            self.var_b7cc4567 = { #origin:anchor.origin + vectorscale( right, 48 ), #angles:anchor.angles };
        }
    }
    else if ( level.var_gf_spawnmode === 2 )
    {
        // Both flags, because either one alone leaves usestartspawns() returning
        // true - the first short-circuits, the second is the fallthrough.
        level.alwaysusestartspawns = 0;
        level.usestartspawns = 0;
    }
    else if ( level.var_gf_spawnmode === 1 )
    {
        // tdm.gsc:83, transcribed. Gunfight has no equivalent line of its own.
        level.alwaysusestartspawns = 0;

        if ( spawning::usestartspawns() && !level.ingraceperiod && !level.playerqueuedrespawn )
        {
            spawning::function_7a87efaa();
        }
    }

    self [[ level.var_gf_prevspawn ]]( predictedspawn );
}

function private report()
{
    level endon( #"game_ended" );

    wait( 20 );

    for ( ;; )
    {
        // 30xxxxx  the mode actually in effect - confirms the config you think you built
        // 31xxxxx  wrapper invocations. ⚠ ZERO means level.onspawnplayer was
        //          reassigned after us (spawning_squad.gsc:172 is the suspect) and
        //          NOTHING in this test was ever in effect. Read this one first.
        // 32xxxxx  allies*100 + axis, so the team sizes are on screen next to the result
        emit( 30, level.var_gf_spawnmode );
        emit( 31, level.var_gf_spawnhits );
        emit( 32, getplayers( #"allies" ).size * 100 + getplayers( #"axis" ).size );

        wait( 15 );
    }
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

    wait( 3 );
}
