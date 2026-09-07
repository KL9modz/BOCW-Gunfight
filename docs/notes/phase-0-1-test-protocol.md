# Phase 0 + Phase 1 — test protocol

Run this before writing any GSC. It costs ~90 minutes and no exposure, and either half can delete a
workstream outright.

**Exposure: zero.** Stock game, no injector, no compiler, no modified files, no third-party tooling.
Phase 0 and Phase 1 are indistinguishable from ordinary custom-game use.

## What each test decides

| Test | Question | Consequence |
|---|---|---|
| **T0.1** | How many lobby slots does each mode create? | Baseline for `com_maxclients` that T1.1 reads against |
| **T0.2** | Is a time-limit field exposed in the Gunfight rules menu? | Present → timer needs no mod up to the menu cap. Absent → timer work stands |
| **T1.1** | Does a 12-slot session survive a carry to Gunfight? | Retained → 6v6 with zero code. Collapsed → 6v6 unreachable, drop it |
| **T1.2** | Do 12 players spawn cleanly under `alwaysusestartspawns`? | Only runs if T1.1 passes |

## Ground rules for the run

- **Create a fresh lobby for each mode in T0.1.** Do not switch modes inside one lobby to save time —
  that *is* T1.1, and running it early contaminates the baseline.
- **Record the exact menu path you take**, not just the result. The BOCW front-end is compiled LUA and
  absent from every public dump (`.claude/CLAUDE.md` → dead ends), so the menu is only ever documented
  by someone walking it. These notes will be the only source that exists.
- **Record failures verbatim.** "Join failed", "slot greyed out", and "kicked to lobby" are three
  different findings.
- **Record the build/patch version.** The dump is a merge across patches; a result without a version
  is not reproducible.
- Screenshot anything numeric.

---

## Phase 0 — solo, ~1 hr

### T0.1 — lobby slot count per mode

**Question:** what is `com_maxclients` for TDM and for Gunfight?

`com_maxclients` is set by the engine at session creation and has zero writes anywhere in the script
dump (7 references, all `getdvarint`). It is what `function_d36b6597()` returns as the per-team cap for
any 2-team mode (`player_shared.gsc:1300`), which `function_efe5a681()` then compares a joining player
against (`team_assignment.gsc:94`). The number the lobby shows is the number that gates joining.

⚠ The slot count is strong evidence *about* `com_maxclients`, not a direct read of it — the UI could
render a different number than the join check enforces. T1.1's actual join attempt is authoritative;
T0.1 is the cheap baseline.

**Steps**

1. Multiplayer → Custom Games (label varies by patch — record what yours says).
2. Set mode to **Team Deathmatch**. Change nothing else.
3. Count every player slot rendered, filled and empty, across both teams.
4. **Leave the lobby entirely.** Return to the main menu.
5. Create a **new** lobby. Set mode to **Gunfight**.
6. Count slots again.

**Record**

- Menu path used: `_____`
- TDM total slots: `_____` (expected 12) — per team: `_____ / _____`
- Gunfight total slots: `_____` (expected 6) — per team: `_____ / _____`

**Reading it**

- TDM 12 / Gunfight 6 → matches the model. Proceed.
- Gunfight shows more than 6 → the 3v3 cap is not `com_maxclients`, and the 6v6 dead-end conclusion
  needs re-tracing before Phase 1 means anything.
- A count that changes *while you sit in the lobby* → note what changed it. That would mean the
  session re-evaluates, which is precisely what T1.1 asks about.

### T0.2 — Gunfight rules menu walk

**Question:** is the round timer editable without a mod?

`gunfight.gsc:1137` `gettimelimit()` reads `getgametypesetting( #"timelimit" ) / 60` and clamps to
`[level.timelimitmin, level.timelimitmax]`, which `util::registertimelimit( 0, 1440 )` sets to 0 and
**1440 minutes** (`globallogic.gsc:365` → `util.gsc:790`). The clamp is not the constraint. The menu
is: `time_limit_seconds.json` declares 20 values but publishes 6 via `"optionscount": 6` →
**0 / 20 / 30 / 40 / 50 / 60 seconds**, with 40 as `value4`, the default.

If that field is exposed, every target under 60s needs no mod at all.

**Steps**

1. Create a Gunfight custom lobby.
2. Open the game settings / rules editor.
3. Walk **every** page and subsection, not just the obvious one. Record each page name.
4. Look for a time-limit, round-time, or round-length field.
5. If found, open it and record **every** value offered, in order.

**Record**

- Pages walked: `_____`
- Time-limit field present: yes / no — page it lives on: `_____`
- Values offered, in order: `_____`
- Default shown: `_____`
- Any value above 60s: yes / no
- Editable, or greyed out: `_____`

**Reading it**

- Present, offers 0/20/30/40/50/60, default 40 → **the `optionscount` reading is confirmed and the
  timer needs no mod up to 60s.** Timer work only survives if you want >60s.
- Absent → timer work stands as designed.
- Present but offering different or more values → `time_limit_seconds.json` was read wrong, or the dump
  predates the live build. Re-trace before trusting any other JSON reading in these notes.
- Present but greyed out → record which mode greys it. It may be editable under another mode and
  carry, which is T1.1's mechanism applied to a setting instead of a mode.

⚠ **Whatever T0.2 returns, the `level.ontimelimit` reassignment stays mandatory.** It is not there for
the timer value — it is there because stock `overtime()` dereferences `level.zones[0]` on an unlocked
map and kills its own thread (`.claude/CLAUDE.md` → "Why the current glitched maps work"). A menu-set
timer does not fix that.

---

## Phase 1 — the 6v6 gate, ~30 min, 2+ people

### T1.1 — does a 12-slot session survive a carry to Gunfight?

**The question in one line:** is `com_maxclients` stamped at session creation, or re-evaluated on mode
change?

This is the **inverse** of the technique already in use. The known glitch starts from a Gunfight search
and carries a *map* in. This starts from a **TDM lobby** and carries the *mode* in — so the session is
created while the engine believes it is hosting a 12-player mode.

Stamped at creation → the lobby keeps 12 slots and Gunfight runs 6v6 with zero lines of code.
Re-evaluated on mode change → slots collapse to 6, and 6v6 is unreachable from anywhere, because script
can only ever read that dvar.

**Steps**

1. Create a custom lobby under **Team Deathmatch**.
2. Confirm the slot count matches T0.1's TDM number.
3. Apply the map/mode carry glitch to bring **Gunfight** into this lobby *without recreating the
   session*. **Write down every step, in order** — this repo has no record of the technique, and the
   next run needs it.
4. Immediately re-count slots.
5. Have players join until past 3v3. Record exactly what happens at the 7th player, and each one after.
6. If it fills, start the match. Record whether it launches or errors at load.

**Record**

- Slots before carry: `_____`
- Slots immediately after carry: `_____`
- Carry steps taken: `_____`
- Highest player count reached: `_____`
- Behaviour at the cap: joined cleanly / slot greyed out / join failed / kicked / other `_____`
- Match launched above 3v3: yes / no / error `_____`

**Reading it — three outcomes, not two**

| Observed | Meaning | Next |
|---|---|---|
| 12 slots retained, fills past 3v3, match launches | `com_maxclients` is stamped at session creation. **6v6 solved, no code.** | Run T1.2 |
| Slots collapse to 6 at the carry | `com_maxclients` re-evaluates on mode change | **Drop 6v6.** Record as a dead end and remove it from the goals table |
| 12 slots retained but joins blocked past 3v3 | `com_maxclients` is still 12 — something *else* enforces 3v3 | **Stop and re-trace** |

That third row is the one to watch for. `.claude/CLAUDE.md` calls `level.maxteamplayers` a red herring
on the grounds that `function_d36b6597()` consults it only when `teamcount == 0` or
`max_clients == teamcount`, i.e. multiteam only (`team_assignment.gsc:352`). A 12-slot lobby that
refuses a 7th player is direct evidence against that reading. It is cheap to observe here and expensive
to discover in Phase 3.

### T1.2 — spawn density at 12 players (only if T1.1 passed)

**Question:** does Gunfight's spawn configuration survive 4× its intended player count?

Gunfight sets `level.alwaysusestartspawns` and registers TDM spawn points (`gunfight.gsc:77`
`spawning::addsupportedspawnpointtype( "tdm" )`). Every MP map ships TDM spawns, so the points exist —
the open question is whether forcing *start* spawns puts 12 players in a space sized for 6.

**Steps**

1. From the T1.1 lobby, pick the **largest** map available.
2. Start with all 12 slots filled (bots are fine to pad).
3. Watch the first spawn of round 1, then of rounds 2 and 3.

**Record**

- Map used: `_____`
- Players stacked / spawned inside each other: yes / no
- Spawn failure, fall-through, or spectator-lock: `_____`
- Round 2/3 behaviour differs from round 1: yes / no
- Subjectively playable: yes / no

**Reading it**

- Clean → 6v6 needs nothing further.
- Stacking or failures → `alwaysusestartspawns` is the cause, and it is a `level.` field, i.e. writable
  from an injected script. That becomes a Phase 3 line item, not a blocker.

---

## Decision table

| T0.2 | T1.1 | What Phase 3 still has to build |
|---|---|---|
| Field present | 12 retained | Zones guard + latch flags + `ontimelimit`. No timer work, no 6v6 work |
| Field present | collapses to 6 | Same, minus 6v6 from the goals table |
| Field absent | 12 retained | Above + timer via the `timelimit` gametype setting |
| Field absent | collapses to 6 | Above, minus 6v6 |

In **every** row the zones guard, the two latch flags, and the `ontimelimit` reassignment survive. That
is the irreducible core of the mod, unaffected by both tests — which makes it the right Phase 3
hello-world target, and nothing else.

---

## Results

*(unfilled — record inline above, then summarise here)*

- Date run:
- Build / patch version:
- Participants:
- **T0.1:**
- **T0.2:**
- **T1.1:**
- **T1.2:**
- **Decisions taken:**
