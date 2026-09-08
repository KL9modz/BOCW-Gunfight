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

---

## ✅ CONFIRMED IN-GAME — the two Gunfight variants have different bundle sets

Observed by klaze 2026-09-08:

> The lobby UI lets me choose a round timer for **normal Gunfight**, but **not for 3v3 Gunfight**.
> And in a 3v3 lobby it **restricts team assignment to 3 per side.**

That settles a question the dump could not: **`gunfight` and `gunfight_3v3` are configured
separately**, and the per-variant bundle selection is real. `time_limit_seconds` (the
`0/20/30/40/50/60` row) is in normal Gunfight's set and absent from 3v3's — which is why 3v3 sits at
its 40s default with no way to change it from the menu.

⚠ That is a *menu* limitation, not an engine one. `timer_override` already holds 60s in a 3v3 lobby
([`menu-map.md`](menu-map.md)), which is the point: **the bundle set filters the menu, not the
setting.**

### 🔓 The per-side cap is NOT a menu row — and that sharpens the `maxsquadplayers` prediction

All 427 bundles were read. **The only player-count row of any kind is `max_players`.** There is no
squad-size row, no per-team row, nothing that writes a 2-or-3 per side value.

So the 3-per-side restriction is **baked into the gametype config**, not exposed to the menu — which
is exactly the shape of a setting that has a DDL field and no bundle. **`maxsquadplayers` is that
setting** (`uint:6` in `custom_games.ddl`, no bundle, read into `level.var_704bcca1` at
`globallogic.gsc:241` — [`dump-cross-check.md`](dump-cross-check.md)).

**This makes a falsifiable prediction.** `lobby_probe` probe `6xxxxx`:

| Lobby | Predicted `maxsquadplayers` |
|---|---|
| **3v3 Gunfight** | **3** |
| **normal Gunfight** (2v2) | **2** |

If it reads 3 and 2, `maxsquadplayers` **is** the per-side cap, it is a gametype setting, and
`setgametypesetting( #"maxsquadplayers", 4 )` is the lever. If it reads something else — 8, 0,
undefined — the cap is somewhere the dump has not shown and this lead is dead.

⚠ **Run the probe in BOTH lobbies.** One reading cannot distinguish "it is the cap" from "it happens
to be 3".

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

## ⚠ 184 of 427 rows hide values from the menu — this generalises

`.claude/CLAUDE.md` notes `time_limit_seconds` "declares 20 values but publishes 6". **That is not a
quirk of the timer.** 184 bundles publish fewer values than they declare. The menu is a *filtered
view*; `setgametypesetting()` is not filtered.

Gunfight's own rows and what they hide:

| Row | Setting | Published | Hidden |
|---|---|---|---|
| `capture_time_gunfight` | `captureTime` | 1 2 3 4 5 10 15 | **30 45 60 90 120** |
| `round_win_limit_gunfight` | `roundWinLimit` | 1–6 | **7 8 9** |
| `gunfight_spy_plane` | `gunfightSpyPlane` | 0 1 2 | **3** |
| `time_limit_seconds` | `timeLimit` | 0/20/30/40/50/60 | 4 5 6 7 8 9 10 11 … |
| `gunfight_rounds_per_loadout` | `gunfightRoundsPerLoadout` | 0–5 | — |

⚠ **A declared-but-hidden value is not a tested value.** The timer's hidden range is known good (the
clamp is 0–1440 minutes). Nothing else here has been exercised, and a value the menu refuses to offer
may be refused for a reason.

Full table for all 427: [`gamesettings-catalog.md`](gamesettings-catalog.md).

## Untried — not ruled out

- **~200 MP rows never cross-referenced against Gunfight.** The catalog lists them; which appear in a
  Gunfight lobby is still the playlist layer.
- **`localized18#…` display names.** The localization table is not in the dump, so a row's on-screen
  wording cannot be predicted — only its `setting` and values. Walking is the only way to match them up.
- **Whether the rules menu writes settings that survive the map carry.** The carry is known to reset
  gametype settings ([`menu-map.md`](menu-map.md)); whether a lobby-set `maxPlayers` survives it is
  untested, and matters for combining L2 with the any-map recipe.
