# The lobby layer — where each step of hosting actually lives

The hosting workflow is: **create a Custom Games private lobby → pick map, mode and rules → invite
players → set teams → start the match.** Every one of those happens *before* the match exists.

Everything this project has built runs **in-match** — injected GSC in the MP VM, firing on
`on_start_gametype`. So the entire setup phase has been invisible to it. This note maps which layer
each step lives in, and what is reachable in each.

---

## Which layer owns which step

| Step | Layer | Reachable? |
|---|---|---|
| Create the lobby | LUA frontend + playlist | ❌ **the wall** |
| Pick map / mode | LUA frontend | ❌ the wall |
| **Set rules** | LUA frontend, driven by **`scriptbundle/gamesettings/`** | ✅ **the bundles are in the dump** |
| Invite / teams | LUA frontend | ❌ the wall |
| Start the match | `lobbylaunchgame` — cwpatch binds it to **F4** | ✅ via DLL hotkey |
| In-match everything | MP VM | ✅ where all our code runs |

⚠ **`scripts/core/gametypes/frontend.gsc` is NOT the lobby.** It looked promising — it is a real
gametype with `event_handler[gametype_init]` and a `#"menu_response"` callback — but reading it, it is
the **main-menu 3D space**: achievements, the arcade machine, dynent state, `gamestate::set_state(
#"pregame" )`, `level.teambased = 0`. It has no map, mode, rules or team handling. **Do not go looking
for the lobby in GSC; it is not there.**

---

## 🔓 `scriptbundle/gamesettings/` — the complete rules-menu surface, 427 bundles

Each JSON is **one menu row**. `.claude/CLAUDE.md` already cites `time_limit_seconds.json`; the whole
directory had never been read.

```json
{ "name": "time_limit_seconds", "setting": "timeLimit", "optionscount": 6,
  "value1": "0", "value2": "20", "value3": "30", "value4": "40", "value5": "50", "value6": "60",
  "displayname": "localized18#hash_62c13100f00ec8ed", "type": "gamesettings" }
```

| Field | Meaning |
|---|---|
| `setting` | the gametype setting the row writes — the same name `setgametypesetting()` takes |
| `optionscount` | **how many values the menu publishes** — often fewer than are declared |
| `valueN` | the values, in order |
| `displayname` | localized label |

**This is the map between the rules menu and `getgametypesetting`.** Anything with a bundle is
menu-settable; anything without one can only be reached from script.

### Per-gametype variants exist, and the suffix names them

`round_win_limit_gunfight` · `time_limit_seconds` · `time_limit_dom` · `score_limit_ctf` ·
`round_limit_spy` · `round_score_limit_control` · `score_limit_sd_dem`

So the menu picks a *variant* per mode. Gunfight's own bundles: `gunfight_rounds_per_loadout`,
`gunfight_spy_plane`, `round_win_limit_gunfight`, and `time_limit_seconds` — which publishes exactly
`0 / 20 / 30 / 40 / 50 / 60`, matching what was measured in-game.

⚠ **Which bundles a given gametype's menu shows is NOT in the dump.** That selection lives in the
playlist/LUA layer — the FNV1a64 wall. The dump says what a row *would* do, never whether it appears.

---

## 🔓 THE LEAD — `max_players.json` publishes 1 through 12

```json
{ "name": "max_players", "setting": "maxPlayers", "optionscount": 12,
  "value1": "1" … "value12": "12", "displayname": "localized18#menu/max_players" }
```

**A rules-menu row, offering up to twelve players.** And unlike `time_limit` or `round_win_limit`,
**there is no per-gametype variant of it** — no `max_players_gunfight`, no `max_players_dom`. One
generic row.

`maxPlayers` is a real setting: `uint:4` in `custom_games.ddl`, `uint:7` in `mp_custom_game.ddl`, read
live at `challenges.gsc:109`.

### Why this could matter more than anything else in the project

The team-size goal has been stuck on `com_maxclients` being fixed at lobby creation and read-only from
script. **A rules-menu row that sets max players to 12, applied before the match starts, acts at
exactly the layer that has been out of reach.**

⚠ **Two things are unknown and neither is answerable from the dump:**

1. **Does the row appear in a Gunfight custom lobby's rules menu?** Playlist layer, the wall.
2. **Does `maxPlayers` gate joins, or only challenges?** Its only *known* script consumer is
   `challenges.gsc`. `com_maxclients` may be set from it at lobby creation, or may be independent.

**Both are free to check in-game — no injection, no exposure, about two minutes.** This is a Phase 0
test, and it is now the cheapest thing on the board.

⚠ Phase 0 **T0.2** already walked the Gunfight rules pages — **looking for the timer.** Nobody was
looking for a player-count row. Absence of a note is not a negative result here.

---

## 🔓 `bot_autofill_allies` / `bot_autofill_axis` — the bots, from the menu

Both exist as bundles with two options. Also `bot_difficulty_allies` / `_axis` (4 levels) and
`bot_difficulty_vs_bots`.

`.claude/CLAUDE.md` → Phase 3 says **"bots before humans"** and the project never had a mechanism.
[`cw-builtins.md`](cw-builtins.md) found `bot::add_bot()` as the script route. **This is the menu
route, and it needs no injection at all** — which makes it strictly better for filling a test lobby.

⚠ Same unknown: whether the row appears in a Gunfight custom lobby.

---

## Other rows worth knowing

| Row | Setting | Published |
|---|---|---|
| `team_num_lives` | `teamNumLives` | 29 values |
| `player_num_lives` | `playerNumLives` | 14 values |
| `round_win_limit_gunfight` | `roundWinLimit` | 6 |
| `gunfight_rounds_per_loadout` | `gunfightRoundsPerLoadout` | 6 (0–5) |
| `gunfight_spy_plane` | `gunfightSpyPlane` | 3 |
| `allow_ingame_team_change` | `allowInGameTeamChange` | 2 |
| `overtime_time_limit` | `OvertimetimeLimit` | 20 |

⚠ **No bundle writes `maxsquadplayers`.** Grepped all 427. So the team-size lead from
[`dump-cross-check.md`](dump-cross-check.md) has **no menu row** and stays a `setgametypesetting()`
target — the two leads are independent, and `maxPlayers` is the cheaper one to try first.

---

## Tests, cheapest first

| # | Test | Exposure | Answers |
|---|---|---|---|
| **L1** | In a **Gunfight Custom Games** lobby, walk every rules page looking for **Max Players** | **none** | Whether the row exists at all |
| **L2** | If it exists, set it to **12** and count the lobby slots | **none** | Whether `maxPlayers` drives lobby size — **the whole team-size goal, with no code** |
| **L3** | Look for **Bot Autofill** / **Bot Difficulty** rows on the same pages | **none** | A no-injection way to fill a test lobby |
| **L4** | With Max Players at 12, start the match and read `lobby_probe` probe `1xxxxx` | injection | Whether `com_maxclients` followed the setting |

⚠ L1–L3 need no injection and no modded anything. **Do them before any of the C-band tests** — if L2
works, several of those stop mattering.

## Untried — not ruled out

- **The other ~390 bundles.** Only the team/player/round/score families were read.
- **`localized18#…` display names.** The localization table is not in the dump, so a row's on-screen
  wording cannot be predicted — only its `setting` and values. Walking is the only way to match them up.
- **Whether the rules menu writes settings that survive the map carry.** The carry is known to reset
  gametype settings ([`menu-map.md`](menu-map.md)); whether a lobby-set `maxPlayers` survives it is
  untested, and matters for combining L2 with the any-map recipe.
