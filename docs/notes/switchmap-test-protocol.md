# switchmap_load in-match test — protocol (spec 2026-09-11)

Tests the PRIORITY AVENUE (pregame-routes.md): is in-match `switchmap_load(map, level.gametype)` +
`switchmap_switch()` a **joiner-safe** map change? Payload: `src/test_switchmap/scripts/test_switchmap.gsc`
(compile-ready; all builtins verified present). ⚠ Injection needs klaze's explicit per-action go
(memory: `project_bocw_gunfight_test_box`).

## Hook — DEFAULT MP-match pair (NOT frontend)
`bb.gsc` target + `clientids_shared.gsc` replace — it runs in the in-match server VM where stock calls
switchmap. `test_switchmap` is deliberately NOT in inject.sh's frontend list. bb.gsc needs a match loaded
once first (scriptparsetree pool), like gunfight_mod.

Build:  `acts gscc src/test_switchmap/scripts/test_switchmap.gsc -g cw -p pc -o /c/bocw/payloads/test_switchmap`
Inject: `cd /c/bocw/ACTS/bin && ./acts.exe injectcw /c/bocw/payloads/test_switchmap.gscc 'scripts\mp_common\bb.gsc' 'scripts\core_common\clientids_shared.gsc'`
Then restart the match to link it.

## Reading the screen (id*100000+value)
- `70` gametype defined · `71` player count · `72` read_only · `73` gf_sw_done guard
- `90` countdown · `91` FIRING NOW (value=players) · `92` survived switch (unexpected)
- ★ **`7300001` on a map you did NOT launch = the switch fired and the new map's VM is alive = the win.**

## Phases — one game session each (the gf_sw_done dvar persists in-process; a game restart clears it)

### Phase A — read_only=1 (as shipped). Zero risk.
Build+inject, load a solo Gunfight match. Expect `70=1, 71=1, 72=1, 73=0` looping. Confirms the payload
runs in-match, reads state, and does NOT switch. If this is healthy, proceed.

### Phase B — read_only=0, min_players=1. Host alone. Does in-match switchmap work AT ALL?
Edit config `read_only→0`, recompile+reinject. Host a Gunfight match **on a compatible map that is NOT
mp_kgb** (e.g. Nuketown), solo. Let a round breathe (don't end it instantly). At ~7s you see `90` counting
down, then `91`. Then:
- **Map changes to KGB, host alive, `73` now 1** → in-match switchmap WORKS (B2's crash was frontend-only). ✅
- **Host crashes** → in-match switchmap also crashes → route dead. Record the crash + minidump path.
- **Nothing** → the call didn't take; try the 1-arg form (`#pass_gametype`-style tweak) next.

### Phase C — read_only=0, min_players=2. THE QUESTION: does the friend follow?
Config `min_players→2`, recompile+reinject. Host on a compatible map (Nuketown), **friend joins the lobby,
launch together** so both are in-match. Let a round breathe. At fire:
- **Friend follows onto KGB, both playing** → JOINER-SAFE MAP CHANGE CONFIRMED. The avenue pays off:
  real Gunfight, any map, joiner-safe, host-inject only. → go to Phase D.
- **Friend crashes/drops** → switchmap desyncs joiners like the carry. Route dead for joiners; record it.

### Phase D — (LATER, only if C succeeds) incompatible target + guards
Integrate the switch into gunfight_mod (so its zones_guard/timelimit_fix are active), set target to a
VERIFIED-loadable incompatible map (`mp_miami` — proven loadable by the carry), keep `level.gametype`.
This is the actual deliverable: Gunfight on an off-Gunfight map, joiner-safe.

## Safety
- **Only ever target a VERIFIED-loadable map name.** `mapexists()` returns TRUE for any name (B5) — a bad
  name tears the session down with no error. mp_kgb (native Gunfight) and mp_miami (carry-proven) are safe.
- One payload at a time (shared replace target). Phases A–C run standalone; Phase D lives inside gunfight_mod.
- To re-run a phase in the same game session, the guard has already fired — restart the game to clear
  `gf_sw_done` (dvars persist in-process).
- If anything looks wrong during the `90` countdown, leave the match to abort.
