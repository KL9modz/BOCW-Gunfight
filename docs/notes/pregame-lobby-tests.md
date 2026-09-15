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
| 1 · frontend GSC (probe 50 / 52) | ✅ **PASS 2026-09-14** — GSC runs in the lobby; a `maxplayers` write from the lobby carries into the match | **read + write + carry all confirmed** |
| 2 · lobby-set red-triangle (held?) | ❌ **NEGATIVE 2026-09-14** — setters resolve, but calling them from a remote thread doesn't drive the lobby and hangs match start | **native-setter route via `CreateRemoteThread` doesn't deliver; STAGE remains** |
| 3 · STAGE + joiner | | |

### Test 2 — full result (2026-09-14, klaze). The setters are real; the *method* doesn't land.

The scan is clean and repeatable across relaunches: `LobbySetGameType` @ `module+0xae4b730`,
`LobbySetMap` @ `module+0xae4b810`, the call-site and prologue signatures **agree** on LobbySetMap, and
the two sit **0xe0 apart** (BO4 has them 0x10 apart — same jump table). ate47's signatures resolve on
this CW build with high confidence, and both targets have MSVC function-entry shape. So the addresses
are not in doubt.

What the three calls did:

| Call | timeout | result | lobby |
|---|---|---|---|
| `LobbySetGameType(0,"gunfight")` | 5s | **returned** | no visible change (lobby was already Gunfight) |
| `LobbySetMap(0,"mp_miami")` (off-compat) | 5s | **TIMED OUT** (hung) | game stayed up; map unchanged |
| `LobbySetMap(0,"mp_sm_market")` (compatible) | 15s | **returned** | **map row did NOT update**, then **hitting Play HUNG the game** |

▶ **The Play-hang is the finding.** LobbySetMap is *not* a no-op — it wrote enough underlying state to
**break the match load** — but it did **not** update the visible map row, and the loader then choked on
the inconsistent lobby. Clicking a map row in the UI drives the LUA/session model, the dependent map
fields, and these C++ setters *together*; calling the two C++ functions alone from a remote thread
leaves the lobby **half-set** — invisible to the UI, fatal on start. The functions are **lower-level
than the row-click handler** and (LobbySetMap on the large off-compat Miami) also appear to want the
main UI thread, hanging when hijacked onto a `CreateRemoteThread`.

⇒ **The native-setter route does not give pregame map control via this injection method.** Measured,
reproducible (Play hangs), no longer "untried". A *different* approach — calling the higher-level
row-click handler that updates everything, or driving it on the UI thread — is a separate, unbuilt
investigation. **Untried — not ruled out:** that higher-level handler; setting on the UI thread (APC /
hook) rather than a fresh remote thread.

**Tool changes made this session** (`tools/lobby-set.py`, all in the Python app / agent lane): forced
UTF-8 output (a `✓`/`⚠`/`→` print was crashing on the cp1252 console — and would have crashed the write
path before the setter call); on a thread **timeout the stub+string are now leaked, not freed** (freeing
them under a still-running thread is a use-after-free that can itself wedge the game); added `--timeout`
to tell a slow setter from a deadlocked one.

**The map route stays STAGE (Test 3)** — `switchmap_load` staging the lobby's next map, proven
host-side; the joiner is its open clause.

### Test 1 — full result (2026-09-14, klaze, read via held on-screen summary)

The probe's in-match readout was rebuilt from 13 coded numbers (one every 5 s into the 4-line feed —
probe 52 emitted 9th at ~48 s and a ~40 s round always ended first) into **two plain-text lines held
centre-screen, alternating every 3 s** (`iprintlnbold`; free text there is SAFE — it is the stock
"match starting" print — unlike LUIelemText/hint-panel free text, which crashes: [[lui-elem-route]]).
Screenshot-legible. `test_frontend.gscc` = read-only, `test_frontend_maxp.gscc` = writer.

**Controlled pair, same 3v3 Gunfight lobby, only `write_maxplayers` differs:**

| Run | wrote in lobby | `lobby.max` (frontend read) | `match.max` (match start, before any in-match write) |
|---|---|---|---|
| read-only | — | **6** (native 3v3) | **6** |
| writer | `setgametypesetting(#"maxplayers",8)` each sample | **8** | **8** |

- **GSC runs in the pregame lobby** — samples 10–68 over ~100–680 s (probe 50). Closes "nothing runs
  there" for good.
- **The frontend store is the real pending config, not a default** — read-only `lobby.max=6` == the
  match's `match.max=6`, and `time=40` matched too.
- **A frontend `maxplayers` write carries into the match** — writer `lobby.max` read back 8 (write
  stuck) and the match *launched* at `match.max=8`. The in-match half only reads, so the 8 is the
  carried pregame value, not an in-match write. Same store the match starts from.
- ✅ **This DIRECTLY MEASURES the mechanism the 2026-09-09 P2 run could only infer.** That run confirmed
  the *behaviour* — klaze seated a 4th bot per side and played **4v4** (HUD: 4 icons/side, [[pregame-routes]]
  P2 RESULT) — but its probes **59/60 were never captured**: the 5s-spaced 13-probe emit chain never
  reached them before the ~40s round ended, so "the write carried" rested on behaviour, not a number.
  The held readout removes the round-truncation problem, and `match.max=8` is that missing number. Same
  for probe 50 (samples, uncaptured 09-09) and the native-vs-written `lobby.max` pair.
- ⚠ **Still open: the human joiner.** Bots-to-4v4 from the lobby is confirmed (09-09); a human 4th
  *joining* a pregame lobby configured this way is untested. **Untried — not ruled out.**
- Side findings: `flags=63` (frontend·private·mp·online·players·host — fully-formed private lobby);
  `cmc` (com_maxclients) reads **2** in the lobby, not populated to the match value until the match
  spins up; **`dbg=4`** = `adddebugcommand` is **nulled in the match** (console-from-script dead
  in-match, like BO4) — closes the "fire a console command from script" map lead.

**⇒ The write test (old P2) is the pregame team-size solve at the setting level.** Next: seat a 4th in
the lobby / fill bots to 4v4 (bodies), then the joiner. The app can drive this by writing `maxplayers`
from the lobby via the bridge instead of waiting for the match.

**Any win closes roadmap #1** and gives the app a real pregame layer (drive the frontend, not just the
match). Update [[pregame-routes]], [[map-native-lobby-call]], and [[roadmap]] with whichever landed.
