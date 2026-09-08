# BOCW-Gunfight

Research and tooling for running a modified **Gunfight** gametype in Call of Duty: Black Ops Cold War
**private/custom matches**.

## Goal

Stock Gunfight imposes three restrictions that make it unusable for the intended community lobbies:

| Restriction | Stock | Wanted |
|---|---|---|
| Map selection | ~10 curated maps | any map |
| Team size | 3v3 | 6v6 |
| Round timer | 40s, not editable in the rules menu | tunable |

⚠ Two rows of that table are now known to be imprecise, both measured in-game 2026-09-07:

- **Team size** — `com_maxclients` measured **8**, which is **not a ceiling**: 3v3 Gunfight = 6
  players + 2 spectators. The probe read a *lobby config*. ⚠ An earlier note here claimed "4v4 is
  already reachable" — that treated a playlist value as an engine limit. **Disregard it.**

  These same maps do run **Faceoff 6v6** with twelve clients stock — but **in matchmaking, not
  private matches**, and this project is private-only. So 6v6 is not already available within scope.
  What it proves is narrower and still useful: the engine and those map files support twelve clients,
  so the ceiling is neither an engine limit nor a map property — it is the private-match UI declining
  to offer a twelve-client mode on them. The task is getting a *private* lobby configured for twelve
  to run Gunfight: [`docs/notes/team-sizes.md`](docs/notes/team-sizes.md).
- **Round timer** — ✅ **the setting is live, readable, and menu-settable.** Measured **0** in one
  lobby and **30** in another. `gettimelimit()` divides it by 60 (`gunfight.gsc:1139`) and the clamp
  bounds are minutes, so the value is stored in **seconds**: `0` = no limit, `30` = 30-second rounds.
  Both are published menu values, which answers Phase 0 **T0.2** affirmatively — the rules menu *does*
  expose the timer across `0 / 20 / 30 / 40 / 50 / 60`.

  ⚠ An earlier note said this setting "is not where the 40s comes from" and advised re-scoping
  `timer_override`. **That came from a single lobby that happened to read 0 and does not survive a
  second sample. Disregard it.** `timer_override` targets the right setting; it is only *needed*
  above 60s, exactly as `src/gunfight_mod/`'s config comment already said.

  ⚠ **The crash hazard is now live.** With a non-zero timer on a zoneless map the round timer can
  actually expire, reaching `ontimelimit()` → `overtime()` → `level.zones[0]`. Both clean test
  matches so far ended by elimination. Since *every* stock map reads zero zones, this is reachable in
  ordinary custom play — and it is exactly what `timelimit_fix` exists to prevent.

This repo holds the reverse-engineering notes, the fix design, and the test plan.

## Status

Research phase. Nothing built yet. The findings are documented against the decompiled T9 source
([`ate47/bocw-source`](https://github.com/ate47/bocw-source)) with file and line references.

Headline results so far:

- 🪦 **DEAD END — `gunfight_zone_center` is not the map gate.** This file used to lead with "Gunfight
  aborts init when a map lacks `gunfight_zone_center` entities." Every part of that is now
  contradicted, measured in-game 2026-09-07 with [`src/mp_probe/`](src/mp_probe/):

  | Stock Gunfight map | zone entities |
  |---|---|
  | ICBM (`mp_sm_central`) | **0** |
  | Amsterdam (`mp_sm_amsterdam`) | **0** |

  It does not abort — `setupzones()` returns false and `onstartgametype()` takes a plain early return
  (`gunfight.gsc:119-121`), skipping only its presentation tail; `abort_level` is never called from
  `gunfight.gsc`, and **the match runs**. And a condition that is true on *every* stock map cannot be
  what distinguishes ten maps from the rest. **Do not re-open this line of investigation.**

  ⚠ Scope: measured in **private/custom** matches only. The entities plausibly do exist in matchmade
  Gunfight — that is how the shipped overtime feature works — which points at session/playlist-level
  entity filtering. Neither machine can see that from script.

- ⚠ **Consequently, custom Gunfight is ALWAYS running degraded**, on every map, stock or not. That
  makes `gunfight_mod`'s `zones_guard` and `presentation` switches the things that make custom
  Gunfight *correct at all*, not polish for modded maps.

- **So both headline goals rest on one mechanism.** Nothing in `gunfight.gsc` blocks Gunfight on an
  arbitrary map — it demonstrably runs to completion with zero zones, twice. The barrier is the
  menu/playlist layer choosing which maps are offered, which is the same layer that configures a
  lobby for twelve clients. See [`docs/notes/dll-proxy.md`](docs/notes/dll-proxy.md).

- 🔓 **And the menu appears to be that mechanism — n=1, 2026-09-08.** A private match started as
  **Gunfight on Mansion** (a stock Gunfight 2v2 map) had its map switched **to Hijacked** from the
  in-game menu, and Gunfight loaded. Hijacked is a **6v6** BO2 remake added in Season Four and is not
  a Gunfight map. So Gunfight ran on a map its playlist does not offer, with **no GSC, no DLL, and no
  injector** — the job `cwdllgt` was blocked on.

  ⚠ **One report, and "it loaded" is not "it works."** Reproducibility, round flow, timer expiry and
  the player-slot count are all unmeasured. Hijacked is a twelve-client map, so the same lobby is
  also the untaken Phase 1 test. [`docs/notes/menu-map.md`](docs/notes/menu-map.md) holds the caveats
  and the measurement.

- **Spawns are not a problem** — the mode uses TDM spawn points.
- **The zone absence only bites when the round timer expires.** `ontimelimit()` threads `overtime()`,
  which dereferences `level.zones[0]` (`:944`). No timer expiry, no crash. That is why the zoneless
  match above survived: its `timelimit` setting read **0**, meaning no limit, so `overtime()` never ran.
- **The round timer is not hardcoded.** It reads a gametype setting and clamps to 1440 minutes. Only
  the menu caps it.
- **The health-based round decision already exists in stock.** It does not need to be written.
- **6v6 is not script-reachable.** It resolves to `com_maxclients`, which script only ever reads.

See `.claude/CLAUDE.md` for the full picture, including a confirmed dead-ends list.

## Layout

```
.claude/CLAUDE.md       agent operating manual: findings, fix design, test plan
docs/notes/             per-finding deep dives — start at docs/notes/README.md
src/                    GSC source: hello_world/ proves the MP hook, gunfight_mod/ is the staged mod,
                        gunfight_tweaks.gsc is the smoke test. Build order: src/README.md
tools/check-gsc.ps1     offline validation harness
tools/cw-loader-shim/   C shim merging the two unlock DLLs into one game DLL slot (build.cmd, zig cc)
```

This repo is the **single** home for the project's notes. Everything that used to live in a
`.claude/` folder beside it was moved here on 2026-09-06.

Two large dependencies live **beside** this repo, never inside it — `tools/check-gsc.ps1` resolves
both via `$PSScriptRoot\..\..`:

```
<parent>/
├── ACTS/                 60 MB   compiler + injector (pin the version — currently v3.3.0)
├── bocw-source-main/    664 MB   decompiled T9 dump (721 MB on disk; stage 3 reads only
│                                 scripts/, 29 MB — the rest is dead weight if disk is tight)
└── BOCW-Gunfight/                this repo
```

```powershell
.\tools\check-gsc.ps1 .\src\gunfight_tweaks.gsc   # compile + round-trip + resolve every API call
```

Fresh-machine walkthrough: [`docs/notes/test-pc-setup.md`](docs/notes/test-pc-setup.md).

## Scope

Private matches only. No public lobbies, no matchmaking, and no anti-cheat evasion work.

⚠ **A branch name in this repo's history contradicts that line. The branch name is the part that is
wrong.** The GSC work was merged from a branch named `claude/anti-cheat-evasion-research-woypoy`, and
that name now sits permanently in `main`'s history via the merge commit. What the branch actually
contained is [`docs/notes/tac-risk-model.md`](docs/notes/tac-risk-model.md) — a participant-disclosure
document that opens by refusing evasion outright (*"It does not describe how to hide the injector,
defeat a detection, spoof hardware, or reduce detection probability"*) and holds that line throughout,
drawing it explicitly: *"Identifying where a tripwire is so people can decide whether to step is
disclosure; disarming it is not."* The scope statement above is accurate. Recorded here so anyone
auditing the history does not have to reconstruct it.
