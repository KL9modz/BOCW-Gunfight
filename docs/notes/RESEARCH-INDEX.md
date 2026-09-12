# Research index — the map-lobby problem & mod expansion (as of 2026-09-11)

Navigational map of the notes. Start here.

## The goal
Real **Gunfight** gametype on **any map**, at the **lobby/match/state level**, **no glitch steps**, with
**friends able to join and play** (vanilla, nothing installed). Private matches only, throwaway box.

## Current state of the map problem — TWO live paths, everything else closed by measurement
1. ▶ **`switchmap_load` in-match** (TOP, untested, buildable) — coordinated map change stock uses in-match;
   may be joiner-safe where the carry is not. **Spec'd + compiles:** `src/test_switchmap/`, protocol in
   `switchmap-test-protocol.md`. Needs klaze's inject go. → `pregame-routes.md` "PRIORITY AVENUE".
2. ▶ **Cheat Engine on the client-LUI compat state** (built, attach-gate cleared, watchpoint pending) — the
   picker gate is the client-frontend `uimodeldatastruct #hash_109ccf57a41ffd82`, injection-unreachable.

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
| `switchmap-test-protocol.md` | staged run sheet for the switchmap test payload |
| `atian-menu-source.md` | the carry menu internals; the two map-change paths |
| `cw-builtins.md` | the engine builtins with addresses (isvalidgametype, switchmap_*, sessionmode*, etc.) |

## The glitch (for reference; ruled out as a method but documents the target state)
FacelessOne tutorial (youtu.be/uzXXE7v_PBU): a two-account menu race that carries an online playlist's
mode object (full map-compat + com_maxclients) into a private lobby. Steps + mechanism in `pregame-routes.md`.

## Mod expansion — grounded next features (`game-systems.md §9, §11`)
synth overtime zones on any map (script can spawn triggers) · custom/themed loadouts (shipped melee/snipers
bundles) · expose stock settings · map control (pending the switchmap test) · all bounded by: joiners get
server-GSC gameplay + stock clientfields only (§2, §10).
