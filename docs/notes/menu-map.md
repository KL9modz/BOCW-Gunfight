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

### ⚠ It does NOT carry the 6v6 half — the direction is wrong

An earlier version of this note claimed a Gunfight lobby sitting on Hijacked was "the inheritance case
`team-sizes.md` predicts should work," and that one probe run there was a cheap Phase 1.
**That was backwards. Disregard it.**

[`team-sizes.md`](team-sizes.md) is explicit on both halves:

> `com_maxclients` ... is fixed **at lobby creation by the playlist**, not by the gametype. ... Start in
> a lobby the menu has already built with twelve slots, and **never be in a Gunfight lobby at all.**

This carry starts *in a Gunfight lobby* and changes the map. Switching maps does not re-create the
session, so the eight slots were fixed before the switch and Hijacked being a twelve-client map cannot
retrofit them. Measured 8 in a private Gunfight lobby, 12 in a private TDM lobby — both 2026-09-07.

**So the carry solves the map goal and leaves the team-size goal exactly where it was.**

### The asymmetry that actually matters

Two different menu operations, and only one is confirmed:

| Operation | Direction | Status | Solves |
|---|---|---|---|
| **Map change** | inside a Gunfight lobby, swap the map | ✅ **works** — Mansion → Hijacked | any-map |
| **Gametype change** | inside a twelve-slot TDM lobby, swap to Gunfight | ❓ **entry not found** | 6v6 |

The second is the one Phase 1 needs, and it is the one the menu has not yielded. If the menu offers a
map-change entry but genuinely has **no** gametype-change entry, that is a finding in itself: it would
mean the menu closes the map goal and cannot close the team-size one, and Phase 1 falls back to the
map/mode carry glitch or the DLL track. **Establishing which is the highest-value thing left in this
note.**

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
4. **Player slots.** Almost certainly still **8** — fixed at lobby creation, and this lobby was created
   as Gunfight. Worth one probe read anyway, because this project has been burned by reasoning where it
   could have measured, but a `8` there is the model confirming itself, not a failure.
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
| What opens this menu (key/button)? | **ADS + Melee** held together (default PC: RMB + V) |
| Does it open in-lobby, in-match, or both? | In-match — confirmed. In-lobby not tested |
| Host-only, or joiners too? | Not tested; the lobby was single-player |
| Is it stock BOCW UI, or drawn by an injected DLL? | **NEITHER — an injected GSC script** |

#### ✅ ANSWERED 2026-09-08 — it is the Atian Menu, and its source is public

**Not stock UI, not a DLL overlay.** It is `BlackOpsColdWar_atianmenu_pc.gscc`, a precompiled GSC mod
menu, downloaded and injected by the desktop session on 2026-09-08.

| | |
|---|---|
| Tool | [`ate47/t8-atian-menu`](https://github.com/ate47/t8-atian-menu) — **same author as ACTS** |
| Asset | `BlackOpsColdWar_atianmenu_pc.gscc`, release tag `latest_build`, **66,320 bytes** |
| Header | `80 47 53 43 0d 0a 00 38` — `cw::GSC_MAGIC`, last byte `38` = VM38 retail |
| Injected as | `acts injectcw <gscc> scripts\mp_common\bb.gsc scripts\core_common\clientids_shared.gsc` |
| Reliability | Injected cleanly every attempt. **Must be re-injected after every game restart**, and the match restarted afterwards so the script links |

**⚠ This corrects the headline of this note.** It states the carry happened *"with no GSC, no DLL, and
no injector."* That is wrong. It was **entirely GSC and the injector** — the Mansion → Hijacked map
change was performed *by this injected mod menu*. The menu is not a property of the game; it is
something we installed. Anyone reproducing the carry must inject the Atian Menu first.

The mechanism is still real and still closes the map goal without `cwdllgt`. But it is not stock, not
free, and does not survive a restart on its own.

Per this section's own gate — *"if it is an injected mod menu, its behaviour may be readable from that
tool's source"* — **it is readable.** The repo is public, so structure and keybinds come from source
rather than from walking. Read from source, not observed:

**[`scripts/config/keys.gsc`](https://github.com/ate47/t8-atian-menu/blob/master/scripts/config/keys.gsc), verbatim:**

```gsc
self.menu_open   = "ads+melee";
self.parent_page = "melee";
self.last_item   = "ads";
self.next_item   = "attack";
self.select_item = "use";
```

| Action | Game action | Default PC key |
|---|---|---|
| Open | ADS + Melee | RMB + V |
| Up (`last_item`) | ADS | RMB |
| Down (`next_item`) | Attack | LMB |
| **Select** (`select_item`) | Use | **R** — see below |
| Back (`parent_page`) | Melee | V |

**⚠ `select_item = "use"` does NOT mean F.** On BOCW PC the `use` action resolves to **R (Reload)**.
Confirmed in-game 2026-09-08 after F, E and Space all failed. This one fact is what made the menu look
broken: it opened and scrolled but appeared to select nothing.

### B — Screens

The root screen is **paged**, titled `---- Atian Menu CW (n/N) ----`. Observed 2026-09-08: `(4/4)`,
i.e. four pages. Paging is the same up/down inputs; there is no separate page control.

| # | Screen title | Reached from | Notes |
|---|---|---|---|
| 1 | `Atian Menu CW (1/4)` | root | **NOT WALKED** |
| 2 | `Atian Menu CW (2/4)` | root, scroll | **NOT WALKED** |
| 3 | `Atian Menu CW (3/4)` | root, scroll | **NOT WALKED** |
| 4 | `Atian Menu CW (4/4)` | root, scroll | Observed. Contains `Vehicle`, `Map` |

⚠ Pages 1–3 are unwalked. The README's feature list (Tools / Give weapons / Gun tool / Teleport tool /
Loading / Customization / Internal tools) is written for the **BO4** build and did **not** match what
page 4 showed, so do not assume it describes the CW tree.

### C — Entries

| Screen | Entry label | Input | Values offered | Greyed? | Effect observed |
|---|---|---|---|---|---|
| `(4/4)` | `Vehicle` | not selected | unknown | no | not tested |
| `(4/4)` | `Map` | R (select) | unknown — list not recorded | no | **map changed mid-match, Mansion → Hijacked** |

### D — The two entries this project actually needs

| Target | Found? | Screen | Input | Values | Notes |
|---|---|---|---|---|---|
| **Map change** | ✅ works — Mansion → Hijacked | `(4/4)`, entry `Map` | **R** to select | list NOT recorded | Open: did the full map list appear, or only Gunfight's ten? Hijacked is not a Gunfight map, so the list is **not** limited to the ten |
| **Gametype / mode change** | ⚠️ **NOT ABSENT — NOT YET LOOKED FOR** | pages 1–3 unwalked | — | — | See below. Do not record `ABSENT` yet |
| **Team size / max players** | not looked for | pages 1–3 unwalked | — | — | Cross-check against probe 1 rather than the label |
| **Round timer** | not looked for | pages 1–3 unwalked | — | — | expect `0/20/30/40/50/60` |

#### ⚠ On the gametype row — the previous status was wrong

The prior version recorded **`❌ NOT FOUND`**. That overstates what happened: the walk reached page 4
of 4, saw no gametype entry *on that page*, and ended when the session went offline. **Pages 1–3 were
never opened.** "Not found on one of four pages" is not "not found".

Two reasons to expect it exists:

1. The upstream feature list is *"Set map/gametype"* — a **single combined feature**, not two entries.
   The `Map` entry on page 4 may itself carry the gametype option, in which case the answer is one
   `R` press away on a screen already reached.
2. The README lists set-gametype for the tool generally, and the CW build is the same codebase.

So the next walk should (a) select `Map` and record what its submenu actually offers, then (b) walk
pages 1–3. Only record `ABSENT` once all four pages and the `Map` submenu have been seen.

## Inherited context — UNVERIFIED, carried from a lost session

The desktop session `kl9-desktop-crystalline-cascade` went offline mid-walk on 2026-09-08. Its
transcript is on that machine and is not recoverable from the cloud; only its one-line state card
survived:

> *"found R (reload) remaps to map change; need gametype menu entry"*

Read as: the **R key** (bound to Reload in gameplay) reaches the map-change control in this menu
context. **This is a summary of a claim, not a verified finding** — the reasoning behind it is gone.
Re-confirm it on the next walk before building on it, and if it holds, it belongs in table D above
with the screen it applies to.

### ✅ CONFIRMED and corrected 2026-09-08 — that machine came back

The desktop session reconnected and its transcript is intact. The state card was right about the key
and **wrong about the scope**:

> **R is the menu's global SELECT key. It is not a map-change control.**

It is `select_item`, which [`keys.gsc`](https://github.com/ate47/t8-atian-menu/blob/master/scripts/config/keys.gsc)
defines as `"use"` — and on BOCW PC the `use` action resolves to **R (Reload)**, not F. It selects
*any* entry anywhere in the menu. The map change was simply the first thing selected with it.

The distinction matters: read as "R remaps to map change", the next walker looks for a dedicated
map-change binding that does not exist and cannot select anything else. Read correctly, R selects
everything, and the rest of the tree becomes walkable.

The discovery cost real time — F, E and Space were all tried first, because `select_item = "use"`
reads like F to anyone who knows CoD's default Interact key. Worth keeping in the note for exactly
that reason.

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
| `1xxxxx` | `com_maxclients` | **Expect `8`** — fixed at lobby creation, and this lobby was created as Gunfight. A `12` would overturn [`team-sizes.md`](team-sizes.md) and is worth the read for that reason alone. This is **not** the Phase 1 gate; Phase 1 starts from a TDM lobby |
| `5xxxxx` | `gunfight_zone_center` count | Classifies Hijacked. Expect `0`, same as every stock map — a non-zero would overturn [`gunfight-findings.md`](gunfight-findings.md) |
| `2xxxxx` | live `timelimit` | Whether this lobby can reach the `overtime()` exception at all. `0` = no limit = never fires |
| `7xxxxx` | players in match | sanity |

⚠ Injecting begins host-side exposure — [`tac-risk-model.md`](tac-risk-model.md) first. The menu walk
itself carries **zero** exposure and needs no injection, so **walk first, inject second**.
