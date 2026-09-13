# Overtime zone on any map — `#synth_zones`, investigated 2026-09-12

The Gunfight overtime capture zone for maps that do not ship one. Which, in a private match, is
**every map** ([[gunfight-findings]]: `gunfight_zone_center` read 0 on ICBM and Amsterdam, both stock
Gunfight maps). Today the mod guards the hole — `level.zones = []` and an `ontimelimit` that goes
straight to the health tiebreak. This note is the fidelity upgrade: the real overtime, from the real
stock code, anchored on **Domination's neutral B flag** the way the BO1 mod did it.

**Status: BUILDS IN-GAME — `level.zones 1`, no dead match (two maps, 2026-09-12). Anchor now the
Domination B flag, captured before deletion; overtime BEHAVIOUR (clock extend / capture) not yet
watched.** Shipped in `gunfight_menu` behind `gf_zone` (default **0/off**).

> **MEASURED — Zoo then a second map, 2026-09-12.** Census on both: `koth: 0 centre / 3-4 trig`,
> `control: 0 centre / 2 trig`, **`dom live 0 flag_primary`**. With `gf_zone` ON the second map read
> **`live: level.zones 1`** on a hardpoint-trigger anchor at `(542,1904,172)` — so stock `setupzones()`
> accepted the synthesized centre+trigger and built the real zone, no `abort_level`. The hardpoint
> point was ~990u off map centre `(281,946,-136)`, which is why the anchor moved to dom B (below).
> Live stock overtime values on a private map read **`extratime 10s, capture 3s`**.

> **WHY dom read 0, and the fix.** Every dom-capable map *does* carry `flag_primary` — but it is a
> **gameobject**, and `gameobjects::main()` (`globallogic.gsc:5218` → `gameobjects_shared.gsc:590`)
> deletes every gameobject not tagged for the running gametype. That runs at `gametype_start`, before
> our `on_start_gametype` callback — same reason the koth/control *centres* are gone while their
> *triggers* (not gameobjects) survive. **Fix: capture the flags at `postinit`** (`mod_dom_capture`,
> the system's postinit slot) — `run_post_systems` fires *before* `gametype_start`
> (`callbacks_shared.gsc:1361` vs `:1454`), so the flags are still alive. Their origin + `script_label`
> + capture-trigger origin are cached in `game.` (survives the per-round rebuild), keyed by map so a
> session switch invalidates it. `mod_zone_anchor` then prefers cached dom B, reusing the flag's own
> trigger if it survived or spawning a radius at B otherwise. Hardpoint/Control triggers stay as the
> fallback for a map with no dom.

> **MEASURED — Zoo, 2026-09-12 (census).** `gunfight: 0 / 0`, `dom: 0 flag_primary`,
> **`koth: 0 centre / 4 trig`**, **`control: 0 centre / 2 trig`**, `sd bombzone 0, ctf zone 0`. So on
> Zoo there is **no Domination data at all** (the BO1 anchor is absent), and the koth/control **centre
> point-entities are gone but their trigger brushes survive**. Live stock values read
> **`extratime 10s, capture 3s`**. This is exactly §7's first Untried item, now confirmed: *the
> triggers are present, only the centres are missing.* The cause is `gameobjects::main()`
> (`globallogic.gsc:5218` → `gameobjects_shared.gsc:590`): it deletes every gameobject whose
> `script_gameobjectname` is not the running gametype's, and it runs earlier in `callback_startgametype`
> than our callback. A brush trigger is not a gameobject, so it stays. **The builder now anchors on the
> surviving trigger and spawns its own centre at the trigger's origin** — no centre entity needed.

All line numbers are `bocw-source-main` unless stated; `gunfight.gsc` = `scripts/mp_common/gametypes/`.

---

## 1. The mechanism — hand stock `setupzones()` the two entities it wants

`gunfight::setupzones()` (`gunfight.gsc:827-908`) is the only thing standing between a private match
and the shipped overtime. It needs exactly two map entities and checks nothing else about them:

| Entity | Found by | What is required of it |
|---|---|---|
| `gunfight_zone_center` | `getentarray( "gunfight_zone_center", "targetname" )` `:813` | must be **inside exactly one** trigger: `zone istouching( trigs[j] )` `:845`; its `.target` is read **unguarded** as the visuals' targetname `:875` |
| `gunfight_zone_trigger` | `getentarray( "gunfight_zone_trigger", "targetname" )` `:836` | becomes the `gameobjects::create_use_object( #"neutral", zone.trig, visuals, … )` capture volume `:883`; `trigger::add_flags( 16 )` `:856` |

Given those, stock builds everything: the objective (`:883-889`), `level.zones = zones` (`:907`), and
`onstartgametype()` runs past its `:121` early-return into the presentation tail the mod currently
replays by hand. At time expiry, stock `ontimelimit()` (`:915`) threads `overtime()` (`:931`):

- clock reset to `level.extratime` (`:951`), `timelimitclock` restarted (`:953`), `usingextratime = 1`;
- the zone opens for capture: `allow_use( #"group_all" )`, `set_use_time( level.capturetime )`,
  `set_visible( #"group_all" )`, `set_model_visibility( 1, 1 )` (`:964-975`);
- VO `gnfOvertime`, `luinotifyevent( #"hardpoint_unlocked" )`, music `gunfight_time_extended`,
  the `bomb_timer_a` HUD countdown (`function_844322c9`, `:976` / `:991`);
- a capture ends the round for the capturing team, reason 12 (`onzonecapture`, `:1016`); the extra
  time running out re-enters `ontimelimit()` and takes the health tiebreak (`function_c4915ac`, `:1090`).

Every bit of that is stock code we do not have to write or link — the menu payload still does **not**
`#using gunfight` (a fatal link error outside Gunfight matches). The whole approach is: *spawn the two
entities before `setupzones()` looks*.

### Why the callback is early enough — VERIFIED in source

```gsc
// globallogic.gsc:5536-5537, callback_startgametype()
callback::callback( #"on_start_gametype" );
[[ level.onstartgametype ]]();
```

The `on_start_gametype` callbacks — `mod_apply` is one — fire **before** gunfight's `onstartgametype()`.
They are dispatched as `entity thread [[ func ]]()` (`util_shared.gsc:_single_thread`), and a GSC
thread runs synchronously until its first wait, so `mod_apply` completes its entity build before the
caller reaches `[[ level.onstartgametype ]]()`. Nothing in `mod_apply` above the build waits. (This is
the same ordering that lets `mod_apply`'s `level.ontimelimit` override stick — gunfight assigns it in
`main()`, `:58`, which runs earlier still.)

The previous sketch in `game-systems.md §6/§9` proposed building our *own* gameobject and setting
`level.zones` ourselves. Feeding stock instead is strictly less code and gets the HUD, VO, capture
events and tiebreak for free.

---

## 2. The anchor — Domination's neutral B in this game

BO1 reused the dom B flag. BOCW's Domination map data (the shared dom builder,
`hashed/script/script_1304295570304027.gsc:414-470` and `:158-230`):

| Entity | Role |
|---|---|
| `flag_primary` (targetname) | one **script_model per flag** at the flag position; `.script_label` is `_a` / `_b` / `_c` (…`_f`), `.script_index` 1..6; **`.target` names the map's capture trigger** (Onslaught's paintball case shows the convention: `"flag_trigger_a"`, `script_336275a0ba841d18.gsc:215`) |
| `flag_descriptor` (targetname) | script_origins near each flag, `script_linkname`, spawn/VO metadata — not needed |

So the B flag is `flag_primary` with `script_label == "_b"`: its `.origin` is the flag, and
`getentarray( flag.target, "targetname" )[0]` is the designed capture volume. The mod:

1. renames that trigger `gunfight_zone_trigger` (a script-set targetname is what `getentarray` finds —
   `helicopter_shared.gsc:394` sets `chopper.targetname = "chopper"` on a spawned vehicle, `:870` looks it
   up; `globallogic.gsc:4243` does the same for `timeLimitClock`);
2. spawns the centre: `spawn( "script_model", flag.origin + (0,0,16) )` + `setmodel( "tag_origin" )`,
   targetname `gunfight_zone_center` — the entity Onslaught spawns for its own hand-placed zones
   (`util::spawn_model( "tag_origin", … )`, `script_336275a0ba841d18.gsc:190`); `.target` set to
   `gf_zone_visual` so `:875` reads a defined string;
3. renames the flag model itself `gf_zone_visual`, so it becomes the zone's visual: hidden by
   `set_model_visibility( 0, 1 )` at setup (`:885` → `ghost()` + `notsolid()`), shown and made solid by
   `overtime()` (`:968`). The BO1 "flag appears" behaviour, with whatever model the map gave that entity
   (the dom builder replaces it with `tag_origin`, `:427`, so the map model is a placeholder of unknown
   looks — **the census prints it**).

If the map has no dom data, the same walk Onslaught does (`script_336275a0ba841d18.gsc:140-233`:
gunfight → koth → flag_primary) continues to **Hardpoint** (`koth_zone_center` / `koth_zone_trigger`,
`script_50d0f08de978328d.gsc:1340-1423`) and **Control** (`control_zone_center` / `control_zone_trigger`,
`control.gsc:824-829, 953`), both the same centre-inside-trigger shape as Gunfight's. With no reusable
trigger at all the mod spawns one: `spawn( "trigger_radius", origin, 0, gf_zone_radius, 128 )`, the
`ctf.gsc:637` shape; a script-spawned `trigger_radius` feeding `create_use_object` is exactly what
`clean.gsc:615-618` does for its neutral deposit hub.

### 2.1 What the Zoo census forced — anchor on the TRIGGER, not the centre

§2 was written to reuse a *centre entity* (dom flag) and fall through the Onslaught family walk. Zoo
has no dom data and no surviving centres of any family, so that walk returns nothing — which is what
the first build reported (`next round would use: nothing`). But the **triggers are there**, and a
zone trigger is all Gunfight actually needs: its `.origin` is the capture point that
`create_use_object` marks (`gameobjects_shared.gsc:2762`, `spawn( "script_model", trigger.origin )`),
so a centre spawned at `trig.origin` is inside the volume by construction.

So `mod_zone_anchor` now, after the dom-flag branch, calls `mod_zone_trigger_pick( "koth_zone_trigger" )`
then `"control_zone_trigger"` — each returns the trigger **nearest `level.mapcenter`** (a map carries
several; Hardpoint rotates 4, and Gunfight overtime wants the central one). `level.mapcenter` is set by
`calculate_map_center()` (`globallogic.gsc:5500`), which runs in `callback_startgametype` *before* the
`on_start_gametype` callbacks — so it is populated when `mod_apply` reads it. The centre is then spawned
at `trig.origin + (0,0,16)`; the reused trigger is renamed `gunfight_zone_trigger`; the §4 `istouching`
valve still guards the fatal case and restores the trigger's name on back-out.

The dom-flag path (§2) is unchanged and still preferred when a map *does* carry Domination data — it
gives the authored flag visual. The trigger-pick is the general fallback that makes off-Gunfight,
non-dom maps like Zoo work. Only if neither a dom flag nor any koth/control trigger exists does the
builder reach the spawned-`trigger_radius` case, and only a map with a zone *centre* but no trigger
would hit the "half-zone" valve — not observed.

---

## 3. The trap the code had to route around — DERIVED, then handled

`overtime()` sets the visible clock (`:951`), but expiry is decided by `checktimelimit()`
(`globallogic.gsc:3313`): `timeleft = level.timelimit * 60000 - gettimepassed()`, and `level.timelimit`
is refreshed from `[[ level.gettimelimit ]]()` every 0.25 s (`updategametypedvars`, `:3452`). Stock
`gettimelimit()` adds the extra time while `usingextratime` (`gunfight.gsc:1150-1153`). The mod's
`mod_gettimelimit` **did not** — it returned the base timer — so with a real zone the base limit would
read expired again on the very next tick, `ontimelimit()` would take its second-call branch, and the
health tiebreak would fire after a zero-second overtime. `mod_gettimelimit` now mirrors the stock
branch, `function_60d95f53()` (the one-frame-in-ms builtin, `+3ccb620`) epsilon included.

Two more stock reads that private-match values are unknown for, now asserted from dvars each round:
`level.extratime` (`gf_zone_overtime`, default 20 s) and `level.capturetime` (`gf_zone_capture`,
default 5 s). Both read once at `main()` (`:44, :46`) from gametype settings; `set_use_time` is
seconds ×1000 (`gameobjects_shared.gsc`).

---

## 4. The one fatal outcome, and the valve

Zero centres is stock's clean early return. A centre **no trigger contains** is
`globallogic_utils::add_map_error` (`:865`) → `print_map_errors()` → `callback::abort_level()`
(`globallogic_utils.gsc:634`) — callbacks nulled, a dead match ([[gunfight-findings]] "DANGER").

`mod_zone_synthesize()` therefore makes **the same call stock will make**, `center istouching( trig )`,
immediately after spawning, and on failure deletes the centre (and the spawned trigger, or restores a
reused trigger's targetname) and reports to the host. `setupzones()` then sees zero centres — the safe
path — and the round plays as today. `istouching` on a script_model is a generic operation
(`array::get_touching`, `array_shared.gsc:70-76`), and the centre sits 16 units above the anchor so it
is inside the volume rather than on its floor plane.

`assert( zones.size == trigs.size )` (`:837`) is a dev-build assert; retail asserts are inert, and the
counts match anyway (1/1) unless a map carries stray `gunfight_zone_trigger`s — which is one of the
things the census counts.

---

## 5. What joiners will and will not see — DERIVED

| Element | Reaches joiners? | Why |
|---|---|---|
| objective icon / compass / capture progress bar | ✅ | `objective_add` / `objective_setprogress` are server-driven, networked objective state |
| overtime clock, `bomb_timer_a` countdown | ✅ | `setgameendtime`, `setbombtimer`, match flags |
| VO, music, `hardpoint_unlocked` LUI event | ✅ | server-driven |
| flag model appearing at overtime | ✅ | a server entity (`show()`); looks = the map's placeholder model, see census |
| **ground ring / edge marker** | ❌ (unless native, §5.1) | Confirmed 2026-09-12: the ring is the client FX `zoneedgemarker` (`ui/fx8_infil_marker_neutral`), drawn by `gunfight.csc` `function_f789a70b` → the client builtin `function_c6c4ce9f`, **only** around the client's own entity named `gunfight_zone_trigger`. We can't create a client entity (a server rename/spawn doesn't network a targetname) and we don't inject client `.csc`, so on a synthesized zone the client has nothing to draw the ring on. The server never precaches that FX either (grep: 0 hits in gunfight.gsc), so a server `playfx` substitute isn't free. The objective icon + capture bar, being networked, DO show — which is what "icon + capture space, no ring" is |

No GSC print is involved anywhere in this path; the host readout is `mod_host_say` (host only).

---

### 5.1 The native-flag maps are the free win — and the dom-B nuance

Two things the 2026-09-12 session surfaced, both about the ring:

- **A map that SHIPS gunfight OT entities gets the full ring for nothing.** Its `gunfight_zone_center`
  (a gameobject tagged `gunfight`) is *allowed* in a gunfight match, so `gameobjects::main()` keeps it,
  and the client carries the matching `gunfight_zone_trigger` + `gunfight_flag_neutral` — so the stock
  client ring draws. `mod_zone_synthesize` already early-returns on any live `gunfight_zone_center`
  (no synth), so these maps use their native zone untouched. Non-stock maps that still carry the
  entities (candidates: **Diesel, Hijacked** — untested) fall here. **Test one: if the ring shows, this
  is the mechanism.** The census `gunfight: N centre / N trig` line is the tell (N>0 = native).

- **The dom B flag does NOT bring its ring into gunfight.** Two reasons, both measured: a dom flag's
  ring is drawn by `dom.csc` (`monitor_flag_fx`), which does not run in a gunfight match; and the dom
  builder sets the flag model to `tag_origin` (invisible), so the raw entity is a placeholder, not a
  prop. So anchoring on dom B buys the correct *central position* (real, and better than the off-centre
  hardpoint point) — not a visual. The ring wall above is independent of the anchor.

### 5.2 The dom marker FX — TRIED, CRASHES, REVERTED (2026-09-12)

🪦 **RESULT: server `spawnfx` of the dom marker HARD-CRASHES the game at overtime, and was removed.**
klaze reached overtime with the marker enabled and the game crashed the instant it spawned. Cause, now
understood: the FX asset (`ui/fx_dom_marker_*`, and the `ui/fx8_infil_marker_neutral` fallback too) is
**not loaded in a Gunfight match** — VIP's identical call works only because a VIP match loads that FX.
`spawnfx` of an unloaded FX does not return undefined (the assumption the fallback rested on); it
crashes the process, and a GSC thread cannot isolate an engine crash. There is **no safe guard**:
`isassetloaded` is only ever called with `aitype`/`stringtable`/`vehicle`/`xanim` — no `"fx"` type to
pre-check with, and no GSC FX precache/load builtin exists. So synthesized maps are back to icon +
capture; the real ground ring is available **only** where the map ships native gunfight OT entities
(§5.1, client-drawn). A server-spawned MODEL marker (a known-loaded `wpn_t9_eqp_*` prop) is the one
un-tried non-crashing visual if wanted.

<details><summary>the reverted FX approach, kept as the record of why it can't work</summary>


The "include dom resources" question has a clean yes. Domination's ground ring is an FX,
`ui/fx_dom_marker_neutral` / `_neutral_r120` (and team variants), and a **server** gametype already
spawns it server-side: `vip.gsc:661` — `fx = spawnfx( "ui/fx_dom_marker_team_r90", origin, fwd, right );
fx.team = #"none"; triggerfx( fx, 0.001 );`. `spawnfx`/`triggerfx` are server builtins; the FX networks
to every client; and stock plays FX by **raw path with no precache** (e.g. `gadget_homunculus.gsc`
`playfx( #"zm_weapons/…" )`), so there is no fastfile/resource include step — the UI FX ships loaded.

So the ring is reachable after all — not via the client edge FX (still walled, §5), but by spawning the
dom marker ourselves. `mod_zone_fx_watch( origin )` (threaded from `mod_zone_synthesize` on success,
gated `gf_zone_fx` default 1) waits for stock `overtime()` to open the zone (`level.usingextratime`,
gunfight.gsc:953) then `spawnfx( "ui/fx_dom_marker_neutral_r120", … ) → triggerfx`. Isolated in its own
thread: if that FX variant is not loaded, `spawnfx` returns undefined and it falls back to
`ui/fx8_infil_marker_neutral` — gunfight's own edge-marker FX, registered this match
(`gunfight.csc` zoneedgemarker[0]) so guaranteed present; and if `spawnfx` hard-errors on an unloaded
asset the thread dies alone, leaving the icon+capture zone intact. Census reports
`zone fx: on, marker SPAWNED/pending-overtime`.

⚠ UNTESTED in-game: whether `ui/fx_dom_marker_neutral_r120` is loaded in a gunfight match (the fallback
covers a soft miss; a hard error would show no ring and is the thing to watch). Radius is the FX's own
(r120), independent of the capture trigger's real shape — a marker of the spot, close but not an exact
trace of the capture volume.
</details>

## 6. Test plan — read-only first, one thing per match

Menu: `Overtime zone` page. **Run the census before switching it on**; everything it prints is a
`getentarray` count (read-only) plus the anchor the next round would take.

| # | Step | Expect | Measured |
|---|---|---|---|
| T0 | any 6v6 map, `Zone census` | `gunfight: 0 centre / N trig` (N = 0 expected; N > 0 is a finding — the trigger survived and only the centre is missing, see §7), `dom: 3 flag_primary _a _b _c`, a `B:` line with classname, model, target, trigger classname + origin, `next round would use: dom _b @ (x,y,z) in trigger_multiple` | `______` |
| T0b | a Gunfight 2v2 map (Amsterdam/ICBM), `Zone census` | whether these maps carry dom/koth data at all — decides whether the feature covers the stock Gunfight maps or only 6v6 ones | `______` |
| T1 | solo, `Zone ON`, `Timer 20s`, restart | at round start a host toast `zone: dom _b (map trigger) @ (…)`; **no** map error / dead match | `______` |
| T2 | T1, let the timer run out | VO "overtime", clock restarts at 20 s, objective icon at B, flag model appears; the round does **not** end at 0:00 (the §3 trap) | `______` |
| T3 | T2, stand in the zone | capture bar fills over 5 s; round ends for your team | `______` |
| T4 | T2, stay out | at the end of the 20 s the health tiebreak ends the round (stock path) | `______` |
| T5 | round 2 of the same match | toast again — the build is per round (entities do not survive the round restart) | `______` |
| T6 | with a joiner | joiner sees icon/HUD/clock in overtime; no text on their screen; capture from the joiner's side works | `______` |
| T7 | `Zone census` during overtime | `live: level.zones 1, extratime 20s, capture 5s` | `______` |

A `^1zone: centre not inside …` toast at T1 is the valve firing: the round is safe, and the line names
the trigger classname — the next thing to look at is the centre's z offset against that volume.

---

## 7. Untried — not ruled out

- ✅ **CONFIRMED (Zoo): only the centres are missing; the triggers survive.** The builder now uses
  this directly — anchor on a koth/control trigger, spawn the centre at its origin (§2.1). What is
  still untried is whether **every** off-Gunfight map keeps zone triggers (Zoo is n=1) and whether a
  brush trigger's `.origin` is always inside it (it is the capture point stock marks, so expected —
  the valve catches any exception).
- **Why private matches lack the entities.** Still engine-side and unmeasured; `serversettings::
  constrain_gametype` (`serversettings.gsc:137`) deletes by `script_gametype_<gt>` keys for six legacy
  gametypes only, none of them gunfight, so it is not script-side.
- **The flag model.** If the `flag_primary` placeholder looks wrong, the visual can be dropped (leave
  `anchor.visual` undefined) or swapped for a loaded model; CTF's flag models are hashed names
  (`ctf.gsc:114-121`) and only loaded in CTF, so `setmodel` to one of those is a test, not a plan.
- **Client outline.** Only a client-side entity draws it; no injectable VM reaches the client match
  scripts ([[game-systems]] §12). An FX or a script_model ring spawned server-side would be a visible
  substitute if wanted.
- **Overtime pause when a player is already inside at 0:00** (`function_339d0e91() > 0` → `pause_time`,
  `:946`) and the contested-claim rules (`can_contest_claim( 1 )`, `must_maintain_claim( 0 )`) are stock;
  they should just work, and T3 with two players in the zone is the check.
- **Hardpoint/Control anchors** are the fallback for dom-less maps and untested; Hardpoint volumes are
  much larger than a dom flag's, which may want the spawned-radius path instead (`gf_zone_radius`).

---

## 8. Settings and code

| Dvar | Default | Meaning |
|---|---|---|
| `gf_zone` | 0 | 1 = build the zone at every round start (`mod_apply`) |
| `gf_zone_overtime` | 20 | `level.extratime`, seconds |
| `gf_zone_capture` | 5 | `level.capturetime`, seconds |
| `gf_zone_radius` | 128 | `trigger_radius` radius when no map trigger can be reused |

Code: `src/gunfight_menu/scripts/gunfight_menu.gsc` — `mod_zone_synthesize`, `mod_zone_anchor`,
`mod_zone_from_family`, `zone_report`; `mod_apply` (build + gating of `mod_ontimelimit` and the
presentation replay); `mod_gettimelimit` (extra-time branch). With `gf_zone` off, behaviour is byte-for-
byte the previous guard-and-skip.
