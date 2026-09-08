# Test queue — everything open, ordered by risk

One sheet aggregating every untested item across the notes, so a session at the machine does not have
to read five files to find the next thing to run. **Fill in the Result column and the answer becomes
the finding.**

⚠ **A result is a measurement.** Record what the number was. Do not record "therefore X is
impossible" — every such conclusion in this project has had to be walked back. Where a test comes back
negative, write what it ruled *in* and move the question to that note's *Untried* list.

⚠ **One write per match.** Tests 4 onward change session state with distinct failure modes; bundling
them makes a failure unattributable. **Test a lobby return after each** — that is the check that
caught `scene_model_shared`.

**Setup for anything injected:** [`menu-map.md`](menu-map.md) → *PROCEDURE*. Start in **`3v3 Gunfight`**
unless a test says otherwise; the slot count is fixed at lobby creation and cannot be changed after.

---

## A — Zero risk. Read-only, nothing written.

### A1 · `lobby_probe` — four player counts and the gametype bitmask ← **run this first**
`src/lobby_probe/` · [`cw-builtins.md`](cw-builtins.md)

Validate offline first: `.\tools\check-gsc.ps1 .\src\lobby_probe\scripts\lobby_probe.gsc`. It uses
builtins **no stock script calls**, so stage 4 is the real gate here.

| Read | Expect | Result |
|---|---|---|
| `1xxxxx` `com_maxclients` | 8 in 3v3 Gunfight, 12 in TDM | `______` |
| `2xxxxx` `getnumexpectedplayers()` | **unknown — never called** | `______` |
| `3xxxxx` `numremoteclients()` | **unknown** | `______` |
| `4xxxxx` `getnumconnectedplayers()` | **unknown** | `______` |
| `5xxxxx` flags | 1=teambased, 2=private → expect **3** | `______` |
| `9xxxxx` **gametype bitmask** | see below | `______` |

**Read the bitmask controls before anything else.** Bit 0 (`gunfight`) and bit 1 (`tdm`) must be SET;
bit 7 (value ≥128, `zzz_not_a_gametype`) must be CLEAR. Outside `3..127` the probe is meaningless —
discard it, do not interpret it.

- `7` = only `gunfight`, `tdm`, `gunfight_3v3` are valid. Expected.
- `>7` = **a Gunfight variant nobody knew about.** 16 = `gunfight_4v4`, 32 = `gunfight_5v5`,
  64 = `gunfight_6v6`. **This would be the cheapest possible answer to the team-size goal.**

Run it in **both** a 3v3 Gunfight lobby and a private TDM lobby — probes 2–4 are most interesting
where they *disagree* with probe 1.

### A2 · Re-count the Atian map list
[`atian-menu-source.md`](atian-menu-source.md). The walk recorded **19** maps; the CW source wires
**48** (37 under `is_multiplayer()`). Count what the menu actually shows.
→ 19 means the shipped release predates master. 37–48 means the earlier count was one page.
Result: `______`

### A3 · `mp_probe` on a carried lobby
Classify a carried map's `gunfight_zone_center` count (`5xxxxx`). Expect **0**, same as every stock
map. A non-zero would overturn [`gunfight-findings.md`](gunfight-findings.md). Result: `______`

---

## B — Low risk. Reverts on restart.

### B4 · `map_restart()` — can cwpatch be dropped?
`map_restart` (0–1 args, `+3b0a5c0`). The procedure needs **F7** at step 7 because the lobby route
discards the map carry, which makes cwpatch a hard prerequisite that Battle.net silently reverts on
repair.

**Carry a map, then call `map_restart()` instead of pressing F7.** Does the carried map survive?
→ Yes: the DLL comes out of the critical path. → No: F7 stays required, and *why* is worth a line.
Result: `______`

### B5 · `mapexists()` over the 48 source names
Which of the Atian source's map names this build actually has. Pure enumeration, pack as a bitmask the
way A1 does. Result: `______`

---

## C — Session writes. **One per match. Lobby return after each.**

### C6 · `switchmap_load` from a 12-slot TDM lobby ← **the team-size question**
[`atian-menu-source.md`](atian-menu-source.md)

Start in **private TDM** (12 slots — *not* Gunfight). Then:

```gsc
switchmap_load( util::get_map_name(), "gunfight_3v3" );
wait( 1 );          // load-bearing per ate47; reason unknown
switchmap_switch();
```

Then read `mp_probe` `1xxxxx`.

| Reading | Means |
|---|---|
| `100012` | `switchmap_load` reaches the playlist layer — **larger teams are script-reachable** |
| `100008` | it re-derived the lobby from the gametype, like the map carry does |

⚠ The gametype argument is **optional** (1–2 args), so the CW build honouring it is itself untested.
If Gunfight does not load at all, that is the answer to a different question — record which happened.
Result: `______`

### C7 · `addtestclient()` in a loop — the **real** client ceiling
`addtestclient` (0–2 args, `+3d3c9e0`). Add clients until it stops accepting them; the count is the
answer, whatever `com_maxclients` says. This measures the thing instead of reading a proxy for it.

Also the mechanism Phase 3's *"bots before humans"* always assumed and never had.
⚠ `kick` (1–2, `+3b0a3a0`) is the only obvious undo. Result: `______`

### C8 · `setteam()` on a spectator — **is 8 clients actually 4v4?**
[`cw-builtins.md`](cw-builtins.md) §5. If the 8 slots are 6 players + 2 spectators, and `setteam` can
put a spectator on a team, **8 clients is exactly 4v4 with no larger lobby at all** — which is the
stated target.

⚠ `setteam`'s single argument may be a team name, an index, or something else. Try with a bot from C7
before a human. Result: `______`

### C9 · The lobby glitch + `mp_probe`
[`menu-map.md`](menu-map.md). The glitch is a genuine **playlist reconfiguration** where the map carry
is only a load-time override — so it acts on the layer that sets `com_maxclients`. Unreliable, but
this only needs it to work once. Read `1xxxxx`. Result: `______`

---

## D — Menu walk leftovers. No injection beyond the menu itself.

| # | Item | Result |
|---|---|---|
| D10 | **Pages 1–3** of the Atian Menu — never transcribed, reported as "weapons and camera stuff" | `______` |
| D11 | **Host vs joiner** — the menu was only ever opened in a single-player lobby. Can a joiner open it? Does the carry behave for them? | `______` |
| D12 | **In-lobby vs in-match** — only ever opened in-match | `______` |

---

## What would change the project most

1. **A1's bitmask above 7.** A stock Gunfight variant at 4v4 or larger turns the remaining goal into a
   string.
2. **C6 reading 12.** Team size becomes script-reachable.
3. **C8 working.** 4v4 with no lobby change at all — the target, from the lobby you already have.
4. **B4 working.** The hosting procedure loses its DLL prerequisite.

Anything else is worth knowing but does not move a goal.

⚠ Injecting begins host-side exposure — [`tac-risk-model.md`](tac-risk-model.md). Nothing here hides
itself from the anti-cheat; that is out of scope by decision.
