# Forge — prop placer/editor + the hint-bar lines. 2026-09-20

klaze asked for a Forge-style prop placer: a preview that follows your view and adjusts
position/rotation/scale/orientation, cycle next/last, place, and edit placed ones; plus hint-bar
control: menu-open shows controls, others who approach see a configurable line (default a welcome/
discord advert), device-correct glyphs. Built this session; **NOT run in-game yet.**

## Feasibility (all MEASURED against reference/funcs_cw.csv + existing code)
- Input: `getnormalizedmovement` (WASD vector), `getnormalizedcameramovement` (mouse delta), all
  button states (`attack/ads/use/melee/jump/stance/sprint/frag` + generic `buttonpressed`). The
  mod's own `fly_think()` is the proven template (getnormalizedmovement + view angles + jump/crouch).
- Move/ghost: `spawn("script_model")`, `setorigin`/`.origin`, `notsolid`, `setscale`, `linkto`,
  `setvisibletoplayer`/`setinvisibletoplayer`, `playerphysicstrace`. `disableweapons`/`enableweapons`
  so forge buttons don't fire the gun.
- Text surface: this retail build has NO hudelem builtins. On-screen text = `iprintln` (feed),
  `iprintlnbold` (centre, 1 line, host-only), and `sethintstring` on a per-player usable trigger
  (the "hint bar"). The menu hint trigger is `setvisibletoplayer(self)` = host-only.

## The build (gunfight_menu.gsc, forge_* functions before prop_universal)
- **Place mode** (`forge_enter` → `forge_loop`): a `notsolid` preview rides the view (`geteye +
  fwd*dist + (0,0,zoff)`), so it moves where you look. Controls (weapons disabled while active):
  W/S = distance, A/D = yaw, jump/crouch = height, sprint = faster, ADS+W/S = scale;
  **attack** = place, **melee** = next model, **use** = prev model, **frag** = exit. Menu closes on
  enter (`gfmenu.current=""`) and `menu_think` yields entirely while `forge_active`.
- **Placed props** join `level.gf_props` (undo/clear + round-boundary sweep handle them). Barrels
  (prop_master `.barrel`) get the explosive `barrel_think`.
- **Persistence:** each place appends a packed `"model;x;y;z;yaw;scale100;barrel"` string to
  `game.gf_forge[map]` (on `game`, which survives Gunfight's per-round level rebuild — NOT `level`).
  `forge_respawn_saved()` is an `on_start_gametype` callback (re-fires each round via map_restart)
  that re-places them. `forge_clear` wipes the map's layout + live props.
- **App verbs** (`cmd_forge`): `forge enter|exit|place|next|prev|clear`. Edit-placed (select/nudge/
  rotate/scale/delete by index) + app fine-control = PHASE 2.

## Hint bar
- **Menu open → controls:** `menu_render_split`'s hint line now leads with `menu_nav_hint()`
  (editable via `gf_hint_nav`, default "RMB up  LMB down  R select  V back"); the open toast uses it
  too. Answers "edit hint line for the default menu layout" + "menu up shows controls".
- **Others see (approach the host):** a SECOND per-player trigger `self.gf_others_hint`, `setvisibletoall`
  + `setinvisibletoplayer(self)` (everyone EXCEPT host). Distinct field from bocw-1c's broadcast_hint
  trigger so an app Clear won't drop it. Shows `gf_hint_others` (default
  "Welcome to ^3KL9^7's Gunfight lobby! Join us at ^4discord.gg/blackops") normally, `gf_hint_build`
  (default "^1DO NOT KILL - host is building") while forge is active. Created per host spawn
  (`forge_on_spawned` → `others_hint_show`), gated by `gf_hint_others_on` (default 1).
- **App sets the strings CHUNKED** (they exceed the 47-byte bridge slot): `gf_ho0/1/2` (≤36 chars
  each) + `cmd_hintset` arg `others|build` → concatenates into `gf_hint_others`/`gf_hint_build`.

## ⚠ Unknowns to settle in-game (report facts, not predictions)
1. **Device glyphs** (controller vs keyboard icons): `forge_key()` emits `[{+attack}]`-style bind
   tokens when `gf_hint_glyphs 1`, plain `[attack]` text (default 0) otherwise. Whether sethintstring
   RENDERS bind glyphs on this retail build is UNMEASURED — default text works; flip gf_hint_glyphs 1
   to test. If it renders literal "[{+attack}]", glyphs aren't supported on this surface.
2. **In-game feel** — the whole control loop is untested with a body (dist/scale steps, edge
   detection, the disableweapons handoff, whether the preview reads well as a ghost).
3. **forge_respawn_saved timing** — runs on on_start_gametype; if it spawns too early (level not
   ready) props may not appear on respawn — add a wait if so.
4. **"do not kill" trigger visibility** — setvisibletoall+setinvisibletoplayer(self) is the intended
   per-observer split; confirm others actually see it and the host doesn't.

## Payload
`acts gscc` THEN `tools/strip-strhdr.ps1` (the strip is mandatory — an unstripped payload garbles
model/classname literals). Side payload `C:\bocw\payloads\gunfight_menu.forge.gscc` (562,273 B,
stripped 0x8B floor 316), carries forge + props + race + vehicle-exit + panel + proj. NOT the live
slot until klaze/coordination says. Regenerate prop_master: `python tools/props-gen.py`.

## Phase 2 (not built)
In-game grab-edit of placed props (aim → nearest-to-ray pick → carry → re-drop); app fine-editor
(select by index, XYZ nudge, rotation, scale, delete); cross-match layout save/load/share via the
app (read game.gf_forge, store JSON). See [[prop-catalog-barrels]], [[teleport-feature]] (setorigin/
floor idiom), racing "saved tracks" (the save/respawn pattern).

## ⚠ GSC trap that bit forge exit TWICE — "notify kills its own notifier's thread"
`forge_exit` is called FROM inside `forge_loop`, and it did `self notify(#"gf_forge_stop")` while the
loop carried `self endon(#"gf_forge_stop")`. A notify runs its endon handlers SYNCHRONOUSLY, so the
notify terminated the very thread executing `forge_exit`, at that line — everything after it (the
weapon re-enable, unlink, preview delete, the whole restore) never ran. Symptom: exit forge and you
stay stuck — no weapon, view frozen, ghost lingering. The switchtoweapon "fix" and the forge_restore
refactor both sat AFTER the notify, so neither ever executed; each attempt looked like it made it
worse. **Fix: do the cleanup FIRST, then notify a DIFFERENT event the running thread does NOT endon**
(`#gf_forge_done`), and point the death/disconnect cleanup net's endon at that instead.
This is the identical trap the racing prototype hit 2026-09-19 (the race-over path died because the
notifier's thread carried the endon it fired). If a "stop/exit/end" handler mysteriously half-runs,
check whether it notifies an event its own thread endon's. Live build with the fix: cbfb7fe5.
