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
1. ✅ **`switchmap_load` in-match** — 🪦 ~~CLOSED 2026-09-11: inert in MP~~ **RETRACTED 2026-09-12**:
   the "inert" runs had their map-name literal garbled by the ACTS string header. Stripped
   (`tools/strip-strhdr.ps1`), `switchmap_load` + `switchmap_switch` **moves the session** (lobby
   follows, 12 slots read in a Gunfight session), and **`switchmap_load` alone stages the pair as the
   lobby's next map** — the match ends and the pregame lobby has it selected (klaze, 2026-09-12).
   Both are menu verbs (*Stage for lobby* / *Switch NOW*). ⚠ Joiners still untested on both.
   → `session-switch.md`
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
| `desktop-session.md` | ▶ **the runbook** — everything open, ordered by what it costs, stages 0–7. Rewritten 2026-09-12 against the measured state: stage 3 is the save-based hosting workflow (P5's follow-through, mostly needs no injector), stage 6 lists what is closed so it is not redone |
| `overtime-zone.md` | **the overtime capture zone on any map** (`#synth_zones`, built 2026-09-12, UNTESTED, `gf_zone` default off): hand stock `setupzones()` a centre + trigger anchored on Domination's neutral B flag, with the ordering proof, the `gettimelimit` extra-time trap, the abort_level valve and a read-only census. The menu's `Overtime zone` page |
| `switchmap-test-protocol.md` | staged run sheet for the switchmap test payload (🪦 avenue closed) |
| `atian-menu-source.md` | the carry menu internals; the two map-change paths |
| `cw-builtins.md` | the engine builtins with addresses (isvalidgametype, switchmap_*, sessionmode*, etc.) |
| `../reference/bocw-maps.md` | **every loadable MP map, display name ↔ map name, audited 2026-09-12** (dump map table + wiki `console` field + asset fingerprints). The Strike/12v12 split is a *gametype-string* branch inside one map file, not a second map; Nuketown Holiday/Halloween are two unresolved dvars. The menu's labels were regenerated from it |
| `../reference/bocw-weapons.md` | **every MP loadout weapon name (64) with display names + confidence, 2026-09-13** (gun-levels CSV ∩ custom-games DDL enum). Menu Weapons page is generated from it. ⚠ No rock/gulag/throwable weapon exists in T9 — the Gulag rock is an IW8 (MW/Warzone) asset; 19 hashed enum ids brute-forced, no hit |

## The glitch (for reference; ruled out as a method but documents the target state)
GlitchHunterz's tutorial (youtu.be/Wxctp-7rrEs, the founder; FacelessOne's youtu.be/uzXXE7v_PBU re-posts
the same text): a two-account menu race that carries an online playlist's mode object (full map-compat +
com_maxclients) into a private lobby. All three variants verbatim in `roadmap.md §B2` (2026-09-13);
mechanism in `pregame-routes.md`.

## The rest of the scene (swept 2026-09-13) — `ecosystem-survey.md`
No other open MP gametype/lobby project exists. The only new thing is the Zombies-only *T9 Mod Manager*
scene (Aug 2026), whose mods configure themselves in the ZM pregame lobby — the one group plausibly on the
same layer. Client route dead; ACTS 3.3.0 is the current pin.

## Mod expansion — grounded next features (`game-systems.md §9, §11`)
synth overtime zones on any map (script can spawn triggers) · custom/themed loadouts (shipped melee/snipers
bundles) · **loadout-pool camo** (`setcamo` per spawn — `loadout-camo.md`, built, untested) · **bots**
(add/remove one, even-up for an odd human count, per-team difficulty via the cracked
`bot_difficulty_<team>` setting, and a CUSTOM difficulty struct past the stock ceiling — `bots.md`, built,
untested) · expose stock settings · map control (pending the switchmap test) · all bounded by: joiners get
server-GSC gameplay + stock clientfields only (§2, §10).
