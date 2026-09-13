# gf-bridge — build & run instructions (klaze)

The goal and design are in `docs/notes/in-context-bridge.md`. This is the do-it runbook. Everything
here is yours to run (it compiles/loads/runs code in the game process); the agent wrote the source,
this runbook, and the injector. Do **Part 1 (T1)** first — its result decides the rest.

Prereqs, one-time check:
- Game running, in a **Gunfight match** with the in-game menu working (RMB+V).
- cwpatch loaded. Verify: `python ../gf-control/dvar_backend.py --cwpatch` → every row says **yes**.
  (If not, let `ensure-cwpatch` restore the slot, then relaunch the game.)
- `zig` on PATH (confirmed on this box: `zig version` → 0.16.0).
- Run shells **elevated** if `OpenProcess`/inject is refused.

---

## Part 1 — T1: does in-process `set` reach GSC? (the decisive test)

**1. Build the test DLL** (in `tools/gf-bridge/`):

```
zig cc -target x86_64-windows-gnu -shared -O2 -o gf_t1.dll t1_test.c
```

**2. Load it into the running game:**

```
pwsh ./inject-dll.ps1 -Dll (Resolve-Path ./gf_t1.dll)
```

Expect `injected ... into pid ...`. (If it says LoadLibrary returned 0, it was already loaded or
DllMain failed — see Troubleshooting.)

**3. Run the test.** In a live Gunfight match, **press F8**, then open the menu (RMB+V) → Menu display.
Look at **In-game rows**.

- You can also just watch the compact menu: `gf_menu_lines` is the row count, so if it worked the
  visible menu grows to **7 rows**.

**4. Read the result:**

| What you see | Meaning | Next |
|---|---|---|
| Rows become **7** | console `set` reaches GSC `getdvarint` | **Outcome A** → Part 2 |
| **No change** | `set` doesn't reach the GSC store | **Outcome B** → tell the agent; they disassemble the `setdvar` builtin for the store setter |
| Game **hangs** after F8 | in-process `set` wedges mid-match from a worker thread | **Outcome C** → tell the agent; the executor moves to a main-thread hook. Relaunch. |

**5. Also press F8 once in the pregame lobby.** If it works in the lobby but hangs in a match, that's
Outcome C (main-thread hook needed). Tell the agent which of A/B/C you got, in lobby and in match.

---

## Part 2 — the bridge (only if T1 = Outcome A)

**1. Build:**

```
zig cc -target x86_64-windows-gnu -shared -O2 -o gf_bridge.dll bridge.c
```

**2. Load** (same injector, or chain it in `tools/cw-loader-shim` for a permanent install):

```
pwsh ./inject-dll.ps1 -Dll (Resolve-Path ./gf_bridge.dll)
```

**3. Drive the mod** from any shell in the same Windows session:

```
python bridge_channel.py status                      # "bridge DLL is listening" once loaded
python bridge_channel.py switch mp_miami gunfight     # switch map+gametype now
python bridge_channel.py stage  mp_raid_rm gunfight   # stage for the lobby (shows at match end)
python bridge_channel.py fillbots
python bridge_channel.py removebots
python bridge_channel.py restart
python bridge_channel.py "set gf_timer_seconds 90"    # any console command, raw
```

The GSC `cmd_poll()` already consumes `gf_cmd_*` and performs the action — no GSC change needed.

**4. Wire the GUI (optional, after the above works):** ask the agent to point `gf_control.py`'s
Actions/Config buttons at `bridge_channel.send(...)`. Then the Windows app drives the match for real.

---

## Troubleshooting

- **`--cwpatch` rows not all "yes"** → cwpatch isn't the loaded DLL, or a game patch moved it. Let
  `ensure-cwpatch` restore the slot and relaunch; re-check. The test DLL reads cwpatch's resolved
  pointers, so it's inert without cwpatch.
- **F8 does nothing, no beep** → DLL not loaded (re-run the injector; check its output) or F8 is
  bound elsewhere — change `VK_F8` in `t1_test.c` to another key (e.g. `VK_F9` = `0x78`) and rebuild.
- **A short beep on F8** → the DLL loaded but couldn't resolve cwpatch (cwpatch not present, or not
  yet initialized — press F8 a few seconds after the match is fully up).
- **`OpenProcess failed`** in the injector → run the shell elevated.
- **Game hangs after F8** → that's Outcome C, a real result. The command executor doesn't return
  cleanly off the main thread mid-match; relaunch and report it — the bridge's execute step moves to
  a per-frame main-thread hook (the transport and command format stay the same).
- **`zig cc` errors** → make sure you're in `tools/gf-bridge/` and the target triple is
  `x86_64-windows-gnu`. No headers beyond `windows.h` are used.

## Guard / safety

- klaze compiles, loads, and runs everything here; the agent wrote the source, this runbook, and the
  injector. Nothing is hidden or spoofed — the DLL calls the game's own command executor exactly as
  cwpatch does for F4/F6/F7, and `LoadLibrary` injection is the standard, non-evasive load.
- The test is host-local: it changes only the host's session; joiners are unaffected.
- One DLL payload concern does **not** apply here (that rule is for ACTS GSC `injectcw`, a shared
  replace target) — a LoadLibrary'd DLL coexists with cwpatch and the GSC payload fine.
