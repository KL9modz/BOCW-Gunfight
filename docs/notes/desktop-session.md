# Desktop session sheet — everything open, in the order it should be run

⚠ **This is the runbook, not the reference.** Every item here has a fuller entry in
[`test-queue.md`](test-queue.md) with its decision table; this sheet is what to do when you sit down,
in what order, and why that order. Fill in the Result slots — a filled slot is the finding.

🛑 **Stages 4–6 are STALE.** They were written before the 2026-09-10/11 desktop sessions, which ran
P1–P11 and closed most of what they describe: P1/P2/P3 confirmed, `adddebugcommand` nulled, the carry
measured to crash joiners, in-match `switchmap_load` inert, Cheat Engine blocked by TAC.
[`RESEARCH-INDEX.md`](RESEARCH-INDEX.md) is authoritative. **2.3 below is the one live map route** and
is the first thing worth doing.

## The constraint that sets the order: **one payload per game LAUNCH**

B9 measured that injecting a second payload over a live one breaks the link outright. And every
payload's config is compiled in, so **changing a switch means recompile → reinject → relaunch the
game.** A launch is the unit of cost here, not a match: within one launch you can play as many
matches as you like (F7, or the menu's Restart).

🔓 **P5 loosened that constraint and the order now reflects it.** A saved custom game carries the
modded settings with **nothing injected**, so the work that used to cost a launch each is now mostly
free — which is why stage 3 is the save and the menu moved to 4.

So the sheet is ordered by what a step costs:

| Stage | Cost | Contains |
|---|---|---|
| **0** | nothing — answer from memory | 6 questions, **3 already answered** — read those before planning |
| **1** | Windows, no game | the compile gate |
| **2** | game, **no injection** | L0, and **the one live map route (2.3)** |
| **3** | **mostly none** | the save-based hosting workflow — P5's follow-through. Injection is now a one-time config step, not a match-night dependency |
| **4** | 1 launch | the menu — `gunfight_menu`. It compiles, injects and draws; the Match page and the spawn_guard fix are what is untested |
| **5** | 1 launch each | what is left: C10, B9, standalone spawn_guard |
| **6** | 🪦 nothing | measured closed. Listed so it is not redone |
| **7** | people | a human 4v4 — the largest gap between CLOSED and DONE |

⚠ **Stage 3 is cheap and it is the most valuable thing here**, which is why it comes before the menu.
Most of it needs no injector at all, because the save already carries the mod — so if the evening ends
early, it is the stage that leaves you with something shippable.
⚠ **Stage 3's save and stage 4's menu are two different workflows**, not two steps of one. The save is
configuration that survives a relaunch with nothing running; the menu is live in-match control that
does not survive anything.

---

## Stage 0 — questions you can answer without launching anything

These are free. **0.1–0.3 are answered**; 0.4–0.6 are still open.

| # | Question | Why it matters | Answer |
|---|---|---|---|
| 0.1 | **After a `gunfight_mod` match, back in the lobby, does the rules-menu timer row read 60 or 40?** | The mod writes `timelimit = 60` in every match. **60** = the in-match write flows back into the lobby's copy, so *Save Custom Game* captures modded settings **today, with no new code** — and P5 becomes the whole answer to pregame control. **40** = the match's copy is discarded on return, and P5 needs P2 first | 🪦 **40 — REVERTED.** Measured 2026-09-09 with gunfight_mod live (60s rounds confirmed in-match). The match-time write is DISCARDED on return to the lobby, so a save cannot capture modded settings today. **P5 needed P2 first** — and 🔓 **P2 then worked and P5 CLOSED**: the *pregame* write serialises into a save even though the in-match one does not, which is why this row's verdict stopped mattering. Stage 3. ⚠ Also checked: still NO Max Players row, even though the mod writes `maxplayers` every round — so that write does not surface a row either |
| 0.2 | **Is "save an online playlist's mode into Custom Games" a real menu option?** | If it is, the game ships the designed version of what the glitch does by accident. Worth knowing whether it copies rules only, or the map list too | 🪦 **NO** — klaze walked it 2026-09-09: you can only edit game settings for the modes already selectable in private match. No import path from online playlists exists |
| 0.3 | **Save dialog: how many characters for name and description, and how many save slots?** | The dump predicts **64** and **128**. Matching caps confirm `mp_custom_game.ddl` is your build's format, for free | ✅ **20 SLOTS.** Caps not measured exactly — klaze: *"seems large"*, consistent with the predicted 64/128. ⚠ The slot count is NOT in the DDL: that file holds **69 schema versions**, not 69 slots, so slots are a UI/engine constant. Root confirms `string(64) gamename` + `string(128) gamedescription` |
| 0.4 | **In a 3v3 Gunfight lobby, can you add bots before starting — and does it refuse the 4th on a side?** | This is P2's best readout. If the lobby has no bot control outside Nuketown, P2 is judged only by probe 60 and the rules row | `______` |
| 0.5 | **Has a rules-menu value ever carried between lobbies on its own?** | Cheap evidence on whether presets are cloud-authoritative | `______` |
| 0.6 | **After the glitch, is everything right?** Spawns, the map list afterwards, map voting, the AAR | The open ❓ from [`roadmap.md`](roadmap.md). It decides whether B1 is chasing a complete target or a partial one | `______` |

---

## Stage 1 — compile gate. Windows, no game running, zero exposure

**`gunfight_menu` has never been compiled and has never run.** `test_frontend` has — it is what
closed P1, P2, P3 and P5, so it is off this list.

```powershell
python3 tools\check-args.py src\gunfight_menu\scripts\gunfight_menu.gsc
.\tools\check-gsc.ps1 .\src\gunfight_menu\scripts\gunfight_menu.gsc
acts gscc src\gunfight_menu\scripts\gunfight_menu.gsc -g cw -p pc -o $env:GF_PAYLOADS\gunfight_menu
```

⚠ It grew a **Spawns** page and a **Match** page in `3e11a6c` that no compiler has seen. The static
check in that commit counted braces and resolved every `&`-reference by hand; that is not a compile.

⚠ **`gunfight_menu` is 963 lines and its menu engine is a REWRITE of the Atian Menu's, not a copy.**
The original is `#include` / bare-`autoexec` / `#ifdef` under `debugcompiler` — the dialect that
crashed at script link under ACTS. A failure here is a translation bug, and the line number is the
finding, not a mystery.

M1 result: `______`

---

## Stage 2 — the game, with NO injection at all

Nothing here writes memory, nothing here is exposure beyond playing the game.

### 2.1 · 🪦 P5 is CLOSED — its follow-through is stage 3

A saved custom game **carries `maxplayers = 8` through a quit, a relaunch and zero injection**
(2026-09-10, verified clean). This subsection used to be the open test; it is now a result, and
everything it would have led to is **stage 3**.

▶ The one thing to do here: **load the existing 4v4 save on a clean launch and confirm it still
works** before building anything on top of it. Thirty seconds, and it is the precondition for all of
stage 3. Result: `______`

### 2.2 · L0 — Allow In-Game Team Change, the spectator version

Never tested, because the toggle has never been turned on. Rules menu → **Allow In-Game Team Change**
→ on. Fill 3v3, start, have a 7th player join (they get forced to spectate), then **that spectator
opens the pause menu and picks a team**. `menuteam()` has no cap check in script.

⚠ Casters are dead for this — no pause menu. A plain spectator is an ordinary player.
Full decision table: [`test-queue.md`](test-queue.md) L0. Result: `______`

### 2.3 · `LobbySetMap` / `LobbySetGameType` ← **the one live map route.** No injection, no glitch

Every closed route tried to make the picker *allow* Gunfight-on-Miami. This one skips the picker and
calls the two engine functions the picker calls. Full reasoning and both failure modes:
[`lobby-setters.md`](lobby-setters.md).

✅ **Exposure ruled acceptable — klaze, 2026-09-12.** `gfscan` (OpenProcess + read/write) and
`injectcw` (allocate + repoint) have both been tolerated all session; this adds `CreateRemoteThread`,
one API beyond either. Not evasion. ⚠ Accepting it does not make it known: if the game dies the moment
the thread runs, that is the finding, and it costs a relaunch.

▶ **Before 2.3a, get the strings right.** ACTS's own gametype list is Black Ops 4's and **does not
contain `gunfight`**. The tool carries the dump's lists instead:
`python tools\lobby-set.py --list-maps` (43; the screen shows 36) and `--list-gametypes` (27).

**2.3a — scan only. Writes nothing.** Game running, sitting in the custom games lobby:

```
python tools\lobby-set.py
```

| Reading | Means | Result |
|---|---|---|
| both resolve, **one target each** | ate47's signatures still match this build | `______` |
| the two are **≤0x1000 apart** | 🔓 the BO4 relationship holds — there they are `0x10` apart, adjacent in one table. Strong confirmation these are the right pair | `______` |
| `targets NONE` | the pattern is stale for this build. The route needs new signatures; nothing else about it changes | `______` |
| >1 target for one pattern | too loose here. Record every address printed before considering `--force` | `______` |

**2.3b — set the pair.** Only after a clean 2.3a. In the custom games lobby:

```
python tools\lobby-set.py --gametype gunfight --map mp_miami
```

1. Lobby rows read **Gunfight** and **Miami**? `______`
2. ⚠ **Leave the screen and come back.** Does it hold? `______`
   This is the decisive one. Holding = the C lobby owns the selection. Reverting = the Lua master
   re-pushes, and the route joins the closure table **with a measurement instead of a theory**.
3. Start. Loading screen, then in-match — real Gunfight on Miami? `______`
4. Scoreboard, pause menu, **and the friend list / activity** — do they name Miami? `______`
5. 👤 **THE CRITERION — a friend on a vanilla install joins and plays.** The carry fails exactly here,
   by crashing connected clients. ✅ A tester is available (klaze, 2026-09-12), so do not stop at
   "it looks right on my screen" — that is the state the carry reaches too. `______`
6. Lobby return clean? `______`
7. If the order looks wrong, try `--map` before `--gametype`. `______`

⚠ A crash means the scan found the wrong function. Nothing persists — relaunch, and keep the addresses
2.3a printed so the signature gets fixed rather than re-guessed.

**2.3c — free, 30 seconds, unrelated to the above.** `acts dpcw x 113` prints the MAPTABLEENTRY pool
header. **Item size ~0x1A0** = BO4-shaped, no per-map `gamemodes` string; **~0xa8** = BO6-shaped, the
field exists. ⚠ Demoted deliberately — the compat set is *proven* to be the online-fed LUI model, so
even a `gamemodes` string is likely one input to it, not the master. Result: `______`

---

## Stage 3 — the save-based hosting workflow ← **the highest-value open work**

🔓 **P5 closed on 2026-09-10 and changed what this project is.** A saved custom game carried
`maxplayers = 8` through a **quit, a relaunch and zero injection** — verified clean (the payload went
to a dead pid, no cwpatch, stock `discord_game_sdk.dll`). `maxplayers` has **no rules-menu row at
all**, so a save holding 8 cannot have been made by hand. It survived two game restarts.

▶ **So injection is a configuration step performed once, not a match-night dependency.** Everything
below is the follow-through nobody has run.

⚠ **Order within this stage: 3.1, 3.4 and 3.5 need NO injection at all** — load the save you already
have and observe. Do those before you open a terminal. **3.2 and 3.3 each need one injected launch**
to *author* a new save, so they belong with stage 4's launch budget, not before it.

### 3.1 · Does a HUMAN join a save-configured lobby and play? 👤

P5 was verified with **bots**. The team screen accepted 4 a side and the save restored it; a human
fourth has never joined a save-configured lobby.

Load the 4v4 save on a clean launch, inject nothing, have your friend join, fill to 4v4 with people
and bots, play a full match.

| Check | Result |
|---|---|
| the 4th seat accepts a human | `______` |
| the round boundary keeps 4v4 | `______` |
| spawns are in bounds for everyone (⚠ this is `#spawn_guard`'s whole reason) | `______` |
| the friend's client is stable end to end — **no crash** | `______` |

▶ If this passes, **the team-size goal is DONE**, not merely closed: real players, no injection, on a
stock client. That is the sentence the project has been unable to write since 2026-09-08.

### 3.2 · How far does the save go? 5v5, 6v6

L8 killed the *in-match* route to a bigger budget: `maxplayers = 10` landed and `com_maxclients`
stayed at 8. **The save is a different question** — P1 measured that `com_maxclients` is derived at
match start from the store the save serialises, so a save authored at 10 has never been tried.
`uint:7` allows 127; the field is nowhere near its ceiling.

✅ **The field width is already checked, and it is why this is worth trying.** `maxplayers` is
`uint:7`, so 10 and 12 are structurally representable — unlike `timelimit`, which is `fixed<8,2>` and
saturates at 63.75s. ▶ **Check the DDL before authoring any large value**; a narrow field saturates
silently rather than refusing.

One injected launch per value. Author the save with `write_maxplayers = 1` at **10**, then relaunch
clean and load it.

| Value | Seats it actually gives | `com_maxclients` in-match | Result |
|---|---|---|---|
| 10 | `______` | `______` | `______` |
| 12 | `______` | `______` | `______` |

⚠ **Raise one step at a time.** If 10 works, 12 is a separate launch — not a bolder guess.

### 3.3 · What ELSE fits in one save?

`mp_custom_game.ddl`'s `gametypesettings` member is the match-time blob **byte for byte** — 0x65b30
bits, 993 members. In principle *every* gametype setting is serialisable, which would make one save
the entire mod.

Author one save with several pregame writes on at once and check each in the loaded lobby:

| Setting | Why it is worth carrying | Carried? |
|---|---|---|
| `maxplayers` = 8 | ✅ already proven | ✅ |
| `timelimit` = **45** or **55** | ⚠ P3's timer save was **correctly voided** — 60 is published, so it proved only that saving works. ⚠⚠ And **do NOT author 90**: the field is `fixed<8,2>`, ceiling **63.75s**, so 90 saturates and proves nothing. 45 and 55 are not on the published list (0/20/30/40/50/60) *and* sit under the ceiling — unforgeable the way 8 was | `______` |
| `gunfightloadoutindex` = 1 / 3 | snipers-only or melee-only Gunfight, no menu row (B6). ⚠ latched behind `game.var_96a8ff4a`, so it must land before `onstartgametype` | `______` |
| `gunfightspyplane` = 3 | the value the menu row hides (B7) | `______` |

▶ **Every setting that carries is one the hosting workflow stops needing an injector for.**

### 3.4 · Durability — the thing that decides whether this is a workflow or a stunt

| Question | Result |
|---|---|
| survives a **Battle.net patch**? | `______` |
| survives a **settings reset** / "restore defaults"? | `______` |
| does **re-saving from a stock client** preserve the modded value, or normalise it? | `______` |
| where does the file live — did anything under `%USERPROFILE%\Documents\Call Of Duty Black Ops Cold War\player` change, or is it cloud? | `______` |

⚠ The re-save question is the sharp one. If opening and re-saving normalises `maxplayers` back to a
menu-legal value, every incidental edit is a landmine and the save must be treated as read-only.

### 3.5 · Re-run the joiner-save observation properly

klaze, 2026-09-10, casual: a joining account saw 4v4, still saw it after backing out, but **its own
save came back 2v2**. Reading: the modded value rides the live session and does **not** serialise into
a joiner's save — one injected setup per account that wants to *host*, joiners need nothing.

That was an observation, not a controlled run, and it carries the whole "joiners need no toolchain"
claim. Redo it with the steps written down: join → back out → save → relaunch → load. Result:
`______`

---

## Stage 4 — one launch: `gunfight_menu`

```bash
bash tools/inject.sh gunfight_menu     # after loading a private match once
```

⚠ Prerequisite: the process must have loaded MP scripts once, or the hook is not in the pool yet.

**M2 — read-only walk. Select nothing that writes.** RMB+V opens; RMB up / LMB down / R select /
V back. Walk every page: Teams · Players · Round · Loadout · Spy plane · **Spawns** · **Match** ·
Map · All maps. ✅ **The menu compiles, injects and draws** — `80e2d9f` reports klaze toggling the
Spawns page in-game, so M1 and the walk are effectively passed and every later result is about the
controls. ⚠ **Match is still never-drawn**, and the Spawns page has a **new, untested fix** (below).
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
| 8 | Spawns → guard ON + diag ON, on a map that **failed before** | ⚠ **fix untested** | see 4.1 below — read the diag probe first, not the spawns | `______` |
| 9 | Match → round/win limit | ⚠ **never drawn** | the round counter obeys it. `-1` sentinels mean only an explicit pick asserts control | `______` |
| 10 | Map → Zoo, method **carry** | ✅ host-side | loads exactly like the Atian menu did. ⚠ **SOLO ONLY** — see below | `______` |

🪦 **Do NOT run the old #9, `Map → method session`.** `switchmap_load` was measured **inert in MP**
(2026-09-11, two iterations, no crash and no map change). The SESSION option is still in the menu and
**does nothing** — its removal was blocked by a safety classifier during the last build, so treat it
as a known dead row rather than a test. `pregame-routes.md` → *SWITCHMAP AVENUE CLOSED*.

⚠⚠ **#10 is solo-only now.** The carry is **measured to crash connected clients** (2026-09-10). It is
still the working host-side any-map path and it is still worth exercising — but **not with your friend
in the lobby.** Save their time for 2.3b, 4.1 and stage 6.

⚠ **Test a lobby return after 3, 8 and 10.** That is the check that caught `scene_model_shared`.

### 4.1 · spawn_guard — read the diagnostic before you judge the spawns

klaze tested it and it did **nothing** on the maps that "don't use tdm spawns". That was not the fix
failing — it was `mod_gather_spawns` looking only for the DM/TDM targetnames, gathering fewer than two
points, and **failing safe**. `80e2d9f` expands the list to the generic `mp_spawn_point` family (the
most-referenced spawn targetnames in the dump, and what `mp_cartel` / `mp_slums_rm` / `mp_village_rm` /
`mp_miami_strike` actually place) plus the `mp_twar_spawn` Combined Arms layout.

▶ **So the readout is the diag, not your eyes.** Turn `cfg_spawn_diag` on with the guard:

| Probe | Means | Result |
|---|---|---|
| **60xxxxx** | **armed**, with N points gathered. On the maps that failed before, N must now be **> 0** | `______` |
| **61xxxxx** | **still inert** — it gathered fewer than 2 and no-op'd again. The targetname list is still missing this map's family, and the map name is the finding | `______` |

⚠ **Armed is not fixed.** A 60 with a good N says the mechanism now sees spawn points; whether players
land in bounds is the separate question, and it needs 4v4 on a map that previously threw people out.
Record both. Result: `______`

---

## Stage 5 — the leftovers, one launch each

| Test | What it is | Why it is still open | Result |
|---|---|---|---|
| **C10** 👤 | late joiners land on a **team**, not spectator — `src/test_latejoin/` | A chain of nine ANDs with **no cap check** once `level.forceautoassign` or `level.var_a3e209ba` is broken. Needed a joiner, and one is now available. This is the route that does not care what the lobby was configured for | `______` |
| **B9** | inject under a live payload, guard dvar cleared | Its conclusion — that unattended operation is closed off — rests on **four sampled frames** across one round. It is the finding that decides whether an agent can ever put fresh code in the game without klaze present, and it deserves better than four frames | `______` |
| **spawn_guard in `gunfight_mod`** | the no-menu build's copy of the same guard | ✅ **The targetname fix is now ported** — same 12 names, same order as the menu's, verified list-for-list. So the no-menu build is a real fallback again rather than a guaranteed no-op. ⚠ Still **never run**: read probe **60** (armed, N gathered) before judging the spawns, exactly as in 4.1 | `______` |
| **H1 vs H2** ⚠ | write `timelimit = 30` from the lobby and read the **starting clock** | See below. One launch, and **H2 would retract a standing project claim** | `______` |

### 5.1 · The `timelimit` test that decides whether the menu bounds `setgametypesetting()`

Writing 90 produced a 1:03 round twice, deterministically. Two explanations fit and the notes left it
open:

| | Store holds | Clock starts |
|---|---|---|
| **H1** — `fixed<8,2>` saturation | 63.75 | **1:03** (grace not on the clock) |
| **H2** — clamped to the menu's published max | 60 | **1:03** (grace *is* on the clock) |

▶ **Write 30 — a published value, far under both ceilings — and read the starting clock.**

| Clock | Verdict |
|---|---|
| **0:30** | grace is not shown → **H1**. The `fixed<8,2>` ceiling is what we hit. The standing claim holds: the menu's option list does not bound `setgametypesetting()` |
| **0:33** | grace is shown → **H2**, and the write at 90 was **clamped to the menu's published max**. That would mean `setgametypesetting()` **is** bounded by the published list — a retraction of one of this project's load-bearing claims, and it would put every "the menu cap says nothing" conclusion back in doubt |

⚠ **H2 is the more consequential outcome, which is exactly why it must not be assumed away.** The
`fixed<8,2>` reading is structurally true either way — 63.75 *is* the field ceiling — but that does not
prove it is the ceiling we hit at 90.

⚠ **B6 and B7 have moved.** They ride stage 4's menu (rows 5 and 6) or stage 3.3's save. Do not build
standalone payloads for them.

---

## Stage 6 — 🪦 measured closed. **Do not run these.**

Everything here was in this sheet as live work before the 2026-09-10/11 sessions. Each is now a
measurement. They are listed so the work is not redone, not because anything remains to do.

| Was | Now | Where |
|---|---|---|
| the old **Stage 4** — `test_frontend` read-only — does GSC run in the lobby? | ✅ **P1 CONFIRMED.** It runs, and the store it reads **is** the pending lobby config | `pregame-routes.md` |
| the old **Stage 5.1** — the pregame `maxplayers` write | ✅ **P2 WORKS** — 4v4 configured from the lobby, before anyone is seated | `pregame-routes.md` |
| the old **Stage 5.2** — the pregame `timelimit` write | ✅ **P3** — the rules menu *shows* the write. ⚠ But 60 is a published value, so it proved only that saving works. **45 or 55** is what proves anything — 90 saturates at the field's 63.75s ceiling (3.3) | `pregame-routes.md` |
| the old **probe 62** — `adddebugcommand` | 🪦 **NULLED. Probe 62 = 4.** The console is not reachable from GSC in CW retail. D10, `crack-cmds.py` and the whole DLL-command route go with it | `pregame-routes.md` |
| the old **Stage 6** — B1 / `switchmap_load` for the map | 🪦 **inert in MP** in-match (two iterations), and it **crashes the game** from the frontend. The menu's SESSION row is a dead option | `pregame-routes.md` |
| the old **Stage 6** — A4, the script-driven carry with the `endon` fix | 🪦 **moot.** The carry itself is measured to **crash connected clients**, so fixing its wrapper fixes the wrong thing. Host-side solo only | `pregame-routes.md` |
| the map **compat set** | 🪦 client-LUI `uimodeldatastruct #hash_109ccf57a41ffd82`, online-fed, unreachable from every injectable VM (P8–P11). Cheat Engine would reach it; **TAC will not let CE run** | `RESEARCH-INDEX.md` |

▶ **The one map route that survives all of that is stage 2.3** — `LobbySetMap` / `LobbySetGameType`,
which skips the compat set instead of fighting it. [`lobby-setters.md`](lobby-setters.md).

---

## Stage 7 — what "done" needs people for

Three tests need a second person, and one of them is the whole game:

| # | Test | Why it needs a person |
|---|---|---|
| **2.3b step 5** | a friend joins a `lobby-set.py` lobby | the carry **crashes connected clients**. Looking right on the host is the state the carry already reaches |
| **3.1** | a human plays 4v4 from the save | the team-size goal is verified with **bots**. `maxplayers` is a gametype setting the session's own restore reads, so it should transfer — but this project has walked back four claims that felt safer |
| **5 · C10** | a mid-match joiner lands on a team | the join path is the one route that does not care how the lobby was configured |

**And watch the spawns whenever people are in.** With `maxplayers` at 8 a 4v4 no longer *exceeds* the
configured team size, so the out-of-bounds precondition should be gone — and `#spawn_guard` now ships
in both `gunfight_mod` and the menu as the belt-and-braces fix. Bot run 2 played clean, but bots
tolerate a spawn a person would swear at. `src/test_spawnmode/` mode 2 stays built as the fallback.

▶ **Do them in one sitting.** All three want the same friend on the same evening, and 3.1 is the one
that turns CLOSED into DONE.

---

## What each result would change

| If this comes back | Then |
|---|---|
| **2.3b holds and a friend joins** | 🔓 **the map problem is closed** by the route nobody tried — real gametype, correct descriptor, no glitch, no second account |
| 2.3b reverts on a screen change | the Lua master re-pushes the selection. Route closed **by measurement**, and the three options in [`RESEARCH-INDEX.md`](RESEARCH-INDEX.md) are all that is left |
| **3.1 — a human plays 4v4 from the save, no injection** | 🔓🔓 **the team-size goal is DONE, not closed.** Real players, stock client, no toolchain on match night. This is the biggest single result still available |
| 3.2 — a save authored at 10 actually seats 10 | **5v5**, by the one route L8 did not test. 12 is then its own launch, not a bolder guess |
| 3.3 — `timelimit` at **45/55** survives the save | the timer stops needing an injector too. ⚠ 60 proves nothing; it is a published menu value |
| 3.4 — re-saving from a stock client normalises the value | the save is **read-only in practice**, and every incidental rules edit is a landmine. Worth knowing before a match night, not after |
| 2.2 (L0) = spectator joins a full team | **4v4 with zero code**, by a different door than `maxplayers` |
| 4 · row 8 — probe 60 arms with N > 0 and spawns hold at 4v4 | the out-of-bounds bug is fixed in the shipping artifact, not just in theory |
| 5 · C10 — a late joiner lands on a team | the strongest team-size route, and it does not care how the lobby was configured |
| **5.1 clock starts 0:33 (H2)** | 🪦 `setgametypesetting()` **is** bounded by the menu's published option list — a retraction of a load-bearing claim, and every "the menu cap says nothing" conclusion goes back in doubt |
| 5 · B9 re-run disagrees with the four-frame result | unattended operation reopens. That one finding is what decides whether an agent can put fresh code in the game without klaze present |
