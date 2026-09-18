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
