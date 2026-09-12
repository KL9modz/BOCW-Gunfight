# Gunfight Host Control — a Windows app for the host

A native GUI that runs the modded Gunfight match from a **real window** (second screen
/ RDP), because the in-game feed is hard-capped at ~4 lines and the dvar that sizes it
(`com_gameMsgWindow1LineCount`) is latched when the HUD builds — measured 2026-09-12,
readback 14 but the feed never grew. So the full control surface moves off the HUD; the
in-game menu stays as the compact ~4-line panel for when you don't have the app up.

## The idea (why this needs almost no new in-game code)

The injected menu (`src/gunfight_menu`) already **re-reads every `gf_*` dvar in
`mod_apply()` at the start of each round**. So:

- **Config** (team size, timer, loadout, spy plane, match limits, map method, menu
  display) = just writing the existing `gf_*` dvars. Takes effect next round, no new
  GSC. The **Config** tab does this today.
- **Actions** (map/gametype switch, fill/remove bots, restart) are not dvars the mod
  reads — they are one-shot operations. The app stages them as `gf_cmd_*` trigger
  dvars; a small **command-poller** added to the menu payload (next increment) watches
  those, runs the operation, and clears the trigger. The **Actions** tab writes the
  triggers now so the wire format is fixed; they do nothing until the poller ships.

So the app's only hard dependency is **reading/writing dvars in the game process**.

## Files

| File | What |
|---|---|
| `gf_control.py` | the tkinter GUI. `python gf_control.py` (dry-run) / `--live` (writes) |
| `dvar_backend.py` | the memory layer: `Proc` (OpenProcess/RPM/WPM/VirtualAllocEx/CreateRemoteThread, mirrored from `tools/lobby-set.py`) + `set_dvar()` via a remote-thread call to the game's dvar setter |

Dry-run works anywhere (no game, no admin) — the GUI opens and logs every dvar it would
write. That is the safe way to review the layout.

## The one reverse-engineering step — "confirm the setter" (klaze runs this)

`set_dvar()` writes a dvar the same way `lobby-set.py` calls `LobbySetMap`: alloc the
name+value strings, write a stub that loads them into `rcx`/`rdx`, `call` the game's own
dvar-set function, run it on a remote thread. It needs that function's address.

We do **not** guess a signature. ate47's builtin table
(`t8-atian-menu/docs/notes/funcs_cw.csv`) gives the **address of the GSC `setdvar`
builtin** — `BlackOpsColdWar.exe+0x3CD62A0` on that build — and that builtin internally
calls the C dvar-set-from-string function with the two strings. So we read the builtin
in-game and decode the call it makes: **address-anchored, not sig-guessed.**
(`BlackOpsColdWar.exe` is encrypted at rest, so this has to run against the live process,
exactly like `lobby-set.py`.) `SETTER_RVA` stays `0` and **live mode refuses** until a
candidate is confirmed to actually move a dvar.

On the test box, game running, **elevated** shell, in `tools/gf-control/`:

1. `python dvar_backend.py --resolve`
   Reads the `setdvar` builtin and prints the C-setter **candidates** it calls, as RVAs.
   (If it errors reading the builtin, your game build differs from `funcs_cw.csv` —
   update `SETDVAR_BUILTIN_RVA`.)
2. `python dvar_backend.py --try 0x<RVA> gf_menu_lines 6`  for each candidate, then open
   the in-game menu. **The candidate that makes the menu's row count change is the
   setter.** (Harmless dvar to poke; visible feedback; same read-back-a-dvar-you-can-see
   method the in-game diagnostic used.)
3. Put that RVA in `SETTER_RVA` in `dvar_backend.py`. Done — `python gf_control.py --live`
   now writes for real.

Fallbacks if the builtin doesn't cleanly resolve: set a validated byte signature in
`SIG_DVAR_SET` instead, or direct value-write (find the dvar struct and poke its value
field, no remote thread) which needs the dvar-pool offset instead.

## Safety / guard

- **Dry-run by default.** Live writes need `--live` **and** a confirmed sig.
- Per the project guard, the agent wrote this; **klaze runs anything that touches game
  memory.** `CreateRemoteThread` is already ruled acceptable on the test box (same as
  `lobby-set.py`). Nothing here is hidden or spoofed — it calls the game's own function.
- Host-local: writing `gf_*` dvars on the host changes only the host's session; the mod
  applies them server-side. Joiners are unaffected.

## Next increment

1. **Command-poller in `src/gunfight_menu`** — a thread that watches `gf_cmd_go` and runs
   `gf_cmd_map`/`gf_cmd_gametype` (session switch), `gf_cmd_fillbots`, `gf_cmd_removebots`,
   `gf_cmd_restart`, then clears `gf_cmd_go`. Turns the Actions tab live.
2. **State read-back** in the app (team size / timer / map / gametype / bots) once the
   dvar-read path is confirmed, so the GUI mirrors the in-game info header.
