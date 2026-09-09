# Roadmap — what the project is FOR now that the three goals are closed

**Set 2026-09-09 by klaze**, once map, timer and team size were all confirmed in-game. Two goals, both
about how hosting *feels* rather than whether it works. Each carries the open questions that shape it;
the questions are marked ❓ and the answers change the plan, so answer them before building.

---

## Goal A — a proper control surface for hosting

> *"some sort of app or mod menu that lets me control the mode, map, bot fill, move players, etc.
> ideally, it would be nice to have control in the pregame lobby and during the match."*

The current workflow is `inject.sh` + the Atian Menu + F7 + hand-edited configs. It works. It is not
a hosting tool. Three surfaces exist, and they are **not alternatives** — each reaches a layer the
others cannot:

| Surface | Reaches | Cannot reach | Cost | Status |
|---|---|---|---|---|
| **In-match GSC menu** | everything script can — map, mode, team size, bot fill, move players, timer, loadout set, spy plane | the pregame lobby (no GSC runs there) | **low** — the Atian Menu source is public, its item/page API is three functions, and every control is a builtin this project has already called | ▶ second, after D10 |
| **Pregame lobby control** | the lobby, via console commands from the one DLL slot that loads | anything GSC does | **gated on D10** — which command? nobody has looked | ⬅ **#1. Run D10 first** |
| **Windows tool** | orchestration: compile, inject, flip configs, capture probes, drive the other two | the game itself | medium | ⏸ after the menu exists to orchestrate |

### A1 · The in-match menu — ✅ BUILT 2026-09-09 as `src/gunfight_menu/`, compile pending

`gunfight_mod`'s four fixes + team size + the menu, **in one payload** (B9: nothing can be injected on
top of a live one). The engine is the Atian Menu's own `menu.gsc`/`keymanager.gsc` **rewritten in ACTS
dialect** — it could not be copied, because the original is built with `debugcompiler` in the
`#include` / bare-`autoexec` / `#ifdef` dialect this project's history records as crashing at script
link under ACTS. Same keys as the shipped menu. Settings are **dvars** (`gf_team_size`,
`gf_timer_seconds`, `gf_loadout`, `gf_spyplane`, `gf_map_method`, `gf_menu_lines`) because `level` is
rebuilt every round and `game.` resets at match end; B4 measured a dvar surviving a `map_restart`.

Offline checks: `check-dump` 0 fatal (the one unused-by-stock call is `map()` itself — the proven
carry), `check-args` 0 mismatches. ⚠ **Never compiled, never injected.** The map entry ships **both**
methods behind `gf_map_method` — carry (`map()`, verified) by default, session (`switchmap_load`, B1)
as the toggle — so B1's answer flips a dvar rather than forcing a rebuild.

⚠ **A contradiction found while building it, recorded rather than resolved.** A4 diagnosed its map
switch failing because `level endon( #"game_ended" )` killed the thread inside `wait(1)`. But the
shipped Atian Menu's `menu_think` carries the **same endon**, runs its map action **inside that
thread** with the same `wait(1)`, and works — klaze uses it. So the endon cannot be the whole story,
and A4 run 4's self=player theory is back in play. The menu routes around it: every map switch is
threaded onto the **player** with **no endons**, which satisfies both theories without choosing.



The Atian Menu declares a page in one line and an item in one line
(`menu.gsc:71` `add_menu`, `:93` `add_menu_item( menu_id, name, &func, data… )`). Its CW source ships
`menu.gsc` / `menu_items.gsc` / `menu_funcs.gsc` / `keymanager.gsc` under `coldwar/scripts/core_common/`.
**We fork that, drop its 26 functions (guns, camo, vehicles, zombies), and wire ours:**

| Control | Call | Proven? |
|---|---|---|
| Map | `switchmap_load( map, gametype )` → `switchmap_switch()` — **see Goal B**, not `map()` | ⚠ B is the test |
| Mode | same call, gametype argument | ⚠ same test |
| Team size | `setgametypesetting( #"maxplayers", N )` | ✅ L6 — 4v4 verified |
| Bot fill | `bot::add_bots( count, team )` | ✅ C7 — bots reach 4v4 on any map |
| Move a player | `player [[ level.autoassign ]]( 0, team, undefined )` — `team_assignment.gsc:419`, no cap check | ⚠ C11 built, never run |
| Round timer | `setgametypesetting( #"timelimit", N )` — live, ~0.25s | ✅ shipped |
| Loadout set | `setgametypesetting( #"gunfightloadoutindex", 0–3 )` — default / snipers / blueprints / melee | ⚠ B6 built, never run |
| Spy plane | `setgametypesetting( #"gunfightspyplane", 3 )` — the value the menu hides | ⚠ B7, never run |
| Restart | `map_restart()` | ✅ B4 |

⚠ **The menu persists across matches within one game launch** — `mod_apply()` re-runs on every
`on_start_gametype` — but **must be re-injected after every game restart**, and ⚠ **B9 says a payload
cannot be hot-swapped under a live one**. So the menu is injected once per launch, and every control
above has to be *in* it from the start. There is no "add a button later without restarting the game."

❓ **How many people do you normally host?** "Move players" for 8 is a submenu of names; for 12 it
needs paging. Sizing the menu wrong costs a rebuild.

### A2 · The pregame lobby — ⬅ **klaze's #1 priority for the whole project**

Nothing GSC runs in the pregame lobby. The only proven way in is cwpatch's technique — overwrite the
game's command-string blob, call the dispatcher — from `discord_game_sdk.dll`, the one slot that
auto-loads. **`map %s\n` is already in that blob.** What nobody has ever done is list the commands
(`acts dcfuncscw` → `tools/crack-cmds.py`). Full write-up: [`lobby-map-dll.md`](lobby-map-dll.md).

✅ **Answered 2026-09-09 — klaze: "pregame control would be the single most valuable mod for this
entire project."** So D10 runs first, ahead of everything in both goals, and A2 is built on whatever it
finds. ⚠ D10 costs one read with the game running; it writes nothing.

### A3 · The Windows tool — last, because it orchestrates things that must exist first

A tray/GUI app wrapping `check-gsc.ps1`, `inject.sh`, config flips, `capture-probes.ps1`, and — once
A2 lands — the lobby command. It buys convenience, not capability. **Do not start it before A1.**

---

## Goal B — load Gunfight on any map the way the glitch does, not the way the carry does

> *"lets say we start on KGB then force switch to Hijacked, it still says KGB in parts of the UI,
> versus when doing the glitch, it actually says I'm playing Gunfight on Hijacked."*

### The diagnosis, from the dump — the carry rides the one builtin stock never uses

The Atian Menu ships **three** switch variants, and all 48 of its map entries wire the weakest one:

| Menu function | Calls | Gametype passed? | Stock callers |
|---|---|---|---|
| `func_set_map` ← **our carry** | `map( name )` → `switchmap_switch()` | **no** | **zero, anywhere in the dump** |
| `func_set_gametype` | `switchmap_load( map, gametype )` → `switchmap_switch()` | yes | campaign, zombies |
| `func_set_mapgametype` | `switchmap_preload( map, gt )` → `switchmap_load( map, gt )` → `switchmap_switch()` | yes | campaign, side missions |

`map(1-1)` takes **one** argument. It cannot tell the session what gametype it is loading, and nothing
in the game calls it. `switchmap_load(1-2)` / `switchmap_preload(1-2)` take the gametype, and **three
separate stock systems use them to change map with the session tracking correctly**:

```gsc
// campaign level transition — cp_common/load.gsc:398-414
var_31924550 = getuimodel( function_5f72e972( #"lobby_root" ), "transitionMapIdOverride" );
setuimodelvalue( var_31924550, hash( var_83104433 ) );      // <- TELLS THE UI THE NEW MAP, FIRST
switchmap_load( getrootmapname( var_83104433 ), level.gametype );
util::wait_network_frame( 1 );
switchmap_switch();

// side-mission launch — callbacks_shared.gsc:2227
switchmap_preload( eventstruct.name, eventstruct.game_type );
luinotifyevent( #"open_side_mission_countdown", 1, eventstruct.list_index );
wait 10;
switchmap_switch();

// zombies — zm_utility_zsurvival.gsc:153
switchmap_load( map_name, "" );
level waittilltimeout( 25, #"switchmap_preload_finished" );   // <- the load is ASYNC and signals
switchmap_switch();
```

🔓 **Two things our carry never does, both visible above:**
1. **Pass the gametype.** The session record that the scoreboard, pause menu and AAR read is what
   `switchmap_load( map, gametype )` is *for*. `map()` overrides the loaded map underneath a session
   that still says KGB — which is exactly the symptom, and exactly what
   [`menu-map.md`](menu-map.md) §"the scoreboard lies" diagnosed as "a map override at load time, not
   a lobby reconfiguration."
2. **Tell the UI first.** Campaign writes `lobby_root.transitionMapIdOverride = hash( map )` before
   switching. ⚠ That model has **one reference in the whole dump**, campaign-side; whether the MP
   lobby honours it is unknown and is the second thing the test reads.

⚠ **And the wait is wrong.** The menu waits one network frame between load and switch. Zombies waits
on `#"switchmap_preload_finished"` with a 25s timeout — `switchmap_load` is asynchronous and *signals
completion*. A4's own failure (the `endon( #"game_ended" )` killing the thread mid-wait) is the same
class of bug from the other side: the sequence is not three synchronous calls.

### B1 · The test — `test_sessionswitch`, one match, read-only first

From a running Gunfight match on map X, target map Y:

1. **read** `getuimodelvalue( getuimodel( <lobby_root>, "transitionMapIdOverride" ) )` — probe 40
2. `setuimodelvalue( …, hash( Y ) )`
3. `switchmap_load( Y, getdvarstring( #"g_gametype" ) )` — the **current** gametype, read at
   runtime (`util_shared.gsc:5873` is stock's own accessor). Not a guess between `"gunfight"` and
   `"gunfight_3v3"`; whichever the lobby is, that is what gets passed
4. `level waittilltimeout( 25, #"switchmap_preload_finished" )` — probe 41 = did it signal, and when
5. `switchmap_switch()`

| Outcome | Means |
|---|---|
| scoreboard / pause menu / AAR say **Y + Gunfight**, **and the friend list / activity shows Y** | 🔓 **Goal B closed.** The engine's session record moved. Replace `map()` in `gunfight_mod` and the menu |
| in-match UI says Y but **presence still says X** | the call updated the match but not the session. Partial — better than the carry, not the glitch. D10 next |
| loads Y, UI still says X | the session record is not set by `switchmap_load` either. Next: does step 2 alone change what the UI says (probe 40 read-back), and what does the glitch do that neither does |
| `switchmap_preload_finished` never signals (probe 41 = 99999) | the load did not start — wrong gametype string, or the thread was killed. Check the wrapper for `endon` before anything else |
| hangs on load | same failure A4 hit. **Only target maps already carried to** — `mapexists()` returns 1 for everything (B5) and is not a guard |

⚠ **Wrapper rule, learned from A4 at the cost of a hung game:** the sequence must run in a thread
that does **not** carry `level endon( #"game_ended" )`. `map()` fires that notify mid-sequence.

⚠ `function_5f72e972( #"lobby_root" )` is stock's accessor for a named UI-model root — a hashed
helper used on both `.gsc` and `.csc` sides with `#"lobby_root"`, `#"team_momentum"`, `#"doa_world"`,
and its definition was not located by name. **Inferred from the stock pattern, not read:** the engine
table has `getglobaluimodel(0-0)`, and stock reaches named models as
`createuimodel( getglobaluimodel(), name )` / `getuimodel( root, name )`. So B1 should call

```gsc
root = getuimodel( getglobaluimodel(), "lobby_root" );
m    = getuimodel( root, "transitionMapIdOverride" );
```

and **read `getuimodelvalue( m )` first** (probe 40) — a `99999` there means the model does not
exist on the MP side and the chain is wrong before anything is written.

### B2 · What the glitch actually does — ✅ **RESEARCHED 2026-09-09, and it is a PLAYLIST carry**

klaze has only ever triggered it by accident, so this was researched rather than reported. ⚠ **Provenance
is second-hand:** the primary write-up (a Se7enSins thread) and two YouTube tutorials were **blocked by
this session's egress proxy**; what follows is reconstructed from three independent search summaries of
those sources, which agree with each other. **Treat the step order as approximate and the mechanism as
well-supported.** Anyone who can open the thread should replace this section with the verbatim steps.

**Two documented variants, both from January 2021, both needing TWO players:**

| | Variant A — Social/party | Variant B — Bots and Players |
|---|---|---|
| 1 | P2 joins a friend in Multiplayer | Join a friend in Custom Games |
| 2 | P2 opens **Social** | P2 opens **Bots And Players** |
| 3 | **P1 searches for a Gunfight match** | P1 leaves Custom Games |
| 4 | once found, **the host leaves alone** | P2 opens **Bots and Players** again |
| 5 | P2 exits Social → **Custom Games** | **P1 searches for a Gunfight match** |
| 6 | P1 joins P2 | once found, **the host leaves alone** |
| 7 | P2 tries to join P1 → *"failed to connect"* | P2 exits Bots and Players and leaves the lobby |
| 8 | P1 joins P2 again | |
| 9 | P2 leaves the party alone | |

🔓 **The mechanism, and it explains the whole symptom.** A **matchmaking search loads the Gunfight
playlist descriptor into the session.** Aborting at the "match found" moment leaves that descriptor
resident, and the party join/fail/rejoin churn **transplants it into the Custom Games lobby**. The
session then genuinely holds *"Gunfight, on this map"* — which is why the scoreboard, pause menu and AAR
are all correct.

▶ **So the glitch operates one layer above our carry.** It is a **playlist reconfiguration**; ours is a
**map override at load time**. [`menu-map.md`](menu-map.md) diagnosed exactly that from the stale
scoreboard without knowing the glitch's steps, and the research confirms it from the other side. The two
mechanisms are not variants of one thing — they touch different state.

### ✅ The glitch requires matchmaking — and klaze has decided that is acceptable

⚠ **Both variants pivot on "search for a Gunfight match"** — the public matchmaking queue. The first
ground rule says *never matchmaking*. This was flagged as a decision rather than assumed.

✅ **klaze, 2026-09-09:** *"Proceed without worrying about public matchmaking restrictions. The end goal
is still a private match, which follows the rules just fine."* The search is aborted the instant a match
is found; no public lobby is ever played; the end state is a private custom game. **Recorded as his
decision, and the glitch is a legitimate route again** — for the *result*, and as a fallback.

▶ **It is still the fallback, not the plan.** Two players and a sequence of party operations is a worse
route than one script call, *if* one script call works. **B1 tests that first.** And ⚠ D10 now has a
second question to answer: whether party join / leave / matchmaking-search are **console commands** —
if they are, the glitch itself may be automatable from the DLL slot, which is the only way it could ever
become a one-button thing.

### ✅ Where the carry's UI goes stale — ANSWERED, and it is everywhere

klaze, 2026-09-09: *"everywhere the map is written still says the last map. menu, scoreboard, friend
list, activity, everything."*

🔓 **Friend list and activity are the tell.** Those are **platform presence** — what Battle.net
broadcasts to other people about what you are playing. They are not in-match HUD; nothing in GSC
writes them (the engine table has **no** presence-writing builtin at all — `resetinactivitytimer` is
the only match). So they can only change when the **engine's own session record** changes. The carry
leaves *all* of it untouched, which is the strongest possible confirmation that `map()` is a raw map
load under an unchanged session — and it hands B1 a clean, binary success criterion:

▶ **After `switchmap_load( map, gametype )`, does the friend list / activity show the new map?**
If yes, the engine's session record moved and Goal B is closed. If no, no GSC call reaches it and the
route is D10 (a console command) or the glitch.

### ❓ Still needs klaze
- **After the glitch, is *everything* right?** Spawns, the map list afterwards, map voting, the AAR. If
  everything is right it is a full playlist reconfiguration and B1 may not match it; if some things are
  off, it is closer to our carry than it looks.

---

## Order of work

⚠ **REORDERED 2026-09-09.** klaze: *"pregame control would be the single most valuable mod for this
entire project."* That moves A2 from third to first and pulls **D10** — the measurement that gates it —
to the front of the whole roadmap.

1. **D10 — `acts dcfuncscw`, then `tools/crack-cmds.py`.** ⬅ **the new #1.** It is a read, it needs no
   code written, and it is the only thing standing between here and pregame control. Everything about
   the delivery mechanism is already proven: cwpatch executes arbitrary console commands from
   `discord_game_sdk.dll`, the one slot that auto-loads, and `map %s\n` is already in the blob it writes
   to. **Nobody has ever looked at the command list.** [`lobby-map-dll.md`](lobby-map-dll.md)
2. **A2 — the pregame control itself**, shaped by whatever D10 finds. If a lobby map/mode command
   exists, this is a small addition to `tools/cw-loader-shim/`.
3. **B1 — `switchmap_load( map, gametype )`.** One match, read-only pass first. Cheap, three stock
   precedents, and it decides what A1's map control is built on. ⚠ **Do not build any map control on
   `map()`** — it has zero stock callers and cannot pass a gametype.
4. **A1 — the in-match menu.** Everything in it except the map/mode entries is already a proven call;
   those two wait on B1.
5. **A3 — the Windows tool**, once there is something to orchestrate.

⚠ In parallel and unrelated to either goal: **a human 4v4** is still the largest gap between "closed"
and "done" — see the Open questions in `.claude/CLAUDE.md`. Nothing here should jump that queue.

## Untried — not ruled out

- `func_set_mapgametype`'s full three-step (preload → load → switch) rather than load → switch
- Whether `transitionMapIdOverride` alone — no switch — changes what the pause menu shows
- `luinotifyevent` with a lobby-shaped event before switching, the way side missions do
- Whether the glitch's session state survives a *second* switch (glitch to Hijacked, then B1 to Zoo)
- A pregame GSC hook: `frontend.csc` runs client script in the lobby-pose scene; whether any
  server-side script runs there at all has never been checked
