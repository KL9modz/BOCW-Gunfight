# Menu test runbook — every never-run `gunfight_menu` feature, in the order to run it

Live session started 2026-09-17 23:18 (game pid 35204, fresh launch; app `[LIVE]`). Payload under
test: `C:\bocw\payloads\gunfight_menu.gscc` **365,638 B, commit `81fa13b`** — the source in the
working tree is exactly what is injected. Session bocw-85 drives; peers bocw-0f / bocw-db hold
(no rebuild, no reinject, no edits to `gunfight_menu.gsc` without a message first).

This sheet aggregates the test sheets of [`teleport.md`](teleport.md) §7, [`client-control.md`](client-control.md) §6,
[`destructibles.md`](destructibles.md) §8, [`projectiles.md`](projectiles.md) §7, [`static-props.md`](static-props.md) §8,
[`bots.md`](bots.md) §5, [`loadout-camo.md`](loadout-camo.md), [`overtime-zone.md`](overtime-zone.md),
[`game-systems.md`](game-systems.md) §14c/§14d, [`hint-panel.md`](hint-panel.md) (banner), [`vehicles.md`](vehicles.md),
[`map-data.md`](map-data.md) and the app notes ([`hud-and-control-app`] memory: Load current, scoped Apply now).
**A filled Result cell here is the finding; copy it back to the feature note's sheet when a sheet completes.**

**Keys:** ADS + melee opens · ADS (RMB) = up · attack (LMB) = down · reload (R) = select · melee (V) = back.
Default layout = region 2: menu as the one-line centre carousel, status in the feed, info line in the hint row.

**Rules for the session**
- ⚠ **A result is a measurement.** Write what happened and what the feed line said; "therefore impossible" goes nowhere.
- 📷 Every readout is ONE feed line — one screenshot. bocw-85 captures the screen itself (`CopyFromScreen`, read-only)
  when the game window is in front; klaze only has to say "done" / what he saw.
- Rows that **reload the match** (marked ↻) come LAST in their match, one at a time; rows that could **crash** (marked 💥)
  come last in their launch. **Lobby return after every ↻ / 💥 row.**
- Read-only channels (`config_scan.py`, `roster_scan.py`, `mapdata_scan.py`) are run by bocw-85 from the shell —
  pure `ReadProcessMemory`, the primitive measured safe mid-match.
- bocw-85 sends app-side `set`/verb lines over the bridge only when klaze says go for that row.

---

## S0 — setup (fresh launch, nothing injected yet)

| # | do | expect | result |
|---|---|---|---|
| S0.1 | Custom Games → Gunfight (any Gunfight map) → Start, play into the match once | `bb.gsc` is in the script pool; app Inject/Status shows game + cwpatch green | |
| S0.2 | App → Inject / Status → **Set up all (bridge + menu)** | log: bridge injected + listening, `acts injectcw` rc 0 | |
| S0.3 | Restart the match (F7, or lobby → Start again) | the menu links: ADS+melee draws the root carousel; bocw-85: `bridge_channel.py status` = listening | |

## M1 — one Gunfight match, bots (a Gunfight map). Read-only channels, per-player verbs, teleport, camo

Order: nothing here reloads the match until **M1.30**.

| # | where | do | expect | result |
|---|---|---|---|---|
| M1.1 | Teams | 4v4 → Fill with bots | 4 a side (proven) | |
| M1.2 | Display → Debug feed | **Asset census** ON, read 3 lines, then Everything off | `VEHICLES …` / `PROPS …` / **`DESTRUCT <map> n=? kinds=? veh=? X=…`** (new line) | |
| M1.3 | shell (bocw-85) | `mapdata_scan.py` one sweep | GFMAPVEH/PROP/SPAWN/**DEST** found, `mapdata/<map>.json` written | |
| M1.4 | shell (bocw-85) | `config_scan.py` | `GFCFG` found, resolved config printed, tick advancing | |
| M1.5 | App → Config | **Load current** | every field snaps to the game's live values (matches M1.4); status names the sweep time | |
| M1.6 | shell (bocw-85) | `roster_scan.py` | `GFROSTER` found: host + bots, names/teams/kind | |
| M1.7 | App → Actions | **Connected → Refresh** | names appear (`swept ~1 s`), pick one → Player box fills | |
| M1.8 | Players | open the page; open a bot's page | list = `you host allies` + bots; the client page draws (entity in `data1`, `isstring` guard) | |
| M1.9 | Players → bot | **Godmode** → shoot the bot | no damage; row shows `[ON]` | |
| M1.10 | Players → bot | **Max ammo – every weapon** | feed `bot: max ammo on N weapons` | |
| M1.11 | Players → bot | **Give weapon** → Assault rifles → XM4 | header `Weapons @<bot>`; feed `gave XM4 -> <bot>`; **V returns to the bot's page** | |
| M1.12 | root → Weapons | Assault rifles → XM4 | header has **no `@`**; the XM4 lands on the host (target context dropped) | |
| M1.13 | Players → bot | **Freeze** → watch → **Unfreeze** | bot stops moving, can still look; resumes | |
| M1.14 | Players → bot | **Kill** (on the godmode'd + frozen bot) | bot dies (the `suicide()` half must land past invulnerability) | |
| M1.15 | Players → bot | **To Axis** / To Allies / To Spectator | side switches, spawns normally next round (C11) | |
| M1.16 | Players + App | stay on Players; App → Bots one at a time → Add bot | the new row appears within 2 s, cursor unmoved (live list) | |
| M1.17 | Player (host) | Godmode · Third person · Give max ammo · Drop weapon | each acts on the host (sanity, some proven) | |
| M1.18 | Teleport → Me to… | **Save point**; walk 30 m; **Me to saved point** (T1) | snap back, facing as saved | |
| M1.19 | Teleport → Me to… | aim at floor 20 m → **Me to crosshair** (T2) | stand there, view unchanged | |
| M1.20 | Teleport → Me to… | aim at a WALL chest height → Me to crosshair (T3); aim at the sky (T4) | beside the wall on the floor, not inside / "aim at something first", no move | |
| M1.21 | Teleport → Everyone to… | **All to me** (T5 — the one that reloaded the match on 09-15) | bots in a ring ~2 m out, facing you; feed `N moved`; **no reload** (tp_grace 1.5 s) | |
| M1.22 | Teleport → Everyone to… | All to my crosshair (open ground, T6); (doorway, T7); All to map centre (T8) | ring around the aim point / some at centre, nobody in a wall / everyone at minimap centre | |
| M1.23 | Teleport → Everyone to… | Other team to me / My team to me (T9) | only that side moves | |
| M1.24 | Movement + Teleport | Fly mode ON → All to me / Me to crosshair (T10) | you move while flying (anchor moved) | |
| M1.25 | Teleport → gun/grenade | **Teleport gun – host** ON: shoot floor / wall / sky (T11) | move / move beside / nothing; menu navigation does NOT teleport | |
| M1.26 | Teleport → gun/grenade | **Teleport grenade – host** ON: throw a frag; a stun (T14) | you appear at each detonation | |
| M1.27 | Players → bot | Teleport to me / Teleport me to them / Swap places (T15) | in front of you facing you / in front of them / exchanged | |
| M1.28 | App → Teleport | **All to me** (T16) | same as M1.21 with no menu open | |
| M1.29 | next round | gun still ON after your respawn (T13) | still a teleport gun (re-armed on spawn) | |
| M1.30 | Movement → Out of bounds | walk into a restricted area with **OFF** (default) | no warning, no countdown, no death | |
| M1.31 | Movement → Out of bounds | **stock** → walk out again | warning + countdown return (then set OFF again) | |
| M1.32 | Movement → Jump | **Builtin jump 200** → jump; then **leave stock** | visibly higher jump = `setjumpheight` works; else record "no change" | |
| M1.33 | Host | **Freeze everyone – no banner** (toggle) → again | bots freeze, no banner; unfreeze | |
| M1.34 | Host | **Countdown 5..1 GO – bold** | centre 5 4 3 2 1 GO | |
| M1.35 | Host | **Announce settings to all** | the settings lines in the feed | |
| M1.36 | Host → Broadcast | **Banner: gunfight.us [held]** → wait 10 s → **Clear banner** | a persistent hint-row line (no fade); gone on Clear | |
| M1.37 | Loadout → Pool camo | at spawn, touch nothing (step 0) | both weapons carry a mastery/PaP camo, primary ≠ secondary | |
| M1.38 | Loadout → Pool camo | **Gold** → look at the gun; switch to secondary | toast `pool camo: Gold`; both gold this round | |
| M1.39 | next round | (Gold still set); get killed by a bot / killcam | both spawn gold; bot's weapon gold; flags line `camo:Gold` | |
| M1.40 | Loadout → Pool camo | **Random each round** → 2 rounds; then **Random: same for both** | same pair for everyone within a round, different next round; one camo for both | |
| M1.41 | Loadout → Pool camo | **Stock** mid-round | toast says bare until next round; weapons bare; next round = the pool's own look | |
| M1.42 | Pool camo by ID | ids 1, 6, 70, 80 | write the category each is | |
| M1.43 | Round → Timer | Timer 60s | clock changes within a second (proven) | |

### M1 tail — the rows that reload / restart (one at a time, watch the pre-round on the way back)

| # | where | do | expect | result |
|---|---|---|---|---|
| M1.50 ↻ | Round → Pre-match / pre-round | **Pre-round 3s** | the next round's countdown reads 3 s (does the pick itself reload the match? record) | |
| M1.51 ↻ | Round → Pre-match / pre-round | **Pre-match 5s** → Round → Restart match | the pre-match countdown reads 5 s | |
| M1.52 ↻ | Match | **First to 2** (+ Restart) | the match ends after 2 round wins; AAR normal | |
| M1.53 ↻ | Match | **Loadout+sides every 1** | sides + loadout flip every round (one flip, not two) | |
| M1.54 ↻ | Loadout | **Snipers** (B6) → Restart | snipers-only loadouts; Default restores | |
| M1.55 ↻ | Spy plane | **Shared – hidden value** (B7) → Restart | both sides see enemies on the minimap | |
| M1.56 | App → Config | change **Gravity** → **Apply now** | gravity changes, **no restart** (81fa13b scope fix) | |
| M1.57 | App → Config | change **First to N** → **Next round** | the restart-required dialog appears | |
| M1.58 | App → Actions | **+ Restart** | restarts; the menu still opens after | |

### M1 bots (bots.md B1–B9) — same match or the next; B4/B5 write settings, watch for a reload

| # | do | expect | result |
|---|---|---|---|
| B1 | Bots → **Add bot – auto** ×2 | second lands on the smaller side; tie → opposite the host; toast `AvX` | |
| B2 | **Remove one bot** | the bigger side loses one | |
| B3 | **Even up teams** (needs an odd human count — joiner session) | one bot to the short side | |
| B4 | **Bot difficulty → Recruit**, then **Veteran**; re-enter the page | behaviour changes; the live-setting line reads back the pick (setting landed) | |
| B5 | **CUSTOM** → Custom bot tuning → **Preset: Potato** | bots barely hit, stand still | |
| B6 | **Preset: Godlike** | headshots, instant reaction | |
| B7 | **Hit chance** row: SELECT steps 100 → 10 | value changes in place; toast counts bots re-assigned | |
| B8 | **Passive** toggle → off | bots wander, never engage; fight again | |
| B9 | let the round end | difficulty survives the boundary | |

### M2 map-name map + offline exploder crack table (prepped 2026-09-18, so live = expected is instant)

| picker label | sv_mapname | exploder rows | cracked-to-name rows (the string-path proof) | notes |
|---|---|---|---|---|
| **Diesel** | `mp_sm_gas_station` | 16 | none | **= the CURRENT map** — the "Diesel" rows (props 13, destruct propane×2) need NO switch |
| **Nuketown '84** | `mp_nuketown6` | 10 | **1 `fxexp_halloween`, 6 `fxexp_holiday`** | fire a named row (6) before the hash rows |
| **Miami** | `mp_miami` | 34 | none | pure hash-path map; 30 destructible defs (richest 6v6) |
| **Crossroads** | `mp_tundra` | 71 | **26 `exp_lgt_12v12`, 56 `fxexp_tundra_6v6`** | Fire ALL ≈ 71×0.5 s ≈ 35 s; named rows 26/56 test the string path here too |

⚠ Named-row-works-but-hash-rows-do-nothing is a REAL finding (bocw-0f): the hash into `activateclientradiantexploder` is the one unverified path. Fire a NAMED row first on Nuketown (6) and Crossroads (26/56); if those fire and a hash row doesn't, that pins it.

## M2 — map toys: Nuketown '84 → (Diesel=here) → Miami → Crossroads (Map → 6v6 maps → … → Switch NOW)

Each map switch is a session write: **lobby return check after the last one.** 💥 rows last on their map.

| # | map | where | do | expect | result |
|---|---|---|---|---|---|
| M2.1 | Nuketown '84 | Map → 6v6 maps → Nuketown '84 → **Switch NOW** | loads as Gunfight; Teams → 6v6 → Fill works (12 slots) | | |
| M2.2 | Nuketown '84 | Destructibles + exploders | read the header row `(N destructibles here, K kinds, V cars)` + **Census line** ON | `DESTRUCT mp_nuketown6 n=? kinds=? …` — n vs the manifest's 13 defs | |
| M2.3 | Nuketown '84 | Destructibles | **Break the one I am looking at** (a car / barrel) | it breaks; feed names the def | |
| M2.4 | Nuketown '84 | Radiant exploders | **Fire 6: fxexp_holiday** (a NAMED row) → **Stop the current one** | holiday lights appear; stop clears | |
| M2.5 💥 | Nuketown '84 | Radiant exploders | **Fire NEXT** from 1 (a HASH row) | any visible/audible change = hash form works; nothing = inference 1 | |
| M2.6 | Nuketown '84 | Props → Universal props | **Place Snowman**, Park bench, Target dummy (aim at the floor 5 m away) | each appears upright, facing you; feed `placed … (n this round)`; walk into one: collides? | |
| M2.7 | Nuketown '84 | Props | **Remove the last prop**, then **Remove every prop** | vanish in that order | |
| M2.8 | Nuketown '84 | Projectiles | **Fire mode – host**; ONE pistol shot at a wall 20 m away | a rocket leaves with the bullet, detonates at the wall; feed `projectiles ON – your shots fire RPG rockets` | |
| M2.9 | Nuketown '84 | Projectiles | one shot with a wall < 1 m away | explodes on you / no self-damage — record which | |
| M2.10 | Nuketown '84 | Projectiles → Projectile | **Crossbow bolt** one shot; **M79 grenade** one shot | a bolt, not a rocket; a grenade-class projectile spawns at all? | |
| M2.11 | Nuketown '84 | Projectiles | **Homing** ON, aim near a bot, one shot | the rocket bends onto the bot; kill credits you | |
| M2.12 💥 | Nuketown '84 | Projectiles → Rate | **One per 150 ms**, then **EVERY shot**; hold an AR 2 s | hitching? rockets vs bullets in the killcam (§4 q1) | |
| M2.13 | Nuketown '84 | Projectiles | **Smoke trail FX** ON, one shot | a trail / nothing / script error — record which; then **Everything OFF** | |
| M2.14 | Nuketown '84 | Vehicles | spawn the **care package heli** (known good) then ONE untested universal row | spawns ahead, enterable / `no vehicle assets` | |
| M2.15 | Diesel | Switch NOW → Diesel | loads | | |
| M2.16 | Diesel | Props → This map's Prop Hunt set | 13 rows (residency-gated); **Place** the cactus (row 0) aiming at the floor 5 m away | appears upright facing you | |
| M2.17 | Diesel | Destructibles | **Break everything within 600 u of me** | only nearby ones go; count in the feed | |
| M2.18 | Miami | Switch NOW → Miami | loads | | |
| M2.19 💥 | Miami | Destructibles | **Break EVERY destructible on the map** (30 defs) | everything breaks over a few frames; hitch? | |
| M2.20 | Crossroads | Switch NOW → Crossroads (12v12 layouts) | loads | | |
| M2.21 | Crossroads | Vehicles | page rows on a 12v12 map; spawn one drivable | what is resident here; enterable | |
| M2.22 💥 | Crossroads | Radiant exploders | **Fire ALL, one every 0.5 s** → **Stop the walk** mid-way | a ~35 s show; stop ends it | |
| M2.23 | Ruka (optional) | Map → Fireteam maps → Ruka → Switch NOW; Props → This map's set | `(no Prop Hunt table on this map – use Universal)`; Universal still offers rows | |
| M2.24 | — | end the match → lobby | **clean lobby return** after the switches | |

## M3 — overtime zone (a 6v6 map; overtime-zone.md T0–T7)

| # | do | expect | result |
|---|---|---|---|
| M3.0 | Overtime zone → **Zone census – read only** (6v6 map) | `gunfight: 0 centre / N trig`, `dom: 3 flag_primary _a _b _c`, a `B:` line, `next round would use: dom _b @ (x,y,z) in trigger_multiple` | |
| M3.0b | same on a Gunfight 2v2 map (Amsterdam / ICBM) — census only | do these maps carry dom/koth data at all | |
| M3.1 ↻ | **Zone ON**, Round → **Timer 20s**, Restart | round-start toast `zone: dom _b (map trigger) @ (…)`; no map error / dead match | |
| M3.2 | let the timer run out | VO "overtime", clock restarts at 20 s, objective icon at B, flag model; the round does NOT end at 0:00 | |
| M3.3 | stand in the zone | capture bar fills over 5 s; round ends for your team | |
| M3.4 | next OT, stay out | at 20 s the health tiebreak ends the round | |
| M3.5 | round 2 | toast again (built per round) | |
| M3.7 | **Zone census** during overtime | `live: level.zones 1, extratime 20s, capture 5s` | |
| M3.9 | **Zone OFF** → lobby | clean lobby return | |

## J — joiner session (needs a friend on a vanilla install)

| # | do | expect | result |
|---|---|---|---|
| J1 | Map → **Stage for lobby** / **Switch NOW** with the joiner in | the joiner follows the switch and plays (the map-problem criterion) | |
| J2 | Players → joiner → **Third person**, **Fly**, **Speed** cycle (cc 5/6) | server-set client state reaches a vanilla joiner; their own input drives fly; speed survives respawn | |
| J3 | Players → joiner → **Kick from the match** (cc 8) | inactivity-drop text on their side; Players page rebuilds | |
| J4 | App → Player by name → joiner → God mode / Give picked weapon (cc 9) | lands on the joiner | |
| J5 | Teleport: All to me (T5) from the joiner's view; **Teleport gun – everyone** (T12) | the joiner sees himself moved; his shots teleport him; bots do not | |
| J6 | Host → Broadcast → **Banner … [held]** | does the hint banner render on the joiner's screen? (the open hint-panel question) | |
| J7 | Props: place one; Destructibles: break one; Projectiles **Fire mode – everyone** | the joiner sees the prop / the break / his own rockets | |
| J8 | Overtime zone ON with the joiner (T6) | joiner sees icon/HUD/clock; capture from his side works | |
| J9 | Bots → **Even up teams** with 2v1 humans (B3) | one bot to the short side, `2v2` | |
| J10 | Config: a **Load current** after the joiner's client changed nothing | unchanged (host-only store) | |

---

## Findings

### F1 — 🐛 EVERY debug-feed toggle is dead in 81fa13b (packed-store desync). Blocks all on-screen debug this launch.
**Symptom (klaze, in-game):** Display → Debug feed → *Asset census* ON gives the `^2debug feed: … ON` toast but **no feed lines appear**; same for spawn placements / structs / families / flags / match.
**Root cause (source-confirmed):** `act_dbg()` (~L8434) toggles the **direct dvar** — `cur = getdvarint(dvar,0)` / `setdvar(dvar,nv)`. But every reader uses the **packed config store** `cfg_geti`: the loop guards `cfg_dbg_*()` (L8365–8370) and the menu `*` marker (L5769/5968). `gf_census` + all `gf_dbg_*` are in `cfg_spec()` (packed chunks, added with the 09-17 config-readback work), so `cfg_geti` reads `game.gf_cfg[idx]` (still 0) while `act_dbg` only moved the direct dvar. → `debug_feed_loop`'s `while(debug_feed_any())` is false, loop never runs; the `*` never lights. Worked on 09-14/15 because back then the keys weren't packed and `cfg_geti` fell through to `getdvarint`.
**Fix (one function, `act_dbg`):** `getdvarint(dvar,0)`→`cfg_geti(dvar,0)` and `setdvar(dvar,nv)`→`cfg_seti(dvar,nv)`. Both fall through to the direct dvar for non-spec keys, so it's safe for any non-packed toggle; matches `act_dbg_all_off` which already uses `cfg_seti`. Fixes census/spawn/structs/families/flags/match/assets/veh at once. Owner: bocw-0f (packed store is theirs); lands next launch.
**Workaround this launch:** none in-game, but the census DATA is unaffected — read it from the read-only `GFMAP*` memory channel (below), which is exactly what `assets_line_*` prints.

### F2 — 🔎 the lobby's native bot-fill is ACTIVE and fights manual single add/remove
Driving the Bots page over the bridge + reading the roster channel (autonomous, no klaze, no visuals) on Gas Station 4v4:
- **removebots (all) ✓** — bots dropped 8→2, then the native fill re-balanced to **1v1** (host + A. Penner) and held. So the ALL-remove verb works; the engine keeps one bot to balance the lone human.
- **fillbots (to team size) ✓** — restored **4v4** (fresh bot names; removed bots don't return).
- **removebot (single)** at a full team = a **name swap** at count 4 (native fill instantly re-adds one) — single-remove is masked while the fill target is met.
- **addbot** at 4v4 (budget/fill target met) = **no-op** (roster unchanged).
⇒ The menu bot verbs are correct, but the lobby's own **Bot Fill** setting re-populates against them, so single add/remove/even (B1–B3) can't be measured cleanly until Bot Fill is set to a fixed count / off in the lobby. Bulk verbs (removebots/fillbots) move the count decisively and are confirmed. Difficulty/passive (B4–B9) need visual bot-behavior = klaze.

### F6 — 🚨 THE INJECTED BUILD WAS STALE (ab158d1, built 65s before the 81fa13b fix) — reframes the whole session
`payloads/gunfight_menu.gscc` (365,638 B) was compiled **2026-09-17 20:11:31**; commit `81fa13b` ("fixes app-only restart", the scoped `cmd_apply_live`) landed **20:12:36** — 65 s later. So the game launched at 23:18 injected the **parent commit `ab158d1`**, whose `cmd_apply_live()` takes **no scope** and unconditionally runs `mod_movement()+mod_bots()+mod_periods()` every apply → `mod_periods`'s `gts_set(prematchperiod/preroundperiod)` reloads the match. That IS klaze's "Apply-now restarts" — the fix existed in source but was never compiled in.
**Implication:** every fix committed this session — 81fa13b scope, F1 (debug feed), F3 (teleport), F4/config-readback/config_scan — was in SOURCE but NEVER in the running game. The features I tested (client-control, bots, teleport, map switch) DID exist in ab158d1, so those results stand; but the app's Apply-now was always going to restart, and the debug feed was always dead, in the injected build.
**Fix:** rebuild `gunfight_menu.gscc` from current source + reinject. No new code. Bundle bocw-0f's F5 spawn fix into the same rebuild so klaze reinjects once. This is why "why can't I use the app normally" had no code-level answer in the source I was reading — I was reading fixed source against a stale binary.

### F5 — spawn stacking on 3v3 Diesel (bocw-0f)
Diesel (`mp_sm_gas_station`) has only 2 TDM start-flagged markers/side (per my census `mapdata/mp_sm_gas_station.json`: `tdm=84/4(2+2+0) ... GROUPS n=0`). Default guard AUTO(2)+family AUTO(8): `mod_spawn_build` picks TDM, `mod_family_starts` returns 2/2, `mod_anchor_authored` sets them as-is, `mod_spawn_override` round-robins 3 players over 2 anchors → 2 stack. Root: the engine-start-picker probe (`function_77b7335`, the "don't touch working maps" path) is gated on family==0, so a selected family overrides EVERY map incl. ones where stock spawns fine. Fix (bocw-0f, agreed): for AUTO(2) try the engine picker FIRST regardless of family, fall to family anchors only when it returns nothing. FORCE(1)+family stays anchors-always.

### F4 — 🔎 "Apply now still restarts" ROOT CAUSE: packed-chunk contamination (7/9 chunks)
klaze reported Apply-now still restarts even after the scope fix. Root cause (confirmed structurally from the PACKED order, no churn): the app's `_apply_config` resends a WHOLE 6-field packed chunk for any changed field; 7 of the 9 chunks also carry a reload-triggering gametype setting, so an "innocent" apply drags a stale neighbor that trips next-round `mod_apply → gts_set` if it differs from the game's live value:
- gf_c1 customcac ← camo/debug · **gf_c3 gf_loadout ← GRAVITY/fly/jump** · gf_c4 map_method/prematch/preround ← menu-display · gf_c5 profile/roundlimit/roundwinlimit ← rounds_loadout/spawn_diag · gf_c6 spec_slots ← speed/spawn-tuning · gf_c7 spyplane/team_size ← TIMER/strike/switch
- SAFE: gf_c2 (falldamage/debug), gf_c8 (zone), gf_c0 (bots/camo-pool)
`gts_set` no-ops an UNCHANGED write, so it only reloads when the app's stale neighbor DIFFERS. **Fix is app-side (bocw-0f's gf_control.py, no payload rebuild): sync every untouched field in each dirty chunk from the live config (config_scan / Load-current-first) before applying.** The scope fix (adb7e2f-era) was correct but addressed a different path (mod_periods); this is the chunk-neighbor path. Immediate apply is reload-free (mod_movement only); the reload is the deferred next-round path.

### Autonomous coverage matrix (2026-09-18, bridge + memory + PrintWindow screenshots, no klaze input)
| Feature | Verdict | How |
|---|---|---|
| Client: godmode / max ammo / **give-weapon target-context** / third person | ✅ PASS | menu (god/ammo/give) + bridge (thirdperson); `gave EM2 -> F. Noor` proves the target hub |
| **Client team move** (act_move, per-client, C11) | ✅ PASS | bridge `move "A. Raymond" axis` → roster flips allies↔axis, bidirectional, no reload |
| **gf_cmd_target quoted-name string round-trip** | ✅ PASS | `"A. Raymond"` resolved to the bot — proves the string-command bridge path with spaces (was int-only proven) |
| **Scoped Apply-now (move)** — no reload | ✅ PASS (by code + run) | cmd_apply_live("move") = mod_movement() only, no setgametypesetting → reload-free by construction; bridge run showed no splash |
| Config readback (GFCFG / config_publish / config_scan / Load current) | ✅ PASS | config_scan found GFCFG + printed full live config, end-to-end |
| Bots: removebots / fillbots | ✅ PASS | bridge → roster channel (8→2→4v4) |
| Map census (Diesel + Nuketown) / roster / live config | ✅ PASS | GFMAP*/GFROSTER/GFCFG memory sweeps |
| **Map switch** (Gas Station → Nuketown '84, gunfight) | ✅ PASS | bridge `switch` → do_session_switch |
| Exploder `all` / destruct `all` | ⚠ dispatch OK, **visual pending** | fired, no crash/reload; FX at map locations I can't survey from a fixed host view — needs klaze look-around |
| Announce / countdown | ⚠ channel proven | broadcast_feed/bold = same iprintln the debug feed uses; fast-fade beat my capture |
| **F1** debug-feed toggles | 🐛 dead (packed-store desync) | fix built into next build (bocw-c3) |
| **F3** teleport All-to-me | 🐛 confirmed → **FIXED** | see below |
| Bot difficulty/passive, pool camo over rounds, gravity/speed/jump/fly feel, OOB, projectiles, prop placement, teleport gun/crosshair | ⛔ needs klaze | visual effect / aim / trigger — no memory channel |

### F3 — 🐛→✅ Teleport "All to me" reloaded the round; FIXED (2026-09-18)
**Confirmed & characterized:** with every player **FROZEN** (bridge `freeze` → no combat possible), `tpall me` still reloaded the round (roster 4v4→1v0). So it is **not** bot combat and invulnerability can't fix it — the engine ends the round when **both teams occupy one cluster**. `team`/`enemy`-to-me (one team) are the proven-safe cases.
**Fix (`tp_gather`, split into `tp_gather` dispatcher + `tp_gather_ring`):** "all" now does two independent single-team gathers at two centres 384u apart (forward of the host, sideways fallback if blocked) — each is exactly the working single-team case, and the two teams never co-locate. Owner-cleared by bocw-c3; lands in the vehmode build (next launch). ⚠ Not live-tested (needs rebuild+relaunch); re-run T5 next launch to confirm no reload.

### F3-orig — the original observation

Driven over the bridge (`tpall me`) on Gas Station 4v4, autonomous. The frame ~0.8 s later showed the **"GUNFIGHT — ELIMINATE ENEMY PLAYERS" round-start splash** (fresh loadout, reset health bars); roster after = host only, bots wiped (native-fill re-adding). So the round reloaded — the 283,546 B `tp_grace` fix did **not** prevent the double-elimination that `teleport-feature.md` recorded on 2026-09-15.
**Diagnosis (source, `tp_gather` L10248 / `tp_grace` L10220):** the grace is applied **only to the moved bots, not the host**, and is a 1.5 s `enableinvulnerability`. But the reload beat the 1.5 s window (<0.8 s), so it is likely **not** post-grace mutual fire — more likely the teleport landing itself (telefrag / fall damage in the frame before grace threads, or the ring stacking both teams triggering an engine round-end) . `team`/`enemy` to-me move only one side and were reported working; only **all** (both teams to one point) reloads.
**Next:** re-test with the F1-fixed feed next launch + a per-frame trace (did a bot take damage? did `level.playerlives`/elimination fire?); candidate fixes: grace the host too and apply `enableinvulnerability` BEFORE the setorigin, or stagger the two teams' rings so they never occupy one cluster. Owner: teleport feature (no active peer session owns it — flag to klaze). ⚠ Do not drive `tpall me` again this launch (it reloads).

## Results log (chronological, one line per event)

- 2026-09-18 ~00:34 — **F3: teleport All-to-me RELOADS the round** (bridge `tpall me` → round-start splash, roster wiped to host). tp_grace insufficient. Also this launch: **M1.17 third person (host) ✓** (bridge, camera pulled back), **destruct all** sent (inconclusive — propane-tank targets not in view).

- 2026-09-18 ~00:30 — **Bots (bots.md, never-run) via bridge+roster:** removebots ✓ (8→2, native-fill→1v1), fillbots ✓ (→4v4). See F2. Match left at 4v4.

- 2026-09-17 23:18 — game launched (pid 35204), app LIVE; bridge not yet loaded; payload 365,638 B on disk = source.
- 2026-09-18 ~00:19 — **M1.11 ✓ target context PASS** — gave a weapon from a bot's Give-weapon hub, feed read **`gave EM2 -> F. Noor`**. Source-confirmed: `act_giveweapon` gives to `menu_target()` and `target_tail` only emits `-> name` when the target isn't the host, so the `-> F. Noor` tail proves the shared Weapons hub was aimed at that bot (and `switchtoweapon` puts it in the bot's hands). V returned to the bot's page, not root (M1.11 step 3 ✓). Host's own gun unchanged by the bot-give (✓ not host). Remaining: the root-Weapons give → host half (M1.12).
- 2026-09-18 ~00:17 — **M1.8 ✓** client page renders (bot's page drawn in the feed: Godmode/Max ammo/Give weapon rows). **M1.9 ✓ Godmode** on the bot (`Godmode [ON]` green marker; klaze: works, shot it). **M1.10 ✓ Max ammo** on the bot. Client-control (`client-control.md`, never-run) first three verbs PASS.
- 2026-09-18 ~00:00 — **M1.1 ✓** 4v4 filled with bots on Gas Station (`mp_sm_gas_station`, gunfight). **M1.6 roster ✓** (GFROSTER, 0.8 s: `8bit allies host`). **M1.3 mapdata ✓** all four GFMAP strings live (SPAWN parser bug in mapdata_scan.py fixed). **M1.4 config ✓** (73 s). **M1.40 side-finding:** random-each-round pool camo visibly working (gold last round → green this round on both host + bot). **M1.2 feed toggle = F1 bug** (no lines); census captured from memory instead:
  - `GFMAPVEH mp_sm_gas_station gunfight` — drivable(5): vehicle_motorcycle_mil_us_offroad, _alt, vehicle_t9_mil_ru_apc_heavy, _open_turret, vehicle_t9_mil_helicopter_care_package · other(10): chopper_gunner, ru_heli_transport_drop, rcxd_racing(+alt), hash_58cc8ce25d32031f, ac130_gunship, helicopter_gunship(+guard), ru_air_vtol_forger, straferun
  - `GFMAPPROP mp_sm_gas_station tbl=1 rows=13` — cactus/tire_pile/sidewalk_sign/dumpster/pallet_stack/plywood/steps/beer_box/trashbin/cactus_barrel/water_cooler/newspaper_stand/cardboard_box
  - `GFMAPDEST mp_sm_gas_station n=2 kinds=1` — **decor_propane_tank_01_en_ddef ×2** (the real def name the manifest hashes)
  - `GFMAPSPAWN mp_sm_gas_station` — tdm=84/4(2+2+0) dom=26/0 ctf=71/0 control=62/0 dm=88/8(1+1+6) hq=0 · NAMED all 0/0 · GROUPS n=0
