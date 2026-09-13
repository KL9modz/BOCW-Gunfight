# `luinotifyevent` — stock LUI widgets are a display channel (2026-09-13)

**Seen in-game by klaze:** the Host page's *Pause* put the game's own **TIMEOUT** overlay
("waiting…" text, ticking timer) on screen. Nothing in the mod draws that. The mod fires

```
luinotifyevent( #"esports_game_paused", 1, 1 );   // pause   (globallogic.gsc:6128, the CDL pause)
luinotifyevent( #"esports_game_paused", 1, 0 );   // resume  (:6164)
```

and the **client-side Lua UI's handler for that event draws the stock widget**. Same for the resume
countdown: `matchstarttimer( 5 )` fires `create_prematch_timer`, the pregame countdown widget.

So the rule in [hud-and-control-app / the menu header] — "server GSC has two text channels
(iprintln / iprintlnbold)" plus the hint string (region 4, [hint-panel](hint-panel.md)) — gets a
**fourth channel: any stock LUI event, drawn by its shipped handler.** Server script cannot *create*
HUD elements in T9 (no hudelem builtins), but it can *trigger* every widget the client already has,
with the parameters that widget expects. Level-wide (`luinotifyevent(...)`) or per client
(`player luinotifyevent(...)`).

**The limit:** the widgets' TEXT comes from the client's own string tables — the string args are
localized-string hashes (`#"mp/kill_denied"`) or indices, not free text. Numbers (end times, counts,
entnums, team ranks) are free. Free text stays `iprintln` / `iprintlnbold` / the hint string.

## Reusable widgets (call shapes from the dump)

| event | args (count, ...) | what the client draws | host-tool use |
|---|---|---|---|
| `esports_game_paused` | `1, on` | the TIMEOUT / paused overlay | ✅ Pause (menu, built) |
| `create_prematch_timer` | `2, endtime_ms, show_countdown` | the big pregame countdown (`globallogic.gsc:1442`; `gettime() + n*1000, 1` at `:77`); end it with `prematch_timer_ended` `1, show` | any countdown: "switching in 30", round-start delay |
| `show_gametype_objective_hint` | `1, string_hash` | the objective hint banner (`:1416`, per player) | stock strings only |
| `player_callout` | `2, string_hash, entnum` | "kill denied"-style callout naming a player | stock strings only |
| `team_eliminated` | `1, teamranking` | team-eliminated banner (per player) | end-of-round flair |
| `show_outcome` | `5..7, ...` | VICTORY / DEFEAT outcome screen (`:319-353`) | needs the enums; risky mid-match |
| `quick_fade` | `0` | a quick screen fade | transitions |
| `top_squad` | `n, client_nums...` | top-squad card | end-of-match |
| `medal_received`, `killstreak_received`, `rank_up`, `score_event`, `hvo_card`, `open_side_mission_countdown` (`1, list_index` — the map-switch countdown, `:2228`), `round_start`, `prematch_waiting_for_players`, `prematch_over`, `clear_notification_queue`, `show_perk_notification`, `waypoint_captured`, `oic_eliminated`, `potm_*`, `*_killcam_transition` | see grep | stock flair | catalogue only |

Full catalogue: `grep -rhoE 'luinotifyevent\( #"[a-z0-9_]+"' scripts/mp_common scripts/core_common`
in the dump — ~40 named events plus ~25 still-hashed ones.

⚠ Each event's handler validates its own parameter shape; a wrong arg count or type is at best
ignored, at worst a client Lua error. Copy a stock call site exactly. Only `esports_game_paused`
and `create_prematch_timer` (via `matchstarttimer`) have been seen working from the mod.
