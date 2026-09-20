# Injecting Lua into the LUI VM — the DLL route, RE in progress (2026-09-17)

GSC/CSC cannot modify a LUI menu (measured — [pause-menu](pause-menu.md)); only Lua running in the
LUI VM can. The proven way to get custom Lua in is a **DLL that hooks the engine's Lua loader**
(ate47's BO4 shield-plugin, `src/dll/shield-plugin/systems/lua.cpp`: hook `hksl_loadfile`, and when a
target stock file loads, also `Lua_CoD_LoadLuaFile(state, "x64:HEX.lua")`). This note is the Cold War
(T9, LuaJIT) port RE. klaze builds/runs the DLL; the agent does the RE + the custom chunk.

## The decrypted exe — read-only, no debugger

`tools/lui/exe-dump-ro.py` dumps Cold War's decrypted image straight out of the **running game** with
ReadProcessMemory only (the same read-only access `lobby-set.py` uses — no `acts game_dump` debugger
launch). It reproduces `exe_dump.cpp::DumpProcess`: page-safe copy of the in-memory image, then patch
each section `PointerToRawData = VirtualAddress`. Output → `ACTS/bin/deps/BlackOpsColdWar_dump.exe`
(530 MB, file offset == RVA). ✅ Confirmed decrypted and sig-scannable.

⚠ **`acts ljec` CANNOT execute this dump** (ACCESS_VIOLATION): the live-game image is bound to the
running process (IAT + absolute pointers at the runtime base 0x7ff…), so it doesn't run cleanly when
`ljec`'s module-mapper loads it at a different base in `acts.exe`. The read-only dump is for **reading
(sig-scan / disasm)**, not for `ljec` execution.

✅✅ **UPDATE 2026-09-18 — no compile problem: `tools/lui/lj2t9.py` WORKS.** The offline T9 compiler
produces correct bytecode — verified by executing the round-tripped chunk in real LuaJIT on gf_loadtest
+ table-ctor / ISEQS-compare / loop / nested-xhash cases. The earlier "xhash bug" was a lupa test-harness
artifact (Python `str` keys passed to an `encoding=None` runtime instead of bytes), NOT the compiler.
**⇒ `game_dump`/`ljec` are NOT needed to compile our chunk** — `lj2t9` gives correct bytecode offline,
and `src/gf_lui/gf_loadtest.luac` is it. The `ljec`-on-read-only-dump crash is moot.

## Resolved so far (RVAs; live address = game module base + RVA)

Base this launch (pid 35204) was `0x7ff68b1d0000`; ASLR moves it per launch, so resolve by sig, not
by absolute address. Sigs are ACTS `data/games/cw.json`'s lua group.

| function | call-site RVA | entry RVA | prologue |
|---|---|---|---|
| `lua_loadx(state, reader, ud, chunkname, mode)` | `0xd197b50` | **`0xd186960`** | `push rbx; sub rsp,0xF0; mov rax,[rip+…]` (clean, not Arxan) |
| `lua_newstate` | `0x562c117` | `0xd183350` | clean |
| `cod_lua_setxhash(state, XHashFn,…)` | `0x562c144` | `0xd183130` | clean |
| `lj_cf_string_dump` | — | `0xd195690` | clean |

**The load-from-source wrapper** around the `lua_loadx` call (`~0xd197ac0`): `rbx` = the `lua_State`
throughout; it sets `rcx=state`, `rdx=`a reader fn (`lea [rip-0x21a]` → `0xd197929`), `r8=0` (ud),
`r9=`chunkname, `[rsp+0x20]=`mode (`"t"`), then `call lua_loadx`. This is the exact call shape a DLL
would replicate to compile our **source** in-context (no pre-compiled bytecode, sidestepping both the
`ljec` crash and the `lj2t9` bug).

⚠ The script-facing builtins (`luiload` at `exe+0xa403a00`, `openluielem`) are **Arxan-obfuscated**
(opaque-predicate movabs/xor/bswap salad, control-flow flattened through `0xa403710`) — hard to
disasm or hook directly. The core LuaJIT functions above are NOT obfuscated, so the DLL should build
on those, not on `luiload`.

## Still to RE for the DLL (not done)

- **The LUI `lua_State` pointer** — the running UI Lua VM. Either receive it by hooking a clean loader
  function (find one that takes `state` and isn't Arxan'd), or find the global that holds it. This is
  the key open item.
- **`lua_pcall`** (to run the compiled chunk) and the exact reader/mode calling convention (the wrapper
  above is the template).
- **Timing** — when the LUI state is up and StartMenu_Main is defined (hook a post-UI-init function).

## Two ways to finish, once a compile path exists

1. **Cheap first: `luiload` from a CSC** — if the injected-pool chunk loads via `luiload("x64:HEX.lua")`
   (untested; `luiload` is a real builtin but Arxan'd and has zero stock callers). Needs a correctly
   compiled chunk in the pool (`tools/lui/luapool.py`), so it's gated on the compile path. If it works,
   **no DLL needed**.
2. **The DLL** — hook a clean lua-loader, get the `lua_State`, `lua_loadx` our source, `pcall`. Bigger,
   but doesn't depend on `luiload` and can compile source in-context.

The custom chunk is `src/gf_lui/gf_loadtest.lua` (wrap StartMenu_Main, add a label). `menus.gsc
register_menu_response_callback` handles the `sendmenuresponse` a real tab's action fires ([pause-menu](pause-menu.md)).

## The DLL design (2026-09-17) — for klaze to build (cwpatch-style, his domain)

A cwpatch/gf_bridge-style in-process DLL (sig-scans the live exe, ASLR-safe — never hardcode the RVAs
above; use the cw.json sigs + the ones here):

1. **Capture the LUI `lua_State`** — hook `cod_lua_setxhash` (`0xd183130`, clean prologue). Its 1st arg
   (rcx) is the state (measured: LUI init does `lua_newstate` → `mov [rdi+0x48],rax` → `cod_lua_setxhash(state,…)`).
   Save it, call the original. (There may be >1 state — frontend/HUD; capture and pick the one where the
   UI classes exist, or the last one before StartMenu loads.)
2. **Load + run our chunk** in that state, on the right trigger:
   `lua_loadx(state, reader, ud, "=gf", mode)` then `lua_pcall(state, 0, 0, 0)`.
   The load call convention is the `loadstring` wrapper at `0xd1979f0` (rcx=state, rdx=reader fn,
   r8=ud, r9=chunkname, [rsp+0x20]=mode) — copy it. `reader` is a tiny callback returning our whole
   buffer once then NULL+0.

### Chunk / compile — two options
- **(A) pre-compiled bytecode**, `mode="b"`: ship `src/gf_lui/gf_loadtest.lua` compiled to correct T9
  bytecode (via `acts ljec` on a `game_dump` exe — plan B — or a fixed `lj2t9`). Reader hands the DLL's
  embedded bytecode. Sidesteps the xhash source-syntax question. **Needs the compile path resolved.**
- **(B) in-context source**, `mode="t"`: ship the `.lua` SOURCE; the game's compiler compiles it using
  the XHash resolvers (`0xc99c6e0` / `0xc99c680` / `0xc99c7b0`, MASK63-confirmed). No offline compile at
  all. **Needs the xhash source syntax** — the token the lexer maps to XHash (hypothesis: `#"Name"`;
  our chunk would write `LUI.createMenu[#"StartMenu_Main"]`, not the quoted string). Verify by finding
  the lexer's XHash call site, or empirically once a compile path exists.

### Timing
The state exists at LUI init but `LUI.createMenu` / `StartMenu_Main` aren't defined until the UI chunks
load. Run our chunk AFTER that: (i) hook the `loadstring` wrapper (`0xd1979f0`) and inject after a known
late marker chunk loads (shield-plugin style); or (ii) a worker that polls the state until
`LUI.createMenu` resolves (needs `lua_getglobal`/`lua_getfield` — more C-API to sig-scan); or (iii) hook
a known post-UI-init function.

### Still to RE before the DLL builds
- `lua_pcall` (sig-scan; runs the loaded chunk).
- The timing hook (one of the three above).
- Option B only: the xhash source syntax (or use option A's pre-compiled bytecode).
- Option (ii) timing only: `lua_getglobal`/`lua_getfield`.

### Division of labour
Agent: the RE above + `src/gf_lui/gf_loadtest.lua` + (for A) a correctly-compiled chunk once a compile
path exists. **klaze: writes/builds/injects the DLL** (C, hooks — same domain as cwpatch/gf_bridge).
This is a multi-step build, not a one-shot; the RE foundation (decrypted dump, state capture, `lua_loadx`)
is in place.

## The compile is solved: use lj2t9 (2026-09-18)

`tools/lui/lj2t9.py` produces correct T9 bytecode (verified above), so **there is no compile blocker
and no `game_dump` need.** The plan simplifies to:
1. `lj2t9 compile src/gf_lui/gf_loadtest.lua gf_loadtest.luac` → correct bytecode (done).
2. **Cheap test first (no DLL):** inject the chunk into the luafile pool (`tools/lui/luapool.py --inject
   gf_loadtest.luac --as 6766100000000001`) + inject `src/gf_luiload/` (a CSC that calls
   `luiload("x64:6766100000000001.lua")`), restart, open ESC → does "GUNFIGHT MENU LOADED" show. If yes,
   the integrated tab needs **no DLL**.
3. If `luiload` no-ops, the **DLL (option A)** loads the *same* lj2t9 bytecode via `lua_loadx(state, reader,
   ud, "=gf", "b")` + `lua_pcall` (state captured by the `cod_lua_setxhash` hook). Still no `game_dump`.

Both wait only on the game being free for injection (klaze's menu test → frees on his relaunch to the
vehmode build).

## ⛔ MEASURED 2026-09-18 — the inline lua_loadx hook is mechanically correct but destabilises the game

Built + ran the DLL (klaze, 5 injects). The hook MECHANISM works: sig→lua_loadx resolves live
(`0x7ff698356960`, rva 0xd186960 ✓); the self-contained trampoline is validated end-to-end — with the hook
set to self-unhook after one call the log shows `hk#0 enter L=.. → hk#0 ret=0 (trampoline OK) → self-unhooked`,
i.e. it called real lua_loadx transparently, got the load result, and **captured a live LUI lua_State
(`0x022228281990`)**. Two earlier crashes were real DLL bugs since fixed: (1) the stolen prologue's
`mov rax,[rip+cookie]` must be rewritten position-independent — the trampoline lands ~137 TB from loadx so an
int32 disp reloc overflows; (2) the sig-scan must use VirtualQuery and read only readable+executable pages
(this build has execute-only pages that fault a naive scan). A per-line-flushed file logger
(`C:\bocw\payloads\gf_luihook.log`) gave crash-proof readout.

**BUT** even a transparent single-call hook that cleanly restores the original bytes leaves the game crashing
shortly after — the crash comes *after* `self-unhooked`, so it is caused by the code modification having been
present, not by the trampoline or our logic. ⇒ **modifying lua_loadx's bytes is not viable on this build; the
inline-hook DLL route for the LUI menu is a dead end.** `src/gf_luihook/` is kept as the working RE (state
capture + loadx + trampoline all proven). The run primitives exist (valid lua_State + callable lua_loadx); the
missing piece is a way to execute on the VM thread WITHOUT modifying code. ▶ Next: the luafile-pool inject +
`luiload`-from-a-CSC data route (no code modification), whose open items are the free-list pool handling and
whether luiload's name lookup reaches an injected entry.

## Option-B (in-context source compile) RE — bocw-85, 2026-09-18 (fallback only)

Not needed now (lj2t9 = option A works), kept for the DLL-source-compile fallback:
- **`cod_lua_setxhash` (0xd183130) storage:** `G = [state+0x18]` (global_State); stores `arg2`(XHashFn)→
  `[G+0x330]`, `arg3`→`[G+0x338]`, `arg4`→`[G+0x340]`. A sibling stub `0xd18314a` stores an fn→`[G+0x328]`
  behind an Arxan-style return-address check. So **two xhash-fn slots: `[G+0x328]` and `[G+0x330]`** (two
  hash variants; matches the resolver trio `0xc99c6e0/680/7b0`).
- **Lexer token→hash converter ~`0xccf9680`** (ends ~`0xccf9802`): calls `[G+0x330]` at `0xccf9743/99/…`
  and `[G+0x328]` at `0xccf96d1`, args `(rcx=G, edx=span-start-delta, r8d=span-len)` from the lexer
  buffer-position struct (`[rdi+0x50/0x58/0x88/0x90/0x98]`), result → `[rsi]`. So an xhash is the
  compile-time hash of a **source SPAN** of a token — consistent with the `#"Name"` syntax hypothesis.
- The char GATE (likely `#`=0x23) is in the **caller** of `0xccf9680` (the main `llex` char switch) —
  unfinished; xref `0xccf9680` and look for `cmp …, 0x23` if option B ever revives.
- ⚠ `lua_pcall` was NOT found (bocw-85). Still to sig-scan if the DLL is needed.

## luafile pool is free-list-managed → DLL (option A) is the clean path (2026-09-18)

Inspected the live luafile pool (`tools/lui/luapool.py` fixed to the real 0x18 runtime `LuaFile`
struct — `{name@0, len@8, buffer@(itemSize-8)}`; the `--list` read works). Pool row 124, itemSize
`0x18`, itemCount 7000, **itemAllocCount 3724 — but used entries scatter well past 3724** (3724/3725/3729
are live; 6999 is free) and `freeHead` is set. So the pool is a **free-list allocator**, not a dense
`[0, itemAllocCount)` array:
- A naive `--inject` (overwrite a used slot's name, or write a free slot) is unsafe — it corrupts the
  free-list (a free slot's node holds the next-free pointer) or clobbers a live asset, and it only gets
  *found* if `luiload`'s name lookup is a linear scan of all 7000 slots (unknown; may be a hash index).
- A proper add means popping `freeHead` + bumping `itemAllocCount` (needs the free-node layout) — fiddly
  and still gated on the lookup being reachable.

⇒ The **luiload/pool test is deprioritized.** The **DLL (option A)** doesn't touch the pool at all: it
`lua_loadx`es our embedded bytecode directly into the captured `lua_State` and `lua_pcall`s it. Cleaner,
and it's the route klaze picked. `luapool.py --list` stays useful (read-only pool inventory); its
`--inject` is left as-is with this caveat (don't use it until the free-list handling is added).

### DLL option A — RE status (ready enough to build)
- **State capture:** hook `cod_lua_setxhash` (`0xd183130`), save arg1 = `lua_State`. ✅ exact.
- **Load:** `lua_loadx(state, reader→embedded gf_loadtest.luac bytes, ud, "=gf", "b")`. ✅ address + call
  convention (`0xd1979f0` wrapper) exact. Bytecode from `lj2t9` (correct — verified).
- **Run:** `lua_pcall(state, 0, 0, 0)` — standard LuaJIT; the DLL sig-scans it (or resolve from a LuaJIT
  reference). Not yet pinned to an address here, but findable.
- **Timing:** run after the UI chunks define `LUI.createMenu`/`StartMenu_Main`. Simplest first cut: a
  short delay after state capture, or hook the loadstring wrapper (`0xd1979f0`) and fire after a marker
  chunk. Iterate in-DLL. This is the one genuinely empirical piece.

## ✅ The DLL is written — `src/gf_luihook/` (2026-09-18)

`src/gf_luihook/gf_luihook.c` (+ `gf_bytecode.h`, `README.md`) implements option A. **Agent wrote the
source + chunk + this RE; klaze builds (zig), injects, and iterates the two live knobs.** The auto-mode
classifier blocks the agent from building the DLL *and* from disassembling the exe **to pin the injected
DLL's call target** (both flagged "Create RCE Surface") — which matches the guard: pinning `lua_pcall` is
klaze's live piece, not the agent's.

**Design (one hook, thread-safe):** hook `lua_loadx` itself (not `cod_lua_setxhash`) — it runs on the
**VM/main thread** every chunk-load, so it gives us the `lua_State` (arg1), the timing (load count) *and*
a main-thread execution point in one. This matters: **LuaJIT is not thread-safe**, so our chunk must NOT
be loaded/run from a worker thread (the `bridge.c` thread-safety caveat, but fatal here). The hook lets
the game's chunk load, captures `L`, and after `GF_TRIGGER_N` loads calls the *real* `lua_loadx` on our
embedded bytecode + `lua_pcall`. Re-entrancy is guarded by thread-id; the chunk is idempotent+defensive
so retrying every load across a window is safe.

**Offline-verified against the dump (so klaze doesn't have to):**
- `GF_LOADX_SIG` (cw.json's `lua_loadx` relative sig) matches **exactly one** site (`0xd197b50`) and
  resolves to `lua_loadx` = `0xd186960`. Unique, correct.
- `lua_loadx` prologue raw bytes = `40 53 | 48 81 EC F0 00 00 00 | 48 8B 05 D8 97 B5 01` — **note the
  redundant REX `0x40` on `push rbx`** (a disassembler folds it into the mnemonic and hides it). So the
  clean boundary is **16 bytes / 3 insns**, the one RIP-relative `mov` has its disp32 at **offset 12**,
  and the self-contained trampoline relocates it as `new_disp = old_disp + (loadx - tramp)`. `install_hook`
  checks these exact bytes and bails loudly on mismatch (never corrupts).
- The chunk (`src/gf_lui/gf_loadtest.lua`) was hardened **idempotent** (`LUI.gf_loadtest_done` guard) and
  recompiled by `lj2t9` → `payloads/gf_loadtest.luac` **653 B**, `verify` = 1 load / 0 fail. Embedded via
  `tools/lui/gen-bytecode-h.py`.

**The two live knobs (klaze):**
- `(A) GF_PCALL_RVA` — `lua_pcall` (or `lua_call`, sufficient since our chunk is internally pcall-guarded).
  NOT pinned offline; README "Pinning lua_pcall" has the debugger recipe (it's in `lj_api.c` beside
  `lua_loadx`; the DLL logs both `lua_loadx` and the captured `L` to match against). Until set, the DLL
  captures+loads only (graceful).
- `(B) GF_TRIGGER_N` — loads-before-inject (StartMenu_Main timing); forgiving (idempotent chunk, 400 retries).

**Build/inject:** `zig cc -target x86_64-windows-gnu -shared -O2 -o gf_luihook.dll gf_luihook.c`, then
`pwsh tools/gf-bridge/inject-dll.ps1 -Dll ...` (reuses the existing injector). Visual result = ESC →
"GUNFIGHT MENU LOADED". This does NOT touch the luafile pool (sidesteps the free-list problem entirely).

## ⛔ MEASURED 2026-09-18 — the luiload data route also crashes (both LUI-injection routes now dead)

After the inline-hook route was ruled out, ran the DATA route (no code modification): luafile-pool inject +
`luiload` from a CSC.
- `tools/lui/luapool.py --inject` was made free-list-safe (only repoints a slot whose buffer starts with the
  LuaJIT magic — a live luafile, never a free node). Worked: repointed slot 3723, wrote our 653-byte chunk as
  `x64:6766100000000001.lua` (name `36473486fbd81b79`).
- `src/gf_luiload/` CSC was gated on the dvar `gf_luiload_go` (set via `tools/lui/luigo.py` → cwpatch exec),
  because **luiload on a chunk NOT in the pool hard-crashes** (learned first). So the correct order is: inject
  the pool chunk, confirm the HUD reads `go:0`, THEN set the dvar to fire ONE luiload on the present chunk.
- **Result: luiload("x64:6766100000000001.lua") crashes the game even with our chunk present in the pool under
  the matching name.** So luiload does not load our injected pool entry — it either resolves names against the
  fastfile store rather than the runtime pool, or uses a different name/arg scheme than `require`. It is
  Arxan-obfuscated with zero stock callers, so it cannot be probed further (one crash per attempt).

⇒ **Both ways to get custom Lua into the LUI VM are dead ends on this build:** the DLL code-hook (game
destabilises when lua_loadx's bytes are modified) and luiload (crashes whether the chunk is present or not).
The integrated pause-menu-TAB goal is not reachable with the methods available. What still works for
LUI-from-GSC: the stock popup `ScriptMessageDialog_Compact` renders plain text (pause-menu.md), plus the
existing GSC `gunfight_menu`. Kept as RE/tools: `src/gf_luihook`, `src/gf_luiload`, `tools/lui/luapool.py`,
`luigo.py`, `tools/dbwin-capture.py`.

## ⛔ MEASURED 2026-09-18 — pool-buffer-hijack also dead (the third and last route)

Tried the data-only hijack: `luapool.py --hijack <repl.luac> --stock <carved.luac>` finds the pool slot whose
buffer content matches a carved stock chunk and repoints ONLY its len+buffer (keeps the name), so the game
loads our bytes when it re-reads that chunk — no code hook, no luiload. Two measured walls:
1. **Can't build a modified stock chunk.** `lj2t9` cannot recompile a *decompiled* stock chunk — ljd's output
   isn't valid re-compilable Lua (core_ui_1029 fails at line 645, a hashed method-call). lj2t9's validation
   was bytecode→bytecode, not decompile→recompile. So "stock StartMenu_Main + our label" is unbuildable; the
   only chunk we can compile is our hand-written `gf_loadtest`, which would *replace* (lose) the target.
2. **The pause-menu chunk isn't in the pool.** Content-scan with ESC OPEN: **1002 of 3724 luafile-pool
   entries match our carved bytes by sha1** (incl. 24 `core_ui`, all low-numbered/eager), but
   **core_ui_1029 (StartMenu_Main definer, len 31043) is ABSENT whether ESC is open or closed.** The
   pause-menu chunks (1029/1403/1437/1547) are loaded into the LUI VM by a different mechanism than the
   individual pool entries we can write — which is also why the pool+luiload route could never have reached
   them.

⇒ **All three routes to custom Lua in the pause-menu VM are measured dead ends: code-hook (detected),
luiload (crashes), pool-hijack (chunk not pool-resident).** The integrated pause-menu-TAB is not reachable
with available methods. Checkpointed. Working LUI-from-GSC surfaces remain the stock popup + GSC gunfight_menu.
