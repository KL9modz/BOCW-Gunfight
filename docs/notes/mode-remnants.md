# Mode remnants after a session switch — what the switch moves, what it leaves behind

**Measured 2026-09-13 (klaze), three facts:**

1. **Switch NOW with the `switchmap_load` sequence changes the mode fully in-match.** TDM → Gunfight on
   the 02:11 build (`switchmap_load` → wait ≤25 s for `#"switchmap_preload_finished"` → `switchmap_switch`,
   stock ZM's sequence, `zm_common/zm_utility_zsurvival.gsc:153-155`): *"it actually changes the mode
   fully … it loaded real gunfight in match."* The `switchmap_preload` variant that stood in the code
   for a few hours today was what "seemed unstable"; it is gone ([[session-switch]] has the revert).
2. **The lobby's own game options do NOT follow.** After the switch (and after the match ends) the lobby
   header reads *Gunfight* with the Gunfight description, but **MODE: TEAM DEATHMATCH** and TDM's
   rules (screenshot `C:\bocw\Screenshot 2026-09-13 020406.png`). The switch moves the *session* —
   map, gametype, and the match pulls the new mode's settings — not the lobby's custom-game config.
3. ~~**A match launched FROM that lobby is a hybrid**: `g_gametype = gunfight` (the session's) on TDM's
   settings blob (the lobby config's) — "says gunfight but loads TDM rules and custom classes".~~
   **RETRACTED 2026-09-14 for lobby launches — column B == column A, a lobby launch rebuilds the blob
   from the session gametype's preset. The hybrid exists only after an in-match Switch NOW (LS6).**

Fact 3 has one fully-explained symptom and a measured fix; the rest is a census away.

## Why "custom classes" — the gate, from the dump

`scripts/mp_common/gametypes/gunfight.gsc:102-109`, in `onstartgametype()`:

```gsc
if ( level.disablecustomcac !== 1 )
{
    setgametypesetting( #"disableclassselection", 0 );
    level.disableclassselection = 0;
    setgametypesetting( #"perksenabled", 1 );
    level.perksenabled = 1;
    level.givecustomloadout = undefined;      // no fixed loadouts
}
```

Gunfight has a built-in **custom-classes variant**, gated on one gametype setting, `disableCustomCAC` — the
rules-menu row *Custom Classes* (`scriptbundle/gamesettings/disable_cac.json`, `setting: disableCustomCAC`,
enabled/disabled). The real Gunfight mode's blob has it at 1; TDM's does not; a hybrid launch runs the
custom-class branch. (`disableClassSelection` follows: the custom branch forces it to 0, so the base mode
has it at 1 — inferred, not read from a Gunfight blob.)

**Where it is fixable — the order in `globallogic.gsc:5530-5537`**, `callback_startgametype()`:

| step | call | what it does |
|---|---|---|
| 1 | `function_b9b7618()` | copies every gametype setting into `level.*` — `level.disablecustomcac` at `:5159`, `level.disableclassselection` at `:5160` |
| 2 | `callback::callback( #"on_start_gametype" )` | **`mod_apply` runs here** |
| 3 | `[[ level.onstartgametype ]]()` | Gunfight's gate above reads `level.disablecustomcac` |

So `mod_apply` can write both the setting and the level var between the read and the gate, and Gunfight
takes its fixed-loadout branch. Built 2026-09-13 in `gunfight_menu.gsc` (02:24 build):

- `gf_customcac` (default 0 = real Gunfight; 1 = the *Custom Classes* row on purpose). Loadout page:
  *Custom classes OFF - Gunfight loadouts* / *Custom classes ON*.
- `mod_apply`: `disablecustomcac` / `disableclassselection` = `1 - gf_customcac`, setting AND level var.
- `mode_profile_prime( gametype )`: the same two settings written **before** `switchmap_load` on both
  the Stage and the NOW path, so they travel with the session (LS6: settings survive a switch).
- ⚠ Never run. The test is the hybrid: TDM lobby → Switch NOW to Gunfight → end match → lobby still says
  TDM options → launch. Expected on the 02:24+ build: fixed Gunfight loadouts, no class menu.

## The rest of TDM's options — measure, don't guess

Per-mode default blobs live in the LUI presets; the dump only *declares* the fields
(`ddl/mp_gametype_settings.ddl`). So: **Display → Settings census to feed** prints 9 lines of key=value
(timelimit, scorelimit, roundlimit, roundwinlimit, cumulative, roundswitch, scoreperkill, respawn
rules, numlives, maxplayers, teamcount, hardcore, spectate, customcac_off, classsel_off, perks,
attach_off, weapondrop_off, loadoutstreaks, teamchange, the three gunfight keys, capturetime, extratime,
prematch, preround, g_gametype, map) three at a time every 3 s — screenshot each batch. Run it:

- **A** in a Gunfight launched from a lobby with Gunfight selected (the real blob);
- **B** in a hybrid launch (fact 3);
- **C** right after a Switch NOW into Gunfight (fact 1, expected ≈ A).

A − B is the remnant list. Whatever differs gets baked into `mode_profile_prime` / `mod_apply` as the
Gunfight profile, with the measured values, and this note records the two columns.

## The delay on Switch NOW

Only the **first** switch of a session receives `#"switchmap_preload_finished"`; later ones sit the
full 25 s ([[session-switch]]). Stock's other sequence — the campaign's immediate one,
`cp_common/load.gsc:412-414`: `switchmap_load`, `util::wait_network_frame(1)`, `switchmap_switch` —
never waits on the notify. Built as `gf_switch_wait` (Map page: *Switch wait: 25s - proven* / *5s* /
*none - cp form, untested*), default 25 = the proven form. Flip to *none* on a second switch and see
whether the load still completes cleanly; if it does, it becomes the default.

## Where the lobby's game options live — the open layer

Fact 2 is [[lobby-setters]]' "decisive unknown" seen from the other side: `switchmap_load`'s gametype write
reaches the summary header but not the MODE line / rules, so the lobby's mode config is a **separate
structure** from the session's gametype field. `LobbySetGameType` may well behave the same (set the field,
not the config). The config itself is the custom-game DDL blob (`ddl/mp_custom_game.ddl`,
`gametypesettings`) + the LUI mode selection — the layer the glitch reconfigures ([[pregame-routes]]
"MODE/PLAYLIST reconfig"). Reachable from GSC: no (P1–P11). Reachable from the menu's assertions: yes, for
every setting the match reads — which is what the profile approach above is.

---

## 2026-09-14 — the two lobby objects, measured from both sides (klaze)

klaze walked both orderings and read the lobby after each. Five facts, all new:

| # | Observation | What it fixes in the model |
|---|---|---|
| 1 | **Case B** (TDM lobby → in-match Switch NOW to Gunfight → back to lobby): picking a *different* map in the **UI picker** and launching gives **Gunfight** on that map, every time. | **A UI map click does not re-push the config's gametype.** The session's `gunfight` survives arbitrary UI map picks. |
| 2 | Case B lobby: the **preview thumbnail says Gunfight**; the **header and the custom-game options say TDM**, and the rules pages are TDM's rows (no Gunfight rows to edit). | Thumbnail = session-driven; header / options / rules = config-driven. Same split as fact 2 above, with the thumbnail now placed on the session side. |
| 3 | **Case A** (Gunfight lobby → in-match NOW switch to an off-compat map → back to lobby): Play relaunches the off-compat map on real Gunfight cleanly, but the picker is locked — **even the currently selected, loaded map carries the red icon**. | The red icon is the *config's* compat set judging the *session's* map. Cosmetic for the host; the launch reads the session. |
| 4 | In a TDM-config lobby with an off-compat map selected, clicking **Gunfight in the mode picker also resets the map** to a Gunfight-compat one. | **The UI mode click writes both objects** (config + session map). No UI ordering yields "Gunfight config + off-compat map" — that state is the glitch's and only the glitch's. |
| 5 | TDM match → **Stage** gunfight → End Game at once → lobby **still TDM**. But TDM match → **Switch NOW** gunfight → End Game *during the ≤25 s wait* → lobby **shows Gunfight** (Case B reached without any switch happening). | **The load is asynchronous and the pair is committed to the session when it completes.** Stage and NOW call the identical `switchmap_load`; the only difference was the seconds between the call and End Game. The 2026-09-12 Stage discovery was made the NOW-interrupted way too. A stage discarded by an early End Game is not a failed stage. |

### The model, stated once

Two independent lobby objects. Our tools reach exactly one of them.

| Object | Holds | Written by | Read by |
|---|---|---|---|
| **Session descriptor** | `(map, gametype)` | UI map click (map only), UI mode click (both), **`switchmap_load` once its load completes** — Stage / Switch NOW | thumbnail, summary header's mode description, the launch (`g_gametype`, `sv_mapname`), presence |
| **Lobby mode config** (LUI/Lua) | the selected *mode object*: MODE line, header, which rules rows show, the **compat set**, the **settings blob** the launch copies | **UI mode click only** | picker gate (red icons), rules pages, custom-game options, the launch's settings |

Underneath: the pregame gametype-setting **store**, which frontend GSC can read and write and whose
writes carry into the launch ([[pregame-lobby-tests]] Test 1) — the *blob's* live copy, not the mode object.

Every route to the mode config is closed by measurement (GSC P1–P11, CE/TAC, the native setters from a
remote thread). So a "Gunfight config with an open picker" is not on the table; the choice is which side
of the mismatch to live with:

| Workflow | Config | Session | Picker | Launch | Cost |
|---|---|---|---|---|---|
| **A** — Gunfight lobby, map via Stage/NOW | Gunfight | gunfight / any map | **locked** (red icons, even on the loaded map) | real Gunfight, real blob | map changes only from inside a match; a NOW switch is not a clean transition for guests |
| **B** — TDM lobby, one seed stage/switch to Gunfight | TDM | gunfight / any map | **open**, and picks stick to `gunfight` (fact 1) | `g_gametype=gunfight` on **TDM's blob** | lobby header / options / rules say TDM; the Gunfight rules rows are not in the UI; the blob must be corrected by script |

▶ **B is the workflow, and with fact 5 its seed step is a Stage, not a switch:** TDM lobby → any match →
*Stage gunfight* → wait for STAGE READY → End Game → the lobby is now "TDM config, gunfight session" and
stays that way across UI map picks. No guest ever sits through an in-match switch. Its two costs split
cleanly: the labels are LUI (unfixable, cosmetic to the host — what a *joiner* sees is still unmeasured),
and the blob is measurable and correctable from script (`mode_profile_prime` before the stage +
`mod_apply` at every match start), which is what the census is for. The Gunfight rows the UI no longer
offers (round win limit, rounds per loadout, spy plane, custom classes, timer) are all menu/app settings
the mod already asserts, so "can't edit Gunfight options in the lobby" costs nothing once the profile
is complete.

### The 25 s — what it is and how to change it

It is **our own wait, not the engine's**. `do_session_switch` runs stock Zombies' sequence verbatim
(`zm_utility_zsurvival.gsc:153-155`): `switchmap_load( map, gt )` → `level waittilltimeout( 25,
#"switchmap_preload_finished" )` → `switchmap_switch()`. The engine fires that notify when the async load
is done; the 25 is only a cap. Measured: the **first** switch of a session gets the notify (moves at once);
**later ones never do and sit the full cap** before switching — yet they switch fine, so the load did
complete, only the notify is missing (an engine latch, not readable from script; the only switchmap
builtins are `switchmap_preload / _load / _switch / _setloadingmovie`, no "is it loaded" query).

Already editable: **`gf_switch_wait`** — Map page *Switch wait: 25s - proven / 5s / none - cp form*, app
Session/Map. `0` is stock **campaign's** immediate form (`cp_common/load.gsc:412-414`: `switchmap_load`,
one network frame, `switchmap_switch` — no wait on the notify at all; `switchmap_switch` evidently blocks
until the load is ready). Untested in MP. ▶ Try `5`, then `0`, on a *second* switch of a session; if the
load still completes cleanly, `0` becomes the default and the 25 s is gone.

**Stage now uses the same notify** (`do_session_stage`, payload 173,657 B / 1,108 strings): after the
load call it waits up to `gf_switch_wait` (25 if 0) for `switchmap_preload_finished` and prints
**STAGE READY** centre-screen — green "load finished" on the notify, yellow "no notify in 25 s - normal
after the first switch" on the cap. End the match only after that line. (Fact 5 is the reason: an End
Game before the load completes discards the stage.)

### Census rebuilt for this (2026-09-14) — superseded the same evening by the one-screen hold, below

Two problems with the old census, both fixed in `gunfight_menu.gsc`:

1. **It read the blob after `mod_apply` had already written to it** (customcac, loadoutindex, spyplane,
   roundwinlimit, maxplayers …), so a hybrid's census would have shown the mod's corrections, not the
   remnants. Now `census_snapshot()` is the **first call in `mod_apply`**, once per `gametype|map` per
   match (`game.gf_census`, keyed so a NOW switch re-snapshots and round 2 keeps round 1's clean read).
   Menu: *Display → Census: blob AS LAUNCHED* (the snapshot) / *Census: LIVE values* (now).
2. **Ten rows into a fading 4-line feed** could not be screenshotted. The readout is now the Test-1 form:
   `iprintlnbold` one row at a time, held 3 s, looping (20 passes), host only, echoed to the feed;
   activate again to stop. **`gf_census 1`** (menu *Census auto ON* / app Display → *Settings census at
   match start*) starts it by itself at every match start, before the Gunfight gate — so it also runs
   in a plain TDM match.

12 rows: timelimit/scorelimit/roundlimit/roundwinlimit · cumulative/roundswitch/scoreperkill ·
forcerespawn/queuedrespawn/respawndelay/numlives · maxplayers/teamcount/hardcore/spectate ·
customcac_off/classsel_off/perks/attach_off · weapondrop_off/loadoutstreaks/teamchange/tacinsert_off ·
gf_rounds_per_loadout/gf_spyplane/gf_loadoutindex · capturetime/extratime/prematch/preround ·
**maxhealth/regentime/autoheal/dmgscalar** (new) · **forceradar/explosivedelay/streakdelay/sprinttime**
(new) · bundle/switchsides/roundswitch/roundsplayed · g_gametype/map/gf_customcac/gf_switch_sides.

### The run (one sitting, host alone, ~15 min)

Arm once: inject the new `gunfight_menu`, set **gf_census 1** (app Display, or menu *Census auto ON*).
It persists across matches. Then three launches; in each, wait for the `LAUNCH n/12` rows to cycle
centre-screen, screenshot all 12 (36 s per pass; it loops, so no hurry), end the match.

| Column | Lobby | How | Reads |
|---|---|---|---|
| **A** | Gunfight selected in the UI, any Gunfight map | Play | the **real Gunfight blob** |
| **B** | Case-B lobby (TDM config, session already `gunfight`), pick an off-compat map in the UI | Play | the **hybrid blob** — the launch everyone will actually use |
| **T** | plain TDM lobby, no stage | Play | TDM's own blob — says which B values are TDM defaults vs. leftovers |

Optional **C**: in A's match, Switch NOW to another map — the re-snapshot after the switch says what the
switch itself carries (expected ≈ A, LS6).

**A − B is the profile.** Each key that differs goes into `mode_profile_prime` (written before the seed
stage, so it rides the session into the lobby's next launch) and `mod_apply` (asserted at every match
start), with A's measured value. Then B's launches are real Gunfight at the rules level and the only
remnant left is the lobby's TDM lettering. ⚠ Two keys are asserted with care: `disableClassSelection`
changes the spawn path if forced wrong (see the mod_apply comment), and `timelimit` is the mod's own
timer (`gf_timer` → `level.gettimelimit`) — read them, don't guess them.

**While the screenshots are being taken, note in the same sitting:** every in-match place that still
says TEAM DEATHMATCH in a B launch (scoreboard header, pause menu, after-action report). Those are the
remnants the blob cannot fix; they are the list to check against the joiner.

### Still open after this

- **The joiner in a Case-B lobby** (the only test that matters for hosting): what their lobby card says,
  and whether they load the Gunfight launch cleanly. The session descriptor is consistent (facts 1, 3,
  5), so the expectation is a clean load with a TDM-labelled card.
- **`gf_switch_wait 0`** on a second switch (above).
- **Frontend stage-only** — a stripped, `switchmap_load`-only payload from the lobby VM. The B2 crash
  ([[pregame-routes]]) predates `strip-strhdr.ps1` and ran the full switch sequence; a stage-only call
  with an intact map name has never been tried. If it works, Case A gets map changes from the lobby
  itself (no match needed, red icon stays cosmetic). Untried — not ruled out.

### Column A — the real Gunfight blob, MEASURED 2026-09-14 (klaze, 12-row build)

Gunfight selected in the UI, `mp_sm_berlin_tunnel`, launched from the lobby; snapshot taken at
`mod_apply` entry, before any mod write:

| key | A | key | A | key | A |
|---|---|---|---|---|---|
| timelimit | **40** | scorelimit | 0 | roundlimit | 0 |
| roundwinlimit | **6** | cumulativeroundscores | 0 | roundswitch | 1 |
| teamscoreperkill | 0 | playerforcerespawn | 1 | playerqueuedrespawn | 0 |
| playerrespawndelay | 0 | **playernumlives** | **1** | maxplayers | 8 ⚠ |
| teamcount | 2 | hardcoremode | 0 | spectatetype | 6 |
| **disablecustomcac** | **1** | **disableclassselection** | **1** | perksenabled | 0 |
| disableattachments | 0 | disableweapondrop | 0 | loadoutkillstreaksenabled | 0 |
| allowingameteamchange | 1 | disabletacinsert | 0 | gunfightroundsperloadout | 2 |
| gunfightspyplane | 0 | gunfightloadoutindex | 0 | capturetime | 3 |
| extratime | 10 | prematchperiod | 15 ⚠ | preroundperiod | 7 ⚠ |
| playermaxhealth | 150 | playerhealthregentime | 5 | autoheal | 0 |
| bulletdamagescalar | 1 | forceradar | 0 | roundstartexplosivedelay | 5 |
| roundstartkillstreakdelay | 10 | playersprinttime | 4 | bundle / switchsides | yes / 1 |
| level.roundswitch | 1 | game.switchedsides | 0 | game.roundsplayed | 0 |

⚠ Three values are probably the mod's own carried writes, not the pristine preset: `maxplayers=8`
(the mod's 4v4 write / the frontend writer — a 2v2 preset would read 4), `prematchperiod=15` and
`preroundperiod=7` (`mod_periods` defaults, written every match; stock's own defaults unknown). For
the profile that is irrelevant — A *as measured* is the state B must reproduce.

Reading it: `disableClassSelection=1` is now **read, not inferred** (the mod_apply caveat about forcing
it is lifted: A has it at 1, so asserting 1 in a Gunfight launch reproduces the real spawn path).
`playernumlives=1` is the no-respawn-within-a-round rule — the first thing a TDM blob (unlimited lives)
will change, and almost certainly the "TDM bleeding into gameplay" klaze saw. `scorelimit=0` matters
too: TDM's blob carries a kill score limit that Gunfight never reads as 0.

### Column B and T — pending (one-screen build)

The 12-row cycle was replaced the same evening by the **one-screen hold** klaze asked for (payload
173,213 B / 1,107 strings): 46 values with short keys, held on all three free-text channels at once —
centre line (re-sent every 3 s), hint row (trigger banner on the host, the widest line, no fade), and
three feed lines (re-printed every 3 s, so the newest 3–4 feed lines are always these). One
screenshot per column. Legend:

| short | setting | short | setting | short | setting |
|---|---|---|---|---|---|
| tl | timelimit | sl | scorelimit | rl | roundlimit |
| rwl | roundwinlimit | cum | cumulativeroundscores | rsw | roundswitch |
| spk | teamscoreperkill | fr | playerforcerespawn | qr | playerqueuedrespawn |
| rd | playerrespawndelay | nl | playernumlives | mp | maxplayers |
| tc | teamcount | hc | hardcoremode | spec | spectatetype |
| cac | disablecustomcac | cls | disableclassselection | prk | perksenabled |
| att | disableattachments | wd | disableweapondrop | lks | loadoutkillstreaksenabled |
| tch | allowingameteamchange | tac | disabletacinsert | gfr | gunfightroundsperloadout |
| gfs | gunfightspyplane | gfl | gunfightloadoutindex | cap | capturetime |
| ext | extratime | pre | prematchperiod | prr | preroundperiod |
| hp | playermaxhealth | reg | playerhealthregentime | ah | autoheal |
| dmg | bulletdamagescalar | rad | forceradar | exd | roundstartexplosivedelay |
| skd | roundstartkillstreakdelay | spr | playersprinttime | bnd | gametype bundle present |
| ssg | bundle.switchsides | lrs | level.roundswitch | ss / rp | game.switchedsides / roundsplayed |

Layout: **centre** `LAUNCH tl sl rl rwl cum rsw spk fr qr rd nl` · **hint row** `mp tc hc spec cac cls
prk att wd lks tch tac gfr gfs gfl` · **feed** `cap ext pre prr hp reg ah dmg` / `rad exd skd spr bnd
ssg lrs ss rp` / `LAUNCH <gametype>/<map> cfg cac= sw=`. `-` = the key is undefined in this build.
Unmeasured until the first run: the hint row's usable width (it clips at the screen edge rather than
wrapping — [[hint-panel]]); if `gfr gfs gfl` fall off the right edge, move them to the feed.

### Column T — TDM's blob, MEASURED 2026-09-14 (klaze, 12-row build), and A − T

Plain TDM lobby, `mp_miami`, launched from the lobby. Only the keys that differ from A:

| key | A (Gunfight) | T (TDM) | what the hybrid does with T's value |
|---|---|---|---|
| timelimit | 40 (s) | 10 (**minutes** — `time_limit` vs `time_limit_seconds` share the key) | the mod's `gettimelimit` override owns the clock; harmless |
| scorelimit | 0 | **100** | a kill score limit Gunfight never reaches as 0 |
| roundlimit | 0 | **1** | **the match ends after one round** |
| roundwinlimit | 6 | **0** | no first-to-N |
| cumulativeroundscores | 0 | 1 | |
| teamscoreperkill | 0 | 1 | kills score toward the 100 |
| **playernumlives** | **1** | **0** | **respawns inside a round, no elimination round-end** |
| maxplayers | 8 | 12 | lobby totals (3+3+2 / 6+6); the mod writes its own |
| spectatetype | 6 | 4 | |
| disablecustomcac | 1 | 0 | custom classes (already asserted) |
| disableclassselection | 1 | 0 | class menu |
| perksenabled | 0 | 1 | perks |
| loadoutkillstreaksenabled | 0 | **1** | **killstreaks** |
| gunfightroundsperloadout | 2 | **0** | **loadout never rotates, sides never swap** |
| capturetime / extratime | 3 / 10 | 10 / 0 | overtime zone timings (mod's zone block owns them when on) |
| prematchperiod / preroundperiod | 15 / 7 | 10 / 10 | `mod_periods` owns them |
| autoheal | 0 | **1** | **health regenerates** |
| roundstartexplosivedelay | 5 | 0 | |

Everything else is identical (150 hp, regen 5, dmg 1, radar 0, sprint 4, respawn shape, weapon drop,
attachments, tac insert, hardcore 0, bundle present, switchsides 1).

**Two conclusions beyond the diff:**

1. **A lobby launch rebuilds the blob from the config.** T reads `prematch=10 preround=10` although the
   mod writes 15/7 into the settings every match — nothing written in a previous match survives a
   launch from the lobby. So `mode_profile_prime` (settings written before a stage) cannot reach a
   lobby launch; only the **match-start assertion, settings + level vars**, does. (A's 15/7 and
   maxplayers=8 are therefore Gunfight's own preset — 8 = 3+3+2 casters — not carried writes.)
2. **B is predicted = T with `g_gametype=gunfight`.** klaze is capturing it now; if it matches, the
   raw hybrid is: one round then match over, respawns, regen, streaks, perks, custom classes, no
   loadout rotation — every "TDM bleeding into Gunfight" symptom, and every one is in the profile.

### The profile — built 2026-09-14, never run (payload 175,904 B / 1,111 strings)

`mode_profile_gunfight( in_match )` in `gunfight_menu.gsc`, gated on **`gf_profile`** (default 1;
Loadout page *Gunfight profile ON - real blob* / *OFF - raw hybrid*; app Loadout → *Gunfight profile*).
Called from `mod_apply` (after the customcac assertion, `in_match=1`), from `cmd_apply_live`, and from
`mode_profile_prime` (`in_match=0`, settings only — harmless but, per conclusion 1, not load-bearing).

Asserted (setting **and** the level var globallogic copied before the callback — `function_b9b7618`
:5030-5188, util.gsc `register*` from `init()` :364-369 — so it takes effect **this round**):
`playernumlives=1` (+ `level.numlives`, `level.graceperiod=15`), `scorelimit=0`, `cumulativeroundscores=0`,
`teamscoreperkill=0`, `roundwinlimit` (menu value, else 6), `roundlimit` (menu value, else 0),
`playerforcerespawn=1`, `playerqueuedrespawn=0`, `playerrespawndelay=0`, `disableclassselection` (1, or 0
with custom classes on), `perksenabled=0`, `loadoutkillstreaksenabled=0` (+ level var from
`player_loadout.gsc:252`), `disableattachments=0`, `disableweapondrop=0`, `disabletacinsert=0`,
`playermaxhealth=150` (+ `level.var_90bb9821=0`), `playerhealthregentime=5`, `autoheal=0`,
`bulletdamagescalar=1`, `forceradar=0`, `roundstartexplosivedelay=5`, `roundstartkillstreakdelay=10`,
`playersprinttime=4`, `spectatetype=6`. Plus, under the profile, **stock rounds-per-loadout now means
A's 2** instead of "leave the lobby value" (T's 0 = never rotate).

Left to their owners: timer (`gf_timer`), maxplayers (team size), customcac, loadout index, spy plane,
prematch/preround (`mod_periods`), roundswitch (side-switch block), capturetime/extratime (zone block),
hardcore and allowingameteamchange (host's own rules choices, not forced).

**Verification, one Case-B launch with the new payload:** the `LAUNCH` census still shows T's values
(it is the pre-write snapshot — expected), the **LIVE** census (Display → *Census: LIVE values*) shows
A's, and the round plays as Gunfight: one life, round ends on elimination, loadout rotates on round 3,
match runs to 6 round wins. Then the in-match remnant list (scoreboard/pause/AAR lettering) and the
joiner test are what is left.

### Column B — MEASURED 2026-09-14 (klaze): **B == A.** Fact 3 (2026-09-13) is RETRACTED for lobby launches

Case-B lobby (TDM config, `gunfight` session), `mp_tundra` picked in the UI, launched from the lobby;
snapshot at `mod_apply` entry. **Every one of the 46 values equals column A** — `timelimit=40
scorelimit=0 roundlimit=0 roundwinlimit=6 … numlives=1 … customcac_off=1 classsel_off=1 perks=0 …
loadoutstreaks=0 … gf_rounds_per_loadout=2 … capturetime=3 extratime=10 prematch=15 preround=7 …
autoheal=0 … explosivedelay=5`, `g_gametype=gunfight map=mp_tundra`. Not one TDM value.

▶ **A lobby launch rebuilds the settings blob from the SESSION gametype's preset.** The lobby's mode
config (TDM) drives only what the lobby shows — labels, rules pages, compat gate. It does not reach
the launch. Combined with column T (a TDM launch does not keep the mod's earlier writes either), the
launch path is: *session gametype → that mode's preset → blob*, fresh every time.

So the 2026-09-13 statement *"a match launched FROM that lobby is a hybrid: `g_gametype = gunfight`
on TDM's settings blob"* was wrong **for lobby launches**. The hybrid is real, but it lives in exactly
one place: **a Gunfight level reached by an in-match Switch NOW from TDM**, where LS6 applies — the
current match's blob rides the switch into the new level. That is what the 09-13 screenshot ("Gunfight
header, MODE: Team Deathmatch, custom classes") and klaze's "TDM settings bleed … depending on the
method order" were. (⚠ Unverified corner: whether rules-page *edits* made in the TDM config leak into
a Gunfight launch's shared keys — B was taken with untouched TDM rules.)

**What this does to the workflow.** Case B is now better than the note above says: TDM lobby → one
Stage of `gunfight` (wait for STAGE READY) → End Game → from then on every map pick in the UI launches
**real Gunfight on the real Gunfight blob** — one life, first to 6, fixed loadouts rotating every 2
rounds, no streaks, no regen. The remaining costs are the lobby's TDM lettering and the absent Gunfight
rules rows (round win limit, timer, rounds per loadout, spy plane, custom classes are all menu/app
settings). The in-match remnant list and the joiner are what is left to measure.

**And to the profile.** Asserting A unconditionally at every Gunfight match start would have trampled
a host's own Gunfight rules-page choices (round win limit 4, rounds per loadout 3 …) on every real
launch — the very state B proves is already correct. So the profile is now **gated on a hybrid
detector**: `profile_is_hybrid()` reads `playerNumLives` and `roundWinLimit` before anything writes them
— the real Gunfight blob always has 1 and 1–6 (the Gunfight row publishes 1–6, never 0); TDM's has 0 and
0 (column T). Only then are A's values asserted (settings + level vars), with a feed line saying so. On a
lobby launch it is a no-op by construction. The pre-stage priming of the blob was dropped: a launch
rebuilds it anyway, so those writes never arrived. Payload **176,339 B / 1,112 strings**, never run.

**Verification is now a Switch NOW test, not a lobby launch:** TDM match → *Switch NOW → gunfight*
(let it switch) → the new level should print `profile: Gunfight on another mode's blob - asserting the
real one` and play as Gunfight (one life, elimination ends the round). Display → *Census: LIVE values*
should read A. A lobby-launched Gunfight (Case A or B) must show NO profile line.
