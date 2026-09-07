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

This repo holds the reverse-engineering notes, the fix design, and the test plan.

## Status

Research phase. Nothing built yet. The findings are documented against the decompiled T9 source
([`ate47/bocw-source`](https://github.com/ate47/bocw-source)) with file and line references.

Headline results so far:

- **Map restriction is a data dependency, not a whitelist.** Gunfight aborts init when a map lacks
  `gunfight_zone_center` entities. Spawns are not a problem, the mode uses TDM spawn points.
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
