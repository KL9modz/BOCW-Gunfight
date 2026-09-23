# The native control app — `tools/gf-panel/` (2026-09-20)

**What:** klaze's BO1 rcon tool (`Gunfight-dev/tools/rcon`: a Node server + browser panel) rebuilt for
BOCW as a **native C# / .NET 9 WPF app**, published as a self-contained single-file exe so friends run it
with nothing installed. Decisions that shaped it (klaze, same day): *"why web? i just want a windows
app similar to .net or qt"* (a browser panel was proposed and rejected), *"which one will allow my
friends to run the exe without additional software/drivers"* (→ self-contained), *"have every single
feature and sub option from our bocw mod menu and also anything we can possibly replicate that the rcon
has"*. `tools/gf-control` (tkinter) is untouched until retired.

`tools/gf-panel/README.md` is the operating doc (run / build / ship, the channels, the verbs, the test
order). This note records the design facts and what is and is not measured.

## 1. Feature map — rcon block → panel

| rcon (BO1) | panel (BOCW) | how |
|---|---|---|
| SERVER card, SCOREBOARD, alive counts, clock | sidebar SERVER / SCOREBOARD + timer | **GFSTATE** (new publisher, 1 s) |
| PLAYERS table (num, name, score, ping, IP, GUID) + team groups | PLAYERS (entnum, name, team, alive, score, K/D, flags, XUID) grouped by side | **GFPLAYERS** (new, on change); no ping / IP in a P2P private match |
| right-click: kick / ban / message / team move / next-round queue / god / freeze / perks / noclip / locate | right-click: message, move, next-match stage, god, ammo, 3rd person, fly, freeze, speed, give weapon / perk / cosmetics, take / strip, kill, teleport (to me / me to them / swap), copy name / XUID, kick, ban | the menu's per-client verbs (`gf_cmd_target` + `*one`) + new `stage` / `ban` |
| NEXT MATCH staging (one-shot `gf_teamstage`) | NEXT MATCH tab: plan per XUID, Apply now, re-sent at every new match | `stage` (+target) / `stageapply` / `stageclear`; `app_on_connect` seats a staged joiner |
| MATCH CONTROL: start, pause, end round → team, restart round / match, map restart, balance | pause / resume · END → A / X / DRAW · ↺ ROUND · ↻ MATCH · BALANCE · 5..1 GO · ± bots | `endround` = gunfight's own `endround()` minus its page dressing; `restartround` = `map_restart( true )`; `balance` = newest-joiner human move |
| DASHBOARD data-driven blocks + pills (LIVE / NEXT / RESTART / STICKY…) | DASHBOARD + ADVANCED sections from `Game/Schema.cs`; pills LIVE / NEXT / RESTART + UNREAD | every `cfg_*` reader of the GSC, defaults = the GSC's own |
| BOTS: add / kick, per-team ±, fill, difficulty chips, CUSTOM, named profiles | the same + the GSC's four custom presets + named profiles (the 15 knobs) | `gf_bot` / `gf_bot2` packs, `apply bots` |
| PLAYER STATE (god / ammo / perks all) | PLAYER STATE — EVERYONE + PERKS grid | new `godall` / `ammoall` / `thirdall` / `freezeall` / `invisall` / `perkall` |
| FUN & VISION (vision sets, 3rd person, explosive bullets, melee range, drunk, invisible, quake) | vision (`visionsetnaked`, level-wide), drunk, quake, sound, invisible, timescale; explosive bullets ≈ the Projectiles page | new `vision` / `drunk` / `quake` / `sound` / `slowmo`; melee range has no T9 lever |
| MOD TOOLS (give weapon, bullet mode, ride grenade, positions, Gersh, sound, team names, splash) | give me / give EVERYONE, projectiles, teleport gun / grenade, save point, sound; team names have no T9 builtin; splash = the centre print | existing verbs + `giveall` |
| ADMIN message composer (channel / audience / duration / colours / presets) | MESSAGES: centre / feed / banner · all / allies / axis / a player · once / N s / held · ^colours · presets | `gf_cmd_say*` + new `gf_cmd_say_aud` |
| MAPS: gametype picker, rotation editor (live + save to cfg), map grid with LIVE / NEXT | MAPS: Stage for lobby / Switch NOW, the grid (LIVE / NEXT badges), a **panel-driven rotation** | private matches have no engine rotation: the panel stages the next entry 20 s into every new match |
| Save to dedicated.cfg | CONFIG PRESETS (snapshot of every setting; apply sends only the diff) | prefs.json |
| CONSOLE (custom dvar set / read, command reference, history) | CONSOLE: any console command over the bridge (+ optional go pulse), quick commands, history; no reply channel exists | cwpatch's executor runs it |
| FAVORITES pinboard, global search, collapsible blocks, tooltips, toasts, command queue with acks + retry, activity log, join/leave notify + beep, resizable sidebar | all of it | acks = `gf_cmd_seq` echoed in GFSTATE; retry re-sends the SAME seq (the GSC ignores a repeat) |
| Geo-IP, Discord bot, dedicated.cfg, aimbot / account editors | not applicable / not wanted | — |

## 2. The read channel — measured facts it rests on, and what is new

- The primitive: `roster_scan.py`'s read-only sweep (OpenProcess VM_READ + VirtualQueryEx + RPM),
  proven safe mid-match. The script string pool is one private RW region inside the exe image range
  (~500 MB; ~0.5 s per sweep in Python). `Native/MemoryScanner.cs` ports it with three cheaper steps in
  front (remembered addresses → a 16 MB window around them → the last region) because GFSTATE changes
  every second and a 500 MB sweep per tick would be the panel's whole CPU budget. ⚠ Whether the window
  step hits (i.e. where the pool puts a re-interned string) is UNMEASURED — the header prints the sweep
  time and mode (`quick` / `window` / `region` / `full`) so the first live run answers it.
- MEASURED 2026-09-20 (game in the lobby, no match): the exe-image region step = **506 MB in 0.7 s**; the
  whole-process fallback = **9,092 MB in 21.4 s** (hit the 20 s budget, found nothing) and the first
  build ran it every 15 s. Now: region step every 5 s while nothing is found, the whole-process sweep
  once per game process a minute in, never again (the pool is inside the exe range by measurement).
- The first live run also showed 60 UNREAD pills before any readback (every row is unconfirmed until
  GFCFG lands) → the pill is gated on the first readback.
- New publishers (`gunfight_menu.gsc`, appended block): `state_publish` (1 s, no `game_ended` endon so
  the `ended` phase reaches the panel) and `players_publish` (1 s, published on change only). Both keep
  the old `GFROSTER` / `GFCFG` lines intact, so `tools/gf-control` keeps working against the same payload.

## 3. The write channel — rules carried over

One command per bridge message, 80 ms apart, ≤ 47 bytes, `gf_cmd_go` last (bridge-command-limit,
app-bridge-multiline-fix). The seq/ack layer is new: `set gf_cmd_seq N` before the pulse; `cmd_poll`
records N after dispatch and swallows a pulse that repeats the acked N (clears action / arg / target /
say / map / gametype) — so a retry can never double-fire `addbot` or `endround`. The panel seeds its
counter above the game's ack at every new match (another panel may drive the same game).

Packed settings: the panel rebuilds a chunk from the **live** GFCFG values + the change (never from its
own defaults) and refuses a packed write until the first readback — the mechanism behind the 2026-09-19
"Apply now reloads the match" bug can no longer be triggered from here.

## 4. Payload default — the LIVE slot, never the newest side build

First live run (2026-09-20, klaze: *"its injecting the wrong menu build"*): the panel defaulted to the
newest `gunfight_menu*.gscc` in `payloads\` — bocw-c2's `.props.gscc` — not the live slot. klaze's
convention: `payloads\gunfight_menu.gscc` IS the build in play (peers swap builds into it under his
standing order); a side build is an explicit pick. The panel now defaults to the live slot, marks the
choice LIVE SLOT / SIDE BUILD, and on the dev box reads `C:ocw\payloads\` directly (the bundle's
`payloads\` copy is a snapshot for friends' machines only).

## 5. Untested — not ruled out (everything below is built, nothing has run in-game)

- GFSTATE / GFPLAYERS parse end-to-end; the sweep cost per tick with the game up; ack latency (expected
  2–3 s: 1 s publish + 1.5 s tick).
- `endround` via `globallogic::function_a3e3bd39( team, 1 )` — gunfight's own path, but gunfight also
  keeps a hashed "round ended" latch (`level.var_c7cce1ff`) that this call does not set; a second
  end-round arriving from the timer path is guarded by `level.gameended`. Watch for a double round-end.
- `restartround` = `map_restart( true )`: whether game.* (scores / round count) really survives.
- `slowmo` as a standing timescale; `visionsetnaked` names beyond `default` / `mpOutro`; `hide()` for
  invisible players; the BO3-leftover perks (lowgravity / doublejump / wallrun / jetpack).
- `app_on_connect`'s staged-side move at 1.5 s after connect (too early / too late?), and the ban kick
  at 0.5 s.
- The rotation: a stage 20 s into a match, then a natural match end → does the lobby show it (the
  STAGE READY timing was measured at ~25 s for a manual stage).
- Prop favourites → the in-game menu's Props page (bocw-c2's GSC, same day): `gf_prop_favs` /
  `gf_prop_favs2` CSV + `propfavs`.

## 6. The overlay — the panel over the game (2026-09-23)

klaze: *"Let's create an overlay for a real GUI mod menu. Used only for the purpose of controlling our
private match gunfight mod."*

**What was built:** the panel itself is the overlay. A system-wide hotkey (default **Insert**, SETUP →
OVERLAY) lays this window over the game — borderless, topmost, on the game's monitor (layouts: right side
/ left side / centre / full, each inset so the game shows round it) — and pressing it again, Esc, the
header's **⤶ Back to game**, or clicking the game puts the window back exactly where it was and hands the
game its focus. Every tab works as normal inside it. `ViewModels/OverlayVM.cs`, `Native/User32.cs`.

**Why not an in-game menu drawn by a DLL.** The usual "overlay mod menu" is a DLL in the game process
that hooks the renderer's Present and draws (ImGui) every frame. For this project that is the wrong trade,
and the reasons are a decision plus exposure, not a measurement of that route:
- TAC's documented detections are API hooks and overlays (CLAUDE.md, anti-cheat table); a Present hook
  is both at once.
- Keeping one undetected would be anti-cheat evasion work — out of scope by decision (ground rules).
- The one code hook this project ran inside the game (`lua_loadx`, 2026-09-18) left the game crashing even
  after it had cleanly unhooked itself ([[lui-dll-re]]). That was an inline patch in the exe; a swapchain
  hook is a different target, so this is suggestive, not a result for it.
- The GUI already exists here — every menu page, the roster, match control. The in-match GSC menu stays
  the in-game one; [[hud-channels]] maps what else script can draw.

**What it is, precisely** (for whoever reviews the TAC exposure):

| | |
|---|---|
| hotkey | `RegisterHotKey` on the panel's own window, `MOD_NOREPEAT`. The key is reserved system-wide while the panel runs: other apps stop getting it as a normal key press (whether a game reading raw input still sees the press is unmeasured — pick a key you do not play with). A key another app already holds is reported (SETUP status + toast), not silently dropped. F4 / F6 / F7 are cwpatch's and F12 is reserved by Windows, so none is offered. |
| focus | Windows lets "the process that received the last input event" take the foreground (SetForegroundWindow remarks); the hotkey is expected to count as that — it is not documented in those words. No `AttachThreadInput`, no synthetic input. **If Windows refuses anyway**, the overlay stands down 0.8 s later and says so: it never stays topmost over a game that still has the input. |
| the game's window | found by enumerating top-level windows for the game's pid (the largest visible unowned one). The calls made on it: `GetWindowRect`, `IsIconic`, `MonitorFromWindow`, `SetForegroundWindow`, `ShowWindow(SW_RESTORE)` — the taskbar's set. The overlay opens no process handle. |
| the panel window | opaque (not layered, not click-through), topmost **only while shown**; its place and state are saved with `GetWindowPlacement` and restored with `SetWindowPlacement`. Put away as soon as another app takes the focus. |
| display mode | needs **Fullscreen Borderless**. Exclusive Fullscreen gives up the display when focus leaves and the game minimises; the panel sees that (`IsIconic`, 0.8 s after showing) and says what to change. |
| input | while it is up the game gets no keyboard or mouse — the host's player stands still. Pause the match first mid-round (MATCH → PAUSE). |
| joiners | nothing: a window on the host's desktop. The overlay sends nothing to the game; the buttons inside it use the same bridge as always. |

⚠ **Measured: nothing yet.** Built and compile-checked 2026-09-23 on Linux (`dotnet build GfPanel
-p:EnableWindowsTargeting=true`, 0 errors); never run on Windows. Test sheet:

1. BOCW in Fullscreen Borderless, panel running → SETUP → OVERLAY reads *armed - press Insert in the game*.
2. In a match, press Insert → the panel covers the right side; the header shows OVERLAY + ⤶ Back; the
   mouse cursor is usable. *Nothing happens* = the hotkey does not reach the panel while the game has focus
   (see the first unknown). *"stood down" toast* = Windows refused the focus.
3. Insert again → the game has focus and input at once; the panel is back where it was.
4. Up again, then click the game → the overlay puts itself away.
5. Once in exclusive Fullscreen → the warning toast.

**Unknowns the test answers:**
- **Does the hotkey reach the panel while BOCW has focus?** A game that registers raw keyboard input with
  `RIDEV_NOHOTKEYS` switches application hotkeys off while it is in front (Microsoft's RAWINPUTDEVICE
  docs). Whether BOCW does is unknown. Alt+Tab to the panel works either way.
- Does BOCW release the mouse cursor when it loses focus? Expected (it has to for Alt+Tab), unmeasured.
- **TAC and a topmost window over the game: unknown.** The overlay avoids the shape external ESP overlays
  have (layered, click-through, permanently on top, exactly full-screen), but what TAC looks for is not
  public. Same rule as everything else: the throwaway box first.

**Untried — not ruled out:**
- An in-process overlay (DLL + renderer hook + ImGui) — set aside for the reasons above; nobody has
  measured it on this build.
- Translucency — one WPF property, but it makes the window layered, which is the shape external overlays
  have. Left off on purpose.
- A compact overlay view (sidebar + FAVORITES only) instead of the whole panel.
- A controller button to open it: XInput polling from the panel is easy; taking the foreground without a
  keyboard event is the hard part.
- A key path that does not depend on `RegisterHotKey` if step 2 fails: polling `GetAsyncKeyState` sees the
  key but carries no right to the foreground, so it would need a shown-but-unfocused overlay clicked once
  — which is the topmost-over-a-live-game shape this build refuses.
- An Xbox Game Bar widget (Win+G is a system hotkey, which `RIDEV_NOHOTKEYS` leaves working).
