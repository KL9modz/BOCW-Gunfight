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
