# Pregame lobby control — the three tests (2026-09-14)

The roadmap's **#1 open goal**: control the map/mode at the **frontend lobby** so friends join a
normal-looking lobby and just play. Three ready-to-run routes, ordered cheapest-first. Run in one
sitting. Everything is already built — this is execution + observation.

**Prereqs**
- Game launched with **cwpatch loaded** (the app's Inject/Status shows `cwpatch: installed + loaded`,
  or F4/F6/F7 work). Reinstall from the app if the status is red after a Battle.net update.
- A **joiner** available for Test 2/3's pass clause.
- Run shells **elevated** if injection / `OpenProcess` is refused.
- ⚠ Guard: klaze runs the injections and the `lobby-set.py` call (`CreateRemoteThread`). The scan and
  the GSC probe are read-only.

---

## Test 1 — Does GSC run in the pregame lobby? (P1, read-only)

`test_frontend.gscc` hooks `load_shared.gsc` (links in **every** VM), so it runs in the lobby AND the
match. The frontend half samples gametype settings every 10 s and **stashes them in dvars**; the
in-match half prints them. Nothing here writes game state.

1. **At the MAIN MENU** (no match loaded), inject in your terminal:
   ```
   bash /c/bocw/inject.sh test_frontend
   ```
   (inject.sh knows it's a frontend project and uses the `load_shared` hook.)
2. Start a private **Gunfight** match, then return to the lobby. Set up a **3v3** lobby and sit in it
   ~30 s so the frontend half samples (every 10 s).
3. Start a match and **watch the lower-left feed**. Probes print as `id*100000 + value`
   (e.g. `5200006` = probe **52**, value **6**).

**Read probe 50 FIRST** — `50xxxxx` = samples taken in the lobby:

| Probe 50 | Verdict |
|---|---|
| **0** | the frontend half **never ran** — GSC does not run in the lobby. This route is dead; go to Test 2. Everything below is meaningless. |
| **> 0** | ✅ **GSC RUNS IN THE LOBBY.** Read the rest ↓ |

If 50 > 0:
- **`52xxxxx`** = `getgametypesetting(#"maxplayers")` read *from the lobby*. **6** in a 3v3 lobby / **4**
  normal ⇒ the frontend store **is the pending lobby config** — team size is fixable BEFORE anyone is
  seated, through the stock join path, no late-join hack. **99999** = no value / the read threw (check
  50 is still rising).
- **`53xxxxx`** = timelimit; if it matches the rules menu, the store follows the menu **live**.
- **`51xxxxx`** = flags: 1 is_frontend_map · 2 private · 4 mp · 8 online · 16 players>0 · 32 host.

**If 52 reads the lobby config:** the follow-up is the WRITE test — inject `test_frontend_maxp`
(writes `maxplayers` from the lobby); success = a 4th player seats without the late-join hack. That is
the pregame **team-size** solve.

---

## Test 2 — Native lobby setters (`LobbySetMap` / `LobbySetGameType`) — the decisive one

`tools/lobby-set.py` calls the game's own frontend setters, bypassing the map/mode compat rule. The
question: does it **reconfigure the compat gate** (a real, joinable solve) or **just set a field** the
UI overwrites?

1. Game running, sitting in a **Custom Games** lobby. Scan first (read-only, changes nothing):
   ```
   python /c/bocw/BOCW-Gunfight/tools/lobby-set.py
   ```
   It prints the two resolved setter addresses. If the scan finds them, proceed.
2. Set an **incompatible pair** — Gunfight on a non-Gunfight map is the win:
   ```
   python /c/bocw/BOCW-Gunfight/tools/lobby-set.py --gametype gunfight --map mp_miami
   ```
3. **The red-triangle test (decisive, no second account needed):** open the map picker.
   - Miami shows **SELECTED with NO red "not compatible" triangle** ⇒ the compat SET was reconfigured.
     Now **leave the screen and come back:**

   | After leaving + returning | Verdict |
   |---|---|
   | Miami / Gunfight **HELD** | ✅✅ **the joinable solve** — the lobby genuinely holds an off-compat map. Confirm with the joiner (Test-3 step 3): if they load Miami/Gunfight cleanly, **pregame lobby control is SOLVED**. |
   | reverted to a compatible map/mode | it only set a field the UI overwrites — not a solve. Note it; the fallback is Test 1's frontend GSC route or Test 3's STAGE. |

---

## Test 3 — The STAGE route (already half-works)

`switchmap_load(map, gametype)` with no `switchmap_switch()` **stages the lobby's next map**. Proven
host-side; the open question is the **joiner**.

1. In a live **Gunfight** match: app → **Actions → Stage for lobby (next match)** with a map + gametype
   (or the in-game menu's "Stage for lobby - next match"). The Log shows `staged ...`.
2. **End the match** (finish it, or restart to the lobby). The pregame lobby's summary header should now
   show the **staged** map/mode.
3. **Joiner test** — have the friend join now:

   | Joiner sees | Verdict |
   |---|---|
   | the staged map/mode, loads the next match cleanly | ✅ STAGE gives **joinable pregame control** — the practical solve available today |
   | a different map, or crashes on the staged one | STAGE is host-only cosmetic; needs Test 1/2 |

---

## Record the results here

| Test | Result | Verdict |
|---|---|---|
| 1 · frontend GSC (probe 50 / 52) | | |
| 2 · lobby-set red-triangle (held?) | | |
| 3 · STAGE + joiner | | |

**Any win closes roadmap #1** and gives the app a real pregame layer (drive the frontend, not just the
match). Update [[pregame-routes]], [[map-native-lobby-call]], and [[roadmap]] with whichever landed.
