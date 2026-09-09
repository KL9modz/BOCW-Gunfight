# The two unlock DLLs, and merging them

`CW_Soft_Unlock.dll` and the `discord_game_sdk.dll` sitting in the project root
are **not** versions of each other. Different authors, different builds,
different mechanisms. Both unlock; one also launches matches.

Everything below was read directly out of the binaries on 2026-09-06 with
Capstone (`zig cc` was installed the same day, see the shim section).

| | `CW_Soft_Unlock.dll` | `discord_game_sdk.dll` |
|---|---|---|
| SHA-256 | `857c5045…4870` ⚠ still truncated — recompute in full when the file is to hand | ✅ `f72249204ff2cc03620a66e2bda8eb8308023e3a16754f5bfada611e646e84d1` |
| Size | 15,360 B | 13,824 B |
| Built | 2023-10-04 | 2024-02-01 |
| Real project (PDB) | `COD-BOCW-UA` | `cwpatch` |
| Author trail | `E:\Programme\…`, popup credits "synx. & 3n3scan" | `C:\Users\Alaix\source\repos\cwpatch` |
| Exports | **none** | `DiscordCreate` |
| Unlock method | forges the inventory table | sets dvar `loot_fakeall` |
| Also does | nothing | F4–F7 match control |
| Loads how | manual injection only | auto, from the game folder |

The real Discord SDK that Steam installs is **3,891,512 bytes** and exports
`DiscordCreate`, `DiscordVersion`, `rust_eh_personality`. The 13 KB one is a
hijack DLL wearing the name. Keep a backup of the real one.

## `discord_game_sdk.dll` — cwpatch

### The unlock: dvar `loot_fakeall` — VERIFIED

The DLL contains exactly one game hash constant. Its patcher thread:

```
01280  movabs rbx, 0x60cdc482a7d159f8
0128d  call [Dvar_FindVar]          ; rcx = hash
01296  jne  0x12c0
012b2  call [Dvar_Register…]        ; not found -> register it (hash, 0, 1, 1, 1, 0)
012c0: 012ca  call [Dvar_SetBool]   ; found -> (dvar*, 1, 0)
```

The hash cracks to **`loot_fakeall`**, confirmed against ACTS:

```powershell
acts h64 loot_fakeall     # -> loot_fakeall=60cdc482a7d159f8
```

Cracked by meet-in-the-middle (FNV-1a is invertible: `h_prev = (h_next *
IV^-1) ^ c`) over a 33,420-token vocabulary tokenised out of
`bocw-source-main\`. ~9.5M forward states, one clean hit. It is **not** in the
ACTS hash index, not in the GSC dump, and not in the exe's plaintext strings —
it is an engine-side dvar. The `loot_` family is real though: the GSC uses
`loot_contracts`, `loot_crystal`, `loot_pods`,
`loot_special_contract_bundle`.

**Watch the mask.** ACTS `h64` applies `MASK63`; raw FNV-1a 64 gives
`e0cdc482a7d159f8`. The game uses the masked form.

What flipping it actually unlocks in-game is **DERIVED**, from the name and the
`loot_` family — Cold War's "loot" system covers blueprints, camos, calling
cards, emblems, operator skins, charms, stickers.

### The hotkeys — VERIFIED

`GetAsyncKeyState` with VK `0x73`/`0x74`/`0x75`/`0x76`:

| Key | Command |
|---|---|
| F4 | `lobbylaunchgame` |
| F5 | `killserver` |
| F6 | `fast_restart` |
| F7 | `full_restart` |

**F4 is the missing half of [dll-proxy.md](dll-proxy.md).** `acts cwdllgt
gunfight mp_moscow` sets the lobby's gametype and map; F4 force-starts it.
Different DLL slots (`powrprof.dll` vs `discord_game_sdk.dll`), so they
coexist. F6/F7 re-run a match without leaving the lobby.

### How commands are executed — VERIFIED

Not via `Cbuf_AddText`. It locates the game's own contiguous command-string
blob, verifies it starts with `host`, then per command:

```
01455  call WriteProcessMemory   ; overwrite the game's string with ours
0145b  call r15                  ; invoke the game's restart function
01471  call WriteProcessMemory   ; restore the original 48 bytes
```

Three candidate slots are tried (`hostmigration_start\n`,
`checkpoint_restart\n`, `mission_restart\n`), hence six
`WriteProcessMemory` calls. `map_restart\n` and `map %s\n` sit in the same blob
and are reconstructed but unused — **the technique extends to arbitrary
commands** if you ever want that for Gunfight testing.

`WriteProcessMemory` on its own process (via `OpenProcess(GetCurrentProcessId())`)
is what lets it write without `VirtualProtect`.

### Why it can auto-load — VERIFIED

`BlackOpsColdWar.exe` references `discord_game_sdk.dll` and `DiscordCreate`
and nothing else — `DiscordVersion` appears nowhere in the exe. One export
satisfies it. `DiscordCreate` returns `1` (`ServiceUnavailable`), so the game
skips Discord cleanly and Rich Presence stops working.

`DllMain` only caches the exe base. The real work starts from `DiscordCreate`,
which the game calls late — **after the exe has decrypted itself**. That
timing is the whole trick.

Scanning is done with `VirtualQuery` across the module image, skipping
non-committed / `PAGE_NOACCESS` / `PAGE_GUARD` pages. Update-tolerant.

## `CW_Soft_Unlock.dll`

### What it does — VERIFIED

Three signature scans resolve two game functions and one global, then:

```
01337  movabs rdx, 0x411deaf0bb60ba86
01341  lea    ecx, [r9+0x40]        ; asset type 0x3F
01345  call   r11                   ; asset lookup -> table of item IDs
       per row: call r12 -> row string -> atoi -> item id
013bd  call   _time64
       for each id, at r14+0x3DF + i*0x14:
013e4    [rcx-4] = id
013e7    [rcx]   = 1                ; owned
013ed    [rcx+4] = timestamp        ; acquisition date
013fd  [r14+0x61E5B] = count
01404  [r14+0x61E63] = 1            ; table valid
```

It **fabricates your owned-inventory array** — a 20-byte
`{id, owned, acquired}` record per item, with the current time as the
acquisition date. That is a heavier mechanism than one boolean, which is
**DERIVED** to be why it covers more than `loot_fakeall` does: items whose
ownership is read from the inventory array rather than gated by the flag.

The asset name behind `0x411deaf0bb60ba86` is **unresolved** — not in the ACTS
index, and it survived a meet-in-the-middle sweep including path-shaped
candidates. Asset type `0x3F` is *not* `sound_duck`; ACTS's `cwBgNames` is the
bgCache enum, not the XAsset pool, so that mapping does not apply.

### Why it needs manual injection — VERIFIED

Two independent reasons:

1. **No exports at all**, so no DLL slot will ever accept it.
2. **It runs everything inline in `DllMain`**, once, synchronously, with no
   thread and no retry. Loaded at process start it would scan an exe that is
   not decrypted yet and an inventory table that does not exist yet.

### Fragility — VERIFIED

It starts each scan at a hardcoded offset into the image
(`base+0x08400000`, `+0x07400000`, `+0x0A500000`) for a fixed length, with **no
bounds check against `SizeOfImage`** and no page-state filtering. Built
2023-10-04; the exe here is 2026-06-12.

**The "Soft Unlock All is successfully Injected!" popup fires unconditionally.**
`DllMain` never checks the payload's return value. It is not proof the patches
applied. Judge by whether items actually unlock.

## The exe is encrypted at rest — VERIFIED

All seven signatures from both DLLs are **absent** from
`BlackOpsColdWar.exe` on disk, including cwpatch's, which demonstrably works.
So `.text` is decrypted only in memory.

Two consequences:

- Whether either tool still matches a given build **cannot be checked
  statically**. Only an in-game test settles it.
- Decrypted pages are left writable, which is why neither DLL imports
  `VirtualProtect`.

## The Discord slot is the only usable one — VERIFIED

The game `LoadLibrary`s exactly six DLLs by name at runtime:

```
bink2w64      discord_game_sdk.dll   dxgi.dll
ole32.dll     oo2core_8_win64.dll    steam_api64.dll
```

Discord is the only one that is late-loading, single-export, and tolerant of
failure. The other five are load-bearing and load far too early to scan
against.

## The merge — `tools/cw-loader-shim/`

A ~120-line C shim takes the Discord slot and chain-loads both payloads. Neither
payload is modified or reimplemented.

```
<game folder>\
  discord_game_sdk.dll   the shim
  cwpatch.dll            the old fake discord_game_sdk.dll, renamed
  CW_Soft_Unlock.dll     unchanged
```

`DiscordCreate` loads `cwpatch.dll` and calls its `DiscordCreate`
(`loot_fakeall` + F4–F7), spawns a thread polling **F8**, and returns `1`.
F8 does `LoadLibrary("CW_Soft_Unlock.dll")`, whose `DllMain` does the work.

**F8 rather than a timer, deliberately.** The soft unlock has to run when the
loot system is already up — the same moment you would otherwise attach Process
Hacker. A timer is guesswork. And it only works **once per launch**:
`LoadLibrary` on an already-loaded module does not re-run `DllMain`, so pressing
F8 too early means restarting the game.

Build with `tools/cw-loader-shim/build.cmd`, or:

```
zig cc -target x86_64-windows-gnu -shared -Os -o discord_game_sdk.dll shim.c -lkernel32 -luser32
```

Zig is only a self-contained C toolchain here — no MSVC, no Windows SDK.
`winget install -e --id zig.zig`. It puts itself straight on the user PATH,
not in `WinGet\Links`.

**VERIFIED:** builds clean; exports exactly `DiscordCreate` at RVA 0x1000;
internal name `discord_game_sdk.dll`; x64 PE32+; imports only KERNEL32, USER32
and `api-ms-win-crt-*` (all of which the game and both payloads already
import). `LoadLibraryA` + `GetProcAddress("DiscordCreate")` succeed in a test
process — the same sequence the game performs.

**UNVERIFIED:** never run inside the game. Not deployed to the game folder —
see [dll-proxy.md](dll-proxy.md), this arms on *every* launch, including
sessions where you just want to play normally.

## Things that will waste your time

- The soft unlock's success popup **lies**. It is unconditional.
- Renaming `CW_Soft_Unlock.dll` to a hijack name does not work. No exports, and
  `DllMain` runs far too early.
- ACTS `h64` masks to 63 bits. Compare against the masked value.
- `acts lookup` does not know `loot_fakeall` even after
  `acts download_hash_index`. Dvar names are a separate namespace from the GSC
  and asset hashes the index covers.
- Swapping the Discord SDK kills BOCW Rich Presence. Expected, not a bug.
- Hotkeys are `GetAsyncKeyState`, so F4–F8 fire even when alt-tabbed.
