# The spawn atlas — every spawn point on every map, for every mode (2026-09-22)

klaze: *"calculate every spawn group on every map for every mode and include starting spawns and mid
match respawn points. on some maps, if theres enough spots grouped together in certain areas, we may want
to use those as our starting spots instead. so we need a clear picture of every possibility."*

Built 2026-09-22: the GSC census (`spawn_atlas_scan`), the per-map pick (`gf_sp_map`), the widened
Family AUTO, and the panel's **SPAWNS** tab. ✅ The scan has run in game (Nuketown, Miami — below).
✅ **The `O` stage ran once, 2026-09-22 22:56** — klaze's Miami scan under `gunfight_3v3` with `F7DAED9D` +
the merge-format panel: no crash (the game ran on until 00:49, no crash report), filed as a one-entry `Scans`
file, **1 objective = `gunfight_zone_center` at (-1664, -767, 110)** — the mod's own overtime zone (`gf_zone`),
0 other kept entities (Gunfight keeps none on Miami). A second mode's scan (the merge) and the scan tour have
**not** run. ▶ **Every live build since `F7DAED9D`
carries the atlas + objectives** — last checked here: **`DE1BD8E3`, 679,360 B** (2026-09-24 00:43, bocw-84's
port of the cloud branch's fun pack: 3,907 strings, 0 with the 0x8B header, every atlas tell-tale present);
before it **`2B998AD8`, 623,533 B** (2026-09-23 02:34, bocw-84's menu simplification: 3,612 strings, 0 with the 0x8B header; `spawnscan` / `spawnpick`, the `O` stage, GFSPAWN /
GFSPAWNED, `spn=` / `spv=` all present; the pick dvars are `#"gf_sp_map"` hash literals, never plain strings,
in every build). Before it `67FECA4B` (637,463 B, bocw-12: + the saved menu log GFLOG). Earlier builds: `F7DAED9D` (633,580 B,
+ the `O` records) = `gunfight_menu.safe-F7DAED9D.bak.gscc`; `3383FEEE` (631,617 B, the fixed atlas + live
spawn events) = `gunfight_menu.atlas.gscc`; `BFCCBDA6` = `gunfight_menu.safe-BFCCBDA6.bak.gscc`.

**Late 2026-09-22 (klaze: "are we missing any data or do we have every layout?" → "yes"):** scans of one map
under several modes now **merge** (§3a), the scan reads each mode's **objectives** (`O`, §2), and a **scan
tour** switches through every map under one mode by itself (§3d). klaze then asked to *"merge the controls
from advanced > spawns into our new tool"*: the spawn settings block (guard, family, side pick, gap, AUTO trip
distance, anti-stack, Crossroads Strike, diagnostics) now lives in the SPAWNS tab's side panel as **SPAWN
SETTINGS**, not in ADVANCED (§3). ⚠ The `O` stage and the tour have not run in game.

✅ **First real scan, 2026-09-22 20:38 — Nuketown '84 under `dm`, build `15B688BE`, no crash:** 493 markers, 52
BO2-named structs, 0 S&D groups, 30 engine lists, minimap frame NW (-2720, 1826) → SE (2688, -1216) =
**exactly 16:9**, north yaw 90, all 545 points inside the frame. TDM: 85 markers, **no start flag** (so under
Gunfight the engine has no starts there); CTF starts live only in the BO2 structs (`mp_ctf_spawn_*`, 19 + 19);
VIP Escort 6 + 6 starts; Control respawns 38 + 39. **The wiki picture lines up with no alignment** — every
point inside the red playable boundary, on the streets and in the houses: the minimap-frame placement is
exact on this map (§3b). `docs/data/spawns/mp_nuketown6.json`.

⚠ **First live run, 2026-09-22 — CRASH, fixed.** Build `D11C2B3A` crashed Nuketown (FFA) 4 s after the
panel's auto-scan sent `spawnscan`: error `0x91f84370` = a **string concatenation longer than 1024 chars**
(disassembled: the engine's concat at exe+0x1b75200 checks `len(a) + len(b) > 0x400`) — the ~1000-char
chunks plus the `GFSPAWN|…` header. `15B688BE` keeps every string the scan builds under 1024 (chunks ≤ 880,
list records flushed by length, free text ≤ 64; worst-case emulation: longest result 921) and guards the
same limit on GFPLAYERS (full human lobbies) and GFCFG's `trk=` (16-gate tracks). The panel's auto-scan is
now **off by default** — the first scan is a manual press. The same error explains the 09-19 Miami crash
(the map census's long name lists).
Read with [spawn-system](spawn-system.md) (the model) and [map-data](map-data.md) (the STARTS tallies).

---

## 1. Why it is read in game

The dump has **no map entity data**. `tables/data/assets/<map>.csv` lists each map's `game_map` and
`entitylist` assets **by name only** (measured on `mp_satellite`: one row each, no contents), and the map
scripts only nudge a spawn or two (`mp_village_rm.gsc:33` `spawning::move_spawn_point`). The positions
live in the map fastfiles, which nothing in this repo parses. So the census is read from script, one
map per visit, and the panel files it.

## 2. What one scan reads — `spawn_atlas_scan` (verb `spawnscan`; panel only since 2026-09-23 — bocw-84's menu simplification dropped the in-game *Spawn atlas: scan map* row)

| Record | Source | Fields |
|---|---|---|
| `H` | header | version, map, gametype, marker count, map centre, host x/y/z/yaw, switched sides, team size, spawn guard, spawn family, the spawn note (last) |
| `M` | every `mp_spawn_point` struct | index, x, y, z, yaw, `.group_index` (-1 unset), flags (1 start = field `_human_were` / hash 0xa3c53936, 2 `ishqspawn`, 4 `disabled`), m1, m2, m3 |
| `D` / `N` | the legacy-named structs (`mod_spawn_families` minus `mp_spawn_point`) | dictionary row per name, then x, y, z, yaw per struct |
| `G` / `Q` | every `spawn_group_marker` entity + its `groupname` structs | group id, side (`mod_group_side`), position, target, objective, team / then the group's points |
| `C` | the minimap frame: the two `minimap_corner` points + `getnorthyaw()` — what `compass.gsc` `setupminimap` hands `setminimap` (`function_d6cba2e9`) | x0, y0, x1, y1 (`-` when the map has no pair), north yaw, corner count |
| `L` | the engine's live lists for the loaded gametype: `getspawnlists()`, each read per team with `function_82061144( name, #"allies" / #"axis" )` (stock's own call, `script_335d0650ed05d36d.gsc` `function_b4f071cd`) | list name, side, size, members as marker indices (`@x:y:z` for a non-marker), split every 60 |
| `O` | the running mode's objectives (`atlas_objectives`): first the entities stock gametypes read by targetname — `bombzone`, `flag_primary` / `flag_secondary`, `koth_zone_center`, `control_zone_center`, `ctf_flag_pickup_trig` / `ctf_flag_zone_trig`, `gunfight_zone_center` / `gunfight_flag_neutral` — then every other entity `gameobjects::main` KEPT for this mode (a `script_gameobjectname` other than `[all_modes]`; not a script_model / brushmodel / vehicle / `spawn_group_marker`) as kind `ent`. 120 at most, a frame every 200 entities | kind, x, y, z, yaw, radius (0 = none), targetname, `script_label` (`_a` / `_b` …), `script_gameobjectname` |

⚠ **Mode-specific entities exist only in their own mode.** `gameobjects::main` (`gameobjects_shared.gsc:583`)
deletes at load every entity whose `script_gameobjectname` does not name the running mode, so a scan under
`dm` has no bomb sites and no `spawn_group_marker`s; the `mp_spawn_point` **structs** survive in every mode.
Hence one scan per mode, merged (§3a). `classname` is compared as a **string** (the form this file already
uses and measured — a hash literal would be a string / hash compare).

**The mode bits are the engine's whole vocabulary** — the fields `function_82ca1565`
(`script_44b0b8420eabacad.gsc:306`) tests, in its order, with its test (`isdefined && value`):
- **m1** (25): base ffa sd ctf domination demolition gg tdm infiltration control uplink kc hardpoint frontline ct escort bounty fireteam vip war dropkick spy + three unresolved (`var_3cb82e5e` `var_d8e690f8` `var_3d72e6da`)
- **m2** (22): DOM flags A-F (`domination_flag_a/b/c`, `var_99227e72`, `var_6cd325d0`, `var_991d7e64`), Demolition attacker/remove/overtime/start/defender, Control attack/defend add/remove A/B (`registerlast_mapshouldstun` = the dump's alias for control_defend_add_a's hash)
- **m3** (15): `koth_zone_0-9` and `war_zone_0-4` (`function_fac242d0`'s numbered lists)

A marker with a mode bit **and** the start flag is where that mode OPENS (the engine's `start_spawn`);
with the bit and **no** start flag it is the mode's MID-MATCH respawn pool (`auto_normal`). Which
gametypes use which flag (from `addsupportedspawnpointtype`): **tdm** = TDM, Kill Confirmed, **Gunfight**,
Prop Hunt, Dropkick, Fireteam, clean · **ffa** = FFA, Gun Game, Infected, OITC, Sticks & Stones, Scream ·
sd · ctf · dom · koth (field `hardpoint`) · control · dem · war · vip · spy · fireteam · dropkick.

**Wire.** `level.gf_atlas[ i ] = "GFSPAWN|<stamp>|<map>|<i>|<n>|<records>|END"`: records `;`-separated,
fields `,`-separated, ≤ ~1000 chars a chunk, `<stamp>` = `getrealtime()` at the scan's start (ties one
scan's chunks together). Held for the level; the marker is assembled at runtime (no decoy in the payload).
One frame per 12 markers / per group / per list (the `0x91f84370` lesson: no map-sized walk in one VM
resumption).

## 3. The panel — SPAWNS tab

- **Collect**: `GameLink.RequestAtlas` → the tick calls `MemoryScanner.CollectAll("GFSPAWN")` (every copy
  of every chunk in the pool region; the whole exe range from the 3rd try) → `SpawnAtlas.FromHits` takes
  the newest scan stamped at/after the request's state tick, for that map, with ALL chunks present. 30 s,
  then a toast (manual scans only).
- **Auto-scan** (opt-in, off by default since the 09-22 crash): a map with no atlas is scanned 8 s after it
  first shows in GFSTATE (toggle in the tab).
- **Files**: `docs/data/spawns/<map>.json` + `picks.json` on the dev box (the bundle ships them in
  `spawns\`); a friend's bundle writes `%LOCALAPPDATA%\GfPanel\spawns`.
- **Shows**: the plot (every point, per-mode layers, S&D groups, named structs, engine lists, HQ; filled =
  start, hollow = respawn, tick = facing; wheel zoom / drag / double-click fit / turn 90°); every mode's
  starts and respawns per side; the named / group / engine-list rows; **dense areas** (greedy: the point
  with most neighbours inside radius + height band becomes an area, repeat; knobs in the tab); and the
  **start layouts**: each mode's authored starts, the BO2 war starts, every S&D group pair, the engine's
  own start list, and the best pairs of dense areas — ranked (covers the team size first, then separation).
  An area layout halos exactly the points the game will arm (it re-selects by radius).
- **What runs**: live `spn=` from GFSTATE (also the sidebar's *Spawns* row), the no-pick prediction (the
  C# mirror of the GSC chain), and this map's pick. ⚠ The engine lists are the lists of the mode the scan ran
  under: a scan under `dm` reads dm's `start_spawn` (Nuketown: 1 + 1), not Gunfight's. So the prediction
  (and the "engine start list" layout) use the live lists only for a tdm-type scan (gunfight / tdm / kc /
  prop / dropkick / fireteam) and otherwise rebuild Gunfight's start list from the markers the way the engine
  does — tdm flag + start flag, by `.group_index`.
- **Dense-area radius**: 0 = auto, 6 % of the points' spread, 200–800 (Nuketown: 273 → 22 areas; the old
  fixed 650 put 188 of 545 points in one area).
- **SPAWN SETTINGS** (moved from ADVANCED, 2026-09-22 late): the `gf_spawn_*` / `gf_strike` block sits under
  *WHAT RUNS ON THIS MAP* — the same schema rows (`Schema.cs`, section tab `"spawns"`), pins, readback and
  apply path as every other block; search hits say *SPAWNS ›*. A guard / family change re-tags the AUTO layout
  as soon as GFCFG reads it back. The spawn *debug-feed* toggles (`gf_dbg_spawn` / `_structs` / `_families` /
  `_flags`) stay in ADVANCED → DEBUG FEED.

## 3a. One map, many modes — the merge

`SpawnAtlasStore.Save` no longer overwrites: `SpawnAtlas.Merge( old, new )` keeps one `ModeScan` per mode
(`Scans`: that scan's lists, S&D groups + points, objectives, host, note, team size / guard / family). A
rescan of a mode replaces its entry; **Gunfight and Gunfight 3v3 share one slot** (`SameMode`: one gametype
script, settings apart). The markers / named structs / minimap frame come from the newest scan (the same
structs in every mode). `Flatten()` fills the top-level views on load: groups (ids shifted past the earlier
scans' so two modes never collide; each tagged with its mode) and objectives = the union; the engine lists
(and the gametype the prediction reads) = the Gunfight scan's, else a tdm-type mode's, else the latest.
Files written before the merge (one scan, no `Scans`) load unchanged and become the first entry on the next
save. The status line reads *scanned under dm, sd, gunfight …*. Offline test (scratchpad `mergetest`, the real
Nuketown file + synthetic S&D / Gunfight / 3v3 chunks in the wire format): 22 / 22 checks.

**Objectives on the plot** (toggle *objectives*, on by default): ★ per objective, labelled A / B, HP1,
CTL, flag, GF; a ring at its radius when it has one; small squares = the mode's other kept entities; hover =
kind, mode, position, radius, targetname. The side list gains *objectives under <mode>* rows.

## 3d. The scan tour — every map, one mode, unattended

SPAWNS → *SCAN TOUR* (side panel, last block): mode + map set (*maps not yet scanned in this mode* /
every MP map (the 28 + 8 in `Catalog`) / 6v6 / Gunfight maps) → **START THE TOUR** asks once, then per map:
Switch NOW (`gf_cmd_map` / `gf_cmd_gametype`, the pick pre-pushed like the MAPS tab does) → wait until
GFSTATE reports that map under that mode in prematch / playing (150 s, else skipped) → 8 s → `spawnscan` →
the atlas filed (40 s) → next. The map already running goes first; two maps in a row that never report halt
the tour (payload gone / load stuck); *when done, switch back* returns to the map + mode it started on.
Auto-scan stands down while it runs. A map-switch command is **one-shot** in `GameLink.Send` (no retry: its
ack dies with the level, and a retry would switch again). ~1 min a map → ~40 min for all 36 under one mode.
Run it once per mode that matters (Gunfight first, then S&D for the groups + bomb sites, then Domination /
Hardpoint / Control / CTF for their objectives and zone respawn sets).

## 3c. Live spawns — where everyone actually spawns (klaze: "do i add bots and the visualizer will show what spots they use?")

- **GSC** (`spawnev_add`, called from `spawn_log_record` on every spawn while `gf_spawn_diag` is on — the
  default): one event per spawn, kept in `game.` for the match (the last 96):
  `round,order,entnum,team(1/2/0),x,y,z,yaw,how(e engine / a anchor / s stock),slot(k/n on the mod's anchors,
  else -),bot,name` — `order` = 1 for the first player to spawn this round. `spawnev_publish` republishes at most
  once a second after a spawn: `GFSPAWNED|<stamp>|<map>|<i>|<n>|V,<match>,<ver>;E,…|END` (chunks via
  `atlas_add`, ≤ 880). GFSTATE carries `spv=<match>.<ver>`.
- **Panel**: when `spv=` moves, the tick collects the chunks (`MemoryScanner.CollectAll("GFSPAWNED")`, retried
  until the version read matches the one announced — the publisher trails a spawn by up to 1 s). The SPAWNS
  plot, on the running map: this round's spawns as numbered dots in spawn order, team coloured, facing ticks;
  a white ring (and ×N) on each scanned spot that was used (nearest within 48u across / 72u up); *this match* /
  *every round seen* add earlier rounds as faded dots — a heat map of the spots. Hover a dot: player, round,
  how placed (engine picker / anchors slot k of n / stock), the spot. *spot numbers* draws every marker's index
  (the same index the in-game feed prints as `near mp_spawn_point#N`).
- **How the mod orders its own anchors**: each side's anchor list is shuffled at every round start and handed
  out in spawn order — slot 1 to the first player of that side, slot 2 to the next. The engine's start picker
  (maps with their own Gunfight starts) has no order script can read; the overlay shows its results.
- Verified offline: the real parser on synthetic chunks in the wire format, the real plot rendered off-screen
  (numbered round, faded earlier rounds, rings, numbers). Not yet run in game.

## 3b. The map pictures (klaze: "are you able to digitize them on the maps?")

- **The art**: the Call of Duty wiki hosts the in-game tactical map of every Cold War map as
  `<Map> MiniMap BOCW.png` (3840×2160 full-screen captures, uploaded 2020 by one editor; all 36 MP maps,
  the Strike and 12v12 layouts of Armada / Collateral / Crossroads separately, Moscow old + new, the 5
  Fireteam maps). The same art sites like gamesatlas crop and watermark. `Game/MapArt.cs` maps each map id
  to its file(s), the layout gunfight loads first; the URL is derived from the file name (MediaWiki's md5
  upload path, `scale-to-width-down/1920`, `format=original` = PNG — the default is WebP, which WPF cannot
  decode). `MapArtCache` downloads once into `%LOCALAPPDATA%\GfPanel\mapart` (never the repo or the bundle).
  *Your picture…* uses any image instead (copied into the same folder).
- **Placement**: on the game's minimap frame — the scan's `C` record, sorted into north-west / south-east
  exactly as `function_d6cba2e9` does (`SpawnAtlas.Frame()`) — and the plot turns **north up** like the
  in-game map. ✅ **MEASURED exact on Nuketown '84** (2026-09-22: its frame is exactly 16:9 like the captures,
  and every scanned point lands on the walkable areas with no alignment). Other maps unverified; Armada's two
  layouts share one corner pair (the 6v6 / 12v12 switch is client-side, `mp_black_sea.csc`), so at least one
  of its two pictures needs aligning. **Align** (drag = move, Ctrl+wheel = scale, Shift+wheel = turn, Alt = fine) fixes
  a picture once; it is saved per map + picture in `docs/data/spawns/art-align.json`.
- **Export**: *Save image* (this view, 2x) and *Save all maps* (every scanned map: its picture, every spawn
  point, its pick else AUTO highlighted, a caption with the legend) into `Pictures\Gunfight spawn maps`;
  `GfPanel.exe --export-spawns` does the second and exits.

## 4. The per-map pick — the GSC contract

- `gf_sp_map` = `"<map>:<kind>"` — kind **1-7** = that family's authored starts (the `gf_spawn_family`
  numbering, via `mod_family_starts`: flagged starts + BO2-named starts + S&D groups), **9** = AREA,
  **10** = stock (the hook steps aside). `gf_sp_a` / `gf_sp_b` = `"x,y,z,r,zr"` for AREA: every point of
  the pick pool (markers + named + sided S&D group points, de-duplicated) within 2D radius `r` and height
  band `zr` of the centre; anchors face the other area's centre.
- **Any other map ignores it** (the map token must equal `sv_mapname`), so one map's pick never leaks.
- It **wins over** `gf_spawn_family` / AUTO and **forces the anchors** (`mod_spawn_override` skips the
  engine start picker while `level.gf_sp_active`). Needs the spawn guard on (AUTO or FORCE).
- A pick that arms nothing on a side falls through to the normal chain and says why in `spn=`
  (`pick:area EMPTY 0/4 > …`).
- Verb `spawnpick apply|clear` re-reads the dvars and rebuilds now: the **next** spawn uses it.
- **When it lands**: the panel pushes a map's pick when that map first shows (from the next round, or
  *USE + RESTART ROUND*), before a panel *Switch NOW* to it (round 1 included), and for a panel-staged
  map at the end of the match. ⚠ Round 1 of a map launched from the lobby UI runs AUTO.
- Bridge lines ≤ 41 bytes (limit 47).

## 5. Family AUTO, widened (every round)

Old: S&D starts if both sides have 2+, else TDM. New: the first family whose authored starts **cover the
team size** on both sides, in the order **S&D, TDM, CTF, Domination, Control, Hardpoint**; none does →
the one with the most a side if that is 2+ (the old rule), else TDM (geometric). Why: Satellite's census
(2026-09-19) reads **TDM 100 markers / 0 starts but CTF 6 + 6** — a family the old chain never looked at.
Guard AUTO still asks the engine's start picker first on every spawn (a map whose stock starts exist keeps
them, the F5 rule); the family chain only decides where the engine has none.

## 6. Test sheet (klaze — nothing above has run)

1. Inject the live slot (`15B688BE`), any map, panel open → press **SCAN THE MAP RUNNING NOW** → within a
   few seconds: toast *Spawn atlas: <map> filed*, `docs/data/spawns/<map>.json` appears, the SPAWNS tab plots
   it. Sidebar *Spawns* shows `spn=`. ✗ *no complete spawn scan … in 30 s* → report it with the GFSTATE say=
   line. Only after a clean manual scan, turn *auto-scan new maps* on.
2. **Satellite**: modes table should show CTF 6 + 6 starts, TDM starts —; *WITH NO PICK* should now read
   the CTF starts (the widened AUTO). Play a round: `spn=` should read `ctf:… starts 6/6 … a8`.
3. Pick a *Dense areas* layout → **USE + RESTART ROUND** → both teams open inside the two rings;
   `spn=pick:area n/m`.
4. Switch to another map → that map runs its own AUTO (`spn=` has no `pick:`).
5. Back on the first map → the pick comes back (from the next round); **Clear pick** → AUTO.
6. The atlas file has `Lists` (start_spawn / auto_normal …) — the `function_82061144` read worked.
7. **The picture**: after the scan the map art appears under the points, north up. ✅ Nuketown: exact with no
   alignment. On other maps, if the points miss the walkable areas, **Align** once and note which way it was off.
8. **Live spawns**: fill the lobby with bots, play or restart a round → the SPAWNS map shows every spawn
   numbered 1..N in spawn order with the used spots ringed; *this match* stacks the rounds.
9. **Objectives** (payload `F7DAED9D` or later — the live `DE1BD8E3` carries it; ✅ the stage itself ran clean
   once, Miami under Gunfight 3v3 → the overtime-zone centre): switch a map to **S&D**, scan → ★ A and B on the bomb sites, the S&D
   groups appear, the status line reads *scanned under <earlier>, sd*; the earlier mode's data is still there.
   ✗ a crash on the scan → decode it ([crash-decode](crash-decode.md)) before anything else.
10. **Scan tour**: from a Gunfight match, mode Gunfight, *maps not yet scanned* → it walks the maps and fills
   the map list; watch the first two switches, then leave it. Note any map it skips and why.
11. **SPAWN SETTINGS** in the SPAWNS tab: change *Spawn family* → the AUTO tag in START LAYOUTS moves within a
   few seconds (after the GFCFG readback). ADVANCED no longer has a SPAWNS block.

## 7. Untried — not ruled out

- Reading positions **offline** from the map fastfiles (`game_map` / `entitylist`) — needs a T9 fastfile
  parser; would give the whole atlas without visiting a map.
- A floor plan drawn from the game itself instead of the wiki art: a grid of downward `bullettrace`s over
  the minimap frame (height + `surfacetype` per cell) plus `ispointonnavmesh` (walkable) — exact alignment
  by construction, a few seconds of scanning per map, the same chunk channel.
- A GSC-baked per-map pick table (a `spawn-gen` block like `props-gen`) so round 1 of a lobby launch uses
  the pick too.
- Re-placing everyone when a pick lands during the prematch countdown.
- Objectives of modes nobody scans — a mode's objectives exist only in its own scan (§2); the tour collects
  them one mode at a time.
- Strike / 12v12 variants as separate scans (`tdm10v10` is its own slot today; whether its bounds change the
  lists is unmeasured).
