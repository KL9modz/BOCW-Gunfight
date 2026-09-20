# gf_luihook — inject a custom Lua chunk into Cold War's LUI VM (the pause-menu-tab route)

GSC/CSC cannot modify a LUI menu (measured — `docs/notes/pause-menu.md`); only Lua running in the LUI
VM can. This DLL hooks the engine's Lua loader and runs our chunk (`src/gf_lui/gf_loadtest.lua`) in the
live VM, which wraps `LUI.createMenu["#StartMenu_Main"]` and adds a bright **GUNFIGHT MENU LOADED**
label to the ESC pause menu. If that label shows, a custom chunk loaded and ran in the LUI VM — the
integrated pause-menu-tab route is open, no fastfile edit, no pool inject.

Full RE and the design rationale: **`docs/notes/lui-dll-re.md`**.

## Division of labour (project guard)

The agent wrote the DLL **source** (`gf_luihook.c`), the custom chunk, the RE, and this runbook. **klaze
builds (zig), injects, and iterates** — everything below runs against the live game process. Two knobs
need live tuning; both are marked `(A)`/`(B)` in `gf_luihook.c` and explained below.

## How it works (one hook, VM-thread-safe)

- Sig-scans the running exe for `lua_loadx` — cw.json's proven relative call-site sig; resolves to the
  function entry. Verified against the read-only dump: the sig matches exactly one site and resolves to
  `lua_loadx`, and the 16-byte prologue the trampoline relocates is byte-confirmed.
- Inline-hooks `lua_loadx`. The hook runs on the **VM/main thread** (LuaJIT is *not* thread-safe — we
  must never touch the VM from a worker thread; the loader hook is our main-thread execution point). It:
  - captures the `lua_State*` (arg1),
  - counts chunk-loads (a timing proxy — `StartMenu_Main` isn't defined until the UI chunks load),
  - once enough have loaded, calls the **real** `lua_loadx` on our embedded bytecode, then `lua_pcall`.
- The chunk is **defensive** (no-ops until `LUI.createMenu["#StartMenu_Main"]` exists) and **idempotent**
  (guards on `LUI.gf_loadtest_done`), so firing it every load across a timing window is safe.

The hook is self-contained (no MinHook/other lib, matching `bridge.c`/`t1_test.c`): it relocates
`lua_loadx`'s known 16-byte, 3-instruction prologue (fixing the one RIP-relative `mov`) and JMPs back. If
the prologue ever stops matching (game update), it **bails loudly** (DebugView) instead of corrupting the
process — re-check the prologue in a fresh `tools/lui/exe-dump-ro.py` dump.

## Build

`zig` on PATH (confirmed on this box: `zig version` → 0.16.0). From `src/gf_luihook/`:

```powershell
zig cc -target x86_64-windows-gnu -shared -O2 -o gf_luihook.dll gf_luihook.c
```

`gf_bytecode.h` (the embedded `gf_loadtest.luac`, 653 bytes) sits beside the `.c`. Regenerate it after
editing the chunk:

```powershell
python tools/lui/lj2t9.py compile src/gf_lui/gf_loadtest.lua payloads/gf_loadtest.luac
python tools/lui/lj2t9.py verify  payloads/gf_loadtest.luac        # expect "1 load, 0 fail"
# then re-embed (the snippet that wrote gf_bytecode.h is in docs/notes/lui-dll-re.md)
```

## Inject (reuse the existing injector)

```powershell
pwsh tools/gf-bridge/inject-dll.ps1 -Dll (Resolve-Path ./gf_luihook.dll)
```

Standard `LoadLibrary` inject (same as the bridge/T1 DLLs). Run the shell **elevated** if `OpenProcess`
is refused. Inject **after** the game is at the main menu (the LUI VM must exist). Then load into a match
and open **ESC** — look for **GUNFIGHT MENU LOADED**.

⚠ Do **not** inject into a game instance another session's test owns. Relaunch first if unsure.

## Debug output — one line per event (the debug-feed convention)

`OutputDebugStringA`; view with Sysinternals **DebugView** (filter `gf_luihook`). Expected sequence:

```
[gf_luihook] base=... size=...
[gf_luihook] lua_loadx = 0x... (rva 0xd186960)
[gf_luihook] lua_pcall = 0x...              (or: lua_pcall NOT set ...)
[gf_luihook] hook installed - waiting for the LUI VM to load chunks
[gf_luihook] trigger reached at load#=40, L=0x... - attempting inject
[gf_luihook] pcall rc=0 (0=ran ok) - open ESC, look for GUNFIGHT MENU LOADED
```

The **real** result is visual (the ESC-menu label); the log tells you which step reached.

## (A) Pinning `lua_pcall` — the one address to resolve live

`lua_pcall` could not be pinned from the read-only dump by shape/caller-count alone (LuaJIT has many
similar internal functions), and pinning the exact call target of an injected DLL is your domain, not the
agent's. It's quick with a debugger on the live game:

1. Inject with `GF_PCALL_RVA 0`. The log prints the resolved `lua_loadx` address **and**, at the trigger,
   the captured `L=<ptr>`. Loading still happens (proves capture + load); only the run is skipped.
2. In x64dbg/CE attached to the game, go to the `lua_loadx` address. `lua_call`/`lua_pcall` live in the
   same `lj_api.c` neighborhood (a few KB away). Identify by signature:
   - **`lua_pcall(L, nargs, nresults, errfunc)`** — reads `G(L)` = `[L+0x18]`, has a `test r9d,r9d`
     (the `errfunc==0` branch), computes `L->top - nargs`, calls the VM runner, returns a status in eax.
   - **`lua_call(L, nargs, nresults)`** — shorter sibling, no `errfunc`, tail-jumps to the VM runner.
     Our chunk is internally `pcall`-guarded (can't throw), so **`lua_call` is also sufficient** to run
     it — whichever you pin first unblocks the DLL.
   - Confirm: set a breakpoint; the real one fires with `rcx == L` (the value the DLL logged) whenever
     the UI runs a callback (move the mouse over a menu).
3. Set `GF_PCALL_RVA` to the resolved **RVA** (`addr − module base`; the log prints both), rebuild,
   re-inject. (Or fill `GF_PCALL_SIG` with a unique prologue sig if you'd rather resolve by scan.)

The prototype the DLL calls is `int lua_pcall(void* L, int nargs, int nresults, int errfunc)` — if you
pin `lua_call` instead, drop the 4th arg (it's `void lua_call(void* L, int nargs, int nresults)`; change
the typedef + the call in `gf_run`).

## (B) Tuning `GF_TRIGGER_N` — the timing

`GF_TRIGGER_N` (default 40) is how many chunk-loads to wait before injecting, so `StartMenu_Main` exists.
It's forgiving: the chunk is idempotent + defensive and the DLL retries every load for
`GF_MAX_ATTEMPTS` (400) more. If the label never appears but `pcall rc=0` logs, raise `GF_TRIGGER_N`
(fired too early, before the menu was defined) or confirm via a Lua probe that the label add ran. If
nothing logs past "hook installed", lower it. A later, cleaner trigger is a post-UI-init marker chunk
(hook fires when a specific late chunk name loads) — noted in `lui-dll-re.md` if you want to move off the
count.

## Files

- `gf_luihook.c` — the DLL source (this is what you build).
- `gf_bytecode.h` — embedded `gf_loadtest.luac` (generated; do not hand-edit).
- `../gf_lui/gf_loadtest.lua` — the chunk source (edit here, then recompile + re-embed).

## Not evasion

Nothing here is hidden or spoofed. It hooks the game's own Lua loader in-process and runs a Lua chunk in
the game's own VM — the same mechanism the game uses for every UI chunk. `LoadLibrary` injection is the
standard, non-evasive load, as with the project's other DLLs.
