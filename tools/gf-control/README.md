# Gunfight Host Control — a Windows app for the host

A native GUI that runs the modded Gunfight match from a **real window** (second screen
/ RDP), because the in-game feed is hard-capped at ~4 lines and the dvar that sizes it
(`com_gameMsgWindow1LineCount`) is latched when the HUD builds — measured 2026-09-12,
readback 14 but the feed never grew. So the full control surface moves off the HUD; the
in-game menu stays as the compact ~4-line panel for when you don't have the app up.

> ⚠ **The write path changed 2026-09-13.** `gf_control.py` no longer writes dvars into game
> memory — that route (WriteProcessMemory / the route A/B setter below) was proven **not to
> reach the GSC dvar store** the mod reads. The GUI now sends console `set <dvar> <value>`
> lines through the **in-process bridge** (`tools/gf-bridge/`): the app writes a shared-memory
> block, `gf_bridge.dll` polls it and runs each line via cwpatch's executor, and an in-process
> `set` **does** reach GSC `getdvarint` (proven in-game, T1). Build+inject `gf_bridge.dll` once
> per launch (`tools/gf-bridge/README.md`), then `python gf_control.py --live`. Everything below
> about the two memory-write routes is retained as the **RE record of why external memory-write
> was abandoned**; `dvar_backend.py` remains the read-only anchor/RE toolkit (`--cwpatch` etc.).

## The idea (why this needs almost no new in-game code)

The injected menu (`src/gunfight_menu`) already **re-reads every `gf_*` dvar in
`mod_apply()` at the start of each round**. So:

- **Config** (team size, timer, loadout, spy plane, match limits, map method, menu
  display) = just writing the existing `gf_*` dvars. Takes effect next round, no new
  GSC. The **Config** tab does this today.
- **Actions** (map/gametype switch, fill/remove bots, restart) are not dvars the mod
  reads — they are one-shot operations. The app stages them as `gf_cmd_*` trigger
  dvars; the **command-poller** in the menu payload (`cmd_poll` / `cmd_dispatch` in
  `gunfight_menu.gsc`) watches those, runs the operation, and clears the trigger.
  The map/gametype action has the same two verbs as the in-game pick page:
  **Stage for lobby** writes `gf_cmd_stage=1` with the map/gametype — the mod calls
  `switchmap_load` only, the match keeps running, and the pregame lobby shows the
  staged map when it ends (`docs/notes/session-switch.md` → *Stage*); **Switch NOW**
  (`gf_cmd_stage=0`) is the in-match session switch.

So the app's only hard dependency is **reading/writing dvars in the game process**.

## Files

| File | What |
|---|---|
| `gf_control.py` | the tkinter GUI. `python gf_control.py` (dry-run) / `--live` (sends over the bridge). Its `BridgeBackend` composes `set <dvar> <value>` lines and hands them to `tools/gf-bridge/bridge_channel.py` |
| `dvar_backend.py` | **no longer the GUI's write path** (see the banner above). Retained as the read-only anchor/RE toolkit: `Proc` (OpenProcess/RPM/WPM/VirtualAllocEx/CreateRemoteThread, mirrored from `tools/lobby-set.py`) + the `--cwpatch/--finddvar/--dumpabs` CLI. The `set_dvar()` memory-write routes are documented below as the retired approach |

Dry-run works anywhere (no game, no admin) — the GUI opens and logs every dvar it would
write. That is the safe way to review the layout.

## The write primitive — anchored on cwpatch (klaze runs the in-game steps)

`set_dvar()` needs one thing the app cannot get any other way: a way to reach a dvar
inside the running game. The exe is encrypted at rest, so nothing can be resolved
statically — but **cwpatch already resolved it, in-process.** The 13 KB
`discord_game_sdk.dll` in the game folder (`docs/notes/unlock-dlls.md`; `tools/ensure-cwpatch.ps1`
keeps it there) signature-scans the decrypted exe at `DiscordCreate` and stores the
results in its own `.data`. Read out of the DLL statically on 2026-09-12:

| `discord_game_sdk.dll +` | holds | resolved 2026-09-12 (`BlackOpsColdWar.exe +`) |
|---|---|---|
| `0x5658` | `Dvar_FindVar(u64 hash)` → `dvar_t*` | `0xbf88690` |
| `0x5660` / `0x5668` | `Dvar_RegisterBool` / `Dvar_SetBool(dvar*, 1, 0)` | `0xbf9d6c0` / `0xbf8dfe0` |
| `0x5638` | the command executor behind F4/F6/F7 | `0x3ace080` |
| `0x5640` / `48` / `50` | the `hostmigration_start\n` / `checkpoint_restart\n` / `mission_restart\n` literals it overwrites to run a command | `0xd6a5cb0` / `cc8` / `d88` |

Plain `ReadProcessMemory` reads those — no code runs. `dvar_backend.py` also carries
cwpatch's seven byte-signatures as a fallback (Battle.net regularly puts the stock SDK
back; `--cwpatch` tells you which DLL is loaded — cwpatch's image is `0x9000` bytes,
the stock SDK's `0x3b8000`). ✅ **Verified on the live game 2026-09-12:** `--cwpatch`
read the slots and re-derived every one of the seven by signature; both methods
agreed on all seven and the three literals read as expected.

🪦 **Retired:** calling the GSC `setdvar` builtin (`+0x3CD62A0`) on a remote thread.
Measured: it works inline inside the script VM, its only calls are error helpers, and a
wrong call **wedges the game** — a stuck remote thread blocks every later
`CreateRemoteThread` until relaunch. `--resolve`/`--try` are gone for that reason.

### Two routes, and the steps that confirm them

**A — DIRECT (ints).** `Dvar_FindVar(hash)` is a pure lookup that returns NULL on a
miss, and cwpatch itself calls it from a foreign thread, so it is safe on a remote
thread. It hands back the real `dvar_t*`; the value's offset inside it is pinned once
by watching which cell moves when the in-game menu changes the dvar. After that a
write is one `WriteProcessMemory` of an int32 — no game code runs at all.

On the test box, game up (fresh launch — a wedged thread from an earlier session
blocks remote calls), cwpatch loaded, in `tools/gf-control/`:

1. `python dvar_backend.py --cwpatch` — read-only. Every row must say **yes**.
2. Be **one round in** with the current payload — `dvars_register()` creates every
   `gf_*` dvar on the first `mod_apply`, so they all exist by then. (With an older
   payload that lacks it, touch `gf_menu_lines` in the menu once instead; the GSC only
   *reads* these dvars, so nothing is in the registry until something `setdvar`s it.)
3. `python dvar_backend.py --findvar gf_menu_lines` — one remote call, prints the
   `dvar_t*` and an annotated dump. NULL means step 2 was skipped.
4. `python dvar_backend.py --diff 0x<that address>` — snapshot; change the rows again
   in the menu (3 → 4); Enter. It prints every int32 that moved, as a **path** — the
   cell whose old→new matches what you set is `current`. Paste it into
   `DVAR_INT_PATH` (`(0x18,)` for a direct field, `(0x28, 0x0)` if it sits behind a
   pointer).
5. `python dvar_backend.py --poke 0x<that cell> 5` and open the menu: rows = 5 means
   the write lands. `python gf_control.py --live` now writes every int config dvar.

Strings (`gf_cmd_map`, `gf_cmd_gametype`) are **refused** on this route on purpose — a
string dvar's value is engine-owned storage. Either the GSC grows an int index for the
map/gametype pick, or route B carries them.

**B — EXEC (everything). 🪦 TESTED 2026-09-12 AND RULED OUT.** The idea: park
`set <dvar> <value>\n` in one of the game's command-string literals, `CreateRemoteThread`
on the executor, restore the 48 bytes — which would carry strings and create dvars too.
Disassembly (`scratchpad/disasm.py`) confirmed the mechanism exactly: the executor at
`+0x5638` reads the command blob and takes no arguments, and cwpatch drives F4/F6/F7
through it. But when called via `CreateRemoteThread`:

- `Dvar_FindVar(gf_exec_probe)` returned NULL (not registered), then `--exec
  "set gf_exec_probe 777"` ran — and the **executor never returned** (5 s timeout). The
  game kept rendering and stayed responsive, but the next `Dvar_FindVar` (which had
  returned instantly moments before) now **hung**: the executor had taken the dvar-system
  lock to create the dvar and blocked while holding it, so every later dvar call waits
  on a lock that is never released. **Recovery is a game relaunch.**
- Why cwpatch gets away with the same executor: its commands (`fast_restart` /
  `full_restart` / `lobbylaunchgame`) tear the match down, so the executor not returning
  cleanly never matters. `set` is the first caller that needed a clean return, and it
  exposed the problem. (A `set` likely defers onto the main game thread and the remote
  thread blocks on that hand-off.)

So **route A is the live path.** `--exec` now refuses without `--force`, and
`EXEC_ROUTE_CONFIRMED` stays `False`. If strings are ever needed through the executor,
they'd have to be driven from a thread the game already pumps (cwpatch's hotkey hook
is the proof that works) — not a raw `CreateRemoteThread`.

**GSC pre-register (shipped).** `dvars_register()` in `gunfight_menu.gsc` (called first
thing in `mod_apply` each round) `setdvar`s every `gf_*` dvar to its default *when
unset* (guarded so it never overwrites a host's choice). So from the first round onward
the dvars exist and `--findvar` never meets a NULL — step 2 above (touching
`gf_menu_lines` in the menu) is then unnecessary. Route A needs this; it cannot find a
dvar nothing ever set.

## Safety / guard

- **Dry-run by default.** Live writes need `--live` **and** a confirmed route (`DVAR_INT_PATH` pinned, or `EXEC_ROUTE_CONFIRMED`).
- Per the project guard, the agent wrote this; **klaze runs anything that touches game
  memory.** `CreateRemoteThread` is already ruled acceptable on the test box (same as
  `lobby-set.py`). Nothing here is hidden or spoofed — route A calls the game's own lookup and writes one int; route B does exactly what cwpatch does on F6.
- Host-local: writing `gf_*` dvars on the host changes only the host's session; the mod
  applies them server-side. Joiners are unaffected.

## Next increment

1. ✅ **Command-poller in `src/gunfight_menu`** — shipped: watches `gf_cmd_go` and runs
   `gf_cmd_map`/`gf_cmd_gametype` (+ `gf_cmd_stage`), `gf_cmd_fillbots`, `gf_cmd_removebots`,
   `gf_cmd_restart`, then clears the triggers. The Actions tab is live once dvar writes are.
2. **State read-back** in the app (team size / timer / map / gametype / bots / staged map)
   once the dvar-read path is confirmed, so the GUI mirrors the in-game info header.
