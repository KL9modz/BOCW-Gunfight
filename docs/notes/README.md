# Notes index

Single-incident deep dives. One file per finding. `.claude/CLAUDE.md` links here with `[[slug]]`,
which resolves to `docs/notes/<slug>.md`.

These are **not** auto-loaded. Open the one you need.

## Index

**Start here if you are at the machine**

- [gamesettings-catalog](gamesettings-catalog.md) — **all 427 rules-menu rows**, with the setting each
  writes, what it publishes, and what it **hides**. 184 rows offer the menu fewer values than the
  setting accepts.
- [gametype-settings-map](gametype-settings-map.md) — **which of the 463 gametype settings the menu can
  reach, and which it cannot.** Establishes **hashed ⇒ hidden** (0 of 236 hashed keys has a menu row),
  cracks `gunfightloadoutindex` (snipers-only / melee-only Gunfight for one call), finds the value
  `gunfight_spy_plane` hides, corrects the join-gate citation and its missing second check, and flags
  the one setting that can break Route A.
- [lobby-map-dll](lobby-map-dll.md) — **an auto-loading DLL that picks the Gunfight map from the
  lobby.** Kills `acts cwdllgt` twice over (the proxy crashes *and* the exports are absent from ACTS
  master), then lays out the route that does work: cwpatch already runs arbitrary console commands
  from the one slot that loads, so the only open question is which command — and `acts dcfuncscw` plus
  `tools/crack-cmds.py` answers it before any C gets written.
- [lobby-settings](lobby-settings.md) — **the pre-match layer**: which step of hosting lives where, why
  `frontend.gsc` is not the lobby, and `scriptbundle/gamesettings/` — 427 JSON bundles that are the
  complete rules-menu surface. Carries the cheapest open lead in the project: a **Max Players** row
  publishing 1–12.

- [compile-status](compile-status.md) — stages 1–2 on the Windows gate. All five staged tests compile;
  with the cloud session's stages 3–4 and arity checks, every offline check is green. Carries the
  provenance caveats: relayed, and the ACTS version is unrecorded.

- [test-queue](test-queue.md) — **every open test, on one sheet, ordered by risk**, with record slots.
  Aggregates the untried items from every other note so a session at the test box does not have to
  read five files to find the next thing to run.

**Getting running**

- [setup-new-pc](setup-new-pc.md) — bootstrapping the dev toolchain on a new machine. What travels
  with the repo, what must be re-verified locally, and the prerequisites list.
- [test-pc-setup](test-pc-setup.md) — headless closet test box over RDP: reachability, RDP tuning,
  the Activision-account trap, the toolchain mirror, and the ACTS auto-update gotchas.
- [toolchain](toolchain.md) — compiling and injecting with ACTS. `gscc` / `injectcw` invocations,
  the script skeleton, hook scripts per mode, and two gotchas that cost real time.
- [testing](testing.md) — the four test layers, from the offline harness that needs no game up to
  Gunfight on a normal map.
- [phase-0-1-test-protocol](phase-0-1-test-protocol.md) — step-by-step protocol for the Phase 0 and
  Phase 1 tests. Not a finding yet: it carries a **Results** section that gets filled in on the run,
  at which point it becomes the finding record for both gates.
- [mp-load-path](mp-load-path.md) — how injected GSC reaches the **MP** Gunfight VM. Verified against
  dump `edd94bd`: additive `autoexec` / `event_handler` / `callback` registration, no detour needed.
  One residual unknown — whether the injector honors injected registration — with a hello-world for it.
- [pipeline-toolchain-survey](pipeline-toolchain-survey.md) — the six commonly-cited tool/mod repos,
  checked in-session. Which help the compile→inject pipeline (two do), which are dead or closed, and
  where the MP hook point (`mp_common/bb.gsc`) and the injector load model came from.

- [mp-dvars](mp-dvars.md) — which dvars actually take effect in MP and which set cleanly and do
  nothing. `jump_height` is inert in MP; `bg_gravity` works, and why. Carries the do-not-use list of
  functions absent from T9, and the closed-loop trap: reading back a value you wrote proves only that
  the write landed. **First confirmed gameplay modification, VERIFIED in-game 2026-09-07.**

**The Gunfight findings**

- [menu-map](menu-map.md) — the **Atian Menu**: the map carry that puts Gunfight on any of the
  offered maps, the confirmed end-to-end procedure (3v3 Gunfight on Zoo, 60s rounds), the three traps,
  and what the walk settled. Carries an **Untried — not ruled out** list; nothing there is closed.
- [dump-cross-check](dump-cross-check.md) — **the A0 grep, run against the alternate dump.** Two
  retractions (`gunfight_3v3` is not there; `setteam` is an entity function) and one opening: the
  per-team cap resolves to `com_maxclients`, so **nothing in team assignment enforces 3-per-team**.
  Changed three scripts before they were injected.
- [cw-builtins](cw-builtins.md) — survey of ate47's **Cold War builtin table** (4,481 functions with
  binary addresses). Four player-count builtins where this project used one; `isvalidgametype()` to
  test a gametype string with zero risk; `addtestclient()` for the bots the test plan always assumed;
  `setteam()` for the 4v4-from-8-slots idea; `map_restart()` which may drop the cwpatch dependency.
  Carries a seven-test staged plan ordered by risk.
- [atian-menu-source](atian-menu-source.md) — source survey of that menu. **`func_set_gametype()`
  already exists in the Cold War tree and is simply never wired into the menu.** The two builtins it
  uses are confirmed present in `BlackOpsColdWar.exe`, so `gunfight_mod` can call them directly —
  which makes the larger-team question a cheap live test rather than a blocked one.
- [gunfight-findings](gunfight-findings.md) — the one hard map dependency (`gunfight_zone_center`),
  why it is almost certainly the round-timer bug, and why a *partial* zone setup is worse than none.
- [team-sizes](team-sizes.md) — where team size actually lives, what is overridable from GSC and
  what is a hard engine ceiling.

**Risk and disclosure**

- [tac-risk-model](tac-risk-model.md) — threat model and **participant disclosure** for the mod: where
  TAC and server telemetry can observe it, host vs joiner. Risk identification, **not** evasion.

**DLL-level tooling** (not GSC — separate track)

- [dll-proxy](dll-proxy.md) — forcing gametype/map with the `powrprof.dll` proxy, and why
  LoadLibrary injection does not work for it.
- [unlock-dlls](unlock-dlls.md) — the two unlock DLLs pulled apart: the dvar `loot_fakeall`, F4
  `lobbylaunchgame`, why `BlackOpsColdWar.exe` cannot be signature-scanned at rest, and the loader
  shim in `tools/cw-loader-shim/` that merges both into the one usable DLL slot.

## ⚠ Use the dump for mechanism. Use external sources for anything player-facing.

The dump has **no display names, no localization table, and no map metadata.** It cannot resolve a UI
name to a codename, ever. Two sessions spent several exchanges arguing over whether "ICBM" was one of
the nine `mp_sm_*` maps — reasoning from asset-token frequencies, conceding, re-arguing — and a single
web search answered it in one step. ICBM is a Season One Gunfight-exclusive map; `mp_sm_central` is
its codename.

Both of us kept reaching for the dump because it was the tool in hand, on a question it was
structurally incapable of answering. The split to remember:

- **Dump** — function signatures, call sites, control flow, entity targetnames, gametype settings.
  Anything the engine or script actually consumes.
- **External** — map display names, release seasons, which modes ship where, playlist composition,
  player-visible behaviour. Anything a person sees in a menu.
- **The game itself** — anything conditional on session or playlist state, which is invisible to both.

## Conventions

- One finding per file, named `<slug>.md`, same slug as the `[[link]]` that points at it.
- Lead with the conclusion, then the evidence, then the file/line references.
- Record **dead ends** as their own notes. A dead end that isn't written down gets re-researched.
- Cite `bocw-source` paths in full, e.g. `scripts/mp_common/gametypes/gunfight.gsc:1137`.
- ⚠ The dump is a merge across game patches. Line numbers drift between dump revisions. Quote the
  surrounding code, not just the line number.
