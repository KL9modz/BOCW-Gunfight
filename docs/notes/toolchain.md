# Toolchain — compiling and injecting Cold War GSC

Cold War is T9, GSC **VM 38** (retail PC). VM 37 is the alpha/`COD2020.exe` build.

## Compile

```powershell
acts gscc myscript.gsc -g cw -p pc -o myscript          # 3.3.0 finds cw.json from any cwd
.\tools\strip-strhdr.ps1 -In myscript.gscc -Out myscript.gscc   # ⚠ REQUIRED, see below
```

⚠ **`acts gscc` alone does not produce a working payload.** It stores every string literal as
`8B <len+1> 00 <text> 00` — the ship-format *encrypted-string* header with unencrypted text. The
engine tests the first byte, takes `0x8B` as "encrypted", and decrypts the plaintext into garbage.
Symptoms, all seen on this project before the cause was found: printed literals render as nothing
(the "numbers only" finding), and literals handed to the engine — a map name to `switchmap_load`, a
classname to `struct::get_array` — silently miss. `tools/strip-strhdr.ps1` rewrites each string in
place over its header (same offset, same file size; the string table is not touched), matching how
the t7-compiler-built Atian payload stores strings. Verified in-game 2026-09-12: labelled text on
screen, and `switchmap_load` working. `tools/README.md` → *Payloads*.

**VERIFIED** — produces `myscript.gscc` with magic bytes `80 47 53 43 0D 0A 00 38`,
which is exactly `cw::GSC_MAGIC` (`0x38000a0d43534780`) that the injector checks.
If the last byte is `37` you built for the alpha VM and `injectcw` will reject it.
Re-verified byte-for-byte after ACTS auto-updated 3.1.0 → 3.3.0 — the format is
unchanged. ACTS is now version-pinned; see
[setup-new-pc.md](setup-new-pc.md) item 3 for why and how.

Useful flags: `-d` dev options, `-O` obfuscate, `--detour <type>`, `-c` build
client (`.csc`) scripts.

## Script skeleton

This is ACTS's own Cold War template (`ACTS\bin\data\templates\gsc\scripts\default_script.mustache`):

```gsc
#using scripts\core_common\callbacks_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;

#namespace mymod;

function autoexec __init__system__()
{
    system::register( #"mymod", &__init__, undefined, undefined, undefined );
}

function __init__()
{
    callback::on_start_gametype( &on_start_gametype );
    callback::on_connect( &on_player_connect );
}

function on_start_gametype() { /* level vars are live here */ }

function on_player_connect() { self iprintln( "loaded" ); }
```

**VERIFIED** against the game source: `callback::on_start_gametype( func, obj )`
at `callbacks_shared.gsc:449`, `callback::on_connect( func, obj, ... )` at `:278`
(namespace `callback`, declared line 10), and
`system::register( str_name, func_preinit, func_postinit, var_e9137475, reqs )`
— five parameters — at `system_shared.gsc:9`.

## Inject

```powershell
acts injectcw myscript.gscc scripts\mp_common\bb.gsc scripts\core_common\clientids_shared.gsc
#              ^script       ^hook                    ^replaced
```

All three arguments are required. **VERIFIED** the tool aborts immediately with
`Can't find game process: BlackOpsColdWar.exe` if the game is not running.

Hook scripts (from ACTS's own project template):

| Mode | Hook |
|---|---|
| Multiplayer | `scripts\mp_common\bb.gsc` |
| Zombies | `scripts\zm_common\load.gsc` |
| Any | `scripts\core_common\load_shared.gsc` |

Replaced (sacrificial) script: `scripts\core_common\clientids_shared.gsc` — the
ACTS UI default. It is tiny (1,243 bytes), which is why it was chosen.

### What injection actually does — DERIVED, from `cw.cpp:506` `InjectScriptCW`

1. Scans the `scriptparsetree` XAsset pool in the live process.
2. Finds the hook and the replaced script entries by name hash.
3. Appends the replaced script's hash to the **hook's includes table** and bumps
   `includes_count`, so loading the hook pulls in your script.
4. Copies the replaced script's `crc` and `name` into your buffer so linking passes.
5. `VirtualAllocEx`, writes your script, repoints the replaced pool entry's
   `buffer` at it.

**Consequence:** it patches a pool entry, so it takes effect when the game next
**links** that script. Inject while the scripts are in the pool but before the
gametype links them — in practice, in the lobby, then start/restart the match.
**UNVERIFIED** — this is the first thing to pin down empirically.

### `injectcw` does NOT apply detours

**VERIFIED** by reading the injector: it only swaps a buffer and edits includes.
The `function detour ns<path>::fn()` syntax exists in the ACTS grammar
(`grammar/gsc.g4:37`) but requires a linker that understands the ACTS addon
detour table. Plain `injectcw` is not that.

**So: override behaviour through callbacks and `level.*` function pointers, not
detours.** Gunfight exposes `level.givecustomloadout`, `level.onendround`,
`level.ondeadevent`, `level.ontimelimit`, `level.gettimelimit`,
`level.ononeleftevent` (all assigned in `gunfight.gsc:53-63`).

## Decompiling for reference

```powershell
acts gscd -g cw -p pc -o outdir file.gscc
```

Names come out hashed (`function_c4915ac`, `#"hash_..."`) unless a hash
dictionary is present — `strings.txt`, or `.wni` files in a `package_index\`
folder. `acts download_hash_index` fetches one.

## Two gotchas that cost real time

**1. `Can't read file data for cw` is a WARNING, not an error.** **VERIFIED** —
`gscd` prints it (plus `for pc`, plus `Can't find script name, using x.gsc`) to
**stderr** and then succeeds with exit code 0. It only means there is no hash
dictionary for a standalone script.

**2. Never wrap ACTS calls in `$ErrorActionPreference = 'Stop'`.** PowerShell 5.1
promotes any native-command stderr line into a terminating `NativeCommandError`,
so the harmless warning above kills your script. Gate on `$LASTEXITCODE` instead.
This is what broke `check-gsc.ps1` on first write.
