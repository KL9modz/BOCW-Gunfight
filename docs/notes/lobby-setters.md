# `LobbySetMap` / `LobbySetGameType` — the layer the map hunt never tried

⚠ **Read [`pregame-routes.md`](pregame-routes.md) first.** P1–P11, the memory scans, the glitch
analysis and the closure table are there. This note is one route that is **not in that table**, found
2026-09-12 by reading ACTS's source rather than the game's.

## The distinction that makes it new

Every route in the closure table attacks the **compat set** — *make the picker allow Miami with
Gunfight selected.* That hunt ended precisely: the allowed set is the client-frontend LUI
`uimodeldatastruct #hash_109ccf57a41ffd82`, populated at runtime from downloaded playlist data,
unreachable from every injectable VM (P8–P11), and its C-side appearances are downstream reflections
of a Lua master. Cheat Engine would have reached it; TAC will not let Cheat Engine run.

**This route does not touch the compat set.** It targets the **selection** instead:

> Don't make the picker allow the pair. Skip the picker and call what the picker calls.

## The two functions

ACTS names both, from its Black Ops 4 work, with addresses, in
`atian-cod-tools/src/core/acts/tools/bo4/lobby_tool.cpp:455` and `:473`:

```c
LobbySetGameType( LobbyType lobby, char const* gametype )   // BO4: 0x398E410
LobbySetMap     ( LobbyType lobby, char const* map      )   // BO4: 0x398E420
```

`LobbyType` **0 = LOBBY_TYPE_PRIVATE** (`src/dll/bo3-dll/data/bo3.hpp:139`) — a custom game.
⚠ The two addresses are **0x10 apart**: adjacent entries in one table. That is a free self-check for
any Cold War port, and `tools/lobby-set.py` runs it.

🔓 **ate47 already wrote the Cold War port.** `src/core/acts/tools/cw/cw_lobby_tool.cpp`, 218 lines:
an ImGui panel, a gametype dropdown, a map dropdown, signature scans instead of hardcoded addresses,
`VirtualAllocEx` for the argument string, a remote-thread call. Its map list includes **every map,
`wz_` ones included**, and its gametype list every mode. **It was built to set any pair, and there is
no compatibility filter anywhere in it.**

🪦 **And it ships disabled, with two bugs.** Its registration line is commented out —

```cpp
// ADD_TOOL_NUI(bocw_lobby_tool, "BOCW Lobby tool", bocw_lobby_tool);   // :217
```

— while the BO4 equivalent, line 528 of its own file, is not. The two defects:

1. **Double base.** `ProcessModule::Scan` returns an **absolute** address (`memapi.cpp:626`,
   `return current + off`, `current` starting at the module base). The caller then does `cw[loc]`, and
   `Process::operator[](uint64_t)` is documented *"Relative offset → absolute offset"*
   (`memapi.hpp:158`) — the module base is added a second time.
2. **The call site is not the function.** Both patterns begin `E8 ? ? ? ?`, a **relative call**. The
   scan returns the address of the `E8`; nothing decodes the rel32 to its destination.

⚠ **This project has already looked at that file and walked past it.**
[`dump-cross-check.md`](dump-cross-check.md) §7 examined `cw_lobby_tool.cpp`, concluded its
`gametypes[]` table is Black Ops 4's, and wrote *"Do not mine it for CW names."* That is correct about
the table and it is why nobody read what the tool **does**.

## `tools/lobby-set.py`

That tool, finished. Scans, decodes the `E8`, groups call sites by resolved target, checks the two
targets sit close together the way they do in BO4, and **changes nothing unless asked**:

```
python tools\lobby-set.py                                  # scan and report only
python tools\lobby-set.py --gametype gunfight --map mp_miami
python tools\lobby-set.py --self-test                      # touches no process
```

No C++ toolchain, no DLL, no GSC, no glitch input.

### The names it takes — ⚠ not ACTS's

`cw_lobby_tool.cpp`'s `gametypes[]` table is Black Ops 4's, and **it does not contain `gunfight` at
all** ([`dump-cross-check.md`](dump-cross-check.md) §7). `lobby-set.py` carries lists built from the
dump instead — `ddl/mp_custom_game.ddl`'s `enum mpmaps` for maps, `scripts/mp_common/gametypes/*.gsc`
for modes — and its `--self-test` asserts their shape:

```
python tools\lobby-set.py --list-maps         # 43; the screen shows 36 (the 7 wz_ ones are not on it)
python tools\lobby-set.py --list-gametypes    # 27, gunfight and gunfight_3v3 among them
```

🔓 The enum shipped **two** of its 43 entries as unresolved hashes, and both are now named:
`hash_4f0163e68a9333ac` = **`mp_jungle_rm`**, `hash_2a5c9d82575f9045` = **`mp_russianbase_rm`**.
Not by guessing — 14,922 candidates missed each — but by **subtraction** against the shipped map files.
Method note: [`dump-cross-check.md`](dump-cross-check.md) §8.

### What it checks before it calls anything

- every call site matching one pattern must resolve to the **same** target
- both targets must lie **inside the main module**
- their **first 16 bytes are printed**, and flagged if they do not open like a function entry
- the two must sit **close together** — in BO4 they are `0x10` apart, adjacent in one table

None of that proves correctness; only a disassembler would. It catches the obvious wrong answers
before a remote thread runs on one, which is the difference between a finding and a relaunch.

---

## ⚠ Two reasons this may fail — both from this project's own measurements

### 1. The Lua master may re-push the selection

*"All C ints are downstream reflections of the Lua master"* is a measured finding, and it is the
strongest argument against this route. If the frontend re-pushes its own selection on the next UI
refresh, the write is transient.

▶ **The counter-argument, and why it is worth one run anyway.** What was proven Lua-authoritative is
the **allowed set** and the picker's own display state — that is what the value scans kept snagging.
The **selection** has to reach C: the session descriptor that gets advertised and launched from is
C-side, which is why `presence.mapid` was worth hunting at all. `LobbySetMap` is not a reflection of
that state; it is the *entry point Lua uses to write it*. Calling it is one layer better than writing
an int and one layer below the wall.

▶ **The test is cheap and decisive:** set the pair, **leave the screen and come back**. Held = the C
lobby owns the selection. Reverted = Lua re-pushes, and this route joins the closure table with a
measurement rather than a theory.

### 2. `CreateRemoteThread` is new API surface for this project

`gfscan.exe` has worked all session — `OpenProcess` + read/write, no signature, not a debugger, so TAC
does not flag it. `injectcw` is the same class: it allocates and repoints a pool entry, and never
creates a thread. **`lobby-set.py` needs `CreateRemoteThread`, which neither of those uses.**

⚠ Raised as an unknown rather than a safe bet, because exposure is klaze's call and not ours. It is
not evasion — nothing is hidden or spoofed — but it is not identical to the two tools already proven
tolerated either.
✅ **RULED ACCEPTABLE on the test box — klaze, 2026-09-12.** Recorded in `.claude/CLAUDE.md`'s ground
rules. The unknown does not go away because it was accepted: if the game dies the moment the thread
runs, that is the finding, and it is a cheap one.

---

## Why it would be worth it

Measured against the pinned requirement — *"Gunfight on any map at the lobby/match/state level,
without glitch steps"* — this route, **if it holds**, satisfies every clause the closed ones failed:

| Requirement | Carry | Glitch | This |
|---|---|---|---|
| real Gunfight gametype | ✅ | ✅ | ✅ |
| correct session descriptor | 🪦 stale | ✅ | ✅ **expected** — the lobby is *set*, not overridden at load |
| joiners can connect | 🪦 **crashes them** | ✅ | ❓ **the criterion.** Same call a normal pick makes, so it should advertise normally |
| no glitch input sequence | ✅ | 🪦 | ✅ |
| no second account | ✅ | 🪦 | ✅ |

▶ **Judge it on joiners.** The carry's failure was never cosmetic — it crashes connected clients. If a
friend on a vanilla install joins a `lobby-set.py` lobby and plays Gunfight on Miami, the map problem
is closed by the route nobody tried.
✅ **A tester is available — klaze, 2026-09-12.** So the decisive run is reachable in one sitting, and
there is no reason to settle for "it looks right on my screen".

## Where it sits among what is left

[`pregame-routes.md`](pregame-routes.md)'s closing section offers three options: CE stealth via DBVM
(kernel-level, can BSOD), automating the glitch's input sequence (works, but it *is* the glitch), or
accepting the gate. **This is a fourth**, it is cheaper than all three, and one scan-only run says
whether it is real. ▶ Run it before deciding between the other three.

---

## A sturdier third signature + the confirmed calling convention (git-recovered `exported.cpp`)

The two `E8 …` patterns above are both **call sites** — they match a caller, and `lobby-set.py`
decodes the rel32 to reach the function. Correct, but fragile in one way: if retail differs from
ate47's build, the *caller's* surrounding bytes (`48 8B C7 0F B6 80…` / `0F B6 83 … 38 86`) can move
even when the function itself is untouched.

🔓 **There is a second, independent anchor for `SetMap` that lands on the function directly.** ate47's
v3.3.0 DLL implemented these setters in `src/dll/bocw-dll/systems/exported.cpp` — **removed from master
and the 3.3.0 tag on 2026-09-05** (commit `10569f8`, "move cw scans to generated and remove old
code"), recovered from parent `46b1d1e`. It names them `LobbyData_SetGameType` / `LobbyData_SetMap`,
finds them by an **in-process** scan (`hook::library::QueryScanContainerSingle`), and for `SetMap`
matches the **function prologue itself**, not a call site:

```
48 89 5C 24 10 57 48 83 EC 20 48 8B DA 8B F9 8B D1 33 C9 E8 ? ? ? ? 84 C0 0F 84 B1 00 00 00
8B D7 48 89 74 24 30 33 C9 E8 ? ? ? ? 48 85 C0 75 08 8D 70 78
```

`mov [rsp+10],rbx; push rdi; sub rsp,20; mov rbx,rdx; mov edi,ecx; …` — a function that immediately
saves `rdx` (the map string) and `ecx` (the lobby type): exactly `(ecx = LobbyType, rdx = const char*
map)`. The scan address **is** the function; no rel32 decode. That yields a **free cross-check** —
`lobby-set.py`'s `E8`-decoded `SetMap` target and this prologue address should be the **same**; two
independent methods agreeing beats either alone, and the prologue is the one likelier to survive a
patch. `lobby-set.py` carries it as `SIG_SET_MAP_PROLOGUE` and asserts the agreement.

✅ **Calling convention confirmed** (and it settles the `E8`-resolution question): `memapi_calls.hpp`
emits `mov rcx, LobbyType; mov rdx, strptr; sub rsp,0x20; call fn`, and `exported.cpp` decodes the
call-site sigs with `.GetRelative<int32_t>(1)` = `sig + 5 + *(int32*)(sig+1)`. So **x64 fastcall,
`rcx = lobby (0)`, `rdx = char* name`; call sites need `+5+rel32`, the prologue is used as-is** —
which is what `lobby-set.py`'s stub and decode already do.

⚠ Only `SetMap` has a published prologue sig; `SetGameType`'s is in no source. But the two sit `0x10`
apart in BO4, so once `SetMap` is anchored, `SetGameType` is a neighbour — capture its own prologue
bytes there at runtime and record them as a durable sig.

## Confirming the result from GSC — use `src/lobby_state/`

`lobby-set.py` fires the call; **`src/lobby_state/` is the read-only in-match oracle** that names what
actually loaded (LS1..LS12 labelled pages: map, gametype, `com_maxclients`, player counts). Run
`lobby-set.py` in the Custom Games lobby, then **start the match from the lobby** and read those pages
— `MAP=mp_miami / GT=gunfight` on a Gunfight-incompatible map is the win. It also emits
`com_maxclients` as mp_probe's `1xxxxx` tag so the key number survives even if text does not.

⚠ **The 3-byte string-header bug is GSC-only — `lobby-set.py` is unaffected.** ACTS prefixes every
compiled GSC string literal with `8B <len+1> 00`, which the engine treats as an encrypted string and
garbles; `tools/strip-strhdr.ps1` slides it off post-compile, and that fix is *why `lobby_state`'s text
renders* (and, separately, why in-match `switchmap_load` had looked inert — its map-name literal was
garbled). **`lobby-set.py` passes a plain C string it allocates in the target with `VirtualAllocEx` —
not an ACTS-compiled literal — so the header bug does not touch the native-call route at all.** The map
codename reaches `LobbySetMap` intact.

▶ **Cheap GSC extension, if wanted:** a *frontend*-hooked (`load_shared.gsc`) sampler that stashes the
lobby's `getgametypesetting(#"maxplayers"/#"timelimit")` to **numeric** dvars (garble-proof, no string
literals) every few seconds — to watch whether `LobbySetGameType` moves the lobby's readable store
*before* launch. `lobby_state` is in-match (`bb.gsc`) only, so it cannot see the pre-launch store; that
is the one observation it does not cover.

## Untried — not ruled out

- **The signatures against a live build.** ate47's patterns are the only ones anyone has, and they
  have never been run. `lobby-set.py`'s scan-only default and its BO4-adjacency check exist for this.
- **Whether the two setters are enough, or whether a third call commits the selection.** The BO4 tool
  exposes only these two, which is weak evidence that they are sufficient there.
- 🔓 **A sibling `LobbySetMaxPlayers` / `LobbySetNumClients` — the 6v6 lever GSC cannot reach.** BO4 puts
  `LobbySetGameType` and `LobbySetMap` `0x10` apart, adjacent entries in one table, so a setter for the
  session client budget (`com_maxclients`) plausibly sits in the same block. Script only ever *reads*
  `com_maxclients`, and `setgametypesetting(#"maxplayers")` was measured (L8) not to move it — so a
  native lobby setter for it would be the only route to >4v4. ▶ Once `lobby-set.py` resolves `SetMap`,
  print the functions immediately before/after it and look for one taking an **int** second arg.
- **Order.** `--gametype` then `--map` is a guess at the UI's own order. The reverse is one more run.
- **`LobbyType` 1 and 2** (`LOBBY_TYPE_GAME`, `LOBBY_TYPE_TRANSITION`). `--lobby` takes them.
- **Whether the menu's own rows update**, or the lobby launches correctly while the UI lies. Only the
  loading screen and scoreboard say.
- **Whether CW's map table carries BO6's per-map `gamemodes` string.** ACTS's BO6 reader has
  `const char* gamemodes` at offset 0x10 (`tools/cordycep/t10/dumper_t10_map_gametype.cpp:23`);
  **BO4's struct has no such field** (`.../bo4/bo4_unlinker_map_table.cpp:13`), though it does carry
  `mapDescription` and `mapLocation` — the two strings the custom-games map screen renders. T9 sits
  between, ACTS has no CW maptable unlinker, so the asset is absent from the dump.
  ▶ `acts dpcw x 113` prints any pool's header before its switch on known types (`poolt9.cpp:937`):
  **item size ~0x1A0 = BO4-shaped, no field; ~0xa8 = BO6-shaped, field present.** One command, no
  injection. ⚠ **Demoted**, and deliberately: the compat set is *proven* to be the online-fed LUI
  model, so even a `gamemodes` string would likely be one input to it rather than the master. Worth
  the 30 seconds, not worth a plan.
- **A `.csc` payload at all.** `scripts/core_common/load_shared.csc` sits beside the `.gsc` this
  project hooks. P6b measured that injected client scripts run in the *match* VM, not the frontend
  one — so this is probably closed, but the hook itself was never tried.

## Sources

- `ate47/atian-cod-tools` — `tools/cw/cw_lobby_tool.cpp`, `tools/bo4/lobby_tool.cpp`,
  `tools/cw/poolt9.cpp`, `tools/cordycep/t10/dumper_t10_map_gametype.cpp`,
  `tools/fastfile/handlers/bo4/bo4_unlinker_map_table.cpp`, `shared/utils/memapi.cpp`,
  `shared/utils/memapi_calls.hpp`, `dll/bocw-dll/data/cw.hpp`, `dll/bo3-dll/data/bo3.hpp`
- `ate47/bocw-source` — `ddl/mp_custom_game.ddl` (the 43-entry `mpmaps` enum; the custom-games screen
  shows 36 = those 43 minus the 7 `wz_` maps), `scriptbundle/datasourcelist/`,
  `tables/data/assets/core_frontend.csv`
- ⚠ **Nothing online.** Searches for the warning string, for BOCW custom-games map restrictions, and
  for `LobbySetMap` / `LobbySetGameType` return nothing on this problem. The community documents GSC
  injection and Zombies menus; the lobby layer is undocumented, and ACTS's lobby tool appears in no
  write-up, release note or video. It is dead code nobody has switched on.
