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

## 2026-09-23 — more stock events, and how they travel ([hud-channels](hud-channels.md))

- **An LUI event is a write to the client's `script_notify` UI model** — the client twin of the lower
  message (`hud_message_shared.csc:27-41`) fires the same hash by writing `script_notify.arg1..N` +
  `numArgs`. One slot per client, so stock sends **one event per client per frame** (the luielem queue,
  `lui_shared.gsc:221-235`). Pace yours the same way.
- **The lower message**: `player hud_message::setlowermessage( #"mp/waiting_to_spawn", secs )`
  (`hud_message_shared.gsc:57` → `#"hash_424b9c54c8bf7a82"`, `2, text, secs`) — a lower-centre line with our
  own countdown; `clearlowermessage()` takes it down.
- **Gunfight's "N v M" banner**: `#"hash_6b67aa04e378d681"`, `3, 2, allies, axis` (`player_killed.gsc:2556`)
  — an indexed notification; `1, 7` / `2, 1, n` / `2, 6, loadout` are its other stock shapes.
- **`function_2891bd54`** (`exe+3d1f190`, beside `luinotifyevent`) is the same kind of event addressed to one
  luielem instance — the transport of the event-backed luielems ([hud-channels](hud-channels.md) §1).

