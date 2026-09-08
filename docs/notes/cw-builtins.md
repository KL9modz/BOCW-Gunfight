# Cold War builtin table — functions this project never knew it had

**Source survey 2026-09-08.** [`ate47/t8-atian-menu`](https://github.com/ate47/t8-atian-menu)
`docs/notes/funcs_cw.csv` @ `f78bff6` — **4,481 Cold War script builtins**, each with argument counts
and an address in `BlackOpsColdWar.exe`. Same author as ACTS and as the dump this project reads.

This is a **different kind of reference from `bocw-source`.** The dump shows what *stock script*
calls. This table shows what the *engine exposes*, including functions no stock script uses. Several
of them bear directly on open questions here.

⚠ **A name in this table is not a working call.** It proves the engine exports the symbol, nothing
more. Argument *meanings* are unknown, return types are unknown, and the CW build may reject calls
the table lists. Validate with `tools/check-gsc.ps1` stage 4, then measure.

---

## 1 — There are FOUR player-count builtins. This project has used one.

| Builtin | Args | Address | Used here? |
|---|---|---|---|
| `getdvarint( #"com_maxclients" )` | — | — | ✅ the only one |
| `getnumexpectedplayers` | 0–1 | `+3b09500` | ❌ never called |
| `numremoteclients` | 0–0 | `+3c607f0` | ❌ never called |
| `getnumconnectedplayers` | 0–1 | `+3b09cc0` | ❌ never called |

The whole team-size argument in [`team-sizes.md`](team-sizes.md) rests on `com_maxclients` reading
**8** in a 3v3 Gunfight lobby and **12** in private TDM. That is one number from one source.

**If any of the other three disagrees with it, "8 slots" is not one fact but several** — and the
6-players-plus-2-spectators split this project has assumed becomes something to measure rather than
infer. [`../../src/lobby_probe/`](../../src/lobby_probe/) reads all four in one match.

## 2 — `isvalidgametype()` tests a gametype string without switching to it

`isvalidgametype` — 1 arg, `BlackOpsColdWar.exe+3b0b300`. **Read-only, zero risk, and it can be
asked about a string that does not exist.**

The project knows two Gunfight strings, both from `mp_common/player/player_record.gsc`'s switch:
`gunfight` and `gunfight_3v3`. Nobody has asked whether the enum holds more.

**If `gunfight_4v4` or `gunfight_5v5` validates, the team-size target may be a string rather than a
lobby-configuration problem.** That would be the cheapest possible answer to the project's remaining
goal, and it costs one probe.

`lobby_probe` packs the answers into a single bitmask with **a negative control** (`zzz_not_a_gametype`,
which must read 0) and **two positive controls** (`gunfight`, `tdm`, which must read 1). Read the
controls before the payload — a function that returns true for everything is worse than no reading at
all. That is the `jump_height` lesson from [`mp-dvars.md`](mp-dvars.md).

Related, both untested:

- **`getgametypeenumfromname`** — 2 args, `+3bd0d20`. Would confirm `gunfight` = `0x2f` from the
  running game rather than from the dump, and resolve any name the bitmask turns up.
- **`forcegamemodemappings`** — 2 args, `+3b0af80`. Name suggests it forces gametype↔map pairings.
  Nothing is known about it. Worth reading in the dump for a call site before trying it live.

## 3 — ⚠ `getgametypesetting` takes up to TEN arguments

`getgametypesetting` — **1–10 args**. Every call in this project, and every stock call cited in
`.claude/CLAUDE.md`, passes exactly one. What the other nine do is unknown and unexamined.

`setgametypesetting` is 2–2, so the asymmetry is real, not a table artifact. Cheap to investigate in
the dump: find any stock call site passing more than one argument.

## 4 — Bots. The test plan asks for them and had no mechanism.

`.claude/CLAUDE.md` → Phase 3 says **"Bots before humans."** There has never been a documented way to
add one. The table has a full suite:

| Builtin | Args | Address |
|---|---|---|
| `addtestclient` | 0–2 | `+3d3c9e0` |
| `isbot` / `istestclient` / `islobbybot` / `isrobot` | 1 / 0 / 0 / 0 | — |
| `ishostforbots` | 0 | — |
| `botsetmovedir`, `botpressbutton`, `bottapbutton`, `botswitchtoweapon`, … | | ~20 more |

**`addtestclient()` in a loop is a direct, empirical measurement of the real client ceiling** — better
than reading a dvar, because it tests the thing itself. Add clients until it stops accepting them and
the answer is the count, whatever `com_maxclients` says.

⚠ This is a **write**. It changes the session, it may fail in ways that need a lobby return to clear,
and `kick` (1–2 args, `+3b0a3a0`) is the only obvious undo. Stage it alone.

## 5 — Team and spectator control is script-reachable

`com_maxclients` is read-only from script. **Team assignment is not.**

| Builtin | Args | What it might allow |
|---|---|---|
| `setteam` | 1 | Move a client onto a team |
| `getteam` | 0 | Read one back |
| `getassignedteam` / `getassignedteamname` | 1 | What the session assigned |
| `getteamplayersalive` | 1 | Per-team live count |
| `allowspectateteam` / `allowspectateallteams` | 2 / 1 | Spectator permissions |
| `spawnspectator` / `setcurrentspectatorclient` | 2 / 1 | Spectator handling |

⚠ **`setteam` turned out to be the wrong lever** — 55 stock call sites, all world objects. See
[`dump-cross-check.md`](dump-cross-check.md). The player path is `teams::change()`, and the **cheaper**
question is whether a team accepts a fourth player at all: `function_d36b6597()` returns
`com_maxclients` for a two-team mode and `team_assignment.gsc:95` refuses only at eight, so nothing
in that path enforces three. That is what [`../../src/test_teamfill/`](../../src/test_teamfill/) asks. Where the 6+2 split is actually enforced is unestablished — `team_assignment.gsc:94`
gates on `team_players.size >= max_players` where `max_players` resolves to `com_maxclients` (8),
which is not obviously 3-per-team.

⚠ Untested, and `setteam`'s single argument may be a team name, an index, or something else entirely.

## 6 — `map_restart()` may remove the F7 dependency

`map_restart` — 0–1 args, `+3b0a5c0`.

[`menu-map.md`](menu-map.md)'s procedure requires cwpatch's **F7** (`full_restart`) at step 7, because
the lobby route discards the map carry. cwpatch is therefore a hard prerequisite for the whole
workflow, and Battle.net silently reverts it on repair.

**If `map_restart()` restarts without going through the lobby, the DLL stops being required.** Same
class of restart, reachable from the script already being injected.

Also there: `mapexists` (1 arg, `+3b0b2d0`) — tests a map name without loading it, the map-side
equivalent of `isvalidgametype`.

## 7 — `sessionmodeisprivate()` lets the mod verify its own ground rule

`sessionmodeisprivate` (0 args, `+3ce9830`), alongside `sessionmodeisprivateonlinegame`,
`sessionmodeisonlinegame`, `sessionmodeissystemlink`.

The project's first ground rule is **private matches only**. Right now that is enforced by the
operator remembering. `gunfight_mod` could gate its own `mod_apply()` on this and refuse to modify a
non-private session — turning a procedural rule into a mechanical one.

---

## Staged tests — ordered by risk, cheapest and safest first

| # | Test | Risk | Answers |
|---|---|---|---|
| **0** | **`tools/dump-grep.sh`** — stock call sites for the builtins below | **none, off-game** | The argument shapes that block tests 6–7, and whether a larger Gunfight string already exists in the dump |
| **1** | **`lobby_probe`** — four player counts, gametype bitmask, session flags | **none, read-only** | Whether `com_maxclients` is the whole story, and whether a larger stock Gunfight variant exists |
| **2** | `getgametypeenumfromname( "gunfight", ? )` | read-only | Confirms the enum live; resolves anything test 1 turns up |
| **3** | `mapexists()` over the 48 names in the Atian source | read-only | Which of them this build actually has |
| **4** | `map_restart()` in a carried lobby — [`../../src/test_maprestart/`](../../src/test_maprestart/) | restarts a match | Whether cwpatch/F7 can be dropped from the procedure |
| **5** | `switchmap_load( get_map_name(), "gunfight_3v3" )` in a 12-slot TDM lobby | reloads the session | **The team-size question.** [`atian-menu-source.md`](atian-menu-source.md) |
| **6** | `addtestclient()` in a loop until refusal — [`../../src/test_addclients/`](../../src/test_addclients/) | adds clients | The **real** client ceiling, measured rather than read |
| **7** | fill ONE team until refused — [`../../src/test_teamfill/`](../../src/test_teamfill/) | adds clients to a team | Whether 8 clients can be 4v4 |

Tests 5–7 now ship as code: [`../../src/test_switchmap/`](../../src/test_switchmap/),
[`../../src/test_addclients/`](../../src/test_addclients/),
[`../../src/test_teamfill/`](../../src/test_teamfill/). Separate projects on purpose — a payload that
can only do one thing cannot accidentally do another. Readings and decision tables:
[`test-queue.md`](test-queue.md).

⚠ **One per match.** Tests 4–7 are writes with distinct failure modes; bundling them makes a failure
unattributable. Test a **lobby return** after each, which is the check that caught the
`scene_model_shared` breakage.

⚠ Injecting begins host-side exposure — [`tac-risk-model.md`](tac-risk-model.md).

## Untried — not ruled out

- **The other 4,400 builtins.** This survey filtered for lobby, team, player-count, gametype, map, bot
  and dvar names. Whole categories are unexamined.
- **`xassetpools_cw.csv` / `xasset_origins_cw.csv`** in the same folder — asset pool layout. Unread.
- **`opcodes_cw.txt`** — VM38 opcode table. Unread, and relevant if a compiled payload ever needs
  hand-inspection.
- **The 9 unexamined `getgametypesetting` arguments.**
