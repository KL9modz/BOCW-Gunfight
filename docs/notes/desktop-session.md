# Desktop session sheet — everything open, in the order it should be run

⚠ **This is the runbook, not the reference.** Every item here has a fuller entry in
[`test-queue.md`](test-queue.md) with its decision table; this sheet is what to do when you sit down,
in what order, and why that order. Fill in the Result slots — a filled slot is the finding.

## The constraint that sets the order: **one payload per game LAUNCH**

B9 measured that injecting a second payload over a live one breaks the link outright. And every
payload's config is compiled in, so **changing a switch means recompile → reinject → relaunch the
game.** A launch is the unit of cost here, not a match: within one launch you can play as many
matches as you like (F7, or the menu's Restart).

So the sheet is ordered by what a step costs:

| Stage | Cost | Contains |
|---|---|---|
| **0** | nothing — answer from memory | 6 questions, and one of them may close route P5 outright |
| **1** | Windows, no game | the compile gate for two payloads |
| **2** | game, **no injection** | the lobby walk, saved games, L0 |
| **3** | 1 launch | the menu — `gunfight_menu`, walk + every control |
| **4** | 1 launch | the pregame probe, read-only (+ the console test, free) |
| **5** | 1 launch each | the pregame writes, one switch at a time |
| **6** | 1 launch each | the leftovers: B1, A4, B9 |
| **7** | people | a human 4v4 — the largest gap between CLOSED and DONE |

⚠ **Stage 2 can invalidate stages 4–6, and stage 4 can invalidate stage 5.** Do not skip ahead to the
interesting one; the cheap steps are ordered first *because* they can delete the expensive ones.

---

## Stage 0 — questions you can answer without launching anything

These are free and two of them redirect real work.

| # | Question | Why it matters | Answer |
|---|---|---|---|
| 0.1 | **After a `gunfight_mod` match, back in the lobby, does the rules-menu timer row read 60 or 40?** | The mod writes `timelimit = 60` in every match. **60** = the in-match write flows back into the lobby's copy, so *Save Custom Game* captures modded settings **today, with no new code** — and P5 becomes the whole answer to pregame control. **40** = the match's copy is discarded on return, and P5 needs P2 first | `______` |
| 0.2 | **Is "save an online playlist's mode into Custom Games" a real menu option?** | If it is, the game ships the designed version of what the glitch does by accident. Worth knowing whether it copies rules only, or the map list too | `______` |
| 0.3 | **Save dialog: how many characters for name and description, and how many save slots?** | The dump predicts **64** and **128**. Matching caps confirm `mp_custom_game.ddl` is your build's format, for free | `______` |
| 0.4 | **In a 3v3 Gunfight lobby, can you add bots before starting — and does it refuse the 4th on a side?** | This is P2's best readout. If the lobby has no bot control outside Nuketown, P2 is judged only by probe 60 and the rules row | `______` |
| 0.5 | **Has a rules-menu value ever carried between lobbies on its own?** | Cheap evidence on whether presets are cloud-authoritative | `______` |
| 0.6 | **After the glitch, is everything right?** Spawns, the map list afterwards, map voting, the AAR | The open ❓ from [`roadmap.md`](roadmap.md). It decides whether B1 is chasing a complete target or a partial one | `______` |

---

## Stage 1 — compile gate. Windows, no game running, zero exposure

Two payloads have **never been compiled**. Neither has ever run.

```powershell
python3 tools\check-args.py src\gunfight_menu\scripts\gunfight_menu.gsc
.\tools\check-gsc.ps1 .\src\gunfight_menu\scripts\gunfight_menu.gsc
acts gscc src\gunfight_menu\scripts\gunfight_menu.gsc -g cw -p pc -o $env:GF_PAYLOADS\gunfight_menu

python3 tools\check-args.py src\test_frontend\scripts\test_frontend.gsc
.\tools\check-gsc.ps1 .\src\test_frontend\scripts\test_frontend.gsc
acts gscc src\test_frontend\scripts\test_frontend.gsc -g cw -p pc -o $env:GF_PAYLOADS\test_frontend
```

⚠ **`gunfight_menu` is 963 lines and its menu engine is a REWRITE of the Atian Menu's, not a copy.**
The original is `#include` / bare-`autoexec` / `#ifdef` under `debugcompiler` — the dialect that
crashed at script link under ACTS. A failure here is a translation bug, and the line number is the
finding, not a mystery.

M1 result: `______` · test_frontend result: `______`

---

## Stage 2 — the game, with NO injection at all

Nothing here writes memory, nothing here is exposure beyond playing the game.

### 2.1 · P5 — saved custom games ← **the highest-value free test in the project**

The dump says a saved custom game **is the match-time settings blob**, byte for byte
(`mp_custom_game.ddl`'s `gametypesettings` member is identical to `mp_gametype_settings.ddl`'s root
member — 0x65b30 bits, 993 members, same struct). `maxplayers` sits in it as **`uint:7`**, so 8, 10
and 12 all fit. If a modded value can get into a save, **it loads from the account with no injection
at all**, before anyone is seated. [`pregame-routes.md`](pregame-routes.md) P5.

1. **If 0.1 said 60:** save the custom game right after a `gunfight_mod` match. Start a *fresh*
   lobby. Load the save. Walk the rules menu — does the timer still read 60?
   Result: `______`
2. **Save any custom game, then sort `%USERPROFILE%\Documents\Call Of Duty Black Ops Cold War\player`
   by modified time.** A new or changed file = **local**, and the DDL above is its schema. Nothing =
   **cloud**, as expected. Result: `______`
3. Note the name/description caps and slot count while the dialog is open (that is 0.3).

⚠ **What a save cannot carry: the current map.** There is no map field in the root — only a 43-entry
per-map *enable* array, and that array sits **outside** `gametypesettings`, so `setgametypesetting()`
cannot reach it even in principle. A save can hold "Gunfight, maxplayers 8, these maps enabled". It
can never hold "Gunfight on Hijacked".

### 2.2 · L0 — Allow In-Game Team Change, the spectator version

Never tested, because the toggle has never been turned on. Rules menu → **Allow In-Game Team Change**
→ on. Fill 3v3, start, have a 7th player join (they get forced to spectate), then **that spectator
opens the pause menu and picks a team**. `menuteam()` has no cap check in script.

⚠ Casters are dead for this — no pause menu. A plain spectator is an ordinary player.
Full decision table: [`test-queue.md`](test-queue.md) L0. Result: `______`

---

## Stage 3 — one launch: `gunfight_menu`

```bash
bash tools/inject.sh gunfight_menu     # after loading a private match once
```

⚠ Prerequisite: the process must have loaded MP scripts once, or the hook is not in the pool yet.

**M2 — read-only walk. Select nothing that writes.** RMB+V opens; RMB up / LMB down / R select /
V back. Walk every page: Teams · Players · Round · Loadout · Spy plane · Map · All maps. If the menu
draws and navigates, the engine translation is right and every later result is about the controls.
⚠ If only one item shows per page, or lines overwrite, set `gf_menu_lines`. Result: `______`

**M3 — controls, cheapest and most-proven first.** All in the same launch.

| # | Control | Proven? | Expect | Result |
|---|---|---|---|---|
| 1 | Round → Timer 60s | ✅ shipped | clock changes within a second | `______` |
| 2 | Teams → 4v4 → Fill with bots | ✅ L6 + C7 | 4 a side, **survives the round boundary** | `______` |
| 3 | Round → Restart match | ✅ B4 | restarts, **and the menu still opens after** | `______` |
| 4 | Teams → Remove all bots | — | bots gone | `______` |
| 5 | Loadout → Snipers (B6) | ⚠ | **next** round is snipers-only. Needs two matches: the latch is `game.`-scoped | `______` |
| 6 | Spy plane → Shared (B7) | ⚠ | next round; value 3 is the one the menu hides | `______` |
| 7 | Players → someone → To Axis (C11) | ⚠ | they switch sides and spawn normally | `______` |
| 8 | Map → Zoo, method **carry** | ✅ | loads exactly like the Atian menu did | `______` |
| 9 | Map → method **session** → Zoo (B1) | ⚠ | **the criterion is presence** — see below | `______` |

⚠ **Test a lobby return after 3, 8 and 9.** That is the check that caught `scene_model_shared`.

**On #9, what to look at, in this order:** scoreboard → pause menu → AAR → **a friend's view of your
activity**. Presence is the binary one: no GSC builtin writes it, so if the friend list says Zoo, the
engine's session record moved and **Goal B closes**. In-match UI new + presence old is its own result
and worth recording exactly.

---

## Stage 4 — one launch: `test_frontend`, read-only

**The first payload ever hooked at `load_shared.gsc`**, which links in *every* VM. `inject.sh` picks
that hook itself for this project.

```bash
bash tools/inject.sh test_frontend     # ⚠ at the MAIN MENU - no match needed first
```

⚠ That "no match needed" is **predicted from a BO4 capture, not measured in CW**. If it says
`Can't find target script`, that is a finding — record it and load a match first.

**The walk:** inject → play or restart one match (links the MP half; it prints `50 = 99999`, which is
correct, nothing is stashed yet) → **leave to the lobby** (links the frontend half) → Custom Games →
set up the usual 3v3 Gunfight lobby → wait ~30s → walk the rules menu, set the timer to 60 → **start
the match** and read the probes.

⚠ Start `pwsh tools/capture-probes.ps1 -Seconds 240 -Every 3` **before** the match starts.

| Probe | Reading | Means | Result |
|---|---|---|---|
| **50** | `0` / `99999` | **the frontend half never ran.** Everything below is void — check for a lobby hang first | `______` |
| 50 | rising | it runs, and keeps running while you navigate | |
| 51 | bitmask | 2 = private · 16 = a player entity exists in the lobby · 32 = it answers `ishost()`. Bits 16/32 are the input half of a future lobby menu | `______` |
| **52** | `6` in 3v3 / `4` normal | 🔓 **the frontend store IS the pending lobby config** — same numbers L6/L7 read in-match. Stage 5 is live | `______` |
| **52** | `99999` while 50 rises | the read threw or returned nothing. **Stage 5 is moot in GSC** — skip it and go to P5/P3 | |
| 53 | `60` | the store follows the rules menu **live**. `40` = it holds the default and the menu writes elsewhere | `______` |
| 54 | `0` | control — L5 read 0 in-match | `______` |
| 55 / 56 / 58 | numbers | lobby client count, connected players, `com_maxclients` **as the lobby sees it**. A free reading on when the budget is fixed | `______` |
| 57 | int | `getlobbyuiscreen()` per screen. `88888` = defined but not an int | `______` |
| **62** | `2` or `3` | 🔓🔓 **`adddebugcommand()` is alive — the console is reachable from GSC.** `gametype_setting`, `map`, `lobbylaunchgame` each become one script line, in the lobby too, and the whole DLL route becomes unnecessary. `4` = nulled like BO4 | `______` |

⚠ **Lobby return.** This payload links in the frontend, which is exactly where `scene_model_shared`
hung the game.

---

## Stage 5 — one launch per switch: the pregame writes

**Only if probe 52 came back with a number.** Edit `default_config()`, recompile, reinject, relaunch.

**5.1 — `write_maxplayers = 1`** (value 8). Same walk as stage 4. Three readouts, and only one is a
probe:

1. **the lobby itself:** can a 4th bot or player go on one side? Today a 3v3 lobby refuses.
   Lifted → 🔓 **the lobby cap follows `maxplayers`, and a human 4v4 is seated by the stock join
   path, with nothing to undo at the round boundary.** Result: `______`
2. **probe 59:** `2` = written and read back · `3` = rejected or clamped (note what 52 says)
   Result: `______`
3. **probe 60**, read in-match before anything writes: `8` = **it carried into the match**. `6` = the
   launch rebuilt the store from the DDL; the write reached the lobby VM but not the launch.
   Result: `______`

**5.2 — `write_timelimit = 1`** (value 60), separately. The **rules-menu row** is the readout: if it
shows 60 without being touched, the write reached what the UI reads. Result: `______`

⚠ Both switches write on **every 10s sample**, on purpose — the store may be rebuilt when the mode is
picked or the lobby created, and a single early write would just be overwritten. That repetition is
itself untested. Lobby return after each.

▶ **If 5.1 lands, go straight back to P5** and try to *save* the modded lobby. That is the
combination that ends with no injection in the hosting workflow at all.

---

## Stage 6 — the leftovers, one launch each

| Test | What it is | Why it is still open | Result |
|---|---|---|---|
| **B1** | `switchmap_load( map, gametype )` via `src/test_sessionswitch/`, `read_only = 1` first | Goal B. ⚠ **Covered by M3 #9** if the menu works — run the standalone only if the menu's map page fails. Probe 40 must not be 99999 | `______` |
| **A4** | the script-driven carry, with the `endon` fix | Diagnosed and never re-run. If it works, the map workflow drops the Atian Menu entirely | `______` |
| **B9** | inject under a live payload, guard dvar cleared | Its conclusion — that unattended operation is closed off — rests on **four sampled frames**. One clean run is worth it | `______` |

---

## Stage 7 — people, not code

**A human 4v4.** The team-size goal is verified **with bots**. `maxplayers` is a gametype setting the
session's own team-size restore reads, so it should transfer — but this project has walked back four
claims that felt safer than this one. No new code; it needs bodies.

**And watch the spawns.** With `maxplayers` at 8 a 4v4 no longer *exceeds* the configured team size,
so the out-of-bounds precondition should be gone. Bot run 2 played clean — bots tolerate a spawn a
person would swear at. `src/test_spawnmode/` mode 2 stays built as the fallback.

Result: `______`

---

## What each stage would change

| If this comes back | Then |
|---|---|
| 0.1 = **60** | P5 is the pregame answer, and it needs **no code at all**. Stages 4–5 become confirmation rather than the plan |
| stage 2.2 (L0) = spectator joins a full team | **4v4 with zero code**, by a different door than `maxplayers` |
| probe 62 = **2 or 3** | the console is scriptable. The DLL route, D10, and `crack-cmds.py` all become unnecessary |
| probe 52 = a number, then 5.1 lifts the 4th seat | **pregame control, the project's #1 priority, closed** |
| M3 #9 flips presence | **Goal B closed** — the map carry stops being a hack |
| probe 50 = 0 | GSC does not run in the CW frontend after all. Retract [`pregame-routes.md`](pregame-routes.md) in its own words and fall back to P3/P4 |
