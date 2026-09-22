# Crash-report decode — from `sre_stack` to the GSC line (`tools/sre-decode.py`)

> Reading a Cold War crash report takes a minute once you know the two facts below. Both were
> established 2026-09-21 by calibration against two known crashes; the tool encodes them.

## 1. Where the report is, what is in it

`%LOCALAPPDATA%\Activision\Call Of Duty Black Ops Cold War\crash_reports\BlackOpsColdWar.<UTC stamp>.zip`
(the stamp is UTC; the `mini_dumper.log` beside it lists every dump time). Inside: `info.json` (the
useful part), `dump.dmp` (a 1 MB minidump: threads, modules, stacks — no script VM memory),
`stacktrace_crash.csv` (native frames, Arxan-obfuscated exe, rarely useful), dxdiag, procstats.

`info.json` fields that matter:

| field | meaning |
|---|---|
| `error_type` | `Script Runtime Error` = a GSC error the retail VM treats as fatal; `EXCEPTION_ACCESS_VIOLATION` = native; absent = engine `Com_Error` (e.g. the `0x91f84370` VM-limit family) |
| `error_message` | `0x6394f836,0000000000000001,` is the generic SRE code — seen for a dev-only builtin outside a devblock (2026-09-15), an unresolved script import at link (2026-09-16) and `sethighlighted` on a script_model (2026-09-21). The code does not say which; the stack does |
| `sre_stack` | the script call stack, one line per frame, **innermost first** (below). **Absent + error 0x6394f836 = the payload failed to LINK at map load** (§2b) |
| `map`, `gamemode`, `crash_time` | `crash_time` is UTC |
| `bnet_err_diag*` | Battle.net file-tree errors with LOCAL timestamps — the `loadingmovie` ones mark every map load, so they date the last load before the crash |

## 2. The `sre_stack` line

```
[124cecff7280be52.3380156066.56:128255] (bytecode offset)
```

- `124cecff7280be52` — the script's name hash (FNV1a-64/63 of the path). **This one is
  `scripts/core_common/clientids_shared.gsc`, the injector's replace target = OUR payload.**
  `1686c9a67db75fae` = `player_vtol.gsc`, `3a7e21b450c1b143` / `07c165117833e69f` = stock scripts
  in the mod's `#using` list (callbacks / globallogic).
- `3380156066` — the crc ACTS writes into the header (`0xc97916a2`). ⚠ **Constant across every build
  of ours** — it does NOT identify which build was running.
- `56` — the VM (0x38).
- `128255` — a **FILE offset** into the `.gscc` (not cseg-relative, not function-relative), pointing at
  the **last byte of the call instruction** of that frame: the first line is the call that was executing
  when the error fired, each next line is the caller's call site.

Calibration: the 2026-09-19 map-scan crash gave `58199 -> mod_apply +11 into its call` and
`59831 -> mod_movement +15 into its call` (mod_apply calls mod_movement: a chain); the 2026-09-21 forge
crash gave `forge_spawn_preview[sethighlighted] <- forge_enter <- menu_run_item[action pointer] <-
menu_think` — exactly the menu's dispatch chain.

## 2b. Link-time vs runtime — telling them apart without a stack

Two `0x6394f836` shapes exist, and `stacktrace_crash.csv` separates them by ONE native frame:

| | runtime script error | link failure at map load |
|---|---|---|
| `error_type` | `Script Runtime Error` | absent |
| `sre_stack` | present | **absent** |
| native frame 3 (adjusted) | `078EC786` | **`078EB1C7`** |
| when | any time | 5–8 s after the map switch (`last_map_switch_time`), every mode |
| seen | forge crash 20260921-120426 | vehicle_probe v2 20260916-014558; 20260921-121217 / -122215 |

The link failure means an import the engine could not resolve. Known causes: a bare call to a
script function that is not a builtin (09-16, `getmapname` / `tablelookupbyrow`), and — 09-21 —
**a `namespace::fn` call whose script is not in the file's `#using` list**. The compiled include
table IS the `#using` list, and the linker resolves imports through it; the function existing
somewhere in the dump is not enough. `gametype::on_round_switch()` with no
`#using scripts\mp_common\gametypes\gametype;` took down every match load from the 04:33 build
onward (the calling build had 17 namespaces called and 16 `#using`s — read straight off the
binaries: every earlier build had the two sets equal). `check-gsc` stage 3 now fails this
(`NO #USING`), with the `#using` line to add.

## 3. Which build was running

Because the crc is constant, decode against the live payload first; **if the frames do not form a
caller chain, the game was running an older build** — decode against `payloads/*.bak.gscc` until they
do. 2026-09-21: the offsets were data (`exp_rows_*`) on the 04:52 combined build and the 04:33 props
build, but a clean chain on the 573 KB builds from 03:07–04:03 — klaze had not re-injected. Byte-for-byte
the same crash would have followed on the live build, since the line was in all of them.

## 4. The tool

```
python tools/sre-decode.py <payload.gscc> <offset> [<offset> ...]
```

Disassembles the payload with `acts gscd -a -l -L` into `%TEMP%`, maps each offset to
`<function> +N <instruction>`, resolving hashed names with the t89 script hash over the current source,
a few git revisions, and the engine builtin table (`reference/funcs_cw.csv`, so a hashed callee like
`sethighlighted` comes back by name).

## 5. Decoded so far

| report | build | stack | cause |
|---|---|---|---|
| 20260919-021250 | 454705d | mod_movement ← mod_apply ← callbacks ← globallogic | VM execution limit (map-census scan) — [`mapscan`](../../README.md), memory `mapscan-crash-fix` |
| 20260920-104228 | race/vehmode combined | player_vtol.gsc 897 ← 783 (native AV) | streak-asset exit — [`vehicles.md`](vehicles.md) |
| 20260921-120426 | 03:07–04:03 forge builds | forge_spawn_preview[`sethighlighted`] ← forge_enter ← menu_run_item ← menu_think | `sethighlighted( 1 )` on the ghost-preview script_model; stock calls it only on a player inside dev-only code (`dev_class.gsc`). Removed 05:19 (`gunfight_menu.gscc` 583,484 B, BC5C73B3). `check-gsc` cannot catch it: the engine table lists it type 0 |
| 20260921-121217 / -122215 | 1E61F8D8 / BC5C73B3 (583 KB; A047DD92 had it too) | none — link failure (§2b) | `gametype::on_round_switch()` with no `#using` of `gametype.gsc`: every match load died 6–8 s in, every mode. Fixed by the one `#using` line; live 05:43 = 583,500 B, 3ACE391A, 17 includes. `check-gsc` now fails this class |

⚠ Lesson for `check-gsc`: a builtin that stock uses **only inside `/# #/` functions** (`Type: dev` in the
dump) is a runtime risk even when the engine table says type 0. Worth a stage-5 warning. (The `#using`
gate from §2b is in.)
