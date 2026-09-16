# The spawn system — maps, modes, what Gunfight uses, what we can use (2026-09-14)

klaze: *"mixed results — mid-round spawn points that shouldn't be used for Gunfight, players spawning on
top of each other or on the wrong side when the lobby is large; every map supports 6v6 TDM spawns; Case B
shows spawns I've never seen that look good for Gunfight on some maps. I need the complete picture."*

This is that picture, as far as the dump and the code allow, with the gaps named and a probe built to
fill them. Read with `game-systems.md §16` (the pipeline), which this supersedes where they differ.

---

## 1. How CW MP spawning works (the model)

### 1a. Map data — ONE family of spawn markers, flagged per mode

Cold War does not ship the classic per-mode classnames (`mp_tdm_spawn_allies_start`, `mp_sd_spawn_attacker`
…). Every map script that touches spawns names exactly three struct families — **`mp_spawn_point`,
`mp_spawn_point_allies`, `mp_spawn_point_axis`** (`mp_cartel.gsc:43-45`, `mp_slums_rm`, `mp_village_rm`,
`mp_miami_strike`) — and the gametypes read them with `spawning::function_d400d613( #"mp_spawn_point",
keys )`, which groups the structs by **per-mode flag keys** (`control.gsc:148`: keys like
`control_attack_add_0`). The dev spawn tool (`dev_spawn.gsc:36-70`) lists the flag vocabulary a marker can
carry:

`dm/ffa · tdm · sd · dom (+ domination_flag_a/b/c) · ctf · koth · control · kc · dem (+ attacker_a/b,
defender_a/b, overtime, remove_a/b, start_spawn) · vip · escort · bounty · dropkick · clean · ct ·
frontline · gun · infil`

**There is no `gunfight` flag.** Gunfight owns no spawn markers on any map, its own 2v2 maps included.

⚠ The dump has no map entity data, so *which* keys a given map's markers carry — and how a "team start"
marker is expressed — is not readable offline. The struct-field probe (§4) reads it live.

### 1b. Gametype side — declare the flags you want, then start-vs-scored

Each gametype declares the flags it spawns on: `spawning::addsupportedspawnpointtype( "<flag>" )` —
TDM/Gunfight/KC/Prop/Fireteam/Dropkick `"tdm"`, FFA-family `"ffa"`, S&D `"sd"`, CTF `"ctf"`, Control
`"control"`, VIP `"vip"`, Demolition its `dem_*` set, Spy `"spy"`. The engine builds its spawn lists from
the markers carrying those flags (script names for this — `addsupportedspawnpointtype`, `addspawns`,
`clear_spawn_points`, `get_spawnpoint_array`, `move_spawn_point` — live in `mp_common/gametypes/spawning.gsc`,
which the dump ships **truncated to 2 functions**, and `spawnlogic.gsc`, which it ships **empty**; the
engine builtins underneath are in `funcs_cw.csv`: `addspawnpoints`, `enablespawnpointlist`,
`disablespawnpointlist`, `clearspawnpoints`, `getbestspawnpoint`, `placespawnpoint`, `recordusedspawnpoint`,
`testspawnpoint`, `getspawnlists`, `function_77b7335`).

At spawn time, `spawning_shared.gsc onspawnplayer()` (:194) runs one of four paths, in order:

| # | path | code | when |
|---|---|---|---|
| 1 | **override** | `level.var_cda5136b` callback returns true → the callback placed the player | a gametype/mod installs it |
| 2 | **start spawn** | `usestartspawns()` → `function_77b7335( self.team, "start_spawn" )` (engine) | `level.alwaysusestartspawns` (Gunfight, S&D, VIP, Prop) or the round-start grace period in other modes |
| 3 | **scored** | `getbestspawnpoint( team, team, enemymask, player, predicted, lists )` over `level.default_spawn_lists` (`"normal"` + whatever the gametype added) — the influencer model: away from enemies, near teammates, not recently died at | when 2 returns nothing |
| 4 | **map centre** | `groundtrace` at `level.mapcenter` (`function_594e5666`) | when 3 returns nothing — **every failing player lands on the same point** |

Side switching: the engine's start-spawn side follows the team mapping (`gametype.gsc function_f2f4dfa7`
→ `util::set_team_mapping`, driven by `game.switchedsides`); the scored path flips `point_team` itself
(`:409`). So after a switch, allies spawn where axis did — by design, both paths.

### 1c. What Gunfight actually does — it is TDM's spawning, start-only

`gunfight.gsc:77-79, :99-100`: `addsupportedspawnpointtype( "tdm" )`, the **same two selector callbacks TDM,
DM, KC, Control, Dropkick and Scream register** (`function_90dee50d` / `function_c24e290c` — generic, nothing
Gunfight-specific), `level.graceperiod = 3`, **`level.alwaysusestartspawns = 1`**. So:

- **Every Gunfight spawn is a TDM *team-start* spawn** — the spots TDM players stand on at match start,
  never TDM's mid-match respawn points (as long as path 2 succeeds).
- Gunfight on a 6v6 map therefore spawns at that map's two TDM start zones. That is the whole mechanism
  behind "Gunfight loads on any map" (§16), and the "spawns I've never seen" in Case B are almost certainly
  those start zones seen at 2v2 for the first time (TDM players see them once per match, in a crowd).
- Gunfight's own maps are no different: their markers are `tdm`-flagged start points, sized for 2v2/3v3.

### 1d. What the map scripts change per mode — bounds, never spawns

Only three maps switch LAYOUT on the gametype string, and they move walls, not markers:

| map | small modes (Gunfight is one) | large modes (`koth10v10 ctf vip conf10v10 dom10v10 tdm10v10 war12v12 …`) |
|---|---|---|
| Armada `mp_black_sea` (:130-146) | delete `12v12_bounds` → **6v6 / Strike footprint** | delete `6v6_bounds`, cut the 12v12 navmesh → full ship |
| Collateral `mp_dune` (:158-180) | same → **Strike** | same → full |
| Crossroads `mp_tundra` (:50-58, :175-197) | **inverted**: only `koth sas spy prop control dm sd conf scream oic dom dropkick gun tdm clean infect` get the 5v5 boundary; `gunfight` is not in the list → **boundary hidden, FULL 12v12 map** |

Everything else is cosmetic per mode: Raid/Nuketown `dom_bounds`, Drive-In/Firebase S&D cover, Spy
stashes, Cartel's turret poles. **No map script repositions, enables or disables spawn markers by
gametype** — whether a marker is live under `gunfight` is decided entirely by its flags (`tdm`) and the
engine. So on Crossroads, Gunfight spawns on the `tdm`-flagged starts inside a map whose 5v5 boundary
has been removed — the one case where "12v12 layout" is literally true.

---

## 2. Your mixed results, mapped onto the model (hypotheses to confirm with the log)

| symptom | most likely path | why |
|---|---|---|
| **mid-round spawn points** | path 3 (scored) after path 2 came up empty; or the hybrid's respawns | Start lists are finite. If the team's `tdm` start set has fewer markers than the team has players (a 2v2 Gunfight map at 4v4; a 6v6 map at 6v6 if the set is 6 and the picker refuses reuse), the overflow players fall to the scored pool = TDM's mid-match points. ⚠ Also: a NOW-switched hybrid (`numlives=0`, mode-remnants) *respawns* mid-round — with `alwaysusestartspawns` those are still start spawns, but once `recordusedspawnpoint` has marked them used, later ones overflow. The profile fixes the respawns. |
| **on top of each other** | path 4 (map centre), or the start picker not spacing | Path 4 puts every failing player on `level.mapcenter` — a pile is its signature. If piles appear at *start* markers instead, the engine's start picker reuses a marker (the log's PILE flag + nearest-struct distance tells which). |
| **wrong side** | path 3 flipping `point_team` while path 2 does not, across a side switch; or overflow into the other team's scored region | The scored path swaps teams on `game.switchedsides`; the start path relies on the engine's team mapping. If one player overflows to path 3 in a switched round, his side and his teammates' can disagree. |
| **large lobby makes it worse** | all of the above | more players than start markers per side → more overflow. |
| **Case B spawns that look good** | path 2 working as designed | TDM start zones at 2v2. |

⚠ The spawn **guard** (`gf_spawn_guard`, default OFF) repositions players onto the *central* cluster of
`mp_spawn_point`/DOM/S&D structs — i.e. onto mid-map markers by design. If it was ever switched to AUTO or
FORCE in the app, that alone produces "mid-round spawn points" on every map it decides to guard. Check the
app's Spawns section before reading anything else into the symptoms.

---

## 3. What we can use — five mechanisms, cheapest first

| # | mechanism | what it gives | status / risk |
|---|---|---|---|
| **M1** | Stock: `tdm` starts, always | TDM's two start zones, sized for 6 per side on 6v6 maps, 2–3 per side on Gunfight maps | what runs now; overflow → paths 3/4 |
| **M2** | **Borrow another mode's start family**: `spawning::addsupportedspawnpointtype( "sd" )` (or `ctf`, `dom`, `control`, `vip`), then the dev tool's rebuild — `clear_spawn_points()` · `function_c40af6fa()` · add types · `addspawns()` (`dev_spawn.gsc:110-117`) | **S&D's attacker/defender starts are the closest thing to Gunfight spawns the game has**: two opposing sides, placed for round-based no-respawn play, 6 per side, in-bounds on every 6v6 map. CTF bases and DOM starts are the alternatives; `ffa` is the biggest pool (no sides). | Functions exist in the game's `spawning.gsc` (every gametype calls the first; the dev tool the rest) but not in the dump — `check-gsc` stage 3 will flag them and the **link behaviour of a missing name is unmeasured** → build as a *separate probe payload* first, not in the menu. Whether adding a type *after* `main()` takes without the rebuild is the first thing to read. |
| **M3** | **The pre-spawn override** `level.var_cda5136b` — a callback that places `self` and returns true (path 1) | Total control with **no teleport**: pick 2N markers per side from any family (S&D/DOM starts identified by the struct probe), hand them out round-robin, honour `game.switchedsides`. The engine's own hook; influencers and killcam see the real spawn. | Safe (a `level.*` assignment, like every other mod hook). This is what the guard should become — it currently teleports in `on_spawned`, a frame late and after the engine already chose. |
| **M4** | The existing guard (`gf_spawn_guard` 1/2): teleport onto the central cluster | fixes out-of-bounds by construction | built, never run; central = mid-map, not sides — wrong shape for Gunfight unless the cluster is split (it is, along the longer axis) |
| **M5** | Custom scored lists: `addspawnpoints( team, structs, "gf_list" )` + `spawning::add_default_spawnlist( "gf_list" )` | shapes the **overflow** pool only (path 3), e.g. keep it to the S&D areas so an overflow player still lands on the right side | engine builtins present; only matters once M2/M3 leave an overflow |

▶ **Recommendation:** measure first (§4, one session, three maps), then **M3 seeded from the S&D/DOM start
markers** as the default for every map (it needs no names the dump lacks, no teleport, and makes team size
independent of the `tdm` start count), with **M2 tried as a probe** because if it links it is a one-line
"Gunfight on S&D spawns" that keeps the engine's own scoring. M1 stays the fallback for maps where the
probe shows the `tdm` starts are fine at the size you play.

---

## 4. The probe — built 2026-09-14 (`gunfight_menu`, payload 183,078 B / 1,156 strings), never run

Three rows on the Spawns page, all read-only:

- **Spawn log - engine placements** (needs `gf_spawn_diag 1`, the default): at every spawn, *before* the
  guard moves anyone, records `r<round> <name> <team> <x,y,z> near <family>#<idx> d=<units> [PILE:<name>]`
  — the nearest map spawn struct to where the engine put the player, and a PILE flag when another living
  player is within 48u. Also printed live to the host's feed; kept in `game.` (survives rounds); the row
  replays the last 24, three per 4 s.
- **Spawn structs - fields + engine lists**: for the first two structs of `mp_spawn_point`,
  `_allies`, `_axis` (and the legacy `mp_tdm_spawn*` names, expected empty) prints which of 26 candidate
  fields are defined (`script_string`, `script_noteworthy`, `script_label`, `script_int`, `script_team`,
  `spawnflags`, `script_gametype_*`, `tdm`, `sd`, `start`, `spawn_type`, `type`, `radius`, `script_flag`,
  `script_parameters`, `classname`, `targetname`, `target`, `angles`, …) and their values; then the engine
  builtin `getspawnlists()` — the list names the engine built for this gametype.
- **Spawn report** (existing): struct counts per family + the AUTO-guard numbers.

**Run sheet (one sitting, ~15 min, bots are fine):**

| step | where | read |
|---|---|---|
| 1 | a 6v6 map (Miami/Moscow), Gunfight 2v2 | struct probe: the field schema → **which key marks a `tdm` team start** and which families the map has; `getspawnlists()` names. Spawn log: `d=` should be ~0 (players ON markers) |
| 2 | same map, Teams → 4v4 then 6v6, fill bots, play 2 rounds each | log: at what team size does `d=` jump / PILE appear / a player land far from the others (overflow → path 3), and do piles sit at the map centre (path 4) |
| 3 | a Gunfight map (Berlin Tunnel), 4v4 | the small-map start count: the first size that overflows |
| 4 | Crossroads (`mp_tundra`), 2v2 | the "12v12 layout" case: where the `tdm` starts sit with the boundary gone |
| 5 | (optional) after a side switch round | log: both teams flipped together, or one player on the wrong side (path 3 vs 2 disagreement) |

With the field schema known, step 6 is building M3 (the override, seeded from S&D/DOM starts) and the M2
probe payload. Record results in §5.

---

## 5. Results

### 2026-09-14 — Crossroads, Gunfight 2v2 (Case-B launch), host alone: **path 4 confirmed**

- Spawn log: `r2 8bit allies 0,0,0 near mp_spawn_point#252 d=1082` — the host spawned at the world
  origin, 1082u from the nearest marker; klaze: *"yes it's the combined-arms bug confirmed … it's path 4"*.
  The engine's start list AND its scored lists had nothing for `gunfight` on this map, and
  `onspawnplayer` fell through to `level.mapcenter`. Every further player lands on the same point — the
  pile. So the "combined-arms spawn bug" is not misplaced markers; it is **no markers at all** for this
  gametype in this layout, and the map-centre fallback.
- Engine lists (`getspawnlists()`): `normal fallback spl1 … spl9 start_spawn auto_normal
  air_spawn_starts hq` (15). Nothing named per mode — the mode flags select which markers *populate*
  these lists; on Crossroads/gunfight the population is empty.
- The map has ≥ 253 `mp_spawn_point` structs (index 252 exists) — plenty of designer positions to
  build from; which flags they carry is still unread (the struct probe's first batch faded before it
  could be read — fixed below).

### The fix — the pre-spawn override, built 2026-09-14 (payload 184,782 B / 1,162 strings), never run

`mod_spawn_override( predictedspawn )` installed as `level.var_cda5136b` at every `mod_apply` (and by the
Spawns-page action) whenever `gf_spawn_guard` is on; removed when it is off. Path 1 of
`spawning_shared.gsc onspawnplayer()`: return true after `self spawn( origin, angles )` and the engine
does nothing else — no teleport, no frame late, the engine's influencers/killcam see the real spawn.

- **AUTO (2) decides per spawn with the engine's own start picker**: `function_77b7335( team,
  "start_spawn" )` — the builtin stock itself calls. Defined → the engine has a start spawn for this
  player: use that one (a single call, so the point is not consumed twice) = stock behaviour on every
  good map. Undefined → the engine has nothing (Crossroads) → place on the anchors. No per-map data,
  no legacy names. (The old detector compared `mp_tdm_spawn_*_start` to objective families — names CW
  does not ship — so it read "too few starts" on every map and would have guarded all of them.)
- **FORCE (1)** = anchors on every spawn.
- Anchors = the existing `mod_spawn_build` cluster (the most central `mp_spawn_point` structs, split
  along the longer axis into two sides, shuffled per round, round-robin per side, sides follow
  `game.switchedsides`) — now shared through `mod_spawn_next_anchor()` with the legacy on_spawned
  teleport, which remains only for a spawn that happens before the hook is installed.
- The spawn log line now ends with how the spawn was decided: `engine` / `anchor` / `stock`.
- `predictedspawn` (the killcam's pre-spawn prediction) is left to stock — on a bad map that prediction
  is the map centre, cosmetic.

**Test (Crossroads, 2v2, then 4v4 with bots):** Spawns → *Spawn guard AUTO*. Expected lines: `… anchor`
with `d=` ≈ 0 (on a marker), two distinct sides, no PILE, and a `spawn guard: <name> -> team1 anchor
0/12` receipt per player. Then a good map (Miami) at 2v2: lines must read `engine`, positions unchanged
from stock — proves AUTO leaves working maps alone. Then the struct probe again (now held on screen 30 s:
centre = counts, hint row = struct #0's fields, feed = #1, #2, lists) for the flag schema, which decides
whether the anchors should be narrowed to S&D/DOM-flagged markers.

### Debug feed — the convention for every debug tool (klaze, 2026-09-14)

*"The feed can hold very long lines. Every debug tool gets an enable option that auto-prints ONE full
line with every data point needed, continuously, while the option is on."* Built (payload 191,096 B /
1,214 strings): one level thread, a 3 s tick, one line per enabled tool to the host feed, started at
match start and by every toggle, self-ending when nothing is on. Display → **Debug feed** page (the
spawn ones are mirrored on the Spawns page); app Display section carries the dvars.

| dvar | line | contents |
|---|---|---|
| `gf_census` 1 / 2 | `CENSUS LAUNCH` / `CENSUS LIVE` | gametype/map, then all 46 short-key settings |
| `gf_dbg_spawn` | `SPAWN` | round, guard mode, hook installed, anchors a+b, switched, players, then every placement this round as `name:team:how:d<units>[:PILE]` (`how` = engine / anchor / stock) |
| `gf_dbg_structs` | `STRUCTS` | `mp_spawn_point` / allies / axis counts, the first three structs' defined fields, the engine list names |
| `gf_dbg_families` | `FAMILIES` | non-zero struct family counts, legacy detector numbers, what the guard built |
| `gf_dbg_match` | `MATCH` | mode/map/method/next, round + score, team sizes + bots + budget, timer/win/cap/rot, loadout/camo/spy/cac/profile, pre-periods, spawn guard/zone, movement |

The multi-channel holds (centre + hint row) from earlier in the day are gone; the per-spawn `spawn:`
feed print stays only while `gf_dbg_spawn` is off (the SPAWN line carries it otherwise).

### 2026-09-14, later — schema read, layout confirmed, guard v1 not good enough

- **STRUCTS** (Crossroads): `mp_spawn_point=265 allies=0 axis=0 | #0 tn=mp_spawn_point ang=0,264,0 | #1 … |
  #2 …` — the markers expose **only `targetname`, `angles` and `origin`** to script; none of the 26
  candidate fields exist. The per-mode flags are engine-side, reachable only through the spawning
  script's helpers (`function_d400d613`, `get_spawnpoint_array`) — present in the game, absent from the
  dump (link-risk class, klaze has not opted in). **From script a marker is a position and a facing.**
- **FAMILIES**: `mp_spawn_point=265 | legacy starts=0 obj=265 | guard armed 7+5 sep=680`.
- **Layout**: klaze — *"despite saying Crossroads Strike it loaded the bigger non-Strike version"*.
  Exactly §1d: `mp_tundra.gsc on_game_playing` deletes `tundra_oob_clip` and the `5v5_asset_boundary`
  entities for every gametype outside its list, and `gunfight` is outside it. The lobby label comes
  from the TDM config; the map script reads `g_gametype`. No script-side way to keep Strike (no
  detours; `g_gametype` is the engine's), so under Gunfight Crossroads **is** the full map, and its
  Gunfight spawn set is empty (path 4) — the two facts go together.
- **Guard v1 result**: *"no spawn guard: we all spawned together mid-map. With spawn guard: we all
  spawned together but in a more standard location. Neither suitable."* The override placed everyone
  on markers (`spawn guard: C. Smartt -> team1 anchor 3/7`), but the anchors were one central blob cut
  at its median — sides 680u apart, i.e. one crowd.

**Guard v2 — two sides a real distance apart (built, payload 194,038 B / 1,222 strings, never run).**
With positions the only data, the sides are chosen geometrically: for four axes through the marker
centroid and three gaps around **`gf_spawn_gap`** (default 1800u; Spawns page rows 1200/1800/2400/3200,
app Spawns), take each side's nearest markers to the two ideal points `C ∓ axis·gap/2` (no marker on
both sides), score = group tightness + |separation − gap|/2, keep the best. Anchors are fresh structs
copying the marker origin with **angles turned toward the other side's centre**. `per_side` =
team size + 2 (min 6). FAMILIES shows `sep=` and `gap=`. Changing the gap from the menu rebuilds at once.

**Open:** whether the geometric pick lands on sensible ground on Crossroads (it can only choose among
designer markers, so every anchor is a valid stand — the question is whether the two groups are in a
playable relation). If not, the next lever is the link-risk one: `spawning::get_spawnpoint_array(
"mp_sd_spawn_attacker" )` etc. to take S&D's designed sides.

### Guard v2 result + Strike layout under Gunfight (2026-09-14, built 197,863 B / 1,240 strings)

- Guard v2 first cut: with gap 1200 the FAMILIES line read `sep=661` — the tightness term let the dense
  middle pull both groups together. Fixed: each side now only draws from markers at least (gap/2 − 150)
  out from the centre on its own side of the axis (hard constraint), gap variants ×1/×1.25/×1.5,
  separation weighted 1:1 with tightness. klaze: *"the teams spawned further apart … it could work,
  but it's still odd because it's the 12v12 map."*
- **`gf_strike` (default 1) — keep Crossroads' Strike layout under Gunfight.** `mp_tundra.gsc
  on_game_playing` deletes the `tundra_oob_clip` entities and the `5v5_asset_boundary` entities (by
  targetname and script_noteworthy) for any gametype outside its Strike list; it fires at
  `set_game_playing` (globallogic.gsc:4413), after `mod_apply`, and finds them **by name**. So
  `mod_layout_keep()` renames them at match start (`gf_oob_keep` / `gf_5v5_keep` — a stock idiom,
  globallogic.gsc:4243), calls `showmiscmodels( "5v5_asset_boundary" )` (main() had hidden the models
  at level_init), repeats the Strike branch's `hidemiscmodels( "turret_model" )` +
  `exploder::exploder( "fxexp_tundra_6v6" )`, sets `level.var_633063a5 = 1`. The map's 12v12 lighting
  exploder still runs (cosmetic). The kept entities' centroid + 0.85 × mean ring distance become
  `level.gf_area_center/radius`; the guard then searches only markers inside that ring, centred on it
  (falls back to all markers if < 12 inside; brush ents with a (0,0,0) origin are ignored — if fewer
  than 3 have a real origin there is no area). FAMILIES shows `area=… r=…`. Spawns page rows
  *Crossroads: Strike layout ON / full map - stock*; app Spawns. No-op on every other map.
- ⚠ Untested. Two unknowns: whether renaming defeats the map's `getentarray` lookup (expected — the
  engine field is what both read), and whether the clip entities carry usable origins for the area.

### 2026-09-15 — the flags ARE script fields (Hijacked); Strike work parked; spawn FAMILY built

- **Hijacked, STRUCTS**: `mp_spawn_point=164 | #0 tdm=1 tn=mp_spawn_point ang=0,4,0 | #1 tdm=1 … | #2 tdm=1
  …` — **the mode flag is a plain script field on the marker** (`s.tdm == 1`). Crossroads' first three read
  empty only because they carry flags the probe did not ask for (the 10v10/12v12 variants). So per-mode
  marker sets are filterable from script, no link risk. §1a is corrected by this.
- SPAWN on Hijacked, host alone, FORCE: `8bit:allies:anchor:d0`, `guard armed 6+6 sep=2511 gap=1800`.
- klaze: *"the minimap was never working on those maps on gunfight regardless of gf_strike — park the
  Strike map work. Focus on the 6v6 maps. I've yet to see any map use normal S&D spawns; let's use
  Hijacked and try to get Gunfight using the S&D spawn system."* Strike-keep stays in the tree, off.

**Built (payload 210,543 B / 1,281 strings, never run):**
- **`gf_spawn_family`** 0 none / 1 tdm / 2 **sd** / 3 dom / 4 ctf / 5 koth / 6 control / 7 dm: the guard builds
  its anchors only from markers carrying that flag field; if the markers name sides (candidates:
  `attacker`/`defender`, `sd_attacker`/`sd_defender`, `allies`/`axis`, `*_allies_start`/`*_axis_start`,
  `team`/`script_team` = allies|axis|attacker|defender|team1|team2, or a value-coded flag 2/3) the two
  sides are those markers as-is, facing each other; otherwise the geometric two-sides search runs inside
  the family. With a family set the override places **every** spawn on the anchors (AUTO's engine probe is
  skipped). Spawns page *Family: …* rows; app Spawns. FAMILIES shows `family=sd sd:40 sides 6/6` or
  `nosides->geo` or `sd:none`.
- **FLAGS debug line** (`gf_dbg_flags`, Debug feed / Spawns page / app): for ~40 candidate fields, how many
  markers carry each and a tally of the values (`tdm=102[1:90 2:6 3:6]`) — the read that says how S&D
  marks attacker/defender and how TDM marks a team start.

**Run on Hijacked:** Debug feed → *Marker flags census* + *Spawn placements* + *Spawn families*; Spawns →
*Family: S&D markers*, guard FORCE (or AUTO — a family forces anchors anyway); fill bots; restart. Read
FLAGS first (how sides are marked), then FAMILIES (`sides a/b` = the markers named them; `nosides->geo` =
they did not, and the side-field names in `mod_marker_side` need the real ones from FLAGS).

### 2026-09-15 — Hijacked FLAGS, and the side switch on the engine path

- **FLAGS n=164: `tdm=78[1:78] ctf=78[1:78] control=78[1:78] ffa=86[1:86]`** — and nothing else of the
  first 40 candidates: no `sd`, `dom`, `koth`, no side field, no start field, no value coding. So (a) the
  team-mode markers carry `tdm`/`ctf`/`control` together (the same 78) and the FFA pool is separate (86);
  (b) **S&D / Dom / Hardpoint markers are keyed by names not yet guessed** → `Family: S&D` read `sd:none`,
  guard not armed, engine spawns; (c) **TDM starts carry no flag at all** — the engine's `start_spawn`
  list is built algorithmically at match start (which is why the legacy `*_start` names never existed).
  A second candidate batch (`FLAGS2`: snd, search, sd_a/b, sd_attackers/defenders, attackers/defenders,
  demolition, domination, dom_a/b/c, hardpoint, hp, hq, oic, bounty, ct, infil, frontline, team1/2,
  spawn_type, type, script_label, script_gametype[_sd], target, radius) prints on the same tick.
- **Sides did not switch** on the engine path (klaze). The legacy start-spawn code swapped the team by
  name when `game.switchedsides` was set (`spawning.gsc getteamstartspawnname` →
  `util::function_6f4ff113`); the engine path hands `self.team` straight to the picker. **Fix (built):**
  AUTO asks the engine for the *other* team's start spawn while switched — the same swap the anchors do.
  Payload 215,697 B / 1,309 strings, never run.

### ✅ 2026-09-15 — the working recipe: Family TDM + guard (Hijacked, klaze)

*"I tried TDM Hijacked spawns and the results were very good. They switched sides and lined up well for
Gunfight."* — `gf_spawn_family 1` (the 78 `tdm=1` markers), the geometric two-sides search inside that
set (gap 1800, hard separation, facing each other), every spawn through the pre-spawn override, sides
swapped by the guard on `game.switchedsides`. No engine lists, no unguessed marker names, no per-map data.
**Now the DEFAULT: `gf_spawn_guard 2` (AUTO) + `gf_spawn_family 1` (TDM)** — payload 215,729 B / 1,309
strings. *Family: none* returns a map to the engine's own start spawns (now side-swapping too).

Still open, lower priority: which names key the S&D / Dom / Hardpoint marker sets (FLAGS2 batch built,
unread); Crossroads (full-map layout under Gunfight, parked); a human joiner on the new spawns.

### 2026-09-15 — TDM's two spawn regimes, and the pick mode

klaze: *"in real TDM the spawns are further back on the boat; after respawning I was brought closer up.
Gunfight with TDM seems to use the closer-up version — probably ideal on most maps, but I'd like to
understand and control it."* The model: **openings** = `usestartspawns()` true during the round-start
grace period → the engine's `start_spawn` list (built at match start from the `tdm` markers, no flag —
the two extremes); **respawns** = grace over → the scored path over `normal`, weighted toward teammates
and away from enemies/recent deaths → "closer up" as the team advances. Gunfight never takes the scored
path (`alwaysusestartspawns`). The TDM-family anchors sit at ±gap/2 from the centre, so they are
structurally the closer-up kind.

Controls: **Family: none** = the engine's `start_spawn` = TDM's openings exactly (side swap now applied);
**Guard gap** = the near/far continuum; **`gf_spawn_pick`** (new, default 0 near): 1 = **far ends** — on
each axis the per_side markers nearest the two outermost projections, scored tight-and-far — TDM's
openings rebuilt from markers, so it also works where the engine has none. Spawns page *Pick: near /
far ends*; app Spawns; FAMILIES shows `pick=`. Payload 217,491 B / 1,316 strings, never run.


## Human-joiner test 2026-09-15 (observations during play)

- ⚠ **"sometimes people spawn on the wrong side of the map"** (klaze, humans in the lobby). Default
  guard is AUTO (gf_spawn_guard 2): it only anchors when the engine picker returns empty, otherwise
  it lets TDM's scored selector place the player ("away from enemies" = anywhere), so with humans
  some land cross-map. Immediate lever offered: **gf_spawn_guard 1 (FORCE)** = always use the two
  fixed anchors, every player on their team's side. To disambiguate the remaining cause, need:
  whole-team-wrong (side-swap / game.switchedsides) vs some-players-wrong (engine scored spawns
  leaking through AUTO). PENDING klaze's read after trying FORCE.

## Replicating S&D match-start spawns — the mechanism (dump, 2026-09-15)

klaze: "nothing replicates normal match-start S&D spawns. that's all we need." Found how S&D spawns:
- `sd.gsc:90` = `spawning::addsupportedspawnpointtype( "sd" )` + the shared `spawning::onspawnplayer`.
  No custom selector (function_a800815 is just a planting predicate). So S&D's fixed sides come from
  the "sd" spawn set + `usestartspawns` (Gunfight already has `alwaysusestartspawns=1`).
- Gunfight instead registers `"tdm"` (`gunfight.gsc:77`) + TDM's selector callbacks (78-79), so its
  start spawns are TDM's spread ones - exactly what klaze sees.
- The start picker is the engine builtin `function_77b7335( team, "start_spawn" )` (spawning_shared:470),
  keyed to the REGISTERED type. So the lever is the registered type.
- **Per-gametype spawn ENTITIES exist by classname**: `mp_sd_spawn_attacker` / `mp_sd_spawn_defender`
  (also `mp_tdm_spawn_{allies,axis}_start`, `mp_dom_*`, `mp_ctf_*`, `mp_dm_spawn`), read via
  `getspawnpointarray(cn) = getentarray(cn, "classname")` (zm spawnlogic:317). These are SEPARATE from
  the `mp_spawn_point` struct family (whose FLAGS census found tdm/ctf/control/ffa, no sd). ⭐ **MP has
  NO `remove_unused_spawn_entities`** (only ZM deletes unused-gametype spawns), so a map's `mp_sd_*`
  bases survive a Gunfight match and can be read + used mid-match.

**Two implementation paths, chosen by measurement (gf_dbg_structs ENT line, added 2026-09-15):**
klaze 2026-09-15: "if a map doesn't have sd spawns we should use tdm spawns; however we do it now
isn't proper." The current guard builds GEOMETRIC anchors from the shared marker family (a guess) -
that is the "not proper" part. Proper = use the map's AUTHORED team start-spawn entities:

**Spawn source priority (all authored/fixed):**
1. S&D bases `mp_sd_spawn_attacker` / `mp_sd_spawn_defender` (one team per cluster; swap for sides).
2. TDM starts `mp_tdm_spawn_allies_start` / `mp_tdm_spawn_axis_start` (the REAL fixed team starts,
   not the spread `mp_tdm_spawn` respawns the geometric guard approximated).
3. Only if neither exists: the geometric fallback.

The gf_dbg_structs ENT line measures counts for sd AND tdm-start (and dom/ctf/dm) per map, so one read
decides the path per map. PENDING the ENT read on Hijacked + one other. Payload 265,887 B.

▶ **Superseded the same evening by the dump read in [[map-data]]:** the authored starts are not
entities but `mp_spawn_point` STRUCTS carrying a mode flag, `.group_index` (team) and a start flag
(field hash 0xa3c53936, ACTS alias `_human_were`), so the ENT counts will read 0 on modern maps. Built:
Family AUTO (`gf_spawn_family 8`, the new default) arms the guard with the map's authored S&D starts, else
its TDM starts; the FAMILIES line ends with a `STARTS` tally per mode. Payload 283,546 B, untested.
