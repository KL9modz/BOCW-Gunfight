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
| DASHBOARD data-driven blocks + pills (LIVE / NEXT / RESTART / STICKY…) | DASHBOARD + ADVANCED sections from `Game/Schema.cs` (a section's `Tab` picks where it renders: dashboard / advanced / tools / spawns); pills LIVE / NEXT / RESTART + UNREAD | every `cfg_*` reader of the GSC, defaults = the GSC's own |
| BOTS: add / kick, per-team ±, fill, difficulty chips, CUSTOM, named profiles | the same + the GSC's four custom presets + named profiles (the 15 knobs) | `gf_bot` / `gf_bot2` packs, `apply bots` |
| PLAYER STATE (god / ammo / perks all) | PLAYER STATE — EVERYONE + PERKS grid | new `godall` / `ammoall` / `thirdall` / `freezeall` / `invisall` / `perkall` |
| FUN & VISION (vision sets, 3rd person, explosive bullets, melee range, drunk, invisible, quake) | vision (`visionsetnaked`, level-wide), drunk, quake, sound, invisible, timescale; explosive bullets ≈ the Projectiles page | new `vision` / `drunk` / `quake` / `sound` / `slowmo`; melee range has no T9 lever |
| MOD TOOLS (give weapon, bullet mode, ride grenade, positions, Gersh, sound, team names, splash) | give me / give EVERYONE, projectiles, teleport gun / grenade, save point, sound; team names have no T9 builtin; splash = the centre print | existing verbs + `giveall` |
| ADMIN message composer (channel / audience / duration / colours / presets) | MESSAGES: centre / feed / banner · all / allies / axis / a player · once / N s / held · ^colours · presets | `gf_cmd_say*` + new `gf_cmd_say_aud` |
| MAPS: gametype picker, rotation editor (live + save to cfg), map grid with LIVE / NEXT | MAPS: Stage for lobby / Switch NOW, the grid (LIVE / NEXT badges), a **panel-driven rotation** | private matches have no engine rotation: the panel stages the next entry 20 s into every new match |
| — (new, 2026-09-22) | SPAWNS: the spawn atlas — every spawn point of the map for every mode (starts, respawn pools, S&D groups, BO2-named, engine lists) plotted, dense areas, ranked start layouts, one-click per-map pick; map pictures (wiki art on the minimap frame, north up); LIVE SPAWNS (every real spawn numbered in order, used spots ringed); each mode's OBJECTIVES (★ bomb sites / flags / zones); scans of one map under several modes MERGED; the SCAN TOUR (every map under one mode, unattended); the SPAWN SETTINGS block (`gf_spawn_*`, `gf_strike` — moved here from ADVANCED 2026-09-22, schema tab `"spawns"`) | `spawnscan` (GFSPAWN chunks incl. `O` records, `MemoryScanner.CollectAll`) / `spawnpick` + `gf_sp_map` / `gf_sp_a` / `gf_sp_b`; GFSPAWNED (spawn events) on GFSTATE `spv=`; GFSTATE `spn=`; the tour = `gf_cmd_map` switches (one-shot). [spawn-atlas](spawn-atlas.md) |
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
- 🛑 **Every channel line stays under 1024 characters, header included.** A GSC string concatenation
  whose result passes 1024 is fatal (`0x91f84370`, `crash-decode.md` §2c) — the first spawn-atlas build
  crashed on it. Budget the worst case of any new or growing line: `GFPLAYERS` stops listing at 940
  chars (~80 per human), `GFCFG` cuts the race track (`trk=`) to 440, `GFSPAWN` chunks at 880 and
  flushes list records by length. A line that can outgrow that goes in numbered chunks the panel
  reassembles (`MemoryScanner.CollectAll` + `SpawnAtlas.FromHits` is the pattern), never one long string.

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

## 6. The saved log + the menu log (2026-09-23, bocw-12)

Why: a Miami FFA match on 2026-09-22 ~23:11 "crashed the lobby (not a game crash)" and nothing on the
box could say why — the game writes no console log, the lobby's `COM ERROR` text did not survive in
memory, the mod's lines died with the level, and the panel's Activity list lived only in RAM. klaze:
*"build out the log system with saves. can we log what users do in their menus too?"*

- **Saved log** (`Services/ActivityFile.cs`): every Activity entry → `%LOCALAPPDATA%\GfPanel\logs\
  activity-YYYY-MM-DD.log` (a dry run writes `activity-dry-*`), one line each: time, level (`info ok WARN
  ERR sent MENU`), text; file-only detail lines start with `|`. Each write opens, appends and closes, so
  the file is never held (readable / copyable while the panel runs; a killed panel loses nothing); a
  header per panel start; files older than 90 days pruned. ACTIVITY header → **📂 saved logs**.
  `GFPANEL_DATADIR` overrides the data folder (a test instance must not share klaze's prefs / logs).
- **How each match went** (`Services/MatchTracker.cs`, UI thread): `▶ match` (map, mode, match id;
  "already running" when the panel met it mid-match), `▶ round N`, `round N over`, `■ match over`. When
  the state feed goes quiet — 12 s mid-round, 75 s after a round end, 20 s after the match-over screen —
  one **last gasp** (`CollectAll` of GFSTATE + GFLOG across the exe range) and a verdict:
  `■ match over → lobby` (mo=1); `the level ended after the panel's '<verb>'` (a one-shot level verb sent
  ≤ 20 s before); or `⚠ MATCH DROPPED mid-round` / `after round N ended` with, in the file, the last raw
  state line, the roster, the last 8 menu actions — and a warning when the last action printed no
  confirmation. The same match id coming back = `↺ ... it stalled, it did not end`. The game process
  closing mid-match = a warning to look in crash_reports. One summary line per match (duration, rounds,
  score, peak humans, peak entities, menu actions, how it ended).
- **GSC** (live slot 67FECA4B, 637,463 B / 3,955 strings; previous = `gunfight_menu.safe-F7DAED9D.bak.gscc`):
  GFSTATE gains `mid=` (`game.gf_mid` = getrealtime() at the match's first mod_apply; survives the
  per-round map_restart), `mo=` (`level.gameended` && `util::isoneround() || util::waslastround()` —
  stock's own last-round test, globallogic.gsc:2227; stock sets gameended at EVERY round end, :2329),
  `ents=` (`getentarray().size` every 5 s — stock MP calls it bare, serversettings.gsc:139) and `lg=`
  (the newest menu-log seq). New line `GFLOG|<tick>|<mid>|seq,ms,entnum,who,page,item,result;...|END`:
  `menu_run_item` (host + granted clients) writes the record BEFORE the action runs and fills the result
  (the action's first `menu_say`) after it returns; page navigation is skipped; forge place / delete log
  too. The line keeps the newest records that fit 880 chars (7 at worst-case field lengths, fields capped
  16/16/28/44); `game.gf_log` keeps 24 across rounds. The panel collects GFLOG when `lg=` moves
  (`CollectAll`, every copy unioned by seq — each copy holds an overlapping window), holds a record up to
  4 s for its result, and stamps it with the game-side time (ms → wall clock through GFSTATE's tick).
- **Offline-verified only** (scratch harness: the GSC builder ported line for line + the tracker on a
  fake clock): worst-case GFLOG line 871 chars, GFSTATE with the new fields ~420; union / dedupe; normal
  end, mid-round drop, round transition, stall, relaunch, game closed, older payload (no id); the file
  format and that it is never held open. The published panel starts clean (dry-run screenshot).
  **Nothing of it has run in game** — first run: play a match, use a menu, end it; the log should show
  `▶ match`, `menu · <name> › <page> › <item> → <result>` lines and `■ match over → lobby`.

## 7. Client menus, radar, parachutes, the entity list, the host-menu trim (2026-09-23, bocw-84)

klaze's list of 2026-09-23 (*"every thing i mention needs an app feature. id like to simplify the hosts
mod menu and bring advanced stuff to the app only"*). His answers to the questions asked back: give-all
**and** take-all buttons; keep in the in-game host menu only **Self tools, Players page, Match basics,
Sandbox**; late joiners **always auto-placed** (`late-join.md` §2a); radar default scope **host only,
the app picks others**. GSC = live slot `2B998AD8` (623,533 B / 3,612 strings, check-gsc PASS, 0 headers;
previous = `gunfight_menu.safe-67FECA4B.bak.gscc`). **Nothing below has run in game.**

- **Who has a client menu** — GFPLAYERS flags gain `m` (a granted client menu: `gf_client_menu` or the
  match's grant list `game.gf_client_grants[xuid]`, so a rejoin keeps it) and `F` (forge mode). The
  roster tints the row purple with a **★ MENU** pill and shows **⚒ FORGE** in cyan; the header counts
  "★ N with a menu" and carries **★ Give all menus** / **✖ Take all** (`menuall on|off` — every human
  except the host). The right-click menu leads with the player's name, then **★ Give client mod menu**
  (purple) or **✖ Take back client mod menu**, Forge mode ▸, Message…, then Player ▸ / Loadout ▸ /
  Teleport ▸ / Team ▸, then Show their menu log, Copy ▸, Moderation ▸. ⚠ The theme's global TextBlock
  style had been overriding every MenuItem's own colour (Kill was never red); the MenuItem template now
  re-points the header's Foreground at the item.
- **Teleport a player to a player** — right-click → Teleport → *Them to player* ▸ lists everyone else:
  `tpto <name>` with the target = who moves (in front of the named player, facing them). The granted
  client menu has the same thing for the client themself: Teleport → *Me to a player* ▸.
- **Menu log in the app** — ACTIVITY chips *All* / *Menu log* / *Hide sent*, a text filter, and
  right-click → *Show their menu log* (filters to `menu · <name>` lines; *All* clears it). The data is
  bocw-12's GFLOG (§6).
- **ENTITIES tab** — the new `GFENTS` channel (`ents_publish`, rebuilt every second, republished only on
  a change; GFSTATE `ev=<stamp>` says when). Line: `GFENTS|<stamp>|<i>|<n>|<rec>;<rec>;…|END`, `rec =
  kind,entnum,label,owner,dist,x,y,z,flags` (kind `p` prop / `b` barrel / `v` vehicle; label ≤ 24 and
  owner ≤ 16 chars; dist from the host and the position in 50-u steps so a parked prop does not
  republish; flags `o` occupied, `m` vehicle-mode ride). Chunks ≤ 880 chars by length, 16 max (~200
  entities) — the 1024 rule. The panel collects it (`CollectAll`, newest complete stamp) only while
  the tab is open, ≤ every 2.5 s. Delete one = `entdel <entnum>`: the GSC re-checks the entity is one we
  spawned (a vehicle with `gf_spawned` / `gf_veh_mode`, a prop with targetname `gf_prop`) and never
  deletes an occupied vehicle; a prop also leaves the saved forge layout. *Delete all props /
  vehicles / EVERYTHING* = `entclear props|vehicles|all` (props = `forge_clear`, layout included;
  vehicles = every EMPTY spawned one, `veh_sweep_tagged`). Props / barrels now record `gf_owner`.
- **RADAR & MARKERS** (TOOLS, one plain dvar `gf_radar` = host bits + 256 × everyone bits + 65536 ×
  marker icon; `radar_think` re-asserts every 0.5 s, change-guarded, so a write lands with no reload):
  1 constant enemies on the minimap (`setclientuivisibilityflag( "g_compassShowEnemies", 2 )`, what
  the lobby's "Radar: Constant" sets — player_connect.gsc:465); 2 spy plane (`setteamspyplane` + the
  `radar_<team>` match flag, uav.gsc:750-751 — team-wide, team modes only); 4 H.A.R.P.
  (`function_e72ac8f4( team, 1 )`, recon_plane.gsc:697); 8 enemy markers (one objective per living
  enemy, invisible to all, visible to each viewer — `#"enemy_waypoint"` by default, bits 16-18 pick
  escort / VIP / gunship / teammate icons); 16 enemy glow (`thermal_glow_enemies_only`, the air-streak
  pilot's field, killstreaks_shared.gsc:4262 — ⚠ a test toggle, unmeasured on foot). The in-game Radar
  page toggles the host bits. 🪦 **"Red boxes" are not possible from script**: box / line / sphere /
  print3d are dev-only builtins (funcs_cw.csv type 1, the 0x6394f836 fatal on retail) — the markers
  are the stand-in. klaze's lead (*"player controlled air streaks show markers and players"*): the real
  streaks (Gunship / Chopper Gunner / Cruise Missile, given from the app) show their pilot's markers; a
  menu-spawned AC-130 / Chopper Gunner (VEHICLES → Other) is untested for that.
  **MEASURED 2026-09-23 ~23:40 (klaze, dm on Zoo, build 2B998AD8, the panel's saved activity log):** 1 and 8
  WORK; 2 and 4 did nothing — that build only had the team calls, and free-for-all has no team spy plane:
  stock gives each FFA player their own (uav.gsc:757-769 `radar_client` + the code field `hasspyplane`;
  recon_plane.gsc:714-725 `radar_client` + `var_83266838`) → `radar_ffa_apply` (build 862278C7 on,
  untested; team modes still unmeasured); 16 never draws on foot — both glow fields are client-gated on
  `function_266be0d4` (killstreaks_shared.csc:196 / :247, a streak's pilot view) → off the in-game page,
  the app keeps it as "pilot view only". The app's older *Spy plane* row is Gunfight's own
  `gunfightspyplane` rule (gunfight.gsc:112, Gunfight matches only) — relabeled *Gunfight spy plane*.
- **PARACHUTES** (TOOLS + Movement → Parachutes in-game; `gf_parachute` 0 off / 1 everyone / 2 host
  only; app verb `parachute n`). A Fireteam mode's hidden setting `hash_2966662989c3484c` makes
  globallogic_spawn.gsc:674-678 call `function_8a945c0e( 1 )` + `function_8b8a321a( 1 )` at spawn; the
  mod calls that pair itself per player per spawn — no gametype write, so no reload. ⚠ The height a
  free-fall starts at is unmeasured.
- **Feed readouts** — Match info / Spawn report / Overtime-zone census (`matchinfo` / `spawnreport` /
  `zonecensus`) were in-game rows until the trim; they print to the host feed as before.
- **The host-menu trim** — pages that went app-only (their functions stay; the app drives them): Pool
  loadout + Pool camo, Spy plane, Spawns, Display + Debug, Overtime zone, Match settings, Race (+
  config), Projectiles, Destructibles / Exploders, Gametype, Match periods, per-team bot difficulty +
  CUSTOM bot tuning, Say / Announce. Teams keeps the sizes + fill / remove bots; Round gains *End match
  (host end)*; Movement loses the builtin-jump and barrier-debug rows and gains *Parachutes*. New root
  order: Player, Weapons, Teleport, Camo, Operator, Outfit, Players, Teams, Bots, Round, Host, Map,
  Props, Forge mode, Vehicles, Streaks, Movement, Radar. Operator → the *Invisible* row is gone (menu +
  app list). Two new dvars only (`gf_radar`, `gf_parachute`), both appended to `misc=` (append-only).
- **Weapons** — 17 menu / app rows named the wrong gun; the table is now verified against the CoD
  wiki's internal names (`docs/reference/bocw-weapons.md`, with the page each id was read from).
  Bowie (no zone table carries it) and Ray Gun (no MP / core zone) are out of both lists.
  **MEASURED 2026-09-23 ~23:44 (klaze's menu log):** three melee gives took, then nearly every give failed
  whatever the weapon — klaze: *"the weapons arent broke, they just stop giving once you are holding too
  many ... i think the limit is 13"*. A give past the inventory limit is dropped with no error (the
  zone-residency theory was wrong). `weapon_give_room` (build 862278C7 on): a weapon already held is just
  taken out; a give that did not take frees ONE slot — the oldest weapon the menu gave, else the gun in
  hand, else another primary (only `getweaponslistprimaries` entries, never grenades / equipment / streak
  weapons) — and retries, putting it back if the retry fails too; the line says *"(swapped out X)"* or
  *"not given — X (N held)"*. The app's Give EVERYONE (`give_all`) uses it too. Untested.
- **Hints** — klaze's two hint-bar bugs. (a) *"the menu hint bar disappeared … until i got back into the
  prop forge"*: the text change-guard lived in `gfmenu.last_hint`, which outlives the trigger entity (a
  round rebuild / the match-end cleanup deletes the trigger), so a fresh trigger was skipped as "already
  showing" and stayed blank — the guard now lives on the trigger (`menu_hint_set`, `trig.gf_txt`).
  (b) *"the forge mode ui when holding a prop stayed up even after dropping it"*: a player with FORGE
  MODE but no menu of their own runs no `menu_think`, so nothing repainted over the forge legend —
  `forge_restore` now removes that trigger, and marks a menu owner's stale so the idle line is re-sent.
  The idle "open menu" line sits at low priority (`sethintlowpriority`, stock's player-linked trigger
  shape, remote_weapons.gsc:177) so a world prompt wins. The legend reads `Select | Next | Last | Back`
  (klaze 2026-09-24: *"the menu control for select should say Select not Open"*), with spacers, on every
  device; the app's plain-text fallback is `R Select|M1 Next|M2 Last|V Back` (31 chars = the bridge slot). Asset prompts carry the use-button token in front
  (`forge_key( "use" )`, re-sent when the device changes), and a menu-spawned kind-1 ride (RC-XD,
  streak / intro rides) gets a *"Hold to control / fly / enter <name>"* prompt within 220 u when you
  face it: the menu owner's hint line shows it, anyone else gets a private low-priority trigger that
  follows the ride (display only — the engine's own hold-Use does the entering; `gf_ahint 0` = off).
- **Offline-verified only**: check-gsc PASS; payload tell-tales present (bocw-12's `LOG|` `|mid=` …
  and this batch's); the panel in `--dry --fake` (roster pills, right-click order + colours, *Them to
  player* list, ENTITIES rows, RADAR block) screenshot-checked. `--fake-menu` opens a player's
  right-click menu for such a screenshot.

## 8. The line-break test and the cloud branch's fun pack (2026-09-24, bocw-84)

- **Line-break test** (klaze: *"the next build lets try \n line breaks if we havnt yet"*): a raw `\n` in the
  HINT widget closed the match on 2026-09-14 (`hint-panel.md`); the centre print and the feed had never
  carried one. The cloud branch's `hud_probe` stage 23, as `nltest centre|feed` (GSC `nltest_run`: ONE
  `iprintlnbold` with two `\n` / ONE `iprintln` with one) — TOOLS → *Line-break test* and Host →
  *Line breaks: centre / feed test*. The in-game row closes the menu and prints 1 s later (the carousel
  repaint IS a centre print); press the app buttons with the in-game menu closed. Throwaway match.
- **FUN PACK** (the cloud branch `claude/dazzling-wright-2xq7z3`'s fun pack 1 + 2, ported by hand — ESP left
  out, the RADAR block owns those layers; `docs/notes/fun-pack.md` §*Ported*): TOOLS → **FUN PACK** (fly bind,
  slide speed / super slide / long slide / chain penalty, fast restart, disco camo, disguise + picks + size /
  height, forge tools on the host's aim — spin / speed / reverse / move / link / solid / delete / tilt / spray /
  auto-link / prop gun, shots per trigger, grenade swap + type, Model cannon + blast / ride / keep / model)
  and a player's right-click → **🎉 Fun pack** (fly bind, disco, disguise, prop gun, grenade swap, cannon).
  ONE GSC verb `fun <what> [args]` (`fun_verb`): explicit on / off (a retry never flips a switch), per-player
  ones through `gf_cmd_target`, picks as indices (`fun_nade_pick` / `fun_cannon_pick` / `fun_disg_pick`
  order = `FunVM.NadeTypes` / `CannonModels` / `DisguisePicks`). The 8 new projectile types are
  `Catalog.Projectiles` rows (the existing `projweapon` verb), method 7 = magicmissile in the method picker,
  vehicles 67-75 appended to `Catalog.Vehicles` (mirrors `veh_master`). Kept cannon props show in ENTITIES.
- **Held for klaze's decision: the branch's overlay mode** (a487e8c — the panel's own window laid topmost over
  the game on a global Insert hotkey). It only restyles and positions the panel window (no DLL, no hook, no
  write to the game window), but it IS a topmost window over the game, the one exposure type the project's
  anti-cheat notes name ("overlays"), never run on Windows. Not merged; its gf-panel.md / README /
  RESEARCH-INDEX text stays on the branch.
- Live slot history this night: 2B998AD8 → 3727289F (Select) → 862278C7 (FFA radar, weapon room) →
  EA61DE67 / B0A1532C (line-break test, then the close-the-menu fix) → **DE1BD8E3** (679,360 B / 3,907 strings,
  the fun pack). Backups `gunfight_menu.safe-<sha8>.bak.gscc` for each. **Nothing of §8 has run in game.**

## 9. Menu backdrop, localized line-break tests, vehicle list trims (2026-09-24 03:13, bocw-84)

- **MENU BACKDROP** (klaze: *"try moving the stage 9 boxes to fill behind the menu center line and hint
  row"*): TOOLS → **MENU BACKDROP** = two boxes (`ViewModels/HudBoxVM.cs`), *Behind the centre line*
  (`gf_hb0`) and *Behind the hint row* (`gf_hb1`), each X / Y / W / H / Opacity sliders + colour chips + Apply /
  Off / Live. The dvar is `"x,y,w,h,alpha,r,g,b"` — ONE short `set` (under the 47-byte slot), sent 350 ms after
  the last slider move when Live is on; the GSC (`hudbox_think`, one thread per menu owner) re-reads it every
  0.1 s while that player's menu is open. Units from the widget's Lua: x / y 15 px, **w 8 px**, h 4 px (the
  Pixels readout shows them). Defaults 30,18 / 30,46, 128×12, opacity 8, black = guesses to tune in game.
  Widget facts and the queue / cache trap: [hud-channels](hud-channels.md) §1.
- **Text tests** — the Host page's four rows moved onto a **Host → *Text tests*** sub-page (host-only: a
  granted client starts at `start_client` and cannot back out into the host tree) with six new LOCALIZED
  line-break tests; app TOOLS → PLAYER STATE → *Line breaks from stock text* 1-6 (`nltest loca..locf`).
  Why and what each expects: [hud-channels](hud-channels.md) §10.
- **Vehicles** (klaze: *"rcxd and rcxd alt look the same. but rcxd pha's name look different. so maybe use
  that one as the alt?"*, then *"remove the 2 turrets from vehicles menu"*): master row 37 *RC-XD alt* is now
  PHA's `hash_7dd2944ddf7cc7e9` (the fun pack's *RC-XD streak - PHA's name* row is gone), and
  `veh_missile_turret` / `veh_ultimate_turret` are out — `veh_master` and `Catalog.Vehicles` are 73 rows,
  cross-checked row by row (0 mismatches). `vehspawn` is by index: ship the payload and the panel together.
- Live slot AE827AAE (686,490 B / 3,958 strings, 0 strings with a byte < 0x20) also carries bocw-e0's 6v6
  default + slide chain penalty ON by default. dist republished 03:14. **Nothing of §9 has run in game.**

## 10. Offline checks — `GfPanel.Tests` (2026-09-24, cloud branch)

klaze: *"lets shift gears and work on the panel app"* → the offline test harness first, so the redesign that
follows has something to catch what it breaks. `tools/gf-panel/GfPanel.Tests/` is a plain net9.0 console app
(no NuGet, `RollForward=Major`, runs on Windows or Linux) that compiles the panel's UI-free code in directly
(`Game\*.cs`, `MemoryScanner` / `Win32` / `GameProcess`, `MatchTracker` + `LogEntry`) — the panel itself is
net9.0-windows WPF and cannot be referenced. `dotnet run --project tools\gf-panel\GfPanel.Tests`; exit code 1
on any failure; a name filter as the argument. **57 checks, all green**, ~0.5 s.

| Group | What it holds the panel to |
|---|---|
| parsers | GFSTATE (a `state_build`-shaped line; the fallback line; older-payload defaults), GFPLAYERS / GFROSTER, GFCFG, GFENTS (newest *complete* stamp wins), GFLOG (union of every copy, a filled-in result wins), GFSPAWNED, GFLOBBY; `MemoryScanner.Parse` refusing the 2026-09-20 stale-slot junk |
| the 47-byte slot | every plain setting write at every value it can hold, every packed chunk + bot line at its widest, say / action / switch lines whatever is typed, every verb the panel sends; `Clean()` drops line breaks (the match-closing bug) |
| the GSC contract | every verb sent is a `case` in `cmd_action` / `panel_verb`, every `fun` switch a `case` in `fun_verb`; `Packing.Packed` = `cfg_spec()` in order; each `config_publish` extra (misc / race / dbg / veh / oob / bar) in the panel's order; bot knobs in the writer's order with its fallback defaults; `Catalog.Vehicles` = `veh_master()` row for row; the fun picks = `fun_*_pick`; every GFSTATE key feeds a field and every field has a key; every setting is read by some GSC; every default is the one the GSC runs with |
| schema | unique dvars (a duplicate throws in the type initializer — the app would not start); each default is a value its control can show |
| match tracking | normal end, dropped mid-round, round end with no next round, the panel's own restart, a stall that comes back, a last gasp that finds the feed alive, the game closing, a new match id, menu actions in seq order, the unanswered last action named |

The GSC side is read **as text** (comment-stripped; functions found by name). A function the checks cannot
find fails loudly ("renamed or removed? update the check") rather than passing — so a **payload** change that
renames a verb or reorders a list fails here as well. Run it after GSC edits too.

**The first run found five real bugs**, all fixed in the same change:
1. **The roster froze in the biggest lobbies.** `players_build` stops adding records once the line would pass
   940 chars (the 1024-char fatal) and skips a player with no name yet, but its count is `getplayers().size` —
   and `Roster.ParsePlayers` rejected any line whose record count differed. 16 human records do not fit, so a
   full human lobby stopped updating the PLAYERS list (with `PlayersRich` set, GFROSTER was no fallback either).
   Now the short list is taken, `GameLink.PlayersUnlisted` counts the rest, they keep their last known row
   (`Roster.KeepUnlisted` — else they would log as *left* then *joined* every time the line filled), and a big
   lobby logs one line saying so.
2. **Six built-in message presets were cut mid-sentence in game** — up to 53 chars against the 30 a say line
   carries. Shortened to fit (e.g. *Welcome to custom Gunfight!*). Presets already saved in a user's prefs are
   untouched; the composer's count goes negative for those.
3. **Pin the player while placing read back as ON while the forge ran it OFF.** `config_publish` read
   `gf_forge_pin` with default 1, the forge loop with 0 (`dvars_register`, the only place that sets it, is never
   called — the dvar-pool crash). GSC fix: the publish uses 0. ⚠ Needs a payload rebuild (+ `check-gsc.ps1`).
4. **Grab reach defaulted to 160 in the panel, 200 in the game** (the GSC moved on 2026-09-22). Schema = 200.
5. (not a bug, a gap) the fun pick lists moved from `FunVM` into `Catalog` so the checks can compile them.

**The redesign guard — `ui-surface.txt`** (klaze: *"without losing any functionality (only gaining it)"*):
`GfPanel.Tests/ui-surface.txt` lists every thing a user can do from a view, as 461 keys read from the XAML —
`cmd:<Command> [<parameter>]` for each button / menu item (81 `fun` switches are 81 keys), `set:<Property>` for
each two-way input, `click:<handler>`. Keys use the last segment of a binding path, so moving a control to another
view keeps its key; renaming changes it. `Nothing_the_panel_offered_has_become_unreachable` fails on any key no
view offers any more (verified: deleting the *Swap places* menu item fails it with `cmd:TpSwap`). After an
intended change: `dotnet run --project tools\gf-panel\GfPanel.Tests -- --write-ui-surface`, and the file's
diff in the commit is the record of what moved. `Every_binding_names_a_member_some_view_model_has` catches the
other silent WPF failure: a `{Binding X}` to a member that does not exist.
The generator also lists view-model commands nothing binds or calls — 5 today, features the UI does not offer:
`ForgeVM.SetBuild`, `MainViewModel.PauseResume`, `ToolsVM.PropPlace` / `PropUndo` / `PropClear`.

Rules this sets for the redesign: `Game\` stays free of WPF (the harness compiles it whole); anything that
sends a verb names it as a literal (the verb check reads call sites, and lists any it cannot read).
