# tools

| File | What it is |
|---|---|
| `check-gsc.ps1` | Offline GSC validation — compile, round-trip, resolve every API call and bare builtin |
| `dump-grep.sh` | Offline — resolves builtin argument shapes from stock call sites in `bocw-source`. Writes `dump-report.md`. No game, no network |
| `inject.sh` | Inject **one** payload (`menu` or `mod`) on the known-safe hook/replace pair |
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
/c/bocw/ACTS/bin/acts.exe gscc src/gunfight_mod/scripts/gunfight_mod.gsc \
    -g cw -p pc -o gunfight_mod
mkdir -p /c/bocw/payloads
cp gunfight_mod.gscc /c/bocw/payloads/
```

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

⚠ **Battle.net's repair silently restores the stock SDK.** If F4–F7 stop working mid-session, check
that file's size first. Back up the stock SDK as `discord_game_sdk.dll.orig` before replacing it.

The 13,824-byte DLL is third-party and gitignored (`*.dll`); keep a copy outside the repo.

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
