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
(sig-scan / disasm)**, not for `ljec` execution. Compiling our chunk with `ljec` needs the cleaner
`acts game_dump cw` capture (plan B) — or fix `tools/lui/lj2t9.py` (the offline compiler, currently
has an xhash-chunk bug) — or compile in-context from the DLL (below).

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
