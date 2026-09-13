# The SESSION map switch — measured 2026-09-12: the lobby follows, and the budget reads 12

**`switchmap_load( map, gametype )` + `switchmap_switch()` from inside a match moves the SESSION,
not just the loaded map.** And the load half on its own **stages the next map for the pregame
lobby** without leaving the match — see *Stage*, below. Measured with `src/lobby_state/` after a **lobby-route** restart — the
route that discards a load-time override (menu-map.md, trap 1). It did not discard this.

This is the call `bbf94f9` (2026-09-11 17:59) recorded as *inert in MP*. Every run behind that verdict
was compiled by ACTS with the map-name literal wrapped in the 3-byte header the engine reads as an
encrypted string and turns to garbage ([`../../tools/strip-strhdr.ps1`](../../tools/strip-strhdr.ps1)).
The string reaching the engine intact is the only thing that changed between "inert" and this.

---

## The readout — `lobby_state`, pass 1, photographed off the screen

Sequence: `gunfight_menu` (stripped build) → `Map → Method: SESSION` → `Map → Zoo` → lobby showed the
new map → `inject.sh lobby_state` → **match started FROM THE LOBBY** → readout.

| Line | Value | Reading |
|---|---|---|
| LS1 | `sv_mapname=mp_zoo_rm` | the lobby reloaded **Zoo** — the carried map, not the lobby's original |
| LS2 | `mapname=- ui_mapname=-` | those dvars do not exist in CW; `-` is the default, not a failure |
| LS3 | `rootmap=mp_zoo_rm` | `getrootmapname()` agrees |
| LS4 | `g_gametype=gunfight ui_gametype=-` | gametype rode along |
| LS5 | `level.gametype=gunfight teambased=1` | |
| LS6 | `timelimit=40 roundwinlimit=6` | menu-set values, still in the session |
| **LS7** | **`com_maxclients=12`** `sv_maxclients=-1` | **twelve slots in a Gunfight session** — menu-map.md's `100012` |
| LS8 | `maxplayers=8 teamcount=2 maxteam=0` | `maxplayers` is the menu's own earlier write (team size 4); not the ceiling |
| LS9 | `players all=1 allies=0 axis=1` | host alone |
| LS10 | `private=1 online=1 mode=mp` | private online MP session |
| **LS11** | **`gf_map_method=1`** `gf_team_size=4 gf_timer=120` | **method 1 = SESSION** (`switchmap_load`), not the Atian `map()` carry |
| LS12 | `pass=1` | first pass |

Labelled text on screen is itself a result: it is the first ACTS-built payload to render a string
literal, which confirms the header-strip fix in-game.

⚠ **Not yet recorded: which playlist the lobby was created from.** 3v3 Gunfight (8 slots) would mean
the switch *raised* the budget 8 → 12. A 12-slot start would mean Gunfight rode into a 12-slot session.
Different mechanisms, same outcome; ask before building on either.

---

## What it changes

- **Goal B (stale UI after a carry) is closed by construction** — the session moved, so the scoreboard,
  lobby card and presence have nothing stale to show. Confirm presence (friend list) on the next run.
- **The Atian Menu and the F7-only rule are no longer load-bearing for the map.** The lobby route
  keeps the switched map. cwpatch stays useful for `fast_restart`/`full_restart` but is not a
  prerequisite for changing map.
- **CLAUDE.md's "unexplained 12"** — the earlier `com_maxclients=12` from `test_mapswitch` — now has a
  second instance, and both followed a map switch toward a 6v6 map. Hypothesis: **the budget follows
  the map's default size**, not the gametype.
- `bbf94f9`'s closure of `switchmap_load` is **retracted** by this measurement.

## ✅ 6v6 — filled, 2026-09-12

`gunfight_menu` got a `6v6` item (`clamp_team_size()` allows it at budget 12); klaze ran
`Teams → 6v6 → Fill with bots` in the switched session and **it filled to 6v6.** That is the team-size
goal at the size the project set out for, in a Gunfight session, on a 6v6 map, from script alone —
no glitch, no DLL, no second account. ⚠ With **bots**, like L6; a human 6v6 is the next body test.
As of this commit the menu defaults to the SESSION method and labels it as verified.

## Stage — `switchmap_load` alone sets the lobby's NEXT map (klaze, 2026-09-12)

**Observed, from the menu's own two-call sequence.** The menu's in-match switch is
`switchmap_load( map, gametype )` → `level waittilltimeout( 25, #"switchmap_preload_finished" )` →
`switchmap_switch()`. klaze picked a map and then **ended the match from the pause menu during that
wait** — after the load half, before `switchmap_switch()` had run. The **pregame lobby came up with
the picked map already selected, ready to start.**

So the two builtins split cleanly:

| Call | Does | Lobby |
|---|---|---|
| `switchmap_load( map, gametype )` | loads the pair and **writes it into the session as the next map** | shows it as soon as the match ends |
| `switchmap_switch()` | performs the transition now | follows, as measured above |

That is the **lobby's own selection**, reached from in-match GSC — the layer
[`lobby-setters.md`](lobby-setters.md) targets with a native `LobbySetMap` call. The compat gate the
whole hunt fought is not in the way here for the same reason it is not in the way for the native
call: nothing asks the picker. ⚠ It needs a match to be running (the payload is `bb.gsc`-hooked, MP
only); the native route stays the *from-the-lobby* route.

**The menu now offers both verbs.** Every map / gametype pick opens a two-row page:
`Stage for lobby - next match` (the load half, nothing else; the match keeps running and the state
line shows `next:<map>`) and `Switch NOW` (the verified sequence, unchanged). The app's command
channel carries the same choice as `gf_cmd_stage`. `gunfight_menu.gsc` → *"── Map"*.

**The second-switch delay, while here.** klaze also reports the first NOW switch of a session goes
at once, and later ones sit the full 25s before moving — `switchmap_preload_finished` arrives once.
Campaign's own transition never waits for it (`cp_common/load.gsc:412-414`: `switchmap_load`, one
network frame, `switchmap_switch`); the menu keeps the Zombies wait because that is the sequence
that was measured. A shorter cap is the trim if it ever matters.

### Untried — not ruled out

- **Joiners.** Everything above is host-side. A friend in the lobby when the staged map appears,
  and in the next match, is the test that matters — the same clause as the carry's failure.
- **A natural match end** (score / round limit → `exitlevel`) versus the pause-menu End Game that was
  measured. Same destination; not yet seen.
- **The round boundary.** `level` is torn down per round; the engine's staged map should not be
  level-scoped, but nobody has staged in round 1 and read the lobby after round 3.
- **Staging a gametype.** Inferred from the map result (same builtin, same two arguments); the
  lobby's mode after a `switchmap_load( map, "tdm" )` stage has not been read.
- **Re-staging** (stage A, then stage B) and **un-staging** (stage the current map again). The
  second `switchmap_load` of a session is known to *take* — the delayed NOW switch lands on the right
  map — but the lobby after two stages has not been read.
- **`map_restart()` with a stage pending** — does the restart consume or discard it?
- **`sv_mapname` / `getrootmapname()` in the lobby** — `src/lobby_state/` is in-match; a
  frontend-hooked read would say what the lobby's own store holds after a stage.

## Next

1. **Does the budget track the map?** Session-switch to Mansion (`mp_sm_market`, 2v2 — ⚠ not `mp_sm_central`, which is ICBM; names audited in `docs/reference/bocw-maps.md`) and read LS7.
   8 there and 12 again on Zoo = the map sets the budget, and the 6v6 maps are where 6v6 lives.
2. **Joiners.** Everything above is host-side. A second account joining the switched lobby is the
   test that matters for hosting.

## Untried — not ruled out

- A switch from a lobby created under a *12-slot* playlist (private TDM), to compare budgets.
- `switchmap_load` with a **different gametype** than the current one (`gunfight_3v3`, `tdm`) — the
  menu passes the current `g_gametype`; the builtin takes any.
- Whether the SESSION switch also resets gametype settings the way the `map()` carry did (trap 2).
  LS6 suggests not — the menu-set `timelimit=40` / `roundwinlimit=6` survived — but that is one read.
