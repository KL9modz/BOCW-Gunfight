# Research index — the map-lobby problem & mod expansion (as of 2026-09-11)

Navigational map of the notes. Start here.

## The goal
Real **Gunfight** gametype on **any map**, at the **lobby/match/state level**, **no glitch steps**, with
**friends able to join and play** (vanilla, nothing installed). Private matches only, throwaway box.

## Current state of the map problem — ONE live path; the two below it closed on 2026-09-11
0. ▶▶ **`LobbySetMap` / `LobbySetGameType`** (NEW 2026-09-12, untested, tool written) — **the layer the
   whole hunt skipped.** Every closed route attacks the *compat set* (make the picker allow the pair);
   this one skips the picker and calls the two engine functions the picker itself calls. ACTS names both
   with BO4 addresses **0x10 apart**, and ate47's Cold War port **ships disabled with two bugs**;
   `tools/lobby-set.py` is it finished, scan-only by default. ⚠ Two honest risks, both from our own
   measurements: the Lua master may re-push the selection, and `CreateRemoteThread` is one API beyond
   gfscan and `injectcw`. → `lobby-setters.md`
1. 🪦 ~~**`switchmap_load` in-match**~~ — **CLOSED 2026-09-11**: in-match switchmap is inert in MP.
2. 🪦 ~~**Cheat Engine on the client-LUI compat state**~~ — **CLOSED 2026-09-11**: TAC will not let CE
   run at all, and a custom watchpoint tool hits the same anti-debug wall.

### Closed by measurement (don't reopen without new evidence) — see `game-systems.md §4/§8/§10`
carry (crashes joiners) · GSC/UI-model from any injectable VM (P1–P11) · client-frontend VM (uninjectable) ·
memory value-scan of C compat state (Lua-internal) · save edit (server-side) · no map-unlock dvar ·
`map_restart` (same map) · `forcegamemodemappings` (campaign-only) · TDM reskin (ruled out by requirement) ·
manual/automated glitch (ruled out by requirement).

## Key docs
| Doc | What's in it |
|---|---|
| `pregame-routes.md` | the full map-hunt log: P1–P11, memory scans, the glitch tutorial + mechanism, the switchmap PRIORITY AVENUE, the requirement pin |
| `game-systems.md` | **how the game works / mod-expansion reference** (20 sections): Gunfight anatomy; clientfield sync (+joiner-reach correction); builtins; events; injection surface (10); persistence/save (13); scoring/round-flow (14); loadout struct/perks/content refs (15,17,20); spawning + the combined-arms spawn bug + #spawn_guard (16,16b); CSC match VM (12); host-migration (18); bots (19); expansion roadmap (9) |
| `lobby-setters.md` | **the one live map route**: call `LobbySetMap`/`LobbySetGameType` directly, skipping the compat gate rather than beating it. Why it is not in the closure table, the two ways it could still fail, and `tools/lobby-set.py` |
| `desktop-session.md` | ▶ **the runbook** — everything open, ordered by what it costs, stages 0–7. Rewritten 2026-09-12 against the measured state: stage 4 is the save-based hosting workflow (P5's follow-through, mostly needs no injector), stage 6 lists what is closed so it is not redone |
| `switchmap-test-protocol.md` | staged run sheet for the switchmap test payload (🪦 avenue closed) |
| `atian-menu-source.md` | the carry menu internals; the two map-change paths |
| `cw-builtins.md` | the engine builtins with addresses (isvalidgametype, switchmap_*, sessionmode*, etc.) |

## The glitch (for reference; ruled out as a method but documents the target state)
FacelessOne tutorial (youtu.be/uzXXE7v_PBU): a two-account menu race that carries an online playlist's
mode object (full map-compat + com_maxclients) into a private lobby. Steps + mechanism in `pregame-routes.md`.

## Mod expansion — grounded next features (`game-systems.md §9, §11`)
synth overtime zones on any map (script can spawn triggers) · custom/themed loadouts (shipped melee/snipers
bundles) · expose stock settings · map control (pending the switchmap test) · all bounded by: joiners get
server-GSC gameplay + stock clientfields only (§2, §10).
