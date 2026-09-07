# Setting up on a new PC

## What travels in OneDrive (no action needed)

These live in the project folder and sync:

- `ACTS\bin\acts.exe` + `data\` — the compiler/decompiler/injector. **VERIFIED** working at v3.1.0.
- `bocw-source-main\` — decompiled game source. This is the reference every
  file:line citation in these notes points at.
- `atian-cod-tools-3.1.0\` — full ACTS source tree (useful for reading how the
  tools work; not needed to run them).
- `check-gsc.ps1` — **moved into the git repo**, now at
  `BOCW-Gunfight\tools\check-gsc.ps1`. It resolves ACTS and the dump **two levels
  up** (`$PSScriptRoot\..\..`), so the repo must sit *beside* them, not elsewhere.
  Arrives via `git clone`, not OneDrive. Same for the smoke test, now
  `BOCW-Gunfight\src\gunfight_tweaks.gsc`.
- **These notes** — also moved into the repo (2026-09-06), at
  `BOCW-Gunfight\docs\notes\`. They arrive via `git clone` too. The workspace
  root keeps only a pointer `CLAUDE.md` and `.claude\settings.local.json`.

## What does NOT travel — re-verify on each machine

**1. The game install path.** On the machine these notes were written it was:

```
S:\SteamLibrary\steamapps\common\Call of Duty Black Ops Cold War\BlackOpsColdWar.exe
```

Find it on the new box:

```powershell
Get-ChildItem -Path C:\,D:\,S:\ -Filter BlackOpsColdWar.exe -Recurse -Depth 5 -ErrorAction SilentlyContinue
```

**2. `bocw-source-main` completeness.** The GitHub ZIP download of that repo has
arrived incomplete before — `scripts\` was missing entirely, which is the part
that matters. Check:

```powershell
Test-Path ".\bocw-source-main\scripts\mp_common\gametypes\gunfight.gsc"
```

If false, clone it properly instead of unzipping:

```powershell
git clone --depth 1 https://github.com/ate47/bocw-source.git
```

Source of record: `https://github.com/ate47/bocw-source.git`, branch `main`,
commit `edd94bd` (2025-08-09). Note `tables\` (294 MB), `vehicle\` and `video\`
were deliberately not synced — nothing in this project needs them.

**3. ACTS auto-update — now pinned.** Running `acts.exe` silently updates itself
and rewrites `ACTS\bin`. Seen twice: 2.18.0 → 3.1.0, then 3.1.0 → 3.3.0 *during* a
`check-gsc.ps1` run, where the update banner **replaced the compile output** and
the harness died at step 2 with `ROUND-TRIP FAILED (decompiler produced nothing)`.
The next run succeeded untouched. **That failure looks like a broken script and is
not one** — re-run once before debugging anything.

The off switch is `ACTS\bin\acts-updater.json`:

```json
{ "disabled": true, "timeDelta": 86400000, "lastCheck": 0, "forced": false }
```

**VERIFIED** — with `disabled: true` and a deliberately stale `lastCheck: 0` (which
should force a check), no update fired and the run compiled clean. It also leaves
`acts_update.zip` (~26 MB) and `acts-updater-tmp.exe` behind on a failed cleanup;
both are safe to delete.

Read the build from `ACTS\bin\version`, not the folder name —
`atian-cod-tools-3.1.0\` is a separate source tree and does not track it.

**4. `powrprof.dll` proxy** (only if you want to force gametype/map). It is a
per-machine change to the game folder and is deliberately **not** synced. See
[dll-proxy.md](dll-proxy.md) — and read the always-on caveat there before
installing it.

## Smoke test the toolchain before anything else

```powershell
cd "<project root>\BOCW-Gunfight"
.\tools\check-gsc.ps1 .\src\gunfight_tweaks.gsc
```

Expect `PASS`. If it fails at step 1 the compiler is broken; at step 3 you have
a bad API name. See [testing.md](testing.md).

## Prerequisites summary

| Thing | Needed for | Status on a fresh box |
|---|---|---|
| `acts.exe` | everything | syncs with project; **pin the version**, see above |
| `bocw-source-main\scripts` | API validation, research | syncs — but verify, see above |
| `BOCW-Gunfight\` repo | harness + smoke test | `git clone`, must sit **beside** `ACTS\` |
| Cold War installed | any in-game test | must be installed locally |
| Game **running** | `injectcw` | `injectcw` aborts instantly without the live process |
| `powrprof.dll` proxy | `cwdllgt` only | must be installed per-machine |
| Process Hacker | **nothing here** | see [dll-proxy.md](dll-proxy.md) |

---

## ⚠ The two machines' dumps are NOT the same — verified 2026-09-07

`bocw-source-main` differs materially between the dev laptop and the test box. This produced a real
wrong claim in session (see below), so check which machine a dump-based assertion came from.

| | dev laptop (OneDrive tree) | test box (`C:\bocw\`) |
|---|---|---|
| `.gsc` under `scripts/` | **1,175** | **1,175** — identical |
| total size | 229 MB | 664 MB |
| `tables/` | **absent** | 291 MB |
| `scriptbundle/` | 12 MB | 62 MB |
| `ddl/` | 143 MB | 146 MB |
| git | **not a git repo — no revision** | clone at `edd94bdf` |

**What still holds.** The GSC corpus is identical at 1,175 files, so every claim traced through
`scripts/` is sound on either machine, and `tools/check-gsc.ps1` genuinely reproduces — stage 3 and
stage 4 read only `scripts/`. The harness parity result stands.

**What does not.** Anything about non-script assets — tables, scriptbundles, item lists, asset names.
The laptop cannot see `tables/` at all.

**The error this caused.** A search for `icbm` was run against `scripts/` and reported as "zero
occurrences anywhere in the dump". The test box found 58 files across `tables/`, `scriptbundle/` and
`hashed/`. The laptop could not have found them: it has no `tables/`. **Scope every dump claim to the
directory actually searched, and say which machine ran it.**

**Why the laptop's copy is not a git clone.** It sits inside the OneDrive tree, and Step 5 forbids
letting OneDrive and git sync the same `.git`. Re-cloning it in place would create exactly the
corruption hazard that rule exists to prevent. Fixing the split means relocating the dump outside
OneDrive first — not `git clone` where it currently sits.
