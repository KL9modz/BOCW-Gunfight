# Loader shim — one DLL slot, both unlock tools

Merges `CW_Soft_Unlock.dll` and the cwpatch `discord_game_sdk.dll` so both run
from a plain game launch, with no Process Hacker.

Neither payload is reimplemented or modified. The shim just chain-loads them.

## Why this slot

`BlackOpsColdWar.exe` `LoadLibrary`s six DLLs by name at runtime — `bink2w64`,
`discord_game_sdk.dll`, `dxgi.dll`, `ole32.dll`, `oo2core_8_win64.dll`,
`steam_api64.dll`. Discord is the only viable one: it resolves a single symbol
(`DiscordCreate` — `DiscordVersion` is never referenced) and it loads late enough
that the exe is already decrypted.

> 🪦 **CORRECTION 2026-09-08 — "the game tolerates it failing" is FALSE.** The game
> **statically imports `DiscordCreate`**, so any DLL placed in this slot **must**
> export it or launch dies immediately with *"Entry Point Not Found"*. There is no
> tolerance for failure here; the export is mandatory.
>
> ✅ The slot itself is **confirmed working** — `cwpatch.dll` runs in it with F4–F7
> hotkeys verified live in-game, and it needs no shim precisely because it exports
> `DiscordCreate` itself. So this slot is viable, but only for a DLL that satisfies
> that import.

The other five are load-bearing and load far too early to pattern-scan against.

## Layout

```
<game folder>/
  BlackOpsColdWar.exe
  discord_game_sdk.dll   <- this shim
  cwpatch.dll            <- the old fake discord_game_sdk.dll, renamed
  CW_Soft_Unlock.dll     <- unchanged
```

## Install

Back up the real Discord SDK first (3,891,512 bytes) if you still have it.

```powershell
$g = "S:\SteamLibrary\steamapps\common\Call of Duty Black Ops Cold War"
$s = "C:\Users\klaze\OneDrive - sdccd.edu\Games & Mods\Call of Duty\Cold War"

Copy-Item "$g\discord_game_sdk.dll" "$g\discord_game_sdk.dll.orig"   # real SDK backup
Copy-Item "$s\discord_game_sdk.dll" "$g\cwpatch.dll"                 # cwpatch, renamed
Copy-Item "$s\CW_Soft_Unlock.dll"   "$g\CW_Soft_Unlock.dll"
Copy-Item "$s\BOCW-Gunfight\tools\cw-loader-shim\discord_game_sdk.dll" "$g\discord_game_sdk.dll"
```

The built DLL is **not** in git — `.gitignore` excludes `*.dll`. Run `build.cmd`
on a fresh clone before installing.

Uninstall: delete `cwpatch.dll` and `CW_Soft_Unlock.dll`, restore
`discord_game_sdk.dll.orig` over `discord_game_sdk.dll`.

## Use

| Key | Comes from | Effect |
|---|---|---|
| — | cwpatch, automatic | sets dvar `loot_fakeall` = 1 |
| F4 | cwpatch | `lobbylaunchgame` |
| F5 | cwpatch | `killserver` |
| F6 | cwpatch | `fast_restart` |
| F7 | cwpatch | `full_restart` |
| F8 | this shim | loads `CW_Soft_Unlock.dll` |

**Press F8 at the main menu, once the game is fully loaded.** `CW_Soft_Unlock`
does all of its work synchronously in `DllMain`, once, with no retry — it has to
run when the loot/inventory system is already up, which is exactly why it needed
manual injection before. The hotkey reproduces that timing; a timer would be
guesswork.

It can only run **once per launch** — `LoadLibrary` on an already-loaded module
does not re-run `DllMain`. Press F8 too early and you have to restart the game.

Its own message box confirms it ran. That popup fires unconditionally and is
**not** proof the patches applied — see below.

## Caveats

- **`CW_Soft_Unlock` is build-locked.** Built 2023-10-04; it scans three
  hardcoded windows (`base+0x08400000`, `+0x07400000`, `+0x0A500000`) with no
  bounds check against `SizeOfImage`. Your exe is from 2026-06-12. Whether the
  signatures still match can only be settled in-game — the exe's `.text` is
  encrypted at rest, so it cannot be checked statically. cwpatch, by contrast,
  walks the image with `VirtualQuery` and is far more update-tolerant.
- Discord Rich Presence stops working. `DiscordCreate` returns 1
  (`ServiceUnavailable`), same as cwpatch already does.
- This arms on **every** launch, including sessions where you just want to play
  normally. Same tradeoff as the `powrprof.dll` proxy in `.claude/dll-proxy.md`.
- Hotkeys are `GetAsyncKeyState`, so they fire even when alt-tabbed.

## Build

`build.cmd`, or:

```
zig cc -target x86_64-windows-gnu -shared -Os -o discord_game_sdk.dll shim.c -lkernel32 -luser32
```

Zig is only a self-contained C toolchain here — no MSVC or Windows SDK needed.
`winget install -e --id zig.zig`.

## Verified

- Builds clean; exports exactly `DiscordCreate` at RVA 0x1000, internal name
  `discord_game_sdk.dll`, x64 PE32+.
- `LoadLibraryA` + `GetProcAddress("DiscordCreate")` succeed in a test process —
  the same sequence the game performs.
- Imports only KERNEL32, USER32 and `api-ms-win-crt-*`, which the game and both
  payload DLLs already import.

Not yet run inside the game.
