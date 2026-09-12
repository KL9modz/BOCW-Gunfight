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

⚠ Stated plainly because this project's rule is that exposure is klaze's call, not ours: this is one
API beyond anything run here so far. It is not evasion — nothing is hidden or spoofed — but it is not
identical to the two tools already proven tolerated either. **Unknown, not safe, not condemned.**

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

## Where it sits among what is left

[`pregame-routes.md`](pregame-routes.md)'s closing section offers three options: CE stealth via DBVM
(kernel-level, can BSOD), automating the glitch's input sequence (works, but it *is* the glitch), or
accepting the gate. **This is a fourth**, it is cheaper than all three, and one scan-only run says
whether it is real. ▶ Run it before deciding between the other three.

---

## Untried — not ruled out

- **The signatures against a live build.** ate47's patterns are the only ones anyone has, and they
  have never been run. `lobby-set.py`'s scan-only default and its BO4-adjacency check exist for this.
- **Whether the two setters are enough, or whether a third call commits the selection.** The BO4 tool
  exposes only these two, which is weak evidence that they are sufficient there.
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
