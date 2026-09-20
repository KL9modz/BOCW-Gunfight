# App feature test — 2026-09-18 (autonomous run 2, bocw session 9533bc23)

Driver: `tools/gf-control` real App methods exercised head-less
(`scratchpad/drive.py`), verified by PrintWindow screenshots + read-only
`roster_scan`/`config_scan`/`mapdata_scan` memory sweeps. Game pid 17576
(launched 19:22), payload on disk `payloads/gunfight_menu.gscc` 391,566 B
(454705d). Map at test time: `mp_satellite` / gunfight_3v3 (West Riverbed).
Live config had **gf_vehmode=1** (motorcycles) already set — not by me.

## PASS (evidence captured)
- **Config readback / Load current** — `config_scan` returns full live config
  (tick advancing, ~0.6 s); app "Load current" read 72 fields. ✓
- **Roster / Connected → Refresh** — `roster_scan` + app path both list host+bots. ✓
- **Bots: Fill / Remove all** — bridge → roster 1→8 / 8→1. ✓ (single add/remove/even
  still masked by the lobby's native Bot Fill — F2, unchanged.)
- **Third person** (host) ✓ · **Max ammo** (28→168 reserve) ✓ · **Give weapon** (XM4 in
  hand + HUD) ✓ · **Drop weapon** ✓ · **Camo id 61** (guns turned gold) ✓ ·
  **Operator id / Outfit id** dispatch ✓ (model swap subtle in TP) · **Fly / God mode /
  Unlock all** dispatch ✓.
- **Broadcast: Centre** (colour code honoured) ✓ · **Feed** ✓ · **Announce settings**
  (both HOST lines) ✓ · **Countdown 5..GO** (centre digits) ✓.
- **Pause / Resume** — TIMEOUT overlay + "MATCH STARTING IN 5 / resume" countdown ✓.
- **Apply now — scoped path is reload-free.** Bare `apply none` on a **frozen** 8-bot
  baseline did NOT restart (roster intact, no splash); a 12 s pure frozen baseline held.
  Source confirms `cmd_apply_live("move")` = `mod_movement()` only and `mod_movement`
  + `cfg_load` are fully passive (no `setgametypesetting`/`map_restart`). ✓

## Apply-now "restart" — investigated, NOT a real bug (confound)
`apply move` (gravity) was once followed by a "MATCH STARTING IN 5" splash + roster
8→1. But: (a) the build is confirmed scope-aware (`apply none` didn't reload — a stale
ab158d1 build would have), and (b) every code path in that apply is passive. The reload
was the documented **frozen-bot round-end confound** — a bot that respawned *after* my
`freeze` command (fresh fill) was unfrozen and scored an elimination, ending the round.
⚠ Method fix for next run: after `fillbots`, wait for the fill to finish, THEN `freeze`,
THEN re-read roster twice before any apply — so no late bot is unfrozen.

## BLOCKER — game crashed mid-run (~20:00:13)
`BlackOpsColdWar.exe.17576.dmp` (292 MB), **EXCEPTION_ACCESS_VIOLATION 0xc0000005** at
`0x7ff7511c2180` — **not inside any loaded module** (script-VM / heap region), so a
GSC-VM-side fault, not stock engine. Happened during rapid apply/reload/refill cycling
(several confounded round-restarts in a few minutes) with gf_vehmode=1 live on a
vehicle-less map. 5 crash dumps already exist today (14:57, 15:24, 16:30, 18:20, 20:00) —
this build is crash-prone; the peer's `cwpatch-spinner` note is a parallel instability lead.
Vehicle-mode spawn path is null-guarded (no-asset map → early return), so it is a
secondary suspect, not confirmed. Faulting thread's GSC frame not resolved (non-module addr).

## Still UNTESTED (blocked by the crash — need relaunch + reinject)
Teleport hub (all/team/enemy/me/save/gun/grenade + per-player) · per-player verbs
(god/ammo/third/fly/kill/take/strip/kick/speed/move/spectate/freeze/tp) · map toys
(destruct/exploder/projectiles/props) · Vehicles page (spawn/enter/clear) · Spawns
(guard/family/pick/gap/antistack) · Session switch (stage / switch NOW) · Overtime zone ·
Pool camo over rounds · Loadout sets · Next-round restart-required dialog + gating ·
+ Restart button.

## Next
1. klaze relaunch game → load a private Gunfight match once → app Inject/Status
   "Set up all" (bridge + menu) → restart to link.
2. Turn **gf_vehmode 0** for the feature sweep (isolate it), test it deliberately later.
3. Re-run the sweep with the corrected freeze method; nail the Apply-now question with
   one clean `apply move`; then the untested blocks above.

---

# Run 2b (relaunch, pid 23412, map mp_raid_rm / Garden, gunfight_3v3)

Added a precise reload detector: the **MATCH debug line** (`gf_dbg_match`, F1 fix CONFIRMED
working) prints `... | R<n> <a>-<b> | 4v4 A=..(..b) X=..(..b) | ...` — the round number `R#`
and the A=/X= team counts read in one screenshot. Method fixed: fillbots → wait 9 s → freeze →
verify roster twice.

## More PASS
- **F1 debug feed WORKS now** — `MATCH gunfight_3v3/mp_raid_rm session | R1 0-0 | 4v4 ...` renders
  (the packed-store desync is fixed in this build). ✓
- Re-confirmed third person / camo / give / broadcast(centre,feed) / announce / countdown /
  pause-resume on the fresh launch.

## ⚠ Banner (broadcast loc 2) did NOT render
`say ... loc=2 Fixed` set the persistent hint banner; it did not appear on screen across two
captures over ~14 s (centre + feed broadcasts DID render). Needs a look — `broadcast_hint_make`
spawns a per-player `trigger_radius` + `sethintstring`; may not be drawing host-side, or the
use-prompt widget is suppressed while holding a weapon. Note as "did not provide expected result".

## 🔴 Apply-now RELOAD — real via the app, NOT via the identical bridge command (UNRESOLVED)
Rigorous, frozen-baseline (10 s pure hold = stable, R1 4v4) results:
- **App `_apply_live` (gravity, scope=move): reloads the match 5/5** — "MATCH STARTING IN 5" +
  spawn-guard diag + NEW LOADOUT, roster 8→1, on a provably stable baseline.
- **The IDENTICAL bridge message sent raw: does NOT reload 6/6** — incl. the full payload
  `set gf_oob 0 / gf_c2 / gf_c3 / gf_c5 / gf_c7 / apply move`, byte-for-byte what the app sends.
- Bare `apply none`, `apply move`(no chunks), each single chunk alone → all no-reload.
- Instrumented the app: it sends exactly ONE bridge message = the same bytes. Its only extra
  step is `_sync_untouched` → `config_scan.read_config` (a **read-only** VM_READ sweep) +
  `find_game_pid`. Both scanners verified pure read-only (no WPM / no CreateRemoteThread).
- The injected payload (391,566 B) contains all current-build tell-tales → NOT a stale build.
- GSC side: `cmd_apply_live("move")` = `mod_movement()` only; `mod_movement`, `mod_oob_apply_all`,
  `mod_falldamage_apply`, `cfg_load` are ALL passive (no `gts_set`/`map_restart`). No config watcher.

⇒ By code the app apply CANNOT reload, yet it does 5/5 while the identical bridge bytes don't.
Prime remaining suspects (need a targeted test, not more blind reloads): (a) the app's background
threads (3 s status tick doing OpenProcess/QueryFullProcessImageName + the config_scan worker)
running **concurrently** with the bridge send; (b) a read-then-send timing/state interaction.
Clean next test (one shot): `config_scan.read_config()` THEN raw `bridge_channel.send([...])` in a
single script on a frozen baseline — if THAT reloads, it's the read-before-send interaction; if
not, it's the App's concurrent threads.

## 🔴 Secondary but real: the app OVER-SENDS gts-bearing chunks on every apply (F4 not fully fixed)
`_is_changed(dvar,val)` returns true when `val != app_hardcoded_default`. This game's live
`strike=1` (def 0), `roundwinlimit=0` (def -1), `timer=0/60` differ from defaults, so **gf_c5 and
gf_c7 (which carry roundwinlimit / team_size / timer / strike) are re-sent on EVERY apply**, even
one that only touched gravity. `_sync_untouched` does NOT prevent this — it syncs the *value* but
`_is_changed` still fires because live ≠ hardcoded default. Fix (app-only, no payload): compare
against the LIVE/`_applied` value, not the default — send a chunk only if a field in it genuinely
differs from what the game currently holds. (Note: raw-sending those chunks did NOT reload, so this
is contamination/inefficiency, not proven to be THE reload trigger — but it's wrong regardless.)

## 🔴 STABILITY: two crashes under reload cycling
Game crashed twice (access-violation, script-VM region) after ~10-12 rapid map_restart-class
reloads from the app applies. The build is fragile under repeated fast reloads. STOP driving
reload-inducing applies in a tight loop until the reload cause is fixed.

## 🔴🔴 Crash signatures tie Apply-now to a DETERMINISTIC crash
Three crashes this session, access-violation each:
- pid 17576 (20:00) `0xc0000005 @ 0x7ff7511c2180` — after Apply-now reload cycling
- pid 23412 (22:01) `0xc0000005 @ 0x7ff7511c2180` — **SAME address**, after Apply-now reload cycling
- pid 9140  (22:12) `0xc0000005 @ 0x7ff74d284de2` — DIFFERENT addr, smaller dump (82 MB vs 279),
  hit while the game was on a menu/coordinates screen (NOT a live match) as I sent fill/freeze —
  firing match verbs outside match context (bb.gsc cmd_poll not in a match VM) is its own hazard.
Two identical fault addresses across two separate launches = the Apply-now reload path deterministically
crashes the engine at a fixed instruction. So the app Apply-now is not just a nuisance reload — repeated
use reliably crashes. ⇒ Treat Apply-now (the config-chunk apply path) as actively harmful until fixed;
run the remaining feature sweep with ACTION VERBS ONLY (teleport/map-toys/vehicles/per-player), never a
config apply, and only inside a live match.

## 🔴🔴🔴 Run 2c — the build is too unstable to live-drive; STOPPED after crash #4
Relaunched into a Moscow/Miami **TDM** match (klaze; not Gunfight). Findings:
- fillbots eventually populated 4v4 (delayed); roster/broadcast channels work.
- Host-targeted verbs (thirdperson/fly/move) appeared to no-op — because the **AFK host kept
  dying to the active bots and was SPECTATING** (verbs check `isalive`). TDM with an idle host is
  not a testable environment; the Gunfight freeze-everyone baseline (run 2b) was the controllable one.
- Attempted a **session switch TDM→gunfight_3v3 on mp_garden** to get a controllable Gunfight match.
  It **CRASHED the game** (pid 30332 dump @22:32). do_session_switch (switchmap_load) is a level
  transition and this build crashes on heavy transitions.

**Four crashes in one session** (20:00, 22:01, 22:12, 22:32), all access-violation; the two after
Apply-now cycling share a fixed fault address (deterministic). **Conclusion: the current LIVE build
(454705d, 391,566 B) is crash-prone under any heavy operation — the app's config Apply-now, a session
switch, or commands fired during a transition. Live-driving the remaining sweep is not feasible until
this is stabilised.** Recommend: address the Apply-now reload/crash + investigate the transition
crashes on a build BEFORE resuming the feature sweep, rather than relaunch→crash repeatedly.

## 🎯 ROOT-CAUSE LEAD: 3 of 4 crashes share fault addr 0x7ff7511c2180 = the vehicle-teardown crash
- Apply-now cycling crash #1 (20:00): `0x7ff7511c2180`
- Apply-now cycling crash #2 (22:01): `0x7ff7511c2180`
- **Session-switch crash #4 (22:32): `0x7ff7511c2180`** ← SAME address
- (crash #3, menu-state fill/freeze, was a different addr 0x7ff74d284de2)
The common factor across Apply-now-reload and session-switch is a **LEVEL TRANSITION**, and
**gf_vehmode was live = 1 (motorcycles) the entire session** (config_scan showed it on the first
baseline; something sets it on launch). This is exactly [[vehicle-mode]] / [[map-toys-build]]'s
documented **vehicle-teardown crash**: a menu/mode-spawned vehicle that outlives a level teardown
faults at a byte-identical signature. `veh_sweep_for_transition` hooks stage/switch/carry/restart +
the round-end sweep — but the Apply-now "reload" is a map_restart-class event that path may NOT hook,
so a vehmode vehicle survives it → crash. And the session switch crashed too (a vehmode vehicle spawned
during / surviving the transition).
⇒ **HYPOTHESIS (high confidence): the crashes are the vehicle-mode teardown crash, triggered by
gf_vehmode=1 during transitions — NOT an inherent Apply-now/session-switch flaw.** Testable: with
gf_vehmode=0 (and the sweep covering every reload path), Apply-now and session-switch likely stop
crashing. The Apply-now *reload* (5/5, app-only, unexplained) is a SEPARATE, lower-severity issue.

## Fix priorities (for the "address them after" pass)
1. **gf_vehmode must default OFF and be OFF for normal play** — it was live=1 all session (find what
   sets it on launch; app default + GSC default should both be 0). This is the likely crash trigger.
2. **veh sweep must cover the Apply-now reload path** — whatever map_restart-class event Apply-now
   triggers needs `veh_sweep_for_transition` before it (like the other transitions).
3. **App over-send (F4 residue): `_is_changed` compares to hardcoded default, dragging gts chunks
   into every apply.** Compare to the live/`_applied` value instead. App-only.
4. **Apply-now reload paradox** — app reloads 5/5, identical bare bridge 0/6; unexplained; lower
   priority than the crash. Clean test: config_scan.read_config() then raw bridge send in one script.

## ✅ FIXES MADE (2026-09-18, staged — UNVERIFIED in-game, game was down)
1. **App over-send (gf_control.py `_is_changed`)** — now compares to `_applied` (the live baseline
   `_sync_untouched` refreshes), not the hardcoded default, and drops the sticky `_sent`. **Verified
   offline:** a gravity-only Apply-now sends ONLY `gf_c3` (movement) — no longer `gf_c5`/`gf_c7`
   (roundwinlimit/team_size/timer/strike) or `gf_oob`. Kills the F4 packed-chunk contamination.
   Takes effect on an app restart (gf-control.cmd). Backup: gf_control.py.pretestfix.bak.
2. **GSC apply-path vehicle sweep (gunfight_menu.gsc `cmd_apply_live`)** — `veh_sweep_for_transition
   ("apply")` (guarded on `veh_count_tagged()>0`) so the Apply-now path clears menu-spawned vehicles
   like the other transitions do. Compiled + header-stripped to `payloads/gunfight_menu.gscc`
   (391,642 B, 2225 str, current-build tell-tales present). Backup of the prior live 454705d:
   `payloads/gunfight_menu.pre-applysweep-454705d.bak.gscc`. Needs a reinject (Set up all).

### ⚠ Residual gaps (honest)
- **Occupied-vehicle sweep gap:** the session-switch crash happened DESPITE its sweep because with
  vehmode ON the vehicles are OCCUPIED ("could not remove"); my apply sweep has the same limit. So
  the sweeps are not a complete fix while vehmode is on. **Reliable unblock: run with gf_vehmode=0**
  (no vehicles spawn → nothing to survive a teardown). vehmode's default is already 0 — it was set
  to 1 externally this session.
- **Apply-now reload mechanism still unexplained** (app reloads 5/5, identical raw bridge 0/6; app's
  only extra step is a read-only config sweep). The over-send fix may or may not stop it — needs the
  one-shot `config_scan.read_config()` + raw `bridge_channel.send()` test.
- **Zone entities (gf_zone=1) are a secondary teardown suspect** (not swept on transitions).

### ▶ To resume the sweep (klaze)
Restart the control app (picks up fix #1) → relaunch game into a live **Gunfight** match → Set up all
(injects fix #2) → **set gf_vehmode 0** (and consider gf_zone 0) → I run the action-verb sweep.
