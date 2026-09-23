# Gunfight Host Panel — the native control app (`tools/gf-panel/`)

A **C# / .NET 9 WPF** desktop app that runs the modded Gunfight match from a real window, modelled on
klaze's BO1 rcon tool (sidebar with SERVER / SCOREBOARD / PLAYERS + NEXT MATCH / ACTIVITY, tabs
FAVORITES · DASHBOARD · MATCH · MAPS · ADVANCED · TOOLS · CONSOLE · SETUP, global search, pills, right-click
menus, toasts, a sent→received command queue). It carries **every page and sub-option of the in-game
menu** plus the rcon-only features BOCW can support (everyone-state, match control, fun & vision, a
private-match rotation, presets, bot profiles, next-match team staging, session bans).

Built 2026-09-20 (klaze: *"i just want a windows app similar to .net or qt"*, friends must run it with
nothing installed). It replaces `tools/gf-control` (tkinter), which stays untouched until retired.

## Run / build

| | |
|---|---|
| dev run | `dotnet run --project tools\gf-panel\GfPanel` (live) · add `--dry` to log the commands and send nothing · `--tab tools` opens a tab |
| build | `dotnet build tools\gf-panel\GfPanel` — headless, ~10 s, no NuGet packages (works offline) |
| ship | `powershell -ExecutionPolicy Bypass -File tools\gf-panel\publish.ps1 -Payload C:\bocw\payloads\gunfight_menu.props.gscc` → `tools\gf-panel\dist\gf-panel\` |
| shortcuts | `powershell -ExecutionPolicy Bypass -File tools\gf-panel\shortcuts.ps1 [-Exe <GfPanel.exe>]` — desktop + Start Menu shortcuts and a taskbar pin (Explorer's own pin verb through a temporary `{:}` handler key; measured working on Windows 11 26200, the pin lands ~3 s after the call) |

The bundle is a **self-contained single-file exe** (the .NET runtime is inside, ~58 MB) beside the same
folders the old bundle carried: `acts\` (the injector, 61 MB — *without* the 506 MB decrypted-exe dump),
`gf-bridge\gf_bridge.dll`, `vendor\` (cwpatch, hash-checked before it is ever copied), `payloads\`.
Total ≈ 120 MB. Friends need Windows 10/11 x64 and the game; nothing else. Per-user state (prefs,
saved tracks, crash log) lives in `%LOCALAPPDATA%\GfPanel\`.

⚠ Same caveats as before: pinned to the current game build + cwpatch; AV flags injectors; keep it to a
trusted group (the project's throwaway-PC / blast-radius rule).

## Overlay — the panel over the game

Press **Insert** in the game (SETUP → OVERLAY: on/off, the key, the layout) and this window lays itself
over BOCW — borderless, on top, right-hand side by default so the game shows on the left. Insert again,
Esc, the header's **⤶ Back to game**, or a click on the game puts it back where it was and returns the
focus to the game. It is the same window with every tab; nothing is drawn inside the game (no DLL, no
hook). Needs **Display Mode = Fullscreen Borderless**. While it is up the game gets no input, so pause
the match first mid-round. Never run on Windows yet — design, unknowns and the test sheet:
`docs/notes/gf-panel.md` §6.

## How it talks to the game

**Writes** — the in-process bridge (`tools/gf-bridge`): every button composes console `set …` lines
into the named shared-memory block `gf_bridge`, one command per message, 80 ms apart, ≤ 47 bytes each
(a longer `set` overflows cwpatch's slot and hard-crashes the game — the sender refuses it). A
**command** = its payload + `set gf_cmd_seq N` + `set gf_cmd_go 1`; the GSC records N as the ack in
GFSTATE and ignores a repeated N, so the panel retries a dropped packet safely (up to 3×, 5 s apart).

**Reads** — read-only memory sweeps for the marked strings the mod keeps alive in level fields
(`Native/MemoryScanner.cs`, the roster_scan.py primitive: OpenProcess VM_READ + VirtualQueryEx +
ReadProcessMemory; no thread, no write). One tick every 1.5 s: remembered addresses first, then a 16 MB
window around them, then the last region, then the exe-image regions (506 MB, 0.7 s measured); while
nothing is found (lobby, no match) that runs every 5 s, and a whole-process sweep (9 GB, 21 s measured)
runs once per game process a minute in, never again. The header shows the sweep time and how it was found.

| marker | from | carries |
|---|---|---|
| `GFSTATE` | `state_publish()` (new, 1 s) | map, gametype, round, scores, alive/players/bots per side, spectators, time limit + passed, phase, overtime, paused, frozen, staged map/gt, maxclients, team size, timer, **ack seq**, everyone-state flags, host, **last menu_say text** |
| `GFPLAYERS` | `players_publish()` (new, on change) | entnum;name;team;kind;xuid;alive;score;kills;deaths;flags (g god · f fly · t third person · z frozen · v riding) |
| `GFCFG` | `config_publish()` | the packed chunks gf_c0..c8 + oob/bar/trk/veh/bot/bot2 + (new) race/dbg/misc extras = every host setting's live value |
| `GFROSTER` | `roster_publish()` | the older 4-field roster (fallback when a payload lacks GFPLAYERS) |
| `GFMAP*` | `mapdata_publish()` (opt-in `gf_mapscan`) | per-map vehicle / prop / spawn / destructible census |

**Settings writes** mirror the in-game menu exactly: a packed field rebuilds *its* chunk with the other
five cells taken from the game's live values (never app defaults — the F4 "packed-chunk contamination"
that used to reload the match), the bot knobs rebuild `gf_bot`/`gf_bot2`, a plain dvar is a plain
`set`; then one `apply <scope>` pulse for a field a live subsystem owns. A packed write is **refused until
the first GFCFG readback** has landed. Structural fields (team size, limits) offer a match restart.

## GSC increment (2026-09-20, `gunfight_menu.gsc`, side payload `gunfight_menu.panel.gscc`; superset with
props + proj diag = `gunfight_menu.props.gscc`)

`state_publish` / `players_publish`; `gf_cmd_seq` acks + dedupe in `cmd_poll`; `gf_cmd_say_aud`
(all / allies / axis / a player) in the say branch; `level.gf_lastsay` in `menu_say`; `perks_apply` per
spawn; `app_on_connect` (joiner order, session bans, staged side, everyone-state catch-up); and the
verbs `panel_verb` dispatches from `cmd_action`'s default case:

| verb | arg | does |
|---|---|---|
| `godall` / `thirdall` / `invisall` / `freezeall` / `drunk` | `on`/`off` | everyone |
| `ammoall` · `quake` | — | max ammo everyone alive · one strong earthquake per player |
| `perkall` | `<key>` / `-<key>` / `clear` | the everyone-perk set (re-given each spawn); `perkone` (+target) one player |
| `vision` | name | `visionsetnaked( name, 1 )` level-wide (`default`, `mpOutro` stock) |
| `sound` | alias | `playsoundtoplayer` to everyone |
| `giveall` | weapon | give + switch, everyone alive |
| `slowmo` | 10..300 | `setslowmotion( 1, pct/100, 0.5 )` — the timescale lever (untested standing) |
| `endround` | `allies`/`axis`/`draw` | gunfight's own end-round path (`round::set_winner` + `globallogic::function_a3e3bd39`, reason 1) |
| `restartround` | — | `map_restart( true )` — replay the round, scores kept (untested) |
| `balance` | — | even the HUMAN split (newest joiner moves) |
| `stage` (+target) `a`/`x`/`s`/`-` · `stageapply` · `stageclear` | | next-match sides, applied at connect |
| `ban` (+target) · `banx <xuid>` · `unbanx <xuid>` · `banclear` | | kick + refuse at connect, this session (the panel re-sends its list at every match start) |
| `perkall all` | — | every key of `perk_keys()` in one command (Select all perks) |
| `gf_respawns` (setting) | 0/1/2 | lobby's value / unlimited lives (`playernumlives` 0) / one life - applied each round start |
| `forge enter|exit|place|next|prev|clear` (forge session) | | the in-game prop placer; `hintset others|build` + `gf_ho0/1/2` chunks set the hint-bar lines; `gf_hint_nav` the menu legend |

All built 2026-09-20, **NEVER RUN in-game** — the panel marks the untested ones in their tooltips.
Hardening from the first live run (same day): `state_publish` / `players_publish` build each tick in a
child thread and `cmd_poll` dispatches each verb in one, so a runtime error kills only that tick / verb;
a failed state build still publishes a fallback line with `err=<count>|st=<stage>` (the header shows it).

## Layout of the code

```
GfPanel/
  Native/    Win32.cs (P/Invoke) · User32.cs (the overlay's hotkey + window calls) · GameProcess.cs · MemoryScanner.cs · BridgeChannel.cs (+ the paced BridgeSender) · Injector.cs
  Game/      Schema.cs (every setting, its default, tip, scope) · Packing.cs (gf_c0..c8 / gf_bot order — load-bearing) ·
             Channels.cs (GFSTATE/GFPLAYERS/GFCFG/GFMAP parsers) · Catalog.cs (maps, weapons, vehicles, perks, sounds…) · Commands.cs
  Services/  GameLink.cs (the tick, acks, queue) · ConfigWriter.cs · Prefs.cs · TracksService.cs · PropCatalog.cs (embedded map-props.json)
  ViewModels/ Main · Settings rows/sections · Players · Tools · Props · Message · Maps (+ playlist) · Bots · Console · Inject · Toasts · Overlay
  Views/     Theme (Theme/Theme.xaml) · Templates.xaml (row / section / player / toast / tile templates) · the tab UserControls
```

## Test order (needs the game + a payload that publishes GFSTATE)

1. SETUP → the payload defaults to the LIVE slot (`payloads\gunfight_menu.gscc`); for the panel's own
   features Pick… a build that publishes GFSTATE (`gunfight_menu.props.gscc` = the superset) → Set up all
   → restart the match → the header badge goes **● Connected**, the sidebar fills (map, round, scores,
   timer), PLAYERS lists the roster.
2. A toggle on DASHBOARD (e.g. Passive bots) → the command queue shows ⏳ → ✓ received, the readback
   confirms the value (UNREAD pill gone), the activity log shows the game's `app: …` ack.
3. MATCH tab: pause / resume (proven verbs) → then the new ones one at a time: END → ALLIES, RESTART
   ROUND, BALANCE HUMANS, FREEZE ALL. TOOLS: god ALL, ammo ALL, perks, vision, drunk, sound, timescale, props / barrels.
4. MAPS: Stage for lobby → the sidebar shows `next: …`; rotation ON with two maps → the next match stages.
5. CONSOLE: `set gf_cmd_action countdown` + Send + go → 5..1 GO renders.
6. Overlay (game in Fullscreen Borderless): Insert in a match → the panel over the right side, cursor
   usable → Insert → back to the game with input. The five-step sheet and what each failure means:
   `docs/notes/gf-panel.md` §6.
