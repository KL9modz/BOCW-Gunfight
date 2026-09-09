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

### 🪦 The real cause — `acts-bocw`'s init fails, full stop. ERROR_DLL_INIT_FAILED (1114)

⚠ **A previous version of this note blamed decryption timing. That hypothesis is DEAD — disproven
2026-09-08.** It read: `InitDll` runs at `DLL_PROCESS_ATTACH`, the EXE is encrypted at rest, so it
pattern-scans an undecrypted image and null-derefs. Plausible, fitted the fixed fault offset, and
**wrong**. It is corrected here rather than deleted, because it is exactly the kind of tidy
explanation that survives on elegance and sends the next person down a dead road.

**What actually happened.** A purpose-built proxy `powrprof.dll` (zig, 67 KB) was written that
forwards **all 144** powrprof exports to a renamed copy of the system DLL, exports
`ACTS_EXPORT_SetLobbyGameType` / `SetLobbyMap` as real functions, has an **empty `DllMain`**, and
`LoadLibrary`s `acts-bocw.dll` lazily on first call. Findings, in order:

1. **The game launches.** The `0x17557` crash is gone. It *was* caused by `acts-bocw`'s own `DllMain`
   running at `DLL_PROCESS_ATTACH` — an empty `DllMain` fixes it. That much of the timing story was
   right.
2. **`cwdllgt` finds and calls both exports.** It prints `Set gametype gunfight... Set map ... Done`.
3. **But `Done` is a FALSE SUCCESS.** The proxy's log shows the lazy load failing at both candidate
   paths with **`GetLastError = 1114`**, the stub returning 0, and `cwdllgt` reporting success anyway.
   **`cwdllgt`'s success output cannot be trusted.**

**1114 is `ERROR_DLL_INIT_FAILED`.** The DLL is found, mapped, and every dependency resolves — then
`DllMain` returns FALSE. Not `126` (missing module), not `193` (bad format); both plausible locations
were tested to rule out dependency resolution.

That happened in a **fully loaded game, in a live private match, against an image decrypted hours
earlier**. So the failure has nothing to do with when the DLL loads. **ACTS's `cw` init simply does
not work against this game build**, and no loading strategy engineers around it.

### What that closes

`cwdllgt` is unusable here **however the DLL is loaded**, so this entire route to forcing gametype/map
is closed — not by Battle.net, not by load order, not by timing, but by ACTS's own init failing.

The only untried lever is **a different ACTS version**: 3.3.0 shipped 2026-09-05 and the game may have
patched since. That breaks the same-build pin with the dev laptop and is not obviously worth much.

⚠ **`injectcw` is UNAFFECTED.** It is ACTS's external `OpenProcess` / `WriteProcessMemory` path, not
the in-process DLL, and it has worked reliably throughout. Every GSC result the project has came
through it. Do not let this note's failure taint that.

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
currently blocked. Untried avenues, none validated:

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

🪦 **That "complete substitute" conclusion is FALSE — disproven 2026-09-08.**

The check above only asked what **`BlackOpsColdWar.exe` itself** imports. But a `powrprof.dll` in the
application directory intercepts powrprof for **every module in the process** — D3D12, DXGI, and the
GPU driver among them, and those import other powrprof functions. A proxy exporting only
`CallNtPowerInformation` produces **"No valid DX12 video card found"** and the game will not start.

**Forward all 144 exports**, not one. The working proxy renames the real System32 copy to
`powrprof_orig.dll` beside it and forwards everything.

⚠ The transferable error: the precondition was *"which functions does the game import"* when the
question was *"which functions does the **process** import"*. Narrowing a question to the obvious
consumer is how a check passes while the thing it was checking fails.

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
