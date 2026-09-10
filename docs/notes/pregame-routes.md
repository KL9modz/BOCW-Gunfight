# Pregame routes — what can reach the lobby BEFORE the match starts

klaze, 2026-09-09: *"pregame control would be the single most valuable mod for this entire project."*
This note is the research behind it: every route from our code to the pregame lobby that the dump,
the ACTS source and ate47's notes support, what each has going for it, and the one test that decides
the cheapest of them. **Nothing here is measured in-game unless the line says so.**

▶ **The headline: GSC runs in the pregame lobby, and the lobby keeps a live gametype-setting store
that script can read.** Both were recorded as false in three files. The test is built:
[`../../src/test_frontend/`](../../src/test_frontend/), read-only by default, offline checks green,
never compiled or injected.

▶ **And the save format has room for all of it (P5):** a saved custom game is the match-time settings
blob itself — same struct, `mp_custom_game.ddl` — with `maxplayers` in seven bits. Get one modded
value into a save and it loads from the account with no injection. Whether the in-match write already
flows back into the lobby is a question klaze can answer from memory.

---

## The claim this retracts

`roadmap.md` A2 opened with *"Nothing GSC runs in the pregame lobby."* `lobby-settings.md` said
*"`frontend.gsc` is NOT the lobby … do not go looking for the lobby in GSC."* `.claude/CLAUDE.md`
carried the same line. All three rested on one reading of `frontend.gsc` — a 618-line file whose
retail portion is **108 lines**; everything from `:110` down is one `/# … #/` dev block. What the
retail part does:

| `frontend.gsc` | What it is |
|---|---|
| `:35` `event_handler[gametype_init] main()` | the frontend map's gametype handler — a **server-side** script running in the front end |
| `:46` `gamestate::set_state( #"pregame" )` | it sets **the pregame state**. `gamestate.gsc:31` → `game.state = #"pregame"; level notify( #"pregame" )` |
| `:49` `callback::add_callback( #"menu_response", … )` | a LUI → GSC channel, live in the lobby (`callbacks_shared.gsc:2054` queues it from `event_handler[ui_menuresponse]`) |
| `:37-41` `level.callbackplayerconnect = …` | players **connect** in the frontend — the local player is an entity there |

"Not the lobby" was right about one thing: **map, mode, rules and invites are not written in GSC.**
Those live in compiled LUA and the session layer. But *"nothing GSC runs there"* was wrong, and the
question that matters — can script **read and write the lobby's gametype settings** — was never asked.

## The evidence, split by where it comes from

⚠ ate47's `t8-atian-menu/docs/notes/loaded/` is a **BO4 capture**, not Cold War: 28 of the 216
scripts it names (`tabun.gsc`, `platoons.gsc`, `shoutcaster.csc`, the `ai/planner_commander*` set)
do not exist in the CW dump. It is same-lineage evidence with numbers, and it is quoted here as
exactly that. The Cold War-native evidence stands on its own.

### Cold War (primary dump, `ate47/bocw-source`)

- **Eleven stock GSC files guard on `util::is_frontend_map()`** (`util_shared.gsc:5889`,
  `return get_map_name() === "core_frontend"`). Two of the guards sit in **system preinits** —
  `bot.gsc:39`, `player_shared.gsc:29` — and the rest in `spawning_shared.gsc:36`,
  `scene_shared.gsc:129`, `death_circle.gsc:42`, `dynent_use.gsc:24`, `item_world_util.gsc:356`,
  `player_shared.gsc:131`, `spawning_squad.gsc:1267`, `bot_devgui.gsc:27`, `mp_common/player/player.gsc:160`.
  **Stock does not guard against a VM it never runs in.** So `core_common` — callbacks, system, util —
  links and its preinits execute in the frontend server VM.
- **ACTS documents the hook.** `t8-atian-menu/coldwar/gsc.conf`: *"Recommended injection points: MP:
  `scripts\mp_common\bb.gsc` · ZM: `scripts\zm_common\load.gsc` · Frontend:
  `scripts\core_common\load_shared.gsc`"* — and `load_shared.gsc:63` `preinit()` branches on
  `sessionmodeiscampaigngame()` / `…zombiesgame()` / else, with **no MP gate**: it is the one script
  written to run in every VM.
- **The frontend re-links from the pool on every return.** That is what the `scene_model_shared`
  hang measured (`menu-map.md`): a replaced buffer that the frontend needed at link time hung
  "connecting to lobby". Same mechanism, this time on purpose.
- **`frontend.csc:2918-2920` reads gametype settings from inside the lobby:**
  ```
  if ( level.lastlobbystate === #"matchmaking" || … === #"lobby_pose" ) {
      …
      if ( is_true( getgametypesetting( #"hash_5462586bdce0346e" ) ) )
          var_ca8c236b = min( getgametypesetting( #"hash_3a4691a853585241" ), var_68a9a63c.size );
  ```
  `hash_3a4691a853585241` is **`maxsquadplayers`** (cracked, validated in-game by L5). The client
  script caps the lobby's character line-up by a *gametype setting of the pending game*, on
  `#"lobby_change"`, in `lobby_pose`. **So the engine keeps a gametype-setting store while the
  lobby is being configured, and script can read it.** ⚠ That is the CSC (client) VM. The GSC
  builtin has the same name and the same 1-arg form; whether the server VM's store is the same
  object is untested — that is probe 52.
- **`getgametypesetting` has GSC frontend precedent only behind a guard.** `bot.gsc:39-49`:
  `if ( util::is_frontend_map() ) return;` … `getgametypesetting( #"hash_77b7734750cd75e9" )`. Either
  the call throws in the frontend or its answer is meaningless there; the guard cannot say which.
  Probe 50 (tick count stashed before the read) separates the two.

### BO4 (ate47's capture — same lineage, not the same game)

`loaded/link_frontend.txt`: **`instance SERVER(0) : 190 loaded script(s)`** in the frontend, among
them `callbacks_shared` (refCount 63), `system_shared` (80), `util_shared` (86), `array_shared`,
`gamestate`, `bots/bot.gsc` (11), **`load_shared.gsc`** (`:172`, refCount 2) and
**`clientids_shared.gsc`** (`:171`, refCount 1) — the hook *and* the replace target, in the pool at
the main menu. `bb.gsc` and the rest of `mp_common` are absent from the server instance. And
`scripts/core/frontend.gsc` — BO4's `frontend_exec_delay()`, kept in ate47's own menu source and
**left disabled**, iterates `getplayers()` for `ishost()` in the frontend: the injected script ran
there, the local player was an entity, and he stopped at `wait 10` with the interesting lines
commented out. Precedent for *running*; none for *controlling*.

---

## Routes

### P1 · A frontend GSC payload ← **built: `src/test_frontend/`**

Hook `load_shared.gsc` instead of `bb.gsc`; same replace target. The payload links in **every** VM,
and `util::is_frontend_map()` — the check stock itself uses — decides which half runs.

| | |
|---|---|
| Inject | at the **main menu**, no match needed first (⚠ predicted from BO4's `pool_frontend.txt`; `inject.sh` says what to record if CW differs) |
| Goes live | MP half on the next match; **frontend half on the next return to the lobby after a match** |
| `#using` | **core_common only.** `mp_common` is not loaded in the frontend and pulling it in from there is an untested link. `gunfight_menu` `#using`s `mp_common\gametypes\gunfight` and `bots\bot` — it **cannot** simply be re-hooked |
| Output | **dvars.** Nothing is known to render in the lobby; `iprintlnbold` is tried and expected to show nothing. Each reading is stashed as `gf_fe_<id>` and printed by the in-match half of the same payload — dvars survive the transition (B4 proved they survive `map_restart`) |
| Input | none yet. `usebuttonpressed` & co. on the frontend player are untested; BO4's disabled `frontend_exec_delay` is the only precedent and it reads no buttons |
| Trigger | `level thread` from the system preinit (stock does the same, `load_shared.gsc:71-77`). **Not** `callback::on_start_gametype` — its three dispatch sites are cp/mp/zm `globallogic`, none of which exist in the frontend |

**What the read-only run answers** (probe ids in the file header): whether the frontend half runs at
all (50); the session flags there (51); `com_maxclients` seen from the lobby (58); the lobby client
count builtin (55); **`maxplayers` / `timelimit` / `maxsquadplayers` as the lobby sees them** (52–54)
— reading **6 / 40 / 0** in a 3v3 lobby, the same numbers L5–L7 measured in-match, says the frontend
store *is* the pending lobby config; whether the timer row's value shows up live in 53 says whether
the store follows the menu as it is edited.

### P2 · `setgametypesetting()` from the lobby — the write phase of the same payload

`write_maxplayers = 1` writes `maxplayers = 8` on every 10s sample and reads it back (59). Three
readouts, none of which needs a probe:

1. **the rules menu** — with `write_timelimit = 1` instead, the timer row is a visible mirror of the
   store: if it shows 60 without being touched, the write reached what the UI reads;
2. **the lobby** — can a 4th bot or player be placed on a side? klaze's lobby walk says a 3v3 lobby
   refuses the 4th today. If that refusal follows `maxplayers` the way the in-match cap did (L6), it
   lifts here, and **the stock join path seats a 4v4 with no late-join hack at all**;
3. **the match** — probe 60 reads `maxplayers` before anything in-match writes it. **8 = it
   carried.**

⚠ Hypothesis, stated as one: the per-team cap at connect is `getassignedteamname()` (engine,
`player_connect.gsc:433`), and the lobby's cap is the same session's. Both *should* read the same
`maxplayers`. "Should" is what P2 measures.

⚠ Both switches default to 0, one at a time, and the write repeats per sample because the store may be
rebuilt when the mode is picked or the lobby created — a single early write would just be overwritten.
That repetition is itself untested behaviour. Lobby return after each run.

### P3 · `adddebugcommand()` — the console from script, if it is alive

`adddebugcommand( 1 arg )` and `canadddebugcommand()` are in the CW function table
(`BlackOpsColdWar.exe+3c60330` / `+3c60340`). All **409** stock call sites are inside `/# #/` blocks.
ate47's BO4 table annotates the BO4 pair **"nulled; cbuff('$command')"** and **"return false"** and
flags them `dev`; **the CW rows carry no annotation and are NOT dev-flagged** (type `0`, where CW's
110 dev-flagged builtins — `print`, `recordline`, `box` — are `1`). Three readings of that: he never
checked CW; CW differs; the flag means something else. **One test settles it**, `debugcmd = 1` in
`test_frontend`: `adddebugcommand( "set gf_fe_dbg 7\n" )` then read the dvar (62). `set` is on the
resolved T8 command list; a private dvar is the only thing it can change.

▶ **If 62 reads 2 or 3, the console is reachable from GSC** — in the match *and* in the lobby — and
every command-shaped route below collapses into one script line: `gametype_setting`, `map`,
`lobbylaunchgame` without cwpatch, without the DLL slot, without `dcfuncscw`. If it reads 4, CW is
nulled like BO4, which is what the BO4 note predicts. Either is a measurement.

### P4 · Console commands from the DLL slot — the existing route, currently blocked

[`lobby-map-dll.md`](lobby-map-dll.md). The mechanism is proven (cwpatch overwrites the command blob
and calls the dispatcher from `discord_game_sdk.dll`); the command *list* is not: **D10 ran on
2026-09-08 and `acts dcfuncscw` returned a header and zero rows** — ACTS's hardcoded
`cmd_function_t` base is stale for this build. `tools/crack-cmds.py` is now seeded with all 449
resolved BO4 console names (`gametype_setting`, `gametype`, `map`, `customgames_save/load/count`,
`lobbyrunplaylistsettings`, `lobby_reload`, `lobbylaunchgame`, `sendinvite`,
`joinplayersessionbyxuid`) so the moment a table exists, the cracker has the right vocabulary. Until
then the route needs runtime RE against an encrypted exe. P3 is the cheap way around it.

### P5 · Saved custom games — klaze's idea, and the DDL says the format has room for everything we set

klaze, 2026-09-10: *"the game lets you 'save' custom game mode settings. potentially letting me save a
modded one to my account?"* The dump ships the save format, so most of this is readable offline.

**The Cold War save format is `ddl/mp_custom_game.ddl`** — 69 versions, one per patch that touched a
setting, because saved blobs must migrate. Its root:

| Field | Width | Note |
|---|---|---|
| `loadoutversion` | int | |
| `hash_b1850166655019a` | int | **uncracked** — ~150 guesses across map-index / version / id vocabularies missed |
| `gamedescription` / `gamename` | string(128) / string(64) | ⚠ if the UI caps at these lengths, the format is confirmed against the game for free |
| `createtime` | int | |
| `gametype` | string(32) | |
| **`gametypesettings`** | 0x65b30 bits, **993 members** | **byte-identical to `mp_gametype_settings.ddl`'s root member** (`:2843-2844` in both files) — the match-time settings blob |
| `inuse`, `downloaded`, `loadoutinitialized` | bool | `downloaded` = fileshare |
| `hash_3d4fd60ba0b69eb[mpmaps]` | 43 bools | **a per-map flag array** — the map list, at root, *outside* the settings struct. Name **uncracked** (~180 guesses). `zm_custom_game.ddl` has the same root with `[zmmaps]` (5) |

So **a saved custom game IS the match-time settings blob, plus a name, a gametype string and a
per-map enable list.** Inside that blob, every value this project writes from script has a slot:

| Setting | In the save | Width | Room for |
|---|---|---|---|
| `maxplayers` | `:3022` | `uint:7` | 0–127 — **8 fits, 10 fits, 12 fits** |
| `timelimit` | `:2846` | `fixed<8,2>` | |
| `gunfightloadoutindex` (`hash_3b05ecbff72f1065`) | `:3554` | `uint:5` | snipers / melee presets |
| `gunfightspyplane` | `:2888` | `uint:2` | the hidden value 3 |
| `gunfightroundsperloadout` | `:3584` | `uint:3` | |
| `maxsquadplayers` | `:3446` | `uint:6` | |
| `allowingameteamchange` | `:4778` | bool | |

⚠ **What the save does NOT carry: the current map.** There is no map field in the root — only the
per-map enable flags. The map being played lives in the session and in presence (`presence.ddl`:
`int mapid`, `int gametype`, `int playlist`), not in the save. So a save cannot hold "Gunfight on
Hijacked" as *the map*; it can at most hold *which maps are enabled* — and that array sits outside
`gametypesettings`, so `setgametypesetting()` cannot reach it even in principle. It is LUA's.

🪦 `ddl/custom_games.ddl` is **not** the CW save: a BO4-era six-slot format (`customgames[6]`,
`gametype string(8)`, `maxplayers uint:4`, **zero Gunfight rows** across all ten versions), kept for
migration. `fileshare_customgame.ddl` wraps that legacy struct for the file share.

**Where it lives — expected cloud, not measured.** The `downloaded` flag, the BO4 console verbs
(`customgames_save` / `_load` / `_count`, `gamesettings_upload` / `_download`, `storagewriteddl`,
the `fileshare*` family) and Activision's own statement that every setting except graphics syncs
through the account all point at Demonware storage, like custom classes. ▶ **Measured in one
minute with no code:** save a custom game, sort `%USERPROFILE%\Documents\Call Of Duty Black Ops
Cold War\player` by modified time. A new or changed file = local, and the DDL above is its schema.
Nothing = cloud. ⚠ If it is local, an offline edit is *technically* the lowest-exposure route in the
whole project (no process handle, no memory write) — but the blob is then uploaded with a value no
menu can produce, and whether the service validates it is unknowable from here. klaze's call, not
the note's.

**How a modded value gets into a save.** Two ways, and one of them may already work:

1. **Match → lobby → Save.** `gunfight_mod` writes `timelimit = 60` in-match every time. After that
   match, back in the lobby, **does the rules-menu timer row read 60?** If the in-match write flows
   back into the lobby's copy, then *Save* captures modded settings **today, with no new code**,
   and *Load* replays them into a fresh lobby before anyone is seated. klaze has run that match a
   dozen times and may already know the answer. If the row reads 40, the match's copy is discarded
   on return, and it is route 2.
2. **Lobby write → Save.** P2's `setgametypesetting( #"maxplayers", 8 )` from the frontend — if it
   lands in the live `mp_custom_game` blob rather than a runtime copy, *Save* captures it. Same test,
   one more readout.

Either way the payoff is the same: after one successful save, **`maxplayers = 8` lives in the account
and loads with no injection at all**, and the lobby's own seating logic gets the value before the
first player connects. ⚠ Whether *Load* re-validates values against the rules bundles is the
unknown that survives both routes; the menu shows 6 values for a timer the setting accepts 1440 of,
and nobody knows whether *Load* is a menu or a memcpy.

❓ **"Save Online Game Modes To Custom Games"** — a YouTube title (`tdosMUo3pMY`, egress-blocked here)
says CW can save an *online playlist's* mode into Custom Games. If that is real, it is the designed
version of what the glitch does by accident: a playlist's settings blob copied into a save. Worth
knowing exactly what it copies — settings only, or the playlist's map list too.

### P6 · The LUI channel

`luinotifyevent` (GSC → LUI, `frontend.gsc:536-540` uses it in dev) and `menu_response` (LUI → GSC,
retail, `frontend.gsc:49`) are both live in the lobby. Without LUA we can only fire events stock LUI
already listens for and only receive what stock LUI already sends. Useful as a *display* channel for
P1 if a lobby-visible event with a payload exists; not a control route on its own. Untried.

---

## Builtins with no stock caller that belong to this layer

| Builtin | Table | BO4 annotation | Note |
|---|---|---|---|
| `enablelobbyjoins( bool )` | GSC `+3c6b150` | — | **a write.** Not in the probe. What it closes or opens is unknown |
| `getlobbyclientcount()` | GSC `+3c6b110` | *"client count + join count"* | probe 55 |
| `getlobbyuiscreen()` | GSC `+3d197a0` | *"get lobby ui screen"* | probe 57; return type unknown, `isint()`-guarded |
| `islobbybot()` | GSC method `+3c5b540` | — | per-entity; `bot::add_bot()` territory |
| `function_5f72e972( #"lobby_root" / #"lobby_clients" )` | CSC, **defined nowhere** | — | engine accessor for the lobby UI-model roots; `lobby_clients` has per-slot `entNum` / `visible` children (`frontend.csc:2588-2610`) |
| `function_77ccb73( 1 )`, `function_664bca26( lc, 1, 0 )` | CSC, defined nowhere | — | return xuid arrays the lobby line-up is built from (`frontend.csc:2909-2920`) — the roster, readable client-side |

`sessionmodeisprivate()` / `sessionmodeisprivateonlinegame()` / `sessionmodeisonlinegame()` are the
predicates a lobby payload gates on; probe 51 reads three of them.

## What this would change, if P2 lands

Every team-size route so far acts **after** the session has seated people — `maxplayers` in-match
(L6), late-join seating (C10/C11), the menu's move-player (A1). All of them fight
`getassignedteamname()`'s verdict at connect. A write that lands **before** anyone connects makes
that verdict come out right on its own, for humans, through the stock path, with nothing to undo at
the round boundary. That is why this is A2 and why it outranks polishing A1.

## Untried — not ruled out

- Whether `load_shared.gsc` / `clientids_shared.gsc` are in the CW pool at the main menu (BO4 says
  yes; `inject.sh` records the answer either way)
- Whether the frontend half's `iprintlnbold` renders anything in the lobby at all
- Button builtins on the frontend player — the input half of a lobby menu
- Whether `setgametypesetting` in the frontend touches the lobby *UI* (the rules row), the *launch*
  (probe 60), both, or neither — four outcomes, and each is informative
- `enablelobbyjoins( 0 )` as a "lock the lobby" control
- Writing `lobby_root.transitionMapIdOverride` from the frontend before `lobbylaunchgame` — the
  campaign writes it before its own map switch (`cp_common/load.gsc:398`); the lobby's launch may
  read the same field
- A `luinotifyevent` with a lobby-visible payload as P1's display channel
- P5's on-disk preset, and whether the cloud overwrites it
- The `menu_response` callback in the lobby: which stock menus send one, with what `response` /
  `intpayload` — a free input channel if any lobby button reaches it
- `hash_5462586bdce0346e`, the flag gating the `maxsquadplayers` read at `frontend.csc:2918` —
  uncracked; a squad-lobby feature switch by context
- `hash_3d4fd60ba0b69eb` (the per-map flag array) and `hash_b1850166655019a` (the root int) in
  `mp_custom_game.ddl` — both uncracked after ~330 guesses; the map array's name is the one worth
  having, because it is the custom-games map list
- Whether *Load* clamps a saved value to the rules bundle, or restores it verbatim
- What "save online game mode to Custom Games" copies — settings only, or the map list as well

---

## ✅✅ P1 RESULT — 2026-09-09. **GSC RUNS IN THE PREGAME LOBBY. Confirmed in-game.**

`src/test_frontend/` injected at `load_shared.gsc`, read-only, all write switches off. Sequence:
match (links MP half) → lobby, ~1 min, switched to 3v3 (links frontend half, samples into dvars) →
match (prints the stash). Read by screen capture.

| Probe | Read | Meaning |
|---|---|---|
| `51xxxxx` flags | **63** | **ALL SIX BITS.** `is_frontend_map` + private + multiplayergame + onlinegame + `getplayers().size > 0` + one answered `ishost()` |
| `52xxxxx` `maxplayers` **in the lobby** | **6** | 🔓 **THE READ.** 6 in a 3v3 lobby — **the frontend store is the pending lobby config** |
| `54xxxxx` `maxsquadplayers` | **0** | control, consistent with L5's in-match reading |
| `58xxxxx` `com_maxclients` **in the lobby** | **2** | ⚠ **not 10.** See below |
| `60xxxxx` `maxplayers` in-match | **6** | matches probe 52 exactly |
| `61xxxxx` `timelimit` in-match | **40** | default, `gunfight_mod` not injected |

▶ **"Nothing runs in the pregame lobby" is dead, and it was never measured.** A server VM executes
there, `util::is_frontend_map()` answers true, and there is a **player entity that answers
`ishost()`** — so player-scoped calls are available in the lobby, not just level-scoped ones.

▶ **The frontend store is the pending lobby config.** Probe 52 (lobby) and probe 60 (match) both read
**6** for the same 3v3 lobby. Whatever the frontend holds is what the match receives. **That is the
layer this project has been unable to reach all along** — every wall (playlist, team size,
`com_maxclients`) is set there, before anyone is seated.

🔓 **NEW, and it reframes `com_maxclients`: it reads 2 in the lobby and 10 in the match.** So it is
**not** "fixed at lobby creation" as this project has recorded since the beginning — it is *derived at
match start*, and the lobby's value is a placeholder. ⚠ That does not make it writable; L8 measured
that writing `maxplayers` does not move it. But it does mean the thing that computes it runs **after**
the frontend store is read, which is a different and more promising place to intervene.

▶ **Next: the write phase.** `write_maxplayers = 1`, one switch, one launch. Probe 59 reports whether
the write took and whether the read-back matched; probe 60 says whether it **carried into the match**.
That is the whole pregame-control question, and P1 has established the reads are honest.

⚠ Probe 50 (sample count) was not captured — the emit order is `60, 61, 50, 51, 58, 56, 55, 52, …` at
5s intervals, and a ~40s Gunfight round truncates it. **Probe 51 reading 63 rather than 99999 proves
the frontend half ran**, which is what 50 exists to establish, so this is a gap in the record and not
in the finding. ▶ For the write run, either lengthen the round (`gunfight_mod` cannot coexist) or read
the frames around emit position 3.

## 🔓🔓🔓 P2 RESULT — 2026-09-09. **THE PREGAME WRITE WORKS. 4v4 CONFIGURED FROM THE LOBBY.**

`test_frontend` with `write_maxplayers = 1`, `maxplayers_value = 8`. Injected **at the main menu** —
which incidentally confirms the prediction that `load_shared.gsc` is in the scriptparsetree pool with
no match loaded first (previously backed only by ate47's **BO4** capture, now measured on CW).

Walk: match (links MP half) → lobby, 3v3, ~30s (frontend half writes `maxplayers = 8` every sample) →
team screen → start.

▶ **klaze: *"i did not notice any options but it let me put 4 bots on a team and start the match 4v4."***

✅ **Confirmed on the HUD**: four player icons per side, team health 150 vs 356 — four players each.

### Why this is better than the in-match route it replaces

| | in-match (`gunfight_mod`, L6) | **pregame (P2)** |
|---|---|---|
| When it acts | after the match starts | **before anyone is seated** |
| Team screen | still shows the old cap | **accepts a 4th on a side** |
| Needs a running match | yes | **no** |
| Survives the round boundary | needed L6 to prove it | not applicable — the lobby is already configured |

▶ **The team screen honoured it with no menu row appearing.** klaze saw *no new options* — the pending
config simply allowed a 4th. So the cap the team screen enforces reads from the same store the
frontend half writes.

⚠ **Probes 59 and 60 were NOT captured** — the match ended (Best Play) before the emit sequence reached
position 12. So "the write's read-back matched" is **not** directly measured; what is measured is the
behaviour, which is stronger evidence for the goal but weaker evidence about the mechanism. Re-run for
59/60 if the mechanism matters. Probe 58 re-read **2** (lobby `com_maxclients`), consistent with P1.

⚠ **Bots, not humans, again.** The team screen accepted them, which is more than the in-match route
ever achieved — but a human 4th joining a pregame lobby is still untested.

### ⚠ 3v3 Gunfight's rules menu is missing SEVERAL rows that normal 2v2 has

klaze, 2026-09-09: *"3v3 for some reason does not have the lobby match option for timer like 2v2 does.
3v3 seems to be missing several custom options that 2v2 has in the lobby."*

`.claude/CLAUDE.md` already recorded the timer row specifically. **It is broader than one row** — the
per-variant filter strips a set of options from 3v3, and which ones is unenumerated.

▶ **Practical consequence, and it redirects the next test:** any check that needs to SEE a value in the
rules menu must run in a **normal (2v2) Gunfight lobby**. A `write_timelimit` run in 3v3 would write
correctly and show nothing, and the silence would be indistinguishable from failure.

▶ **2v2 is also the better team-size test.** It baselines at `maxplayers = 4`, so writing 8 asks a
lobby that normally caps at **2 a side** to accept **4** — double, against 3v3's +1. And the timer row
exists there for a second, independent confirmation in the same run.

⚠ **Worth enumerating at some point:** walk both variants' rules pages side by side and list what 3v3
is missing. `settings-xref.py` maps settings to bundles, but which rows a *variant* publishes is
playlist-layer and not in the dump — so this can only come from a menu walk.

### ▶ Two builds ready — one launch each, both to be run in a **normal 2v2 lobby**

Same `src/test_frontend/` source, different compiled-in switches. Variants are staged at
`C:\bocw\build-variants\` and built into `$GF_PAYLOADS`. `tools/inject.sh` knows both names and gives
them the `load_shared.gsc` hook.

| Payload | Switch | What to watch |
|---|---|---|
| `test_frontend_maxp` | `write_maxplayers = 1`, value **8** | **the team screen.** 2v2 caps at 2 a side — does it accept **4**? Double, vs 3v3's +1 |
| `test_frontend_time` | `write_timelimit = 1`, value **60** | **the rules-menu timer row, in the lobby, without starting anything.** 2v2 HAS this row; 3v3 does not |

▶ **`test_frontend_time` is the cheaper and more diagnostic of the two.** It needs no match at all: if
the row reads 60, the pregame write is confirmed *visually*, which is the confirmation P2 could not
give because the match ended before probes 59/60 printed. Run it first.

⚠ **One per launch** (B9). ⚠ **2v2, not 3v3** — a timer write in 3v3 would land correctly and display
nothing, and the silence would look exactly like failure.

## 🔓🔓🔓 P3 RESULT — 2026-09-09. **THE RULES MENU SHOWS THE PREGAME WRITE. 60s, in the lobby.**

`test_frontend_time` (`write_timelimit = 1`, value 60), normal **2v2** Gunfight lobby, injected at the
main menu. Walk: one match → lobby → ~30s → open the rules menu.

▶ **klaze: *"it shows 60s!"*** — the timer row, in the lobby, **with no match started**.

### Pregame control is CONFIRMED on all three surfaces

| Surface | Evidence |
|---|---|
| Rules-menu **display** | ✅ P3 — the row reads 60 |
| Team-screen **cap** | ✅ P2 — accepted a 4th on a side |
| The **match** receives it | ✅ P2 — 4v4 played; P1 — probe 52 (lobby) == probe 60 (match) |

▶ **This is the confirmation P2 could not give.** P2's match ended before probes 59/60 printed, so the
read-back was inferred from behaviour. P3 needs no probe and no match at all: the value is on screen,
in the pregame UI, written by GSC.

▶ **It also supersedes the in-match approach for SETTINGS.** `gunfight_mod`'s `timer_override` and
`team_size_override` fight the round boundary and leave the lobby UI stale. A pregame write is in the
lobby's own store before anyone is seated — no boundary to survive, and the UI is correct because it
is reading the same value.

### 🔓 P5 IS BACK — and 0.1 is the reason it now might work

Stage 0 question **0.1** measured that an **in-match** write does NOT flow back to the lobby's copy
(timer read 40 on return, with `gunfight_mod` live). That killed *Save Custom Game* as a route.

⚠ **A pregame write is not an in-match write.** P3 puts 60 **in the lobby store itself**, which is the
thing the save serialises — `mp_custom_game.ddl`'s `gametypesettings` member is the match-time settings
blob byte for byte. So:

▶ **Free test, no injection, ~2 minutes: with the pregame write still applied and the row reading 60,
SAVE THE CUSTOM GAME. Then relaunch clean, with nothing injected, and load it.** If the timer row still
reads 60, **the mod's settings persist on the account with no injection at all** — and every future
match starts from a saved, modded config.

⚠ Not predicted either way. The save may serialise from a different store than the row displays.

### ⚠ P3's save test was INVALID — 60 is a menu value. klaze caught it.

klaze, 2026-09-09: *"i could have saved a game with 60s myself normally."* **Correct, and it voids the
save half of P3.** `scriptbundle/gamesettings/time_limit_seconds.json` declares 20 values but sets
`"optionscount": 6`, so the row publishes **0 / 20 / 30 / 40 / 50 / 60**. A save containing 60 is
indistinguishable from one a player made by hand — it proves the save works, not that it captured
anything modded.

⚠ **P3's LOBBY result still stands.** The row reading 60 after a GSC write, with no match started, is
unaffected — that was about the write reaching the display, not about persistence.

▶ **The fix: write a value the menu CANNOT produce.** `test_frontend_t90` writes **`timelimit = 90`**,
which is off the published list entirely. If a saved game loads at 90 on a clean launch with nothing
injected, that is unforgeable — no menu path to it exists.

### 🔓 The save button is gated on a UI dirty flag, and the GSC write does not set it

klaze: *"i actually cant save it unless i edit something else first."* The pregame write lands in the
store and renders in the row, but **Save stays disabled until the player edits some other row by
hand**. So the UI's "something changed" flag is separate from the value store the write reaches.

▶ **Workaround, already proven to work:** change any unrelated row by hand, leave the written value
alone, then save. klaze did exactly this.
⚠ **Worth knowing for any future auto-save route** — a script that writes settings and expects to save
them without a human touching the menu will find Save greyed out.

### ⚠ The unconditional write RACED THE RULES MENU — fixed, and the race is itself a finding

klaze, 2026-09-09, running `test_frontend_t90` (`timelimit = 90`):
*"almost every time i open the match options, it reads a different time. then i started the match and
the round began with like 1:03 on the clock."*

▶ **The row first rendered "unlimited".** That is a DISPLAY fallback, not a clamp: `value1` is `0` and
its label is `menu/unlimited`, so the row maps a value to a published option index and 90 has none.
**What it renders is not what the store holds.**

▶ **And the write was not rejected.** A match starting at ~**1:03** is neither the 40 default nor
unlimited, so the written value reaches the match. It simply never **settled**.

🪦 **Cause: our own design.** The frontend half wrote on *every* 10s sample, unconditionally. The rules
menu renders by mapping to an option index and commits on its own cycle, so the store was whatever
touched it last before each read — hence a different number every time the menu opened.

✅ **Fixed: `write_and_check()` is now IDEMPOTENT** — it reads first and writes only when the value is
not already the target. New return **4** = already correct, nothing written. A settled run reads **2**
once and then **4**; a 2 that never becomes 4 means something else keeps overwriting us, which is a
finding rather than a malfunction.
⚠ The old every-sample write existed to survive the store being rebuilt on mode/lobby change. **Still
handled** — a rebuild makes the read-back stop matching and the next sample rewrites. Only the
hammering stops.

⚠ **Consequence for the whole pregame route, and it is not small:** an off-list value is **invisible in
the rules menu by construction**. Any modded setting outside a row's published options will render as
whatever option index the UI falls back to. **Judge these writes by the MATCH, not by the menu** — the
menu is a lossy view. P3's 60 displayed correctly only because 60 is a published option.

## 🔓 THE 1:03 IS A FIELD-WIDTH CAP. `timelimit` cannot exceed **63.75 seconds**.

Writing `timelimit = 90` produced a **63-second round, twice, deterministically** — so the earlier
"unstable write racing the menu" theory does not explain it. The dump does:

```
ddl/mp_gametype_settings.ddl:2846    fixed<8,2> timelimit;
ddl/mp_custom_game.ddl:2846          fixed<8,2> timelimit;      // same field in the SAVE blob
```

**`fixed<8,2>` = 8 bits, 2 fractional bits → max representable value `255 / 4 = 63.75`.** A write of 90
saturates to 63.75 and the round clock reads **1:03**.

⚠ **The grace period is a red herring here, and it nearly fit.** `gunfight.gsc:99` sets
`level.graceperiod = 3`, so "60 + 3" also produces 63 — a coincidence that would have supported the
wrong conclusion (that the value was clamped to the menu's published max of 60). The field width is the
explanation that survives, because it predicts 63.75 rather than 63 exactly, and because it is
structural rather than inferred.

### What this settles

| Claim | Status |
|---|---|
| "The menu cap says nothing about what `setgametypesetting()` accepts" | ✅ **still true** — the menu stops at 60, the field allows 63.75 |
| Longer Gunfight rounds via the `timelimit` **setting** | 🪦 **IMPOSSIBLE.** 63.75s is a hard ceiling in the data format |
| `gettimelimit()`'s `[0, 1440]` **minute** clamp | ⚠ **irrelevant** — the setting cannot hold a value big enough to reach it |
| `gunfight_mod`'s `timer_override` | 🔓 **the ONLY route to rounds > 63.75s**, and now explained: it overrides `level.gettimelimit` directly and never passes through this field |

▶ **So the two mechanisms are complementary, not redundant.** Pregame writes own everything up to
63.75s and are visible before the match; `timer_override` is required for anything longer and always
will be. An earlier note called `timer_override` superseded by the pregame route — **that is wrong for
any round longer than 63.75s.**

⚠ **Check other settings for the same trap before trusting a big write.** `maxplayers` is `uint:7`
(max 127), which is why 8 and 10 both took cleanly — but any `fixed<n,m>` or narrow `uint:n` field has
a ceiling that will silently saturate rather than refuse. **The DDL is the place to look, and it is
free.**

### ⚠⚠ CORRECTION — the field-width conclusion above is NOT settled. Two hypotheses fit.

klaze: *"maybe its 62s"* — and that prompted a recheck that the previous section should have done
before concluding. **Both explanations predict a ~63-second clock**, and they differ only in whether
the round clock includes the 3s grace period:

| Hypothesis | Store holds | Clock if grace is ADDED | Clock if grace is NOT added |
|---|---|---|---|
| **H1** field saturation, `fixed<8,2>` → 63.75 | 63.75 | ~1:07 ✗ | **1:03 ✓** |
| **H2** clamped to the menu's published max | 60 | **1:03 ✓** | 1:00 ✗ |

⚠ **62 vs 63 does not separate them** — that is just when the clock was read. What separates them is
whether grace shows on the clock, and the dump does not answer it cleanly: `globallogic.gsc:4904`
`graceperiod()` is a concurrent `wait`, and the clock is `setgameendtime( gettime() + timeleft )` off
`level.timelimit * 60`.

▶ **THE DECISIVE TEST, and it is one launch: write `timelimit = 30`** — a published value, far below
both ceilings.
- clock starts **0:30** → grace is not on the clock → **H1**, the `fixed<8,2>` ceiling is real
- clock starts **0:33** → grace is on the clock → **H2**, and the write was clamped to the menu max
  of 60, which would mean `setgametypesetting()` **is** bounded by the published option list — a
  retraction of one of this project's standing claims

⚠ **H2 is the more consequential outcome**, which is exactly why it should not be assumed away. The
`fixed<8,2>` reading is *structurally* true regardless — 63.75 IS the field ceiling — but that does not
prove it is the ceiling we hit at 90.

## 🔓🔓🔓🔓 P5 CLOSED — **A SAVED CUSTOM GAME CARRIES THE MODDED TEAM SIZE. NO INJECTION.**

2026-09-10. `test_frontend_maxp` (`write_maxplayers = 1`, value 8) injected at the main menu into a
**normal 2v2** lobby. Walk: match → lobby → ~30s → edit an unrelated row to un-grey Save → **Save
Custom Game** → **quit, relaunch, inject NOTHING, load the save.**

▶ **klaze: *"holy shit...it worked"*** — 4 per side, from the save, on a clean launch.

### Verified clean at the moment it worked

| Check | Result |
|---|---|
| GSC payload injected? | 🪦 **no** — payload went to pid 35804; the working process was **pid 32744**, a different launch. ACTS injection is memory-only and cannot survive process exit |
| Any injection since relaunch? | **none run** |
| cwpatch DLL loaded? | 🪦 **no** — `discord_game_sdk.dll` was the **stock 3,891,512-byte Microsoft SDK** at the time |

▶ **So the game was entirely vanilla.** The only carrier was the saved custom game.

### Why this is unforgeable, and why the timer test was not

`maxplayers` has **no rules-menu row at all** ([[lobby-settings]] L1 walked every page). There is no
menu path to any value, so a save holding 8 cannot have been produced by hand. Contrast P3's timer
save, which klaze correctly voided: 60 **is** a published option, so that save proved only that saving
works. ⚠ **`uint:7` (max 127)** — 8 is nowhere near the field ceiling that made the timer ambiguous.

### What it changes

▶ **Injection is now OPTIONAL for team size.** Host 4v4 from a saved custom game on a stock client.
The whole ACTS pipeline becomes a *configuration step performed once*, not a per-session dependency.
▶ **And it means the save serialises the same store the frontend write reaches** — which
`mp_custom_game.ddl` predicted (its `gametypesettings` member is the match-time blob byte for byte,
`uint:7 maxplayers` at the same offset in both DDLs) and which is now measured rather than inferred.
▶ 🪦 **0.1 is superseded in effect.** An *in-match* write still does not flow back to the lobby copy —
that measurement stands. It simply does not matter, because the pregame write never needed to.

### Still open

⚠ **Bots, not humans.** The team screen accepted 4 a side and the save restored that. A human 4th
joining a saved-config lobby is untested.
⚠ **Untested: how far it goes.** 8 worked. `uint:7` allows up to 127 and `com_maxclients` is derived at
match start (P1) — so 10 and 12 are now worth trying *through the save*, which is a different question
from L8's failed in-match attempt.
⚠ **Untested: durability.** Whether the value survives a Battle.net patch, a settings reset, or being
re-saved from a stock client.

### Persistence and propagation — first observations (klaze, 2026-09-10)

*"i joined from another account and backed out and it was still 4v4 on that account too, until i saved
it and reset then loaded the save it was 2v2. but it survived 2 game restarts for the account on this
pc."*

| Observation | Reading |
|---|---|
| ✅ Survived **2 game restarts** on the host account | the save is durable, not a one-shot |
| A **joining account** saw 4v4, and still did after backing out | the joiner receives the host's live session config, as expected for host-authoritative P2P |
| That account **saved, reset, loaded its own save → 2v2** | 🔓 **the joiner's save did NOT capture it** |

▶ **So the modded value rides the live session but does not serialise into a joiner's own save.** The
save appears to write from the account's *own* pending-lobby store, which only the pregame write
touches — and that write only happened on the host.

▶ **Workflow consequence:** one injected setup per account that wants to **host** a modded save.
Joiners need nothing — they inherit it from the host, which is the right shape for this project
(`tac-risk-model.md`: joiners are expected to be unexposed).

⚠ Casual observation, not a controlled test — the exact sequence on the second account was not
recorded step by step. Worth a proper run before relying on it.

## 🪦 B2 — `switchmap_load()` FROM THE FRONTEND **CRASHES THE GAME**

2026-09-10. `test_lobbymap_live`: injected at the main menu, one match, back to the lobby, sit ~20s,
then `switchmap_load( "mp_zoo_rm", "gunfight" )` → `waittilltimeout( 25, #"switchmap_preload_finished" )`
→ `switchmap_switch()`.

▶ **The game crashed.** Minidump written by the engine's own handler:
`%LOCALAPPDATA%\Activision\Call Of Duty Black Ops Cold War\crash_reports\BlackOpsColdWar.20260910-074102.zip`,
`mini_dumper.log` `[2026.09.10-07h40m23s] Beginning`. Process gone; desktop showed the Battle.net
launcher.

⚠ **What is proven and what is not.** Proven: this payload, in the frontend, ends in a hard crash.
**Not** proven: that `switchmap_load` itself is the faulting call. The probes stash to dvars and are
printed by the *in-match* half on the next match — and there was no next match, so **probes 70–73 were
never read**. The crash could equally be the frontend VM lacking session state the call assumes.
**Do not record this as "switchmap_load is unsafe"** — record it as "this sequence, from this VM,
crashed."

▶ **The route is not dead, it is mis-aimed.** Every stock caller of `switchmap_load` runs **in-match**,
not in the frontend: `cp_common/load.gsc:412`, `zm_utility_zsurvival.gsc:153`,
`callbacks_shared.gsc:2227` (`switchmap_preload`). Calling it where stock never does was the
speculative part of B2, and it is the part that failed.

▶ **Next: B1 (`src/test_sessionswitch/`), which is the stock-shaped version and is already written.**
Same builtin, same two-argument form, but **in-match at `bb.gsc`** — exactly where stock uses it. It
ships `read_only = 1`. Its presence criterion is still the right one: platform presence is unwritable
from GSC, so if it moves, the session moved.

⚠ **Nothing was lost.** The injection is memory-only, and the 4v4 saved custom game is account-side and
unaffected — P5 stands.

### ⚠ Method note: a frontend-only test cannot report through the in-match half

B2's probes were stashed to dvars for the next match to print, copying `test_frontend`'s design. That
works when the frontend half *survives* to a next match. **If the frontend action is the thing that can
crash, the reporting path dies with it.** Any future frontend write-test needs its readout to survive
the action — write the probe to a dvar *before* the risky call and read it externally, or accept that
a crash yields no probe data at all.

## 🪦 P3 CLOSED — `adddebugcommand()` IS NULLED. Probe 62 = 4.

2026-09-10, `test_frontend_dbg` (writes off, probe 62 moved to emit FIRST so a 40s round could not
truncate it again). **Read `6200004`.**

`4` is the "neither" branch: `canadddebugcommand()` returned false **and** `set gf_fe_dbg 7` did not
land. So the console is not reachable from GSC in CW retail — the same state ate47 records for BO4
(*"nulled; cbuff"*). CW's row in the table was unannotated, which made it a question rather than a
verdict; it is now a verdict.

### ▶ Where that leaves the lobby MAP: **no route with the tools this project has**

| Route | Status |
|---|---|
| A map **gametype setting** to write | 🪦 none exists — only `allowmapscripting` in the whole dump |
| A **builtin** that sets lobby map / playlist / session | 🪦 none — all 4,481 CW functions matching playlist/lobby/session/matchmaking/presence are **read-only**; the only writer is `enablelobbyjoins` |
| The **per-map enable array** in the save | 🪦 sits *outside* `gametypesettings`, so `setgametypesetting()` cannot reach it. It is LUA's |
| **Offline edit** of the save | 🪦 the save is **CLOUD** — nothing custom-game-shaped appears in `Documents\...\player` after a confirmed save |
| **P3** console from GSC (`adddebugcommand`) | 🪦 **nulled.** This test |
| **P4** console from the DLL slot | ⚠ blocked — D10 (`acts dcfuncscw`) returns zero rows; ACTS's `cmd_function_t` base is stale for this build |
| **`switchmap_load` from the frontend** | 🪦 B2 — **crashed the game** |

▶ **So the glitch stays manual.** klaze's goal — *"set the pregame lobby map to achieve the same result
as the tricky glitch"* — has no reachable mechanism today. That is a measured conclusion from seven
closed routes, not an assumption.

### ⚠ Untried — not ruled out

- **P6, the LUI channel.** `luinotifyevent` (GSC→LUI) and `menu_response` (LUI→GSC) are both live in
  the lobby. Only stock events can be fired or received without LUA, but **nobody has enumerated which
  stock lobby events exist** — and the map picker is LUI, which is exactly the layer that owns this.
  This is the one route that has never been looked at.
- **Unblocking P4** by finding `cmd_function_t` for this build by hand, so `dcfuncscw` produces a
  command list. Real RE work against an exe that is encrypted at rest, so runtime only.
- **B1** (`src/test_sessionswitch/`) — does *not* set the lobby map, but tests whether in-match
  `switchmap_load( map, gametype )` fixes the **stale UI** after a carry. That is Goal B, and it is
  still the achievable half of the map problem: the carry already works, it just lies to the UI.

## ⚠ P6a RESULT — **`800000`. The UI models are in the CLIENT VM, not the server VM.**

2026-09-10, `test_uimodel`, read-only. **Control probe 80 read 0** — not even the three names the dump
proves exist (`room`, `transitionMapIdOverride`, `fullscreenBlackCount`) resolved. Per the legend that
is "the root or the accessor is wrong", so **bitmasks 81/82 were discarded, not interpreted.**

✅ **The control earned its place again.** Without it this would have entered the notes as "no
map-shaped lobby models exist" — a confident, wrong, and very expensive conclusion. Same shape as B5.

### Why it failed, and it was visible in the dump before the run

| | `.csc` (client) | `.gsc` (server) |
|---|---|---|
| files calling `getuimodel` | **31** | 5 |
| `lobby_root` uses | **3** — `frontend.csc`, `character_customization.csc` | 1 — `cp_common/load.gsc`, **campaign** |

▶ **The UI model tree belongs to the CLIENT VM.** Our payload is a **server** script hooked at
`load_shared.gsc`, so it was asking a VM that has no lobby model tree. The single GSC precedent is
campaign, whose VM context is not the MP frontend.

⚠ **I had this evidence before building** — the three `.csc` paths were in the same grep output I used
to find the chain — and read past it because `function_5f72e972` appears in *both* the GSC and CSC
builtin tables. **A builtin existing in a VM does not mean the data it reaches exists there.**

### ▶ The route is not closed — it moved to the client VM

ACTS's compiler **already supports client scripts**: `acts gscc -c --csc`, plus `--crc-client`,
`--name-client`, `--namespace-client`. And `t8-atian-menu/gsc.conf` (the T8 root, not the CW one)
declares `script_client=scripts\core_common\load_shared.csc`, so the injector concept exists upstream.

**What is unknown and must be established before writing a payload:**
1. Does `injectcw` resolve a **`.csc` target** in the scriptparsetree pool at all? Cheap to find out —
   a wrong target fails harmlessly with *"Can't find target script"*. ⚠ But if it DOES resolve, the
   injection happens, so do not test it with a server-compiled payload: that links a GSC script into
   the client VM and the likely outcome is a crash.
2. Which `.csc` is a **safe replace target**. `clientids_shared.gsc` is the proven safe one on the
   server side; its client counterpart is unverified, and `scene_model_shared` is the standing proof
   that "looks empty" is not "safe to lose".
3. Whether a client-side write to `transitionMapIdOverride` is honoured, or whether LUI ignores a model
   change it did not originate.

⚠ **This is a new track, not a variation on the existing one** — different VM, different compile flags,
different replace target, and every safety property of the GSC pipeline has to be re-established. Worth
scoping deliberately rather than continuing tonight.

## 🪦 P6b — client scripts run in the MATCH client VM, not the FRONTEND one

2026-09-10, four runs. Combining them localises the failure precisely:

| Hook | Ran in match? | Ran in lobby? | Evidence |
|---|---|---|---|
| `load_shared.csc` | ✅ | 🪦 | prints appeared in-match only; tick digit **T = 0** |
| `frontend.csc` | 🪦 | 🪦 | no prints anywhere; preinit digit **P = 0** |

▶ **So an injected client payload executes in the match's client VM and not in the
frontend's.** Every model reading tonight — three separate all-zeros results — was a sampler that
never sampled. They were never evidence about the model tree.

⚠ **The likely blocker is the REPLACE target, not the hook.** Our payload lives in
`radiation_debug.csc`'s slot. If that script is not in the frontend VM's linked set, the code has
nowhere to be — and the six 0-byte candidates are safe to destroy *precisely because nothing
references them*, which is the same property that would stop them being loaded. **Empty and linked may
be mutually exclusive here.**

### ✅ What tonight DID establish, and it is not nothing

1. **Client-script injection works at all.** `acts gscc` builds `.cscc` from a `.csc`, `injectcw`
   places it, and the payload runs — first client-side payload in this project.
2. 🔓 **TWO payloads can coexist on different REPLACE targets.** B9's rule is about *sharing* a
   replace, and these did not: client `frontend.csc → radiation_debug.csc` alongside server
   `bb.gsc → clientids_shared.gsc`. The server half printed while the client half was loaded. That
   removes the one-payload-per-launch constraint for genuinely different pairs.
3. **A lobby→match reporting channel exists**: client stashes to dvars, server prints in-match. It is
   built and working (`src/gf_dvar_read/`), waiting only on a client half that actually runs.
4. 🪦 **File I/O (`openfile`/`fprintln`/`closefile`) CRASHES the game** — type=1 dev builtins, fatal
   rather than inert. Do not retry.
5. ⚠ **The chat feed holds ~3 lines and each print costs two.** Probes must pack into ONE line.

### ▶ The next step is analysis, not another blind run

**Determine which `.csc` scripts the FRONTEND VM actually links**, then pick a replace target from that
set. Guessing has now cost four launches. ate47's BO4 capture
(`t8-atian-menu/docs/notes/loaded/link_frontend.txt`) lists ~190 scripts linked in a BO4 frontend —
**same lineage, not the same game**, so it is a candidate list to verify, not an answer.
⚠ A linked script is by definition one something references, so replacing it is not free. The
`scene_model_shared` failure is exactly this hazard.
