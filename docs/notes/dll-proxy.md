# Forcing gametype/map — the powrprof proxy

Needed **only** for `cwdllgt` (setting the lobby's gametype and map directly,
bypassing the menu's map restriction). The GSC work needs none of this.

---

## 🛑 IT DOES NOT WORK. Deploying this crashes the game at startup — 2026-09-07

**Three attempts out of three, deterministic.** Deployed exactly as this note specifies. The game
never reaches the menu.

```
Faulting application:  BlackOpsColdWar.exe   ts 0x6a03ba27
Faulting module:       POWRPROF.dll  version 0.0.0.0  ts 0x6a9c1e4c
Exception code:        0xc0000005
Fault offset:          0x0000000000017557     <- IDENTICAL every time
```

`version 0.0.0.0` confirms it is our DLL, not System32's. It being the **faulting** module means it
loaded and executed, then crashed — so this is not a load failure, not a missing dependency, and not
Battle.net integrity.

**Ruled out:** VC++ runtime (MSVCP140, VCRUNTIME140, VCRUNTIME140_1 all present); missing ACTS config
(deploying `ACTS\bin\data\` alongside it changed nothing — same offset); `acts.json` toggles (the file
contains literally `null`, so there is no config surface to disable the heavy init path). A
`0xc0000142` / STATUS_DLL_INIT_FAILED dialog appears downstream — that is Windows reporting that
DllMain failed *because* it crashed, not a separate fault.

### Likely cause — a timing problem inherent to the design

`DllMain` calls `cw::InitDll()` at `DLL_PROCESS_ATTACH` (`main.cpp:653`), the earliest possible moment
in process startup. But **`BlackOpsColdWar.exe` is encrypted at rest** — signature scans only match
against the decrypted in-memory image. At `DLL_PROCESS_ATTACH` the image is *not yet decrypted*.

So the probable story is `InitDll` pattern-scanning an encrypted image, finding nothing, and
dereferencing null. A fixed fault offset across every attempt fits that exactly. If so it is inherent
to loading at process start, and no amount of further config will fix it. `UNVERIFIED` — nobody has
stepped through it.

### ⚠ Read the VERIFIED labels below correctly

All four preconditions were verified on 2026-07-26 and **all four are about whether the proxy CAN BE
LOADED** — KnownDLLs, which imports the game uses, whether the forward exists, whether the exports are
present. **None of them establishes that the game LAUNCHES with it installed.** That gap is exactly
where this failed.

**`cwdllgt` has never been executed end to end — not on this machine and not on any other.** Nothing
in this repo ever claimed otherwise; `testing.md:73` positions the proxy as a future step. This is a
design that was reasoned through and precondition-checked, not one that ever ran. So the result above
is the *first* real test of it, not a regression.

Also worth noting the 2026-07-26 verification was done against a Steam install (the shim README's
paths are `S:\SteamLibrary\...`) while the test box is Battle.net, and ACTS 3.3.0 shipped 2026-09-05,
after that date.

### What this costs the project

Both remaining headline goals — Gunfight on arbitrary maps, and 6v6 in a private lobby — reduce to
decoupling gametype from the menu's playlist configuration, and this was the mechanism for it. It is
currently blocked.

> 🔓 **It may also no longer be needed for the map half.** On 2026-09-08 the **in-game menu** carried
> Gunfight from Mansion onto **Hijacked**, a 6v6 non-Gunfight map — no DLL, no injector. If that
> reproduces, `cwdllgt` is off the critical path for map unlocking and this whole proxy is optional.
> n=1 and unverified beyond "it loaded": [[menu-map]].

Untried avenues, none validated:

- **Get the DLL loaded after decryption.** LoadLibrary is already ruled out below for the base-name
  reason, so this needs a different vector.
- **A different DLL slot.** The cwpatch `discord_game_sdk.dll` demonstrably loads later than
  `DLL_PROCESS_ATTACH` and works (see [[unlock-dlls]]). Renaming `acts-bocw.dll` into that slot would
  be **diagnostic** for the timing hypothesis — no crash there would confirm it. ⚠ But it would not
  be *useful*, since `cwdllgt` looks the module up by the base name `powrprof.dll`, and
  `acts-bocw.dll` does not export what the game imports from the Discord SDK, so it may crash for an
  unrelated reason and muddy the reading.
- **Call the exports directly.** `ACTS_EXPORT_SetLobbyGameType` / `ACTS_EXPORT_SetLobbyMap` are
  ordinary exports; reaching them without `acts cwdllgt`'s base-name lookup means new tooling.

**Everything below this line predates the failure and remains accurate about loadability. Do not read
it as evidence the approach works.**

---

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
