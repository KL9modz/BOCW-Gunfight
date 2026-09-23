# HUD channels — every way script can put something on screen (2026-09-23)

klaze: *"determine how to properly display HUD elements and text on screen in additional ways than what
we currently use."* Read from the dump and the retail builtin table; **nothing here has run yet.**
`src/hud_probe/` measures all of it in one launch (§6), and the record sheet at the bottom is where the
answers go.

**The answer up front.**

- T9 has no hudelems (`newclienthudelem`, `settext`, … are absent from `funcs_cw.csv` — [hint-panel](hint-panel.md)).
  Doing it *properly* in T9 means **driving the client's own LUI widgets**: luielems, LUI menus
  (`openluimenu` / `setluimenudata`) and LUI events (`luinotifyevent`), plus a handful of engine HUD
  builtins and world-space objectives. The menu uses a slice of each. **The dump holds ten routes it has
  never used.**
- 🔓 **The biggest: event-backed luielems — `LUIelemBar` and `LUIelemCounter`.** They register **no
  clientfields** and have **no material field**, so they sidestep both walls that closed the luielem
  route in [lui-elems](lui-elems.md): the joiner-desync rule and the material bgcache. Stock MP already
  drives an element of the same kind (the Cruise Missile lock-on), so the transport is live in MP. One
  unknown remains: whether the MP client package ships these two widgets. A positioned, coloured
  **box/bar** and a positioned **number**, from host GSC, possibly visible to everyone.
- ✅ **Ready now** — call shapes stock itself fires in MP matches, so they reach joiners by construction: a
  full-screen colour flash / tint (plus a **drawHUD** flag that, if it means what it says, makes a dark
  backdrop the HUD draws over), the **lower message** with a countdown, the engine **announcement** with
  a number, Gunfight's own
  **"N v M" alive banner**, the **EMP overlay**, objective **progress rings** and **per-player** world
  markers, and the **HUD switches** (hide the HUD, hardcore HUD, hide the mini-scoreboard).
- 🔓 **One new free-text lead: `TempDialog`.** Stock `face.gsc` writes *runtime-built* strings into it,
  so if the menu ships in MP, plain text is its designed input — no localize crash by construction.

## What the menu uses today (for contrast)

| channel | where it lives | status |
|---|---|---|
| feed — `iprintln` | every page, status blocks | ✅ working, ~4 lines, fades |
| centre line — `iprintlnbold` | carousel, toasts | ✅ working, one line |
| hint strings on glued `trigger_radius` (+ `[{+bind}]` glyphs, the others-facing welcome line, the broadcast banner) | [hint-panel](hint-panel.md), [forge](forge.md) | ✅ one short line per trigger |
| `luinotifyevent`: `esports_game_paused`, `create_prematch_timer` (via `matchstarttimer`), `round_start` | Pause, round start | ✅ [lui-events](lui-events.md) |
| world uimodels: `hudItems.team*.noRespawnsLeft`, `hudItems.hideOutcomeUI`; clientfield `out_of_bounds` | presentation fix, outcome, death barriers | ✅ |
| one objective marker, `#"escort_goal"` | race gates | built |
| `visionsetnaked` | Fun & vision page | built |
| client-local `LUIelemText` (stock keys only) | `src/gunfight_menu_c/`, host-only | ✅ measured; plain text is fatal |
| `ScriptMessageDialog_Compact` popup (plain text renders) | `src/lui_probe/` | ✅ renders; dismissal is v2's open question ([pause-menu](pause-menu.md)) |

## The map — every channel, old and new

| # | channel | draws | free text | numbers | who sees it | status |
|---|---|---|---|---|---|---|
| — | feed / centre / hint / 3 LUI events / popup | above | ✅ / ✅ / ✅ / ✗ / ✅ | ✅ | host or all | in use |
| 1 | **`LUIelemBar`** (event-backed luielem) | coloured box / bar with a fill %, anywhere | — | fill % | host; joiner = the question | 🔓 NEW · probe 9 |
| 2 | **`LUIelemCounter`** (event-backed luielem) | a coloured number, anywhere | — | ✅ | host; joiner = the question | 🔓 NEW · probe 10 |
| 3 | `lui::screen_flash` / `screen_fade` (`FullScreenBlack`) | full-screen colour, alpha, fades; **drawHUD veil** | — | — | everyone (stock-registered both sides) | ✅ NEW · probes 1–2 |
| 4 | `hud_message::setlowermessage` | lower-centre line + whole-second countdown | stock keys | countdown | per player | ✅ NEW · probe 3 |
| 5 | `announcement()` / `clientannouncement()` | engine announcement with a number | stock keys | ✅ | all / one client | ✅ NEW · probe 4 |
| 6 | alive banner `#"hash_6b67aa04e378d681"` (+ its other indices) | Gunfight's "N v M" banner | — | ✅ | per player | ✅ NEW · probe 5 |
| 7 | `EmpRebootIndicator` | EMP reboot overlay with a timed progress | — | times | per player | ✅ NEW · probe 6 |
| 8 | objective progress ring, per-player markers, marker-on-entity | world icons | stock objective names | progress | all or chosen players | ✅ NEW · probe 7 |
| 9 | `setclientuivisibilityflag` / `setclienthudhardcore` / `setclientminiscoreboardhide` | hide HUD / hardcore HUD / no mini-score | — | — | per player | ✅ NEW · probe 8 |
| 10 | `printtoprightln` | top-right text, coloured | ✅ if it draws | ✅ | ? | ❓ NEW · probe 11 |
| 11 | `setclientcgobjectivetext` | the per-client objective text (scoreboard / pause?) | ❓ | — | per player | ❓ NEW · probes 12 / 20 |
| 12 | `lui::timer` → `HudElementTimer` | positioned countdown | — | ✅ | per player | ❓ probe 13 (listed untried in [lui-elems](lui-elems.md)) |
| 13 | `MPHintText` | hint box | ❓ | — | per player | ❓ probes 14 / 21 (listed untried in [lui-elems](lui-elems.md)) |
| 14 | **`TempDialog`** | title + one line | ✅ by stock precedent | ✅ | per player | 🔓 NEW · probe 15 |
| 15 | **a menu made of world markers** — a board of icons, a view-locked icon, the on-screen "using" bar | icons, rings, states; one screen bar | ✗ (words stay in the feed / centre line) | rings | chosen players | 🔓 NEW · probes 16–18, §8 |
| 16 | **the subtitle channel** — `subtitleprint( lcn, msec, text )` | a bottom-centre line | ✅ if it prints raw | ✅ | **host only** (client builtin) | 🔓 NEW · `src/subtitle_probe_c/`, §9 |

## 1. Event-backed luielems — `LUIelemBar`, `LUIelemCounter` (the headline)

`scripts/autogenerated/luielems/` holds **72** elements, and they come in **two generations**:

| kind | how a field reaches the client | count | examples |
|---|---|---|---|
| clientfield-backed | a `clientuimodel` clientfield per field, registered on **both** sides (`add_clientfield` → `clientfield::register_luielem`) | 54 | `LUIelemText`, `LUIelemImage`, `full_screen_black`, `mp_revive_prompt`, `hud_spy` |
| **event-backed** | **nothing registered**; each set is an LUI event addressed to one element instance | **6** | **`LUIelemBar`, `LUIelemCounter`**, `remote_missile_target_lockon`, `lui_plane_mortar`, `sr_objective_secure_hud`, `sr_crafting_table_menu` |
| no fields | open / close only | 12 | `fail_screen`, `success_screen`, `mp_prop_controls`, `debug_center_screen` |

**The evidence, link by link:**

- `luielembar.gsc` `setup_clientfields()` is one line, `cluielem::setup_clientfields( "LUIelemBar" )`, and
  that (`lui_shared.gsc:58`) only numbers the instance — no `add_clientfield`, no registration.
- Every setter is `player lui::function_bb6bcb89( hash( name ), idx, field, value, 0 )` (`lui_shared.gsc:185`):
  de-dup per player (`function_bed1b789`, `:155`), queue, and one entry per server frame
  (`function_1c4c4975`, `:221`, `waitframe( 1 )` at `:235`) into
  **`function_2891bd54( menu, idx, 2, field, value )`** (`:209`).
- `function_2891bd54` sits at `exe+3d1f190`, **0x20 after `luinotifyevent`** (`exe+3d1f170`), in both the
  function and the method pools (method `exe+5d311a0` vs `luinotifyevent` `exe+5d31140`); max 10 args =
  `luinotifyevent`'s 9 + the instance index. It is the LUI-event sibling addressed to one element.
- Client side, `luielembar.csc` `register()` also only numbers the instance; the only client registries
  that remember luielem data (`level.var_a706401b`) are **campaign-only** (`lui_shared.csc:421`,
  `function_4206783a` = `sessionmodeiscampaigngame()`).
- ✅ **The transport is live in stock MP.** The Cruise Missile's lock-on (`remotemissile_shared.gsc:63`
  register, `:1289-1298` open + five sets) is an event-backed element driven through exactly this path.

**What that buys, against the walls in [lui-elems](lui-elems.md):**

1. **No clientfield is added** — so the [game-systems](game-systems.md) §2 objection (extra fields desync a
   vanilla joiner) does not apply. It would be the first *positionable, general-purpose* element the server
   can hand a joiner (`FullScreenBlack` already reaches them, but it only covers the whole screen).
2. **No material field** — `LUIelemImage` drew nothing because its material needs a bgcache
   ([lui-elems](lui-elems.md) Stage 2). A bar's fill is the widget's own; the only inputs are geometry,
   colour and a percentage. A bar at 100 % is a box.
3. **Numbers are the payload** — `LUIelemCounter`'s `number` is an int, so there is no localize wall.

**The field maps** (1-based, in the order of each element's reset list, `luielembar.csc` /
`luielemcounter.csc` `function_fa582112`; the server setters confirm every index):

| # | `LUIelemBar` | `LUIelemCounter` |
|---|---|---|
| 1 | x | x |
| 2 | y | y |
| 3 | width | height |
| 4 | height | fadeOverTime |
| 5 | fadeOverTime | alpha (0–15) |
| 6 | alpha (0–15) | red (0–15) |
| 7 | red (0–15) | green (0–15) |
| 8 | green (0–15) | blue (0–15) |
| 9 | blue (0–15) | **number** |
| 10 | **bar_percent (0–127)** | horizontal_alignment |

Colours and alpha travel pre-quantised — the stock setters send `int( value * ( 16 - 1 ) )`, and
`bar_percent` `int( value * ( 128 - 1 ) )`. The stock pixel helpers divide `x`/`y` by **15** and
`width`/`height` by **4** (`luielembar.gsc` `function_e5898fd7` / `function_35f52fe9`); the one
calibration on record ([lui-elems](lui-elems.md), client-local `LUIelemText`) found non-pixel, per-axis
scales, so expect to calibrate once from a screenshot.

**The call shape** — host GSC, no client payload, no `#using` of the element script (nothing in MP links
`luielembar.gsc`; the builtins and `lui_shared` are enough):

```gsc
e = #"luielembar";                                   // == hash( "LUIelemBar" ); hash() lowercases
player openluielem( e, 0, 0 );                       // instance 0 (nothing in MP uses the name)
player lui::function_bb6bcb89( e, 0, 1, 8, 0 );      // x      (15-px units)
player lui::function_bb6bcb89( e, 0, 3, 75, 0 );     // width  (4-px units)
player lui::function_bb6bcb89( e, 0, 6, 15, 0 );     // alpha  (0-15)
player lui::function_bb6bcb89( e, 0, 7, 15, 0 );     // red
player lui::function_bb6bcb89( e, 0, 10, 127, 0 );   // bar_percent: full = a box
// close the stock way (lui_shared.gsc:79): drop the instance's de-dup cache, then close
if ( isdefined( player.var_3bc46b87 ) && isdefined( player.var_3bc46b87[ e ] ) )
    player.var_3bc46b87[ e ][ 0 ] = undefined;
player closeluielem( e, 0 );
```

**The one unknown, and the free way to shrink it first.** No stock script anywhere *opens*
`LUIelemBar` or `LUIelemCounter` (`cp_common/util.gsc:190` registers a bar in a helper nobody calls; the counter
has no user at all). Grounds for optimism: `LUIelemText` is registered only by CP and ZM and still rendered
in MP ([lui-elems](lui-elems.md)), so the generic `LUIelem*` set appears to ship together. **Before any
launch, grep klaze's decompiled UI** (`C:\bocw\lui-source\`, [lui-source](lui-source.md)):

| name | script hash | expect |
|---|---|---|
| `LUIelemText` (positive control) | `5db5c2be57039a7d` | present — it rendered |
| `LUIelemBar` | `7d53f2a6294a2aa7` | ? |
| `LUIelemCounter` | `582e09d72ef4812e` | ? |
| `TempDialog` | `749bf337f9cfe303` | ? (§3) |
| `MPHintText` | `523ec4f7daad9fb2` | ? |
| `HudElementTimer` | `39a1d52a9b0471bf` | ? |
| `EmpRebootIndicator` | `6f9131c1bdab8aa9` | present (stock MP opens it) |

A hit in a `core_ui` / MP chunk predicts the probe; a hit only in `cp_*` / `zm_*` chunks predicts nothing
drawn. `ljcarve.py --names` resolved names found as strings in the GSC dump, and all of these are, so the
plain name may already appear in the decompiled Lua.

**Decision table** (probe stages 9–10):

| host sees | joiner sees (`gf_hud_all 1`) | meaning | next |
|---|---|---|---|
| box + bar / number | yes | a real HUD element for everyone | panel background + highlight bar behind the menu; a round-timer bar; numbers anywhere |
| yes | no | host-only | still a host panel; joiner reach needs a different element |
| nothing, no crash, `o:1` | — | widget missing from MP, or event path ignored | run the **client-local** form in `gunfight_menu_c` (`openluielem( 0, hash( "LUIelemBar" ), 0 )` + `function_bcc2134a`): draws ⇒ widget ships, server path is the problem; blank ⇒ not in MP |
| crash | — | read `crash_reports/*.zip` `info.json` first | [crash-decode](crash-decode.md) |

## 2. Ready now — stock MP call shapes (probe group S)

### 2a. Full-screen colour, and a veil the HUD draws over — `lui::screen_flash` / `lui::screen_fade`

```gsc
player thread lui::screen_flash( 0.15, 0.8, 0.6, 0.55, ( 1, 0, 0 ) );          // in, hold, out, alpha, RGB
player lui::screen_fade( 0.4, 0.45, 0, ( 0, 0, 0 ), 0, "default", 1 );          // up to 45 % black, drawHUD 1
player lui::screen_fade( 0.4, 0, 0.45, ( 0, 0, 0 ), 1, "default", 1 );          // back down, close
```

- `FullScreenBlack` is registered by `lui_shared` on **both sides in every mode** (`lui_shared.gsc:147`,
  `lui_shared.csc:285`), so a vanilla joiner's client already has it; stock MP fades through it
  (`laststand.gsc:1409`, `remote_weapons.gsc:594`). Any RGB: `_screen_fade` only special-cases the strings
  `"black"`/`"white"` (`:905`), a vector goes straight to `set_color`.
- 🔓 **drawHUD** is `screen_fade`'s 7th argument (`:758` → `#"drawhud"` at `:962`); stock precedent
  `zm_tungsten_end_fight.gsc:2090` fades to 0.1 white with it set. If "draw the HUD over the overlay" is
  what it means, a 40–50 % black veil is a **backdrop for the feed menu** — the world dims, the text does
  not. Probe 2 asks exactly that.
- ⚠ Fades nest: a counter (`self.var_d57eeb7f`, `:864-871`) swallows a fade-down while fade-ups
  outnumber it. Pair every fade up with one down, and remember stock laststand / killstreak fades share
  the same overlay. Stock also limits it to one fade per network frame (`:1027`).

### 2b. The lower message — `hud_message::setlowermessage( text, seconds )`

`hud_message_shared.gsc:57` → `luinotifyevent( #"hash_424b9c54c8bf7a82", 2, text, secs )`; the respawn
line (`globallogic_spawn.gsc:1419` is the exact shape); `clearlowermessage()` (`:74`) takes it down. Stock
keys live in `game.strings` (`globallogic.gsc:5042-5066`): `mp/waiting_to_spawn`, `mp/spawn_next_round`,
`mp/match_starting`, `mp/waiting_for_teams`, `mp/opponent_forfeiting_in`, … **The countdown is ours**:
"waiting to spawn 10…" as a round-change or map-switch timer, per player, reaching joiners.

### 2c. The engine announcement — `announcement( text, n, 0 )`

`globallogic_defaults.gsc:54` (`#"mp/opponent_forfeiting_in"`, 20), `globallogic.gsc:920`. Level-wide;
`clientannouncement` (retail, `exe+3cf9d60`, no stock caller) is the per-client form — untried.

### 2d. Gunfight's own "N v M" banner — `luinotifyevent( #"hash_6b67aa04e378d681", … )`

`player_killed.gsc:2556` fires `3, 2, allies_alive, axis_alive` on every death because `gunfight.gsc:45`
sets the gate (`level.var_4348a050`). The same event is an **indexed notification**: `1, 7` = no lives
left (`:2497`), `2, 1, n` = n left (`:2518`), `2, 6, loadoutindex` (`globallogic_ui.gsc:589`), 13–21 in
dem / fireteam. Numbers are free: a "4 v 4" at round start costs one call.

### 2e. The EMP overlay — `openluimenu( "EmpRebootIndicator" )` + `endtime` / `starttime`

`empgrenade.gsc:151-153`, closed by name (`:214-221`). A timed full-screen effect with a progress; EMP
themed, so a flourish rather than a panel.

### 2f. World markers — progress rings, per-player, on an entity

`objective_setprogress( id, frac )` (`sd.gsc:918`, `gunfight.gsc:1004`); `objective_setinvisibletoall` +
`objective_setvisibletoplayer( id, player )` (`spy_skill.gsc:1777-1784`, `ctf.gsc:448`) — **a marker only
one player sees**; `objective_onentity( id, ent )` (`prop.gsc:4646`) — a marker that follows a player;
ids from `gameobjects::get_next_obj_id()` (`gameobjects_shared.gsc:5938`). ⚠ The objective *catalogue*
(`#"escort_goal"` and friends) is an asset type the dump does not carry; use only names seen at stock
call sites.

### 2g. HUD switches

`setclientuivisibilityflag( "hud_visible" | "weapon_hud_visible" | "radar_client" | "killcam_nemesis", 0|1 )`
(18 / 15 / 6 / 6 stock uses), `setclienthudhardcore( 0|1 )`, `setclientminiscoreboardhide( 0|1 )`
(`zm_player.gsc:746-747`; engine builtins). Stock resets `hud_visible` on connect and spawn
(`player_connect.gsc:92`, `globallogic.gsc:2871`), so nothing strands. Uses: a clean screen while the menu
is open, a *hardcore HUD* toggle, a caster/recording mode.

## 3. No MP stock caller — retail behaviour unknown (probe group U)

- **`printtoprightln( text, rgb )`** — type 0 (retail) in the *server* table, type 1 in the client one;
  all 51 stock uses are debug. Only ever called in the **pregame lobby** ([pregame-routes](pregame-routes.md)
  P7), where `iprintln` did not render either, so the lobby null says nothing about a match. If it draws,
  it is a fourth free-text region (top right, coloured).
- **`setclientcgobjectivetext( text )`** — the per-client objective text (`globallogic_ui.gsc:246-275`).
  Stock passes localized keys and `""`; Gunfight sets none. Where Cold War shows it (scoreboard header?
  pause menu?) is the first question; whether it takes plain text (probe 20) the second.
- **`HudElementTimer`** via `lui::timer( secs, endon, x, y, height )` (`lui_shared.gsc:365`) and
  **`MPHintText`** (`mp_common/util.gsc:924-934`) — both were already on [lui-elems](lui-elems.md)'s
  untried list; the probe runs them with stock keys first.
- 🔓 **`TempDialog`** (`ai/systems/face.gsc:233-272`, `_temp_dialog`). Stock opens it by name, finds it
  again with `getluimenu( "TempDialog" )`, and writes **`self.propername + ": " + str_line`** into
  `#"dialogtext"` and plain literals (`"TEMP VO"`, `"MISSING VO SOUND"`) into `#"title"`; `:282` passes
  `"script id: " + … + " sound alias: " + …`. Runtime strings are its designed input, so a missing
  localize key cannot happen. Unknown: whether the menu ships in MP (face.gsc is core, but temp VO is a
  CP/ZM concern). If it does, it is a **titled free-text box driven from host GSC** — a status panel with
  a real line, not a stock key.

## 4. How LUI data travels — the rules for doing it properly

1. **An LUI event is a write to the `script_notify` UI model.** The client twin of the lower message
   (`hud_message_shared.csc:27-41`) fires the *same* event hash by writing `script_notify.arg1..N`,
   `numArgs`, then setting `script_notify` to the event (or force-notifying it). That is one slot per
   client: two events in one frame can overwrite each other. Stock serialises accordingly — the luielem
   queue sends one entry per server frame (`lui_shared.gsc:221-235`), and fades are one per network frame
   (`:1027`). **Rule: at most one LUI event per client per frame; send luielem fields through
   `lui::function_bb6bcb89`**, which also drops unchanged values. (That the server event lands in the same
   model is inferred from the matching hashes, not traced in the exe.)
2. **Text: a hash goes in, a localized string comes out.** A plain string survives only where the widget's
   Lua uses the localize-*if-hash* helper — measured both ways: the popup renders plain text
   ([pause-menu](pause-menu.md)), `LUIelemText` dies on it ([lui-elems](lui-elems.md)). **Rule: plain text
   only into a widget stock itself feeds plain text** (`ScriptMessageDialog_Compact`: measured;
   `TempDialog`: stock precedent). Everything else takes keys from stock MP call sites. Numbers are always
   free.
3. **Never add a clientfield with vanilla joiners present** ([game-systems](game-systems.md) §2). Use
   elements stock registers on both sides in every mode (`FullScreenBlack`, `InitialBlack`) or event-backed
   ones that register nothing (§1).
4. **`#using` only scripts the MP VM links.** Nothing in MP uses `luielembar.gsc` / `luielemcounter.gsc`,
   so importing them risks a link failure; call the builtins and `lui_shared` (which MP links), as the
   probe does.
5. **Close the stock way.** Menus: `getluimenu( name )` + `closeluimenu` (`empgrenade.gsc:214-221`) — but
   `closeluimenu` does not dismiss a *dialog* ([pause-menu](pause-menu.md), lui_probe v1). Luielems: clear
   the de-dup cache, then `closeluielem` (`lui_shared.gsc:79`), or a re-open will not resend unchanged values.
6. **Each round is a level reload** (`globallogic.gsc:2058`, [game-systems](game-systems.md) §14b): threads
   die, luielems and menus may or may not survive. Re-open per round (on `on_spawned` or the round-start
   callback), and keep durable state in dvars.

## 5. Host-only extras — client payload, joiners never see them

- **Any LUI event, any argument type, locally**: write `script_notify` from the injected `.csc` exactly as
  `hud_message_shared.csc:27` does. The same per-widget localize risk applies to plain strings.
- **`subtitleprint( lcn, ?, text )`** — retail (type 0) client builtin, 3 args, no stock caller in CW (BO4's table
  gives the same arity and nothing more), so the argument order is a guess. Untried.
- Client `iprintlnbold` exists too (type 0) — the host's own centre line from the `.csc`.

## 6. The probe — `src/hud_probe/` (built 2026-09-23, never run)

One server payload, 18 stages by default, about 4 minutes; a feed line names the stage and what to look for
every 3 s (`GF HUD <n>/<last> <name> o:<flag> - …`). `check-dump.py`: 0 fatal · `check-args.py`: 0 arity
mismatches. Stages 1–2 of `check-gsc.ps1` (compile + round-trip) still need ACTS.

```
acts gscc src\hud_probe\scripts\hud_probe.gsc -g cw -p pc -o C:\bocw\payloads\hud_probe
.\tools\strip-strhdr.ps1 -In C:\bocw\payloads\hud_probe.gscc -Out C:\bocw\payloads\hud_probe.gscc
bash tools/inject.sh hud_probe        # a private match loaded once; restart the match to link
```

| run | settings (bridge) | who | what it answers |
|---|---|---|---|
| **1** | defaults | host alone (or bots on your side — an enemy kills the round) | which stages draw, where, and whether any crashes |
| **2** | `gf_hud_all 1`, `gf_hud_from` / `gf_hud_to` = the stages run 1 passed | host + one joiner | which of them reach a vanilla joiner |
| 3 (optional, a launch you can lose) | `gf_hud_plain 1`, `gf_hud_from 19` | host alone | plain text in the lower line / objective text / MPHintText / announcement |

- The probe holds the round open (`gf_hud_hold 1` writes `timelimit 0`: `gunfight.gsc:1139` reads it live,
  `globallogic.gsc:3289` skips the limit at ≤ 0) and resumes from `gf_hud_next` after any round reload.
- **After a crash at stage k**: note k from the feed, relaunch with `gf_hud_from k+1`. The crash dump's
  `error_message` second field is the hash of the offending string; the plain strings hash to
  (`tools/crack-hash.py --hash`; control: `GF LUI 3` → `66e1ab67e305530b`, the value in the 2026-09-13
  run's crash dump): `GF plain lower message` `7db1c832b2340302` · `GF plain objective text`
  `48335b7a22de7066` · `GF plain hint text` `5ee38b8e8f2d1c28` · `GF plain announcement` `1a90a8e6636f6203`.

### Record sheet

| # | stage | look for | host: seen? where? | joiner: seen? | notes |
|---|---|---|---|---|---|
| 1 | flash | red, then blue full-screen flash | | | |
| 2 | veil | 45 % dark; HUD + feed on top? | | | |
| 3 | lower | "waiting to spawn" + 8 s count, lower centre | | | |
| 4 | announce | "opponent forfeiting in 20" (everyone) | | | |
| 5 | alive | "4 v 3" banner | | | |
| 6 | emp | EMP reboot overlay, 5 s | | | |
| 7 | marker | left icon ring fills; right icon host-only | | | |
| 8 | hudflags | HUD gone / hardcore / mini-score gone / restored | | | |
| 9 | **bar** | red box + green bar filling | | | `o:` = |
| 10 | **counter** | yellow 10 → 0 | | | `o:` = |
| 11 | topright | 3 yellow lines, top right | | | |
| 12 | objtext | "Match starting" — TAB? ESC? | | | |
| 13 | timer | countdown, upper right | | | `o:` = |
| 14 | mphint | hint box "Match starting" | | | `o:` = |
| 15 | tempdialog | "GF HUD PROBE" + "… t=<n>" | | | `o:` = |
| 16 | **mboard** | 5 icons ahead-right. A ring cursor · B "done" look · C team colour (or vanish?) · D value rings · E aim at one → its ring fills | host-only by design | | which cursor reads best? does aiming select cleanly? |
| 17 | **mlock** | 1 icon beside the crosshair: still → pinned? flick → how far it trails | host-only | | `o:` = ms per server frame |
| 18 | **musing** | an on-screen capture bar filling ~7 s + the Gunfight flag ahead | | | where on screen? any "capturing" text? |
| 19–22 | plain | only with `gf_hud_plain 1` | | | |
| 23 | **centre_nl** (`gf_hud_nl 1`) | ONE centre print with two `\n`: three stacked lines, one line, or a closed match? then one feed print with a `\n` | | | |

## 7. What each result buys the mod

| result | feature it unlocks |
|---|---|
| 9 bar draws | a **background panel and a highlight bar** behind the feed menu (the boxed look [hint-panel](hint-panel.md) said needed C++), a round-timer bar, capture / health bars |
| 10 counter draws | **numbers anywhere**: a big round clock, alive counts, a score, HP |
| 9/10 reach the joiner | all of the above as a **real HUD for everyone**, not just the host |
| 2 veil keeps the HUD on top | a dim backdrop whenever the menu is open — the feed menu becomes readable on bright maps |
| 3 / 5 / 4 draw | round-change and map-switch countdowns, "4 v 4" at round start, match-wide notices — all joiner-safe |
| 7 per-player marker hides from the joiner | markers for one player: a host-only waypoint, a per-player objective |
| 15 tempdialog draws | a **titled free-text box** from host GSC — status text that is not a stock key |
| 11 draws | a fourth free-text region, top right |
| 12 shows up somewhere | per-player objective text in the scoreboard / pause menu (with 17: free text there) |

## 8. A HUD menu made of world markers (klaze, 2026-09-23)

*"Could we create a HUD menu using world markers?"* **Yes — as a navigator, not as a text menu.** A
marker is an objective: engine state the server networks, so it reaches a vanilla joiner exactly as far as
the visibility calls allow (derived, [overtime-zone](overtime-zone.md) §5; the `#"escort_goal"` icon is
measured rendering, [racing](racing.md) run 2). What one can carry, every lever a stock call:

| lever | what it changes | stock precedent |
|---|---|---|
| the objective **type** (`objective_add`'s 4th argument) | the icon — and the only "text": letters baked into types (`#"sd" + "_a"`, `"control_" + n`) | `sd.gsc:722`, `control.gsc:885` |
| `objective_setprogress( id, 0..1 )` | the ring around the icon | `sd.gsc:918`, `gunfight.gsc:1004` |
| `objective_setstate( id, … )` | `"active"` / `"done"` / `"empty"` / `"invisible"` — the four stock values | 12 / 10 / 1 / 11 stock uses |
| `objective_setteam( id, team )` | the owner team: colour, and possibly who sees it | spawn beacons (`objective_setteam( spawnbeacon.objectiveid, spawnbeacon.team )`) |
| `objective_setgamemodeflags( id, n )` | per-type variants; Gunfight's flag: 1 / 2 = allies / axis capture look | `gunfight.gsc:1008` → `gameobjects_shared.gsc:6048` |
| `objective_setinvisibletoall` + `objective_setvisibletoplayer` | who sees it — host-only, or one joiner | `spy_skill.gsc:1777-1784` |
| `objective_setposition`, or an entity as `objective_add`'s 5th argument | move it, or have it follow something | `spy_skill.gsc:1830` (once per server frame); `objective_add( …, self )` |
| **`objective_setplayerusing( id, player )`** + progress | that player gets the **on-screen** capture / plant bar | `sd.gsc:884` / `:918`, cleared by `objective_clearallusing` (`:952`) |

**What it cannot carry: words.** Every label on a marker comes from its objective type, an asset the dump
does not include. Usable icons are the types stock MP names: `#"escort_goal"` (measured), Gunfight's own
flag `#"hash_56c11247a60bfd3c"` (loaded in every Gunfight match), `#"headicon_dead"` (every match); the
lettered S&D / Domination / Control types are unverified in a Gunfight match.

**Three layouts, and what decides each** (probe stages 16–18):

1. **World board — the recommended one.** Place a column of icons once, ahead of the view, and leave it.
   Nothing can swim, because nothing moves; this is how VR menus stay readable. The cursor is a ring, a
   `"done"` look or a team colour (probe 16 A–C shows which reads best); rings double as value bars (D).
   Selection by the menu's keys, or **by aiming** — the icon within ~4° of the crosshair lights up (E),
   which needs no keys at all. The labels go to the centre line. Cost: turn away and the board leaves the
   screen (or clamps to its edge, depending on the type), so it re-centres when the menu opens.
2. **View-locked** — re-place an icon every server frame beside the crosshair (the stock follow rate).
   Expect it pinned while still and trailing a fast turn by at least one server frame plus snapshot
   interpolation; a joiner adds his ping. Probe 17 prints the frame length and shows the trail.
3. **The "using" bar** — the one piece of screen-space HUD objectives can give: mark a player as the
   objective's user and drive the progress, and he gets S&D's plant bar on screen (probe 18). A slider /
   countdown display, per player.

**What it would look like, if 16–18 pass:** the menu opens → up to 8 icons in a column ahead-right; the
ring walks with the cursor (or each ring shows its row's value); the centre line prints the selected row's
label and value, as today; select with the keys or by aiming; adjusting a slider shows the using bar;
closing deletes the markers and returns the ids.

⚠ **Pushback, and the costs.** A column of identical icons means nothing without the centre line naming
the row, so this upgrades the *cursor and the values*, not the text. Ids come from the 64-slot pool the
gametype and the race markers share. Markers may also land on the compass / minimap (type-dependent,
unknown). Anyone sees a marker you do not hide. **If the event-backed `LUIelemBar` / `LUIelemCounter` (§1)
draw, they beat markers for a HUD panel** — fixed on screen, no world clutter, no id pool. Markers stay
the better tool for things that belong in the world: look-to-select, per-player waypoints, a board a
joiner can see.

## 9. Subtitle text (klaze, 2026-09-23)

*"What about subtitle text?"* Three different things answer to "subtitles", and they reach different
people:

| route | text | who sees it | status |
|---|---|---|---|
| **`subtitleprint( lcn, msec, text )`** — the subtitle channel itself | free text **if** the channel prints raw; stock keys if it localizes | **host only** — a client builtin, joiners run stock CSC | 🔓 NEW · `src/subtitle_probe_c/` |
| a **voice line whose sound alias carries a subtitle** (stock plays aliases built as `… + "_subtitle_" + …`, `hashed/script/script_18723fb52cbb6224.gsc:357`) | the alias's own line — stock, localized | everyone who hears it; server-driven | untried; which MP aliases carry subtitles is not in the dump |
| **`TempDialog`** — the stock "temp VO" box a missing voice line falls back to | **runtime-built strings, by design** (`ai/systems/face.gsc:233-272`) | per player, server-driven, so joiners too — if the menu ships in MP | 🔓 probe stage 15 (§3) |

**The evidence.**

- `subtitleprint` and `flushsubtitles` exist **only in the client table** (`funcs_cw.csv`: `exe+2ab2460` /
  `exe+2ab2440`, both type 0, retail). No server builtin prints a subtitle, so **the server cannot put
  subtitle text in front of a joiner** except through a stock voice line.
- The signature: Black Ops 3's official script API (the mod tools' reference, republished as data in
  `EHDSeven/BlackOps3-Scripting-API`) documents `SubtitlePrint( localClientNum, msec, subtitle )` —
  client, *"print to the subtitle channel"*. Cold War and BO4 keep the same three arguments. There is no
  stock caller in the Cold War dump; `flushsubtitles( lcn )` is stock (`scene_shared.csc:2410`, `:2560`, on
  scene skips).
- Stock subtitle text is always a localized key (`scriptbundle/collectible/*` `"subtitle":
  "localized18#hash_…"`). The print family takes both forms — 33 stock `iprintln( #"mp/…" )` calls, and the
  menu's plain strings. What `subtitleprint` does with a plain string is the one unknown that matters:
  `LUIelemText` put a plain string through the localizer and the game died ([lui-elems](lui-elems.md)).
- Campaign keeps subtitles on screen with a HUD model, **`hudItems.subtitles.noAutoHide`**
  (`cp_common/dialog_tree.gsc:777`), written straight from script with `createuimodel( function_5c2e399f(),
  … )` + `setuimodelvalue` (`cp_common/gametypes/globallogic_ui.gsc:1445`, the create at `:1465`, the write at `:1499`), and clears them with
  `ForceClearSubtitles` (`:1628`). If the MP subtitle widget honours the same model, a subtitle becomes a
  **persistent** line instead of a timed one.

**The probe's first step is crash-safe by construction.** It passes the key's *name* as a plain string,
`"mp/match_starting"`. A localizing channel hashes it into a real key (`73938fd7959ab087`, the key that
rendered in [lui-elems](lui-elems.md)) and shows *Match starting*; a raw channel shows
*mp/match_starting*. Either way nothing unknown reaches the localizer. Only a raw result justifies the
free-text steps (`gf_sub_plain 1`), and the newline step needs `gf_sub_nl 1` on top — a raw `\n` closed the
match in the hint widget ([hint-panel](hint-panel.md)).

**What it would give, and the pushback.** A bottom-centre free-text line, independent of the feed — a
status line or toast that never scrolls the menu away, persistent if `noAutoHide` works. But it is
**host-only**, it shares its spot with real voice-line subtitles, and players who turn subtitles off may not
get it at all (the channel may follow that setting; BO4 had a `settings_defaultsubtitles` option). For
text a joiner must read, the feed, the centre line and `TempDialog` remain the routes.

**Run it** on its own launch (or after `hud_probe` in the same one: `gf_sub_delay 260`), Settings →
Subtitles **on**; build + inject lines are in `src/subtitle_probe_c/gsc.conf`, and `bash tools/inject.sh
subtitle_probe_c` knows the client pair.

| step | look for | seen? | notes |
|---|---|---|---|
| 1 keyname | bottom centre: *Match starting* (localized) or *mp/match_starting* (raw) or nothing | | |
| 2 hold | the 1-second line still up after 1 s? cleared by the flush? | | |
| 3 plain (`gf_sub_plain 1`) | *GF subtitle free text t=…* | | |
| 4 styled | colours? the long line wraps or clips — at which character? | | |
| 5 newline (`gf_sub_nl 1`) | two lines, or a closed match? | | |

**Untried — not ruled out:** which MP voice lines carry subtitles (a `globallogic_audio::leader_dialog` line
with Subtitles on is the cheap test — joiner-visible, stock text); `cg_subtitlewidthwidescreen` (a BO4 dvar)
as the width control; the subtitle widget's own UI models (grep `subtitle` in `C:\bocw\lui-source\`).

## 10. Multi-line centre text — why the Atian / MuzzMan menu has it and ours does not (2026-09-23)

klaze: *"that menu has multiple text lines in centre screen but ours only has 1."* **It is the game mode,
not a trick.** The Atian engine (and MuzzMan's copy of it — `get_menu_size_count`, `menu_drawing_function`
and `menu_drawing_secondary` are byte-identical in the two `.gscc`, `tools/gscc-inspect.py`) decides it in
two lines (`t8-atian-menu` `coldwar/scripts/core_common/menu.gsc`):

```gsc
function menu_drawing_function( txt ) { if ( sessionmodeiszombiesgame() ) self iprintlnbold( txt ); else self iprintln( txt ); }
function get_menu_size_count() { if ( sessionmodeiszombiesgame() ) return 5; else return 2; }
```

In **Zombies** each menu line is its own `iprintlnbold`, and the ZM HUD stacks them — a header plus five
rows in the centre. In **MP** the same engine gives up on the centre and pages **two** rows through the
feed, because the MP centre print shows **one** line: several `iprintlnbold` calls replace each other
(recorded here 2026-09-16, the reason for the region-2 carousel). So a video of that menu with a stacked
centre list is a Zombies video; in a Gunfight match it looks like ours.

**What has not been tried in MP: one print that carries newlines.** Stacking separate calls is measured
dead; a single `iprintlnbold( "a\nb\nc" )` may still break into lines — or fail the way a raw `\n` in a
`sethintstring` closed the match ([hint-panel](hint-panel.md)). Probe stage 23, opt-in (`gf_hud_nl 1`), on a
launch you can lose; it tries the feed the same way after. If the centre takes it, the carousel can become a
real multi-row centre list. If not, the multi-line surfaces stay the feed (~4 lines), `TempDialog` (stage 15)
and the popup ([pause-menu](pause-menu.md)).

## Not in T9 — do not re-look

- hudelem builtins (`newclienthudelem`, `newhudelem`, `settext`, hudelem `setshader`) — absent from the
  retail table; `hud_util_shared.gsc`'s builders are dev-only ([hint-panel](hint-panel.md)).
- `print3d`, `debug2dtext`, `print`, `println`, `record*` — type 1 (dev); the type-1 file I/O family crashed
  the game ([pregame-routes](pregame-routes.md)).

## Untried — not ruled out

- **The client-local `LUIelemBar`** (`gunfight_menu_c` pattern) — the disambiguator if stage 9 draws nothing.
- **`openluielem` flags** — the probe opens with 0 (the element default); stock MP's one event-backed opener
  passes 1 (`remotemissile_shared.gsc:1291`), as do `scavenger_icon` and `mp_prop_timer`. Meaning unknown.
- **`clientannouncement( player, … )`** — the per-client announcement; retail, no stock caller, argument shape
  inferred from `announcement`.
- **`luinotifyeventtospectators`** — the same events to casters and spectators (3 stock uses): a caster overlay.
- **`#"force_scoreboard"`** (`zm.gsc:3132`, `1, 1`) — force the scoreboard up; the MP HUD may ignore it.
- **`setscoreboardcolumns( … )`** (`gametype_shared.gsc:53`) — choose the scoreboard's stat columns; the
  column names live in the gametype bundle, which the dump does not carry.
- **`obituary( victim, attacker, weapon, mod )`** — a killfeed line between arbitrary entities (6 stock uses).
- **`sethintstring( key, n1, n2 )`** — numbers substituted into a localized hint (`zm_blockers.gsc:396`).
- **`self openmenu( game.menu[ #"menu_team" ] )`** (`menus.gsc:104`) — pop the team picker for a player (the
  late-join "pick a side" moment, [late-join](late-join.md)); `closeingamemenu()` closes it.
- **The other indices of `#"hash_6b67aa04e378d681"`** (1–21) — stock notification banners by number.
- `subtitleprint`, `script_notify` writes from the `.csc` (§5) — host-only.
- `InGameConfirmOverlay` (a yes/no modal with a GSC callback) and the popup's dismissal — tracked in
  [pause-menu](pause-menu.md).
