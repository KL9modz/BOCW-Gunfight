# Forcing gametype/map — the powrprof proxy

Needed **only** for `cwdllgt` (setting the lobby's gametype and map directly,
bypassing the menu's map restriction). The GSC work needs none of this.

## What it does

```powershell
acts cwdllgt gunfight mp_moscow
```

Calls into the game's own lobby functions — `LobbyData_SetGameType(0, mode)` and
`LobbyData_SetMap(0, map)` (`src\dll\bocw-dll\systems\exported.cpp`). This is the
clean equivalent of the menu glitch for getting Gunfight onto a normal map.

Note ACTS's hardcoded UI gametype list doesn't include `gunfight`, but the CLI
passes an arbitrary string through, so `gunfight` works.

## Process Hacker / LoadLibrary injection does NOT work here — VERIFIED

Two independent reasons:

**1. ACTS looks the module up by base name.**

```cpp
ProcessModule& powrprof{ proc["powrprof.dll"] };   // cw.cpp:1164, in cwdllgt
...
powrprof["ACTS_EXPORT_SetLobbyGameType"]
```

Inject `acts-bocw.dll` and the module is named `acts-bocw.dll`. ACTS then
resolves `powrprof.dll` to the **real system one**, which has no such export, and
fails with `Can't find ACTS_EXPORT_SetLobbyGameType`.

**2. Renaming it and injecting also fails.** The game imports powrprof, so
System32's copy is already loaded, and the Windows loader resolves `LoadLibrary`
against already-loaded modules **by base name** — you would get a handle to the
system DLL back and yours would never load.

## Correct deployment

Copy `ACTS\bin\acts-bocw.dll` into the game folder **as `powrprof.dll`**, next to
`BlackOpsColdWar.exe`. It then loads at process start via DLL search order
(application directory before System32).

All four preconditions **VERIFIED** on 2026-07-26:

| Check | Result |
|---|---|
| `powrprof` in `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\KnownDLLs`? | **No** — so the app-dir copy wins. A KnownDLL would be force-resolved from System32 and this whole approach would be dead. |
| Which powrprof functions does the game import? | **Only `CallNtPowerInformation`.** Checked 10 common exports; the other 9 are unreferenced. |
| Does `acts-bocw.dll` forward it? | **Yes** — `src\dll\bocw-dll\main.cpp:668-683` exports `CallNtPowerInformation` and forwards to the real system powrprof. |
| Are the needed exports in the shipped binary? | **Yes** — `ACTS_EXPORT_SetLobbyGameType`, `ACTS_EXPORT_SetLobbyMap`, `CallNtPowerInformation`, `DLL_DecryptGSCScripts` all present. |

So the proxy is a **complete** substitute — nothing the game needs from powrprof
goes missing.

## Caveat before you install it

`DllMain` calls `cw::InitDll()` on `DLL_PROCESS_ATTACH` (`main.cpp:653`), and this
is a full dev DLL — Detours, imgui, curl, hardware breakpoints — not a minimal
shim. Because it loads at process start:

- **It arms on every single launch**, including sessions where you just want to
  play normally online. That is a persistent change to your exposure, not a
  per-test one.
- **It cannot be attached to an already-running game.** In place before launch,
  or not at all.
- Removing or renaming the file fully reverts it.

Recommended: leave it uninstalled until you are specifically testing
gametype/map forcing, so the GSC tests stay independent of it.

## Anti-cheat context

Cold War does **not** use Ricochet's kernel driver — that is MW2019 and later. It
uses TAC, a user-mode Treyarch anti-cheat. Meaningfully weaker, but still an
anti-cheat, and `injectcw` does `OpenProcess` + `VirtualAllocEx` +
`WriteProcessMemory`.

There is **no offline or LAN multiplayer mode** in Cold War on PC — custom games
still run through Activision's servers, so MP cannot be tested fully
disconnected. Lower-risk sequencing: prove the injection pipeline in offline
Zombies first (hook `scripts\zm_common\load.gsc`), then move to MP.
