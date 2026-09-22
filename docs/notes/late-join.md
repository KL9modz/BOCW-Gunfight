# Late joiners — placed, not benched (`gf_latejoin`, `gf_teamchange`)

> **Status: built 2026-09-21, compiles + check-gsc PASS + check-args 0, NOT run in-game.**
> klaze: *"theres a bug where players who join late get put as a spectator. could we auto assign
> them to the team with LESS humans? if even go to loosing team. if tied they pick (choose your
> team)?"* His calls on the three questions: the tie pick is the pause menu's **CHANGE TEAM, for
> everyone, any time**; **drop a bot** from the joined side when it becomes the bigger one; a tied
> joiner who never picks **stays benched with a reminder**. §4 is the test sheet — the first late
> join measures the one thing the dump could not answer (what the lobby hands a late joiner).

## 1. Why stock benches a late joiner (dump trace, not measured)

`mp_common/player/player_connect.gsc:266-283` — a client whose `pers["team"]` is unset gets
`pers["team"] = spectator`, `sessionstate = "dead"`, then

```gsc
[[ level.autoassign ]]( 0, getassignedteamname( self ), squad );   // :283
```

`level.autoassign` = `globallogic_ui::menuautoassign` (`globallogic_ui.gsc:39`) →
`teams::function_d22a4fbb( comingfrommenu, lobbyteam, squad )` (`mp_common/teams/team_assignment.gsc:396`):

| branch (`:412-430`) | when | result |
|---|---|---|
| `teamname !== none && !comingfrommenu` | the lobby handed a real side | **that side, verbatim, no fullness check** — the join klaze already sees work "when a spot is open" |
| `function_a3e209ba( teamname, 0 )` (`:602`) | no lobby side, unranked, past the countdown, non-host, non-bot, non-splitscreen, `level.forceautoassign` 0 | **`spectator`** |
| neither | e.g. during the countdown | stock counting (`function_bec6e9a`) |

The spectator answer is terminal: `menuautoassign:194` — `if ( assignment === spectator &&
!level.forceautoassign )` → `teams::function_dc7eaabd( spectator )` + `player::function_6f6c29e`
(`joined_spectator`) and **return**. Nothing revisits it; the joiner sits on the bench until he
finds a team menu — and the pause menu's CHANGE TEAM only exists when the `allowingameteamchange`
match setting is on (§3). `level.forceautoassign` is set to 0 in `globallogic::init` (`:272`) and
never set anywhere else in the dump.

Stock's counting path would not do what klaze asked either: `count_players` sees bots, and the
"lowest score" pick `function_4818e9af` (`:474`) never updates `score` inside its loop, so it
returns whichever team it iterated **last** — a stock bug, not a tiebreak.

## 2. The fix — hook the pointer, hand stock the side as if the lobby had

`LATE JOIN` block in `gunfight_menu.gsc` (between `humans_on()` and `bot_other_team()`).

- `mod_latejoin()` runs from `mod_apply` every round (level vars reset per `map_restart`, and
  `globallogic::init` re-points `level.autoassign` at stock each level): saves the stock pointer in
  `level.gf_autoassign_stock`, installs `gf_autoassign` in its place. Guarded so a second call in the
  same level (the menu rows) cannot wrap the wrapper.
- `gf_autoassign( comingfrommenu, teamname, squad )` — the stock signature. It decides only a
  **connect-time** call (`comingfrommenu` 0) for a non-bot, non-host, non-caster (`iscodcaster()`)
  human in a two-side team mode whose lobby side is **not** a playable team (the same
  `isdefined( level.teams[ teamname ] )` test stock uses). Everything else passes straight through:
  `act_move`, a lobby-assigned joiner, the pause menu's Auto Assign (`comingfrommenu` 1), bots, FFA.
- The pick, in klaze's order:
  1. fewer **humans** (`humans_on`: bots and spectators do not count);
  2. equal → the **losing** side (`info_score`, `game.stat["teamscores"]` — the round wins / team
     score the mod's own status line shows);
  3. level too → **they pick**: stock is handed the lobby side `spectator` (deterministic — the
     `:412` verbatim branch — countdown or not), the joiner gets a bold reminder every 5 s
     (*TEAMS ARE TIED - pause menu > CHANGE TEAM to pick your side*, `latejoin_pick_reminder`,
     restarted across the round boundary by `latejoin_on_connect` via `pers["gf_latejoin_pick"]`).
     During the **launch countdown** (round 1, `level.inprematchperiod`) there is nothing to pick
     between yet, so a full tie auto-places instead: fewer players overall, then the side opposite
     the host (`bot_auto_team`'s rule). Same fallback when `gf_teamchange` is 0 (no picker).
- The decided side goes to stock as `menuautoassign( 0, side, squad )` = the `:412` verbatim branch,
  so class choice, `joined_team` callbacks, the bot-difficulty hook and the roster run stock.
- `latejoin_bot_drop( side )` (level thread, one frame later): if the joined side is now **bigger**
  than the other and has a bot, `bot::remove_bot` on its last bot — the even-up drop, so 4v4 stays
  4v4 with no host action. No bot on that side → nothing happens (humans 5v4 is the lobby's business).
- One host feed line per decision (also mirrored into `level.gf_lastsay` for the app's `say=`):
  `JOIN <name> lobby=<side> humans A/X score A-X -> <pick> (<reason>)`; a pass-through human join logs
  `JOIN <name> lobby=<side> -> stock`. **The `lobby=` value is the measurement** — whether the session
  hands a late joiner `none`, `spectator` or a side is engine-side and unreadable in the dump.

## 3. The picker — `gf_teamchange` and the hidden "Team Change In-Game" setting

The pause menu's CHANGE TEAM button is shown by the client only when
`getgametypesetting( "allowInGameTeamChange" ) == 1` (`lui-source/lua/core_ui_1529_026651f8.lua:690`,
predicate `hash_7ffb9ecfafaeabf4`; the pause-menu builder `core_ui_1477:353`; the ChangeTeam list
`core_ui_1485:365-401` sends `sendmenuresponse( "changeTeam", <side> )`). The server acts on it only
when `level.allow_teamchange` is 1 (`menus.gsc:101` opens `ChangeTeam`, `:179` applies
`autoassign / spectator / <team>` via `level.autoassign / level.spectator / level.teammenu`), which
`serversettings.gsc:42-48` derives from the same setting in a private session. The setting exists
(`ddl/gametype_settings.ddl` `bool allowingameteamchange`,
`scriptbundle/gamesettings/allow_ingame_team_change.json`, display name *Team Change In-Game*) but
no custom-games datasource lists it, so the lobby UI never shows it — the mod writes it:

`mod_latejoin()` → `setgametypesetting( allowingameteamchange, want )` **only when the readback
differs** (`is_true()` on the value, since the key is a DDL bool and `gts_set`'s `!==` could see a
bool/int mismatch and rewrite every round) + `level.allow_teamchange = want`. `gf_teamchange` 1
(default) = on for everyone, any time (klaze's call — a mid-match team swap is then one pause-menu
trip for anybody); 0 = written 0 (the stock default).

⚠ **Unmeasured:** whether a change of `allowingameteamchange` fast-restarts the match the way
`maxplayers` and the round limits do (measured 2026-09-15). It is written once per match (round 1
of a lobby that has it 0); if klaze sees a reload at match start after this build, this key is the
first suspect — `gf_teamchange 0` removes the write.

## 4. Test sheet (one late join measures most of it)

Start a private match with two or more humans, let round 1 begin, then have someone join.

| # | look at | expect | tells you |
|---|---|---|---|
| 1 | host feed | `JOIN <name> lobby=<v> humans A/X score A-X -> <side> (<reason>)` | the hook fired; `lobby=` is the engine's answer for a late joiner |
| 2 | joiner's screen | class choice / spawn on `<side>` next spawn wave | stock accepted the handed side |
| 3 | host feed, next frame | `JOIN bot dropped from <side> -> AvX` when that side had a bot and was bigger | the even-up drop |
| 4 | tie case (equal humans, level score, not round 1 countdown) | joiner benched + *TEAMS ARE TIED* bold every 5 s; pause menu shows CHANGE TEAM; picking a side spawns him | the picker path end to end |
| 5 | match start | no reload after the countdown | `allowingameteamchange` is not a restart key |
| 6 | `JOIN ... -> stock` line for a joiner who still benches | `lobby=spectator` | the session put him in a caster slot on purpose — `iscodcaster()` pass-through; report it |

Rows 1-3 are the bug fix; row 4 is klaze's tie rule; rows 5-6 are the unknowns this build carries.

## 5. Knobs

| dvar | default | where |
|---|---|---|
| `gf_latejoin` | 1 | menu Teams → *Late join: fewer humans > losing side > pick* / *stock (spectator)*; app Teams row |
| `gf_teamchange` | 1 | menu Teams → *Pause-menu CHANGE TEAM: on for everyone* / *off*; app Teams row |

Both plain dvars (not in the packed store). Bridge: `set gf_latejoin 0` (17 B), `set gf_teamchange 0`
(19 B). Read on every connect (the hook checks `cfg_latejoin()` at call time) and each round
(`mod_apply`); a `gf_teamchange` change from the app lands at the next round, from the menu at once.

Related: [`lobby-settings.md`](lobby-settings.md) (Route A — the same setting reached from the lobby
side), [`bots.md`](bots.md) (`humans_on`, the even-up drop), `game-systems.md` §16 *Team assignment*.
