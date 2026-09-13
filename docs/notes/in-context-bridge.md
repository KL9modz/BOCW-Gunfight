# In-context DLL bridge — driving the Gunfight mod from outside, the way it actually works

Spec, 2026-09-12. Written after the external-memory-write approach (`tools/gf-control` route A)
was proven not to reach the mod. See [[hud-and-control-app]] for that dead end; the one-line
version: **GSC `getdvarint` reads a GSC-VM dvar store (values string-interned), not the engine
registry, so an external `WriteProcessMemory` of an int cannot set a `gf_*` dvar the mod reads.**
Only a `setdvar` executed *inside the process* reaches that store. This note specs that.

⚠ **Ownership (project guard):** klaze builds, loads, and runs the DLL. The agent specs it, writes
the GSC side, and does read-only disassembly. Nothing here is hidden or spoofed — it is the same
in-process execution cwpatch already performs for F4/F6/F7.

## What already works, and what the bridge must add

- ✅ The GSC side is **done**: `gunfight_menu.gsc` `cmd_poll()` runs on the host every 0.25 s,
  reads `gf_cmd_go` and the `gf_cmd_*` triggers via `getdvarint`/`getdvarstring`, and runs the
  action (session switch, bot fill/remove, restart), then clears the flags. It consumes dvars; it
  does not care who set them.
- ✅ **In-process command execution is proven**: cwpatch (`discord_game_sdk.dll`, the 13,824-byte
  one; [[unlock-dlls]]) runs console commands from inside the game — F4 `lobbylaunchgame`, F6
  `fast_restart`, F7 `full_restart` — by overwriting the game's command-string blob and calling the
  engine command executor. Resolved this session (cwpatch's own slots, cross-checked by signature):
  executor `BlackOpsColdWar.exe+0x3ace080`, the command-string slots `+0xd6a5cb0/cc8/d88`.
- ❌ The missing link: **set the `gf_cmd_*` dvars such that the GSC poller's `getdvarint` sees the
  new value.** That is the one thing external pokes cannot do and the bridge must do in-process.

So the bridge is small: **external app → a command channel → in-process code → set the `gf_cmd_*`
dvars in a way GSC honors.** The existing poller does the rest.

## Architecture (three parts)

```
  gf_control.py  --(named shared memory)-->  bridge DLL (in-process)
                                                  | sets gf_cmd_* so GSC sees them
                                                  v
                                          gunfight_menu cmd_poll()  --> action
```

### 1. Loader — reuse the solved slot
`tools/cw-loader-shim/` already chains multiple payloads into the single usable `discord_game_sdk.dll`
slot ([[unlock-dlls]] "The merge"). Add the bridge as a third chained DLL beside `cwpatch.dll` and
`CW_Soft_Unlock.dll`. It loads **after the exe decrypts** (the whole reason the Discord slot is the
one that works), so in-process signature scans are valid — exactly cwpatch's timing.

### 2. Command channel — NOT a dvar
The external→in-process signal must not itself be a `gf_*` dvar (that is the problem we are solving).
Use a **named shared-memory block**: the DLL `CreateFileMapping`/`MapViewOfFile` on a fixed name
(e.g. `Local\gf_bridge`), the Python app opens the same mapping with `mmap`. Layout is trivial —
a sequence number the app bumps, and a small command record (`{verb, map[32], gametype[24], stage,
ints...}`). The DLL polls the seqno; no game memory is touched for transport. (A plain file in a
known path is an acceptable fallback; shared memory avoids disk and is simpler to poll tightly.)

### 3. Executor — set the dvars so GSC honors them
This is the only real unknown, and it is **one test away** (T1 below). Two outcomes, cheapest first.

## T1 — the pivotal test: does console `set` reach GSC `getdvarint`?

cwpatch already executes console commands in-process. The question is whether a console
`set <dvar> <value>` updates the same store GSC `getdvarint` reads. **If yes, the bridge is trivial.**

**Test:** have an in-process caller run the console command `set gf_menu_lines 7`, then open the
in-game menu. If the row count becomes 7, `getdvarint(#"gf_menu_lines")` read it → console `set`
reaches GSC. Run it **twice — once in the pregame lobby, once in an active match** — because the
remote-thread `set` that wedged earlier did so under match-time dvar-lock contention ([[hud-and-control-app]]),
and we need to know whether an *in-process* `set` is safe mid-match.

Cheapest way to issue that `set` for the test: a ~30-line DLL that, on a hotkey (same `GetAsyncKeyState`
pattern cwpatch uses), writes `set gf_menu_lines 7\n` over the command-string slot at
`+0xd6a5cb0` and calls the executor at `+0x3ace080` — i.e. cwpatch's exact mechanism with a different
command string. (Resolve both by signature, not the hardcoded RVAs — the RVAs are this build only;
cwpatch's own signatures are in `tools/gf-control/dvar_backend.py` `CWPATCH_SIGS`.)

### Outcome A — console `set` reaches GSC (likely; hope for this)
The bridge executor is just: for each queued command, run the console lines
`set gf_cmd_map <map>` · `set gf_cmd_gametype <gt>` · `set gf_cmd_stage <0|1>` · `set gf_cmd_go 1`
(and config dvars the same way), via cwpatch's command-blob mechanism. The GSC poller consumes them.
**No new dvar-internals RE at all.** If T1 also shows in-process `set` is safe mid-match, run it from
the DLL's own (cwpatch-style) thread; if mid-match `set` still contends the lock, run it from a
main-thread hook (see thread-safety) — the command text is identical either way.

### Outcome B — console `set` does NOT reach GSC
Then the store GSC reads is written only by the **GSC `setdvar` builtin** (`BlackOpsColdWar.exe+0x3CD62A0`,
funcs_cw.csv), which updates the GSC-VM dvar store — the global the read path loads from
(`exe+0xc5c2c60` does `mov rax,[base+0x1310a260]`; the `getdvar` worker is `exe+0xa29e3d0`). Two ways in:
- **B1 — call the store's setter directly.** Disassemble the `setdvar` builtin to find the internal
  function it calls that writes the store (read-only; anchored at the two addresses above). Call that
  function `(hash, value)` from a **main-thread hook** (never a raw remote thread — that wedges). More
  RE, but bounded, and it is the function the menu itself uses.
- **B2 — invoke the `setdvar` builtin with a synthesized VM frame.** Heavier and fragile; only if B1's
  internal setter cannot be isolated.

## Thread-safety — the hard-won rule

**Never execute from a raw `CreateRemoteThread`.** This session proved it twice: a remote-thread
`Dvar_FindVar` on a hot dvar and a remote-thread command-executor call both deadlocked on the dvar
lock the match thread holds, wedging the game until relaunch ([[hud-and-control-app]]). In-process is
not automatically safe either — run dvar-touching work **on the main game thread** via a per-frame
hook, so it takes the lock the way the game does. cwpatch gets away with a dedicated thread only for
restart commands that tear the match down; T1 tells us whether `set` is safe off-main-thread. Default
the design to a main-thread hook and relax it only if T1 says a dedicated thread is safe.

Finding a per-frame main-thread hook is the one extra RE item the main-thread path needs; candidates
to disassemble for (read-only): the client-frame / `RunFrame`-class function, or any function cwpatch's
restart path already calls on a known thread. Deferred until T1 decides we need it.

## Staging (cheapest kills the most work)

1. **T1** — the 30-line hotkey-DLL `set gf_menu_lines 7` test, lobby + match. One evening, decides
   everything below.
2. If **A**: ship the bridge DLL (shared-memory poll → cwpatch-mechanism `set` lines). Wire
   `gf_control.py` to write the shared-memory command record instead of pretending to write dvars.
   The Actions tab goes live with no GSC change (the poller already exists).
3. If **B**: read-only disassembly of the `setdvar` builtin to isolate the store setter (B1), then the
   main-thread hook + the call. Then step 2's app wiring.
4. Either way, keep the **in-game menu** as the primary control surface — it drives GSC natively and
   already works; the bridge is the off-HUD convenience layer, not a dependency.

## What the agent can do now without the game / without touching memory
- Write the Python shared-memory writer in `gf_control.py` (transport only; inert until the DLL exists).
- Read-only disassembly toward B1 (the `setdvar` builtin internals) so that branch is ready if T1 is B.
- Draft the bridge DLL's C source (klaze compiles/loads/runs it).

## Untried — not ruled out
- Whether console `set` reaches GSC `getdvarint` (T1) — the entire difficulty hinges on this and it is
  untested.
- Whether an in-process (non-main-thread) `set` is safe mid-match, or needs the main-thread hook.
- Whether a single main-thread hook point exists that is cheap to find and stable across patches.

## Sources / anchors (this build; resolve by signature in practice)
- cwpatch executor `+0x3ace080`, command-string slots `+0xd6a5cb0/cc8/d88`; signatures in
  `tools/gf-control/dvar_backend.py` (`CWPATCH_SIGS`), mechanism in [[unlock-dlls]].
- GSC dvar store global via `exe+0xc5c2c60` → `[base+0x1310a260]`; `getdvar` worker `exe+0xa29e3d0`;
  GSC `setdvar` builtin `exe+0x3CD62A0` (t8-atian-menu `funcs_cw.csv`).
- `tools/cw-loader-shim/` (slot chaining), `src/gunfight_menu/` (`cmd_poll`/`cmd_dispatch`).
