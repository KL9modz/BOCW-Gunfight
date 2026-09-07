# Gunfight on non-Gunfight maps

All line numbers refer to `bocw-source-main\scripts\mp_common\gametypes\gunfight.gsc`
unless stated. Gametype string is **`gunfight`** (enum `0x2f`).

## Headline: one hard map dependency

Gunfight needs the overtime capture zone. Nothing else about it is map-specific.

> ⚠⚠ **THIS HEADLINE IS IN DOUBT. Measured in-game 2026-09-07: a STOCK Gunfight map returned ZERO
> `gunfight_zone_center` entities.**
>
> `src/mp_probe/` read `getentarray("gunfight_zone_center","targetname").size` = **0** on **ICBM**,
> reached through the normal Gunfight rotation in a private match — not a modded or forced map. The
> match then played fine.
>
> Two things follow, and the second undermines the section below.
>
> 1. **It does not abort.** The early return costs only the presentation tail. `abort_level` is never
>    called from `gunfight.gsc`; its four call sites are in `spawning_shared`, `supplydrop`,
>    `globallogic_utils` and zm `spawnlogic`. The zone absence stays dormant until the round timer
>    expires, since `ontimelimit()` is the only path to `overtime()` and its `level.zones[0]`
>    dereference at `:944`. That match's `timelimit` setting read **0** — no limit — so it never
>    fired. **Zero zones is safe; zero zones *plus* a timer expiry is the bug.**
>
> 2. **The zone check cannot be the map gate.** If curated Gunfight maps also lack the entities, a
>    check that early-returns on them is not what limits the mode to ten maps. The limit is most
>    likely the menu/playlist layer — see [[dll-proxy]]. It also means the five presentation symptoms
>    are **not** an unlocked-map artifact; they affect stock private matches too.
>
> 🪦 **RESOLVED 2026-09-07 — n=2, and the headline above is DEAD.** Amsterdam also reads **0**.
>
> | Stock Gunfight map | how identified | zone entities |
> |---|---|---|
> | ICBM (`mp_sm_central`) | inferred from `tables/` asset themes | **0** |
> | Amsterdam (`mp_sm_amsterdam`) | codename **==** UI name, zero inference | **0** |
>
> Amsterdam was chosen precisely so the result would not depend on the `tables/` inference being
> right. It isn't load-bearing: the second map confirms independently.
>
> **The forced conclusion.** Stock Gunfight maps carry no `gunfight_zone_center` entities in
> private/custom matches, so `setupzones()` returns false and `onstartgametype()` early-returns on
> **every** map. Custom Gunfight is *always* running in the degraded state. And a condition true on
> every map distinguishes nothing — **this cannot be what limits the mode to ten maps.**
>
> **Do not re-open this for the map-unlock goal.** Three escape hatches were checked and all are
> closed: no spawner anywhere in the dump, no deleter in `gunfight.gsc`, no consumption in
> `setupzones()`.
>
> ⚠ **Scope, and it matters.** Measured in **private/custom matches only**. The entities plausibly
> *do* exist in matchmade Gunfight — that is how the shipped overtime feature works, and Onslaught
> reads them on these same maps. The likeliest remaining explanation is session- or playlist-level
> entity filtering at map load, which is engine-side and invisible to both machines from script.
>
> **What survives, and is now more important:** `zones_guard` and `presentation` are not modded-map
> polish. They repair every private Gunfight match on every map. See [[dll-proxy]] for where the real
> barrier lives.

### The zero is not a measurement artifact — both escape hatches closed

The probe reads ~8s after `on_start_gametype`, while stock reads *during* it. If anything consumed or
deleted the centers in between, a later read would return 0 with the model intact. It does not:

- **Nothing deletes them.** `grep -E 'delete\(\)|\bdelete\b'` across `gunfight.gsc` returns **zero**.
  `setupzones()`'s loop is entirely additive — it annotates `zone.trig`, `zone.trigorigin`, spawns an
  objectiveanchor script_model, creates a gameobject, sets clientfields, `notsolid()`s visuals.
- **Nothing spawns them either.** All four dump-wide references are `getentarray` **reads**.

So the entities persist for the life of the level, and the measured `0` is a real absence.

### Four consumers, not one — and they are shared map data

| Where | Gated? |
|---|---|
| `gunfight.gsc:813` (centers, server) | **no** — unconditional |
| `gunfight.gsc:836` (triggers, server) | no |
| `gunfight.csc:230` (triggers, client) | yes — `getgametypesetting( #"hash_4091f2d0019b1f4a" )`, shared with `control.csc:266` and `dom.csc:159` |
| `hashed/script/script_336275a0ba841d18.gsc:140` | yes — `getgametypesetting( #"hash_cd096e90260a26b" )` |

That fourth file is **Onslaught** — it sets `level.var_e2f95698 = #"zm_commander_onslaught"` and
`#using`s `zombie_utility`, `zombie_eye_glow`, `gib`. So `gunfight_zone_center` is shared map data
consumed by Gunfight, its client script, *and* the Zombies mode built on these maps. **A map lacking
them breaks more than Gunfight**, which makes a deliberate per-map omission less plausible.

⚠ Only the server-side read is ungated. Two of the four sit behind gametype settings — worth
remembering before concluding anything from a single consumer's behaviour.

### `setupzones()` has TWO failure paths — do not conflate them

`false` does not always mean "zero zones". It also returns false when zones *were* found but
`print_map_errors()` reports mis-triggered ones (the partial-zone case in **DANGER** below). For the
2026-09-07 match it genuinely was zero, because the probe counted the entities directly — but the two
cases have different causes and different fixes.

```gsc
// gunfight.gsc:119, inside onstartgametype()
if ( !setupzones() )
{
    return;              // :121  bails out of the whole function
}
```

`setupzones()` (`:827`) returns false when `getentarray("gunfight_zone_center","targetname")`
is empty — true of every map that isn't a shipped Gunfight map.

## This is almost certainly the round-timer bug — DERIVED

Observed in-game: *"on a non-standard map I had no control of the round timer
even though there's a menu option for it."* The early return at `:121` skips
everything below it:

| Skipped | Line | Effect |
|---|---|---|
| `level.zones = zones;` | :907 | **`level.zones` stays undefined all match** |
| `music::setmusicstate("gunfight_roundstart")` | :126 | no round-start music |
| `function_8cac4c76()` | :129 | `noRespawnsLeft` UI models never set |
| per-team `var_a236b703` / `var_61952d8b` | :131-135 | suppressed "last man" VO comes back |
| `luinotifyevent( #"round_start" )` | :137 | **the round-start LUI event never fires** |
| `function_d33c99f8()` (pushes `timeremaining`) | :145 | tournament HUD never initialised |

Then at time expiry it gets worse. `ontimelimit()` (`:915`) threads `overtime()`,
which does:

```gsc
zone = level.zones[ 0 ];                                     // :944  undefined
if ( zone.gameobject gameobjects::function_339d0e91() > 0 )  // :946  DEREFERENCES IT
    pause_time();

setgameendtime( gettime() + int( level.extratime * 1000 ) ); // :951  never reached
thread globallogic::timelimitclock();                        // :953  never reached
level.usingextratime = 1;                                    // :954  never reached
...
if ( !isdefined( zone ) )                                    // :958  UNREACHABLE DEAD CODE
{ function_c4915ac(); return; }
```

The thread dies at `:946`, before the clock is ever set up. The `isdefined` guard
sits 14 lines too late. Net effect: no round-start event, no overtime clock.

**The round still resolves.** `checktimelimit()` (`globallogic.gsc:3272`) re-fires
while `timeleft <= 0`; `level.var_31f5f23` is already 1, so `ontimelimit()` takes
its else branch straight to the HP tiebreaker `function_c4915ac()` (`:1090`),
which sums `player.health` per team and calls `endround(team, 1)`.

Also unguarded: `ongameplaying()` at `:213` iterates `level.zones` with no
`isdefined` check, and if it throws, `:222-225` never clears the
`gunfight_pregame_rob` clientfield — so the pregame render override sticks on
players. (The client-side twin at `gunfight.csc:147` *is* guarded.)

## DANGER — do not half-build a zone

Zero zone entities is **safe** (clean early return). A `gunfight_zone_center`
*without* a properly overlapping `gunfight_zone_trigger` is **fatal**:

```gsc
globallogic_utils::add_map_error( "Zone at ... is not inside any \"zonetrigger\" trigger" );  // :865
...
if ( globallogic_utils::print_map_errors() ) { return false; }                                 // :902
```

`print_map_errors()` (`globallogic_utils.gsc:634`) calls `callback::abort_level()`,
which nulls `callbackstartgametype`, `callbackplayerconnect`, `callbackplayerdamage`,
`callbackplayerkilled` — a dead, unplayable match. Note `:845` uses
`zone istouching( trigs[j] )`, so the center must be *physically inside* the trigger.

## What already works on any map

- **Spawns.** `:77` `spawning::addsupportedspawnpointtype( "tdm" )` — byte-identical
  to `tdm.gsc:39-41`. There is no gunfight spawn type anywhere. Any TDM-capable map
  works. Caveat: `:100` sets `level.alwaysusestartspawns = 1`, so both teams use the
  fixed TDM start clusters every round — long walk-ups on a big map, not a failure.
- **Loadouts.** `getscriptbundle("gunfightloadoutlist")` → `mp_gunfight_loadout_default`
  / `_snipers` / `_blueprints` / `_melee`. Pure weapon/attachment refs, zero geometry.
  Rotated in `onendround()` (`:388`) every `level.gunfightroundsperloadout` rounds.
- **Round wins.** Last-team-standing via `level.takelivesondeath = 1` (`:50`) and
  `ondeadevent()` (`:357`). No map assets involved.
- **No map-name checks.** Grepping gunfight.gsc/.csc for `mapname`, `g_gametype`,
  `getdvarstring`, `level.script` returns zero hits.

## Fix sketch — UNVERIFIED, not yet written

Cleanest without editing the map, all in an injected script:

1. Set `level.zones = []` unconditionally so nothing dereferences undefined.
2. Guard the `foreach` at `:213`.
3. Replay the block skipped after `:121` — most importantly `luinotifyevent( #"round_start" )`.
4. Let the HP tiebreaker stand in for overtime, or override `level.ontimelimit`.

Because `injectcw` can't detour, do this from `callback::on_start_gametype`,
which runs after Gunfight's own `gametype_init`. Ordering is **UNVERIFIED**.
