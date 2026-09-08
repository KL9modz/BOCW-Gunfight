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

### The four results that would actually move a goal

1. **A1's bitmask above 7** — a stock Gunfight variant at 4v4 or larger turns the goal into a string.
2. **C6 reading `100012` after the switch** — team size becomes script-reachable.
3. **C8's probe 6 reading 1** — 4v4 from the lobby you already have.
4. **B4 keeping the carried map** — the hosting procedure loses its DLL prerequisite.

Everything else is worth knowing but does not move a goal.

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

### C8 · `setteam()` — is 8 clients actually 4v4?
`src/test_setteam/` · [`cw-builtins.md`](cw-builtins.md) §5

**This script never guesses the argument.** It reads a team value off a player who already has one and
passes that back — whatever representation the engine uses is the representation it gets. Probe 3
additionally *reports* which representation it is, by comparison rather than display, since a hashed
team name cannot render on retail but `x === #"allies"` evaluates fine.

**Run with `read_only = 1` first.** Phase 1 writes nothing and is what settles the argument shape.

| Read | Means | Result |
|---|---|---|
| `3xxxxx` representation | 1=`#"allies"` 2=`#"axis"` 4=`"allies"` 8=`"axis"`. **0 = none matched, and that is itself the finding** — stop and record | `______` |
| `4xxxxx` on the donor team before | team distribution | `______` |
| `6xxxxx` **did the team change** | **the answer.** 1 = team assignment is script-writable | `______` |
| `7xxxxx` on that team after | confirms the move landed rather than the read being stale | `______` |

⚠ Needs at least two clients on different teams. **Run C7 first** — with bots in the lobby this test
has something to move; solo it returns 99999 on probe 6 and tells you nothing.

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
| **D10** | **Pages 1–3** of the Atian Menu | Never transcribed — reported as "weapons and camera stuff", which settled the gametype question but is not an index. ⚠ The upstream README's feature list is written for **BO4** and did not match page 4, so do not use it as a CW inventory | `______` |
| **D11** | **Host vs joiner** | Only ever opened in a single-player lobby. Can a joiner open it? Does the carry behave for them? Bears directly on the participant disclosure in [`tac-risk-model.md`](tac-risk-model.md) | `______` |
| **D12** | **In-lobby vs in-match** | Only ever opened in-match. If it opens in-lobby, the procedure may lose a step | `______` |

---

## Build and inject

```powershell
.\tools\check-gsc.ps1 .\src\<project>\scripts\<project>.gsc      # validate offline FIRST
acts gscc src\<project>\scripts\<project>.gsc -g cw -p pc -o <project>
```

then place the `.gscc` in `$GF_PAYLOADS` and inject per [`../../tools/README.md`](../../tools/README.md).

⚠ **A harness PASS is necessary, not sufficient** — it does not check argument counts, dialect, or
anything about runtime. `src/README.md` → *What a harness PASS does and does not mean*.

⚠ Injecting begins host-side exposure — [`tac-risk-model.md`](tac-risk-model.md). Nothing here hides
itself from the anti-cheat; that is out of scope by decision, not oversight.
