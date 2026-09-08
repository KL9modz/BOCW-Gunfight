# The in-game menu — the map/gametype carry, and the index

The private-match menu is the layer both headline goals were blocked on. This note holds what it
demonstrably does, and the index of it — which is **filled in by walking it**, never from the dump.

---

## Headline: the menu carries Gunfight onto a non-Gunfight map — n=1, 2026-09-08

Reported in-game by klaze:

1. Started a private match: **Gunfight on Mansion**.
2. Used the in-game menu to **switch the map to Hijacked**.
3. **Gunfight loaded on Hijacked.**

Both map identities are externally confirmed, per this repo's dump-vs-external rule:

| Map | Status | Source |
|---|---|---|
| **Mansion** | a stock BOCW **Gunfight 2v2** map (post-Season-One addition, alongside Amsterdam, Showroom, Gluboko) | Call of Duty Wiki, GamesAtlas |
| **Hijacked** | a **6v6** map, BO2 remake, added **Season Four, 17 June 2021**. **Not** a Gunfight map | callofduty.com Tactical Map Intel, Blizzard News |

So this is Gunfight running on a map the Gunfight playlist does not offer — **with no GSC, no DLL, and
no injector.**

### Why this matters more than it looks

[`dll-proxy.md`](dll-proxy.md) closes with the project's blocking statement:

> Both remaining headline goals — Gunfight on arbitrary maps, and 6v6 in a private lobby — reduce to
> decoupling gametype from the menu's playlist configuration, and this was the mechanism for it.
> **It is currently blocked.**

It was blocked because the `powrprof.dll` proxy crashes the game at startup, 3 attempts out of 3,
identical fault offset. **The menu appears to do the same job the proxy was going to do.** If this
reproduces, `cwdllgt` is not on the critical path for map unlocking at all.

And the second half of that sentence is now testable in the same lobby. **Hijacked is a twelve-client
map.** The whole 6v6 argument in [`team-sizes.md`](team-sizes.md) is that the private-match UI declines
to offer a twelve-client mode on Gunfight's maps — not that the engine or the map refuses. A Gunfight
lobby sitting on Hijacked is exactly the inheritance case that argument predicts should work.

## ⚠ What is NOT established — n=1, and "it loaded" is not "it works"

Do not let this note become the next thing that has to be walked back. Five things are open:

1. **Reproducibility.** One report, one lobby, one map pair. Unconfirmed whether it survives a
   full/fast restart, a second map switch, or a lobby that other players join.
2. **Whether it plays correctly.** Every private Gunfight match is *already* running degraded on every
   map — `setupzones()` returns false, `onstartgametype()` early-returns, and the five presentation
   symptoms are present ([`gunfight-findings.md`](gunfight-findings.md), n=2, ICBM and Amsterdam both
   read zero zones). Hijacked will be degraded too. That is the **stock** condition, not a
   carried-map artifact — but it means "it loaded" says nothing about round flow, scoring, or the
   round-end decision.
3. **The round-timer path is live and unfixed.** With a non-zero `timelimit` on a zoneless map, a
   round that reaches time expiry runs `ontimelimit()` → `overtime()` → `level.zones[0]` on an
   undefined array. Stock's own latch (`level.var_c7cce1ff`) catches the fallout and the health
   decision still lands one tick late, so this is a **thread exception, not a process crash** — but
   it is exactly what `gunfight_mod`'s `timelimit_fix` exists to prevent. Both prior clean matches
   ended by elimination and never reached it.
4. **Player slots.** Unknown whether `com_maxclients` changed. This is the project's Phase 1 gate and
   nobody has read the number in a carried lobby.
5. **The menu path.** Not recorded. Which screen, which entry, which input — all unknown, and that is
   the whole reason for the index below.

## ⚠ This note cannot be written from the dump — do not try

`.claude/CLAUDE.md` lists the front end under **confirmed dead ends**:

> **BOCW front-end / playlist data** — **not in any public dump.** The UI is compiled LUA;
> `bocw-source`'s `ui/` holds only two graphics cfgs. This is where the map list and per-mode
> `com_maxclients` live, and it is the FNV1a64 wall.

And [`README.md`](README.md) in this folder states the split outright: *"The dump has no display
names, no localization table, and no map metadata. It cannot resolve a UI name to a codename, ever."*
It also records what re-litigating that costs — two sessions spent arguing over whether ICBM was one
of the nine `mp_sm_*` maps from asset-token frequencies, which one web search settled in a step.

**The menu is walked, not decompiled.** Every row below gets filled by a person looking at the screen.
An agent cannot fill them, and an agent guessing at them is the documented failure mode.

---

## The index — fill by walking

Record what you see, not what you expect. An entry that is **absent** is a result; write `ABSENT`
rather than leaving the row blank, so the next reader can tell "checked, not there" from "not checked".

### Capture protocol

- One row per menu entry, in **screen order**, top to bottom.
- Note the **screen** it lives on and the **exact input** that reaches it (button, key, stick).
- Note whether the entry is **greyed out**, and whether that changes as host vs. joiner, in-lobby vs.
  in-match, pre-round vs. mid-round.
- Where an entry has a value list, record **every published value**, not just the current one.
- Screenshots beat transcription. Photograph or capture each screen and attach; the table is the
  summary, not the evidence.

### A — Entry point

| Question | Answer |
|---|---|
| What opens this menu (key/button)? | `_____` |
| Does it open in-lobby, in-match, or both? | `_____` |
| Host-only, or joiners too? | `_____` |
| Is it stock BOCW UI, or drawn by an injected DLL? | `_____` |

> ⚠ **This one gates everything else.** If it is stock BOCW UI, this index is the only record that
> will ever exist and walking it is the whole job. If it is an injected mod menu, its behaviour may be
> readable from that tool's source instead — say which tool and the work changes shape completely.

### B — Screens

| # | Screen title | Reached from | Notes |
|---|---|---|---|
| 1 | `_____` | root | `_____` |
| 2 | `_____` | `_____` | `_____` |

### C — Entries

| Screen | Entry label | Input | Values offered | Greyed? | Effect observed |
|---|---|---|---|---|---|
| `_____` | `_____` | `_____` | `_____` | `_____` | `_____` |

### D — The two entries this project actually needs

| Target | Found? | Screen | Input | Values | Notes |
|---|---|---|---|---|---|
| **Map change** | ✅ works — used for Mansion → Hijacked | `_____` | `_____` (see inherited note below) | `_____` | Did the full map list appear, or only Gunfight's ten? |
| **Gametype / mode change** | ❌ **NOT FOUND** — this is the open ask | `_____` | `_____` | `_____` | Absent entirely, or present and greyed? The two mean different things |
| **Team size / max players** | `_____` | `_____` | `_____` | `_____` | Cross-check against probe 1 rather than trusting the label |
| **Round timer** | `_____` | `_____` | `_____` | expect `0/20/30/40/50/60` | Confirmed live-settable; menu exposure confirmed |

## Inherited context — UNVERIFIED, carried from a lost session

The desktop session `kl9-desktop-crystalline-cascade` went offline mid-walk on 2026-09-08. Its
transcript is on that machine and is not recoverable from the cloud; only its one-line state card
survived:

> *"found R (reload) remaps to map change; need gametype menu entry"*

Read as: the **R key** (bound to Reload in gameplay) reaches the map-change control in this menu
context. **This is a summary of a claim, not a verified finding** — the reasoning behind it is gone.
Re-confirm it on the next walk before building on it, and if it holds, it belongs in table D above
with the screen it applies to.

## Adjacent controls that are NOT this menu

Do not conflate these with menu entries. They are DLL hotkeys from the cwpatch
`discord_game_sdk.dll`, documented in [`unlock-dlls.md`](unlock-dlls.md), and they fire via
`GetAsyncKeyState` even when alt-tabbed:

| Key | Command |
|---|---|
| F4 | `lobbylaunchgame` |
| F6 | `fast_restart` |
| F7 | `full_restart` |

F6/F7 are directly useful here — they re-run a match without leaving the lobby, which is the cheap way
to test whether a carried map/gametype pairing survives a restart.

---

## Measure before you map — one probe run is worth the whole table

[`../src/mp_probe/`](../src/mp_probe/) reads engine-owned state and prints it as tagged numbers
(`PROBE_ID * 100000 + VALUE`; strip the leading digit). Injected into a **carried Gunfight-on-Hijacked
lobby** it answers, in one match, questions the menu index can only describe:

| Tag | Reads | What it settles here |
|---|---|---|
| `1xxxxx` | `com_maxclients` | **The Phase 1 gate.** `12` = the carry inherits Hijacked's client count and **6v6 needs no code**. `8` = the lobby config followed the gametype, and 6v6 stays blocked |
| `5xxxxx` | `gunfight_zone_center` count | Classifies Hijacked. Expect `0`, same as every stock map — a non-zero would overturn [`gunfight-findings.md`](gunfight-findings.md) |
| `2xxxxx` | live `timelimit` | Whether this lobby can reach the `overtime()` exception at all. `0` = no limit = never fires |
| `7xxxxx` | players in match | sanity |

⚠ Injecting begins host-side exposure — [`tac-risk-model.md`](tac-risk-model.md) first. The menu walk
itself carries **zero** exposure and needs no injection, so **walk first, inject second**.
