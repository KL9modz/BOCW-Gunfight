# Gunfight Host Panel — the native control app (`tools/gf-panel/`)

A **C# / .NET 9 WPF** desktop app that runs the modded Gunfight match from a real window, modelled on
klaze's BO1 rcon tool (sidebar with SERVER / SCOREBOARD / PLAYERS + NEXT MATCH / ACTIVITY, pages
MATCH · PLAYERS · RULES · MAPS & SPAWNS · SANDBOX · FORGE · DIAGNOSTICS · SETUP — see [Pages](#pages) — global
search, pills, right-click menus, toasts, a sent→received command queue). It carries **every page and sub-option of the in-game
menu** plus the rcon-only features BOCW can support (everyone-state, match control, fun & vision, a
private-match rotation, presets, bot profiles, next-match team staging, session bans).

Built 2026-09-20 (klaze: *"i just want a windows app similar to .net or qt"*, friends must run it with
nothing installed). It replaces `tools/gf-control` (tkinter), which stays untouched until retired.

## Run / build

| | |
|---|---|
| dev run | `dotnet run --project tools\gf-panel\GfPanel` (live) · add `--dry` to log the commands and send nothing · `--tab sandbox` opens a page (or a sub-tab: `spawns`, `entities`, `console`; the pre-redesign names still work) |
| build | `dotnet build tools\gf-panel\GfPanel` — headless, ~10 s, no NuGet packages (works offline) |
| checks | `dotnet run --project tools\gf-panel\GfPanel.Tests` — the offline checks, no game needed, Windows or Linux: the game-line parsers, the 47-byte command slot, match tracking, and the contract with `gunfight_menu.gsc` (verbs, packed settings, defaults, index lists). Exit code 1 on a failure; `-- verb` runs only checks whose name contains "verb", `-- --list` lists them. **Run after any change to the panel or the payload.** `docs/notes/gf-panel.md` §10 |
| ship | `powershell -ExecutionPolicy Bypass -File tools\gf-panel\publish.ps1 -Payload C:\bocw\payloads\gunfight_menu.props.gscc` → `tools\gf-panel\dist\gf-panel\` |
| shortcuts | `powershell -ExecutionPolicy Bypass -File tools\gf-panel\shortcuts.ps1 [-Exe <GfPanel.exe>]` — desktop + Start Menu shortcuts and a taskbar pin (Explorer's own pin verb through a temporary `{:}` handler key; measured working on Windows 11 26200, the pin lands ~3 s after the call) |

The bundle is a **self-contained single-file exe** (the .NET runtime is inside, ~58 MB) beside the same
folders the old bundle carried: `acts\` (the injector, 61 MB — *without* the 506 MB decrypted-exe dump),
`gf-bridge\gf_bridge.dll`, `vendor\` (cwpatch, hash-checked before it is ever copied), `payloads\`.
Total ≈ 120 MB. Friends need Windows 10/11 x64 and the game; nothing else. Per-user state (prefs,
saved tracks, crash log) lives in `%LOCALAPPDATA%\GfPanel\`.

**Saved logs** (2026-09-23): everything the ACTIVITY list shows is also written to
`%LOCALAPPDATA%\GfPanel\logs\activity-YYYY-MM-DD.log` (one file a day, kept 90 days; ACTIVITY → 📂 saved
logs), plus how each match ended (normal end / ended by the panel / ⚠ dropped mid-match, with the last
state line, the roster and the last menu actions) and every player's menu actions from the game's
`GFLOG` line. Details: `docs/notes/gf-panel.md` §6. `GFPANEL_DATADIR=<folder>` points a test instance at
its own prefs and logs.

⚠ Same caveats as before: pinned to the current game build + cwpatch; AV flags injectors; keep it to a
trusted group (the project's throwaway-PC / blast-radius rule).

## Pages

The 2026-09-24 redesign (klaze: *"reorganize and improve its usability and clarity … without losing any
functionality"*). **MATCH holds the actions a host takes every match; every setting lives on one home page and
can be pinned (☆) onto MATCH.** Pins take setting rows only, so the actions klaze named — map / mode, restart,
bots, spawn layout, menu access, broadcasts — are MATCH blocks in their own right. The sidebar (status,
roster, next-match plan, ACTIVITY log) is on every page.

| Page | What is on it |
|---|---|
| **MATCH** (opens here) | MAP & MODE (stage / switch now, rotation on-off) · ROUND & MATCH (restart round / match, reload map, pause / resume, end round → side / draw, end match) · ★ PINNED SETTINGS (every ☆ pin — seeded once with round time, first-to, round cap, jump height, gravity) · BOTS (fill / remove, add one, even up, both-sides difficulty) · SPAWN LAYOUT (the running map's layouts, use / use + restart) · MOD MENUS (everyone / one player) · MESSAGES — BROADCAST · EVERYONE (freeze all, balance humans) |
| **PLAYERS** | PLAYER — pick one (or right-click a roster row → *Open on the PLAYERS page*) and every right-click action is a button: menus, powers, loadout, teleport, team, fun pack, moderation · EVERYONE & YOU (god / ammo / 3rd person / invisible for all, the host's fly / drop / unlock) · PERKS — EVERYONE · BANS (unban one or all) |
| **RULES** | the match settings: GUNFIGHT MATCH · LOADOUT & CAMO · OVERTIME ZONE · BOTS · CUSTOM BOT TUNING · MOVEMENT · bot presets & profiles · CONFIG PRESETS |
| **MAPS & SPAWNS** | sub-tabs **MAPS** (the grid, rotation, SESSION / MAP) and **SPAWN ATLAS** (the atlas, its layouts and SPAWN SETTINGS) |
| **SANDBOX** | radar & markers, world & vision, movement fun, weapons & cosmetics, disguises, projectiles & map toys, teleport, streaks, vehicles (+ VEHICLE MODE), race (+ RACE SETTINGS) |
| **FORGE** | sub-tabs **BUILD** (props & barrels, place / forge mode, forge tools, PLACEMENT & PROMPTS, FORGE CONTROLS) and **SPAWNED ENTITIES** (the live list; read from the game only while it shows) |
| **DIAGNOSTICS** | sub-tabs **DEBUG & HUD** (feed readouts & probes, text tests, menu backdrop, hint bar lines, IN-GAME MENU DISPLAY, DEBUG FEED) and **CONSOLE** |
| **SETUP** | status, inject, panel options |

Every roster row carries a **☆ / ★** that gives / takes back that player's client menu in one click (not on
the host or bots). Search (`/`) finds any setting and opens its home page.

**Where the old tabs went:** FAVORITES → MATCH → ★ PINNED SETTINGS · DASHBOARD → RULES (its live actions →
MATCH) · MAPS / SPAWNS → MAPS & SPAWNS · ADVANCED → split by subject: SESSION / MAP → MAPS, VEHICLE MODE + RACE
SETTINGS → SANDBOX, PLACEMENT & PROMPTS → FORGE, IN-GAME MENU DISPLAY + DEBUG FEED → DIAGNOSTICS · TOOLS →
SANDBOX, with PLAYER STATE → PLAYERS, FORGE & HINT BAR → FORGE / DIAGNOSTICS, feed readouts → DIAGNOSTICS ·
ENTITIES → FORGE → SPAWNED ENTITIES · CONSOLE → DIAGNOSTICS → CONSOLE · the sidebar's ban list → PLAYERS → BANS.
Nine controls that duplicated another were dropped, each for the one that sends the same verb or dvar:
`docs/notes/gf-panel.md` §11.

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
| `GFSTATE` | `state_publish()` (new, 1 s) | map, gametype, round, scores, alive/players/bots per side, spectators, time limit + passed, phase, overtime, paused, frozen, staged map/gt, maxclients, team size, timer, **ack seq**, everyone-state flags, host, **last menu_say text**; since 2026-09-23 also match id `mid=`, match over `mo=`, entity count `ents=`, newest menu-log seq `lg=`; entity-list stamp `ev=` (bocw-84) |
| `GFLOG` | `gflog_add()` (2026-09-23, on every menu action) | every player's menu actions (host + granted clients) and forge place/delete: seq, time, who, page, item, the action's confirmation — collected when `lg=` moves, written to the saved log |
| `GFPLAYERS` | `players_publish()` (new, on change) | entnum;name;team;kind;xuid;alive;score;kills;deaths;flags (g god · f fly · t third person · z frozen · v riding · **m has a client menu** · **F forge mode**, 2026-09-23) |
| `GFCFG` | `config_publish()` | the packed chunks gf_c0..c8 + oob/bar/trk/veh/bot/bot2 + (new) race/dbg/misc extras = every host setting's live value |
| `GFENTS` | `ents_publish()` (2026-09-23, rebuilt 1 s, republished on change) | every prop / barrel / vehicle the mod spawned that is still in the level, in ≤ 880-char numbered chunks (max 16): `GFENTS\|<stamp>\|<i>\|<n>\|kind,entnum,label,owner,dist,x,y,z,flags;…\|END` (kind p/b/v, flags o occupied · m vehicle-mode ride) — collected while FORGE → SPAWNED ENTITIES is open and `ev=` moves |
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
| `menuall` (bocw-84, 2026-09-23) | `on`/`off` | give / take back the client mod menu for every human except the host (the one-player form stays `forgegrant on\|off` + target) |
| `tpto` (+target = who moves) | player name (prefix ok) | put the target in front of that player, facing them (right-click → Teleport → Them to player) |
| `entdel` | entnum | delete one mod-spawned prop / barrel / vehicle; re-checked in GSC (ours only, never an occupied vehicle); a prop also leaves the saved forge layout |
| `entclear` | `props`/`vehicles`/`all` | props = forge clear (layout too); vehicles = every EMPTY spawned vehicle |
| `radar` | n | writes `gf_radar` = host bits + 256 × everyone bits + 65536 × marker icon (bits 1 minimap · 2 UAV · 4 H.A.R.P. · 8 markers · 16 glow); `radar_think` applies it within 0.5 s, no reload |
| `parachute` | `0`/`1`/`2` | `gf_parachute` off / everyone / host only — armed per player per spawn, no reload |
| `matchinfo` · `spawnreport` · `zonecensus` | — | the feed readouts that were in-game Debug / Spawns / Zone rows until 2026-09-23 (DIAGNOSTICS → FEED READOUTS & PROBES) |
| `nltest` (2026-09-24) | `centre`/`feed` | ONE print carrying newlines (the cloud branch's hud_probe stage 23): `iprintlnbold` with two `\n` / `iprintln` with one - never the hint widget (a `\n` there closed the match). Close the in-game menu first |
| `fun` (2026-09-24, the cloud branch's fun pack) | `<what> [args]` (+target for the per-player ones) | `flybind on\|off` · `slide <pct>` · `slidesuper <n>` · `slidehold`/`slidechain on\|off` · `disco on\|off` / `disco all on\|off` / `disco none` · `disg random\|next\|prev\|off` / `disg pick <i>` · `disgsize <x>` · `disgheight <z>` · `ft spin <0-2\|-1>` / `ft move <kind>` / `ft link 1\|0` / `ft solid` / `ft delete` / `ft speed <s>` / `ft rev on\|off` / `ft tilt <p> <r>` / `ft spray <ms>` / `ft autolink on\|off` · `propgun on\|off` · `projcount <n>` · `nadeswap on\|off` / `nadeswap all on\|off` / `nadeswap none` / `nadeswapw <i>` · `cannon on\|off` · `cannonblast`/`cannonride`/`cannonkeep on\|off` · `cannonmodel <i>` - explicit on/off, picks by index (GSC `fun_verb`) |

All built 2026-09-20, **NEVER RUN in-game** — the panel marks the untested ones in their tooltips.
Hardening from the first live run (same day): `state_publish` / `players_publish` build each tick in a
child thread and `cmd_poll` dispatches each verb in one, so a runtime error kills only that tick / verb;
a failed state build still publishes a fallback line with `err=<count>|st=<stage>` (the header shows it).

## Layout of the code

```
GfPanel/
  Native/    Win32.cs (P/Invoke) · GameProcess.cs · MemoryScanner.cs · BridgeChannel.cs (+ the paced BridgeSender) · Injector.cs
  Game/      Schema.cs (every setting, its default, tip, scope) · Packing.cs (gf_c0..c8 / gf_bot order — load-bearing) ·
             Channels.cs (GFSTATE/GFPLAYERS/GFCFG/GFMAP parsers) · Catalog.cs (maps, weapons, vehicles, perks, sounds…) · Commands.cs
  Services/  GameLink.cs (the tick, acks, queue) · ConfigWriter.cs · Prefs.cs · TracksService.cs · PropCatalog.cs (embedded map-props.json)
  ViewModels/ Main · Settings rows/sections · Players · Tools · Props · Message · Maps (+ playlist) · Bots · Console · Inject · Toasts
  Views/     Theme (Theme/Theme.xaml) · Templates.xaml (row / section / player / toast / tile templates) · one UserControl per page:
             Match · Players · Rules · Maps + Spawns · Sandbox · Forge (+ Entities) · Diagnostics (+ Console) · Setup · Sidebar
```

## Test order (needs the game + a payload that publishes GFSTATE)

1. SETUP → the payload defaults to the LIVE slot (`payloads\gunfight_menu.gscc`); for the panel's own
   features Pick… a build that publishes GFSTATE (`gunfight_menu.props.gscc` = the superset) → Set up all
   → restart the match → the header badge goes **● Connected**, the sidebar fills (map, round, scores,
   timer), PLAYERS lists the roster.
2. A toggle on RULES (e.g. BOTS → Passive bots) → the command queue shows ⏳ → ✓ received, the readback
   confirms the value (UNREAD pill gone), the activity log shows the game's `app: …` ack.
3. MATCH: pause / resume (proven verbs) → then the new ones one at a time: END → ALLIES, RESTART
   ROUND, BALANCE HUMANS, FREEZE ALL. PLAYERS: god ALL, ammo ALL, perks. SANDBOX: vision, drunk, sound,
   timescale. FORGE: props / barrels.
4. MATCH → MAP & MODE: Stage for the lobby → the sidebar shows `next: …`; rotation ON with two maps (MAPS &
   SPAWNS → MAPS) → the next match stages.
5. DIAGNOSTICS → CONSOLE: `set gf_cmd_action countdown` + Send + go → 5..1 GO renders.
