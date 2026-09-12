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

▶ **At the machine, open [`desktop-session.md`](desktop-session.md) instead.** This file is the
reference — every test with its full decision table, grouped by risk. That one is the runbook: the
same tests ordered by what they cost, starting with six questions that need no game at all and the
free observations that can delete whole stages below.

### The results that would actually move a goal

⚠ **REWRITTEN 2026-09-09. All three goals are CLOSED** — map, timer, and team size. The list this
replaced still led with `maxsquadplayers` (measured **0/0**, dead), with L2 (**no such row**), and with
C10/C11 as "the strongest route" to a goal that `maxplayers` closed by a different door. A queue that
points at settled ground is worse than no queue, because it costs a session before it costs a match.

0. **A1 — `gunfight_menu` is BUILT and needs the compile gate.** One payload: gunfight_mod's fixes +
   team size + the in-match menu (teams, bot fill, move players, timer, loadout, spy plane, restart,
   map). Offline checks green; **never compiled, never injected.** It replaces `inject.sh mod` +
   the Atian Menu in the hosting workflow once it runs. Protocol below (band M).
1. 👤 **A HUMAN 4v4.** The goal is closed **with bots**. `maxplayers` is a gametype setting the
   session's own team-size restore reads, so it *should* transfer — but "should transfer" is not
   "measured", and this project has walked back four claims that felt safer than this one.
   ▶ **Needs bodies, nothing else.** No new code, no new test. It is the single largest gap between
   "closed" and "done".
2. 👤 **Do the spawns hold at a human 4v4?** B8 is **downgraded, not deleted**: with `maxplayers` at 8
   a 4v4 no longer *exceeds* the configured team size, so the precondition for the out-of-bounds bug
   is gone. Run 2 played cleanly — with bots, which tolerate a spawn a player would swear at.
   ▶ Same session as #1. Watch where people land. `src/test_spawnmode/` stays built as the fallback.
3. **B9 re-run with the guard dvar cleared.** B9 concluded that injecting under a live script breaks
   the link — and its own caveat says frames were **sampled, not exhaustively read**. That conclusion
   is what closes off unattended operation, so it deserves one clean confirmation rather than
   standing on four frames.
4. 🔓 **5v5, and it is no longer ruled out.** `maxplayers = 10` **lands and sticks** (L8) — what did
   not follow was `com_maxclients`, which stayed at 8. So the setting reaches; the budget did not.
   ⚠ The one `12` reading remains **unexplained and is recorded as an anomaly, not evidence**. Ten
   clients with zero casters is tight, not impossible.
5. **B6 / B7 — two free features, one `setgametypesetting` each, never run.**
   `gunfightloadoutindex` gives **snipers-only** and **melee-only** Gunfight; `gunfightspyplane` value
   3 is a mode the menu hides. Neither has any menu path, so injection is the only door.
   [`gametype-settings-map.md`](gametype-settings-map.md)
6. 🔓 **P1 — `test_frontend`, the first payload that runs IN THE PREGAME LOBBY.** klaze's #1 priority.
   "Nothing GSC runs there" is retracted from the dump (`frontend.gsc:46` sets the pregame state;
   eleven stock scripts guard on `is_frontend_map()`; `frontend.csc:2918` reads gametype settings
   from the lobby). Read-only first; then `maxplayers` written **before anyone is seated**. Band P
   below. [`pregame-routes.md`](pregame-routes.md)
   🪦 D10 (`acts dcfuncscw`) held this slot and **returned zero rows** — stale ACTS base. Not dead;
   blocked on runtime RE, and P3 in the same payload is the cheap way around it.

🪦 **Closed or superseded — do not run these looking for a goal.** L1 (no Max Players row) · L2 (moot,
L1 found no row) · A1 probes 6/12 (`maxsquadplayers` **0/0**, dead — but the *method* was validated:
6 and 12 agreed) · C6/C7/C8/C10/C11 (routes to a team-size goal now closed by `maxplayers`; C11 keeps
value only as a possible 5v5 route) · B4 (**passed** — `map_restart()` restarts from script and an
already-linked script re-runs).

Everything else is worth knowing but does not move a goal.

---

## L — THE LOBBY. No injection, no modded anything. ← **do these first**

The hosting workflow — create lobby, pick map/mode/rules, invite, teams, start — happens entirely
*before* the match, in a layer none of this project's code has ever reached.
[`lobby-settings.md`](lobby-settings.md) maps it, and found a rules-menu row that may hand over the
team-size goal for free.

### L0 · **Allow In-Game Team Change** — the cheapest path to 4v4 that exists ← **do this first**

klaze measured the pre-game team screen capping at **2** (Gunfight), **3** (3v3), **4** (CDL Pro S&D),
**unrestricted** (TDM) — plus **at most 2 CoD Casters** in any mode that supports them. That cap is a
*lobby* rule. `serversettings.gsc:42` turns on in-match team switching for **private matches** when
`allowingameteamchange` is set, and that setting **has a rules-menu row**.

🔓 **And `menuteam()` — the in-match picker at `globallogic_ui.gsc:331` — has NO cap check at all.**
Not 8, not 3: it gates on `level.allow_teamchange` + `hasdonecombat` and then simply **assigns** the
team. [`lobby-settings.md`](lobby-settings.md)

🪦 **The caster version of this test is DEAD.** klaze, 2026-09-09: **casters cannot open the normal
pause menu.** They have their own control scheme (`category_codcaster_keybinds_codcaster.json`). No
pause menu means no ChangeTeam, so a caster cannot reach `menuteam()` however permissive it is. Do not
plan around casters switching to teams.

✅ **The SPECTATOR version is alive, and it has never been tested — because the toggle has never been
on.** klaze also reports: *"a spectator can only fill their spot if they also leave the match then
rejoin rather than just choosing a team."*

⚠ **Read that carefully: it is not evidence the assignment is refused.** `menus.gsc:101` and `:179`
**both gate the ChangeTeam menu on `level.allow_teamchange`**, which is 0 unless the rules row is on
(`serversettings.gsc:42`). klaze has never turned it on. **So "a spectator can't just choose a team"
is fully explained by the menu not being there** — nobody has yet seen what happens when it is.

And a plain spectator is not a caster: they are an ordinary player with an ordinary pause menu, and
`menuteam()` has **no cap check** (`globallogic_ui.gsc:331`).

1. Rules menu → **Allow In-Game Team Change** → on
2. Fill teams 3 v 3. Start the match.
3. A 7th player joins → the session has no slot → **forced to spectate** (klaze's normal outcome)
4. **That spectator opens the pause menu and picks a team.**

| Outcome | Means |
|---|---|
| they join a full team | 🔓 **4v4 with ZERO code.** The single best outcome anywhere in this queue |
| the row is absent from Gunfight's rules | the bundle exists, this variant does not show it → C10 |
| the menu opens, no ChangeTeam entry | `level.allow_teamchange` did not take. Read `serversettings.gsc:42` again — it needs `sessionmodeisprivate()` |
| ChangeTeam opens but the team is greyed out | 🔓 the **LUI** enforces a cap the script does not. **Record exactly what it says** — that is an enforcement point nobody has located |

⚠ **This and C10 are complementary.** L0 asks whether an existing spectator can *choose* a team; C10
changes what happens when they *join*. Different doors into the same 8-client budget. L0 needs no
injection — **which is why it goes first.**
Result: `______`

### L1 · Is there a **Max Players** row in the Gunfight rules menu?
`scriptbundle/gamesettings/max_players.json` is a real menu row writing `maxPlayers`, publishing
**1–12**, with no per-gametype variant. Walk every rules page of a **Gunfight Custom Games** lobby and
look for it.

⚠ Phase 0 **T0.2** already walked those pages — **looking for the timer**. Nobody was looking for a
player count, so its silence is not a negative.
Result: 🪦 **NO. Walked 2026-09-08 — there is no Max Players row in the Gunfight rules menu.**

⚠ **This is a fact about the MENU, not about the setting.** `max_players.json` is a real bundle
publishing 1–12; the Gunfight variant simply does not show it, which is the same playlist-level
filtering that hides the round-timer row from 3v3 Gunfight while `timer_override` still holds 60s
there. Per [`../../.claude/CLAUDE.md`](../../.claude/CLAUDE.md): **a setting being absent from the menu
says nothing about what `setgametypesetting()` accepts.** `maxplayers` stays live as a write target —
it is `lobby_probe` probe `7xxxxx`.

**Worth one minute when convenient:** does a **TDM** custom lobby show the row? Present there and
absent here proves the filtering is per-variant rather than the row being dead everywhere, and that
directly feeds C6 (start in a 12-slot TDM lobby, switch the gametype in place).

### L2 · If it exists, set it to 12 and count the slots ← **the whole goal, with no code**
`com_maxclients` is fixed at lobby creation and read-only from script. A rules row that sets max
players *before* the match acts at exactly that layer.

| Slots | Means |
|---|---|
| **12** | **team size solved with no mod at all.** Most of band C stops mattering |
| still 8 | `maxPlayers` does not drive lobby size — it may only feed challenge logic |

Result: 🪦 **MOOT for Gunfight — L1 found no row to set.** Not attempted. Revisit only if the TDM
walk under L1 shows the row exists there, in which case this becomes a C6 question rather than an L
one.

---

### 🪦 L5 · `maxsquadplayers` — **DEAD, measured 2026-09-08. Read it before writing it, and that paid.**

**Probe 6 = 0 and probe 12 = 0, in BOTH a 3v3 and a normal Gunfight lobby.** Predicted 3 and 2.

✅ **The crack is VALIDATED, and the lead is dead — those are different results and both are real.**
Probe 6 (by the cracked name `maxsquadplayers`) and probe 12 (`level.var_704bcca1`, the variable the
hash actually feeds) **agree**, which is exactly the self-check A1 was built around. So
`tools/crack-hash.py` maps the name correctly against the running game, and every other conclusion
resting on the cracker stands. The setting is simply **0 — Gunfight does not use it.**

🪦 **The `challenges.gsc:113` model is falsified, by its own stated test.** A1 said *"any lobby where
`7 != 2 × 6` falsifies it."* Probe 7 = 6, probe 6 = 0, and 6 ≠ 0. Recorded as the falsification it is.

⚠ `maxsquadplayers` reading 0 is not inert — `function_582e5d7c()` (`team_assignment.gsc:69`) treats
`max_players == 0` as **no limit**. A 0 is "unset", not "capped at zero".

▶ **Superseded by `maxplayers` — see L6.** The original text of this entry is below for the record.

<details><summary>original L5 reasoning (kept — the prediction was wrong, the method was not)</summary>

C7 measured that a Gunfight round boundary **restores the team size to 3** in a 3v3 lobby — session
layer, not script (three script explanations ruled out; see C7). Separately, `maxsquadplayers`
(`globallogic.gsc:241` → `level.var_704bcca1`, cracked from `#"hash_3a4691a853585241"`) is
**predicted to read exactly 3 in that same lobby**, is `uint:6` (max 63), is present in
`custom_games.ddl`, has **no menu row** — and L1 has now confirmed by walking the menu that no
per-side row exists to contradict it.

▶ **The two numbers being the same 3 is the lead.** If the session restores team size *from* that
setting, then the round-boundary revert stops being the obstacle and becomes the lever: one
`setgametypesetting( #"maxsquadplayers", 4 )` and the boundary restores **4v4** instead of undoing it.

⚠ **Read before writing.** A1 probe `6xxxxx` (by cracked name) and probe `12xxxxx` (the variable the
hash actually feeds) must **agree**, and must read **3 in the 3v3 lobby and 2 in normal Gunfight**.
One lobby cannot tell "it is the cap" from "it happens to be 3". Disagreement between 6 and 12
invalidates the cracked name and everything resting on it.

⚠ **A write is a band-C action** — one per match, lobby return after. Do the read first; it is
read-only and `lobby_probe` is already built.
Result: read **0 / 0 — dead** · write **not attempted**

</details>

---

### 🔓🔓 L6 · `maxplayers` — **the team-size setting, measured. Replaces L5.**

**Probe 7 read `6` in a 3v3 Gunfight lobby and `4` in a normal one** — exactly the values A1
predicted, and exactly **2 × the per-side size**. Everything the project wanted from
`maxsquadplayers` is true of this instead:

| Property | Status |
|---|---|
| Tracks team size | ✅ **measured**, 6 ↔ 3v3 and 4 ↔ 2v2 |
| Is a gametype setting | ✅ `getgametypesetting( #"maxplayers" )` returned a value in both lobbies |
| Runtime-writable | ✅ `setgametypesetting()` — Gunfight already calls it on itself at `gunfight.gsc:104`/`:106` |
| Reachable from the menu | 🪦 **no** — L1 walked it. Script is the only way in |
| Name resolved | ✅ plain-named, no crack needed |

▶ **The write test: `setgametypesetting( #"maxplayers", 8 )`.** C7 measured that the round boundary
restores team size from the session layer. **If it restores from this setting, the boundary that has
been undoing 4v4 starts restoring it instead** — which is the whole team-size goal, for one line.

⚠ **This is a band-C write.** One per match, lobby return after. ⚠ And it needs **B8 mode 2 shipped
alongside it** — Gunfight spawns out of bounds past 3 a side, and a working 4v4 with broken spawns is
not a working 4v4.

#### ✅ RUN 1 — 2026-09-08, write only, no bots. **The write lands AND survives the boundary.**

| Probe | Read | Means |
|---|---|---|
| `4xxxxx` read-back after the write | **`400008`** | ✅ `setgametypesetting( #"maxplayers", 8 )` is **accepted** — not refused, not clamped back to 6 |
| `3xxxxx` on **round 2**, before any write | **`300008`** | ✅ **survives the round boundary.** The session restored the round with the setting still at 8, rather than putting it back to 6 |

▶ **What this establishes:** `maxplayers` is writable at runtime, and the round boundary — the thing
C7 measured undoing 4v4 — **does not revert it**. That makes it the first thing this project has found
that is both upstream of team size and reachable from script.

⚠ **What it does NOT yet establish, and the distinction is the whole test:** that the session restores
*team size* **from** this setting. C7's revert moved **actual bots off a team**. Run 1 only shows the
*number* persists — nobody was on a team to be reverted. A setting can persist and be ignored.

#### ▶ RUN 2 — `fill_bots = 1`. Injected 2026-09-08, awaiting result.

⚠ **Fills on ROUND 1 ONLY** — filling every round would re-add the bots the boundary had just removed,
and probe 6 could no longer distinguish "they persisted" from "they were put back". Round 1 fills,
rounds 2+ only observe.

| Probe 6 on **round 2** | Means |
|---|---|
| **`600404`** | 🔓🔓 **4v4 survived the boundary. The team-size goal is one `setgametypesetting` call** |
| `600303` | reverted exactly as C7 measured — `maxplayers` persists but is **not** what the session restores team size from. Record it and move to C10/C11 |

#### ✅✅ RUN 2 — 2026-09-08. **`600404`. 4v4 SURVIVED THE ROUND BOUNDARY.**

klaze: *"600404 — it let the round play with 4v4 working!"*

▶ **The team-size goal is CLOSED.** The session restores team size from `maxplayers`, so the round
boundary that had been undoing every earlier 4v4 now restores it. One `setgametypesetting` call.

Shipped as `team_size_override` / `team_size` in `src/gunfight_mod/`, clamped at runtime against
`com_maxclients` rather than a hardcoded ceiling — the same mistake that had `com_maxclients == 8`
recorded as a law for most of this project's life.

🔓 **This may also have retired B8.** klaze characterised the spawn bug as *"it spawns people out of
bounds **when the team size is exceeded**"*. With `maxplayers` at 8, a 4v4 no longer exceeds the
configured size, so **the precondition is gone** — a cleaner fix than mode 2, and consistent with run
2 playing cleanly. ⚠ Bots may tolerate a spawn a human would notice. **Keep mode 2 built**, and check
spawns explicitly in the first human 4v4.

⚠ **Still open: a human 4v4.** Unlike C10 this is not a bot-only code path — `maxplayers` is read by
the session's own restore, not by anything gated on `isbot` — but that is a reason to expect it to
transfer, not a measurement that it does.

#### ▶ TOMORROW — the human 4v4. What to actually check, in order.

Everything below is unverified with people. ⚠ **`gunfight_mod` does NOT add bots** — it only raises the
cap. An empty lobby staying empty is correct and is not evidence about anything.

1. **Do 4 players fit on one side?** The cap is `maxplayers = 8`; nothing has yet tried to occupy the
   4th slot with a human. ⬅ **the actual open question**
2. **Where does the 4th spawn?** [B8](#b8). The prediction is that it is FINE — klaze characterised the
   bug as out-of-bounds *"when the team size is exceeded"*, and at `maxplayers = 8` a 4v4 no longer
   exceeds the configured size, so the precondition is gone. ⚠ Bots played it cleanly, but bots
   tolerate a spawn a player would notice. **If spawns are bad, `src/test_spawnmode/` mode 2 is built
   and waiting** — do not re-derive it.
3. **Does the 4th survive the round boundary?** Verified for bots (`600404`). Humans hold real session
   slots where mid-match bots do not, so this should be *easier*, not harder.
4. **Lobby return**, as after every write.

⚠ **If a 4th cannot join at all**, that is a session-layer refusal and the route is C10/C11 — both
built, both needing exactly this group.

#### ✅ Hosting stack, end to end — 2026-09-08

Menu injected → carried → `gunfight_mod` injected → **60-second rounds present on the carried map.**
Confirms the mod links after a carry and `timer_override` survives it, for the third time. ⚠ Confirms
**nothing** about team size: the lobby was solo.

⚠ **5v5 is now the untried edge, not an impossibility.** `com_maxclients` is 10 in a 3v3 lobby, so ten
players fit exactly with zero casters. `#team_size: 5` is one number, and `clamp_team_size()` will
refuse it in an 8-slot lobby rather than ask for what the session cannot hold.

Result: run 1 **`400008` / `300008` — PASS** · run 2 **`600404` — PASS. GOAL CLOSED.**

---

### 🔓🔓 L7 · `com_maxclients` is **NOT 8, and NOT fixed.** ← rewrites the project's team-size model

**Probe 1 read `10` in a 3v3 Gunfight lobby and `8` in a normal Gunfight lobby.**

The project has asserted `com_maxclients == 8` since the beginning, and built its entire team-size
model on it — including *"8 clients is the budget, 4v4 is the ceiling, 5v5 needs ten and is
unreachable."* **That was one reading, taken in one lobby type, and generalised.** It is wrong: the
dvar tracks the playlist.

| Lobby | `maxplayers` (7) | `com_maxclients` (1) | players + casters |
|---|---|---|---|
| normal Gunfight | 4 | **8** | 4 + 2 = 6, **2 spare** |
| 3v3 Gunfight | 6 | **10** | 6 + 2 = 8, **2 spare** |

⚠ **Two relationships, both n = 2 — patterns, not laws.** `maxplayers = 2 × per-side`, and
`com_maxclients = maxplayers + 4`. A third lobby (CDL Pro S&D at 4 a side, or TDM) tests both for
free, and is worth taking the next time one is open.

**What this changes:**
- **4v4 fits a 3v3 lobby with room to spare** — 8 players inside 10 slots, 2 left for casters. It is
  no longer "exactly at the ceiling", which is consistent with C7 reaching 4v4 live.
- 🔓 **5v5 is no longer ruled out.** Ten players is exactly `com_maxclients` in a 3v3 lobby, with zero
  casters. That is tight, not impossible — and it was previously recorded as impossible.
- ⚠ **The read-only claim still stands and is unaffected.** 7 refs, all `getdvarint`, zero `setdvar`.
  Script still cannot write it. What changed is the **value**, not the access.
- ⚠ **klaze's caster model is not refuted, it is incomplete.** "At most 2 casters" was measured
  directly. The 2 spare slots beyond players+casters are unexplained and worth a probe.

Result: **3v3 = 10 · 2v2 = 8** · third lobby: `______`

#### 🪦🪦 L7b — **RETRACTED 2026-09-09 by test L8. The budget does NOT follow `maxplayers`.**

**L8, standard Gunfight lobby, read by screen capture rather than transcription:**

| Round | Probe | Read | Meaning |
|---|---|---|---|
| 1 | `4` `maxplayers` after write | **`400010`** | the write **lands** — not refused, not clamped |
| 2 | `2` `maxplayers` before write | **`200010`** | it **survives the round boundary** |
| 2 | `3` `com_maxclients` before | **`300008`** | 🪦 **unchanged.** Input +6, output **0** |

▶ **So `maxplayers` is writable, sticky, and the client budget ignores it.**

⚠ **The error was the inference, not the reading.** L7b rested on ONE before/after pair taken in
**different sessions** and called it causal. A single pair cannot separate "our write moved it" from
"the session was different" — which is exactly the trap A1's dual-lobby rule exists to avoid, and it
was not applied here. The earlier `12` is **unexplained**; record it as an anomaly, never as evidence.

▶ **Consequences:** 5v5 and 6v6 are **undemonstrated again**. ✅ **4v4 is untouched** — L6 verified it
with bots inside a budget of 8, independently of any of this.

<details><summary>the retracted L7b reasoning, kept because the retraction is the lesson</summary>

#### 🔓🔓🔓 L7b · **`com_maxclients` FOLLOWED our `maxplayers` write. Measured 2026-09-08.**

| When | Lobby | `maxplayers` | `com_maxclients` |
|---|---|---|---|
| baseline, earlier the same day | standard Gunfight (2v2) | 4 | **8** |
| after `gunfight_mod` wrote `maxplayers = 8` | **standard Gunfight (2v2)** | 8 (written) | **12** |

**Same lobby type. Same session. The input changed by 4 and the output changed by 4.**

▶ **This is causal, not another correlation.** The two earlier readings (2v2 → 8, 3v3 → 10) were
different lobbies and could only ever support a pattern. This one holds the lobby fixed and moves the
variable, which is the difference between "these numbers co-vary" and "this one sets that one".

▶ **So `com_maxclients` is REACHABLE FROM SCRIPT — indirectly, through `maxplayers`.** The dvar itself
is still read-only (7 refs, all `getdvarint`, zero `setdvar`) and that was never wrong. What was wrong
is the conclusion drawn from it: that the client budget could not be moved. It can — from upstream.

▶ **4v4 is not the ceiling.** Twelve clients is **6v6** with no casters, or 5v5 with two. 6v6 was
recorded in `.claude/CLAUDE.md` as *"not script-fixable"*.

⚠ **CONFIRM BEFORE BUILDING ON IT — one `lobby_probe` run, read probes 7 and 1 together.** The `12`
was read by `test_mapswitch`, which reads `com_maxclients` and **not** `maxplayers`, so "`maxplayers`
is still 8 right now" is inferred from what we wrote rather than observed. Expect **7 = 8, 1 = 12**.
Anything else and this entry is wrong.

⚠ **Then test whether it RATCHETS, carefully.** `#team_size: 6` → `maxplayers = 12` → does
`com_maxclients` go to **16**, or does something clamp? `clamp_team_size()` bounds the request at
`com_maxclients / 2`, so as the budget grows the clamp loosens — **that is a feedback loop**, and it
is worth knowing whether it terminates. Raise `team_size` **one step at a time** and read both probes
after each. Do not jump to 6.

⚠ **Unknown: whether the raised budget is real.** A larger `com_maxclients` means the *script* thinks
there is room. Whether the session will actually seat a 9th–12th client is a separate question, and
the answer that matters is C7/C10 with bodies in the slots — not the dvar.

</details>

---

### 🔧 Reading probes: `tools/capture-probes.ps1` — stop transcribing numbers

Added 2026-09-09 after klaze said, correctly, *"i'm tired of doing this number stuff."* Every probe in
this project printed via `iprintlnbold` and was read off the screen and typed out by hand, for hours.
GDI capture of the game window works, so **the agent reads its own probes now.**

```powershell
pwsh tools/capture-probes.ps1 -Seconds 240 -Every 3    # start BEFORE restarting the match
```

⚠ **Start it before the restart.** Probes begin ~10s into the round, 5s apart, and are gone in under a
minute. A capture started afterwards catches nothing — that happened on the first attempt.

⚠ **`SetProcessDPIAware()` is load-bearing.** Without it, window coords come back in logical pixels
while capture works in physical ones, and on a scaled display the grab is offset. Measured: it started
~390px left of the game and pulled **the terminal** into frame — which was displaying this project's
own *predicted* probe values. A capture tool that can photograph its own expectations and hand them
back as data is worse than no tool.

⚠ **Frame-scoring by white-pixel count does NOT work** — bright map geometry (skylights, marble)
swamps the glyphs at any threshold tried. Read frames directly; probe N lands roughly at frame
`(10 + 5N) / interval`.

🔧 **`tools/send-key.ps1` sends F4/F6/F7 via `SendInput` with SCAN CODES** (games read raw input;
`SendKeys` and `PostMessage` are ignored). It focuses the window first, since input goes to the
foreground window and would otherwise land in the terminal. ⚠ **Whether cwpatch's hook honours
injected input is UNCONFIRMED** — a test on 2026-09-09 sent F7 with both events accepted, but the
observed screen showed a normal round-win, so nothing distinguished "F7 worked" from "the round ended
on its own". Retest deliberately, mid-round.

### L3 · Bot Autofill / Bot Difficulty rows
`bot_autofill_allies` and `bot_autofill_axis` are real bundles. If those rows exist, filling a test
lobby needs **no injection** — strictly better than `bot::add_bot()` for C7/C8. Result: `______`

### L4 · With Max Players at 12, start the match and read `lobby_probe` `1xxxxx`
The only one here that needs injection. Confirms whether `com_maxclients` followed the menu setting.
Result: `______`

---

### D10 · `acts dcfuncscw` — dump the game's console command list ← **gates the lobby-map DLL**
[`lobby-map-dll.md`](lobby-map-dll.md)

klaze wants an auto-loading DLL that picks the Gunfight map from the pregame lobby. **The machinery
already exists** — cwpatch runs arbitrary console commands from the one DLL slot that loads, and
`map %s\n` is in the blob it writes to. **The only open question is which command**, and nobody has
ever looked at the list.

```powershell
acts dcfuncscw                                  # game RUNNING, in a Gunfight pregame lobby
python3 tools\crack-cmds.py cfuncs_cw.csv
```

⚠ **Read the control line before anything else.** The tool checks five commands known real from
cwpatch. **Zero resolving means the hash form or the CSV column is wrong and the rest is noise.**

| Outcome | Means |
|---|---|
| a command that sets the lobby map | 🔓 **the DLL is one command in the shim.** Every step already proven by cwpatch |
| only `map <name>` | bind it. ⚠ Untested whether `map` from a lobby keeps the Gunfight gametype |
| nothing map-shaped | the wordlist was wrong first, the command layer second. Add guesses with `--words=` before concluding anything |
| `dcfuncscw` errors or dumps garbage | its `cmd_function_t` base is hardcoded (`poolt9.cpp:607`) and may be stale for this build. That is a fact about ACTS, not about the game |

⚠ Read-only, but it **attaches to the live process** — less exposure than the injector already in use,
not zero.

🪦 **Result 2026-09-08: `dcfuncscw` produced a HEADER AND NOTHING ELSE.** 18 bytes,
`location,name,func`, zero rows. ACTS found the process fine (`pid=33852`) and reported `done`.

That is the fourth row of the table above, called in advance: **ACTS's `cmd_function_t` base is
hardcoded (`poolt9.cpp:607`) and is stale for this build.** A fact about ACTS, not about the game —
the command table certainly exists, ACTS just cannot find it.

▶ **`crack-cmds.py` never ran** — there was nothing to feed it. Its control-line gate (five known-real
commands must resolve) was never reached, so it remains unvalidated rather than failed.

⚠ **Untried — not ruled out:** locating `cmd_function_t` for this build by hand and passing it in, or
patching ACTS. Both are real reverse-engineering work against an exe that is encrypted at rest, so it
must be done at runtime. **Not worth it for automation** — `adddebugcommand()` from script (band P,
P3) is cheaper and does not depend on ACTS internals at all; if it is alive in CW, the command list is
tried one name at a time from the payload instead of read out of memory.

### D11 · `dumpbin /exports acts-bocw.dll | findstr /i lobby` — 30 seconds, no game
`acts cwdllgt` calls `ACTS_EXPORT_SetLobbyGameType` / `ACTS_EXPORT_SetLobbyMap`. **Neither exists in
ACTS master** — one export in the whole DLL. But the project pins **v3.3.0**, a release binary.
Nothing back → drop the powrprof track entirely rather than trying to fix its crash.

🪦 **Result 2026-09-08: NOTHING BACK. Drop the powrprof track.** Scanned v3.3.0's shipped
`acts-bocw.dll` (1,091,584 B) for `ACTS_EXPORT_*` and for any `*lobby*` identifier: **zero matches of
either.** ✅ **The method was controlled** — the same scan finds `CallNtPowerInformation`, the one
export the DLL is documented to have, so an empty result means absent rather than unscannable.

▶ **`acts cwdllgt` is dead for the third and final time**, and now for the simplest possible reason:
the functions it calls **are not in the binary**, in the pinned release any more than in master. The
startup crash was never the real problem. **Do not spend more on the powrprof proxy.**

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
| `7xxxxx` **`maxplayers`** | `uint:4` (max 15) in `custom_games.ddl`, `uint:7` (max 127) in `mp_custom_game.ddl`. 🔓 **`challenges.gsc:113` computes `maxplayers / maxsquadplayers` as a TEAM COUNT** — so read together with probe 6 this tests a model, not a number. **Predicted (6,7) by lobby: Gunfight (2,4) · 3v3 (3,6) · CDL S&D (4,8) · TDM (6,12).** Any lobby where `7 != 2 × 6` falsifies it, which is worth as much as a confirmation | `______` |
| `8xxxxx` **`gunfightloadoutindex`** | **NEW, cracked this pass.** Selects the loadout set: **0** default · **1 snipers** · **2** blueprints · **3 melee**. Expect `0`. ⚠ A reading of `99999` means the cracked name is wrong — the value is definitely being read by `gunfight.gsc:83` | `______` |
| `10xxxxx` `level.var_7d3ed2bf` | **the party-fill flag — CAN BREAK ROUTE A.** When on, one non-`fill` party counts as 8 on a team and nobody else can join it. Expect `0` or `99999`; a `1` is the thing to know | `______` |
| `11xxxxx` `level.var_9ff21849` | placement-scoring flag. Expect `0` in Gunfight | `______` |
| `12xxxxx` `level.var_704bcca1` | ✅ **the crack self-check. Must EQUAL probe 6.** Probe 6 asks by the cracked name `maxsquadplayers`; this reads the variable the hash actually feeds. Agreement validates `tools/crack-hash.py` against the running game. **Disagreement invalidates every conclusion resting on that name** | `______` |
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
submenu may be too.

#### ✅ ANSWERED 2026-09-08 — **37 registered, 19 visible. It is the SECOND row, and the walk
undercounts.**

klaze counted **19** on screen. But the shipped `.gscc` was **decompiled** (`acts gscd`) and it
registers **all 37 MP maps unconditionally**, inside a single `if ( function_7813976a() )` —
`is_multiplayer()` — with **no per-map filter anywhere in the block**:

```gsc
self function_d7ae9d08( "map", "mp_amerika",     &function_7856adb2, "mp_amerika" );
...  36 more, one line each, no conditions ...
self function_d7ae9d08( "map", "mp_zoo_rm",      &function_7856adb2, "mp_zoo_rm" );
```

▶ So the shipped binary is **not** older than master in this respect, and the 19 is a **display/paging
artifact**. The full list is at [`../reference/atian-menu-maps.txt`](../reference/atian-menu-maps.txt).

🪦 **AND THIS KILLS THE "USE THE MENU LIST AS A WHITELIST" PLAN, which was written an hour earlier.**
`mp_hijacked_rm` is in the menu at line 2478, wired to the same `func_set_map`. **Carrying to Hijacked
through the menu would break the session identically** — it is the same three calls. The hazard is not
something the automation introduced; it is pre-existing in the menu workflow, and klaze simply never
picked that entry.

▶ **There is therefore NO source of a safe-map list except empirical confirmation.** Not the dump
(38 names, script presence only), not `mapexists()` (returns true for everything, B5), not the menu
(37 names, includes the one that breaks). **A map is safe when it has been loaded successfully, and
not before.**

⚠ **Name discrepancy worth chasing:** the menu registers **`mp_clhanger`**; the dump has
**`mp_cliffhanger`** (`scripts/mp/mp_cliffhanger.gsc`). One is wrong. If it is the menu's, that entry
is broken in the shipped build and is a second landmine of the same kind as Hijacked.

🔓 **Technique worth reusing: `acts gscd` decompiles the shipped menu payload.** That is how this was
answered in seconds without a menu walk, and it applies to any question about what the shipped build
actually contains — a far better source than counting rows on screen.

```bash
acts gscd payloads/BlackOpsColdWar_atianmenu_pc.gscc -g cw -p pc -o menu-decomp
```

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

#### 🪦 RESULT 2026-09-08 — **`mapexists()` RETURNS TRUE FOR EVERYTHING. Useless.**

Run as `src/test_mapexists/` over all 38 names from the dump's `scripts/mp/`.

| Probe | Read | Meaning |
|---|---|---|
| `9xxxxx` **control** | **`900003`** | 🪦 true for the live map **and** for `"zzz_not_a_map"` |
| `1xxxxx` group A (15) | `132767` | 32767 — **all 15 bits set** |
| `2xxxxx` group B (15) | `232767` | 32767 — **all 15 bits set** |
| `3xxxxx` group C (6) | `300063` | 63 — **all 6 bits set** |

▶ **The payload is discarded, not interpreted.** On its own it reads as a clean "all 38 maps are
loadable" finding. It is not a finding; it is a builtin that cannot say no.

✅ **THE CONTROL IS WHAT CAUGHT IT.** Without probe 9 this would have entered the notes as a real map
list and been trusted. That is the `jump_height` lesson from [`mp-dvars.md`](mp-dvars.md) firing
exactly as intended, and the same discipline `crack-cmds.py` enforces by refusing to report when its
five known-real controls fail. **Keep putting controls in probes.**

⚠ **This kills A4's guard 4, which was written the same day.** `mapexists()` would have returned 1 for
`mp_hijacked_rm` and passed the switch that broke the session. The guard is **deleted** rather than
kept with a caveat — a guard that always passes manufactures confidence, and a warning in a comment
does not stop the next reader trusting the code.

⚠ **Untried — not ruled out.** As called, with a plain string, it is useless. Whether some *other*
argument form (a hashed name, a different builtin) answers honestly is unknown; `mapexists` is 1-arg
at `+3b0b2d0` and a string is the obvious form. Also unknown whether it is genuinely a stub or is
answering about something other than installed content.

▶ **What this leaves:** there is currently **no way to ask whether a map will load without loading
it**, and loading it is the destructive act. So A4's only safe targets are maps confirmed by having
actually carried to them through the Atian Menu — which promotes **A2** (capture the menu's shipped
19-map list) from a curiosity to a **prerequisite** for the automation route.

### B1 · `switchmap_load( map, gametype )` — switch map the way STOCK does ← **Goal B**
`src/test_sessionswitch/` · [`roadmap.md`](roadmap.md) Goal B

After a carry, *"everywhere the map is written still says the last map — menu, scoreboard, friend
list, activity, everything"* (klaze). The carry calls `map( name )`: **one argument, zero stock callers
anywhere in the dump.** Campaign transitions, side-mission launches and Zombies all switch with
`switchmap_load( map, gametype )`, and campaign tells the UI first via
`lobby_root.transitionMapIdOverride`. This test calls what they call.

🔓 **The criterion is presence — friend list / activity — and it is clean.** No GSC builtin writes
presence (the engine table's only presence-shaped entry is `resetinactivitytimer`), so it can only
change when the engine's own session record does. Observable from any friend's screen.

1. `read_only = 1` → inject, restart. Read **`40xxxxx`**: **`99999` means the UI-model chain is wrong**
   (it is inferred from stock's `getglobaluimodel()` pattern, not read) and `tell_ui` cannot work.
   Anything else = the model exists. `42xxxxx` = 1.
2. `read_only = 0`, `target` = a map **already carried to** (`mapexists()` returns 1 for everything —
   B5 — and is not a guard; an unloadable map hung the game once in A4). Inject, restart.
3. **Read `41xxxxx` first.** `99999` = `#"switchmap_preload_finished"` never signalled in 25s and the
   load never started — presence proves nothing then. A number = seconds ×10 until it signalled.
4. Then check **scoreboard · pause menu · AAR · a friend's view of your activity**. Write down which
   say the NEW map and which the OLD.
5. Two runs if there is time: `tell_ui: 1` and `tell_ui: 0`. One run with both cannot say which
   mattered.
6. ⚠ **Test a lobby return.**

| Reading | Means |
|---|---|
| in-match UI **and** presence show the new map | 🔓 **Goal B closed.** The carry used the wrong builtin all along. Replace `map()` in `gunfight_mod` and the menu |
| in-match UI new, **presence old** | reached the match, not the session. Better than the carry, not the glitch. D10 next |
| `41` = `99999` | the load never began — wrong gametype string, or the thread died. Check for an `endon` before anything else |
| `42` = 3 | refused: already on the target. Change `target` |

⚠ The sequence runs in a thread with **no `level endon( #"game_ended" )`** — A4 found `map()` fires that
notify mid-sequence and the endon killed the thread inside the wait.
Result — run 1 (`read_only`): `______` · run 2 (`tell_ui: 1`): `______` · run 3 (`tell_ui: 0`): `______`

### B6 · `gunfightloadoutindex` — **snipers-only and melee-only Gunfight**
[`gametype-settings-map.md`](gametype-settings-map.md)

`#"hash_3b05ecbff72f1065"` cracked to **`gunfightloadoutindex`**, and
`scriptbundle/gunfightloadoutlist` holds four sets: `default` · **`snipers`** · `blueprints` ·
**`melee`**. There is **no menu row**, so `setgametypesetting()` is the only way to reach them.

```gsc
setgametypesetting( #"gunfightloadoutindex", 1 );   // snipers
game.var_96a8ff4a = undefined;                       // clear the latch, see below
```

⚠ **Timing is the whole test.** `gunfight.gsc:81` wraps the loadout pick in
`if ( !isdefined( game.var_96a8ff4a ) )`, and `game.` scope survives the round. Our hook runs at
`globallogic.gsc:5536`, *before* `onstartgametype` at `:5537`, so the **first** match of a lobby
should take the setting on its own. A **second** match in the same lobby needs the latch cleared too
— which is why the line above is there and why this needs two matches to answer properly.

| Outcome | Means |
|---|---|
| match 1 is snipers-only | the setting lands, and Gunfight gets a weapon-set selector for one line |
| match 1 default, match 2 snipers | the hook runs too late; move the write earlier |
| neither | the cracked name is wrong, or the bundle index is not what `:83` reads |

⚠ Lower risk than anything else in B — it writes a gametype setting, which
`gunfight.gsc:104` already does to itself. Reverts by not injecting.
Match 1: `______` · Match 2: `______`

### B7 · `gunfightspyplane` value 3 — the menu row hides one of its four values
`scriptbundle/gamesettings/gunfight_spy_plane.json` declares `value1..value4` (0/1/2/3) but sets
`"optionscount": 3`, so **`3` = `menu/shared` never appears in the lobby.** `gunfight.gsc:48` reads
the setting into `level.gunfightspyplane` regardless.

```gsc
setgametypesetting( #"gunfightspyplane", 3 );
```

Same shape as `time_limit_seconds` publishing 6 of the 20 values it declares — and the same reason to
expect it to work. Result: `______`

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
🔓 **Upgraded 2026-09-09, and it now unblocks solo testing.** klaze: Gunfight on **Nuketown** lets the
host add bots (to the same 3-per-side cap); **no other Gunfight map does, stock.** But
`scripts/mp/mp_nuketown6.gsc` contains **zero** bot or Gunfight references — the permission is
playlist/LUI, not script — and `bot::add_bot()` (`bot.gsc:98`) has **no map gate and no cap check**,
while `function_582e5d7c()` bounds bots at `com_maxclients`, not 3. **Predict: this works on any
Gunfight map and fills past 3 per side.** If it does, C8 and C10 no longer need four friends.
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

#### ✅ RUN 1 — 2026-09-08. Both predictions confirmed; numeric ceiling NOT yet clean.

klaze, solo start, a **non-Nuketown** Gunfight map: *"i started round 1 with just me, then bots started
pooring in, at one point it was 4v4!"*

- ✅ **`bot::add_bot()` has no map gate.** The Nuketown-only bot restriction is playlist/LUI, exactly as
  predicted. Bots fill on any Gunfight map.
- ✅ **The 3-per-side cap is not enforced in-match.** **4v4 was observed live.** This also lands C8's
  headline early — a team held four, so the eight clients of the existing lobby *are* 4v4.
- ⚠ **The numbers are NOT a ceiling reading.** `run()` had no once-guard and no `endon`, and
  `on_start_gametype` fires **per round**, so rounds 2+ threaded additional concurrent copies. They
  break each other's exit condition (A's add raises the count, B resets its own `stalled`), so every
  thread ran to `maxtries = 20`. **Fixed** — `game.var_c7_done` guard + `level endon( #"game_ended" )`.
  Re-run needs a **NEW LOBBY**, not a new round (`game.` scope survives rounds).

#### ⚠ RUN 1's REAL FINDING — the revert is at the ROUND BOUNDARY, and it is above script

klaze: *"at the start of every round, it removes the extra bots and reverts to 3v3, or it glitches and
turns into 2v4."*

**Three script-side explanations are ruled out, by grep:**

1. **No retail script path drops a bot.** The only `remove_bot` call sites in MP are
   `team_assignment.gsc:1102` and two in `bot_devgui.gsc` — **all inside `Type: dev` functions**,
   stripped from retail. `bot.gsc:192` `botdropclient()` is the sole definition and has no live caller.
2. **The NOTSPAWNED kick cannot fire.** `globallogic_spawn.gsc:1021`
   `kick( …, "EXE/PLAYERKICKED_NOTSPAWNED" )` sits below `if ( sessionmodeisprivate() ) return;`.
3. **Re-assignment cannot evict.** Our bots are `botteam = "autoassign"`, so `function_582e5d7c()`
   (`:66`) is false and `:435` does not return early. They fall to `function_bec6e9a()` (`:339`) →
   `function_650d105d()` — count the teams, pick the smaller — **no cap, no eviction**.

▶ **So the round-boundary revert is session/playlist-layer, not script.** ⚠ And note *what* it reverts
to: **3v3, the playlist's team size — NOT `com_maxclients`'s 8.** That is the same playlist layer that
fixes `com_maxclients` at lobby creation and that the map carry rides underneath.

⚠ **Do NOT read this as "4v4 cannot persist."** It is measured for **bots**, and bots are the weakest
possible proxy here: a bot added mid-match by `addtestclient` holds no lobby/session slot, so a session
that re-derives its client list at a round boundary has nothing to restore it from. A **human** who
joined the session holds a real slot. Whether a human 4th survives the round boundary is **untested and
not ruled out** — it is precisely what C10/C11 ask.

#### 🪦 C7 does NOT unblock C10. Corrected 2026-09-08.

This entry previously read *"if it does, C8 and C10 no longer need four friends."* **Half wrong.**
`function_a3e209ba` (`team_assignment.gsc:634`) contains `if ( isbot( self ) ) return false;` — a bot
exits the nine-AND spectator rule **before** the branch C10 overrides. **A bot can never exercise
C10's code path**, whichever lever is set.

- **C8 — still fine with bots.** It fills a named team and reads where it lands. No spectator path.
- **C10 / C11 — still need humans.** No substitute exists.

⚠ Bots may not leave cleanly. `kick` (1–2 args, `+3b0a3a0`) is the only obvious undo; A0 reports its
call sites. **Also the mechanism Phase 3's "bots before humans" always assumed and never had** — if
this works, every later test gets cheaper.

### C8 · the PER-TEAM ceiling — can four stand on one team?
`src/test_teamfill/` · [`dump-cross-check.md`](dump-cross-check.md)

⚠ **This replaces the earlier `test_setteam`, which was built on a wrong premise.** `setteam` has 55
stock call sites and every one sets the team of a *world object*. The player path is
`teams::change()`. The grep caught it before a match was spent on it.

**The dump says the 3-per-team limit is not enforced by team assignment.**
`function_d36b6597()` returns `com_maxclients` for a two-team mode, and `team_assignment.gsc:95`
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

### C10 · late joiners land on a TEAM ← **the strongest team-size route** 
`src/test_latejoin/` · [`lobby-settings.md`](lobby-settings.md)

klaze's measured caster model: a pregame lobby assigns players to a team **or** as a CoD Caster, and
**at most 2 casters**. 3v3 Gunfight = 3 + 3 + 2 = **8** = `com_maxclients`. That is what the 8 has
always been — a **total client budget** that casters spend from.

The mod removes **one condition** from `function_a3e209ba` (`team_assignment.gsc:600–656`), the
nine-AND rule that sends a mid-match joiner to spectator. They then fall into `function_650d105d()`,
which **counts the teams and picks the smaller one, with no cap check of any kind**.

1. Inject with `predicate: 1`, `forceautoassign: 0` (**lever 2 — surgical, try first**)
2. Host 3v3 Gunfight private. Fill both teams: **3 v 3**
3. Two extra players in the pregame lobby **leave** — klaze's normal workaround
4. **Start the match**
5. Those two **rejoin** while it is running
6. Read probe `20xxxxx` = `allies*100 + axis`. `2000404` is **4v4**

| Reading | Means |
|---|---|
| `2000404` | 🔓 **4v4, and the team-size goal is reached with one line** |
| `2000303` after both rejoin | lever 2 did not fire — flip to `forceautoassign: 1`, run again |
| they cannot rejoin at all | a **session-layer** refusal, nothing to do with this script. Record it: it says the 8-client budget was already spent, which is itself a measurement |

✅ **The mechanism has a stock precedent, so this is not a hope.** The joiner ends up at
`teams::function_dc7eaabd( assignment )`, which sets three script fields —
`self.pers[#"team"]`, `self.team`, `self.sessionteam` — and calls **nothing the engine can refuse**.
`infect.gsc:1345` and `infection.gsc:249` use that exact call to flip a player onto the infected team
*after the match has started*, every game. Moving a player onto a team mid-match is something stock
does routinely.

⚠ **What the session decides, it decides ONCE.** `getassignedteamname()` (engine builtin, the real
cap) is read at `player_connect.gsc:269` and only when the player has no team yet. It is not a running
authority — which is why overriding the script's obedience to it is enough.

⚠ **One lever per match.** Both on and a good result tells you nothing about which one did it.

⚠ **Lever 1 has a second consumer.** `globallogic_ui.gsc:194` — with `forceautoassign` on, a player who
*deliberately* picks spectator skips the spectator setup. That may break casters, which is how the 7th
and 8th bodies get in. Hence lever 2 first.

⚠ **This reaches 4v4, not 5v5.** Eight clients, zero casters. 5v5 needs ten and `com_maxclients` is
untouched by this. Do not record it as solving the goal outright.

⚠ **Test a lobby return afterwards.**
Lever 2: `______` · Lever 1: `______`

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

---

### A4 · script-driven map carry — **diagnosed, fix NOT yet run**
`src/test_mapswitch/` · [`menu-map.md`](menu-map.md)

If this works the map workflow drops the Atian Menu entirely — `gunfight_mod` carries the map itself.

**The diagnosis, from decompiling the shipped menu payload:** its handler is

```gsc
self function_9441a07f( "loading " + name );   // cosmetic text draw, no state setup
map( name );
wait 1;
function_f4472a8();                             // switchmap_switch, engine builtin
```

**Identical to our sequence.** Both `map()` and `function_f4472a8` are called *unqualified*, so they
are global builtins — which also weakened the self-binding theory run 4 was built on.

🔓 **The wrapper was the difference, not the sequence.** Runs 1–3 had the calls inline inside `run()`,
which carries `level endon( #"game_ended" )`. `map()` starts the map transition → the engine notifies
`game_ended` → **the endon kills the thread during `wait(1)`** → `switchmap_switch()` never runs. The
load was staged and never committed.

▶ **The fix is to call the sequence from a thread that does NOT carry that endon.** Untested.

⚠ Only target maps confirmed present. `mapexists()` returns **1 for everything** (B5), so it is not a
guard — loading a bad map is the destructive act, and A4 has already hung the game once that way.
Result: `______`

### B9 · does injecting under a live script link the new build? 🪦 **NO — re-run to confirm**
`src/test_relink/`

The version-stamp test. v1 injected, linked by one F7, ran, emitted `200001` (guard passed, restart
firing). v2 — byte-identical except `version = 2` — injected during v1's 5s pre-restart window. The
restart landed and produced a new round. **Then nothing emitted.** Neither `100001` nor `100002`,
across frames spanning the whole round.

That is the opposite of B4, where the same payload re-ran cleanly after its own `map_restart` and
emitted `400001`. The single difference is that a new payload was injected over the buffer while the
old one was live.

▶ **Consequence: inject → self-restart → linked does NOT work, and unattended operation is not
closed.** The resident-payload plan sketched after B4 rests on exactly the behaviour this falsified.

⚠ **Its own caveat, and the reason it is still in this queue:** frames were **sampled, not
exhaustively read** — four, spanning the round. Probe cadence is 5s and displays persist ~5s at a 3s
capture interval, so a miss is unlikely but not impossible. **Re-run with the guard dvar cleared.**
This one result is what closes off unattended operation; it is worth one clean run.
Result: `______`

---

## M — THE MENU. `src/gunfight_menu/` — compile first, then a read-only walk

**One payload carries everything** — B9 measured that nothing can be injected on top of a live one —
so this replaces *both* `inject.sh mod` and the Atian Menu in the hosting workflow. `gunfight_mod`
stays as the no-menu variant.

### M1 · Compile gate
```powershell
.\tools\check-gsc.ps1 .\src\gunfight_menu\scripts\gunfight_menu.gsc -CompileOnly
```
963 lines, ACTS dialect, no preprocessor. ⚠ **The engine is a rewrite of the Atian Menu's, not a copy**
— the original is `#include` / bare-`autoexec` / `#ifdef` under `debugcompiler`, the dialect that
crashed at script link under ACTS. If this fails to compile, the failure is in the translation, and the
line number is the finding. Result: `______`

### M2 · Read-only walk — open every page, select NOTHING that writes
Inject (`bash tools/inject.sh gunfight_menu`), restart the match, then:

| Key | Expect |
|---|---|
| **RMB + V** | `---- Gunfight Host (1/3) ----` with two items |
| **RMB / LMB** | cursor moves, pages advance |
| **R** on a page name | opens it |
| **V** | back, then closes |

Walk: Teams · Players (should list every human with `allies` / `axis` / `spec`) · Round · Loadout ·
Spy plane · Map · All maps. **Select nothing.** If the menu draws and navigates, the engine
translation is right and every later result is about the controls, not the menu.
⚠ If only 1 item shows per page, or lines overwrite each other, set `gf_menu_lines` — the Atian author
chose 2 for MP and it is a dvar here for exactly this reason. Result: `______`

### M3 · Controls, one per match, cheapest and most-proven first
| Order | Control | Proven? | What to look for |
|---|---|---|---|
| 1 | Round → Timer 60s | ✅ shipped | round clock changes within a second |
| 2 | Teams → 4v4, then Fill with bots | ✅ L6 + C7 | `4v4` message; bots land 4 a side; **survives the round** |
| 3 | Round → Restart match | ✅ B4 | restarts; menu still opens afterwards (`menu_restart` on start_gametype) |
| 4 | Teams → Remove all bots | — | bots gone |
| 5 | Loadout → Snipers | ⚠ B6 | **next round** is snipers-only |
| 6 | Spy plane → Shared | ⚠ B7 | next round |
| 7 | Players → someone → To Axis | ⚠ C11 | they switch sides and spawn normally |
| 8 | Spawns → guard ON, play a round at 4v4 | ⚠ **page never drawn** | nobody spawns out of bounds; anchors build immediately so it applies the same round |
| 9 | Match → round / win limit | ⚠ **page never drawn** | the round counter obeys it; `-1` sentinels mean only an explicit pick asserts control |
| 10 | Map → Zoo (method: carry) | ✅ host-side | loads Zoo exactly like the Atian menu did. ⚠⚠ **SOLO ONLY — the carry crashes connected clients** (measured 2026-09-10) |
| 🪦 | ~~Map → method **session** → Zoo~~ | 🪦 **DO NOT RUN** | `switchmap_load` measured **inert in MP** (2026-09-11, two iterations). The SESSION row is a dead menu option; its removal was blocked by a safety classifier |

⚠ **Test a lobby return after 3, 8 and 10.** ⚠ Settings are dvars — they persist until the game is
restarted, including across matches. `gf_team_size`, `gf_timer_seconds`, `gf_loadout`, `gf_spyplane`,
`gf_map_method`, `gf_menu_lines`.
Results: `______`

---

## P — THE PREGAME LOBBY. `src/test_frontend/` — a different hook, so its own band

[`pregame-routes.md`](pregame-routes.md). **This is the only payload hooked at `load_shared.gsc`**
(`inject.sh` picks the target itself for this project). It links in every VM; `util::is_frontend_map()`
splits the two halves. The frontend half stashes its readings in `gf_fe_<id>` dvars and the in-match
half prints them, because nothing is known to render in the lobby.

⚠ **It links in the frontend, which is exactly where `scene_model_shared` hung the game.** A lobby
return is part of every run below, not an afterthought. If the lobby hangs on "connecting", the
payload's `#using` list is the first suspect (core_common only, deliberately).

### P1 · Read-only — does it run there, and what does it see? ← **run first**

```
inject.sh test_frontend            # at the MAIN MENU. ⚠ predicted to work with no match loaded;
                                   #   "Can't find target script" here is a finding - record it
play or restart one match          # links the MP half. It prints 50 = 99999. Correct: nothing stashed yet
leave to the lobby                 # links the FRONTEND half
Custom Games → the usual 3v3 Gunfight lobby → wait 30s → rules menu, set the timer to 60 → start
```

| Probe | Reading | Means |
|---|---|---|
| **50** | `0` / `99999` | **the frontend half never ran.** Everything else is void. `#using` failed to link, or the thread died before `wait( 3 )` — check for a lobby hang first |
| 50 | rising | it runs, and keeps running while you navigate |
| 51 | bit 2 set | `sessionmodeisprivate()` is true in a custom lobby — the gate a real payload uses |
| 51 | bit 16 / 32 | a player entity exists there / it answers `ishost()` — the input half of a lobby menu has something to poll |
| **52** | `6` (3v3) / `4` (normal) | **the frontend store IS the pending lobby config** — the same numbers L6/L7 read in-match |
| 52 | `99999`, 50 rising | the read threw or returned nothing. `bot.gsc:39`'s guard was for a reason; **P2 is moot in GSC** and P3/P6 carry the goal |
| **53** | `60` | the store follows the rules menu **live** |
| 53 | `40` | it holds the default and the menu writes somewhere else (the DDL); note which and move on |
| 54 | `0` | control — L5 read 0 in-match |
| 55 / 56 / 58 | numbers | lobby client count, connected players, `com_maxclients` as the lobby sees them. Write them down; `com_maxclients` here vs 8/10 in-match is a free reading on when the budget is fixed |
| 57 | int | `getlobbyuiscreen()` — note the value per screen you were on. `88888` = defined but not an int |

Result: `______`

### P2 · One write from the lobby — `maxplayers`, then `timelimit`, separately

`write_maxplayers = 1` (value 8). Same walk. **Three readouts, none of them a probe:**

1. **the lobby:** try to put a 4th bot / player on one side. Today a 3v3 lobby refuses. Lifted →
   🔓 **the lobby cap follows `maxplayers`, and a human 4v4 is seated by the stock join path**;
2. **59** = `2` → the write landed and read back; `3` → rejected or clamped (record the value in 52);
3. **60** in the match, read before anything writes: `8` → **it carried.** `6` → the launch rebuilt
   the store from the DDL; the write reached the lobby VM but not the launch. Its own row.

Then `write_timelimit = 1` (value 60): the **rules-menu row** is the readout — if it shows 60 without
being touched, the write reached what the UI reads.

⚠ The write repeats every 10s on purpose (the store may be rebuilt when the mode is picked). That
repetition is untested. Lobby return after each. Result: `______`

### P5 · Three observations, NO code — the saved-games route ← **do these before P1 if you are at the machine anyway**
[`pregame-routes.md`](pregame-routes.md) P5. The save format is the match-time settings blob with
`maxplayers` in seven bits; the only question is how a modded value gets into it.

1. **After a `gunfight_mod` match, does the lobby's timer row read 60?** `gunfight_mod` writes
   `timelimit = 60` in-match. If the row shows 60 back in the lobby, the in-match write flows back and
   **Save captures modded settings today** — then Save it, start a fresh lobby, Load it, and read
   `lobby_probe` 2xxxxx (60 = it round-tripped through the account). Row reads 40 → route 2 (P2).
   Result: `______`
2. **Save a custom game, then sort the `player` folder by modified time.** New file = local (the DDL is
   its schema). Nothing = cloud. Result: `______`
3. **How long a name / description does the Save dialog accept?** The DDL says 64 / 128. Matching caps
   = the format is confirmed against the game. Result: `______`

### P3 · `debugcmd = 1` — is `adddebugcommand()` alive in CW?

In-match only. `adddebugcommand( "set gf_fe_dbg 7\n" )`, then read the dvar. `62`: **2 or 3 = the
console is reachable from script** — `gametype_setting`, `map`, `lobbylaunchgame` become one GSC line
each, in the lobby too, and the DLL route is unnecessary. `4` = nulled, as BO4's table says of BO4.
`1` alone = `canadddebugcommand()` says yes but `set` did not land — try `seta`, then a command with a
visible effect. Result: `______`

---

## 🖥️ Unattended operation — what the agent can and cannot drive alone

Established 2026-09-09, when klaze asked whether he could leave the machine running and drive testing
by Remote Control.

| Capability | Status |
|---|---|
| Inject a payload (`tools/inject.sh`) | ✅ no user input needed |
| Read probe output | ✅ `tools/capture-probes.ps1` — the agent reads its own probes |
| Compile, commit, push | ✅ |
| Restart the match from script (`map_restart()`) | ✅ **B4 PASSED** — and an already-linked script re-runs after it |
| **Restart the match (F7 / SendInput)** | 🪦 **CONFIRMED NOT WORKING** |
| **Link a freshly injected payload** | 🪦 **B9: breaks the link outright** ← the blocker |
| Navigate the Atian Menu | 🪦 never tested |

🪦 **F7 is settled, and it is a measurement now, not an open question.** Clean mid-round test: before,
a live round at 0:32; after F7, the same round, same position, clock running 22.8 → 4.9 across 25
seconds. No reload. cwpatch's hotkey hook ignores injected input — `LLKHF_INJECTED`, which
`tools/send-key.ps1`'s own header named as the first suspect. Not fixable from our side.

✅ **B4 found the replacement, and it is better:** `map_restart()` is a GSC builtin, so it needs no
keyboard at all, and **the linked script re-ran after the restart** — a `map_restart` is a real
script-linking load, not a lighter reset.

🪦 **But B9 closed the loop that would have made it autonomy.** Injecting v2 over a live v1 and letting
v1's restart land produced **neither** version stamp. Swapping a payload under a running script does
not link the new build; it appears to break the link outright, leaving nothing running. So
inject → self-restart → linked **does not work**, and the agent still cannot put fresh code into the
game unattended.

⚠ **B9's own caveat, kept rather than glossed:** frames were **sampled**, not exhaustively read — four
frames spanning the round. The probe cadence is 5s and displays persist ~5s at a 3s capture interval,
so a miss is unlikely but not impossible. **Re-running with the guard dvar cleared would confirm it**,
and since this one result is what closes off unattended operation, it is worth the one run.

⚠️ **The desktop must stay live.** Screen capture is GDI against the game window, so:
- `powercfg` display-off / standby / disk-idle set to **0 on AC** (2026-09-09). Revert:
  `powercfg /change monitor-timeout-ac 15 ; powercfg /change standby-timeout-ac 120 ; powercfg /change disk-timeout-ac 20`
- The screensaver is active at 20 min but **not** secure, so it does not lock. Leave it that way.
- 🪦 **Do NOT RDP in and then disconnect.** Disconnecting locks the console session and GDI capture
  goes black — the agent loses all probe reading with no error to explain it. Use Claude Remote
  Control (message the session) and leave the PC logged in, or stay connected for the whole run.
