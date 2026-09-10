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
