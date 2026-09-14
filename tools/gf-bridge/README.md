# gf-bridge — in-context control bridge for the Gunfight mod

Why this exists: an external process **cannot** set the mod's `gf_*` dvars (GSC `getdvarint`
reads a GSC-VM store whose values are string-interned; a raw `WriteProcessMemory` never reaches
it — proven 2026-09-12, see `docs/notes/hud-and-control-app.md`). Only a `setdvar` executed
**inside the process** reaches that store. This bridge runs that set in-process, the way
cwpatch already runs F4/F6/F7. Full design: `docs/notes/in-context-bridge.md`.

**Guard:** klaze builds, loads, and runs the DLLs (anything touching game memory / DLLs). The
agent wrote the source and the Python transport. Nothing is hidden or spoofed — it calls the
game's own command executor, identically to cwpatch.

## Files

| File | What |
|---|---|
| `t1_test.c` | **Run this first.** A hotkey DLL that answers the one question the whole design hinges on. |
| `bridge.c` | The real bridge: polls shared memory, runs the console commands the app sends. Ship only after T1 passes. |
| `bridge_channel.py` | The Python transport the app uses to send commands into the bridge. No game memory touched. |

## Step 1 — T1, the decisive test

Does an in-process console `set <dvar> <value>` reach GSC `getdvarint`? Everything else depends
on the answer.

```
zig cc -target x86_64-windows-gnu -shared -O2 -o gf_t1.dll t1_test.c
```

Load `gf_t1.dll` into the running game (your usual DLL-load path, or chain it in
`tools/cw-loader-shim`). cwpatch must be loaded (`ensure-cwpatch`), since the test reads
cwpatch's already-resolved pointers. Then, **in a Gunfight match with the menu available**,
press **F8** (`set gf_hint_lines 12`) and open the in-game menu → Display: the green `*` marks
what GSC `getdvarint` reads. It is absent by default (`gf_hint_lines` is unregistered until set —
the menu's pre-register was disabled). F9 sets 6, for the lobby press.

- **`*` moves to Hint rows 12** → console `set` reaches GSC. Go to Step 2, outcome A.
- **no `*` on any Hint row** → `set` does not reach the GSC store. Step 2, outcome B (needs the
  GSC-store setter; agent disassembles the `setdvar` builtin).
- **Game hangs after F8** → in-process `set` is unsafe off the main thread mid-match. The
  mechanism still works, but `bridge.c`'s execute step must move to a main-thread hook
  (`docs/notes/in-context-bridge.md` → thread-safety). Record it and relaunch.

Also press **F9 once in the pregame lobby** (marker on 6 once the match is up) — if it works
there but hangs in-match, that too points at the main-thread-hook requirement.

## Step 2 — the bridge (after T1 = A)

```
zig cc -target x86_64-windows-gnu -shared -O2 -o gf_bridge.dll bridge.c
```

Load it (alongside cwpatch). Then from anywhere in the same Windows session:

```
python bridge_channel.py status                     # "listening" once the DLL is loaded
python bridge_channel.py switch mp_miami gunfight    # set gf_cmd_map/gametype/stage 0/go 1
python bridge_channel.py stage  mp_raid_rm gunfight  # stage for the lobby (gf_cmd_stage 1)
python bridge_channel.py fillbots                    # set gf_cmd_fillbots 1 / go 1
python bridge_channel.py restart
python bridge_channel.py "set gf_timer_seconds 90"   # raw passthrough (any console command)
```

The existing GSC `cmd_poll()` in `gunfight_menu.gsc` consumes `gf_cmd_*` and performs the
action — no GSC change needed. Last wiring step: point `gf_control.py`'s Actions/Config tabs at
`bridge_channel.send(...)` instead of the (dead) external-dvar path.

## Channel protocol (shared between `bridge.c` and `bridge_channel.py`)

Named shared memory `gf_bridge`, 256 bytes, little-endian:

| Offset | Field | Meaning |
|---|---|---|
| `+0` | `u32 magic` | `0x31424647` ('GFB1'); DLL stamps it when listening |
| `+4` | `u32 seq` | app bumps for each new command; DLL runs when it changes |
| `+8` | `u32 len` | bytes of `cmd` in use |
| `+12` | `char cmd[244]` | one or more console commands, `\n`-separated; DLL runs each |

The app writes the body, then the header, then bumps `seq` last, so the DLL never reads a torn
command. Same-session only (both processes are klaze's); for a cross-session/elevation split,
switch the name to `Global\gf_bridge` and widen the mapping ACL.

## Status

- `bridge_channel.py` — done; protocol round-trip tested (no game needed).
- `t1_test.c`, `bridge.c` — written, **not yet built or run** (klaze's to compile/load/test).
- Decision gate: **T1**. A → ship `bridge.c` as-is. B → agent adds the GSC-store setter. Hang →
  move execute to a main-thread hook.
