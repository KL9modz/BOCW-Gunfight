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
| **In-match GSC menu** | everything script can — map, mode, team size, bot fill, move players, timer, loadout set, spy plane | the pregame lobby (no GSC runs there) | **low** — the Atian Menu source is public, its item/page API is three functions, and every control is a builtin this project has already called | ▶ **build first** |
| **Pregame lobby control** | the lobby, via console commands from the one DLL slot that loads | anything GSC does | **gated on D10** — which command? nobody has looked | ⏸ after D10 |
| **Windows tool** | orchestration: compile, inject, flip configs, capture probes, drive the other two | the game itself | medium | ⏸ after the menu exists to orchestrate |

### A1 · The in-match menu — every control is already a known call

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

### A2 · The pregame lobby — gated, and the gate is cheap

Nothing GSC runs in the pregame lobby. The only proven way in is cwpatch's technique — overwrite the
game's command-string blob, call the dispatcher — from `discord_game_sdk.dll`, the one slot that
auto-loads. **`map %s\n` is already in that blob.** What nobody has ever done is list the commands
(`acts dcfuncscw` → `tools/crack-cmds.py`). Full write-up: [`lobby-map-dll.md`](lobby-map-dll.md).

❓ **How much does pregame control matter versus in-match?** If in-match is 90% of the value, A2 waits
behind everything. If you want to pick the map *before* inviting people, A2 moves up and D10 runs next
session.

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
3. `switchmap_load( Y, "gunfight" )` — ⚠ the gametype string: `"gunfight"` vs `"gunfight_3v3"` is
   itself a question; `player_record.gsc:589` proves both names are real
4. `level waittilltimeout( 25, #"switchmap_preload_finished" )` — probe 41 = did it signal, and when
5. `switchmap_switch()`

| Outcome | Means |
|---|---|
| scoreboard / pause menu / AAR say **Y + Gunfight** | 🔓 **Goal B closed.** The carry was using the wrong builtin all along. Replace `map()` in `gunfight_mod` and the menu |
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

### B2 · What the glitch actually does — ❓ THE question, and only klaze can answer it

Every note in this repo refers to "the lobby glitch" and none records its steps. It is the *control*
for Goal B — the thing that provably produces the correct session state — and this project cannot
compare against a mechanism it has never written down.

❓ **What are the exact steps of the glitch, from the main menu to the match starting?** Every
button, in order, including anything that involves a search or a playlist.

❓ **Does any step involve matchmaking or a public search?** The project's first ground rule is
private matches only. If the glitch briefly touches a public queue, that has to be known before it is
automated, because automating it changes the risk.

❓ **After the glitch, is *everything* right — spawns, map voting, the lobby's map list afterward,
the AAR — or is anything off?** "Everything" means the glitch is a full playlist reconfiguration and
B1 may not be able to match it. "Some things off" means it is closer to what we do than it looks.

❓ **Where exactly does the carry's UI go stale?** Scoreboard, pause menu, AAR, loading screen, the
lobby afterwards — all of them, or some? Each reads a different source, and the pattern of which are
stale locates the record `map()` fails to update.

---

## Order of work

1. **B1** — one match, read-only pass then live. It is cheap, it has three stock precedents, and if it
   works it changes what the menu in A1 is built on. **Do not build A1's map control on `map()`.**
2. **A1** — the menu. Everything in it except the map/mode entries is already proven; those two wait
   on B1.
3. **D10** — the command list, when pregame control's priority is settled (❓ above).
4. **A2**, then **A3**.

⚠ In parallel and unrelated to either goal: **a human 4v4** is still the largest gap between "closed"
and "done" — see the Open questions in `.claude/CLAUDE.md`. Nothing here should jump that queue.

## Untried — not ruled out

- `func_set_mapgametype`'s full three-step (preload → load → switch) rather than load → switch
- Whether `transitionMapIdOverride` alone — no switch — changes what the pause menu shows
- `luinotifyevent` with a lobby-shaped event before switching, the way side missions do
- Whether the glitch's session state survives a *second* switch (glitch to Hijacked, then B1 to Zoo)
- A pregame GSC hook: `frontend.csc` runs client script in the lobby-pose scene; whether any
  server-side script runs there at all has never been checked
