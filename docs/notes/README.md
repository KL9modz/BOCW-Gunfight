# Notes index

Single-incident deep dives. One file per finding. `.claude/CLAUDE.md` links here with `[[slug]]`,
which resolves to `docs/notes/<slug>.md`.

These are **not** auto-loaded. Open the one you need.

## Index

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

**The Gunfight findings**

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

## Conventions

- One finding per file, named `<slug>.md`, same slug as the `[[link]]` that points at it.
- Lead with the conclusion, then the evidence, then the file/line references.
- Record **dead ends** as their own notes. A dead end that isn't written down gets re-researched.
- Cite `bocw-source` paths in full, e.g. `scripts/mp_common/gametypes/gunfight.gsc:1137`.
- ⚠ The dump is a merge across game patches. Line numbers drift between dump revisions. Quote the
  surrounding code, not just the line number.
