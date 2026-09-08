# Test queue — everything open, ordered by risk

One sheet aggregating every untested item across the notes, so a session at the machine does not have
to read five files to find the next thing to run. **Fill in the Result rows and the answer becomes the
finding.**

⚠ **A result is a measurement.** Record what the number was. Do not record "therefore X is
impossible" — every such conclusion in this project has had to be walked back. Where a test comes back
negative, write what it ruled *in*, and move the question to that note's *Untried* list.

⚠ **One write per match.** Everything in bands B and C changes session state, each with different
failure modes; bundling them makes a failure unattributable. **Test a lobby return after each** —
that is the check that caught `scene_model_shared`.

**Setup for anything injected:** [`menu-map.md`](menu-map.md) → *PROCEDURE*.

### The results that would actually move a goal

0. **L0 — in-match team change working past the lobby cap.** Stock, private-match-only, one rules
   toggle. If a player can join a full side after the match starts, **4v4 needs no code at all** and
   the whole team-size track collapses to "get eight bodies in the lobby".
   [`lobby-settings.md`](lobby-settings.md)
1. **L2 — a Max Players row that goes to 12 and actually changes the slot count.** No injection, no
   code, no exposure, about two minutes. If it works it closes the last open goal outright and makes
   most of band C unnecessary. **Check this before anything else.**
   [`lobby-settings.md`](lobby-settings.md)
1. **A1's probe `6xxxxx` reading 3** — `maxsquadplayers` is a runtime-writable gametype setting that
   bounds squad size, and for Gunfight a team *is* a squad. Reading 3 in a 3v3 lobby makes it the
   lever this project has been hunting from the start, and the next step is **one
   `setgametypesetting` call**, not a new mechanism. **The cheapest path to the goal that has ever
   been on the table.** [`dump-cross-check.md`](dump-cross-check.md)
1. **A1's bitmask above 7** — a stock Gunfight variant at 4v4 or larger turns the goal into a string.
2. **C6 reading `100012` after the switch** — team size becomes script-reachable.
3. **C8's probe `3xxxxx` reaching 4** — a team holds four, so 8 clients is 4v4 from the lobby you
   already have. ⚠ That probe number changed when `test_setteam` became `test_teamfill`.
4. **B4 keeping the carried map** — the hosting procedure loses its DLL prerequisite.

Everything else is worth knowing but does not move a goal.

---

## L — THE LOBBY. No injection, no modded anything. ← **do these first**

The hosting workflow — create lobby, pick map/mode/rules, invite, teams, start — happens entirely
*before* the match, in a layer none of this project's code has ever reached.
[`lobby-settings.md`](lobby-settings.md) maps it, and found a rules-menu row that may hand over the
team-size goal for free.

### L0 · **Allow In-Game Team Change** — the cheapest path to 4v4 that exists ← **do this first**

klaze measured the pre-game team screen capping at **2** (Gunfight), **3** (3v3), **4** (CDL Pro S&D),
**unrestricted** (TDM). That cap is a *lobby* rule. `serversettings.gsc:42` turns on in-match team
switching for **private matches** when `allowingameteamchange` is set — and that setting **has a
rules-menu row**. The in-match gate is `com_maxclients` (**8**), not 2 or 3.

1. Rules menu → find **Allow In-Game Team Change** → on
2. Start a match, open the in-match team menu, try to join the full side

| Outcome | Means |
|---|---|
| **switch succeeds past the lobby cap** | **4v4 needs no code** — only enough players in the lobby |
| row absent from Gunfight's rules | the bundle exists but this variant does not show it |
| switch blocked anyway | something past `serversettings.gsc` is enforcing it; record what the game says |

⚠ Then the binding constraint is **lobby capacity**, not the cap: 4v4 needs 8 players in an 8-client
lobby, so the two suspected spectator slots must be usable. Same question as C7/C8, different door.
Result: `______`

### L1 · Is there a **Max Players** row in the Gunfight rules menu?
`scriptbundle/gamesettings/max_players.json` is a real menu row writing `maxPlayers`, publishing
**1–12**, with no per-gametype variant. Walk every rules page of a **Gunfight Custom Games** lobby and
look for it.

⚠ Phase 0 **T0.2** already walked those pages — **looking for the timer**. Nobody was looking for a
player count, so its silence is not a negative. Result: `______`

### L2 · If it exists, set it to 12 and count the slots ← **the whole goal, with no code**
`com_maxclients` is fixed at lobby creation and read-only from script. A rules row that sets max
players *before* the match acts at exactly that layer.

| Slots | Means |
|---|---|
| **12** | **team size solved with no mod at all.** Most of band C stops mattering |
| still 8 | `maxPlayers` does not drive lobby size — it may only feed challenge logic |

Result: `______`

### L3 · Bot Autofill / Bot Difficulty rows
`bot_autofill_allies` and `bot_autofill_axis` are real bundles. If those rows exist, filling a test
lobby needs **no injection** — strictly better than `bot::add_bot()` for C7/C8. Result: `______`

### L4 · With Max Players at 12, start the match and read `lobby_probe` `1xxxxx`
The only one here that needs injection. Confirms whether `com_maxclients` followed the menu setting.
Result: `______`

---

## 0 — Off-game. Dev PC, no game, zero exposure.

### A0 · `tools/dump-grep.sh` — resolve builtin argument shapes ← **run first**

```bash
bash tools/dump-grep.sh                    # dump at ../bocw-source-main
bash tools/dump-grep.sh /c/path/to/dump    # or say where it is
```

Writes `dump-report.md`. Greps stock call sites for `setteam`, `addtestclient`, `map_restart`,
`getnumexpectedplayers`, `switchmap_*`, `kick`, the spectator functions, and any `getgametypesetting`
call passing more than one argument.

✅ **RUN 2026-09-08, against BOTH dumps.** [`dump-cross-check.md`](dump-cross-check.md) has the
findings — a real team-size lead (`maxsquadplayers`), one confirmed retraction (`setteam` is an entity
function), and **one retraction that was itself wrong** (`gunfight_3v3` is real; the alternate dump
just leaves it hashed).

⚠ **The lesson, and it cost a wrong code change: grep `ate47/bocw-source`, not the alternate.**
`bash tools/dump-grep.sh` with **no argument** defaults to the primary for exactly this reason.
Absence in `shiversoftdev/t9-src` is evidence of nothing.

**Two things to look at first:**

- **The `gunfight*` string list.** Anything beyond `gunfight` and `gunfight_3v3` **pre-answers A1's
  headline with no game at all** — and would go straight into C6's `target`.
- **Whether `setteam` has zero stock call sites.** That is not a failure; C8 is written to work either
  way (it reads a team value off an existing player and passes it back, never guessing). But zero
  sites means the dump cannot corroborate C8's reading, so weight C8's result accordingly.

Result: `______`

---

## A — Zero risk. Read-only, nothing written.

### A1 · `lobby_probe` — four player counts and the gametype bitmask ← **the headline**
`src/lobby_probe/` · [`cw-builtins.md`](cw-builtins.md)

Validate offline first — it calls builtins **no stock script calls**, so stage 4 is the real gate:

```powershell
.\tools\check-gsc.ps1 .\src\lobby_probe\scripts\lobby_probe.gsc
```

| Read | Expect | Result |
|---|---|---|
| `1xxxxx` `com_maxclients` | 8 in 3v3 Gunfight, 12 in TDM | `______` |
| `2xxxxx` `getnumexpectedplayers()` | **unknown — never called** | `______` |
| `3xxxxx` `numremoteclients()` | **unknown** | `______` |
| `4xxxxx` `getnumconnectedplayers()` | **unknown** | `______` |
| `5xxxxx` flags | 1=teambased + 2=private → expect **3** | `______` |
| `6xxxxx` **`maxsquadplayers`** | **THE prediction.** klaze confirmed a 3v3 lobby caps team assignment at **3 per side**, and all 427 menu bundles were read — **no row sets a per-side cap**, so it is a gametype setting with no menu exposure, which is exactly what `maxsquadplayers` is. **Predicted: `3` in a 3v3 lobby, `2` in normal Gunfight.** Both readings confirm it is the cap; anything else kills the lead. **Run in BOTH lobbies** — one reading cannot tell "it is the cap" from "it happens to be 3" | 3v3: `____` · 2v2: `____` |
| `7xxxxx` **`maxplayers`** | never read by this project. `uint:4` (max 15) in `custom_games.ddl`, `uint:7` (max 127) in `mp_custom_game.ddl`. ⚠ Its only *known* consumer is challenge logic, so it may gate nothing — but it is free to read | `______` |
| `9xxxxx` **gametype bitmask** | see below | `______` |

**Read the controls before the payload.** Bit 0 (`gunfight`) and bit 1 (`tdm`) must be SET; bit 7
(≥128, `zzz_not_a_gametype`) must be CLEAR. Outside `3..127` the probe is meaningless — discard it,
do not interpret it. A function returning true for everything is worse than no reading, which is the
`jump_height` lesson from [`mp-dvars.md`](mp-dvars.md).

- `7` = only the two known strings plus `tdm`. Expected.
- `>7` = **a Gunfight variant nobody knew about.** 16 = `_4v4`, 32 = `_5v5`, 64 = `_6v6`.

**Run it in BOTH a 3v3 Gunfight lobby and a private TDM lobby.** Probes 2–4 are most interesting
where they *disagree* with probe 1 — a disagreement means "8 slots" is several facts, not one, and
the 6-players-plus-2-spectators reading becomes measurable rather than inferred.

⚠ If probes 2–4 all read 99999, they returned undefined rather than a count. That is a result about
the *builtins*, not about the lobby — record it and C8 becomes the better route to the same question.

### A2 · Re-count the Atian map list
[`atian-menu-source.md`](atian-menu-source.md)

The walk recorded **19** maps; the CW source wires **48** entries, **37** of them under
`is_multiplayer()`. Open `(4/4)` → `Map` and count to the bottom.

| Count | Means |
|---|---|
| ~19 | the shipped `latest_build` release predates current master — **a source build would offer more maps** |
| ~37 | the earlier count was one page, and the full list was always there |
| something else | record it; neither explanation fits |

⚠ Count by scrolling to the end, not by what fits on screen — the root menu is paged and the map
submenu may be too. Result: `______`

### A3 · `mp_probe` on a carried lobby
Classify a carried map's `gunfight_zone_center` count (`5xxxxx`). Expect **0**, the same as every
stock Gunfight map (n=2, ICBM and Amsterdam). A non-zero would overturn
[`gunfight-findings.md`](gunfight-findings.md)'s headline, which is currently the basis for
`zones_guard` being necessary at all.

Also worth reading here: `2xxxxx` (live `timelimit`). Under a carry it should show `timer_override`'s
value, not the rules-menu value — that is the second confirmation of the reset behaviour.
Result: `______`

---

## B — Low risk. Reverts on restart.

### B4 · `map_restart()` — can cwpatch be dropped?

`map_restart` — 0–1 args, `BlackOpsColdWar.exe+3b0a5c0`.

**Why it matters more than it looks.** [`menu-map.md`](menu-map.md)'s procedure needs **F7**
(`full_restart`) at step 7, because returning via the lobby discards the map carry. That makes cwpatch
a hard prerequisite for the entire workflow — and Battle.net silently reverts
`discord_game_sdk.dll` on repair, so the whole recipe breaks with no obvious cause. Removing that
dependency makes the setup one step shorter and one failure mode smaller.

`src/test_maprestart/` · ships with `read_only = 1`.

**Procedure:** run steps 1–5 of the hosting recipe, **carry to a map**, then inject this instead of
pressing F7.

⚠ **Why it needs a dvar.** To answer "did the carried map survive" the script must compare the map
before the restart with the map after. `level` is rebuilt per round (mp_probe probe 6, answered), so
`level.*` cannot carry a value across; whether `__init__` state survives is still probe 8's open
question. So the previous map name is parked in `scr_gf_prevmap`, which is process-level.

⚠ That is **not** the closed loop `mp_probe.gsc` warns about: we store map A, the engine reloads, and
we compare our stored A against a **fresh `util::get_map_name()` from the engine**. The comparison is
against engine-owned state, so it is evidence.

It emits on every `on_start_gametype`; you want two readings.

| Run 2 reads | Means |
|---|---|
| `100001 / 200001` | **carried map SURVIVED.** cwpatch comes out of the critical path — update the procedure |
| `100001 / 200000` | `map_restart` reloaded the lobby's own map, like the lobby route does. F7 stays required |
| `100000 / 2xxxxx` | the **dvar** did not survive the restart. A result about dvar lifetime, not about the map — the test needs a different carrier before it can answer B4 |
| no run 2 at all | nothing restarted, or the script did not re-link. **Check the hook before concluding the call failed** |

⚠ Calls the **no-argument** form — 0–1 args, and 0 args is the only one that cannot be wrong about an
argument. `pass_arg` / `arg_value` are there if A0 shows stock passing something.

Result: `______`

### B5 · `mapexists()` over the 48 source names

`mapexists` — 1 arg, `+3b0b2d0`. The map-side equivalent of `isvalidgametype`: tests a name without
loading it. Read-only.

**Cheapest as an addition to `lobby_probe`** rather than a new project — same bitmask trick, one bit
per name, batched in groups of ~20 so each number stays readable. Tells you which of the Atian
source's names this build actually has, which is also a cross-check on A2's count.

Result: `______`

---

## C — Session writes. **One per match. Lobby return after each.**

### C6 · `switchmap_load` from a 12-slot TDM lobby ← **the team-size question**
`src/test_switchmap/` · [`atian-menu-source.md`](atian-menu-source.md)

⚠⚠ **START IN PRIVATE TDM, NOT GUNFIGHT.** The whole test is whether a 12-slot lobby *keeps* its 12
slots after the gametype switches in place. Starting in Gunfight makes the reading meaningless.

The script is `func_set_gametype()` from the Atian Menu's CW source — dead code there — extracted and
instrumented. **Run with `read_only = 1` first**: it reports the lobby state and switches nothing,
confirming you are in the right lobby before spending a session reload.

It emits on **every** `on_start_gametype`, so you get a reading before the switch and another after.

| Sequence | Means |
|---|---|
| `100012 / 200000` then `100012 / 200001` | **THE WIN.** Gunfight running in a 12-slot lobby |
| `100012 / 200000` then `100008 / 200001` | switchmap re-derived the lobby from the gametype, same as the map carry |
| `2xxxxx` never reads 1 | the optional gametype argument was ignored. **That is the finding** — record it |
| no second reading at all | the script did not survive the reload. Re-inject and check the hook, do not assume the switch failed |

⚠ `switchmap_load` is 1–2 args; the 2-arg form existing does not prove the CW build honours the
second. ⚠ ate47 on the sequence: *"the wait is important, I don't know why."* Do not remove it.

Result: `______`

### C7 · `addtestclient()` — the **real** client ceiling, measured
`src/test_addclients/` · [`cw-builtins.md`](cw-builtins.md) §4

Everything this project believes about team size rests on `com_maxclients` reading 8. This fills the
lobby until the engine refuses, and the refusal point *is* the ceiling — measured, not read.

The script calls the **zero-argument** form (the only one that cannot be wrong about an argument),
waits 2s after each add for the join to land, stops after two consecutive adds fail to raise the
count, and hard-caps at 20 iterations so a never-tripping exit condition cannot spin forever in a live
match.

| Read | Means | Result |
|---|---|---|
| `3xxxxx` players after the fill | **the answer.** 6 = spectator slots are not player slots. 8 = they are, and **8 clients is 4v4** | `______` |
| `4xxxxx` adds that stuck | `3xxxxx` minus the baseline | `______` |
| `5xxxxx` attempts | if this reads 20, the cap was hit and the ceiling is higher than the test looked — raise `maxtries` and rerun | `______` |

⚠ Bots may not leave cleanly. `kick` (1–2 args, `+3b0a3a0`) is the only obvious undo; A0 reports its
call sites. **Also the mechanism Phase 3's "bots before humans" always assumed and never had** — if
this works, every later test gets cheaper.

### C8 · the PER-TEAM ceiling — can four stand on one team?
`src/test_teamfill/` · [`dump-cross-check.md`](dump-cross-check.md)

⚠ **This replaces the earlier `test_setteam`, which was built on a wrong premise.** `setteam` has 55
stock call sites and every one sets the team of a *world object*. The player path is
`teams::change()`. The grep caught it before a match was spent on it.

**The dump says the 3-per-team limit is not enforced by team assignment.**
`function_d36b6597()` returns `com_maxclients` for a two-team mode, and `team_assignment.gsc:148`
refuses a team only at `team_players.size >= 8`. So this test does not try to *force* anything — it
puts bots on one team with `bot::add_bot( team )` until the engine refuses, and reads where it lands.

**Run with `read_only = 1` first** to confirm the team value is the right representation.

| Read | Means | Result |
|---|---|---|
| `2xxxxx` on the team before | baseline | `______` |
| `3xxxxx` on the team after | **the answer.** ≥4 = a team holds four, and 8 clients is 4v4 | `______` |
| `4xxxxx` total players after | if this hit `com_maxclients`, the TOTAL cap bit first and the run says nothing about the per-team limit — free up slots and rerun | `______` |
| `5xxxxx` attempts | `______` |

⚠ `3xxxxx` stopping at 3 does **not** mean the goal is unreachable — it means something enforces three
that the dump does not show, and *that* is the finding. Candidates are in
[`dump-cross-check.md`](dump-cross-check.md)'s *Untried* list.

### C9 · The lobby glitch + `mp_probe`
[`menu-map.md`](menu-map.md)

The map/mode carry glitch is a genuine **playlist reconfiguration** where our carry is only a
load-time override — so it acts on the layer that actually sets `com_maxclients`. Get into a glitched
Gunfight-on-a-6v6-map lobby, inject `mp_probe`, read `1xxxxx`.

`100012` = twelve slots, and the goal is met with no code at all. `100008` = the glitch changes the
map list but not the slot count.

⚠ Unreliable, but this only needs to work **once**. ⚠ Distinguish it from the Atian carry: the glitch
makes the game report *"Gunfight on \<map\>"* correctly, where the carry leaves the scoreboard naming
the old map. If the scoreboard is stale you are in a carry, not a glitch, and the reading means
something else. Result: `______`

---

## D — Menu walk leftovers. No injection beyond the menu itself.

| # | Item | Why it is still open | Result |
|---|---|---|---|
| **D10** | **Pages 1–3** of the Atian Menu | ✅ **Largely resolved without a walk.** `Unlock`/`Dev` are `#ifdef ATIAN_MENU_DEV`, so an MP release build shows **8** root entries = **2 per page, declaration order**: `(1/4)` Tools·Guns · `(2/4)` Weapons·Camo · `(3/4)` Skin·Outfit · `(4/4)` Vehicle·Map. Page 4 already matches the walk and klaze confirmed no `Unlock` in MP. **Remaining: confirm the six names on pages 1–3** — the shipped `.gscc` is an older release than the source | `______` |
| **D11** | **Host vs joiner** | Only ever opened in a single-player lobby. Can a joiner open it? Does the carry behave for them? Bears directly on the participant disclosure in [`tac-risk-model.md`](tac-risk-model.md) | `______` |
| **D12** | **In-lobby vs in-match** | Only ever opened in-match. If it opens in-lobby, the procedure may lose a step | `______` |

---

## Build and inject

```powershell
python3 tools\check-args.py src\<project>\scripts\<project>.gsc   # arity — check-gsc.ps1 skips this
.\tools\check-gsc.ps1 .\src\<project>\scripts\<project>.gsc      # compile + resolve
acts gscc src\<project>\scripts\<project>.gsc -g cw -p pc -o <project>
```

✅ **All five new projects pass `check-args.py` with zero arity mismatches**, run here 2026-09-08
against the CW table. That is builtin arity only — it is not a compile, and `check-gsc.ps1` still has
to run on your machine.

then place the `.gscc` in `$GF_PAYLOADS` and inject per [`../../tools/README.md`](../../tools/README.md).

⚠ **A harness PASS is necessary, not sufficient** — it does not check argument counts, dialect, or
anything about runtime. `src/README.md` → *What a harness PASS does and does not mean*.

✅ **All five now compile.** Stages 1–2 ran on the Windows box `vmi3404923` 2026-09-08 and all five
came back clean, which closes dialect — the class behind two of three game-crashing defects here.
Stages 3–4 and arity ran separately in the cloud session, also clean. **Every offline check the
project has is green.** [`compile-status.md`](compile-status.md)

⚠ Two caveats live in that file: the result was **relayed rather than seen** (the VPS has no push
credential), and the **ACTS version was not recorded** while the project pins v3.3.0. Neither is
likely to matter; both are cheap to settle.

⚠ Injecting begins host-side exposure — [`tac-risk-model.md`](tac-risk-model.md). Nothing here hides
itself from the anti-cheat; that is out of scope by decision, not oversight.
