# tools

| File | What it is |
|---|---|
| `check-gsc.ps1` | Offline GSC validation — compile, round-trip, resolve every API call and bare builtin |
| `dump-grep.sh` | Offline — resolves builtin argument shapes from stock call sites in `bocw-source`. Writes `dump-report.md`. No game, no network |
| `check-args.py` | Offline — checks builtin **argument counts** against ate47's Cold War table. `check-gsc.ps1` explicitly does not do this |
| `crack-hash.py` | Offline — recovers the NAME behind a T9 script hash by guessing and hashing. Cracked `maxsquadplayers` and `gunfightloadoutindex`. Unsalted hash, so a 63-bit match is proof |
| `crack-cmds.py` | Offline — recovers console-command NAMES from `acts dcfuncscw`'s hashed `cfuncs_cw.csv`. Command-shaped vocabulary, tries masked *and* raw hash forms, and refuses to be read at all if none of five known-real controls resolve. The gate on `docs/notes/lobby-map-dll.md` |
| `lobby-set.py` | **Online, Windows** — sets the custom-games lobby's map and gametype by calling the engine's own `LobbySetGameType` / `LobbySetMap`, skipping the LUI compat gate instead of beating it. Signature-scans, decodes the `E8` rel32, groups call sites by resolved target, and checks the two setters sit close together the way they do in BO4. **Scan-only unless you pass `--gametype`/`--map`**; `--self-test` touches no process. Finishes ACTS's own `cw_lobby_tool.cpp`, which ships disabled. ⚠ Uses `CreateRemoteThread` — one API beyond gfscan and `injectcw`. `docs/notes/lobby-setters.md` |
| `settings-xref.py` | Offline — classifies all 463 gametype settings script reads by whether a **menu row** exists for them. Establishes *hashed ⇒ hidden*: 0 of 236 hashed keys has a bundle. Regenerates `docs/notes/gametype-settings-map.md` |
| `check-dump.py` | Offline — **stages 3–4 of `check-gsc.ps1` without ACTS or PowerShell.** Resolves every call against the dump AND ate47's engine table, which splits "no stock caller" from "does not exist" |
| `strip-strhdr.ps1` | **Required after every `acts gscc`.** Removes the 3-byte string header ACTS emits, which the engine reads as "encrypted" and garbles — see *Payloads* below |
| `ensure-cwpatch.ps1` | Keeps cwpatch in the `discord_game_sdk.dll` slot. One-shot check/restore, `-Watch` resident guard, `-Install` registers the guard as a logon task. Never copies a file that fails the recorded SHA-256 — see *cwpatch* below |
| `inject.sh` | Inject **one** payload (`menu`, `mod`, or any `src/<name>/`) on the known-safe hook/replace pair |
| `autoinject.sh` | Watch for the game and inject automatically, re-arming after each restart |
| `cw-loader-shim/` | C shim for the `discord_game_sdk.dll` slot (see `docs/notes/unlock-dlls.md`) |

The full hosting procedure — Gunfight on any map with a 60-second round timer — is in
[`../docs/notes/menu-map.md`](../docs/notes/menu-map.md). Read that first; this file only covers
getting the payloads in place.

---

## Payloads

Both scripts read from `$GF_PAYLOADS`, defaulting to **`/c/bocw/payloads`**. Compiled `.gscc` files
are gitignored (`*.gscc`), so they are **not** in this repo and must be rebuilt or re-downloaded on a
fresh machine. Two files go in that directory:

### 1. `gunfight_mod.gscc` — build it

```bash
# validate first (catches typo'd API names AND non-existent builtins)
./tools/check-gsc.ps1 ./src/gunfight_mod/scripts/gunfight_mod.gsc

# compile
mkdir -p /c/bocw/payloads
/c/bocw/ACTS/bin/acts.exe gscc src/gunfight_mod/scripts/gunfight_mod.gsc \
    -g cw -p pc -o /c/bocw/payloads/gunfight_mod

# ⚠ STRIP THE STRING HEADERS — every build, no exceptions
./tools/strip-strhdr.ps1 -In /c/bocw/payloads/gunfight_mod.gscc -Out /c/bocw/payloads/gunfight_mod.gscc
```

⚠ **ACTS writes every string literal with a 3-byte ship-format "encrypted string" header
(`8B <len+1> 00`) and leaves the text unencrypted.** The engine decides "encrypted" from the first
byte, so it decrypts the plaintext into garbage: nothing you print renders, and — worse — every
literal you pass to the engine (`switchmap_load( "mp_zoo_rm", … )`, spawn classnames, music states)
arrives garbled. That is what made `switchmap_load` look inert (`bbf94f9`) and what made retail look
"numbers only" (`hello_world`, 2026-09-07). `strip-strhdr.ps1` slides each string over its header in
place — same offsets, same size, nothing else in the file moves — which is exactly how the working
Atian payload stores its strings. Found 2026-09-11; `docs/notes/session-switch.md` has the in-game
confirmation. **A `.gscc` that has not been through it is not a finished payload.**

Source is [`../src/gunfight_mod/`](../src/gunfight_mod/). Its `default_config()` ships the
configuration verified in-game on 2026-09-08 — all four switches on, `timer_minutes: 1` (= 60s).

### 2. `BlackOpsColdWar_atianmenu_pc.gscc` — download it

Third-party, not ours, not redistributable here.

| | |
|---|---|
| Source | [`ate47/t8-atian-menu`](https://github.com/ate47/t8-atian-menu) — **same author as ACTS** |
| Release | tag `latest_build` |
| Asset | `BlackOpsColdWar_atianmenu_pc.gscc` |
| Size | **66,320 bytes** |
| Header | `80 47 53 43 0d 0a 00 38` — `cw::GSC_MAGIC`, last byte `38` = VM38 retail |

```bash
mkdir -p /c/bocw/payloads
curl -sSL -o /c/bocw/payloads/BlackOpsColdWar_atianmenu_pc.gscc \
  https://github.com/ate47/t8-atian-menu/releases/download/latest_build/BlackOpsColdWar_atianmenu_pc.gscc
```

Verify the size before using it — a 404 saved to disk is still a file.

**Keybinds** (from [`scripts/config/keys.gsc`](https://github.com/ate47/t8-atian-menu/blob/master/scripts/config/keys.gsc)):
open **ADS+Melee** (RMB+V), up **ADS** (RMB), down **Attack** (LMB), select **Use** — which on BOCW PC
is **R (Reload)**, *not* F — back **Melee** (V).

---

## `discord_game_sdk.dll` (cwpatch) — required, not optional

Gives F4 `lobbylaunchgame` / F6 `fast_restart` / F7 `full_restart`, auto-loading on every launch with
no injection step.

**F7 is load-bearing for the hosting workflow.** A carried map is a load-time override that never
changes lobby state, so returning to the lobby to restart *discards the carry*. `full_restart`
restarts the match without going via the lobby, and is the only way to link the mod while keeping the
carried map.

| Size | What it is |
|---|---|
| **13,824** | cwpatch — hotkeys live |
| **3,891,512** | stock Microsoft SDK — hotkeys dead |

⚠ **Battle.net silently restores the stock SDK — on ROUTINE UPDATES, not just repairs.** Observed
twice on 2026-09-08: once after a repair-triggered re-download, and again after an ordinary small
patch a few hours later. **Check the file size after every Battle.net update.** If F4–F7 stop working
mid-session, check it first.

✅ **Restoring takes seconds now** — see *Irreplaceable binaries* below for the command. The second
occurrence was fixed from the backup with a matching hash before it cost anything; the first cost the
file outright.

✅ **And it can be automatic.** `ensure-cwpatch.ps1 -Install` registers a hidden logon task that
watches the slot and puts cwpatch back within seconds of Battle.net overwriting it (deferring until
the game exits if it is running, since the DLL is read once at launch). `ensure-cwpatch.ps1` with no
switch is the one-shot pre-launch check. Both verify the backup's full SHA-256 before copying
anything, and log to `C:\bocw\ensure-cwpatch.log`. ⚠ It cannot know whether a game update moved
cwpatch's offsets — that still needs the in-game F4/F6/F7 check.

Since the SESSION map switch (`docs/notes/session-switch.md`) the map no longer depends on F7: a
lobby-route restart keeps a session-switched map. F7 remains the fastest way to relink a fresh
injection without a lobby trip.

⚠ **An update may also change `BlackOpsColdWar.exe`.** It is encrypted at rest, so no static check can
confirm cwpatch's offsets still fit the new build. **If F4–F7 are dead with the correct 13,824-byte
file in place, suspect the patched game, not the DLL.** The same applies to ACTS: injection failing or
behaving oddly right after an update points at the build, not the payload.

---

## Irreplaceable binaries — the rule, and the one that got away

⚠ **The cwpatch DLL was lost on 2026-09-08 and RECOVERED the same day** — klaze had a copy and put it
back. The near-miss stands as the reason this section exists.

A `rm -rf` on the game's `Data` folder forced a full Battle.net re-download, the repair wrote the stock
3,891,512-byte SDK back over cwpatch, and **the repo held no copy because `.gitignore` has a blanket
`*.dll`.** Recycle Bin scan: nothing (the repair overwrote in place). ✅ **Now backed up** — see the
location at the end of this section.

🪦 **And the truncated hash failed at exactly the job it was kept for.** The recovered file is
authentic — 13,824 bytes, prefix `f7224920` matching to 32 bits — but the notes recorded the tail as
`84f1` and it is **`84d1`**. A one-character transcription slip. Had those four characters been used to
authenticate a re-download, **the correct file would have been rejected.** Record hashes in full.

⚠ **Two mistakes, and the second is the instructive one:**

1. The deletion. Owned, and separately guarded — ACTS now lives in its own `acts\` subfolder.
2. **The backup preserved the wrong file.** This section used to say *"back up the stock SDK as
   `discord_game_sdk.dll.orig`."* That backs up the file **Battle.net restores for free** and leaves
   the irreplaceable one unprotected. It is exactly backwards.

▶ **The rule: classify a binary by whether you can get it back, not by whether it is a binary.**

| Class | Example | Ignore it? |
|---|---|---|
| **Rebuildable** | our `*.gscc` — `acts gscc` from `src/`, seconds | ✅ yes, it is build output |
| **Re-fetchable** | `BlackOpsColdWar_atianmenu_pc.gscc` — stable release URL, size recorded above | ✅ yes, but **record URL + exact byte size** |
| **Neither** | cwpatch `discord_game_sdk.dll` — no source, no canonical URL | ⚠ **out-of-repo backup, written down, or it is gone** |

This repo is **public**, so third-party binaries stay out of it regardless — which is precisely why
the out-of-repo backup is the entire safety net rather than a convenience.

### If you recover or rebuild cwpatch, verify it against this

Recorded in [`../docs/notes/unlock-dlls.md`](../docs/notes/unlock-dlls.md) from a Capstone read of the
binary on 2026-09-06, while we still had it:

| | |
|---|---|
| Size | **13,824 bytes** |
| SHA-256 | ✅ **`f72249204ff2cc03620a66e2bda8eb8308023e3a16754f5bfada611e646e84d1`** — computed in full from the recovered file, 2026-09-08. ⚠ The notes previously carried this truncated as `…84f1`, which is **wrong in the last four characters** |
| Built | 2024-02-01 |
| PDB path | `C:\Users\Alaix\source\repos\cwpatch` |
| Exports | `DiscordCreate` (the stock SDK also exports `DiscordVersion`, `rust_eh_personality`) |
| Mechanism | registers/sets dvar `loot_fakeall`; binds F4 `lobbylaunchgame`, F6 `fast_restart`, F7 `full_restart` |

⚠ **Record the FULL hash next time.** A truncated hash in the notes and no file on disk is how a
verifiable artifact becomes an unverifiable description.

**Backup location for anything in the "neither" class: `C:\bocw\vendor-backup\`.** Not in the repo, not
under the game folder (Battle.net repairs that), not in the scratchpad (cleared on reboot — which is
how the payload directory was lost the same day).

✅ **Seeded 2026-09-08**, named so the size is visible without hashing anything:

| File | Size | Why it is there |
|---|---|---|
| `discord_game_sdk.CWPATCH-13824.dll` | 13,824 | ⚠ **the irreplaceable one.** No source, no URL |
| `discord_game_sdk.STOCK-3891512.dll` | 3,891,512 | the real Microsoft SDK, to restore a clean game folder |
| `BlackOpsColdWar_atianmenu_pc.gscc` | 66,320 | re-fetchable, but a 404 saved to disk is still a file |

**Restoring cwpatch after a Battle.net repair:**

```bash
cp /c/bocw/vendor-backup/discord_game_sdk.CWPATCH-13824.dll \
   "/d/Battle.net/Call of Duty Black Ops Cold War/discord_game_sdk.dll"
```

Then confirm F4/F6/F7 respond in game — the file being the right size does not prove the build still
matches the current game binary, and `BlackOpsColdWar.exe` is encrypted at rest so no static check can
tell you.

---

## Why one payload at a time

`injectcw` takes `(script, target, replace)` and **overwrites the replace script's buffer**. Two
injections sharing a replace clobber each other, so coexistence needs two different pairs.

That was tried and **broke the game**: `gunfight_mod` over `core_common\scene_model_shared.gsc` made
leaving a match hang forever on "connecting to lobby". That file declares an empty-bodied subclass,
which looked free to lose — but the frontend uses scene models for menu backgrounds, and a subclass
declaration must still exist at link time.

`clientids_shared.gsc` is the **only** replace target proven safe. Do not substitute another without
testing a **lobby return** — that is the check that catches frontend breakage. Full reasoning and the
other rejected candidates are in [`../docs/notes/menu-map.md`](../docs/notes/menu-map.md).
