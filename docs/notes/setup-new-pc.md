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

### Size is the integrity check

**A correct `git clone --depth 1` of `ate47/bocw-source` is ~664 MB. Anything materially smaller is
incomplete.** 229 MB specifically means `tables/` (291 MB) and most of `scriptbundle/` (50 MB) are
absent.

⚠ Do not read the old 229 MB figure in these notes as having been *stale*. It was **accurate — for an
incomplete corpus**. That distinction matters: the first diagnosis here was "the documentation drifted",
and the real problem was a missing 341 MB. A number can be correctly measured and still describe the
wrong thing. Check the size on any new machine before trusting a dump-wide search on it.

### Fixing the split does not require relocating anything

An earlier framing of this was wrong and made it sound harder than it is. `tools/check-gsc.ps1` already
takes `-Source` as a parameter (line 14) — it is not hardcoded to the sibling path. So the fix is one
step, not a relocation negotiation:

```powershell
# any path OUTSIDE the OneDrive tree
git clone --depth 1 https://github.com/ate47/bocw-source.git C:\bocw-src
.\tools\check-gsc.ps1 .\src\hello_world\scripts\hello_world.gsc -Source C:\bocw-src
```

The existing incomplete copy can stay where it is and be deleted later. Nothing needs moving first.

**Why the laptop's copy is not a git clone.** It sits inside the OneDrive tree, and Step 5 forbids
letting OneDrive and git sync the same `.git`. Re-cloning *in place* would create exactly the
corruption hazard that rule exists to prevent — which is why the clone above targets a path outside
OneDrive rather than replacing the existing folder.

---

## Reference clones — optional, but they have already paid for themselves

None is needed to build or inject. Each answers something `bocw-source` cannot, and the 2026-09-08
cross-check corrected three scripts before they reached the game
([`dump-cross-check.md`](dump-cross-check.md)).

```bash
cd <parent>          # the folder holding bocw-source-main/ and BOCW-Gunfight/
GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 https://github.com/ate47/t8-atian-menu
GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 https://github.com/shiversoftdev/t9-src
GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 https://github.com/ate47/atian-cod-tools
GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 https://github.com/ModzCentral01/cold-war-mods
GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 https://github.com/ProjectHiNAtyu/t9_bocw_gsc_wiki
```

| Clone | Size | What only it can answer |
|---|---|---|
| `t8-atian-menu` | 8 MB | The menu GSC we inject, and **`docs/notes/funcs_cw.csv`** — 4,481 Cold War builtins with argument counts and `BlackOpsColdWar.exe` addresses. **`tools/check-args.py` needs this file.** |
| `t9-src` | 74 MB | Alternate dump, `vm-38/` = retail. Cross-check only, more hashed than primary — but `tools/dump-grep.sh` runs against it as `bash tools/dump-grep.sh <path>/t9-src/vm-38` |
| `atian-cod-tools` | 28 MB | ACTS source: the bocw DLL, and why the `powrprof` proxy crashes ([`dll-proxy.md`](dll-proxy.md)) |
| `cold-war-mods` | 111 MB | Working example of the load path. Zombies-weighted |
| `t9_bocw_gsc_wiki` | 624 KB | Notes only |

⚠ `--depth 1` throughout. History is not needed and the shallow packs are much faster through a proxy.

---

## Windows VPS as a compile gate — 60 MB, no dump needed

The one check that cannot run in a Linux cloud session is `check-gsc.ps1` stages 1–2: `acts gscc`
(compile) and `acts gscd` (round-trip). Both need **ACTS, a Windows binary**. Stages 3–4 need the
720 MB dump but not Windows, and `tools/check-dump.py` already runs them anywhere Python does.

**So the split is clean.** A bare Windows box needs ACTS and nothing else:

```powershell
git clone https://github.com/KL9modz/BOCW-Gunfight
# put ACTS beside it so acts.exe lands at <parent>\ACTSincts.exe
#   https://github.com/ate47/atian-cod-tools/releases  (pin v3.3.0)

cd BOCW-Gunfight
.	ools\check-gsc.ps1 .\src\lobby_probe\scripts\lobby_probe.gsc -CompileOnly
```

⚠ **`-CompileOnly` reports `COMPILE OK`, never `PASS`.** Stages 3–4 are what catch a typo'd API name —
it compiles clean and dies at runtime — so the script refuses to claim a pass without them. Run
`python3 tools/check-dump.py <script>` for those, on any machine with the dump.

| Where | Can run | Cannot run |
|---|---|---|
| Linux cloud session | `check-args.py`, `check-dump.py` (stages 3–4), `dump-grep.sh`, `crack-hash.py` | anything needing ACTS |
| Windows VPS + ACTS | stages 1–2 via `-CompileOnly` | stages 3–4 without the dump |
| Dev PC (ACTS + dump) | **everything** — `check-gsc.ps1` full, all four stages | — |

**The dev PC is still the only place a full `PASS` is possible.** The VPS closes the compile gap so a
cloud session can stop ending every summary with "this has never been compiled" — it does not replace
the full harness.

⚠ Two Remote Control Windows boxes exist (`WIN-IK7N6SD2UBU`, `vmi3404923`). Neither has ACTS or the
repo yet; the block above is the whole setup.
