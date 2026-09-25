# Account unlocks — the `unlock` verb and the app's UNLOCKS tab (2026-09-24, bocw-84)

klaze, 2026-09-24: *"proceed incorperating the full entire unlock system and all features into the app"*.
**Built, NOT run.** Nothing here has been measured in game.

⚠ These write a player's **Activision account** (saved stats), not the match. That is permanent, and it is the
"manipulation of game data" Activision bans for. The project's ground rule applies: joiners' accounts are
theirs — so **nothing is written to anyone but the host until that player accepts on their own screen**
(hold Use for 1 s within 20 s; no answer = skipped).

## Source — the game's own scripts and tables, not a community menu

The ecosystem survey's MuzzMan menu (`ecosystem-survey.md` §7) was surveyed, not ported; its crystals and
Dark Aether (zombie-kill) parts are Zombies-only anyway. Everything below is read from `bocw-source`:

| Part | Where the data comes from | How it is written |
|---|---|---|
| Challenges | `gamedata/stats/mp/statsmilestones1-6.csv` — col 2 target, col 3 group, col 4 stat | each stat **raised** to its row's target (read, add the difference; a rerun changes nothing) |
| · `#global` | | `stats::get_stat_global` / `stats::function_dad108fa` (increment, `playerstatslist`) |
| · `#common` (seasonal events) | | `stats::function_927be59d` / `stats::function_42277145` (increment, common buffer) |
| · `#weapon_<class>` | weapons of that class from `mp_gunlevels.csv` + `util::getweaponclass` | `stats::function_b2c11cc` / `stats::function_e24eec31` (= `addweaponstat`, what stock's kill tracking calls) |
| · `#group` | every weapon | as above (the engine folds weapon stats into item groups — read, not run) |
| · `#attachment` (10 reticle rows) | — | **skipped**: stock has no attachment-stat setter |
| Weapon levels | `gamedata/weapons/mp/mp_gunlevels.csv` — col 1 cumulative XP, col 2 weapon | `stats::set_stat( #"ranked_item_stats", weapon, #"xp", top )` — stock's own developer route (`zm_devgui.gsc:4343`); DDL `mp_progression.ddl` `ranked_item_stats` |
| Player level | the engine's rank table (no script copy) | `rankxp` = the least XP `getrankforxp()` maps to its top rank (binary search), `rank` = that rank; `prestige_reset.cfg` names both stats |
| Achievements | `ddl/pc_achievements.ddl` — 44 ids: mp 5, zm 9, cp 25, doa 5 | `giveachievement( id )`, 1 s apart |
| Save | — | `uploadstats( player )` after each part (stock: `globallogic.gsc:1906`, `persistence_shared.gsc:523`) |

`stats::` setters return without writing for bots and when `level.disablestattracking` is set
(`player_stats.gsc:55`); a run lifts that flag and restores it when it ends or is stopped (`unlock_guard`).

## The open question — does a custom match keep any of it?

Custom games give **no XP**: `globallogic.gsc:188` `level.rankedmatch = gamemodeisusingxp()`, `:190`
`level.custommatch = gamemodeismode( 1 ) || gamemodeismode( 7 )`. Whether the engine **keeps** a stat
written in a custom match is **unmeasured**. So the first thing to run is the **Write check** (`unlock
probe`): it writes the host's rank XP and XM4 XP back **unchanged** and reports `custom / ranked / online /
tracking-off` plus whether each write was accepted. "REFUSED" = nothing else here can work in this match
type; "OK" = the write was accepted in-session — persistence still needs a look at the barracks / Gunsmith
after the match.

## Verb (app → `panel_verb`, host only)

`unlock <what> [all]` — `what` = `probe | weapons | challenges | level | ach | achmp | achzm | achcp | achdoa |
everything | save | stop | local`. No target = the host; `gf_cmd_target` = one player; `all` = every other
human. `local` = `loot_fakeall 1` (this PC only, nothing saved — same as TOOLS → Unlock all). One run at a
time (`level.gf_unlock_busy`); `stop` notifies `gf_unlock_stop` — the next step does not run, what was
written stays (stock also uploads at match end). Progress: the host's `say=` line (ACTIVITY "game: …"),
the saved menu log (`gflog_add` page "Unlock").

## App

`UNLOCKS` tab (`ViewModels/UnlocksVM.cs`, `Views/UnlocksView.xaml`): WHO (me / one player / everyone else),
Write check, Max weapon levels / Complete all challenges / Max player level / Everything, achievements (all or
by mode), Save now / Stop / Local unlock, and the latest progress line. Every permanent action asks for
confirmation; the other-player ones say the player must accept on their screen.

## Test order (nothing run yet)

| # | Step | Look for |
|---|---|---|
| 1 | Write check (me) | `write OK` or `REFUSED` for both stats, and the mode flags |
| 2 | only if 1 = OK: Max weapon levels (me), then leave the match | Gunsmith shows max levels; `weapons N maxed` |
| 3 | Max player level (me) | the level in the lobby after the match |
| 4 | Complete all challenges (me) | camos / calling cards unlocked after the match; a stall = a bad stat name |
| 5 | One player, with them watching | the accept prompt; declining writes nothing |

## MEASURED 2026-09-24 (8bit, Gunfight on Game Show, the panel's saved log)

- Match 1 (19:00-19:03): Write check → `custom 1 ranked 0 online 1 …` (its OK / REFUSED part was overwritten by
  the "started" reply — fixed below); **Max weapon levels → 64 maxed, 0 refused**; **All challenges → 5,442
  stats raised, 10 skipped (the attachment rows) of 1,475 rows, ~15 s**; level / achievements / save pressed
  during the challenges run → refused ("one is already running"). Match ended normally.
- Match 2 (19:06-19:08): "everything" (sent from the lobby, ran at match start) → challenges **5,442 raised
  again**, 44 achievements given, **weapons 64 maxed, 0 already** — i.e. match 1's writes were NOT there at
  match 2's start: stat writes made in a custom match look **discarded at match end**. klaze asked "but
  chalendges worked?" — whether challenge REWARDS (camos / calling cards) are kept separately is his menus'
  call, not the log's.
- **Bug, fixed in source:** "max player level" searched for the top of `getrankforxp()` up to 1e9 and wrote
  rankxp **999,993,315** — the lookup never tops out. Now: the least XP reaching rank index 54 (level 55),
  never lowering a higher value.

## Changes after the first runs (klaze 2026-09-24 — built; live since 20:01 in 4027F3EB, now ABFFA931; not run yet)

- **Client menu → Account** (`client_account_enter` / `act_account`): Max weapon levels, All challenges, Max
  level (55), All achievements, Stop — on the pressing player's OWN account, no accept prompt (they pressed it).
  Write check, per-mode achievements, Save now and Everything were removed from it on klaze's asks.
  **Superseded 2026-09-24 (bocw-57, build AF1B8963):** *"for the clients menu, remove the account menu and move
  achievements to the player menu and call it "Unlock achievments""*. The Account page and `client_account_enter`
  are gone; the one client row left is **Client menu → Player → Unlock Achievements** (`act_account( "ach" )`,
  all 44, the same queue). Weapons / challenges / level 55 / Stop are host-only now (the app's UNLOCKS page).
- **Presses queue** (`unlock_start` / `unlock_next`): a press during a run waits its turn (same part from the
  same asker once, at most 12); the host's Stop drops the running part and the whole queue, a client's Stop
  only their own.
- The write check's result is no longer overwritten (`unlock_run` waits one frame before starting).

## Untried — not ruled out

- Attachment challenges (reticles): the `attachment_stats` path exists in the DDL; no stock setter to copy.
- Weapon prestige (`ranked_item_stats.plevel`) and seasonal prestige: left alone.
- Zombies-only unlocks (crystals, Dark Aether) — would need a Zombies match.
