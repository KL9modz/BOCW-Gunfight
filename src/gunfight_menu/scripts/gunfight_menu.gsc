// ─────────────────────────────────────────────────────────────────────────────
// GUNFIGHT HOST MENU — the in-match control surface. Roadmap Goal A, item A1.
//
// Hook: scripts\mp_common\bb.gsc, mode=mp  (see ../gsc.conf)
//
// ── WHAT THIS IS ─────────────────────────────────────────────────────────────
// gunfight_mod (all four fixes + team size, verified in-game) PLUS a mod menu on
// top, in ONE payload. B9 measured that a payload cannot be hot-swapped under a
// live one, so the host cannot inject the mod and then the menu: whatever the
// host needs must be in the file that gets injected once per game launch.
// gunfight_mod.gsc is untouched and remains the no-menu variant.
//
// ── WHERE THE MENU ENGINE COMES FROM, AND WHY IT IS REWRITTEN NOT COPIED ─────
// The engine is a translation of ate47/t8-atian-menu's coldwar/scripts/core_common/
// {menu,keymanager}.gsc - the same menu klaze already drives for the map carry, so
// every key and every screen behaves the way he already knows.
//
// ⚠ It could NOT be copied. The Atian Menu is built with shiversoftdev's
//   debugcompiler in #include / bare `autoexec` / #ifdef dialect - the exact dialect
//   this project's history records as crashing the game at script link under ACTS
//   (hello_world, 2026-09-07). This file is ACTS dialect throughout: #using,
//   `function` on every definition, `function private autoexec`, system::register
//   with five args and a hashed name, no preprocessor, one file.
//
// ── WHERE SETTINGS LIVE, AND WHY IT IS DVARS ─────────────────────────────────
// A menu that wrote into level.* would revert at a round or match boundary; `game.`
// survives rounds but resets at match end. A DVAR survives both (B4: one carried across
// a map_restart). So every host setting is a dvar with a default, read by mod_apply().
// ⚠ mod_apply runs on on_start_gametype, which is the MATCH-start callback
// (globallogic callback_startgametype) - it fires ONCE PER MATCH, not per round. That is
// fine for settings that are applied once and then persist (timer override, team size,
// gametype settings). But anything that must CHANGE per round cannot live only here:
//   - the loadout rotation / side switch is per round-end in gunfight.gsc's onendround,
//     gated on the level var it reads - so mod_apply sets that live level var, not just
//     the gametypesetting (gf_rounds_loadout, below);
//   - the spawn-guard anchor shuffle + side-follow is refreshed per round in on_spawned
//     (mod_spawn_place), because building it once in mod_apply would freeze it for the
//     whole match.
// The dvars, read by mod_apply once per match:
//
//     gf_team_size      per side, default 4
//     gf_spec_slots     2 (default) - spectator/caster slots ADDED to the maxplayers write (team
//                       size x 2 + slots, capped at com_maxclients) so a spectator does not eat a
//                       player slot at bot fill / join time (klaze 2026-09-15: 4v4 + 1 spectator = 3v4 fill).
//     gf_timer_seconds  default 60. 0 = NO round timer: rounds end by elimination only
//     gf_prematch       pre-MATCH countdown in seconds - "match starting in", before round 1.
//                       Default 15 (the custom-games row offers 5/10/15/30/45/60). -1 = the
//                       lobby's own value.
//     gf_preround       pre-ROUND countdown in seconds - before every round after the first.
//                       Default 7 (the row offers 0-30; 0 = no countdown). -1 = the lobby's
//                       own value. Both feed the ONE stock level var level.prematchperiod,
//                       which stock fills from the settings BEFORE this callback - so
//                       mod_periods() writes the live var as well as the settings.
//     gf_loadout        0 default / 1 snipers / 2 blueprints / 3 melee
//     gf_customcac      0 (default) = real Gunfight: fixed loadouts, class selection off. 1 = the
//                       rules-menu "Custom Classes" row (disable_cac.json) on purpose. ⚠ Why this
//                       exists: gametype settings SURVIVE a session switch (LS6), so a Gunfight
//                       reached from TDM runs on TDM's settings blob, and gunfight.gsc:102-109 runs
//                       a CUSTOM-CLASSES branch whenever disableCustomCAC != 1 - "Gunfight header,
//                       MODE: Team Deathmatch, custom classes" (klaze's screenshot, 2026-09-13).
//                       Asserted at every Gunfight match start (mod_apply) and primed before a
//                       switch (mode_profile_prime). The rest of the blob is measured, not guessed:
//                       Display -> Settings census. docs/notes/mode-remnants.md
//     gf_profile        1 (default) = when a Gunfight level is running on ANOTHER mode's blob (only
//                       an in-match Switch NOW from TDM does that - a lobby launch rebuilds the
//                       blob from the session gametype, column B == A), assert the REAL Gunfight
//                       blob (column A, docs/notes/mode-remnants.md): settings + level vars, so
//                       1 life per round, no kill limit, fixed loadouts, no streaks/perks. Detected
//                       by playerNumLives/roundWinLimit (profile_is_hybrid). 0 = the raw hybrid.
//     gf_census         0 off (default). DEBUG FEED: 1 = print the settings blob AS LAUNCHED
//                       (the snapshot mod_apply takes before its own writes) as ONE feed line
//                       every 3 s; 2 = the LIVE values. Short keys, legend in
//                       docs/notes/mode-remnants.md. Display -> Debug feed.
//     gf_dbg_spawn      1 = one feed line every 3 s: this round's engine/guard placements, every
//                       player (name:team:how:d:PILE) + the guard state. docs/notes/spawn-system.md
//     gf_dbg_structs    1 = one feed line: mp_spawn_point counts, the first structs' fields, the
//                       engine's spawn list names.
//     gf_dbg_families   1 = one feed line: spawn-struct family counts, legacy detector numbers,
//                       what the guard built.
//     gf_dbg_match      1 = one feed line: the Show-match-info readout.
//     gf_dbg_assets     1 = three feed lines. VEHICLES: which of 154 candidate names are resident
//                       vehicle assets on this map, by index:name, + the veh_spawn_point count.
//                       PROPS: this map's Prop Hunt table (tbl/rows/size buckets/row-0 model +
//                       residency). DESTRUCT: the map's destructible entities - count, kinds
//                       (their .destructibledef names, the REAL names the manifests only hash),
//                       veh_ cars, + X = the offline radiant-exploder count for this map.
//                       src/vehicle_probe + src/prop_probe as a menu tool, so the per-map census
//                       is a map walk with the menu in. docs/notes/vehicles.md §5, destructibles.md
//     gf_camo           camo forced onto every loadout-pool weapon, every player, every spawn.
//                       -2 random each round (DEFAULT: one roll per weapon, shared by everyone)
//                       -3 random per player-spawn / -1 stock (the pool's own look - bare,
//                       blueprints keep theirs) / N a camo index: 61 Gold 62 Diamond 63 DM Ultra
//                       64 Golden Viper 65 Plague Diamond 66 Dark Aether 67-69 Pack-a-Punch 1-3,
//                       1-121 mapped. docs/notes/loadout-camo.md
//     gf_camo_pool      the random modes draw from: 0 mastery + Pack-a-Punch (default) / 1 all 1-121
//     gf_camo_split     1 (default) primary and secondary roll separately / 0 one roll for both
//     gf_spyplane       0 off / 1 on / 3 shared (the value the menu hides)
//     gf_map_method     1 session (switchmap_load - the lobby FOLLOWS, verified 2026-09-12, default)
//                       0 carry   (map() - the Atian load-time override; lobby stays stale. fallback)
//     gf_staged_map     READ-ONLY markers, written by the "Stage for lobby" verb: the map /
//     gf_staged_gt      gametype switchmap_load'ed but not switched, which the lobby shows
//                       when the match ends. Only the state line reads them.
//     gf_spawn_guard    0 off (default) / 1 force on / 2 AUTO - reposition to central,
//                       in-bounds real spawns. AUTO only guards a map whose Gunfight start
//                       spawns are the wrong (12v12) layout; good maps keep stock. (untested)
//     gf_spawn_autospread AUTO trip point (units, default 2500): guard when the nearest
//                       start spawn is farther than the map's objective-spawn cluster
//                       radius + this. Read only in AUTO mode; the report prints the raw
//                       measurements so it can be calibrated on the first run.
//     gf_caster_probe   1 on (default) - while the host is a CoD Caster, print a probe line
//                       (to BOTH text channels) listing every button currently pressed, so
//                       which buttons a caster delivers to GSC + which channel renders can be
//                       read off in one match. Toggle from Display. Only runs while casting.
//     gf_spawn_diag     1 on (default) - 60=armed(N) / 61=inert + AUTO probes
//     gf_strike         0 (default) - Crossroads: keep the STRIKE layout under Gunfight by renaming
//                       the oob-clip / boundary entities the map's on_game_playing would delete.
//                       Off by default: the client map script still draws the 12v12 minimap and
//                       bounds (mp_tundra.csc), so clips stand on visibly open ground. No-op elsewhere.
//     gf_spawn_family   1 tdm (DEFAULT since 2026-09-15, measured good on Hijacked) / 0 none / 2 sd /
//                       3 dom / 4 ctf / 5 koth / 6 control / 7 dm:
//                       the guard builds its anchors ONLY from markers carrying that mode's flag
//                       field (measured on Hijacked: `tdm=1` is a plain script field on
//                       mp_spawn_point), uses their side fields when present, and places EVERY
//                       spawn on them. Gunfight on the S&D spawn set = 2.
//     gf_dbg_flags      1 = one feed line: which flag fields the markers carry + value tallies.
//     gf_spawn_pick     0 (default) near: the two sides sit around the centre at gf_spawn_gap -
//                       TDM's respawn zone, the "closer up" spawns. 1 far ends: the two outermost
//                       marker groups on the best axis - TDM's opening spawns, rebuilt from markers.
//     gf_spawn_gap      1800 (default) - the guard's target distance in units between the two
//                       sides' centres; anchors are the tightest marker groups either side of
//                       the map centre at about that distance, facing each other.
//                       62=obj-radius 63=nearest-start 64=decision + per-spawn receipts, to
//                       the HOST's screen only. Nothing this payload prints reaches a joiner.
//     gf_zone           0 off (default) / 1 on - build the OVERTIME CAPTURE ZONE that private
//                       matches never get (no map ships gunfight_zone_center in a private match,
//                       docs/notes/gunfight-findings.md). Anchored on Domination's neutral B flag,
//                       then a Hardpoint / Control zone. docs/notes/overtime-zone.md
//     gf_zone_overtime  seconds of overtime once the round timer runs out, default 20
//     gf_zone_capture   seconds standing in the zone to capture it, default 5
//     gf_zone_radius    trigger radius (units) when no map trigger can be reused, default 128
//     gf_roundwinlimit  -1 leave stock (default) / N first-to-N rounds
//     gf_roundlimit     -1 leave stock (default) / N round cap
//     gf_rounds_loadout -1 leave stock (default) / N = rotate loadout AND switch sides
//                       every N rounds (stock couples both; mod_apply sets the live level
//                       var + the switchsides gate so the menu pick actually takes)
//     gf_switch_sides   1 (default) = the mod OWNS the side swap: the gametype bundle's
//                       switchsides gate is forced on and the generic roundswitch path is
//                       silenced (level.roundswitch = 0), so only Gunfight's own coupled
//                       path flips game.switchedsides - once per rotation. 0 = stock: the
//                       bundle flag as shipped and BOTH paths live. ⚠ Why: two stock paths
//                       reach gametype::on_round_switch at one round end (gunfight.gsc:397
//                       then display_transition.gsc:523); two flips = no visible swap while
//                       the loadout still rotates - klaze's "rotates the loadouts but does
//                       not switch sides" (2026-09-13). docs/notes/mode-remnants.md
//     gf_menu_lines     visible item rows in the panel window, default 7 (was 2)
//     gf_menu_region    2 (DEFAULT since 2026-09-14): menu carousel in the centre, status block
//                       in the feed, info line in the hint row / 0 lower-left feed / 1 centre / 2 SPLIT status-left
//                       menu-centre / 3 SPLIT menu-left status-centre / 4 HINT panel. ⚠ The
//                       centre shows only ONE line (engine limit; no dvar grows it - only the
//                       lower-left feed is multi-line, ~4). So region 2 renders the centre
//                       menu as a HORIZONTAL carousel (items side by side, current bracketed,
//                       slides as you scroll); region 3 (or 0) puts a vertical multi-row list
//                       in the feed - raise gf_menu_lines there for more rows. SPLIT has no
//                       toast region, so confirmations fold into the status. Set it from
//                       Display.
//                       4 = HINT: the panel is a trigger hint string, drawn by the stock
//                       use-prompt widget - the third text channel this engine has, and the
//                       one every "full HUD" Cold War GSC menu (SoCanKam PS4/PC, Lucy-Base)
//                       actually uses, since T9 retail has no hudelem builtins at all
//                       (docs/notes/ecosystem-survey.md; funcs_cw.csv). It does not fade, it
//                       does not scroll, one call repaints it, colour codes work, and the
//                       host alone sees it (setvisibletoplayer). Toasts go to the centre.
//                       ⚠ built 2026-09-13, never run - see the hint knobs below.
//     gf_hint_lines     region-4 item rows per page, default 8 (Lucy-Base packs 8, SoCanKam
//                       15). Lower it if the widget truncates the string.
//     gf_hint_newlines  region-4 row separator: DISABLED 2026-09-14 - a real \n CLOSES THE
//                       MATCH (the use-prompt widget can't take an embedded newline). Rows are
//                       always packed on one line, split by ^8| (the form both open menus ship).
//                       (old note kept below for context; the newline path no longer exists.)
//                       [former] 1 = a real newline between rows. Whether the widget honours it is
//                       UNMEASURED; flip it once from Display and look.
//     gf_menu_hspan     region-2 carousel width: how many entries the centre bar shows at
//                       once, default 4. Fixed window (clamped) so the bar does not grow/
//                       shrink as you scroll; < / > show there are more off each end.
//     gf_feed_lines     how many lines the lower-left feed shows at once, default 14.
//                       This is the stock dvar com_gameMsgWindow1LineCount (ships at
//                       ~4-5) - the feed capped the panel until we raised it. Host-
//                       local, so joiners are unaffected. Lower it if the feed spills
//                       into other HUD; 0 leaves the stock value alone.
//     gf_gravity        bg_gravity, stock 800 (verified engine-consumed in MP, mp-dvars.md)
//     gf_jump           setjumpheight BUILTIN value, -1 = engine default. ⚠ The builtin has no
//                       stock caller and has never been watched in-game; gf_jump_boost is the
//                       mechanism-proven alternative.
//     gf_jump_boost     extra UPWARD velocity (units/s) added at every takeoff, every player,
//                       0 = off. Stock's own shape (setvelocity( getvelocity() + push ), 16
//                       uses): jump apex = v^2 / 2g, stock v ~250 at g 800 -> +150 ~100u apex,
//                       +400 ~260u, +800 ~690u, +1300 ~1500u. jump_boost_think per player.
//     gf_oob            1 (DEFAULT) = out-of-bounds OFF for everyone: no "restricted area" HUD
//                       warning, no countdown, no death. 0 = stock. Stock's own switch: the
//                       per-player value disable_oob (oob.gsc:81) - set, the trigger callback
//                       returns before enter_oob (oob.gsc:640 via function_65b20), so the HUD
//                       clientfield and the kill timer never start; set on someone already out,
//                       resetoobtimer clears the HUD at once. Spy mode uses the same call
//                       (spy.gsc:2411). ⚠ Stock NUKES every disable_oob layer on each spawn
//                       (globallogic_spawn.gsc:612), so it is re-set per life in
//                       mod_spawn_movement. A plain dvar, not in the packed store.
//     gf_vehmode        VEHICLE MODE, 0 (default) off: everyone spawns already riding this map's
//                       ride of the class - 1 motorcycles / 2 attack helis (Hind) / 3 care-package
//                       heli (every map) / 4 snowmobiles / 5 quads + buggies / 6 tanks + APCs /
//                       7 cars + trucks / 8 streak gunship (seat untested) / 9 AUTO (lightest ride,
//                       else the care package heli). Stock's spawn-in-vehicle shape
//                       (spawning_squad.gsc:1578): spawnvehicle at the spawn point + usevehicle.
//     gf_veh_lock       1 (default) riders cannot get off: the disable_usability value layer +
//                       a re-seat watcher. 0 = free to leave. Plain dvars, docs/notes/vehicle-mode.md.
//     gf_veh_hp         vehicle health, PERCENT of the asset's default (100). 25 makes a Hind
//                       killable by rifles; 400 makes bikes tanky.
//     gf_veh_alt        air rides spawn this many units above the spawn point (300), ceiling-traced.
//     gf_dbg_veh        1 = the VEHMODE debug feed line (one line, every 3 s).
//     gf_falldamage     1 stock / 0 off - bg_falldamageminheight/maxheight pushed out of reach
//                       (the pair cp/zm "oldschool" mode raises, cp globallogic.gsc:184). The
//                       stock values are captured once per process (gf_fd_min/max_stock) so
//                       "stock" restores the real ones, not a guess.
//     gf_speed          move speed in PERCENT, default 100. player setmovespeedscale(), the
//                       per-player scaler stock uses (Prop Hunt props, the Scream slasher 1.55,
//                       loadout speed modifiers) - re-applied after every loadout since
//                       give_loadout resets it (player_loadout.gsc:1883).
//     gf_fly_speed      host fly mode: units per server frame, default 20 (Atian's default);
//     gf_fly_fast       while sprint is held, default 60. Fly = playerlinkto a script_origin
//                       that follows getnormalizedmovement + view angles, jump/crouch = up/down
//                       (the shipped Atian Cold War fly, header.gsc fly_mode, and the same
//                       link+move shape Prop Hunt's _prop_controls.gsc uses). disable_oob is
//                       set while flying so the out-of-bounds timer leaves the host alone.
//                       While paused, "BLINKER CHECKPOINT" is held on every screen (re-sent
//                       every 3 s, pause_banner_think) until the 5 s resume countdown.
//     gf_cmd_say        app/bridge channel: a non-empty string is broadcast to every player
//                       and cleared. gf_cmd_say_loc 0 = centre (bold) / 1 = feed / 2 = a held
//                       HINT banner (persistent, per-player glued trigger; gf_say_hint_indent
//                       nudges it right). gf_cmd_say_dur 0 once / >0 hold N s / <0 until Clear.
//                       gf_cmd_pause 1 = pause the match / 2 = resume, same as the Host page.
//     gf_bot_diff_allies  bot difficulty per side, the stock gametype setting behind the
//     gf_bot_diff_axis    custom-games "Bot Difficulty" row: bot_difficulty_<team>, read by
//                       bot_difficulty::assign() when a bot joins its team (cracked 2026-09-12:
//                       #"hash_7a5a6325a6e843b7" == "bot_difficulty_"). -1 leave the lobby's
//                       value = default / 0 recruit / 1 regular / 2 hardened / 3 veteran /
//                       4 CUSTOM - our own difficulty struct, built from the gf_bot_* knobs
//                       below and swapped in after every stock assign. docs/notes/bots.md
//     gf_bot_hit        CUSTOM: chance (%) a shot cycle is aimed on-target, default 100 (stock 40/50/60/90)
//     gf_bot_head       CUSTOM: chance (%) an on-target cycle aims at j_head, default 50 (stock 0/3/10/20)
//     gf_bot_react      CUSTOM: ms of aim before each fire window, default 100 (stock 1400/1100/700/300)
//     gf_bot_fire       CUSTOM: ms the fire window lasts, default 1000 (stock 300/400/500/700)
//     gf_bot_hip        CUSTOM: hit-chance scale (%) when not ADS, default 100 (stock 50/50/60/70)
//     gf_bot_far        CUSTOM: hit-chance scale (%) at max range, default 90 (stock 100/80/66/50)
//     gf_bot_semi       CUSTOM: ms between semi-auto taps, default 100 (stock 800/600/400/150)
//     gf_bot_burst      CUSTOM: ms between bursts, default 100 (stock 1200/900/700/250)
//     gf_bot_moveshoot  CUSTOM: 1 keeps moving with a target in sight (default) / 0 stops to shoot (stock recruit/regular)
//     gf_bot_fastaim    CUSTOM: 0 slow look = stock recruit/regular / 1 fast = stock hardened/veteran, default / 2 max
//     gf_bot_sprint / gf_bot_melee / gf_bot_prone / gf_bot_slide / gf_bot_crouch
//                       CUSTOM: the bundle's allow* flags, all default 1 (stock veteran is the only
//                       preset with all five on)
//     gf_bot_passive    1 = every bot ignores everyone (stock .ignoreall - the dev-gui "Ignore All"
//                       flag: bot_action/bot_orders skip the engage decision). Target dummies.
//                       0 (default) normal.
//
// Set once, they hold until the game is restarted - at which point the payload
// has to be re-injected anyway. ⚠ These are NO LONGER pre-registered: dvars_register was
// disabled 2026-09-13 (registering all 72 at once overflowed the GSC-VM dvar store and crashed
// the game - memory dvar-pool-crash). It existed only for the dead route-A external dvar write
// (bocw-7f proved external WPM can't reach the GSC-VM store), so its loss costs nothing: every
// cfg_* reader uses getdvarint(name, default) and every menu write uses setdvar (registers on
// demand). Cosmetic only: a setting's '*' current-value marker appears after its first change.
//
// ── KEYS (identical to the shipped Atian Menu) ───────────────────────────────
//     open    ADS + melee     (RMB + V)
//     back    melee           (V)
//     up      ADS             (RMB)
//     down    attack          (LMB)
//     select  reload          (R)
//
// ── WHAT IS PROVEN AND WHAT IS NOT ───────────────────────────────────────────
//     zones_guard / timelimit_fix / presentation / timer_override   ✅ in-game
//     team size via maxplayers                                        ✅ L6 4v4; 6v6 filled 2026-09-12 (bots, 12-slot session)
//     bot fill via bot::add_bot                                       ✅ C7
//     add one / remove one / even-up via bot::add_bot / remove_bot   ⚠ built 2026-09-12, never run.
//                                                                       Same two primitives as fill, new
//                                                                       verbs around them.
//     bot difficulty via setgametypesetting( bot_difficulty_<team> )  ⚠ built 2026-09-12, never run.
//       + bot_difficulty::assign() re-read on live bots                 Key cracked exactly; the row is
//                                                                       stock custom-games UI, so the
//                                                                       setting is proven writable at
//                                                                       lobby level - runtime is ours.
//     CUSTOM difficulty = our struct on bot.bot.difficulty             ⚠ built 2026-09-12, never run.
//                                                                       Every stock reader is a plain
//                                                                       field read with a default
//                                                                       (bot_weapons.gsc:2970-3288).
//                                                                       docs/notes/bots.md
//     map_restart()                                                   ✅ B4
//     map carry via map() + switchmap_switch()                        ✅ the Atian carry (load-time only)
//     move a player via [[ level.autoassign ]]                        ⚠ C11 built, never run
//     loadout set via gunfightloadoutindex                            ⚠ B6 never run
//     loadout-pool camo via setcamo( weapon, index ) on spawn         ⚠ built 2026-09-12, never run.
//                                                                       The builtin is the engine's own
//                                                                       repaint (Pack-a-Punch, reactive
//                                                                       camos); the spawn timing is ours.
//     spy plane value 3                                               ⚠ B7 never run
//     #spawn_guard central real-spawn reposition                      ⚠ NEVER ACTUALLY RAN before 2026-09-12:
//                                                                       its targetnames were garbled by the ACTS
//                                                                       string header, so it gathered 0 and no-op'd
//                                                                       (probe 61). First real test is still ahead.
//     gametype switch via switchmap_load( map, gametype )             ⚠ built 2026-09-12, untested. mod_apply is
//                                                                       gated on gunfight/gunfight_3v3 for it
//     match limits roundwinlimit/roundlimit/roundsperloadout          ✅ keys verified in source
//     pre-match / pre-round countdowns via level.prematchperiod +      ⚠ built 2026-09-13, never run.
//       setgametypesetting( prematchperiod / preroundperiod )            Keys + read order verified in
//                                                                       source (mod_periods); the rows
//                                                                       are stock custom-games UI.
//     move/spectate guard level.autoassign / level.spectator          ✅ hardened
//     map via switchmap_load( map, gametype )                         ✅ 2026-09-12: the SESSION moves.
//                                                                       lobby-route restart reloaded Zoo,
//                                                                       com_maxclients read 12. Needs the
//                                                                       string-header strip (tools/) or the
//                                                                       map name reaches the engine garbled -
//                                                                       which is why bbf94f9 called it inert.
//                                                                       docs/notes/session-switch.md
//     HINT panel layout (gf_menu_region 4) via sethintstring on a     ⚠ built 2026-09-13, never run.
//       trigger_radius linked to the host                                Stock shapes (ctf/laststand/vip);
//                                                                       docs/notes/hint-panel.md has the
//                                                                       seven-step test.
//     jump boost via setvelocity at takeoff                           ⚠ built 2026-09-13, never run.
//                                                                       Stock's own shape (16 uses);
//                                                                       the takeoff detector is ours.
//     move speed via setmovespeedscale                                ⚠ built 2026-09-13, never run.
//                                                                       Stock's per-player scaler
//                                                                       (Prop Hunt, Scream, loadout).
//     fall damage off via bg_falldamageminheight/maxheight            ⚠ built 2026-09-13, never run.
//                                                                       cp/zm oldschool sets the pair.
//     fly via playerlinkto( script_origin ) + getnormalizedmovement   ⚠ built 2026-09-13, never run
//                                                                       HERE; the shipped Atian CW
//                                                                       menu's fly_mode works for
//                                                                       klaze, same mechanism.
//     pause via stock's esports-pause sequence (freeze+pausetimer)    ⚠ built 2026-09-13, never run.
//     freeze via val::set freezecontrols_allowlook / takedamage       ⚠ built 2026-09-13, never run.
//     broadcast via player iprintlnbold / iprintln                    ⚠ built 2026-09-13, never run.
//     weapons: all 64 MP loadout names + BO4 leftovers                ⚠ names from the data; display
//                                                                       labels marked ? are inferred.
//     stage a map for the LOBBY via switchmap_load alone              ✅ 2026-09-12 (klaze): match ended
//                                                                       between the load and the switch ->
//                                                                       the pregame lobby had the new map
//                                                                       selected. Now a menu verb; joiners,
//                                                                       a natural match end and the round
//                                                                       boundary still to be measured.
//     destructibles: break aimed / near / all via dodamage on the     ⚠ built 2026-09-17, never run.
//       map's own destructible entities; radiant exploders fired        Stock's own reads and writes
//       by hash from the bgcache table (exploder::exploder)              (destructible.gsc:23/:613,
//                                                                       exploder_shared.gsc:278).
//     projectiles: weapon_fired -> magicbullet( w, eye, far, self ),   ⚠ built 2026-09-17, never run.
//       rate-gated, optional missile_settarget homing                    Stock shapes (remotemissile
//                                                                       :415, straferun.gsc:897-899);
//                                                                       the per-shot rate is the test.
//     out of bounds OFF via val::set( "disable_oob", 1 ) per spawn    ⚠ built 2026-09-17, never run.
//                                                                       Stock's own switch (spy.gsc:2411);
//                                                                       fly mode already uses it here.
//     props: spawn( "script_model" ) + setmodel + setscale from the    ⚠ built 2026-09-17, never run.
//       map's _ph.csv table + a universal p9_* set, isassetloaded-gated  Prop Hunt's recipe (prop.gsc
//                                                                       :1946); "xmodel" residency
//                                                                       read measured 2026-09-15.
//
// ⚠ ONE CONTRADICTION THIS FILE HAD TO ROUTE AROUND. A4 diagnosed its map-switch
//   failure as `level endon( #"game_ended" )` killing the thread inside wait(1).
//   But the shipped Atian Menu's menu_think carries the SAME endon, its map action
//   runs INSIDE that thread with the same wait(1), and it works - klaze uses it.
//   So the endon cannot be the whole story. Rather than pick a theory, every map
//   switch here is threaded off onto the PLAYER with no endons at all, which
//   satisfies both the endon theory and A4 run 4's self=player theory at once.
// ─────────────────────────────────────────────────────────────────────────────

#using scripts\core_common\array_shared;
#using scripts\core_common\callbacks_shared;
#using scripts\core_common\clientfield_shared;
#using scripts\core_common\system_shared;
#using scripts\core_common\util_shared;
// val:: is the layered per-player value system (values_shared.gsc) stock uses for
// freezecontrols / takedamage / disable_oob, so a freeze here stacks with stock's own
// (the pause, scenes, insertion) instead of clobbering it. core_common: links everywhere.
#using scripts\core_common\values_shared;
#using scripts\core_common\struct;
#using scripts\core_common\music_shared;
#using scripts\core_common\exploder_shared;
#using scripts\core_common\bots\bot;
// bot_difficulty: assign() is the stock "re-read bot_difficulty_<team> and install the bundle"
// entry point (bot_difficulty.gsc:34). bot.gsc #uses it, so it links wherever bot does.
#using scripts\core_common\bots\bot_difficulty;
// globallogic, NOT gunfight: the menu links into TDM/etc. for the gametype switch, and
// gunfight.gsc is ABSENT from a non-Gunfight match's link set - a gunfight:: import there
// is a fatal link error ("error loading match", 2026-09-12). globallogic loads in every
// MP match, and it carries the round-end the health decision needs. See mod_ontimelimit.
#using scripts\mp_common\gametypes\globallogic;
// pausetimer / resumetimer for the match pause; #used by globallogic itself, so it is in
// every MP link set the line above is.
#using scripts\mp_common\gametypes\globallogic_utils;

#namespace gunfight_menu;

function private autoexec __init__system__()
{
    // preinit &__init__ (callbacks); postinit &mod_postinit - two snapshots that are only
    // readable BEFORE gametype_start. The postinit runs at run_post_systems
    // (callbacks_shared.gsc:1361), so before function_b9b7618() latches game.gamestarted
    // (the pre-match vs pre-round test, mod_periods) and before gameobjects::main()
    // (globallogic.gsc:5218) deletes the Domination flag entities as not-this-gametype. That
    // deletion is why an in-match read of flag_primary returns 0 on every map. Captured
    // there, cached in game., used every round (mod_dom_capture).
    system::register( #"gunfight_menu", &__init__, &mod_postinit, undefined, undefined );
}

function private __init__()
{
    callback::on_start_gametype( &mod_apply );
    callback::on_connect( &on_player_connect );
    callback::on_spawned( &mod_spawn_place );
    // Anti-stack net (F5b, 2026-09-18): right after the guard/engine placement, for EVERY spawn
    // path and every map - if a player lands on top of one already placed this round, fan them out
    // side-by-side onto clear floored ground. Map-agnostic backstop for any residual stacking
    // (too-few guard anchors, the engine handing the same start, the combined-arms map-centre pile).
    callback::on_spawned( &mod_spawn_antistack );
    // Separate handler on purpose (mod_spawn_place holds the spawn guard + host tools):
    // per-life movement state - speed scale after stock's loadout reset, the jump-boost
    // watcher - for EVERY player, bots included.
    callback::on_spawned( &mod_spawn_movement );
    // Vehicle mode (docs/notes/vehicle-mode.md): everyone spawns already riding. After the
    // movement handler so the rider's speed / oob / fall-damage state is in place first.
    callback::on_spawned( &mod_spawn_vehicle );

    // Fired by bot_difficulty::assign() on the bot after EVERY stock difficulty install -
    // join, reconnect at the round boundary, our own re-assign. Where the custom struct and
    // the passive flag land, so a bot never keeps a stock bundle we meant to replace.
    // The literal hashes to bot.gsc:81's #"hash_730d00ef91d71acf" (cracked 2026-09-12).
    callback::add_callback( #"bot_difficulty_assigned", &bot_on_difficulty_assigned );
}

// ═════════════════════════════════════════════════════════════════════════════
// SETTINGS — dvar-backed, so they survive rounds and matches
// ═════════════════════════════════════════════════════════════════════════════

function private cfg_team_size()     { return cfg_geti( #"gf_team_size", 4 ); }
function private cfg_spec_slots()    { return cfg_geti( #"gf_spec_slots", 2 ); }
function private cfg_timer_seconds() { return cfg_geti( #"gf_timer_seconds", 60 ); }
// "60s", or "inf" when the timer is off - shared by the state line and the compact
// header so neither ever reads "0s" for unlimited.
function private cfg_timer_label()   { secs = cfg_timer_seconds(); return secs > 0 ? ( secs + "s" ) : "inf"; }
function private cfg_prematch()      { return cfg_geti( #"gf_prematch", 15 ); }
function private cfg_preround()      { return cfg_geti( #"gf_preround", 7 ); }
function private cfg_loadout()       { return cfg_geti( #"gf_loadout", 0 ); }
function private cfg_customcac()     { return cfg_geti( #"gf_customcac", 0 ); }
function private cfg_profile()       { return cfg_geti( #"gf_profile", 1 ); }
// Loadout-pool camo (docs/notes/loadout-camo.md). -2 (default) = random each round, one roll
// per weapon that everyone shares. -3 = rolls per player-spawn. -1 = stock, the pool's own look.
// >= 0 = force that camo index on every pool weapon at every spawn. The random modes draw from
// gf_camo_pool: 0 = mastery + Pack-a-Punch (61-69, 116-121), 1 = every mapped index, 1-121;
// gf_camo_split 1 = primary and secondary roll separately, 0 = one roll covers both.
function private cfg_camo()          { return cfg_geti( #"gf_camo", -2 ); }
function private cfg_camo_pool()     { return cfg_geti( #"gf_camo_pool", 0 ); }
function private cfg_camo_split()    { return cfg_geti( #"gf_camo_split", 1 ); }
function private cfg_spyplane()      { return cfg_geti( #"gf_spyplane", 0 ); }
function private cfg_map_method()    { return cfg_geti( #"gf_map_method", 1 ); }
// ═════════════════════════════════════════════════════════════════════════════
// PACKED CONFIG STORE (dvar-pool budget, 2026-09-15). The 52 int config settings live in
// 9 chunk dvars gf_c0..gf_c8 (6 per chunk, SORTED key order) instead of 52 individual
// dvars - the GSC-VM dvar pool is only 4096 and heavy maps nearly fill it (dvar-pool-crash:
// error 0xa370b5b4). cfg_geti / cfg_seti are the ONLY accessors and every gf_* read/write
// was routed through them; a name NOT in the packed set (gf_cmd_*, gf_staged_*, gf_bot*,
// gf_fd_*, gf_hint_*, gf_say_hint_indent) falls back to a real getdvarint/setdvar, so nothing
// else changes. The app (gf_control.py) sorts the SAME 52 keys the SAME way and writes the
// SAME chunks, so order cannot drift; a short/absent chunk falls back to the per-key default.
// ═════════════════════════════════════════════════════════════════════════════
function private cfg_add( c, name, def )
{
    st = spawnstruct();
    st.n = name;
    st.d = def;
    c[ c.size ] = st;
    return c;
}

function private cfg_spec()
{
    if ( isdefined( game.gf_cfg_spec ) )
        return game.gf_cfg_spec;

    c = [];
    c = cfg_add( c, #"gf_autoswitch", 0 );
    c = cfg_add( c, #"gf_bot_diff_allies", -1 );
    c = cfg_add( c, #"gf_bot_diff_axis", -1 );
    c = cfg_add( c, #"gf_bot_passive", 0 );
    c = cfg_add( c, #"gf_camo", -2 );
    c = cfg_add( c, #"gf_camo_pool", 0 );
    c = cfg_add( c, #"gf_camo_split", 1 );
    c = cfg_add( c, #"gf_caster_probe", 1 );
    c = cfg_add( c, #"gf_census", 0 );
    c = cfg_add( c, #"gf_customcac", 0 );
    c = cfg_add( c, #"gf_dbg_assets", 0 );
    c = cfg_add( c, #"gf_dbg_families", 0 );
    c = cfg_add( c, #"gf_dbg_flags", 0 );
    c = cfg_add( c, #"gf_dbg_match", 0 );
    c = cfg_add( c, #"gf_dbg_spawn", 0 );
    c = cfg_add( c, #"gf_dbg_structs", 0 );
    c = cfg_add( c, #"gf_falldamage", 0 );
    c = cfg_add( c, #"gf_feed_lines", 14 );
    c = cfg_add( c, #"gf_fly_fast", 60 );
    c = cfg_add( c, #"gf_fly_speed", 20 );
    c = cfg_add( c, #"gf_gravity", 800 );
    c = cfg_add( c, #"gf_jump", -1 );
    c = cfg_add( c, #"gf_jump_boost", 0 );
    c = cfg_add( c, #"gf_loadout", 0 );
    c = cfg_add( c, #"gf_map_method", 1 );
    c = cfg_add( c, #"gf_menu_hspan", 4 );
    c = cfg_add( c, #"gf_menu_lines", 3 );
    c = cfg_add( c, #"gf_menu_region", 2 );
    c = cfg_add( c, #"gf_prematch", 15 );
    c = cfg_add( c, #"gf_preround", 7 );
    c = cfg_add( c, #"gf_profile", 1 );
    c = cfg_add( c, #"gf_roundlimit", -1 );
    c = cfg_add( c, #"gf_rounds_loadout", -1 );
    c = cfg_add( c, #"gf_roundwinlimit", -1 );
    c = cfg_add( c, #"gf_spawn_autospread", 2500 );
    c = cfg_add( c, #"gf_spawn_diag", 1 );
    c = cfg_add( c, #"gf_spawn_family", 8 );
    c = cfg_add( c, #"gf_spawn_gap", 1800 );
    c = cfg_add( c, #"gf_spawn_guard", 2 );
    c = cfg_add( c, #"gf_spawn_pick", 0 );
    c = cfg_add( c, #"gf_spec_slots", 2 );
    c = cfg_add( c, #"gf_speed", 100 );
    c = cfg_add( c, #"gf_spyplane", 0 );
    c = cfg_add( c, #"gf_strike", 0 );
    c = cfg_add( c, #"gf_switch_sides", 1 );
    c = cfg_add( c, #"gf_switch_wait", 0 );
    c = cfg_add( c, #"gf_team_size", 4 );
    c = cfg_add( c, #"gf_timer_seconds", 60 );
    c = cfg_add( c, #"gf_zone", 0 );
    c = cfg_add( c, #"gf_zone_capture", 5 );
    c = cfg_add( c, #"gf_zone_overtime", 20 );
    c = cfg_add( c, #"gf_zone_radius", 128 );
    game.gf_cfg_spec = c;
    game.gf_cfg_idx = [];

    for ( i = 0; i < c.size; i++ )
        game.gf_cfg_idx[ c[ i ].n ] = i;

    return c;
}

function private cfg_load()
{
    spec = cfg_spec();
    game.gf_cfg = [];

    for ( i = 0; i < spec.size; i++ )
    {
        chunk = i / 6;
        pos = i % 6;
        parts = strtok( getdvarstring( "gf_c" + int( chunk ), "" ), "," );

        if ( isdefined( parts ) && pos < parts.size && parts[ pos ] != "" )
            game.gf_cfg[ i ] = int( parts[ pos ] );
        else
            game.gf_cfg[ i ] = spec[ i ].d;
    }
}

function private cfg_geti( name, def )
{
    cfg_spec();

    if ( !isdefined( game.gf_cfg_idx[ name ] ) )
        return getdvarint( name, def );

    if ( !isdefined( game.gf_cfg ) )
        cfg_load();

    return game.gf_cfg[ game.gf_cfg_idx[ name ] ];
}

function private cfg_seti( name, val )
{
    cfg_spec();

    if ( !isdefined( game.gf_cfg_idx[ name ] ) )
    {
        setdvar( name, val );
        return;
    }

    if ( !isdefined( game.gf_cfg ) )
        cfg_load();

    idx = game.gf_cfg_idx[ name ];
    game.gf_cfg[ idx ] = int( val );
    cfg_write_chunk( idx / 6 );
}

function private cfg_write_chunk( chunk )
{
    spec = cfg_spec();
    out = "";

    for ( pos = 0; pos < 6; pos++ )
    {
        i = int( chunk ) * 6 + pos;

        if ( i >= spec.size )
            break;

        out += ( pos > 0 ? "," : "" ) + game.gf_cfg[ i ];
    }

    setdvar( "gf_c" + int( chunk ), out );
}

function private cfg_switch_wait()   { return cfg_geti( #"gf_switch_wait", 0 ); }  // 0 = immediate switch (cp form); klaze default 2026-09-15

// ── Write a gametype setting ONLY when it actually changes ────────────────────
// The engine FAST-RESTARTS the match when setgametypesetting() changes certain keys
// (maxplayers + the round limits, measured 2026-09-15). mod_apply re-asserts the whole
// blob every round (a Gunfight round is a map_restart, so on_start_gametype re-fires),
// and cmd_apply_live ("Apply now") re-asserts periods/bots on every apply - so a bare
// setgametypesetting fires a reload every time even when the value did not change. Since
// the packed config store (2026-09-16) makes the app resend a whole 6-field chunk when any
// one field in it changes, an unrelated Apply (e.g. the timer, which shares a chunk with
// team size) was re-writing a restart key at its old value and reloading the match.
// getgametypesetting returns the live value (stock compares it the same way,
// globallogic.gsc updategametypedvars :3447), so skip the write when it already matches:
// a redundant assert is now a no-op, and only a genuine change reloads. This is the single
// choke point - every setgametypesetting in this file goes through it.
function private gts_set( key, value )
{
    if ( getgametypesetting( key ) !== value )
        setgametypesetting( key, value );
}
function private cfg_autoswitch()    { return cfg_geti( #"gf_autoswitch", 0 ); }
// ⚠ Clamped: menu_think primes `for(i=0;i<lines+1)` blanks, so a garbage-huge value here spins
// the render and freezes the game (measured 2026-09-14). Bound both row counts to a sane range.
function private cfg_clamp_lines( n ) { if ( n < 1 ) return 1; if ( n > 24 ) return 24; return n; }
function private cfg_menu_lines()    { return cfg_clamp_lines( cfg_geti( #"gf_menu_lines", 3 ) ); }
function private cfg_menu_region()   { return cfg_geti( #"gf_menu_region", 2 ); }
function private cfg_menu_hspan()    { return cfg_geti( #"gf_menu_hspan", 4 ); }
function private cfg_feed_lines()    { return cfg_clamp_lines( cfg_geti( #"gf_feed_lines", 14 ) ); }
function private cfg_hint_lines()    { return cfg_geti( #"gf_hint_lines", 8 ); }
function private cfg_hint_newlines() { return cfg_geti( #"gf_hint_newlines", 0 ); }

// #spawn_guard (ported from gunfight_mod, adapted to dvars). Default OFF - test solo first.
function private cfg_spawn_guard()     { return cfg_geti( #"gf_spawn_guard", 2 ); }
function private cfg_spawn_diag()      { return cfg_geti( #"gf_spawn_diag", 1 ); }
// Anti-stack net, default ON. NON-packed dvar on purpose (cfg_geti falls through to getdvarint) -
// keeps it out of the packed chunk store, so no 3-file lockstep / config_scan change is needed.
function private cfg_spawn_antistack() { return cfg_geti( #"gf_spawn_antistack", 1 ); }
function private cfg_spawn_autospread(){ return cfg_geti( #"gf_spawn_autospread", 2500 ); }
function private cfg_spawn_gap()       { return cfg_geti( #"gf_spawn_gap", 1800 ); }
function private cfg_spawn_pick()      { return cfg_geti( #"gf_spawn_pick", 0 ); }
function private cfg_strike()          { return cfg_geti( #"gf_strike", 0 ); }
function private cfg_caster_probe()   { return cfg_geti( #"gf_caster_probe", 1 ); }

// Overtime zone (docs/notes/overtime-zone.md). Default OFF: a zone is a round-start
// entity build, and the one failure that matters is fatal (a centre no trigger contains
// is a map error -> abort_level). mod_zone_synthesize backs out before that can happen.
function private cfg_zone()          { return cfg_geti( #"gf_zone", 0 ); }
function private cfg_zone_overtime() { return cfg_geti( #"gf_zone_overtime", 20 ); }
function private cfg_zone_capture()  { return cfg_geti( #"gf_zone_capture", 5 ); }
function private cfg_zone_radius()   { return cfg_geti( #"gf_zone_radius", 128 ); }

// Match-length knobs. Sentinel -1 = leave the lobby's value untouched (only an explicit
// menu pick asserts control). Keys verified against gunfight.gsc / globallogic.gsc.
function private cfg_roundwinlimit()  { return cfg_geti( #"gf_roundwinlimit", -1 ); }
function private cfg_roundlimit()     { return cfg_geti( #"gf_roundlimit", -1 ); }
function private cfg_rounds_loadout() { return cfg_geti( #"gf_rounds_loadout", -1 ); }
function private cfg_switch_sides()   { return cfg_geti( #"gf_switch_sides", 1 ); }

// Movement. bg_gravity is engine-consumed in MP (docs/notes/mp-dvars.md, verified
// 2026-09-07; stock 800). Jump uses the setjumpheight BUILTIN - the jump_height DVAR
// is a campaign/ZM dead end in MP - and -1 leaves the engine default untouched.
function private cfg_gravity()  { return cfg_geti( #"gf_gravity", 800 ); }
function private cfg_jump()     { return cfg_geti( #"gf_jump", -1 ); }
function private cfg_jump_boost() { return cfg_geti( #"gf_jump_boost", 0 ); }
function private cfg_falldamage() { return cfg_geti( #"gf_falldamage", 0 ); }
function private cfg_oob()        { return cfg_geti( #"gf_oob", 1 ); }          // 1 = OOB disabled (default)
function private cfg_speed()      { return cfg_geti( #"gf_speed", 100 ); }
function private cfg_fly_speed()  { return cfg_geti( #"gf_fly_speed", 20 ); }
function private cfg_fly_fast()   { return cfg_geti( #"gf_fly_fast", 60 ); }

// Bots (docs/notes/bots.md). Difficulty per side: -1 leave the lobby's row alone, 0-3 the
// stock levels, 4 = the custom struct built from the knobs below. Knob defaults are the
// "Veteran+" profile - past the stock ceiling on every axis, since that is the one thing
// the lobby cannot already give.
function private cfg_bot_diff_allies() { return cfg_geti( #"gf_bot_diff_allies", -1 ); }
function private cfg_bot_diff_axis()   { return cfg_geti( #"gf_bot_diff_axis", -1 ); }
// The 15 numeric bot knobs are packed into ONE string dvar gf_bot ("hit,head,react,..."),
// not 15 dvars - the GSC-VM dvar store is only 4096 and heavy maps nearly fill it
// (dvar-pool-crash: error 0xa370b5b4 "Can't register more dvar"). Order is fixed; see
// bot_num indices. passive/diff_allies/diff_axis stay separate (they are menu-highlight groups).
function private bot_num( idx, def )
{
    // Split across gf_bot (fields 0-7) and gf_bot2 (8-14): a single `set gf_bot <all 15>` is
    // ~54 bytes, and the bridge command slot only safely restores 48 - a longer `set` corrupts
    // adjacent game memory and hard-crashes (klaze 2026-09-15). Each half's `set` is <40 bytes.
    if ( idx < 8 )
        parts = strtok( getdvarstring( #"gf_bot", "100,50,100,1000,100,90,100,100" ), "," );
    else
    {
        parts = strtok( getdvarstring( #"gf_bot2", "1,1,1,1,1,1,1" ), "," );
        idx = idx - 8;
    }
    if ( isdefined( parts ) && idx < parts.size && parts[ idx ] != "" )
        return int( parts[ idx ] );
    return def;
}

// Write one packed field of gf_bot without disturbing the others (knob cycle).
function private bot_set_field( idx, val )
{
    if ( idx < 8 )
    {
        parts = strtok( getdvarstring( #"gf_bot", "100,50,100,1000,100,90,100,100" ), "," );
        cfg_seti( #"gf_bot", bot_join( parts, 8, 0, idx, val ) );
    }
    else
    {
        parts = strtok( getdvarstring( #"gf_bot2", "1,1,1,1,1,1,1" ), "," );
        cfg_seti( #"gf_bot2", bot_join( parts, 7, 8, idx, val ) );
    }
}

function private bot_join( parts, count, base, idx, val )
{
    out = "";
    for ( i = 0; i < count; i++ )
    {
        v = ( ( base + i ) == idx ) ? ( "" + val ) : ( ( isdefined( parts ) && i < parts.size && parts[ i ] != "" ) ? parts[ i ] : "0" );
        out += ( i > 0 ? "," : "" ) + v;
    }
    return out;
}

function private cfg_bot_hit()         { return bot_num( 0, 100 ); }
function private cfg_bot_head()        { return bot_num( 1, 50 ); }
function private cfg_bot_react()       { return bot_num( 2, 100 ); }
function private cfg_bot_fire()        { return bot_num( 3, 1000 ); }
function private cfg_bot_hip()         { return bot_num( 4, 100 ); }
function private cfg_bot_far()         { return bot_num( 5, 90 ); }
function private cfg_bot_semi()        { return bot_num( 6, 100 ); }
function private cfg_bot_burst()       { return bot_num( 7, 100 ); }
function private cfg_bot_moveshoot()   { return bot_num( 8, 1 ); }
function private cfg_bot_fastaim()     { return bot_num( 9, 1 ); }
function private cfg_bot_sprint()      { return bot_num( 10, 1 ); }
function private cfg_bot_melee()       { return bot_num( 11, 1 ); }
function private cfg_bot_prone()       { return bot_num( 12, 1 ); }
function private cfg_bot_slide()       { return bot_num( 13, 1 ); }
function private cfg_bot_crouch()      { return bot_num( 14, 1 ); }

function private cfg_bot_passive()     { return cfg_geti( #"gf_bot_passive", 0 ); }

// ── Pre-register ─────────────────────────────────────────────────────────────
// The cfg_* readers above need no dvar to exist - getdvarint( name, default ) - so until
// the host touches a setting in the menu, most gf_* dvars are not in the VM dvar store at
// all. This registers every gf_* dvar with its default at each match start, but ONLY if it
// is absent: an unconditional setdvar would reset every host setting and undo the whole
// "settings are dvars" design. Absent = getdvarstring returns the sentinel "" - an int
// dvar that exists reads back as digits, never as "". The string dvars (gf_cmd_map/gametype,
// gf_staged_*) have "" as their idle value, so the same guard registers a missing one and
// leaves a queued command alone.
// ⚠ This is NOT what makes the Windows app work. bocw-7f confirmed 2026-09-12 that an
//   external WriteProcessMemory cannot reach these: getdvarint reads the GSC VM's own
//   string-interned dvar store, not the engine's Dvar_FindVar table, so an outside writer
//   pokes the wrong copy. Only in-VM setdvar (this menu) applies gf_* at all; an external
//   control app needs in-context code (a cwpatch-style DLL calling setdvar in-thread,
//   klaze's DLL domain), and pre-registering keeps the names present for that path. See
//   tools/gf-control (hud-and-control-app / dvar-write RE state).
// ⚠ Keep the defaults in step with the cfg_* lines above and the gf_cmd_* poller.
function private dvar_reg( name, default_value )
{
    if ( getdvarstring( name, "" ) == "" )
        setdvar( name, default_value );
}

function private dvars_register()
{
    // ⚠ NOT CALLED as of 2026-09-13 - the call in mod_apply is commented out because registering
    // this whole batch at once overflows the GSC-VM dvar store and fatally crashes the game
    // ("Can't register more dvar"). Do NOT add more dvar_reg lines here expecting them to run, and
    // do NOT re-enable the call without a plan for the store cap. Kept for reference. See memory
    // dvar-pool-crash. (dvar_reg only sets when absent, so re-enabling would still overflow.)
    dvar_reg( #"gf_team_size", 4 );
    dvar_reg( #"gf_timer_seconds", 60 );
    dvar_reg( #"gf_prematch", 15 );
    dvar_reg( #"gf_preround", 7 );
    dvar_reg( #"gf_loadout", 0 );
    dvar_reg( #"gf_customcac", 0 );
    dvar_reg( #"gf_camo", -2 );
    dvar_reg( #"gf_camo_pool", 0 );
    dvar_reg( #"gf_camo_split", 1 );
    dvar_reg( #"gf_spyplane", 0 );
    dvar_reg( #"gf_map_method", 1 );
    dvar_reg( #"gf_switch_wait", 0 );
    dvar_reg( #"gf_autoswitch", 0 );
    dvar_reg( #"gf_menu_lines", 3 );
    dvar_reg( #"gf_menu_region", 2 );
    dvar_reg( #"gf_feed_lines", 14 );
    dvar_reg( #"gf_spawn_guard", 0 );
    dvar_reg( #"gf_spawn_autospread", 2500 );
    dvar_reg( #"gf_caster_probe", 1 );
    dvar_reg( #"gf_menu_hspan", 4 );
    dvar_reg( #"gf_hint_lines", 8 );
    dvar_reg( #"gf_hint_newlines", 0 );
    dvar_reg( #"gf_spawn_diag", 1 );
    dvar_reg( #"gf_zone", 0 );
    dvar_reg( #"gf_zone_overtime", 20 );
    dvar_reg( #"gf_zone_capture", 5 );
    dvar_reg( #"gf_zone_radius", 128 );
    dvar_reg( #"gf_roundwinlimit", -1 );
    dvar_reg( #"gf_roundlimit", -1 );
    dvar_reg( #"gf_rounds_loadout", -1 );
    dvar_reg( #"gf_switch_sides", 1 );
    dvar_reg( #"gf_gravity", 800 );
    dvar_reg( #"gf_jump", -1 );
    dvar_reg( #"gf_jump_boost", 0 );
    dvar_reg( #"gf_falldamage", 0 );
    dvar_reg( #"gf_speed", 100 );
    dvar_reg( #"gf_fly_speed", 20 );
    dvar_reg( #"gf_fly_fast", 60 );
    // The engine's own fall-damage thresholds, captured the FIRST time this runs in the
    // process - before mod_movement ever writes them - so "fall damage: stock" can put the
    // real numbers back. Guarded like everything here: never overwritten once set.
    dvar_reg( #"gf_fd_min_stock", getdvarint( #"bg_falldamageminheight", 128 ) );
    dvar_reg( #"gf_fd_max_stock", getdvarint( #"bg_falldamagemaxheight", 300 ) );

    // Bots (docs/notes/bots.md). Defaults = the cfg_bot_* lines above.
    dvar_reg( #"gf_bot_diff_allies", -1 );
    dvar_reg( #"gf_bot_diff_axis", -1 );
    dvar_reg( #"gf_bot_passive", 0 );

    // The app's command channel (cmd_dispatch) and the stage markers (stage_mark).
    dvar_reg( #"gf_cmd_go", 0 );
    dvar_reg( #"gf_cmd_stage", 0 );
    dvar_reg( #"gf_cmd_say", "" );
    dvar_reg( #"gf_cmd_map", "" );
    dvar_reg( #"gf_cmd_gametype", "" );
    dvar_reg( #"gf_staged_map", "" );
    dvar_reg( #"gf_staged_gt", "" );
}

// Never ask the session for more clients than it has slots for. com_maxclients is
// read-only from script but READABLE - 10 in a 3v3 lobby, 8 in a normal one - so the
// bound is measured live rather than assumed. Copied from gunfight_mod.
// The maxplayers write: team size x 2 PLUS spectator slots (gf_spec_slots, default 2 - the
// game's own caster allowance), capped at the client budget. klaze 2026-09-15: "spectators
// seem to count towards the limit - 4v4 with one spectator makes it 3v4 bot fill". With the
// budget at 12 (a TDM-config lobby) the only cap left at 9 clients is maxplayers = 8, so the
// spectator is being counted against it; adding the slots lifts it to 10.
function private maxplayers_value( per_side )
{
    mp = per_side * 2 + cfg_spec_slots();
    budget = getdvarint( #"com_maxclients", 0 );
    if ( budget > 0 && mp > budget )
        mp = budget;
    return mp;
}

function private clamp_team_size( per_side )
{
    budget = getdvarint( #"com_maxclients", 0 );

    if ( budget <= 0 )
    {
        return per_side;
    }

    ceiling = int( budget / 2 );

    if ( per_side > ceiling )
    {
        return ceiling;
    }

    return per_side;
}

// ═════════════════════════════════════════════════════════════════════════════
// THE MOD — gunfight_mod's verified fixes, applied every on_start_gametype
// ═════════════════════════════════════════════════════════════════════════════

// The menu can now switch GAMETYPE, so it gets linked into TDM/DM/etc. matches too.
// Everything below the gate is Gunfight's and would wreck another mode: ontimelimit
// becomes the health decision, gettimelimit clamps the match to the Gunfight timer,
// the HUD latch says "no respawns left". Only the menu itself runs everywhere.
function private mod_is_gunfight()
{
    gt = tolower( getdvarstring( #"g_gametype", "" ) );
    return gt == "gunfight" || gt == "gunfight_3v3";
}

function private mod_apply()
{
    cfg_load();
    // ⚠ dvars_register() DISABLED 2026-09-13 (bocw-e1). Force-registering all 72 gf_* dvars at
    // match start overflows the GSC-VM dvar store -> FATAL "Can't register more dvar" and the game
    // crashes (klaze's crash dump named it: err 0xa370b5b4, offending-dvar hash 1e61d7c5cd9329f7 =
    // gf_staged_gt, the 72nd/last dvar_reg). The pre-register's ONLY purpose was dead route A (an
    // external Dvar_FindVar seeing gf_*); the mod needs none of it - every cfg_* reader uses
    // getdvarint(name, default) and every menu write uses setdvar (auto-registers ON DEMAND, one at
    // a time, only for settings the host actually touches). Cosmetic only: the '*' current-value
    // marker no longer shows a setting's default until it is first touched. See memory dvar-pool-crash.
    // dvars_register();

    // Settings census: snapshot the blob AS LAUNCHED before anything below writes to it
    // (once per gametype|map per match), and start the centre-screen readout when asked
    // (gf_census 1). Every mode, before the gate - a TDM match's blob is a reference too.
    census_snapshot();
    if ( debug_feed_any() )
        debug_feed_start();
    level thread mapdata_publish();     // GAME->APP map census (mapdata_scan.py)
    level thread config_publish();     // GAME->APP live config readback (config_scan.py -> app "Load current")

    // Movement mods apply in EVERY gametype, so they run before the Gunfight gate.
    mod_movement();

    // Vehicle mode: resolve this map's ride for the round (every gametype) and tell the host.
    veh_mode_announce();
    // Every vehicle this menu spawned is deleted the moment the round ends, before map_restart
    // (the 2026-09-18 Miami round-transition crash had a page-spawned heli standing in the ground).
    level thread veh_round_end_sweep();

    // Bots too: difficulty is a stock per-team gametype setting in every mode, and the
    // bots re-init at the round boundary (bot.gsc:239 on_player_connect -> assign), so
    // re-asserting the setting each round is what keeps a pick from silently reverting.
    mod_bots();

    // Pre-match / pre-round countdowns - every mode too, for the same reason as the two above.
    mod_periods();

    // Auto-switch to Gunfight: if enabled and this match is NOT Gunfight, do the one proven
    // in-match session switch on the host, once, after he has spawned. Runs before the gate.
    mod_autoswitch();

    if ( !mod_is_gunfight() )
    {
        mod_menu_restart_all();
        return;
    }

    // ✅ Necessary, not defensive: level.zones is assigned only on setupzones()'s
    // success path (gunfight.gsc:907) and stays undefined for the whole match on
    // every custom-lobby map, stock ones included.
    if ( !isdefined( level.zones ) )
    {
        level.zones = [];
    }

    // Overtime zone. Built HERE because the on_start_gametype callbacks fire BEFORE
    // [[ level.onstartgametype ]]() (globallogic.gsc:5536-5537) - so gunfight's own
    // setupzones() (gunfight.gsc:827) finds our entities and builds the real zone,
    // overtime(), HUD timer, VO and capture included. The callback is threaded
    // (util::_single_thread) but runs to its first wait before the caller resumes, and
    // nothing above this line waits. docs/notes/overtime-zone.md
    have_zone = 0;
    if ( cfg_zone() )
        have_zone = mod_zone_synthesize();

    if ( have_zone )
    {
        // Stock ontimelimit -> overtime() stays installed (gunfight.gsc:58). It reads
        // these two at main() from gametype settings whose private-match values are
        // unknown, so assert ours. Seconds, both (overtime :951, set_use_time x1000).
        level.extratime = cfg_zone_overtime();
        level.capturetime = cfg_zone_capture();
    }
    else
    {
        // THE load-bearing fix: reach the health decision without the overtime() thread
        // that dereferences level.zones[0] and dies.
        level.ontimelimit = &mod_ontimelimit;
    }

    // Round timer. gettimelimit() returns MINUTES, range [0, 1440]; a carry resets the
    // rules-menu value, and this re-applying per round is what makes it stick.
    level.gettimelimit = &mod_gettimelimit;

    // Cache the round's base limit HERE (round start). mod_gettimelimit returns this cache,
    // not a live cfg read - so changing gf_timer_seconds mid-round (the app's "Next round" =
    // config only) no longer ends the current round the instant the new limit drops below the
    // elapsed time (klaze 2026-09-15: "next round instantly restarts"). It applies at the NEXT
    // round when this re-caches. "Apply now" (cmd_apply_live) refreshes the cache on purpose.
    level.gf_timelimit_cache = cfg_timer_seconds() / 60;

    // Team size. maxplayers = 2 x per side; L6 measured it survives the round boundary,
    // so this is belt-and-braces against the CARRY, which re-initialises settings.
    gts_set( #"maxplayers", maxplayers_value( clamp_team_size( cfg_team_size() ) ) );

    // ── Mode remnants after a session switch ─────────────────────────────────
    // Gametype settings SURVIVE switchmap_load (LS6, docs/notes/session-switch.md), so a
    // Gunfight reached from TDM runs on TDM's settings blob. The remnant that shows first is
    // disableCustomCAC: gunfight.gsc:102-109 runs a CUSTOM-CLASSES branch whenever it is not 1
    // (class selection on, perks on, level.givecustomloadout = undefined - no fixed loadouts).
    // The real Gunfight mode's blob has it at 1; TDM's does not - hence "Gunfight header, MODE:
    // Team Deathmatch, custom classes" (klaze's screenshot, 2026-09-13). Fixable HERE because
    // this callback runs AFTER globallogic copied the settings into level vars
    // (function_b9b7618, globallogic.gsc:5159-5160) and BEFORE gunfight's onstartgametype
    // reads those vars (:5536-5537) - so both the setting and the level var are written.
    // ⚠ ONLY disablecustomcac is asserted. gunfight.gsc:102 keys the whole fixed-loadout
    // path off THIS one setting (== 1 -> givecustomloadout stays &givecustomloadout, the
    // table main() built at :80-89 -> fixed loadouts; != 1 -> custom classes), so this is
    // the sufficient and documented fix. disableClassSelection WAS deliberately not forced
    // (its value was inferred; forcing 1 when the blob wants 0 changes the spawn path,
    // globallogic_ui.gsc:305). 2026-09-14: the launch census READ it as 1 in the real
    // Gunfight blob (column A), so mode_profile_gunfight below asserts it with customcac.
    // gf_customcac 1 = the rules-menu "Custom Classes" row (disable_cac.json), on purpose.
    dcc = cfg_customcac() ? 0 : 1;
    gts_set( #"disablecustomcac", dcc );
    level.disablecustomcac = dcc;

    // The rest of the real Gunfight blob (column A, measured 2026-09-14) - settings AND the
    // level vars globallogic already copied, so a Case-B hybrid launch plays as real Gunfight
    // from THIS round. ⚠ Built 2026-09-14, never run. See mode_profile_gunfight.
    mode_profile_gunfight( 1 );

    // Loadout set and spy plane - written each match from the dvars (mod_apply is once
    // per match). Harmless when unchanged. The loadout LATCH (game.var_96a8ff4a) is
    // cleared only by the menu action, once, so a change takes effect without re-randomising.
    gts_set( #"gunfightloadoutindex", cfg_loadout() );
    gts_set( #"gunfightspyplane", cfg_spyplane() );

    // Match-length knobs - sentinel -1 leaves the lobby value alone. Re-applied each match
    // like the timer/team so a menu pick self-heals across the round boundary and a carry.
    if ( cfg_roundwinlimit() >= 0 )
        gts_set( #"roundwinlimit", cfg_roundwinlimit() );
    if ( cfg_roundlimit() >= 0 )
        gts_set( #"roundlimit", cfg_roundlimit() );
    // Loadout rotation AND side switch, both driven by this one setting: gunfight.gsc
    // onendround rotates the loadout and calls on_round_switch() (the side swap) inside a
    // single check on level.gunfightroundsperloadout. TWO reasons a menu pick did nothing:
    //  1. main() (gametype_init) copied the setting into level.gunfightroundsperloadout
    //     BEFORE this callback runs, and onendround reads the LEVEL var, not the setting -
    //     so setgametypesetting alone is read too late. Set the live level var too.
    //  2. on_round_switch only toggles game.switchedsides when level.var_d1455682.switchsides
    //     is set (the gametype bundle's flag). Force it on so the swap actually happens.
    //  3. (2026-09-14) "stock" (-1) meant "leave the lobby value alone" - which in a Case-B
    //     launch is TDM's blob: gunfightroundsperloadout=0 (column T), i.e. NEVER rotate the
    //     loadout or swap sides. The real Gunfight blob has 2 (column A). So stock now means
    //     A's 2, the same way the profile treats roundwinlimit/roundlimit.
    rpl = ( cfg_rounds_loadout() >= 0 ) ? cfg_rounds_loadout() : 2;
    if ( cfg_rounds_loadout() >= 0 || ( cfg_profile() && profile_is_hybrid() ) )
    {
        gts_set( #"gunfightroundsperloadout", rpl );
        level.gunfightroundsperloadout = rpl;
        if ( isdefined( level.var_d1455682 ) )
            level.var_d1455682.switchsides = 1;
    }

    // ── Side switch: own it ──────────────────────────────────────────────────
    // Two stock paths reach gametype::on_round_switch (gametype.gsc:70-84), which flips
    // game.switchedsides ONLY if the gametype bundle's switchsides flag is set (the bundle
    // comes from a builtin; its contents are not in the dump):
    //   A. gunfight.gsc:388-398 - every gunfightroundsperloadout rounds, coupled with the
    //      loadout rotation, from onendround (called at globallogic.gsc:2598);
    //   B. display_transition.gsc:507-527 checkroundswitch() - every level.roundswitch
    //      rounds (the generic `roundswitch` gametype setting, util.gsc:735-740), reached
    //      from display_round_end (globallogic.gsc:2605) - AFTER A, same round end.
    // Both firing on one boundary flips the flag twice = no visible swap while the loadout
    // still rotates; which boundaries collide depends on the blob's roundswitch (TDM's in a
    // hybrid launch), so it looks random - klaze's "rotates the loadouts but does not
    // switch sides, not sure if it's map based" (2026-09-13). So: force the gate on and
    // silence B (level.roundswitch is the level var checkroundswitch reads; it was copied
    // from the setting at init and nothing rewrites it), leaving only Gunfight's own coupled
    // path - one flip per rotation. gf_switch_sides 0 puts stock back for comparison.
    if ( cfg_switch_sides() )
    {
        if ( isdefined( level.var_d1455682 ) )
            level.var_d1455682.switchsides = 1;
        level.roundswitch = 0;
    }

    // With a zone, stock onstartgametype() runs past :121 and does its own presentation
    // tail (music, noRespawnsLeft, round_start) - replaying it would fire round_start twice.
    if ( !have_zone )
        mod_presentation_fixups();

    // Crossroads: keep the Strike layout under Gunfight (renames the entities the map's
    // on_game_playing would delete; must run before that callback - it does, this is
    // on_start_gametype). Also yields the area the guard builds inside. No-op elsewhere.
    mod_layout_keep();

    // #spawn_guard: rebuild the central-spawn anchors each round (level is torn down per
    // round) and install the pre-spawn override (path 1 of spawning_shared onspawnplayer).
    // Off = hook removed, stock spawns. docs/notes/spawn-system.md
    if ( cfg_spawn_guard() )
    {
        mod_spawn_build();
        level.var_cda5136b = &mod_spawn_override;
    }
    else
    {
        level.var_cda5136b = undefined;
    }

    mod_menu_restart_all();
}

// Belt and braces for the menu across round boundaries: the Atian Menu's own
// loop survives rounds in klaze's hands (game_ended fires once, at match end -
// globallogic.gsc:2374), but level is rebuilt per round and this costs nothing.
// menu_think endons on gfmenu_restart, so an old loop dies before a new one runs.
function private mod_menu_restart_all()
{
    foreach ( player in getplayers() )
    {
        if ( player ishost() && isdefined( player.gfmenu ) )
        {
            player thread menu_restart();
        }
    }
}

// The health decision, reached WITHOUT importing gunfight.gsc. mod_apply installs this
// only in a Gunfight match, but the menu now also links into TDM for the gametype switch,
// where a gunfight:: import is a fatal link error. globallogic::function_a3e3bd39 is
// exactly what gunfight::endround threaded (score + round::set_winner + end_round), and
// globallogic loads in every MP match. Overtime is dropped on purpose: it is the crashing
// path this fix exists to avoid (level.zones[0] on an undefined array), and the design
// skips it regardless of this (docs/notes/gunfight-findings.md - "overtime is absent, and
// that is correct").
// bg_gravity: verified engine-consumed in MP. setjumpheight: a real builtin, distinct
// from the dead jump_height dvar - UNTESTED here, so it only fires when the host picks
// a value (sentinel -1 = leave the engine default). Both re-asserted each round so a
// menu pick self-heals across the round boundary and a map switch.
function private mod_movement()
{
    setdvar( #"bg_gravity", cfg_gravity() );

    if ( cfg_jump() >= 0 )
        setjumpheight( cfg_jump() );

    mod_falldamage_apply();
    mod_oob_apply_all();
}

// ── Out of bounds (gf_oob, default OFF = disabled) ───────────────────────────
// oob.gsc drives the whole "restricted area" experience from one entry point, enter_oob
// (:660): it is reached from the trigger_out_of_bounds callback (:603) and the vehicle
// airspace loop (:269), and BOTH return first when function_65b20() (:703) sees
// self.oobdisabled - which is what the registered value disable_oob sets (:81 -> :952
// disableplayeroob: resetoobtimer + oobdisabled = 1). No enter_oob = no "out_of_bounds"
// clientfield (the HUD warning + screen effect, :832), no watchforleave (the countdown,
// :881) and no killentity (:840). Setting it while a player is already out runs
// resetoobtimer (:547): HUD cleared, oob_exit notified, the watchers end. Layered with the
// fly mode's own gf_fly layer (values_shared.gsc:275 - a reset only drops its own id).
// ⚠ Not covered: the territory in-bounds volumes (oob.gsc:138, territory.gsc:151) - they call
// enter_oob without the check. Fireteam's own gametype uses those; 6v6 / Gunfight maps
// ship trigger_out_of_bounds.
function private mod_oob_apply()
{
    if ( !isplayer( self ) )
        return;

    if ( cfg_oob() )
        self val::set( #"gf_oob", "disable_oob", 1 );
    else
        self val::reset( #"gf_oob", "disable_oob" );
}

function private mod_oob_apply_all()
{
    foreach ( player in getplayers() )
        player mod_oob_apply();
}

function private act_oob( item, value )
{
    cfg_seti( #"gf_oob", value );
    mod_oob_apply_all();
    self menu_say( value ? "^2out of bounds OFF - no warning, no death (everyone)" : "^2out of bounds: stock" );
    return true;
}

// Fall damage on/off. bg_falldamageminheight / maxheight are the engine pair the campaign
// and Zombies "oldschool" mode raise (cp_common globallogic.gsc:184-185), same bg_ family
// as the verified bg_gravity. Off = both thresholds beyond any map, so a boosted jump or a
// fly-mode drop lands clean. Stock = the values captured at first run (see the guarded
// dvar_reg at the top of this function - relocated here from the disabled dvars_register).
function private mod_falldamage_apply()
{
    // Capture the engine's stock fall-damage thresholds ONCE, before we ever override them.
    // Relocated here 2026-09-13 from the now-disabled dvars_register (the 72-dvar batch overflowed
    // the GSC-VM dvar store - see memory dvar-pool-crash). dvar_reg is guarded, so this fires only
    // on the first apply of a launch, when bg_falldamage* are still pristine; this function is the
    // ONLY writer of those dvars, so the captured value is identical to what dvars_register saw.
    dvar_reg( #"gf_fd_min_stock", getdvarint( #"bg_falldamageminheight", 128 ) );
    dvar_reg( #"gf_fd_max_stock", getdvarint( #"bg_falldamagemaxheight", 300 ) );

    if ( cfg_falldamage() )
    {
        setdvar( #"bg_falldamageminheight", cfg_geti( #"gf_fd_min_stock", 128 ) );
        setdvar( #"bg_falldamagemaxheight", cfg_geti( #"gf_fd_max_stock", 300 ) );
    }
    else
    {
        setdvar( #"bg_falldamageminheight", 100000 );
        setdvar( #"bg_falldamagemaxheight", 200000 );
    }

    // The hard way too (klaze 2026-09-15: "fall damage isn't always off and I'm not touching
    // it"). The dvars are what the engine consults, but something re-applies the stock
    // thresholds on some rounds. So the script-side damage gate as well: level.onplayerdamage
    // (player_damage.gsc:1482) - returning 0 makes modify_player_damage return undefined, and
    // :139 treats undefined damage as no damage, stock's own path. Installed only where stock
    // left the default (&globallogic::blank); VIP/OIC/SAS/Prop own theirs and keep them.
    if ( level.onplayerdamage == &globallogic::blank || level.onplayerdamage == &mod_onplayerdamage )
        level.onplayerdamage = &mod_onplayerdamage;
}

function private mod_onplayerdamage( einflictor, eattacker, idamage, idflags, smeansofdeath, weapon, vpoint, vdir, shitloc, psoffsettime )
{
    if ( !cfg_falldamage() && isdefined( smeansofdeath ) && smeansofdeath == "MOD_FALLING" )
        return 0;

    return undefined;
}

// Per-life movement state, every player (on_spawned fires after give_loadout, which is
// where stock resets the speed scale - globallogic_spawn.gsc:637 vs :758).
function private mod_spawn_movement()
{
    if ( !isplayer( self ) )
        return;

    self speed_apply();
    self thread jump_boost_think();

    // Fall damage off, the engine-native way (2026-09-15): specialty_fallheight is the engine
    // perk behind "no fall damage" - Infected grants it to the infected (infect.gsc:87),
    // Zombies Turned sets/unsets it (zm_turned.gsc:149/:228); no CW loadout perk exposes it.
    // Granted here, after give_loadout has cleared and re-applied the loadout's perks
    // (globallogic_spawn.gsc:637 vs this callback at :758), so it survives the spawn. The
    // bg_falldamage* dvars and the onplayerdamage gate stay as belt-and-braces.
    if ( !cfg_falldamage() )
        self setperk( #"specialty_fallheight" );
    else if ( self hasperk( #"specialty_fallheight" ) )
        self unsetperk( #"specialty_fallheight" );

    // Out of bounds: stock val::nuke()s every disable_oob layer at :612, before this
    // callback (:758) - so the flag is re-set here, every life, for every player.
    self mod_oob_apply();
}

// gf_speed percent -> setmovespeedscale, on top of the loadout's own modifier exactly the
// way stock composes it (player_loadout.gsc:1883).
function private speed_apply()
{
    base = isdefined( self.movementspeedmodifier ) ? self.movementspeedmodifier : 1;
    pct = isdefined( self.gf_speed_pct ) ? self.gf_speed_pct : cfg_speed();   // per-client override (Players page)
    self setmovespeedscale( base * pct / 100 );
}

function private speed_apply_all()
{
    foreach ( player in getplayers() )
    {
        if ( isalive( player ) )
            player speed_apply();
    }
}

// Takeoff detector: on the ground last frame, airborne and rising now, jump held, not a
// mantle -> add gf_jump_boost upward. One shot per jump (grounded latches until landing),
// reads the dvar live so a menu pick takes effect on the next jump with no respawn.
// Bots jump through the same input path, so they get it too.
function private jump_boost_think()
{
    self notify( #"gf_jump_boost_restart" );   // one watcher per life
    self endon( #"gf_jump_boost_restart" );
    self endon( #"disconnect" );
    self endon( #"death" );

    grounded = 1;

    for ( ;; )
    {
        boost = cfg_jump_boost();
        on_ground = self isonground();

        if ( boost > 0 && grounded && !on_ground && self jumpbuttonpressed() && !self ismantling() )
        {
            v = self getvelocity();

            if ( v[ 2 ] > 0 )
                self setvelocity( ( v[ 0 ], v[ 1 ], v[ 2 ] + boost ) );
        }

        grounded = on_ground;
        waitframe( 1 );
    }
}

// ── Fly (host). The shipped Atian Cold War fly_mode, in this file's dialect: link the
// player to a script_origin and move THAT each frame from the movement input, so no
// physics apply; sprint = fast, jump = up, crouch = down. Stops itself on death
// (fly_cleanup unlinks, deletes the anchor, restores the out-of-bounds guard). ─────────
function private fly_think()
{
    self notify( #"gf_fly_stop" );   // never two
    self endon( #"gf_fly_stop" );
    self endon( #"disconnect" );
    self endon( #"death" );

    anchor = spawn( "script_origin", self.origin );
    anchor.angles = self.angles;
    self.gf_fly_anchor = anchor;   // a teleport moves THIS while flying (tp_place)
    self.gf_fly = 1;
    self playerlinkto( anchor );
    self val::set( #"gf_fly", "disable_oob", 1 );
    self thread fly_cleanup( anchor );

    for ( ;; )
    {
        step = self sprintbuttonpressed() ? cfg_fly_fast() : cfg_fly_speed();
        ang = self getplayerangles();
        fwd = anglestoforward( ang );
        right = anglestoright( ang );
        mv = self getnormalizedmovement();
        delta = ( 0, 0, 0 );

        if ( isdefined( mv ) )
            delta = fwd * mv[ 0 ] + ( right[ 0 ], right[ 1 ], 0 ) * mv[ 1 ];

        if ( self jumpbuttonpressed() )
            delta += ( 0, 0, 1 );
        else if ( self stancebuttonpressed() )
            delta += ( 0, 0, -1 );

        anchor.origin += delta * step;
        waitframe( 1 );
    }
}

function private fly_cleanup( anchor )
{
    self waittill( #"gf_fly_stop", #"death", #"disconnect" );

    if ( isdefined( self ) )
    {
        self unlink();
        self val::reset( #"gf_fly", "disable_oob" );
        self.gf_fly = 0;
        self.gf_fly_anchor = undefined;
    }

    if ( isdefined( anchor ) )
        anchor delete();
}

// ── Freeze / pause. Per player: the same layered values stock's esports pause sets
// (util_shared.gsc:7232-7233) - freezecontrols + takedamage 0, under our own id so
// stock's own layers are untouched. Pause = stock's pause sequence (globallogic.gsc
// function_411eb759 :6125-6165) minus its two telemetry builtins: the "GAME PAUSED" LUI
// event, round timer held (pausetimer), every non-spectator frozen by stock's own
// util::function_1c8873f6, the paused flag stock threads wait on; resume counts down 5
// with the stock match-start timer like a CDL unpause, then releases everything. ────────
function private freeze_set( player, on )
{
    if ( on )
    {
        player val::set( #"gf_freeze", "freezecontrols_allowlook", 1 );
        player val::set( #"gf_freeze", "takedamage", 0 );
        player.gf_frozen = 1;
    }
    else
    {
        player val::reset( #"gf_freeze", "freezecontrols_allowlook" );
        player val::reset( #"gf_freeze", "takedamage" );
        player.gf_frozen = 0;
    }
}

function private freeze_all_set( on )
{
    foreach ( player in getplayers() )
    {
        if ( player.team != #"spectator" )
            freeze_set( player, on );
    }

    level.gf_frozen_all = on;
}

function private match_pause()
{
    if ( isdefined( level.gf_paused ) && level.gf_paused )
        return;

    level.gf_paused = 1;
    level.gf_resuming = 0;
    level notify( #"esports_game_paused" );
    luinotifyevent( #"esports_game_paused", 1, 1 );
    globallogic_utils::pausetimer( 1 );
    util::function_1c8873f6( 1 );
    level.var_e80a117f = 1;
    level thread pause_banner_think();
}

// Held on every screen for the whole pause: the centre print fades after a few seconds,
// so it is re-sent every 3 s until the resume countdown takes the centre over.
function private pause_banner_think()
{
    level endon( #"game_ended" );

    while ( isdefined( level.gf_paused ) && level.gf_paused && !( isdefined( level.gf_resuming ) && level.gf_resuming ) )
    {
        broadcast_bold( "^1BLINKER ^3CHECKPOINT" );
        wait 3;
    }
}

// Threaded off the caller: the 5 s countdown waits.
function private match_resume()
{
    if ( !isdefined( level.gf_paused ) || !level.gf_paused )
        return;

    level endon( #"game_ended" );
    level.gf_resuming = 1;
    thread globallogic::matchstarttimer( 5 );
    wait 5;

    if ( isdefined( level.timerpausetime ) && isdefined( level.var_9d348da1 ) )
        level.var_9d348da1 += gettime() - level.timerpausetime;

    level.var_e80a117f = 0;
    util::function_1c8873f6( 0 );
    globallogic_utils::resumetimer();
    level notify( #"hash_22962c7c3ae16f30" );
    luinotifyevent( #"esports_game_paused", 1, 0 );
    level.gf_paused = 0;
    level.gf_resuming = 0;
}

// ── Broadcast. iprintlnbold ON each player is the server->client centre print stock
// uses for "match starting"; the feed form (iprintln) for multi-line. ──────────────────
function private broadcast_bold( msg )
{
    foreach ( player in getplayers() )
        player iprintlnbold( msg );
}

function private broadcast_feed( msg )
{
    foreach ( player in getplayers() )
        player iprintln( msg );
}

// App broadcast with a chosen location + hold duration (gf_cmd_say / gf_cmd_say_loc / _dur).
//   loc: 0 = centre (iprintlnbold),  1 = lower-left feed (iprintln).
//   dur: 0 = send once and let the engine fade it;  > 0 = hold that many seconds;
//        < 0 = FIXED, held until a Clear (gf_cmd_say_clear -> gf_say_stop).
// Held text is re-sent every 2 s so the centre line never fades; on the feed a held message
// re-prints (adds a line each time). Only one held broadcast at a time.
function private broadcast_hold( msg, loc, dur )
{
    level notify( #"gf_say_stop" );

    if ( loc == 2 )
    {
        broadcast_hint_start( msg, dur );   // persistent banner; dur < 0 = held until Clear
        return;
    }

    broadcast_hint_stop();                  // a centre/feed broadcast clears any banner

    if ( dur == 0 )
    {
        broadcast_where( msg, loc );
        return;
    }

    level endon( #"gf_say_stop" );
    level endon( #"game_ended" );
    end = ( dur > 0 ) ? ( gettime() + dur * 1000 ) : 0;
    while ( true )
    {
        broadcast_where( msg, loc );
        wait( 2.0 );
        if ( end != 0 && gettime() >= end )
            break;
    }
}

function private broadcast_where( msg, loc )
{
    if ( loc == 1 )
        broadcast_feed( msg );
    else
        broadcast_bold( msg );
}

function private broadcast_countdown()
{
    level endon( #"game_ended" );

    for ( i = 5; i >= 1; i-- )
    {
        broadcast_bold( "^3" + i );
        wait 1;
    }

    broadcast_bold( "^2GO!" );
}

// ── Broadcast as a persistent HINT banner (loc 2). Unlike the centre print, a hint
// string STAYS on screen with no re-send and no flicker, so it is the clean "held
// until Clear" banner. Each player gets a trigger_radius glued to them (so they are
// always inside it) showing the message. Text sits at the fixed use-prompt anchor
// (sethintstring has no position arg); gf_say_hint_indent prepends spaces to nudge it
// right. ⚠ OPEN QUESTION this tests: does a server hint on a player entity render for a
// VANILLA JOINER? All prior hint work was host-only. If it does, this is a rare
// joiner-visible server->client text channel (game-systems §2: most mod text is host-only).
function private broadcast_hint_start( msg, dur )
{
    level.gf_hint_msg = msg;
    level notify( #"gf_hint_changed" );

    if ( !is_true( level.gf_hint_running ) )
    {
        level.gf_hint_running = 1;
        level thread broadcast_hint_manager();
    }

    if ( dur > 0 )
        level thread broadcast_hint_expire( msg, dur );
}

function private broadcast_hint_stop()
{
    level.gf_hint_msg = undefined;
    level notify( #"gf_hint_changed" );
}

// A timed banner (dur > 0) clears itself, unless a newer banner replaced it first.
function private broadcast_hint_expire( msg, dur )
{
    level endon( #"game_ended" );
    level endon( #"gf_hint_changed" );
    wait( dur );
    if ( isdefined( level.gf_hint_msg ) && level.gf_hint_msg == msg )
        broadcast_hint_stop();
}

// Re-applies to every CURRENT player each 2 s (so a joiner mid-banner picks it up), until
// the message is cleared; then removes every banner trigger. Re-setting the same hint
// string is idempotent - no flicker, unlike the centre print's re-send.
function private broadcast_hint_manager()
{
    level endon( #"game_ended" );

    while ( isdefined( level.gf_hint_msg ) )
    {
        indent = "";
        pad = cfg_geti( #"gf_say_hint_indent", 0 );
        for ( i = 0; i < pad; i++ )
            indent += " ";

        foreach ( player in getplayers() )
        {
            if ( !isdefined( player.gf_say_trig ) )
                player broadcast_hint_make();

            player.gf_say_trig sethintstring( indent + level.gf_hint_msg );
        }

        level waittilltimeout( 2, #"gf_hint_changed" );
    }

    broadcast_hint_wipe();
    level.gf_hint_running = undefined;
}

// One banner trigger glued to the player (NO cursor icon; short text so it never clips).
function private broadcast_hint_make()
{
    trig = spawn( "trigger_radius", self.origin, 0, 96, 128 );
    trig setcursorhint( "HINT_NOICON" );
    trig triggerignoreteam();
    trig setvisibletoplayer( self );
    trig setmovingplatformenabled( 1 );
    trig enablelinkto();
    trig.origin = self.origin;
    trig linkto( self );
    self.gf_say_trig = trig;
}

function private broadcast_hint_wipe()
{
    foreach ( player in getplayers() )
    {
        if ( isdefined( player.gf_say_trig ) )
        {
            player.gf_say_trig delete();
            player.gf_say_trig = undefined;
        }
    }
}

// The state line every joiner cannot otherwise see: team size, timer, map, mode, limits.
function private broadcast_settings()
{
    ts = cfg_team_size();
    broadcast_feed( "^3HOST: ^7" + ts + "v" + ts + " Gunfight, round timer " + cfg_timer_label() + ", map " + getdvarstring( #"sv_mapname", "?" ) + " / " + getdvarstring( #"g_gametype", "?" ) );
    broadcast_feed( "^3HOST: ^7first to " + ( cfg_roundwinlimit() >= 0 ? ( "" + cfg_roundwinlimit() ) : "stock" ) + " rounds, cap " + ( cfg_roundlimit() >= 0 ? ( "" + cfg_roundlimit() ) : "stock" ) + ", loadout+sides every " + ( cfg_rounds_loadout() >= 0 ? ( "" + cfg_rounds_loadout() ) : "stock" ) + ", pre-round " + ( cfg_preround() >= 0 ? ( cfg_preround() + "s" ) : "lobby" ) );
}

// Pre-match / pre-round countdowns: the two settings behind the custom-games rows
// "Pre-Match Timer" (prematchperiod: 5/10/15/30/45/60) and "Pre-Round Timer" (preroundperiod:
// 0-30, scriptbundle/gamesettings/pre*_period.json). Defaults 15s / 7s; -1 hands a row back
// to the lobby.
//
// ⚠ ORDERING, verified in source. Stock reads BOTH into the one level var
// level.prematchperiod in function_b9b7618() - prematchperiod on the match's first load
// (globallogic.gsc:5072), preroundperiod on every map_restart( 1 ) round after (:5087) - and
// that runs BEFORE this callback (callback_startgametype: :5532 vs on_start_gametype :5536).
// The consumer runs AFTER it: thread startgame() (:5539) -> prematchperiod() ->
// matchstarttimer( level.prematchperiod ) (:4855/:4873/:4881), which also drives the HUD
// countdown (luinotifyevent create_prematch_timer, :1441). So the setting write alone would
// miss the load it is made on; the live level var is what THIS load's countdown reads. Both
// are written: the level var for now, the settings so every later read agrees (the next
// load's function_b9b7618(), the intro-cinematic gate at namespace_66d6aa44 :259). No
// gametype gate: the settings are global MP, and the menu links into every mode it can
// switch to.
function private mod_periods()
{
    periods_snapshot();

    pm = periods_value( cfg_prematch(), game.gf_lobby_prematch );
    pr = periods_value( cfg_preround(), game.gf_lobby_preround );

    if ( isdefined( pm ) )
        gts_set( #"prematchperiod", pm );
    if ( isdefined( pr ) )
        gts_set( #"preroundperiod", pr );

    // Which countdown THIS load runs: the postinit's snapshot of stock's own test
    // (mod_postinit). Stock skips the pre-round read in splitscreen (:5085); mirror that.
    if ( isdefined( level.gf_first_load ) && level.gf_first_load )
        want = pm;
    else if ( isdefined( level.splitscreen ) && level.splitscreen )
        want = undefined;
    else
        want = pr;

    if ( isdefined( want ) )
        level.prematchperiod = want;
}

// The lobby's own values, captured ONCE per match (game. resets at match end) before
// anything here writes the settings - so "-1 = lobby's value" restores the real row
// mid-match instead of freezing whatever was last written. The menu actions call it too,
// in case the host picks a value before the first mod_apply of an injection match.
function private periods_snapshot()
{
    if ( !isdefined( game.gf_lobby_prematch ) && isdefined( getgametypesetting( #"prematchperiod" ) ) )
        game.gf_lobby_prematch = getgametypesetting( #"prematchperiod" );
    if ( !isdefined( game.gf_lobby_preround ) && isdefined( getgametypesetting( #"preroundperiod" ) ) )
        game.gf_lobby_preround = getgametypesetting( #"preroundperiod" );
}

// A dvar pick, or the lobby's value for the -1 sentinel; undefined = nothing to write.
function private periods_value( pick, lobby )
{
    if ( pick >= 0 )
        return pick;

    return lobby;   // may be undefined: no snapshot yet -> leave the setting alone
}

function private mod_ontimelimit()
{
    // One-shot. checktimelimit() re-invokes level.ontimelimit every 0.25s while the timer
    // reads expired; gunfight's re-entrancy latch lived in gunfight::endround, which we no
    // longer call, so own it here. level is rebuilt per round, so this resets each round.
    if ( isdefined( level.gfmenu_round_ended ) && level.gfmenu_round_ended )
        return;
    level.gfmenu_round_ended = 1;

    // Vehicle mode: a rider's armour is his ride, so its health fraction (0..100) joins the
    // side's total - otherwise a Hind at 5% and a Hind at 100% tie (veh_mode_hp_bonus).
    allies_health = 0;
    foreach ( p in getplayers( #"allies" ) )
        allies_health += p.health + veh_mode_hp_bonus( p );

    axis_health = 0;
    foreach ( p in getplayers( #"axis" ) )
        axis_health += p.health + veh_mode_hp_bonus( p );

    if ( allies_health > axis_health )
        globallogic::function_a3e3bd39( #"allies", 1 );
    else if ( axis_health > allies_health )
        globallogic::function_a3e3bd39( #"axis", 1 );
    else
        thread globallogic::end_round( 2 );
}

function private mod_gettimelimit()
{
    // seconds -> minutes, fractional is fine: the DDL field is fixed<8,2>.
    // 0 (Timer unlimited) is the engine's own "no time limit": checktimelimit() sees
    // level.timelimit <= 0 and clears the end time (globallogic.gsc:3289), so
    // ontimelimit never fires, the clock hides, and the round ends only when a team
    // is wiped. Returned unclamped on purpose - the stock gunfight::gettimelimit
    // floors at level.timelimitmin, which would turn 0 back into a limit.
    // Cached at round start (mod_apply / cmd_apply_live), NOT read live here, so a mid-round
    // gf_timer_seconds change from the app's "Next round" defers to the next round instead of
    // ending this one instantly. Fallback to the live read before the first cache exists.
    timelimit = isdefined( level.gf_timelimit_cache ) ? level.gf_timelimit_cache : ( cfg_timer_seconds() / 60 );

    // Overtime. overtime() (gunfight.gsc:951) sets the HUD clock to extratime, but
    // checktimelimit() (globallogic.gsc:3313) measures expiry against level.timelimit,
    // which updategametypedvars() refreshes from THIS function every 0.25s. Without
    // the extra time added here the base limit reads expired again on the next tick
    // and ontimelimit() falls straight through to the HP tiebreak - a zero-second
    // overtime. Mirrors stock gettimelimit (gunfight.gsc:1150-1153), frame epsilon and all.
    if ( isdefined( level.usingextratime ) && level.usingextratime )
        return timelimit + ( level.extratime + float( function_60d95f53() ) / 1000 ) / 60;

    return timelimit;
}

function private mod_presentation_fixups()
{
    if ( !util::isfirstround() )
    {
        music::setmusicstate( "gunfight_roundstart" );
    }

    if ( isdefined( level.teams ) )
    {
        foreach ( team, _ in level.teams )
        {
            level.var_a236b703[ team ] = 1;
            level.var_61952d8b[ team ] = 1;
        }
    }

    thread mod_norespawns_hud();
    luinotifyevent( #"round_start" );
}

function private mod_norespawns_hud()
{
    waitframe( 1 );
    clientfield::set_world_uimodel( "hudItems.team1.noRespawnsLeft", 1 );
    clientfield::set_world_uimodel( "hudItems.team2.noRespawnsLeft", 1 );
}

// ── Keep Crossroads' STRIKE layout under Gunfight (klaze, 2026-09-14) ────────────
// mp_tundra.gsc on_game_playing() opens the full 12v12 map for every gametype outside its
// Strike list - it deletes the "tundra_oob_clip" entities and the "5v5_asset_boundary"
// entities (by targetname and by script_noteworthy) - and "gunfight" is outside the list,
// so a Case-B launch of Crossroads is the big map under a "Crossroads Strike" label. That
// callback fires at set_game_playing (globallogic.gsc:4413), AFTER this mod_apply, and it
// finds its victims by NAME - so renaming them here (a stock idiom: globallogic.gsc:4243
// sets a targetname) leaves it nothing to delete and the Strike clips stand. main() had
// already hidden the boundary misc models at level_init (:54); showmiscmodels() brings them
// back, and the Strike branch's own turret/fx calls are repeated for fidelity (the map's
// 12v12 lighting exploder still runs from its callback - cosmetic). The kept entities also
// give the spawn guard the AREA: their centroid and ring radius bound the markers it may
// use, so the two sides are built inside the Strike area, not out on the big map.
// gf_strike - DEFAULT 0 since the first run (2026-09-14): the CLIENT half of the map script
// (mp_tundra.csc function_7f639bc1) branches on the same gametype list and hides the 6v6
// boundary decals / occluders for gunfight, so every client - vanilla joiners included -
// draws the full-map minimap and bounds while the server keeps Strike clips: invisible walls
// on open ground ("the minimap is broken" - klaze). Unreachable from a server payload. Kept
// as an option; a no-op on any map without those names (only Crossroads has them;
// Armada/Collateral already keep Strike for small modes, gunfight included).
function private mod_layout_keep()
{
    level.gf_area_center = undefined;
    level.gf_area_radius = undefined;
    level.gf_strike_status = "off";

    if ( !cfg_strike() )
        return;

    oob = getentarray( "tundra_oob_clip", "targetname" );
    bnd = arraycombine( getentarray( "5v5_asset_boundary", "targetname" ), getentarray( "5v5_asset_boundary", "script_noteworthy" ), 0, 0 );
    level.gf_strike_status = "no-ents";

    if ( oob.size == 0 && bnd.size == 0 )
        return;

    level.gf_strike_status = "kept " + oob.size + "+" + bnd.size;

    foreach ( e in oob )
    {
        if ( isdefined( e ) )
            e.targetname = "gf_oob_keep";
    }

    foreach ( e in bnd )
    {
        if ( !isdefined( e ) )
            continue;
        e.targetname = "gf_5v5_keep";
        e.script_noteworthy = "gf_5v5_keep";
    }

    showmiscmodels( "5v5_asset_boundary" );
    hidemiscmodels( "turret_model" );
    exploder::exploder( "fxexp_tundra_6v6" );
    level.var_633063a5 = 1;

    // The area the clips enclose. Brush entities can carry a (0,0,0) origin, so only ents
    // with a real origin count; fewer than 3 = no area (the guard uses the marker centroid).
    ring = arraycombine( oob, bnd, 0, 0 );
    sum = ( 0, 0, 0 );
    n = 0;
    foreach ( e in ring )
    {
        if ( isdefined( e ) && isdefined( e.origin ) && length( e.origin ) > 1 )
        {
            sum += e.origin;
            n++;
        }
    }

    if ( n >= 3 )
    {
        c = sum / n;
        dsum = 0;
        foreach ( e in ring )
        {
            if ( isdefined( e ) && isdefined( e.origin ) && length( e.origin ) > 1 )
                dsum += sqrt( mod_dist2d_sq( e.origin, c ) );
        }
        level.gf_area_center = c;
        level.gf_area_radius = ( dsum / n ) * 0.85;
    }

    if ( !isdefined( level.gf_area_radius ) )
        level.gf_strike_status += " noarea";
}

function private act_strike( item, value )
{
    cfg_seti( #"gf_strike", value );
    self menu_say( value ? "^2Crossroads Strike layout under Gunfight ON - from the next match/round" : "^2Crossroads: full map under Gunfight - stock" );
    return true;
}

// ── Spawn FAMILY: build the anchors from one mode's markers (klaze, 2026-09-14) ─────────
// MEASURED on Hijacked (STRUCTS line): every mp_spawn_point struct carries its mode flag as a
// plain script field - `tdm=1` on the first three - so the per-mode marker sets ARE readable
// from script (Crossroads' first three read empty only because they carry flags this probe
// did not ask for: the 10v10/12v12 variants). "I've yet to see any map use normal S&D spawns
// under Gunfight - let's get Gunfight using the S&D spawn system." So: gf_spawn_family picks
// a flag; the guard's anchors are built only from markers that carry it; sides come from the
// markers' own side fields when they have them (what those are called is what the FLAGS
// debug line measures - the candidates below are the plausible names), else the geometric
// two-sides search runs inside that family. With a family set the override places EVERY
// spawn on the anchors (the engine's tdm start list is not consulted).
//   0 none (engine start spawns, anchors only when the engine has none - AUTO - or FORCE)
//   1 tdm   2 sd   3 dom   4 ctf   5 koth   6 control   7 dm/ffa
// DEFAULT 1 (tdm) + guard AUTO since 2026-09-15: MEASURED on Hijacked by klaze - "the results
// were very good, they switched sides and lined up well for Gunfight." The 78 tdm markers,
// two ends picked geometrically, facing each other, sides swapped by the guard. Family: none
// hands a map back to the engine's own start spawns.
//   8 AUTO - DEFAULT since 2026-09-15 (the spawn keys below): the map's authored S&D starts
//     when it has them on both sides, else its authored TDM starts, else (nothing authored)
//     exactly the tdm geometric split above. "Proper" S&D / TDM spawns, per map, no data.
function private cfg_spawn_family()   { return cfg_geti( #"gf_spawn_family", 8 ); }

function private family_name( f )
{
    if ( f == 1 ) return "tdm";
    if ( f == 2 ) return "sd";
    if ( f == 3 ) return "dom";
    if ( f == 4 ) return "ctf";
    if ( f == 5 ) return "koth";
    if ( f == 6 ) return "control";
    if ( f == 7 ) return "dm";
    if ( f == 8 ) return "auto";
    return "none";
}

// Does this marker carry the family's flag? (fields, by constant name - GSC has no dynamic
// field access, so one branch per family.)
function private mod_marker_has( s, f )
{
    if ( f == 1 ) return isdefined( s.tdm );
    if ( f == 2 ) return isdefined( s.sd );
    if ( f == 3 ) return isdefined( s.dom ) || isdefined( s.domination );   // engine: spawnpoint.domination
    if ( f == 4 ) return isdefined( s.ctf );
    if ( f == 5 ) return isdefined( s.koth ) || isdefined( s.hardpoint );    // engine: spawnpoint.hardpoint
    if ( f == 6 ) return isdefined( s.control );
    if ( f == 7 ) return isdefined( s.dm ) || isdefined( s.ffa );
    return false;
}

// Which side a marker belongs to, 1 / 2 / 0 (none), from the plausible side fields. The
// FLAGS line says which of these a map actually uses; unknown names simply never match.
function private mod_marker_side( s, f )
{
    if ( isdefined( s.attacker ) ) return 1;
    if ( isdefined( s.defender ) ) return 2;
    if ( isdefined( s.sd_attacker ) ) return 1;
    if ( isdefined( s.sd_defender ) ) return 2;
    if ( isdefined( s.allies ) ) return 1;
    if ( isdefined( s.axis ) ) return 2;
    if ( isdefined( s.tdm_allies_start ) ) return 1;
    if ( isdefined( s.tdm_axis_start ) ) return 2;
    if ( isdefined( s.dom_allies_start ) ) return 1;
    if ( isdefined( s.dom_axis_start ) ) return 2;
    if ( isdefined( s.ctf_allies ) ) return 1;
    if ( isdefined( s.ctf_axis ) ) return 2;

    t = undefined;
    if ( isdefined( s.team ) )
        t = s.team;
    else if ( isdefined( s.script_team ) )
        t = s.script_team;

    if ( isdefined( t ) )
    {
        if ( t == "allies" || t == #"allies" || t == "attacker" || t == #"attacker" || t == "team1" || t == #"team1" )
            return 1;
        if ( t == "axis" || t == #"axis" || t == "defender" || t == #"defender" || t == "team2" || t == #"team2" )
            return 2;
    }

    // Value-coded flags: a family field worth 2 / 3 rather than 1 (a guess the FLAGS tallies
    // will confirm or kill).
    v = undefined;
    if ( f == 1 && isdefined( s.tdm ) ) v = s.tdm;
    if ( f == 2 && isdefined( s.sd ) ) v = s.sd;
    if ( f == 3 && isdefined( s.dom ) ) v = s.dom;
    if ( f == 4 && isdefined( s.ctf ) ) v = s.ctf;
    if ( isdefined( v ) && isint( v ) )
    {
        if ( v == 2 ) return 1;
        if ( v == 3 ) return 2;
    }

    return 0;
}

// ── The REAL spawn keys (dump, 2026-09-15) ───────────────────────────────────
// The engine's own spawn build (hashed spawning scripts script_335d0650ed05d36d.gsc
// function_beae80f9 :194 + script_44b0b8420eabacad.gsc function_82ca1565 :306) reads three
// things off every mp_spawn_point struct: the MODE FLAGS as plain fields (.tdm .sd .ctf
// .control .domination .hardpoint .ffa .base ...), the TEAM as .group_index (1 = allies,
// 2 = axis, 0 = either; swapped by function_3ea24e49 when game.switchedsides), and a START
// flag that sends the marker to the engine's "start_spawn" list - field hash 0xa3c53936,
// which ACTS prints as `_human_were` (a dictionary alias: the name compiles back to the same
// hash, so this reads exactly the field the engine reads; the Radiant KVP behind it is
// unknown). HQ markers carry .ishqspawn. So a mode's AUTHORED team starts - the points stock
// S&D / TDM open on - are: flag && start && group_index 1/2. No geometry, no guessed side
// names, every one designer-placed. Hijacked's FLAGS census (no `sd` on any marker) means
// the remasters ship no S&D set, which is why AUTO falls back to the TDM starts.
function private mod_marker_is_start( s ) { return is_true( s._human_were ); }
function private mod_marker_group( s )    { return isdefined( s.group_index ) ? int( s.group_index ) : 0; }

// MEASURED Standoff 2026-09-15 (STARTS tdm=29/0 dom=16/0 ctf=92/0 control=66/0 dm=37/8(1+1+6),
// and mp_tdm_spawn_team1_start=6 / team2_start=6 by targetname): on the remasters the team-mode
// markers carry NO start flag at all - only the FFA set does - and the TDM starts survive under
// their BO2 NAMES as separate structs the T9 engine never reads (gettdmstartspawnname has no
// caller). So a family's authored starts come from two places: the flagged markers (the T9
// way) and the legacy-named start structs (the remaster way), targetname -> side.
function private mod_named_side( p, fam )
{
    tn = p.targetname;
    if ( !isdefined( tn ) )
        return 0;

    if ( fam == 1 )
    {
        if ( tn == "mp_tdm_spawn_allies_start" || tn == #"mp_tdm_spawn_allies_start" || tn == "mp_tdm_spawn_team1_start" || tn == #"mp_tdm_spawn_team1_start" ) return 1;
        if ( tn == "mp_tdm_spawn_axis_start" || tn == #"mp_tdm_spawn_axis_start" || tn == "mp_tdm_spawn_team2_start" || tn == #"mp_tdm_spawn_team2_start" ) return 2;
    }
    else if ( fam == 2 )
    {
        if ( tn == "mp_sd_spawn_attacker" || tn == #"mp_sd_spawn_attacker" ) return 1;
        if ( tn == "mp_sd_spawn_defender" || tn == #"mp_sd_spawn_defender" ) return 2;
    }
    else if ( fam == 3 )
    {
        if ( tn == "mp_dom_spawn_allies_start" || tn == #"mp_dom_spawn_allies_start" ) return 1;
        if ( tn == "mp_dom_spawn_axis_start" || tn == #"mp_dom_spawn_axis_start" ) return 2;
    }
    else if ( fam == 4 )
    {
        if ( tn == "mp_ctf_spawn_allies_start" || tn == #"mp_ctf_spawn_allies_start" || tn == "mp_ctf_spawn_allies" || tn == #"mp_ctf_spawn_allies" ) return 1;
        if ( tn == "mp_ctf_spawn_axis_start" || tn == #"mp_ctf_spawn_axis_start" || tn == "mp_ctf_spawn_axis" || tn == #"mp_ctf_spawn_axis" ) return 2;
    }

    return 0;
}

// ── S&D spawn GROUPS (dump, userspawnselection.gsc:793-869) ─────────────────
// MEASURED Standoff + Raid 2026-09-16: no `sd` flag on ANY mp_spawn_point marker, yet both run
// S&D in retail. BOCW S&D does not open on flagged starts at all - it uses spawn_group_marker
// ENTITIES (classname), one per selectable spawn group: .script_team = sidea / sideb (mapped
// to attackers / defenders by util::get_team_mapping, swapped on game.switchedsides), .target
// = the groupname of its point structs (struct::get_array( target, "groupname" )), .spawnlist
// = the engine list it fills, .script_objective = the minimap label. The player picks a group
// at round start (the spawnselectenabled / usespawngroups gametype settings - off under
// Gunfight) and the engine scores a point inside it. The entities and their structs are in
// the map under every gametype, so a map's authored S&D bases are readable here: one group a
// side (the largest) = the classic fixed S&D opening.
function private mod_group_side( g )
{
    tm = g.script_team;
    if ( !isdefined( tm ) )
        return 0;

    if ( tm == "sidea" || tm == #"sidea" || tm == "allies" || tm == #"allies" || tm == "attackers" || tm == #"attackers" )
        return 1;
    if ( tm == "sideb" || tm == #"sideb" || tm == "axis" || tm == #"axis" || tm == "defenders" || tm == #"defenders" )
        return 2;

    return 0;
}

// The map's spawn groups: g1 / g2 = arrays of point arrays per side, n = marker count,
// u = markers whose side could not be read. Built once per level.
function private mod_spawn_groups()
{
    if ( isdefined( level.gf_spawn_groups ) )
        return level.gf_spawn_groups;

    out = spawnstruct();
    out.g1 = [];
    out.g2 = [];
    out.n = 0;
    out.u = 0;
    markers = getentarray( "spawn_group_marker", "classname" );

    if ( isdefined( markers ) )
    {
        out.n = markers.size;

        foreach ( m in markers )
        {
            side = mod_group_side( m );

            if ( side == 0 || !isdefined( m.target ) )
            {
                out.u++;
                continue;
            }

            raw = struct::get_array( m.target, "groupname" );
            pts = [];

            if ( isdefined( raw ) )
            {
                foreach ( s in raw )
                {
                    if ( isdefined( s ) && isdefined( s.origin ) )
                        pts[ pts.size ] = s;
                }
            }

            if ( pts.size == 0 )
            {
                out.u++;
                continue;
            }

            if ( side == 1 )
                out.g1[ out.g1.size ] = pts;
            else
                out.g2[ out.g2.size ] = pts;
        }
    }

    level.gf_spawn_groups = out;
    return out;
}

// The largest group of a side (ties: first), or undefined.
function private mod_group_largest( groups )
{
    best = undefined;

    foreach ( g in groups )
    {
        if ( !isdefined( best ) || g.size > best.size )
            best = g;
    }

    return best;
}

// ` | GROUPS n=6 a=3(6,5,4) b=3(6,6,5)` for the STARTS line.
function private mod_groups_tally()
{
    gr = mod_spawn_groups();
    out = " | GROUPS n=" + gr.n;

    if ( gr.u > 0 )
        out += " u=" + gr.u;

    out += " a=" + gr.g1.size + "(";
    for ( i = 0; i < gr.g1.size; i++ )
        out += ( i > 0 ? "," : "" ) + gr.g1[ i ].size;
    out += ") b=" + gr.g2.size + "(";
    for ( i = 0; i < gr.g2.size; i++ )
        out += ( i > 0 ? "," : "" ) + gr.g2[ i ].size;
    out += ")";
    return out;
}

// The authored starts of one family among `pts`, split by side: { #a1, #a2 } - for S&D the
// map's spawn groups (largest group a side) when it has them, else the flagged markers (flag
// + start + group_index) plus the legacy-named start structs.
function private mod_family_starts( pts, fam )
{
    a1 = [];
    a2 = [];

    if ( fam == 2 )
    {
        gr = mod_spawn_groups();
        b1 = mod_group_largest( gr.g1 );
        b2 = mod_group_largest( gr.g2 );

        if ( isdefined( b1 ) && isdefined( b2 ) && b1.size >= 2 && b2.size >= 2 )
            return { #a1:b1, #a2:b2 };
    }

    foreach ( p in pts )
    {
        side = mod_named_side( p, fam );

        if ( side == 0 && mod_marker_has( p, fam ) && mod_marker_is_start( p ) )
            side = mod_marker_group( p );

        if ( side == 1 )
            a1[ a1.size ] = p;
        else if ( side == 2 )
            a2[ a2.size ] = p;
    }

    return { #a1:a1, #a2:a2 };
}

// The legacy-named start structs per family, as ` tdm=6/6 sd=0/0 dom=0/0 ctf=0/0`.
function private mod_named_tally( pts )
{
    out = "";

    for ( f = 1; f <= 4; f++ )
    {
        n1 = 0;
        n2 = 0;

        foreach ( p in pts )
        {
            side = mod_named_side( p, f );
            if ( side == 1 )
                n1++;
            else if ( side == 2 )
                n2++;
        }

        out += " " + family_name( f ) + "=" + n1 + "/" + n2;
    }

    return out;
}

// The STARTS feed line (spawn families toggle) - its own line so FAMILIES stays inside the
// HUD width (Standoff's read was cut at "sep=" with the tally appended).
function private starts_line()
{
    if ( isdefined( level.gf_starts_line ) )
        return level.gf_starts_line;

    level.gf_starts_line = "^3STARTS^7" + mod_starts_tally() + " | NAMED" + mod_named_tally( mod_gather_spawns() ) + mod_groups_tally();
    return level.gf_starts_line;
}

// Family AUTO (8): the map's S&D starts when it authors them on both sides, else its TDM
// starts (klaze, 2026-09-15: "if a map doesn't have sd spawns we should use tdm spawns").
// A map with neither authored resolves to tdm and mod_spawn_build does what it always did
// for tdm (the geometric two-sides search) - so AUTO can never do worse than the old default.
function private mod_family_auto( pts )
{
    st = mod_family_starts( pts, 2 );
    if ( st.a1.size >= 2 && st.a2.size >= 2 )
        return 2;
    return 1;
}

// Anchors that keep the marker's OWN angles: authored starts face where the designer aimed
// them (mod_anchor_copies re-aims at the other side, right only for a geometric guess).
function private mod_anchor_authored( markers )
{
    out = [];

    foreach ( m in markers )
    {
        a = spawnstruct();
        a.origin = m.origin;
        a.angles = isdefined( m.angles ) ? m.angles : ( 0, 0, 0 );
        out[ out.size ] = a;
    }

    return out;
}

// STARTS tally for the FAMILIES line: per mode flag `markers/starts(group1+group2+either)`,
// then hq. `tdm=78/12(6+6+0)` = 78 tdm markers, 12 authored starts, 6 a side. Modes with no
// marker are skipped. Built once per level.
function private mod_starts_tally()
{
    if ( isdefined( level.gf_starts_tally ) )
        return level.gf_starts_tally;

    arr = struct::get_array( "mp_spawn_point", "targetname" );
    if ( !isdefined( arr ) )
        arr = [];

    out = "";

    for ( f = 1; f <= 7; f++ )
    {
        n = 0;
        s0 = 0;
        s1 = 0;
        s2 = 0;

        foreach ( s in arr )
        {
            if ( !mod_marker_has( s, f ) )
                continue;

            n++;

            if ( !mod_marker_is_start( s ) )
                continue;

            g = mod_marker_group( s );
            if ( g == 1 )
                s1++;
            else if ( g == 2 )
                s2++;
            else
                s0++;
        }

        if ( n == 0 )
            continue;

        out += " " + family_name( f ) + "=" + n + "/" + ( s0 + s1 + s2 ) + "(" + s1 + "+" + s2 + "+" + s0 + ")";
    }

    hq = 0;
    foreach ( s in arr )
    {
        if ( is_true( s.ishqspawn ) )
            hq++;
    }

    out += " hq=" + hq;
    level.gf_starts_tally = out;
    return out;
}

function private act_spawn_family( item, value )
{
    cfg_seti( #"gf_spawn_family", value );
    if ( cfg_spawn_guard() )
    {
        mod_spawn_build();
        level.var_cda5136b = &mod_spawn_override;
    }
    self menu_say( value ? ( "^2spawn family " + family_name( value ) + " - anchors from its markers, every spawn" + ( isdefined( level.gfmenu_spawn ) ? "" : " (NO markers with that flag here - stock spawns)" ) ) : "^2spawn family off - engine / geometric" );
    return true;
}

// ── FLAGS debug line: which flag fields the map's markers carry, with value tallies ─────
function private flags_tally( line, name, cnt, vals )
{
    if ( cnt == 0 )
        return line;

    line += " " + name + "=" + cnt;
    if ( isdefined( vals ) && vals != "" )
        line += "[" + vals + "]";
    return line;
}

// Value tally for an int-valued flag: "1:90 2:6 3:6".
function private flags_vals( arr )
{
    counts = [];
    other = 0;
    foreach ( v in arr )
    {
        if ( isint( v ) && v >= 0 && v <= 9 )
            counts[ v ] = ( isdefined( counts[ v ] ) ? counts[ v ] : 0 ) + 1;
        else
            other++;
    }
    out = "";
    for ( i = 0; i <= 9; i++ )
    {
        if ( isdefined( counts[ i ] ) )
            out += ( out == "" ? "" : " " ) + i + ":" + counts[ i ];
    }
    if ( other )
        out += ( out == "" ? "" : " " ) + "x:" + other;
    return out;
}

function private flags_line()
{
    if ( isdefined( level.gf_flags_line ) )
        return level.gf_flags_line;

    arr = struct::get_array( "mp_spawn_point", "targetname" );
    if ( !isdefined( arr ) )
        arr = [];

    // One counter + value list per candidate. Kept to the names a CW map plausibly uses.
    c_tdm = []; c_sd = []; c_dom = []; c_ctf = []; c_koth = []; c_ctrl = []; c_dm = []; c_ffa = [];
    c_dem = []; c_vip = []; c_kc = []; c_conf = []; c_gun = []; c_prop = []; c_spy = []; c_esc = [];
    c_war = []; c_w12 = []; c_t10 = []; c_d10 = []; c_k10 = []; c_c10 = []; c_ft = []; c_dk = [];
    c_start = []; c_ss = []; c_tstart = []; c_sstart = []; c_all = []; c_ax = []; c_att = []; c_def = [];
    c_team = []; c_steam = []; c_sdatt = []; c_sddef = []; c_sf = []; c_sint = []; c_str = []; c_nw = [];

    foreach ( s in arr )
    {
        if ( isdefined( s.tdm ) ) c_tdm[ c_tdm.size ] = s.tdm;
        if ( isdefined( s.sd ) ) c_sd[ c_sd.size ] = s.sd;
        if ( isdefined( s.dom ) ) c_dom[ c_dom.size ] = s.dom;
        if ( isdefined( s.ctf ) ) c_ctf[ c_ctf.size ] = s.ctf;
        if ( isdefined( s.koth ) ) c_koth[ c_koth.size ] = s.koth;
        if ( isdefined( s.control ) ) c_ctrl[ c_ctrl.size ] = s.control;
        if ( isdefined( s.dm ) ) c_dm[ c_dm.size ] = s.dm;
        if ( isdefined( s.ffa ) ) c_ffa[ c_ffa.size ] = s.ffa;
        if ( isdefined( s.dem ) ) c_dem[ c_dem.size ] = s.dem;
        if ( isdefined( s.vip ) ) c_vip[ c_vip.size ] = s.vip;
        if ( isdefined( s.kc ) ) c_kc[ c_kc.size ] = s.kc;
        if ( isdefined( s.conf ) ) c_conf[ c_conf.size ] = s.conf;
        if ( isdefined( s.gun ) ) c_gun[ c_gun.size ] = s.gun;
        if ( isdefined( s.prop ) ) c_prop[ c_prop.size ] = s.prop;
        if ( isdefined( s.spy ) ) c_spy[ c_spy.size ] = s.spy;
        if ( isdefined( s.escort ) ) c_esc[ c_esc.size ] = s.escort;
        if ( isdefined( s.war ) ) c_war[ c_war.size ] = s.war;
        if ( isdefined( s.war12v12 ) ) c_w12[ c_w12.size ] = s.war12v12;
        if ( isdefined( s.tdm10v10 ) ) c_t10[ c_t10.size ] = s.tdm10v10;
        if ( isdefined( s.dom10v10 ) ) c_d10[ c_d10.size ] = s.dom10v10;
        if ( isdefined( s.koth10v10 ) ) c_k10[ c_k10.size ] = s.koth10v10;
        if ( isdefined( s.conf10v10 ) ) c_c10[ c_c10.size ] = s.conf10v10;
        if ( isdefined( s.fireteam ) ) c_ft[ c_ft.size ] = s.fireteam;
        if ( isdefined( s.dropkick ) ) c_dk[ c_dk.size ] = s.dropkick;
        if ( isdefined( s.start ) ) c_start[ c_start.size ] = s.start;
        if ( isdefined( s.start_spawn ) ) c_ss[ c_ss.size ] = s.start_spawn;
        if ( isdefined( s.tdm_start ) ) c_tstart[ c_tstart.size ] = s.tdm_start;
        if ( isdefined( s.sd_start ) ) c_sstart[ c_sstart.size ] = s.sd_start;
        if ( isdefined( s.allies ) ) c_all[ c_all.size ] = s.allies;
        if ( isdefined( s.axis ) ) c_ax[ c_ax.size ] = s.axis;
        if ( isdefined( s.attacker ) ) c_att[ c_att.size ] = s.attacker;
        if ( isdefined( s.defender ) ) c_def[ c_def.size ] = s.defender;
        if ( isdefined( s.team ) ) c_team[ c_team.size ] = s.team;
        if ( isdefined( s.script_team ) ) c_steam[ c_steam.size ] = s.script_team;
        if ( isdefined( s.sd_attacker ) ) c_sdatt[ c_sdatt.size ] = s.sd_attacker;
        if ( isdefined( s.sd_defender ) ) c_sddef[ c_sddef.size ] = s.sd_defender;
        if ( isdefined( s.spawnflags ) ) c_sf[ c_sf.size ] = s.spawnflags;
        if ( isdefined( s.script_int ) ) c_sint[ c_sint.size ] = s.script_int;
        if ( isdefined( s.script_string ) ) c_str[ c_str.size ] = s.script_string;
        if ( isdefined( s.script_noteworthy ) ) c_nw[ c_nw.size ] = s.script_noteworthy;
    }

    line = "^3FLAGS^7 n=" + arr.size;
    line = flags_tally( line, "tdm", c_tdm.size, flags_vals( c_tdm ) );
    line = flags_tally( line, "sd", c_sd.size, flags_vals( c_sd ) );
    line = flags_tally( line, "dom", c_dom.size, flags_vals( c_dom ) );
    line = flags_tally( line, "ctf", c_ctf.size, flags_vals( c_ctf ) );
    line = flags_tally( line, "koth", c_koth.size, flags_vals( c_koth ) );
    line = flags_tally( line, "control", c_ctrl.size, flags_vals( c_ctrl ) );
    line = flags_tally( line, "dm", c_dm.size, flags_vals( c_dm ) );
    line = flags_tally( line, "ffa", c_ffa.size, flags_vals( c_ffa ) );
    line = flags_tally( line, "dem", c_dem.size, flags_vals( c_dem ) );
    line = flags_tally( line, "vip", c_vip.size, flags_vals( c_vip ) );
    line = flags_tally( line, "kc", c_kc.size, flags_vals( c_kc ) );
    line = flags_tally( line, "conf", c_conf.size, flags_vals( c_conf ) );
    line = flags_tally( line, "gun", c_gun.size, flags_vals( c_gun ) );
    line = flags_tally( line, "prop", c_prop.size, flags_vals( c_prop ) );
    line = flags_tally( line, "spy", c_spy.size, flags_vals( c_spy ) );
    line = flags_tally( line, "escort", c_esc.size, flags_vals( c_esc ) );
    line = flags_tally( line, "war", c_war.size, flags_vals( c_war ) );
    line = flags_tally( line, "war12v12", c_w12.size, flags_vals( c_w12 ) );
    line = flags_tally( line, "tdm10v10", c_t10.size, flags_vals( c_t10 ) );
    line = flags_tally( line, "dom10v10", c_d10.size, flags_vals( c_d10 ) );
    line = flags_tally( line, "koth10v10", c_k10.size, flags_vals( c_k10 ) );
    line = flags_tally( line, "conf10v10", c_c10.size, flags_vals( c_c10 ) );
    line = flags_tally( line, "fireteam", c_ft.size, flags_vals( c_ft ) );
    line = flags_tally( line, "dropkick", c_dk.size, flags_vals( c_dk ) );
    line = flags_tally( line, "start", c_start.size, flags_vals( c_start ) );
    line = flags_tally( line, "start_spawn", c_ss.size, flags_vals( c_ss ) );
    line = flags_tally( line, "tdm_start", c_tstart.size, flags_vals( c_tstart ) );
    line = flags_tally( line, "sd_start", c_sstart.size, flags_vals( c_sstart ) );
    line = flags_tally( line, "allies", c_all.size, flags_vals( c_all ) );
    line = flags_tally( line, "axis", c_ax.size, flags_vals( c_ax ) );
    line = flags_tally( line, "attacker", c_att.size, flags_vals( c_att ) );
    line = flags_tally( line, "defender", c_def.size, flags_vals( c_def ) );
    line = flags_tally( line, "team", c_team.size, ( c_team.size ? spawn_fv( c_team[ 0 ] ) : "" ) );
    line = flags_tally( line, "script_team", c_steam.size, ( c_steam.size ? spawn_fv( c_steam[ 0 ] ) : "" ) );
    line = flags_tally( line, "sd_attacker", c_sdatt.size, flags_vals( c_sdatt ) );
    line = flags_tally( line, "sd_defender", c_sddef.size, flags_vals( c_sddef ) );
    line = flags_tally( line, "spawnflags", c_sf.size, flags_vals( c_sf ) );
    line = flags_tally( line, "script_int", c_sint.size, flags_vals( c_sint ) );
    line = flags_tally( line, "script_string", c_str.size, ( c_str.size ? spawn_fv( c_str[ 0 ] ) : "" ) );
    line = flags_tally( line, "script_noteworthy", c_nw.size, ( c_nw.size ? spawn_fv( c_nw[ 0 ] ) : "" ) );

    level.gf_flags_line = line;
    return line;
}

// Second batch of candidate names (Hijacked read only tdm/ctf/control/ffa - S&D, Dom,
// Hardpoint and the sides must be keyed by something else). Separate line, same tick.
function private flags_line2()
{
    if ( isdefined( level.gf_flags_line2 ) )
        return level.gf_flags_line2;

    arr = struct::get_array( "mp_spawn_point", "targetname" );
    if ( !isdefined( arr ) )
        arr = [];

    a1 = []; a2 = []; a3 = []; a4 = []; a5 = []; a6 = []; a7 = []; a8 = []; a9 = []; a10 = [];
    a11 = []; a12 = []; a13 = []; a14 = []; a15 = []; a16 = []; a17 = []; a18 = []; a19 = []; a20 = [];
    a21 = []; a22 = []; a23 = []; a24 = []; a25 = []; a26 = []; a27 = []; a28 = []; a29 = []; a30 = [];

    foreach ( s in arr )
    {
        if ( isdefined( s.snd ) ) a1[ a1.size ] = s.snd;
        if ( isdefined( s.search ) ) a2[ a2.size ] = s.search;
        if ( isdefined( s.sd_a ) ) a3[ a3.size ] = s.sd_a;
        if ( isdefined( s.sd_b ) ) a4[ a4.size ] = s.sd_b;
        if ( isdefined( s.sd_attackers ) ) a5[ a5.size ] = s.sd_attackers;
        if ( isdefined( s.sd_defenders ) ) a6[ a6.size ] = s.sd_defenders;
        if ( isdefined( s.attackers ) ) a7[ a7.size ] = s.attackers;
        if ( isdefined( s.defenders ) ) a8[ a8.size ] = s.defenders;
        if ( isdefined( s.demolition ) ) a9[ a9.size ] = s.demolition;
        if ( isdefined( s.domination ) ) a10[ a10.size ] = s.domination;
        if ( isdefined( s.dom_a ) ) a11[ a11.size ] = s.dom_a;
        if ( isdefined( s.dom_b ) ) a12[ a12.size ] = s.dom_b;
        if ( isdefined( s.dom_c ) ) a13[ a13.size ] = s.dom_c;
        if ( isdefined( s.hardpoint ) ) a14[ a14.size ] = s.hardpoint;
        if ( isdefined( s.hp ) ) a15[ a15.size ] = s.hp;
        if ( isdefined( s.hq ) ) a16[ a16.size ] = s.hq;
        if ( isdefined( s.oic ) ) a17[ a17.size ] = s.oic;
        if ( isdefined( s.bounty ) ) a18[ a18.size ] = s.bounty;
        if ( isdefined( s.ct ) ) a19[ a19.size ] = s.ct;
        if ( isdefined( s.infil ) ) a20[ a20.size ] = s.infil;
        if ( isdefined( s.frontline ) ) a21[ a21.size ] = s.frontline;
        if ( isdefined( s.team1 ) ) a22[ a22.size ] = s.team1;
        if ( isdefined( s.team2 ) ) a23[ a23.size ] = s.team2;
        if ( isdefined( s.spawn_type ) ) a24[ a24.size ] = s.spawn_type;
        if ( isdefined( s.type ) ) a25[ a25.size ] = s.type;
        if ( isdefined( s.script_label ) ) a26[ a26.size ] = s.script_label;
        if ( isdefined( s.script_gametype ) ) a27[ a27.size ] = s.script_gametype;
        if ( isdefined( s.script_gametype_sd ) ) a28[ a28.size ] = s.script_gametype_sd;
        if ( isdefined( s.target ) ) a29[ a29.size ] = s.target;
        if ( isdefined( s.radius ) ) a30[ a30.size ] = s.radius;
    }

    line = "^3FLAGS2^7";
    line = flags_tally( line, "snd", a1.size, flags_vals( a1 ) );
    line = flags_tally( line, "search", a2.size, flags_vals( a2 ) );
    line = flags_tally( line, "sd_a", a3.size, flags_vals( a3 ) );
    line = flags_tally( line, "sd_b", a4.size, flags_vals( a4 ) );
    line = flags_tally( line, "sd_attackers", a5.size, flags_vals( a5 ) );
    line = flags_tally( line, "sd_defenders", a6.size, flags_vals( a6 ) );
    line = flags_tally( line, "attackers", a7.size, flags_vals( a7 ) );
    line = flags_tally( line, "defenders", a8.size, flags_vals( a8 ) );
    line = flags_tally( line, "demolition", a9.size, flags_vals( a9 ) );
    line = flags_tally( line, "domination", a10.size, flags_vals( a10 ) );
    line = flags_tally( line, "dom_a", a11.size, flags_vals( a11 ) );
    line = flags_tally( line, "dom_b", a12.size, flags_vals( a12 ) );
    line = flags_tally( line, "dom_c", a13.size, flags_vals( a13 ) );
    line = flags_tally( line, "hardpoint", a14.size, flags_vals( a14 ) );
    line = flags_tally( line, "hp", a15.size, flags_vals( a15 ) );
    line = flags_tally( line, "hq", a16.size, flags_vals( a16 ) );
    line = flags_tally( line, "oic", a17.size, flags_vals( a17 ) );
    line = flags_tally( line, "bounty", a18.size, flags_vals( a18 ) );
    line = flags_tally( line, "ct", a19.size, flags_vals( a19 ) );
    line = flags_tally( line, "infil", a20.size, flags_vals( a20 ) );
    line = flags_tally( line, "frontline", a21.size, flags_vals( a21 ) );
    line = flags_tally( line, "team1", a22.size, flags_vals( a22 ) );
    line = flags_tally( line, "team2", a23.size, flags_vals( a23 ) );
    line = flags_tally( line, "spawn_type", a24.size, ( a24.size ? spawn_fv( a24[ 0 ] ) : "" ) );
    line = flags_tally( line, "type", a25.size, ( a25.size ? spawn_fv( a25[ 0 ] ) : "" ) );
    line = flags_tally( line, "script_label", a26.size, ( a26.size ? spawn_fv( a26[ 0 ] ) : "" ) );
    line = flags_tally( line, "script_gametype", a27.size, ( a27.size ? spawn_fv( a27[ 0 ] ) : "" ) );
    line = flags_tally( line, "script_gametype_sd", a28.size, flags_vals( a28 ) );
    line = flags_tally( line, "target", a29.size, ( a29.size ? spawn_fv( a29[ 0 ] ) : "" ) );
    line = flags_tally( line, "radius", a30.size, ( a30.size ? spawn_fv( a30[ 0 ] ) : "" ) );

    if ( line == "^3FLAGS2^7" )
        line += " none of the second batch";

    level.gf_flags_line2 = line;
    return line;
}

function private cfg_dbg_flags()    { return cfg_geti( #"gf_dbg_flags", 0 ); }
function private act_dbg_flags( item ) { return self act_dbg( item, #"gf_dbg_flags", 1, "marker flags" ); }

// ── ASSET CENSUS (gf_dbg_assets) — src/vehicle_probe + src/prop_probe as feed lines ─────
// Measured 2026-09-15 (vehicles.md §5): isassetloaded( "vehicle", #"name" ) - the PLAIN-STRING
// type argument, the only form stock uses - answers residency per map; the hashed-type form
// (#"vehicle") says yes to everything and is void. The 105 names are the dump's veh_t8/t9_*
// xmodel names; on mp_sm_gas_station exactly one is a resident vehicle asset (#82, the
// Chopper Gunner), so the model# names are a working candidate list for vehicle#.
// Computed once per round (level is rebuilt each round), then re-printed every tick.
//
//   VEHICLES <map> G=n E=n{type:count,...} M=n[i:name,...] S=n N=154
//     G  bogus-asset control - MUST BE 0 or the line is void
//     E  vehicle ENTITIES present in the level now (getvehiclearray) - the direct answer to
//        "which vehicles does this map have IN THIS MODE" - as index:namexcount for types in our
//        candidate list, u=n for types outside it. (No function_9e72a96: it is DEV-ONLY, crashes retail.)
//     M  resident vehicle ASSETS among the candidates, as index:name (index = list order below;
//        0-104 the veh_t9_* streak/xmodel style, 105+ the real vehicle_t9_*/wz names)
//     S  veh_spawn_point structs on this map (stock Path A, initvehiclemap - expect 0)
//   PROPS <map> tbl=n rows=n xs= s= m= l= xl= other= first=<model> res=n G=n
//     tbl  isassetloaded( "stringtable", gamedata/tables/mp/<map>_ph.csv ) - stock's own guard
//          before a table it is not sure of (scoreevents_shared.gsc:502). 0 = no table here.
//     rows the curated Prop Hunt props for this map (prop.gsc:1850), size buckets per column 1
//     first/res  row-0 model name, read live, and whether it is a resident xmodel
//
//   DESTRUCT <map> n=N kinds=K veh=V unnamed=U X=E [<def>xcount,...]
//     n     destructible ENTITIES in the level (getentarray "destructible" - destructible.gsc:23)
//     kinds distinct .destructibledef names among them; the first 10 listed with their counts.
//           These are the REAL asset names - the manifests hash every one (destructibles.md §4)
//     veh   how many are cars (def starts veh_, stock's own test at :30)
//     X     radiant exploders the OFFLINE table lists for this map (0 = the generator has no
//           row for this map name - check sv_mapname against docs/data/map-exploders.json)
//
// ⚠ getmapname() and tablelookupbyrow() in prop.gsc are SCRIPT functions, not builtins -
//    calling them bare crashed the game twice at link time. level.script + tablelookuprow.
function private assets_line_v()
{
    if ( isdefined( level.gf_assets_v ) )
        return level.gf_assets_v;

    names = assets_names();
    m = assets_candidates();
    n = 0;
    txt = "";

    for ( i = 0; i < m.size; i++ )
    {
        if ( isassetloaded( "vehicle", m[ i ] ) )
        {
            n++;

            if ( n <= 24 )
                txt += ( n > 1 ? "," : "" ) + i + ":" + names[ i ];
        }
    }

    bogus = isassetloaded( "vehicle", #"veh_t9_gf_probe_nonexistent_asset" ) ? 1 : 0;
    nodes = struct::get_array( "veh_spawn_point", "targetname" );
    spawnpoints = isdefined( nodes ) ? nodes.size : 0;

    // E = the vehicle ENTITIES present in the level right now. getvehiclearray() is a normal
    // builtin (type 0). We identify each by matching its .vehicletype against our own candidate
    // list by INDEX - NOT function_9e72a96(), which is a DEV-ONLY builtin (funcs_cw.csv type=1)
    // and crashes retail with "Dev only calls must be wrapped in a devblock" (klaze, 2026-09-15,
    // wz_duga + gas_station). Live types not in our list are counted in u=. Fireteam maps place
    // their vehicles in Radiant and the engine spawns them for that gametype only, so under
    // TDM/Gunfight the map's own vehicles do not exist as entities even where assets are resident.
    vehs = getvehiclearray();
    ecount = isdefined( vehs ) ? vehs.size : 0;
    unknown = 0;
    hit_i = [];
    hit_n = [];

    if ( isdefined( vehs ) )
    {
        foreach ( v in vehs )
        {
            vt = v.vehicletype;
            idx = -1;

            if ( isdefined( vt ) )
            {
                for ( k = 0; k < m.size; k++ )
                {
                    if ( m[ k ] == vt )
                    {
                        idx = k;
                        break;
                    }
                }
            }

            if ( idx < 0 )
            {
                unknown++;
                continue;
            }

            found = 0;

            for ( k = 0; k < hit_i.size; k++ )
            {
                if ( hit_i[ k ] == idx )
                {
                    hit_n[ k ]++;
                    found = 1;
                    break;
                }
            }

            if ( !found )
            {
                hit_i[ hit_i.size ] = idx;
                hit_n[ hit_n.size ] = 1;
            }
        }
    }

    etxt = "";

    for ( k = 0; k < hit_i.size && k < 16; k++ )
        etxt += ( k > 0 ? "," : "" ) + hit_i[ k ] + ":" + names[ hit_i[ k ] ] + "x" + hit_n[ k ];

    level.gf_assets_v = "^3VEHICLES^7 " + getdvarstring( #"sv_mapname", "?" ) + " G=" + bogus
        + " E=" + ecount + "{" + etxt + ( hit_i.size > 16 ? ",..." : "" ) + " u=" + unknown + "}"
        + " M=" + n + "[" + txt + ( n > 24 ? ",..." : "" ) + "] S=" + spawnpoints + " N=" + m.size;
    return level.gf_assets_v;
}

function private assets_line_p()
{
    if ( isdefined( level.gf_assets_p ) )
        return level.gf_assets_p;

    mapname = level.script;

    if ( !isdefined( mapname ) )
        mapname = util::get_map_name();

    path = "gamedata/tables/mp/" + mapname + "_ph.csv";
    bogus = isassetloaded( "xmodel", #"p9_gf_probe_nonexistent_prop" ) ? 1 : 0;
    head = "^3PROPS^7 " + getdvarstring( #"sv_mapname", "?" );

    if ( !isassetloaded( "stringtable", path ) )
    {
        level.gf_assets_p = head + " tbl=0 G=" + bogus;
        return level.gf_assets_p;
    }

    numrows = tablelookuprowcount( path );

    if ( !isdefined( numrows ) )
        numrows = 0;

    xs = 0; sm = 0; md = 0; lg = 0; xl = 0; other = 0;

    for ( i = 0; i < numrows; i++ )
    {
        switch ( assets_table_cell( path, i, 1 ) )
        {
            case #"xsmall": xs++; break;
            case #"small": sm++; break;
            case #"medium": md++; break;
            case #"large": lg++; break;
            case #"xlarge": xl++; break;
            default: other++; break;
        }
    }

    first = "-";
    res = "-";

    if ( numrows > 0 )
    {
        firstmodel = assets_table_cell( path, 0, 0 );

        if ( isdefined( firstmodel ) && firstmodel != "" )
        {
            first = firstmodel;
            res = isassetloaded( "xmodel", firstmodel ) ? 1 : 0;
        }
    }

    level.gf_assets_p = head + " tbl=1 rows=" + numrows + " xs=" + xs + " s=" + sm + " m=" + md
        + " l=" + lg + " xl=" + xl + " other=" + other + " first=" + first + " res=" + res + " G=" + bogus;
    return level.gf_assets_p;
}

// One pass over the level's destructibles: per-def names[] / counts[], the veh_ count and the
// unnamed count, cached on level for the round (a broken destructible is still an entity).
function private destruct_tally()
{
    if ( isdefined( level.gf_destruct_tally ) )
        return level.gf_destruct_tally;

    t = spawnstruct();
    t.n = 0;
    t.veh = 0;
    t.unnamed = 0;
    t.names = [];
    t.counts = [];

    foreach ( e in destruct_list() )
    {
        t.n++;
        d = destruct_def( e );

        if ( d == "?" )
        {
            t.unnamed++;
            continue;
        }

        if ( d.size >= 4 && getsubstr( d, 0, 4 ) == "veh_" )
            t.veh++;

        idx = -1;

        for ( k = 0; k < t.names.size; k++ )
        {
            if ( t.names[ k ] == d )
            {
                idx = k;
                break;
            }
        }

        if ( idx < 0 )
        {
            t.names[ t.names.size ] = d;
            t.counts[ t.counts.size ] = 1;
        }
        else
        {
            t.counts[ idx ]++;
        }
    }

    level.gf_destruct_tally = t;
    return t;
}

// "<def>x<count>,..." for the first max kinds.
function private destruct_tally_text( t, max )
{
    txt = "";

    for ( k = 0; k < t.names.size && k < max; k++ )
        txt += ( k > 0 ? "," : "" ) + t.names[ k ] + "x" + t.counts[ k ];

    if ( t.names.size > max )
        txt += ",...";

    return txt;
}

function private assets_line_d()
{
    if ( isdefined( level.gf_assets_d ) )
        return level.gf_assets_d;

    t = destruct_tally();
    level.gf_assets_d = "^3DESTRUCT^7 " + getdvarstring( #"sv_mapname", "?" ) + " n=" + t.n + " kinds=" + t.names.size
        + " veh=" + t.veh + " unnamed=" + t.unnamed + " X=" + exp_table().size + " [" + destruct_tally_text( t, 10 ) + "]";
    return level.gf_assets_d;
}

// prop.gsc:1834 as a local: the real builtin tablelookuprow( table, row ) returns the row as an array.
function private assets_table_cell( table, row, col )
{
    columns = tablelookuprow( table, row );

    if ( isdefined( columns ) && col < columns.size )
        return columns[ col ];

    return "";
}

// The 105 candidates, hashed (what the engine is asked). Same order as assets_names().
function private assets_candidates()
{
    c = [];
    c[c.size] = #"veh_t8_drone_hunter_mp_light";
    c[c.size] = #"veh_t8_drone_raps";
    c[c.size] = #"veh_t8_drone_recon_cp_light_small";
    c[c.size] = #"veh_t8_drone_siege_arm_d";
    c[c.size] = #"veh_t8_drone_siege_minigun_d";
    c[c.size] = #"veh_t8_drone_siege_rocket_d";
    c[c.size] = #"veh_t8_drone_wasp_piece_body_mp";
    c[c.size] = #"veh_t8_drone_wasp_piece_wing_rocket_left_mp";
    c[c.size] = #"veh_t8_drone_wasp_piece_wing_rocket_right_mp";
    c[c.size] = #"veh_t8_mil_air_gunship";
    c[c.size] = #"veh_t8_mil_air_jet_fighter_mp_dark";
    c[c.size] = #"veh_t8_mil_air_jet_fighter_mp_light";
    c[c.size] = #"veh_t8_mil_boat_tactical_raft";
    c[c.size] = #"veh_t8_mil_helicopter_light_debris_fastrope_bar";
    c[c.size] = #"veh_t8_mil_helicopter_light_debris_skids";
    c[c.size] = #"veh_t8_mil_helicopter_light_debris_tail";
    c[c.size] = #"veh_t8_mil_jet_cargo_gunship_pickup";
    c[c.size] = #"veh_t8_soviet_civ_sedan_midsize_dest_vehicle";
    c[c.size] = #"veh_t8_vintage_gaz66_troopbed";
    c[c.size] = #"veh_t9_civ_eu_2dr_wagon_blue";
    c[c.size] = #"veh_t9_civ_eu_2dr_wagon_red";
    c[c.size] = #"veh_t9_civ_eu_bicycle";
    c[c.size] = #"veh_t9_civ_eu_sedan_50s";
    c[c.size] = #"veh_t9_civ_eu_van_work";
    c[c.size] = #"veh_t9_civ_eu_wagon_50s";
    c[c.size] = #"veh_t9_civ_hatchback_80s_tan";
    c[c.size] = #"veh_t9_civ_hatchback_80s_tan_eu_tkd";
    c[c.size] = #"veh_t9_civ_ru_bus_large";
    c[c.size] = #"veh_t9_civ_ru_sedan_60s_vista";
    c[c.size] = #"veh_t9_civ_ru_sedan_80s";
    c[c.size] = #"veh_t9_civ_ru_sedan_80s_base";
    c[c.size] = #"veh_t9_civ_ru_sedan_80s_cp";
    c[c.size] = #"veh_t9_civ_ru_sedan_80s_cp_wet";
    c[c.size] = #"veh_t9_civ_ru_sedan_80s_kgb_cp";
    c[c.size] = #"veh_t9_civ_ru_sedan_80s_police_lit";
    c[c.size] = #"veh_t9_civ_ru_truck_light_hardtop_cp";
    c[c.size] = #"veh_t9_civ_us_station_wagon_vista_wht";
    c[c.size] = #"veh_t9_civ_us_truck_4x4_cp_duga";
    c[c.size] = #"veh_t9_civ_us_truck_4x4_cp_turkey";
    c[c.size] = #"veh_t9_civ_us_van_vista_window";
    c[c.size] = #"veh_t9_drone_rcxd_pickup";
    c[c.size] = #"veh_t9_mil_air_flogger_fly_napalm";
    c[c.size] = #"veh_t9_mil_air_flogger_pickup";
    c[c.size] = #"veh_t9_mil_air_transport_cp";
    c[c.size] = #"veh_t9_mil_gaz66_riders";
    c[c.size] = #"veh_t9_mil_helicopter_gunship_riders";
    c[c.size] = #"veh_t9_mil_remote_missile";
    c[c.size] = #"veh_t9_mil_remote_missile_pickup";
    c[c.size] = #"veh_t9_mil_ru_air_awacs_gear_down";
    c[c.size] = #"veh_t9_mil_ru_air_counter_spyplane_mp";
    c[c.size] = #"veh_t9_mil_ru_air_counter_spyplane_mp_friendly";
    c[c.size] = #"veh_t9_mil_ru_air_counter_spyplane_pickup";
    c[c.size] = #"veh_t9_mil_ru_air_flogger_flight";
    c[c.size] = #"veh_t9_mil_ru_air_frogfoot_mp";
    c[c.size] = #"veh_t9_mil_ru_air_frogfoot_pickup";
    c[c.size] = #"veh_t9_mil_ru_air_spyplane_friendly_mp";
    c[c.size] = #"veh_t9_mil_ru_air_spyplane_mp";
    c[c.size] = #"veh_t9_mil_ru_air_spyplane_pickup";
    c[c.size] = #"veh_t9_mil_ru_air_vtol_forger_cockpit";
    c[c.size] = #"veh_t9_mil_ru_air_vtol_forger_flight";
    c[c.size] = #"veh_t9_mil_ru_air_vtol_forger_pickup";
    c[c.size] = #"veh_t9_mil_ru_heli_gunship_hind";
    c[c.size] = #"veh_t9_mil_ru_heli_gunship_hind_yam";
    c[c.size] = #"veh_t9_mil_ru_truck_50s_cargo_delivery_tenla_market";
    c[c.size] = #"veh_t9_mil_ru_truck_light_base";
    c[c.size] = #"veh_t9_mil_ru_truck_light_mp_tundra";
    c[c.size] = #"veh_t9_mil_ru_truck_transport";
    c[c.size] = #"veh_t9_mil_snowmobile_spawn_medpack";
    c[c.size] = #"veh_t9_mil_snowmobile_spawn_ski";
    c[c.size] = #"veh_t9_mil_us_air_aurora_spyplane_friendly";
    c[c.size] = #"veh_t9_mil_us_air_napalm_bomb_projectile";
    c[c.size] = #"veh_t9_mil_us_air_napalm_bomb_projectile_lrg";
    c[c.size] = #"veh_t9_mil_us_air_napalm_strike";
    c[c.size] = #"veh_t9_mil_us_air_napalm_strike_pickup";
    c[c.size] = #"veh_t9_mil_us_air_napalm_strike_vista";
    c[c.size] = #"veh_t9_mil_us_air_snake";
    c[c.size] = #"veh_t9_mil_us_air_snake_finish_move_vehicle";
    c[c.size] = #"veh_t9_mil_us_air_snake_pickup";
    c[c.size] = #"veh_t9_mil_us_air_snake_riders";
    c[c.size] = #"veh_t9_mil_us_air_transport_hpc_intro";
    c[c.size] = #"veh_t9_mil_us_air_transport_static_ground";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_armada_turret_base";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_chopper_gunner";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_cp_armada";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_cp_armada_02";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_cp_prisoner_dest";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_cp_takedown";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_pickup";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_riders";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_riders_armada_ai";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_riders_armada_player";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_static";
    c[c.size] = #"veh_t9_mil_us_helicopter_large_vip_settings";
    c[c.size] = #"veh_t9_mil_us_helicopter_light_zm_sv_intro_static";
    c[c.size] = #"veh_t9_mil_us_turret_lmg_stationary_cp";
    c[c.size] = #"veh_t9_mphd_uaz_riders";
    c[c.size] = #"veh_t9_mphd_uaz_riders_amk";
    c[c.size] = #"veh_t9_mphd_uaz_riders_takedown";
    c[c.size] = #"veh_t9_rcxd_finish_prop_fin_move";
    c[c.size] = #"veh_t9_sv_atv_payload";
    c[c.size] = #"veh_t9_sv_truck_hemtt_payload_delivery";
    c[c.size] = #"veh_t9_turret_m60_riders";
    c[c.size] = #"veh_t9_turret_mg_riders";
    c[c.size] = #"veh_t9_zm_arc_xd";
    c[c.size] = #"veh_t9_zm_ndu_mil_tank_tiger";
    // batch 2 (index 105+): the REAL vehicle namespace - Fireteam player vehicles, their
    // hashed siblings, MP streak/insertion/supply vehicles - harvested from the dump 2026-09-15
    // after klaze read "just the Chopper Gunner" on Ruka, a map with a dozen vehicle kinds.
    c[c.size] = #"vehicle_t9_mil_fav_light";
    c[c.size] = #"veh_mil_ru_fav_heavy";
    c[c.size] = #"vehicle_t9_mil_snowmobile";
    c[c.size] = #"vehicle_t9_mil_ru_truck_light_player";
    c[c.size] = #"vehicle_t9_civ_ru_sedan_80s_player";
    c[c.size] = #"vehicle_motorcycle_mil_us_offroad";
    c[c.size] = #"veh_quad_player_wz_blk";
    c[c.size] = #"veh_quad_player_wz_grn";
    c[c.size] = #"veh_quad_player_wz_tan";
    c[c.size] = #"vehicle_t9_mil_ru_truck_transport_player";
    c[c.size] = #"vehicle_t9_mil_ru_truck_transport_player_obj_sr";
    c[c.size] = #"vehicle_t9_mil_ru_tank_t72_sr";
    c[c.size] = #"vehicle_t8_mil_tank_wz_base_mg";
    c[c.size] = #"vehicle_t9_mil_ru_heli_gunship_hind_wz";
    c[c.size] = #"vehicle_t9_plane_flyable_prototype";
    c[c.size] = #"veh_boct_mil_jetski";
    c[c.size] = #"vehicle_boct_mil_boat_pbr";
    c[c.size] = #"vehicle_t9_mil_boat_tactical_raft_bundle_settings";
    c[c.size] = #"hash_17e868e0ebf3c1d6";
    c[c.size] = #"hash_232abda4e81275f4";
    c[c.size] = #"hash_28d512b739c9d9c1";
    c[c.size] = #"hash_2a245bf3738fed8b";
    c[c.size] = #"hash_2c0e11a1e87bbcd5";
    c[c.size] = #"hash_2d32c08b862baa46";
    c[c.size] = #"hash_2f8d60a5381870ee";
    c[c.size] = #"hash_42b91f3544c1a9e1";
    c[c.size] = #"hash_6595f5efe62a4ec";
    c[c.size] = #"hash_985b7e40ee02aa2";
    c[c.size] = #"hash_dd63f34c77a725e";
    c[c.size] = #"vehicle_t9_mil_helicopter_care_package";
    c[c.size] = #"vehicle_t9_mil_ru_heli_transport_vehicle_drop";
    c[c.size] = #"vehicle_t8_mil_air_transport_infiltration";
    c[c.size] = #"vehicle_t8_mil_helicopter_transport_dark_wz_infiltration";
    c[c.size] = #"vehicle_t8_mil_helicopter_gunship_wz_infiltration";
    c[c.size] = #"vehicle_t8_mil_helicopter_light_transport_wz_infil";
    c[c.size] = #"vehicle_t9_mil_air_transport_hpc_intro";
    c[c.size] = #"vehicle_t9_mil_us_helicopter_large_mp_intro";
    c[c.size] = #"vehicle_t9_mil_us_helicopter_large_vip_extract_anims";
    c[c.size] = #"vehicle_t9_rcxd_racing";
    c[c.size] = #"veh_t7_mil_vtol_fighter_mp";
    c[c.size] = #"veh_t6_air_a10f";
    c[c.size] = #"veh_t7_drone_hunter";
    c[c.size] = #"veh_flak_drone_mp";
    c[c.size] = #"vehicle_ac130";
    c[c.size] = #"vehicle_t9_mil_us_helicopter_large_cp_armada_player";
    c[c.size] = #"vehicle_t9_mil_us_truck_m35_canvas_cp";
    c[c.size] = #"vehicle_t9_mil_us_truck_m35_cargo_cp";
    c[c.size] = #"vehicle_t9_mil_us_truck_m35_tanker_cp";
    c[c.size] = #"vehicle_t9_mil_ru_truck_light_cp_canvas_top";
    return c;
}

// The same 105 as display strings, SAME ORDER - never handed to the engine.
function private assets_names()
{
    c = [];
    c[c.size] = "veh_t8_drone_hunter_mp_light";
    c[c.size] = "veh_t8_drone_raps";
    c[c.size] = "veh_t8_drone_recon_cp_light_small";
    c[c.size] = "veh_t8_drone_siege_arm_d";
    c[c.size] = "veh_t8_drone_siege_minigun_d";
    c[c.size] = "veh_t8_drone_siege_rocket_d";
    c[c.size] = "veh_t8_drone_wasp_piece_body_mp";
    c[c.size] = "veh_t8_drone_wasp_piece_wing_rocket_left_mp";
    c[c.size] = "veh_t8_drone_wasp_piece_wing_rocket_right_mp";
    c[c.size] = "veh_t8_mil_air_gunship";
    c[c.size] = "veh_t8_mil_air_jet_fighter_mp_dark";
    c[c.size] = "veh_t8_mil_air_jet_fighter_mp_light";
    c[c.size] = "veh_t8_mil_boat_tactical_raft";
    c[c.size] = "veh_t8_mil_helicopter_light_debris_fastrope_bar";
    c[c.size] = "veh_t8_mil_helicopter_light_debris_skids";
    c[c.size] = "veh_t8_mil_helicopter_light_debris_tail";
    c[c.size] = "veh_t8_mil_jet_cargo_gunship_pickup";
    c[c.size] = "veh_t8_soviet_civ_sedan_midsize_dest_vehicle";
    c[c.size] = "veh_t8_vintage_gaz66_troopbed";
    c[c.size] = "veh_t9_civ_eu_2dr_wagon_blue";
    c[c.size] = "veh_t9_civ_eu_2dr_wagon_red";
    c[c.size] = "veh_t9_civ_eu_bicycle";
    c[c.size] = "veh_t9_civ_eu_sedan_50s";
    c[c.size] = "veh_t9_civ_eu_van_work";
    c[c.size] = "veh_t9_civ_eu_wagon_50s";
    c[c.size] = "veh_t9_civ_hatchback_80s_tan";
    c[c.size] = "veh_t9_civ_hatchback_80s_tan_eu_tkd";
    c[c.size] = "veh_t9_civ_ru_bus_large";
    c[c.size] = "veh_t9_civ_ru_sedan_60s_vista";
    c[c.size] = "veh_t9_civ_ru_sedan_80s";
    c[c.size] = "veh_t9_civ_ru_sedan_80s_base";
    c[c.size] = "veh_t9_civ_ru_sedan_80s_cp";
    c[c.size] = "veh_t9_civ_ru_sedan_80s_cp_wet";
    c[c.size] = "veh_t9_civ_ru_sedan_80s_kgb_cp";
    c[c.size] = "veh_t9_civ_ru_sedan_80s_police_lit";
    c[c.size] = "veh_t9_civ_ru_truck_light_hardtop_cp";
    c[c.size] = "veh_t9_civ_us_station_wagon_vista_wht";
    c[c.size] = "veh_t9_civ_us_truck_4x4_cp_duga";
    c[c.size] = "veh_t9_civ_us_truck_4x4_cp_turkey";
    c[c.size] = "veh_t9_civ_us_van_vista_window";
    c[c.size] = "veh_t9_drone_rcxd_pickup";
    c[c.size] = "veh_t9_mil_air_flogger_fly_napalm";
    c[c.size] = "veh_t9_mil_air_flogger_pickup";
    c[c.size] = "veh_t9_mil_air_transport_cp";
    c[c.size] = "veh_t9_mil_gaz66_riders";
    c[c.size] = "veh_t9_mil_helicopter_gunship_riders";
    c[c.size] = "veh_t9_mil_remote_missile";
    c[c.size] = "veh_t9_mil_remote_missile_pickup";
    c[c.size] = "veh_t9_mil_ru_air_awacs_gear_down";
    c[c.size] = "veh_t9_mil_ru_air_counter_spyplane_mp";
    c[c.size] = "veh_t9_mil_ru_air_counter_spyplane_mp_friendly";
    c[c.size] = "veh_t9_mil_ru_air_counter_spyplane_pickup";
    c[c.size] = "veh_t9_mil_ru_air_flogger_flight";
    c[c.size] = "veh_t9_mil_ru_air_frogfoot_mp";
    c[c.size] = "veh_t9_mil_ru_air_frogfoot_pickup";
    c[c.size] = "veh_t9_mil_ru_air_spyplane_friendly_mp";
    c[c.size] = "veh_t9_mil_ru_air_spyplane_mp";
    c[c.size] = "veh_t9_mil_ru_air_spyplane_pickup";
    c[c.size] = "veh_t9_mil_ru_air_vtol_forger_cockpit";
    c[c.size] = "veh_t9_mil_ru_air_vtol_forger_flight";
    c[c.size] = "veh_t9_mil_ru_air_vtol_forger_pickup";
    c[c.size] = "veh_t9_mil_ru_heli_gunship_hind";
    c[c.size] = "veh_t9_mil_ru_heli_gunship_hind_yam";
    c[c.size] = "veh_t9_mil_ru_truck_50s_cargo_delivery_tenla_market";
    c[c.size] = "veh_t9_mil_ru_truck_light_base";
    c[c.size] = "veh_t9_mil_ru_truck_light_mp_tundra";
    c[c.size] = "veh_t9_mil_ru_truck_transport";
    c[c.size] = "veh_t9_mil_snowmobile_spawn_medpack";
    c[c.size] = "veh_t9_mil_snowmobile_spawn_ski";
    c[c.size] = "veh_t9_mil_us_air_aurora_spyplane_friendly";
    c[c.size] = "veh_t9_mil_us_air_napalm_bomb_projectile";
    c[c.size] = "veh_t9_mil_us_air_napalm_bomb_projectile_lrg";
    c[c.size] = "veh_t9_mil_us_air_napalm_strike";
    c[c.size] = "veh_t9_mil_us_air_napalm_strike_pickup";
    c[c.size] = "veh_t9_mil_us_air_napalm_strike_vista";
    c[c.size] = "veh_t9_mil_us_air_snake";
    c[c.size] = "veh_t9_mil_us_air_snake_finish_move_vehicle";
    c[c.size] = "veh_t9_mil_us_air_snake_pickup";
    c[c.size] = "veh_t9_mil_us_air_snake_riders";
    c[c.size] = "veh_t9_mil_us_air_transport_hpc_intro";
    c[c.size] = "veh_t9_mil_us_air_transport_static_ground";
    c[c.size] = "veh_t9_mil_us_helicopter_large_armada_turret_base";
    c[c.size] = "veh_t9_mil_us_helicopter_large_chopper_gunner";
    c[c.size] = "veh_t9_mil_us_helicopter_large_cp_armada";
    c[c.size] = "veh_t9_mil_us_helicopter_large_cp_armada_02";
    c[c.size] = "veh_t9_mil_us_helicopter_large_cp_prisoner_dest";
    c[c.size] = "veh_t9_mil_us_helicopter_large_cp_takedown";
    c[c.size] = "veh_t9_mil_us_helicopter_large_pickup";
    c[c.size] = "veh_t9_mil_us_helicopter_large_riders";
    c[c.size] = "veh_t9_mil_us_helicopter_large_riders_armada_ai";
    c[c.size] = "veh_t9_mil_us_helicopter_large_riders_armada_player";
    c[c.size] = "veh_t9_mil_us_helicopter_large_static";
    c[c.size] = "veh_t9_mil_us_helicopter_large_vip_settings";
    c[c.size] = "veh_t9_mil_us_helicopter_light_zm_sv_intro_static";
    c[c.size] = "veh_t9_mil_us_turret_lmg_stationary_cp";
    c[c.size] = "veh_t9_mphd_uaz_riders";
    c[c.size] = "veh_t9_mphd_uaz_riders_amk";
    c[c.size] = "veh_t9_mphd_uaz_riders_takedown";
    c[c.size] = "veh_t9_rcxd_finish_prop_fin_move";
    c[c.size] = "veh_t9_sv_atv_payload";
    c[c.size] = "veh_t9_sv_truck_hemtt_payload_delivery";
    c[c.size] = "veh_t9_turret_m60_riders";
    c[c.size] = "veh_t9_turret_mg_riders";
    c[c.size] = "veh_t9_zm_arc_xd";
    c[c.size] = "veh_t9_zm_ndu_mil_tank_tiger";
    c[c.size] = "vehicle_t9_mil_fav_light";
    c[c.size] = "veh_mil_ru_fav_heavy";
    c[c.size] = "vehicle_t9_mil_snowmobile";
    c[c.size] = "vehicle_t9_mil_ru_truck_light_player";
    c[c.size] = "vehicle_t9_civ_ru_sedan_80s_player";
    c[c.size] = "vehicle_motorcycle_mil_us_offroad";
    c[c.size] = "veh_quad_player_wz_blk";
    c[c.size] = "veh_quad_player_wz_grn";
    c[c.size] = "veh_quad_player_wz_tan";
    c[c.size] = "vehicle_t9_mil_ru_truck_transport_player";
    c[c.size] = "vehicle_t9_mil_ru_truck_transport_player_obj_sr";
    c[c.size] = "vehicle_t9_mil_ru_tank_t72_sr";
    c[c.size] = "vehicle_t8_mil_tank_wz_base_mg";
    c[c.size] = "vehicle_t9_mil_ru_heli_gunship_hind_wz";
    c[c.size] = "vehicle_t9_plane_flyable_prototype";
    c[c.size] = "veh_boct_mil_jetski";
    c[c.size] = "vehicle_boct_mil_boat_pbr";
    c[c.size] = "vehicle_t9_mil_boat_tactical_raft_bundle_settings";
    c[c.size] = "hash_17e868e0ebf3c1d6";
    c[c.size] = "hash_232abda4e81275f4";
    c[c.size] = "hash_28d512b739c9d9c1";
    c[c.size] = "hash_2a245bf3738fed8b";
    c[c.size] = "hash_2c0e11a1e87bbcd5";
    c[c.size] = "hash_2d32c08b862baa46";
    c[c.size] = "hash_2f8d60a5381870ee";
    c[c.size] = "hash_42b91f3544c1a9e1";
    c[c.size] = "hash_6595f5efe62a4ec";
    c[c.size] = "hash_985b7e40ee02aa2";
    c[c.size] = "hash_dd63f34c77a725e";
    c[c.size] = "vehicle_t9_mil_helicopter_care_package";
    c[c.size] = "vehicle_t9_mil_ru_heli_transport_vehicle_drop";
    c[c.size] = "vehicle_t8_mil_air_transport_infiltration";
    c[c.size] = "vehicle_t8_mil_helicopter_transport_dark_wz_infiltration";
    c[c.size] = "vehicle_t8_mil_helicopter_gunship_wz_infiltration";
    c[c.size] = "vehicle_t8_mil_helicopter_light_transport_wz_infil";
    c[c.size] = "vehicle_t9_mil_air_transport_hpc_intro";
    c[c.size] = "vehicle_t9_mil_us_helicopter_large_mp_intro";
    c[c.size] = "vehicle_t9_mil_us_helicopter_large_vip_extract_anims";
    c[c.size] = "vehicle_t9_rcxd_racing";
    c[c.size] = "veh_t7_mil_vtol_fighter_mp";
    c[c.size] = "veh_t6_air_a10f";
    c[c.size] = "veh_t7_drone_hunter";
    c[c.size] = "veh_flak_drone_mp";
    c[c.size] = "vehicle_ac130";
    c[c.size] = "vehicle_t9_mil_us_helicopter_large_cp_armada_player";
    c[c.size] = "vehicle_t9_mil_us_truck_m35_canvas_cp";
    c[c.size] = "vehicle_t9_mil_us_truck_m35_cargo_cp";
    c[c.size] = "vehicle_t9_mil_us_truck_m35_tanker_cp";
    c[c.size] = "vehicle_t9_mil_ru_truck_light_cp_canvas_top";
    return c;
}

// ═════════════════════════════════════════════════════════════════════════════
// SPAWN GUARD — ported from gunfight_mod (game-systems sec 16b), dvar-driven here.
// Fixes combined-arms/large-variant OOB / odd spawns by repositioning each player
// onto a CENTRAL, real spawn struct for their team. Only ever uses EXISTING structs,
// so every destination is designer-placed and mesh-valid. Fails safe (< 2 points =>
// no-op, stock spawns stand). ⚠ UNTESTED — validate SOLO first (watch where you spawn).
// ═════════════════════════════════════════════════════════════════════════════

function private mod_spawn_build()
{
    // AUTO (mode 2) used to gate on mod_spawn_needs_guard() here - a detector built on the
    // legacy mp_tdm_spawn_*_start names, which CW does not ship, so it read "too few starts"
    // on every map. Since 2026-09-14 AUTO decides PER SPAWN in mod_spawn_override with the
    // engine's own start picker; the anchors are always built (cheap) and only used when
    // the engine has nothing. Force (mode 1) uses them always.
    pts = mod_gather_spawns();

    if ( !isdefined( pts ) || pts.size < 2 )
    {
        level.gfmenu_spawn = undefined;
        if ( cfg_spawn_diag() )
            mod_gf_emit( 61, isdefined( pts ) ? pts.size : 0 );   // inert: too few points
        return;
    }

    center = mod_centroid( pts );
    level.gf_family_note = "";

    // A spawn FAMILY: only that mode's markers, and its own sides when the markers name them.
    fam = cfg_spawn_family();
    if ( fam == 8 )
        fam = mod_family_auto( pts );   // S&D starts when authored on both sides, else TDM
    if ( fam != 0 )
    {
        fpts = [];
        foreach ( p in pts )
        {
            if ( mod_marker_has( p, fam ) )
                fpts[ fpts.size ] = p;
        }

        // The map's AUTHORED team starts for this mode - the exact points the engine's own
        // start_spawn list holds (mode flag + start flag + group_index, see the spawn keys
        // above) plus the legacy-named start structs the remasters keep: use them as they
        // are, own angles, no geometry. What "proper S&D / TDM spawns" means (klaze,
        // 2026-09-15). Read from the FULL pool - a named start carries no mode flag. A side
        // with fewer than 2 authored falls through to the older side-field / geometric search.
        st = mod_family_starts( pts, fam );
        if ( st.a1.size >= 2 && st.a2.size >= 2 )
        {
            level.gf_family_note = family_name( fam ) + ":" + fpts.size + ( ( fam == 2 && mod_spawn_groups().g1.size > 0 ) ? " group " : " starts " ) + st.a1.size + "/" + st.a2.size;
            rp0 = isdefined( game.roundsplayed ) ? game.roundsplayed : 0;
            level.gfmenu_spawn = { #team1:mod_shuffle( mod_anchor_authored( st.a1 ) ), #team2:mod_shuffle( mod_anchor_authored( st.a2 ) ), #next1:0, #next2:0, #round:rp0 };
            if ( cfg_spawn_diag() )
                mod_gf_emit( 60, st.a1.size + st.a2.size );
            return;
        }

        if ( fpts.size < 4 )
        {
            level.gfmenu_spawn = undefined;
            level.gf_family_note = family_name( fam ) + ":none";
            return;
        }

        pts = fpts;
        center = mod_centroid( pts );

        s1 = [];
        s2 = [];
        foreach ( p in pts )
        {
            side = mod_marker_side( p, fam );
            if ( side == 1 )
                s1[ s1.size ] = p;
            else if ( side == 2 )
                s2[ s2.size ] = p;
        }

        if ( s1.size >= 2 && s2.size >= 2 )
        {
            // The map's own sides for this family - use them as they are.
            c1 = mod_centroid( s1 );
            c2 = mod_centroid( s2 );
            team1 = mod_anchor_copies( s1, c2 );
            team2 = mod_anchor_copies( s2, c1 );
            level.gf_family_note = family_name( fam ) + ":" + pts.size + " sides " + s1.size + "/" + s2.size;
            rp0 = isdefined( game.roundsplayed ) ? game.roundsplayed : 0;
            level.gfmenu_spawn = { #team1:mod_shuffle( team1 ), #team2:mod_shuffle( team2 ), #next1:0, #next2:0, #round:rp0 };
            return;
        }

        level.gf_family_note = family_name( fam ) + ":" + pts.size + " nosides->geo";
    }

    // A kept Strike area (mod_layout_keep) bounds the search: only markers inside its ring,
    // centred on it - so the sides are built inside the playable area, not out on the
    // full map. Falls back to every marker when too few are inside.
    if ( isdefined( level.gf_area_center ) && isdefined( level.gf_area_radius ) )
    {
        inside = [];
        r2 = level.gf_area_radius * level.gf_area_radius;
        foreach ( p in pts )
        {
            if ( mod_dist2d_sq( p.origin, level.gf_area_center ) <= r2 )
                inside[ inside.size ] = p;
        }
        if ( inside.size >= 12 )
        {
            pts = inside;
            center = level.gf_area_center;
        }
    }

    // TWO SIDES A REAL DISTANCE APART (klaze, 2026-09-14, Crossroads: with the old central
    // split - one blob cut at its median, sides 680u apart - "we all spawned together").
    // The markers carry no mode flags script can read (STRUCTS line: targetname, origin,
    // angles, nothing else), so the sides are chosen geometrically: for four axes through
    // the map's marker centroid and three gaps around gf_spawn_gap, take each side's
    // per_side nearest markers to the two ideal points C -/+ axis*gap/2 (no marker on both
    // sides), and keep the configuration whose groups are tightest and whose separation is
    // closest to the gap. Every anchor is still a designer-placed marker; each is copied
    // into a fresh struct whose angles face the OTHER side's centre, so a Gunfight round
    // opens with both teams looking at each other, the way the real maps do.
    per_side = cfg_team_size() + 2;
    if ( per_side < 6 )
        per_side = 6;

    gap = cfg_spawn_gap();
    best = undefined;
    bestscore = 0;

    // PICK: far ends (klaze, 2026-09-15 - "in real TDM the opening spawns are further back on
    // the boat, respawns closer up; Gunfight-with-TDM-family uses the closer version"). TDM's
    // openings are the engine's start_spawn list = the two extremes; this rebuilds that from
    // the markers: on each axis the per_side markers nearest the two outermost projections,
    // scored tight-and-far. The gap-based pick (0, default) is the "closer up" version.
    if ( cfg_spawn_pick() == 1 )
    {
        for ( a = 0; a < 4; a++ )
        {
            dir = mod_axis_dir( a );
            lo = 0;
            hi = 0;
            foreach ( p in pts )
            {
                pr = ( p.origin[ 0 ] - center[ 0 ] ) * dir[ 0 ] + ( p.origin[ 1 ] - center[ 1 ] ) * dir[ 1 ];
                if ( pr < lo ) lo = pr;
                if ( pr > hi ) hi = pr;
            }
            p1 = center + vectorscale( dir, lo );
            p2 = center + vectorscale( dir, hi );
            t1 = mod_nearest_k_excl( pts, p1, per_side, undefined, undefined, undefined, 0, 0 );
            t2 = mod_nearest_k_excl( pts, p2, per_side, t1, undefined, undefined, 0, 0 );
            if ( t1.size < 3 || t2.size < 3 )
                continue;
            c1 = mod_centroid( t1 );
            c2 = mod_centroid( t2 );
            sep = sqrt( mod_dist2d_sq( c1, c2 ) );
            score = mod_mean_dist2d( t1, c1 ) + mod_mean_dist2d( t2, c2 ) - sep * 0.25;
            if ( !isdefined( best ) || score < bestscore )
            {
                best = { #t1:t1, #t2:t2, #c1:c1, #c2:c2, #sep:sep };
                bestscore = score;
            }
        }
    }

    for ( a = 0; a < 4 && cfg_spawn_pick() == 0; a++ )
    {
        dir = mod_axis_dir( a );

        for ( g = 0; g < 3; g++ )
        {
            gg = gap;
            if ( g == 1 )
                gg = gap * 1.25;
            else if ( g == 2 )
                gg = gap * 1.5;

            // Each side only draws from markers at least (gg/2 - 150) out from the centre
            // on its own side of the axis - a HARD constraint, so the dense middle cannot
            // pull both groups together (first run: gap 1200 gave sep 661).
            p1 = center - vectorscale( dir, gg / 2 );
            p2 = center + vectorscale( dir, gg / 2 );
            t1 = mod_nearest_k_excl( pts, p1, per_side, undefined, center, dir, -1, gg / 2 - 150 );
            t2 = mod_nearest_k_excl( pts, p2, per_side, t1, center, dir, 1, gg / 2 - 150 );

            if ( t1.size < 3 || t2.size < 3 )
                continue;

            c1 = mod_centroid( t1 );
            c2 = mod_centroid( t2 );
            sep = sqrt( mod_dist2d_sq( c1, c2 ) );
            score = mod_mean_dist2d( t1, c1 ) + mod_mean_dist2d( t2, c2 ) + abs( sep - gap );

            if ( !isdefined( best ) || score < bestscore )
            {
                best = { #t1:t1, #t2:t2, #c1:c1, #c2:c2, #sep:sep };
                bestscore = score;
            }
        }
    }

    // No axis had 3+ markers far enough out on both sides (a tiny map): fall back to the
    // unconstrained nearest groups so the guard still arms.
    if ( !isdefined( best ) )
    {
        dir = mod_axis_dir( 0 );
        t1 = mod_nearest_k_excl( pts, center - vectorscale( dir, gap / 2 ), per_side, undefined, undefined, undefined, 0, 0 );
        t2 = mod_nearest_k_excl( pts, center + vectorscale( dir, gap / 2 ), per_side, t1, undefined, undefined, 0, 0 );
        if ( t1.size == 0 || t2.size == 0 )
        {
            level.gfmenu_spawn = undefined;
            return;
        }
        best = { #t1:t1, #t2:t2, #c1:mod_centroid( t1 ), #c2:mod_centroid( t2 ), #sep:0 };
    }

    team1 = mod_anchor_copies( best.t1, best.c2 );
    team2 = mod_anchor_copies( best.t2, best.c1 );

    // Shuffled once per round; mod_spawn_place hands them out in order so no two
    // players of a side land on the same struct (a telefrag at worst, a pile at best).
    // #round tracks the round the current shuffle is for, so mod_spawn_place can reshuffle
    // when the round advances (this build runs once per MATCH - see mod_spawn_place).
    rp0 = isdefined( game.roundsplayed ) ? game.roundsplayed : 0;
    level.gfmenu_spawn = { #team1:mod_shuffle( team1 ), #team2:mod_shuffle( team2 ), #next1:0, #next2:0, #round:rp0 };

    if ( cfg_spawn_diag() )
        mod_gf_emit( 60, pts.size );   // armed, N spawn points gathered
}

// ── AUTO detection ───────────────────────────────────────────────────────────
// Is THIS map one whose Gunfight start spawns are the wrong (12v12) layout?
//
// Gunfight is hardwired to the TDM START spawns: main() does
// addsupportedspawnpointtype("tdm") + alwaysusestartspawns=1, and the engine draws from
// mp_tdm_spawn_<team>_start (spawning.gsc gettdmstartspawnname). Every standard MP map
// ships those, so Gunfight spawns everywhere - but on the combined-arms maps
// (Armada mp_black_sea, Collateral mp_dune, Crossroads mp_tundra) the map script keeps
// the 12v12 layout active because "gunfight" is not in its war12v12/tdm10v10/... list
// (mp_black_sea.gsc:130, game-systems 16b), so those start markers sit out in the 12v12
// staging areas - far from where the map's OBJECTIVE spawns (Domination/S&D/generic, laid
// out for the 6v6 footprint) are. That distance is the signal, and reading spawn origins
// from script needs no per-map data (the dump ships none anyway).
//
// Measure: obj = the objective/6v6 spawn pool -> centroid + mean radius. starts = the TDM
// start markers -> nearest one to that centroid. If even the CLOSEST start spawn is farther
// than (radius + gf_spawn_autospread), the starts are the wrong layout -> guard. A normal
// map always has some start near its objective cluster, so it reads "not needed" and keeps
// stock spawns. Emits the raw numbers (62/63/64) so the trip point calibrates on run 1.
function private mod_spawn_needs_guard()
{
    starts = mod_gather_named( mod_start_families() );

    // Too few start spawns to judge (or to seat the match) - guard from the pool instead.
    if ( starts.size < 2 )
    {
        if ( cfg_spawn_diag() )
            mod_gf_emit( 64, 1 );
        return true;
    }

    // The map's objective/6v6 spawns: generic mp_spawn_point plus Domination and S&D, which
    // are placed for the small footprint on exactly the maps that break. This is also the
    // "proper dom/sd-located spawns" source the reposition below draws its central cluster from.
    obj = mod_gather_named( mod_obj_families() );

    // Can't characterise the footprint - don't override stock spawns (conservative).
    if ( obj.size < 4 )
    {
        if ( cfg_spawn_diag() )
            mod_gf_emit( 64, 0 );
        return false;
    }

    c = mod_centroid( obj );
    objrad  = mod_mean_dist2d( obj, c );
    startmin = mod_min_dist2d( starts, c );
    needed = startmin > ( objrad + cfg_spawn_autospread() );

    if ( cfg_spawn_diag() )
    {
        mod_gf_emit( 62, int( min( objrad, 99999 ) ) );
        mod_gf_emit( 63, int( min( startmin, 99999 ) ) );
        mod_gf_emit( 64, needed ? 1 : 0 );
    }

    return needed;
}

// The two family lists the AUTO detector compares. []-built, never bare array() (see the
// note on mod_spawn_families / keys_init - stock MP has zero bare array() calls).
// starts = what Gunfight actually spawns on; obj = the map's 6v6 objective footprint.
function private mod_start_families()
{
    names = [];
    names[ names.size ] = "mp_tdm_spawn_allies_start";
    names[ names.size ] = "mp_tdm_spawn_axis_start";
    names[ names.size ] = "mp_tdm_spawn_team1_start";
    names[ names.size ] = "mp_tdm_spawn_team2_start";
    return names;
}

function private mod_obj_families()
{
    names = [];
    names[ names.size ] = "mp_spawn_point";
    names[ names.size ] = "mp_spawn_point_allies";
    names[ names.size ] = "mp_spawn_point_axis";
    names[ names.size ] = "mp_dom_spawn_allies_start";
    names[ names.size ] = "mp_dom_spawn_axis_start";
    names[ names.size ] = "mp_dom_spawn";
    names[ names.size ] = "mp_sd_spawn_attacker";
    names[ names.size ] = "mp_sd_spawn_defender";
    return names;
}

// struct::get_array over a passed name list (mod_gather_spawns is the same over the full
// family set). Skips structs with no origin.
function private mod_gather_named( names )
{
    pts = [];

    foreach ( n in names )
    {
        arr = struct::get_array( n, "targetname" );

        if ( isdefined( arr ) )
        {
            foreach ( s in arr )
            {
                if ( isdefined( s ) && isdefined( s.origin ) )
                    pts[ pts.size ] = s;
            }
        }
    }

    return pts;
}

function private mod_mean_dist2d( pts, center )
{
    if ( pts.size == 0 )
        return 0;

    sum = 0;
    foreach ( p in pts )
        sum += sqrt( mod_dist2d_sq( p.origin, center ) );

    return sum / pts.size;
}

function private mod_min_dist2d( pts, center )
{
    best = -1;
    foreach ( p in pts )
    {
        d = sqrt( mod_dist2d_sq( p.origin, center ) );
        if ( best < 0 || d < best )
            best = d;
    }

    return ( best < 0 ) ? 0 : best;
}

// Fires on every spawn (registered in __init__). No-op unless the flag is on and anchors
// were built this round. Repositions the player onto a central spawn for their team.
// ── The pre-spawn override (path 1) — built 2026-09-14 after klaze's Crossroads read ────
// MEASURED (docs/notes/spawn-system.md §5): on Crossroads under gunfight the host spawned at
// 0,0,0, 1082u from the nearest marker - path 4, the map-centre fallback: the engine's
// start list AND its scored lists had nothing for this gametype, so it fell through to
// level.mapcenter. Every further player lands on the same point (the pile). The on_spawned
// teleport (mod_spawn_place) fixes the position a frame late; this fixes the SPAWN itself
// through the engine's own hook: spawning_shared.gsc onspawnplayer() :198 calls
// level.var_cda5136b( predictedspawn ) first and, when it returns true, does nothing else -
// the callback has placed the player (stock's contract: `self spawn( origin, angles )`).
// Nothing in MP installs that hook (grep of the dump), so it is ours.
//
// AUTO (gf_spawn_guard 2) decides PER SPAWN with the engine's own start picker, the builtin
// stock calls at :469: function_77b7335( team, "start_spawn" ). A defined result = the engine
// has a start spawn for this player -> use THAT (one call, so the point is not consumed
// twice), which on every good map is byte-for-byte stock behaviour. Undefined = the engine
// has nothing (the Crossroads case) -> place on our anchors. So AUTO never touches a map
// that works, and needs no per-map data and no legacy family names (the old detector
// compared mp_tdm_spawn_*_start to objective families - names CW does not ship, so it read
// "too few starts" everywhere and would have guarded every map). FORCE (1) = anchors always.
// predictedspawn (the killcam's pre-spawn prediction) is left to stock: on a bad map that
// prediction is the map centre, cosmetic.
function private mod_spawn_override( predictedspawn )
{
    if ( predictedspawn )
        return false;

    if ( !isplayer( self ) || !isdefined( self.team ) )
        return false;

    // AUTO (guard 2) tries the engine's OWN start picker FIRST on every map, for ANY family:
    // on a map whose stock spawns work (Diesel, Hijacked, every normal map) the engine returns a
    // real start spawn and spreads players exactly like stock - no override, no stacking. Only
    // when the engine has nothing (the combined-arms maps under gunfight: Crossroads / Collateral
    // / Armada, whose gunfight has no start spawns -> the path-4 map-centre pile) does it fall
    // through to the family / geometric anchors below.
    // ⚠ FIX F5 (2026-09-18, klaze: "3v3 on Diesel spawns on top of each other"): the family path
    // uses the map's AUTHORED starts as the anchor list, and Diesel ships only 2 TDM starts per
    // side (census tdm=84/4(2+2+0)) - so mod_spawn_next_anchor's round-robin wrapped 3 players
    // onto 2 anchors and doubled them up. Stock spawns were fine; the guard was overriding good
    // spawns with too few anchors. Deferring to the engine picker wherever it works is what "AUTO"
    // was always meant to be - it previously did this ONLY when no family was selected
    // (cfg_spawn_family()==0), but the DEFAULT family is AUTO=8, so AUTO overrode every map.
    // FORCE (guard 1) still uses the anchors always, for anyone who wants a specific S&D/TDM layout.
    if ( cfg_spawn_guard() == 2 )
    {
        // Sides: the engine path hands self.team straight to the picker and swaps nothing, so ask
        // for the OTHER team's start spawn while game.switchedsides (the same swap the anchors do).
        // MEASURED 2026-09-15 (Hijacked): without this the sides did not switch on a round flip.
        team = self.team;
        if ( isdefined( game.switchedsides ) && game.switchedsides )
            team = util::getotherteam( team );

        s = function_77b7335( team, "start_spawn" );

        if ( isdefined( s ) && isdefined( s.origin ) )
        {
            self spawn( s.origin, isdefined( s.angles ) ? s.angles : ( 0, 0, 0 ) );
            self.lastspawntime = gettime();
            self.gf_spawn_how = "engine";
            return true;
        }
    }

    pt = self mod_spawn_next_anchor();

    if ( !isdefined( pt ) || !isdefined( pt.origin ) )
        return false;                       // no anchors: stock does what it does

    self spawn( pt.origin, isdefined( pt.angles ) ? pt.angles : ( 0, 0, 0 ) );
    self.lastspawntime = gettime();
    self.gf_spawn_how = "anchor";
    return true;
}

// The round-robin the on_spawned teleport used, factored out so both paths share it. Returns
// the struct for this player's side, or undefined when the guard is not armed.
function private mod_spawn_next_anchor()
{
    if ( !isdefined( level.gfmenu_spawn ) )
        return undefined;

    rp = isdefined( game.roundsplayed ) ? game.roundsplayed : 0;
    if ( !isdefined( level.gfmenu_spawn.round ) || level.gfmenu_spawn.round != rp )
    {
        level.gfmenu_spawn.team1 = mod_shuffle( level.gfmenu_spawn.team1 );
        level.gfmenu_spawn.team2 = mod_shuffle( level.gfmenu_spawn.team2 );
        level.gfmenu_spawn.next1 = 0;
        level.gfmenu_spawn.next2 = 0;
        level.gfmenu_spawn.round = rp;
    }

    switched = isdefined( game.switchedsides ) && game.switchedsides;
    use_team2 = ( self.team == #"axis" ) ? !switched : switched;

    if ( use_team2 )
    {
        list = level.gfmenu_spawn.team2;
        idx = level.gfmenu_spawn.next2;
        level.gfmenu_spawn.next2 = idx + 1;
        self.gf_spawn_side = "team2";
    }
    else
    {
        list = level.gfmenu_spawn.team1;
        idx = level.gfmenu_spawn.next1;
        level.gfmenu_spawn.next1 = idx + 1;
        self.gf_spawn_side = "team1";
    }

    if ( !isdefined( list ) || list.size == 0 )
        return undefined;

    self.gf_spawn_slot = idx % list.size;
    self.gf_spawn_slots = list.size;
    return list[ self.gf_spawn_slot ];
}

function private mod_spawn_place()
{
    // Host player tools that need re-asserting each spawn (both reset on respawn).
    if ( isdefined( self.gf_god ) && self.gf_god )
        self enableinvulnerability();
    if ( isdefined( self.gf_tp ) && self.gf_tp )
        self setclientthirdperson( 1 );

    // Teleport gun / grenade and the projectile fire mode are per-life threads (endon death):
    // re-arm for whoever wants them.
    self tp_spawn_rearm();
    self proj_spawn_rearm();

    // Loadout-pool camo: the stock give is done by now (give_loadout ran at
    // globallogic_spawn.gsc:637, this callback fires at :758), so repaint on top of it.
    self mod_camo_on_spawn();

    // Spawn log (gf_spawn_diag): where the ENGINE put this player, before the guard below
    // moves anyone - the per-map evidence for docs/notes/spawn-system.md.
    if ( cfg_spawn_diag() )
        self spawn_log_record();

    if ( !cfg_spawn_guard() )
        return;

    // The pre-spawn override (mod_spawn_override) handled this spawn: receipt only. To the
    // HOST, named per player - `self` here is whoever just spawned, and printing on `self`
    // put "spawn guard: ..." on every joiner's own feed each time they spawned.
    if ( isdefined( self.gf_spawn_how ) )
    {
        if ( cfg_spawn_diag() && self.gf_spawn_how == "anchor" )
            mod_host_say( "spawn guard: " + self.name + " -> " + self.gf_spawn_side + " anchor " + self.gf_spawn_slot + "/" + self.gf_spawn_slots );
        self.gf_spawn_how = undefined;
        return;
    }

    // Legacy path - the override was not installed for this spawn (it is installed at
    // mod_apply and by the menu action; a spawn before either lands here): the teleport,
    // a frame after the engine placed the player. Same anchors, same round-robin.
    if ( !isplayer( self ) || !isdefined( self.team ) )
        return;

    pt = self mod_spawn_next_anchor();

    if ( !isdefined( pt ) || !isdefined( pt.origin ) )
        return;

    self setorigin( pt.origin );

    if ( isdefined( pt.angles ) )
        self setplayerangles( pt.angles );

    if ( cfg_spawn_diag() )
        mod_host_say( "spawn guard (teleport): " + self.name + " -> " + self.gf_spawn_side + " anchor " + self.gf_spawn_slot + "/" + self.gf_spawn_slots );
}

// ═════════════════════════════════════════════════════════════════════════════
// LOADOUT-POOL CAMO — docs/notes/loadout-camo.md
// ═════════════════════════════════════════════════════════════════════════════
// Gunfight builds every pool weapon with getweapon( name, attachments ) and hands it over
// with NO weapon options - giveweapon( weapon, undefined, blueprint ) (gunfight.gsc:538,
// :618) - so a pool gun spawns bare, and the only camo the pool ever shows is a blueprint's
// own. The camo lives in the weapon OPTIONS on the player's held weapon, and the engine
// ships a builtin that rewrites exactly that on a held weapon: setcamo( weapon, index ).
// It is what Pack-a-Punch uses (item_inventory.gsc:6627), what reactive camos step through
// (activecamo_shared.gsc:954), and what the Atian Menu's Camo page calls. Server-side, so
// joiners see it with nothing installed (world model and killcam read the same options).
//
// The index space is gamedata/weapons/common/camooptions.csv, `camo` rows 1-121: tiers 1-7
// x {mp, zm} x 5 (the 35 + 35 progression camos), 61-66 mastery, 67-69 Pack-a-Punch, 80-115
// CDL team camos, 116-121 the Mauer / Forsaken Pack-a-Punch tiers. 0 = none.
//
// Applied per SPAWN, to every weapon in getweaponslistprimaries() - primary AND secondary,
// whatever the loadout set. Painted on the spawn frame, then again on every weapon_change
// for the life of that spawn: the spawn-frame call is the one we want, the switch re-paint
// is the Atian force_camo timing (paint on weapon_change only), kept as belt and braces
// for a give the engine has not finished raising. Nothing here imports gunfight.gsc.
//
// The random modes roll PER WEAPON, keyed by weapon name, so the primary and the secondary
// each get their own camo (gf_camo_split 0 collapses that to one key = one roll for both).
// Per round (-2) the rolls live in level.gfmenu_camo: everyone holds the same two weapons
// this round, so keying by name hands everyone the same pair, and level is rebuilt at
// every round boundary (mp_probe) so the pair re-rolls itself. Per player (-3) they live
// on the player and are cleared by every start, so each spawn is a fresh pair.

// The index for ONE weapon this spawn. -1 = leave it alone.
function private mod_camo_id( w )
{
    mode = cfg_camo();

    if ( mode >= -1 )
        return mode;                      // stock, or a fixed index for everything

    key = cfg_camo_split() ? w.name : #"gfmenu_camo_all";

    if ( mode == -2 )
    {
        if ( !isdefined( level.gfmenu_camo ) )
            level.gfmenu_camo = [];
        if ( !isdefined( level.gfmenu_camo[ key ] ) )
            level.gfmenu_camo[ key ] = mod_camo_random();

        return level.gfmenu_camo[ key ];
    }

    if ( !isdefined( self.gfmenu_camo ) )
        self.gfmenu_camo = [];
    if ( !isdefined( self.gfmenu_camo[ key ] ) )
        self.gfmenu_camo[ key ] = mod_camo_random();

    return self.gfmenu_camo[ key ];
}

function private mod_camo_random()
{
    if ( cfg_camo_pool() == 1 )
        return 1 + randomint( 121 );          // every mapped index, 1-121

    // Mastery + Pack-a-Punch: 61-69 (9) and 116-121 (6).
    r = randomint( 15 );
    return ( r < 9 ) ? ( 61 + r ) : ( 116 + r - 9 );
}

function private mod_camo_on_spawn()
{
    if ( !mod_is_gunfight() || cfg_camo() == -1 )
        return;

    self mod_camo_start( undefined );
}

// One hold thread per player: a new start supersedes the old, so a mid-round pick never
// leaves two threads repainting against each other on every switch. forced, when given,
// is painted onto everything instead of the per-weapon pick (the mid-round Stock strip).
function private mod_camo_start( forced )
{
    self notify( #"gfmenu_camo_restart" );
    self.gfmenu_camo = undefined;         // fresh per-player rolls for this spawn / pick
    self thread mod_camo_hold( forced );
}

function private mod_camo_hold( forced )
{
    self endon( #"death" );
    self endon( #"disconnect" );
    self endon( #"spawned_player" );
    self endon( #"gfmenu_camo_restart" );

    self mod_camo_paint( forced );

    for ( ;; )
    {
        self waittill( #"weapon_change" );
        self mod_camo_paint( forced );
    }
}

function private mod_camo_paint( forced )
{
    weapons = self getweaponslistprimaries();

    if ( !isdefined( weapons ) )
        return;

    foreach ( w in weapons )
    {
        if ( !isdefined( w ) || w == level.weaponnone )
            continue;

        id = isdefined( forced ) ? forced : self mod_camo_id( w );

        if ( id >= 0 )
            self setcamo( w, id );
    }
}

// Names for the toast, the flags line and the app. Everything else is "id N".
function private camo_label( id )
{
    if ( id == -1 ) return "stock";
    if ( id == -2 ) return "random/round";
    if ( id == -3 ) return "random/player";
    if ( id == 61 ) return "Gold";
    if ( id == 62 ) return "Diamond";
    if ( id == 63 ) return "DM Ultra";
    if ( id == 64 ) return "Golden Viper";
    if ( id == 65 ) return "Plague Diamond";
    if ( id == 66 ) return "Dark Aether";
    if ( id >= 67 && id <= 69 ) return "PaP " + ( id - 66 );
    if ( id >= 116 && id <= 118 ) return "PaP Mauer " + ( id - 115 );
    if ( id >= 119 && id <= 121 ) return "PaP Forsaken " + ( id - 118 );
    return "id " + id;
}

// Fisher-Yates on a copy.
function private mod_shuffle( arr )
{
    out = [];
    foreach ( p in arr )
        out[ out.size ] = p;

    for ( i = out.size - 1; i > 0; i-- )
    {
        j = randomint( i + 1 );
        t = out[ i ];
        out[ i ] = out[ j ];
        out[ j ] = t;
    }

    return out;
}

// 0 = X, 1 = Y: whichever the cluster spans more of.
function private mod_spread_axis( pts )
{
    minx = pts[ 0 ].origin[ 0 ]; maxx = minx;
    miny = pts[ 0 ].origin[ 1 ]; maxy = miny;

    foreach ( p in pts )
    {
        if ( p.origin[ 0 ] < minx ) minx = p.origin[ 0 ];
        if ( p.origin[ 0 ] > maxx ) maxx = p.origin[ 0 ];
        if ( p.origin[ 1 ] < miny ) miny = p.origin[ 1 ];
        if ( p.origin[ 1 ] > maxy ) maxy = p.origin[ 1 ];
    }

    return ( ( maxy - miny ) > ( maxx - minx ) ) ? 1 : 0;
}

// []-construction, NOT bare array(): keys_init above documents why array() is a link-time
// risk in this file (zero precedent in stock MP scripts). Same rule applies here.
function private mod_gather_spawns()
{
    pts = [];

    foreach ( n in mod_spawn_families() )
    {
        arr = struct::get_array( n, "targetname" );

        if ( isdefined( arr ) )
        {
            foreach ( s in arr )
            {
                if ( isdefined( s ) && isdefined( s.origin ) )
                    pts[ pts.size ] = s;
            }
        }
    }

    return pts;
}

// ⚠ These are string literals handed to the engine. Every build before 2026-09-12 shipped
// them with the ACTS string header the engine reads as "encrypted" (tools/strip-strhdr.ps1),
// so get_array matched NOTHING and the guard no-op'd with probe 61 every time - which is
// what sent the desktop hunting for a "missing family". The families were never the miss.
function private mod_spawn_families()
{
    names = [];

    // GENERIC map spawns - the most common targetname family in the source, and what the
    // maps that "don't use tdm spawns" actually place: mp_cartel / mp_slums_rm /
    // mp_village_rm / mp_miami_strike all move_spawn_point() these. This is the set the
    // first pass was missing, so it gathered <2 and no-oped. The game's own
    // function_d400d613 reads them with the same struct::get_array( name, "targetname" ).
    names[ names.size ] = "mp_spawn_point";
    names[ names.size ] = "mp_spawn_point_allies";
    names[ names.size ] = "mp_spawn_point_axis";

    // DM / FFA and TDM.
    names[ names.size ] = "mp_dm_spawn";
    names[ names.size ] = "mp_dm_spawn_start";
    names[ names.size ] = "mp_tdm_spawn";
    names[ names.size ] = "mp_tdm_spawn_allies_start";
    names[ names.size ] = "mp_tdm_spawn_axis_start";
    names[ names.size ] = "mp_tdm_spawn_team1_start";
    names[ names.size ] = "mp_tdm_spawn_team2_start";

    // OBJECTIVE families (Domination / S&D / CTF). These are the "proper dom/sd-located
    // spawns" - laid out for the 6v6 objective footprint, so on the combined-arms maps they
    // sit CENTRAL and in-bounds where the 12v12 TDM starts do not. mod_nearest_k then pulls
    // the central cluster out of the combined pool, which biases the anchors onto exactly
    // these. Real CW targetnames (confirmed in the dump's spawn tables).
    names[ names.size ] = "mp_dom_spawn";
    names[ names.size ] = "mp_dom_spawn_allies_start";
    names[ names.size ] = "mp_dom_spawn_axis_start";
    names[ names.size ] = "mp_sd_spawn_attacker";
    names[ names.size ] = "mp_sd_spawn_defender";
    names[ names.size ] = "mp_ctf_spawn_allies";
    names[ names.size ] = "mp_ctf_spawn_axis";
    names[ names.size ] = "mp_ctf_spawn_allies_start";
    names[ names.size ] = "mp_ctf_spawn_axis_start";

    // Combined Arms / Team War - the large-format layout that leaves you OOB in the first
    // place. Gather them too; mod_nearest_k still extracts the central cluster from them,
    // which is exactly what a small mode needs.
    names[ names.size ] = "mp_twar_spawn";
    names[ names.size ] = "mp_twar_spawn_allies_start";
    names[ names.size ] = "mp_twar_spawn_axis_start";

    return names;
}

// ── Spawn log + struct probe (gf_spawn_diag) — docs/notes/spawn-system.md ──────────────
// The per-map evidence the spawn picture needs, from the host's own matches:
//   spawn_log_record   at every spawn (before the guard moves anyone): round, player, team,
//                      origin, the NEAREST map spawn struct (family#index, distance) and a
//                      PILE flag when another living player is within 48u. Kept in game. so
//                      it survives the round boundary; the Spawn report prints it.
//   structs_line       (debug feed) the field schema of the map's mp_spawn_point structs - which of the
//                      candidate keys are defined and what they hold. CW folds every mode's
//                      spawn markers into one mp_spawn_point family with per-mode flags
//                      (dev_spawn.gsc lists the flag vocabulary: tdm sd dom ctf koth control
//                      dm ffa dem vip ...), but the dump ships no map entity data and the
//                      MP spawnlogic/spawning scripts are missing from it, so the only way
//                      to learn how "tdm start" is marked on a point is to read one.
//   getspawnlists()    the engine builtin (0 args, funcs_cw.csv): what spawn lists the
//                      engine built for this gametype - "normal", the start list, ...
function private spawn_fv( v )
{
    if ( !isdefined( v ) )
        return "-";
    if ( isstring( v ) )
        return v;
    if ( isvec( v ) )
        return int( v[ 0 ] ) + "," + int( v[ 1 ] ) + "," + int( v[ 2 ] );
    if ( ishash( v ) )
        return "hash";
    if ( isarray( v ) )
        return "arr" + v.size;
    return "" + v;
}

function private spawn_team_str( t )
{
    if ( !isdefined( t ) )
        return "?";
    if ( t == #"axis" )
        return "axis";
    if ( t == #"allies" )
        return "allies";
    return "other";
}

function private spawn_log_record()
{
    if ( !isplayer( self ) || !isdefined( self.origin ) )
        return;

    if ( !isdefined( game.gf_spawnlog ) )
        game.gf_spawnlog = [];

    rp = isdefined( game.roundsplayed ) ? game.roundsplayed : 0;

    bestd = -1;
    bestname = "none";
    bestidx = -1;

    foreach ( n in mod_spawn_families() )
    {
        arr = struct::get_array( n, "targetname" );

        if ( !isdefined( arr ) )
            continue;

        for ( i = 0; i < arr.size; i++ )
        {
            s = arr[ i ];

            if ( !isdefined( s ) || !isdefined( s.origin ) )
                continue;

            d = distancesquared( s.origin, self.origin );

            if ( bestd < 0 || d < bestd )
            {
                bestd = d;
                bestname = n;
                bestidx = i;
            }
        }
    }

    pile = "";
    foreach ( p in getplayers() )
    {
        if ( p != self && isalive( p ) && isdefined( p.origin ) && distance( p.origin, self.origin ) < 48 )
            pile = " ^1PILE:" + p.name;
    }

    how = isdefined( self.gf_spawn_how ) ? self.gf_spawn_how : "stock";
    line = "r" + rp + " " + self.name + " " + spawn_team_str( self.team ) + " " + spawn_fv( self.origin ) + " near " + bestname + "#" + bestidx + " d=" + ( bestd < 0 ? "-" : ( "" + int( sqrt( bestd ) ) ) ) + " " + how + pile;

    // Keep the last 24: rebuild without the oldest when full ([]-construction, see keys_init).
    if ( game.gf_spawnlog.size >= 24 )
    {
        trimmed = [];
        for ( i = 1; i < game.gf_spawnlog.size; i++ )
            trimmed[ trimmed.size ] = game.gf_spawnlog[ i ];
        game.gf_spawnlog = trimmed;
    }

    game.gf_spawnlog[ game.gf_spawnlog.size ] = line;

    // Compact per-round entry for the debug feed's SPAWN line (level. = this round only).
    if ( !isdefined( level.gf_spawn_round ) )
        level.gf_spawn_round = [];
    level.gf_spawn_round[ level.gf_spawn_round.size ] = self.name + ":" + spawn_team_str( self.team ) + ":" + how + ":d" + ( bestd < 0 ? "-" : ( "" + int( sqrt( bestd ) ) ) ) + ( pile != "" ? ":PILE" : "" );

    if ( !cfg_dbg_spawn() )
        mod_host_say( "spawn: " + line );
}

// One struct's candidate fields -> "k=v k=v". Only defined ones print.
function private spawn_struct_fields( s )
{
    out = "";
    if ( isdefined( s.script_string ) )        out += " str=" + spawn_fv( s.script_string );
    if ( isdefined( s.script_noteworthy ) )    out += " nw=" + spawn_fv( s.script_noteworthy );
    if ( isdefined( s.script_label ) )         out += " lbl=" + spawn_fv( s.script_label );
    if ( isdefined( s.script_int ) )           out += " int=" + spawn_fv( s.script_int );
    if ( isdefined( s.script_team ) )          out += " team=" + spawn_fv( s.script_team );
    if ( isdefined( s.spawnflags ) )           out += " sf=" + spawn_fv( s.spawnflags );
    if ( isdefined( s.script_gametype_tdm ) )  out += " gt_tdm=" + spawn_fv( s.script_gametype_tdm );
    if ( isdefined( s.script_gametype_sd ) )   out += " gt_sd=" + spawn_fv( s.script_gametype_sd );
    if ( isdefined( s.script_gametype_dom ) )  out += " gt_dom=" + spawn_fv( s.script_gametype_dom );
    if ( isdefined( s.script_gametype_dm ) )   out += " gt_dm=" + spawn_fv( s.script_gametype_dm );
    if ( isdefined( s.script_gametype_ctf ) )  out += " gt_ctf=" + spawn_fv( s.script_gametype_ctf );
    if ( isdefined( s.script_gametype_koth ) ) out += " gt_koth=" + spawn_fv( s.script_gametype_koth );
    if ( isdefined( s.tdm ) )                  out += " tdm=" + spawn_fv( s.tdm );
    if ( isdefined( s.sd ) )                   out += " sd=" + spawn_fv( s.sd );
    if ( isdefined( s.start ) )                out += " start=" + spawn_fv( s.start );
    if ( isdefined( s.script_start ) )         out += " sstart=" + spawn_fv( s.script_start );
    if ( isdefined( s.spawn_type ) )           out += " stype=" + spawn_fv( s.spawn_type );
    if ( isdefined( s.script_spawn_type ) )    out += " sstype=" + spawn_fv( s.script_spawn_type );
    if ( isdefined( s.type ) )                 out += " type=" + spawn_fv( s.type );
    if ( isdefined( s.radius ) )               out += " rad=" + spawn_fv( s.radius );
    if ( isdefined( s.script_flag ) )          out += " flag=" + spawn_fv( s.script_flag );
    if ( isdefined( s.script_parameters ) )    out += " prm=" + spawn_fv( s.script_parameters );
    if ( isdefined( s.classname ) )            out += " cls=" + spawn_fv( s.classname );
    if ( isdefined( s.targetname ) )           out += " tn=" + spawn_fv( s.targetname );
    if ( isdefined( s.target ) )               out += " tgt=" + spawn_fv( s.target );
    if ( isdefined( s.angles ) )               out += " ang=" + spawn_fv( s.angles );
    if ( out == "" )
        out = " (none of the candidate fields)";
    return out;
}

// Spawns -> "Spawn report": what this map actually places, and what the guard built from
// it. Three lines a page so it can be read. Zero counts are skipped.
function private spawn_report()
{
    self endon( #"disconnect" );

    n = 0;
    foreach ( name in mod_spawn_families() )
    {
        arr = struct::get_array( name, "targetname" );

        if ( !isdefined( arr ) || arr.size == 0 )
            continue;

        self iprintln( name + " = " + arr.size );
        n++;

        if ( n % 3 == 0 )
            wait( 4 );
    }

    if ( n == 0 )
        self iprintln( "^1no spawn structs found by any known targetname" );

    // AUTO detector readout: what it measured on THIS map and what it would decide, so the
    // trip point (gf_spawn_autospread) can be calibrated by eye. Read-only - does not arm.
    starts = mod_gather_named( mod_start_families() );
    obj = mod_gather_named( mod_obj_families() );
    if ( starts.size >= 2 && obj.size >= 4 )
    {
        c = mod_centroid( obj );
        objrad = int( mod_mean_dist2d( obj, c ) );
        startmin = int( mod_min_dist2d( starts, c ) );
        verdict = ( startmin > objrad + cfg_spawn_autospread() ) ? "^1legacy detector: wrong-layout" : "^2legacy detector: ok";
        self iprintln( "legacy: obj r=" + objrad + " nearest start=" + startmin + " trip=" + cfg_spawn_autospread() + "  " + verdict + " - AUTO now decides per spawn" );
    }
    else
    {
        self iprintln( "legacy detector: starts=" + starts.size + " obj=" + obj.size + " - AUTO now decides per spawn via the engine start picker" );
    }

    if ( isdefined( level.gfmenu_spawn ) )
    {
        c1 = mod_centroid( level.gfmenu_spawn.team1 );
        c2 = mod_centroid( level.gfmenu_spawn.team2 );
        sep = int( sqrt( mod_dist2d_sq( c1, c2 ) ) );
        self iprintln( "guard armed: " + level.gfmenu_spawn.team1.size + " + " + level.gfmenu_spawn.team2.size + " anchors, sides " + sep + " apart" );
    }
    else
    {
        reason = "switched off";
        if ( cfg_spawn_guard() )
            reason = "too few markers to build anchors";
        self iprintln( "guard not armed this round (" + reason + ")" );
    }
}

function private mod_centroid( pts )
{
    sum = ( 0, 0, 0 );

    foreach ( p in pts )
        sum += p.origin;

    return sum / pts.size;
}

// The four axes the side search tries, as unit vectors: x, y and the two diagonals.
function private mod_axis_dir( a )
{
    if ( a == 0 )
        return ( 1, 0, 0 );
    if ( a == 1 )
        return ( 0, 1, 0 );
    if ( a == 2 )
        return ( 0.7071, 0.7071, 0 );
    return ( 0.7071, -0.7071, 0 );
}

// k nearest of pts to target (2D), skipping any struct in excl, and - when hcenter/hdir are
// given - only markers whose projection on hdir from hcenter, times sign, is >= minproj
// (the half-plane past the ideal point's side). O(n*k), no sort - this runs 24 times per
// build, so the O(n^2) sort in mod_nearest_k would not do.
function private mod_nearest_k_excl( pts, target, k, excl, hcenter, hdir, sign, minproj )
{
    center = target;
    out = [];
    taken = [];

    for ( n = 0; n < k; n++ )
    {
        besti = -1;
        bestd = 0;

        for ( i = 0; i < pts.size; i++ )
        {
            if ( isdefined( taken[ i ] ) )
                continue;

            p = pts[ i ];
            if ( !isdefined( p ) || !isdefined( p.origin ) )
                continue;

            if ( isdefined( excl ) && mod_in_array( excl, p ) )
                continue;

            if ( isdefined( hcenter ) && isdefined( hdir ) && sign != 0 )
            {
                proj = ( ( p.origin[ 0 ] - hcenter[ 0 ] ) * hdir[ 0 ] + ( p.origin[ 1 ] - hcenter[ 1 ] ) * hdir[ 1 ] ) * sign;
                if ( proj < minproj )
                    continue;
            }

            d = mod_dist2d_sq( p.origin, center );
            if ( besti < 0 || d < bestd )
            {
                besti = i;
                bestd = d;
            }
        }

        if ( besti < 0 )
            break;

        taken[ besti ] = 1;
        out[ out.size ] = pts[ besti ];
    }

    return out;
}

function private mod_in_array( arr, p )
{
    foreach ( q in arr )
    {
        if ( q == p )
            return true;
    }

    return false;
}

// Fresh anchor structs: the marker's origin, angles turned (yaw only) toward the other
// side's centre. The map's own structs are never modified.
function private mod_anchor_copies( markers, face )
{
    out = [];

    foreach ( m in markers )
    {
        a = spawnstruct();
        a.origin = m.origin;
        d = ( face[ 0 ] - m.origin[ 0 ], face[ 1 ] - m.origin[ 1 ], 0 );
        if ( length( d ) > 1 )
            a.angles = vectortoangles( d );
        else
            a.angles = isdefined( m.angles ) ? m.angles : ( 0, 0, 0 );
        out[ out.size ] = a;
    }

    return out;
}

function private mod_nearest_k( pts, center, k )
{
    scored = [];

    foreach ( p in pts )
        scored[ scored.size ] = { #pt:p, #d:mod_dist2d_sq( p.origin, center ) };

    for ( i = 0; i < scored.size; i++ )
    {
        for ( j = i + 1; j < scored.size; j++ )
        {
            if ( scored[ j ].d < scored[ i ].d )
            {
                tmp = scored[ i ];
                scored[ i ] = scored[ j ];
                scored[ j ] = tmp;
            }
        }
    }

    out = [];
    n = ( scored.size < k ) ? scored.size : k;

    for ( i = 0; i < n; i++ )
        out[ out.size ] = scored[ i ].pt;

    return out;
}

// Vector components by CONSTANT index only - a variable index into a vector has no
// stock precedent, and this file does not gamble links.
function private mod_coord( p, ax )
{
    if ( ax == 1 )
        return p.origin[ 1 ];

    return p.origin[ 0 ];
}

function private mod_median_axis( pts, ax )
{
    xs = [];

    foreach ( p in pts )
        xs[ xs.size ] = mod_coord( p, ax );

    for ( i = 0; i < xs.size; i++ )
    {
        for ( j = i + 1; j < xs.size; j++ )
        {
            if ( xs[ j ] < xs[ i ] )
            {
                t = xs[ i ];
                xs[ i ] = xs[ j ];
                xs[ j ] = t;
            }
        }
    }

    return xs[ int( xs.size / 2 ) ];
}

function private mod_dist2d_sq( a, b )
{
    dx = a[ 0 ] - b[ 0 ];
    dy = a[ 1 ] - b[ 1 ];
    return dx * dx + dy * dy;
}

function private mod_gf_emit( id, value )
{
    mod_host_say( id * 100000 + value );
}

// Every diagnostic emitted OUTSIDE the host's menu thread (round start, another
// player's spawn) goes through here: to the host's screen and nobody else's. This
// used to be a foreach-player broadcast - the probe-era readout, from when the only
// screen that mattered was the test box's - which put 60xxxxx/61xxxxx across every
// joiner's view whenever the host switched the spawn guard on and at every round
// start after. A print on a player entity reaches that client only (the stock idiom:
// globallogic's `self iprintln( #"mp/host_endgame_response" )`), so the host is
// looked up explicitly instead of trusting whatever `self` happens to be. Lands in
// the toast region, like every other confirmation, so it never scribbles the panel.
function private mod_host_say( txt )
{
    foreach ( player in getplayers() )
    {
        if ( player ishost() )
        {
            player menu_toast( txt );
            return;
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// OVERTIME ZONE — the capture zone private Gunfight never gets. docs/notes/overtime-zone.md
// ═════════════════════════════════════════════════════════════════════════════
// Stock setupzones() (gunfight.gsc:827-908) wants two map entities and nothing else:
//   gunfight_zone_center   an entity INSIDE a trigger (zone istouching( trig ), :845)
//                          whose .target names its visuals (read unguarded, :875)
//   gunfight_zone_trigger  the capture volume, handed to gameobjects::create_use_object
// No private match has them (findings note, n=2 on stock Gunfight maps). Everything
// downstream - overtime(), the clock, VO, the capture - hangs off level.zones[0], so
// giving setupzones() those two entities gives the whole feature back, stock code.
//
// The BO1 approach: reuse Domination's neutral B flag. In this game that is the
// flag_primary entity with script_label "_b" (the dom builder, script_1304295570304027
// :414-470) - a script_model at the flag, whose .target names the map's own capture
// trigger. Take its origin, rename its trigger, and the designed centre volume becomes
// the Gunfight zone. Onslaught does the same family walk for its own zones
// (script_336275a0ba841d18:140-233): gunfight -> koth -> flag_primary.
//
// ⚠ The ONE fatal outcome: a centre no trigger contains is a map error and
//   print_map_errors() -> abort_level() (globallogic_utils.gsc:634) - a dead match.
//   So the builder makes the same istouching call stock will make, and backs out
//   completely if it fails: zero centres is stock's safe early return.

// The current map, for cache validity across a session switch (game. outlives one map).
function private mod_mapkey()
{
    return getdvarstring( #"sv_mapname", getdvarstring( #"mapname", "?" ) );
}

// POSTINIT (see the registration note): two snapshots that are only readable before
// gametype_start, each stored where its consumer looks.
function private mod_postinit()
{
    // Pre-match or pre-round? This is the exact test stock is about to make at
    // globallogic.gsc:5036 (`!isdefined( game.gamestarted )`) to choose which setting fills
    // level.prematchperiod - and :5070 then latches game.gamestarted = 1, so by mod_apply the
    // test is gone. game. is fresh on a match's first load and kept by the map_restart( 1 )
    // that starts every round after (:2058), so this is 1 exactly when stock read
    // prematchperiod. A level var is fine: level and this are both rebuilt per load.
    level.gf_first_load = isdefined( game.gamestarted ) ? 0 : 1;

    mod_dom_capture();
}

// Runs before gameobjects::main() deletes the dom flags (see the registration
// note). Snapshots every flag_primary (origin, script_label, and its capture trigger's
// origin while both are still alive) into game.gf_dom, keyed by map so a switch invalidates
// it. game. survives the per-round level rebuild, which is what we need: by the time any
// round's mod_apply runs, the live flags are already gone.
function private mod_dom_capture()
{
    mapk = mod_mapkey();

    if ( !isdefined( game.gf_dom_map ) || game.gf_dom_map != mapk )
    {
        game.gf_dom = undefined;   // a different map: drop the previous map's cache
        game.gf_dom_map = mapk;
    }

    flags = getentarray( "flag_primary", "targetname" );

    if ( flags.size == 0 )
        return;   // no dom on this map, or we ran too late - keep any good cache

    dom = [];
    foreach ( f in flags )
    {
        e = { #origin: f.origin, #label: ( isdefined( f.script_label ) ? f.script_label : "?" ) };

        if ( isdefined( f.target ) )
        {
            e.target = f.target;
            trigs = getentarray( f.target, "targetname" );

            if ( trigs.size > 0 )
                e.trigorigin = trigs[ 0 ].origin;
        }

        dom[ dom.size ] = e;
    }

    game.gf_dom = dom;
}

// The cached neutral B flag for THIS map, or undefined. B is script_label "_b"; failing
// that the middle flag (the centre of an A-B-C line by convention).
function private mod_dom_b()
{
    if ( !isdefined( game.gf_dom ) || !isdefined( game.gf_dom_map ) || game.gf_dom_map != mod_mapkey() || game.gf_dom.size == 0 )
        return undefined;

    foreach ( e in game.gf_dom )
    {
        if ( e.label == "_b" )
            return e;
    }

    return game.gf_dom[ int( game.gf_dom.size / 2 ) ];
}

// Returns 1 when a zone will exist by the time setupzones() runs (shipped, or built here).
function private mod_zone_synthesize()
{
    if ( getentarray( "gunfight_zone_center", "targetname" ).size > 0 )
        return 1;   // the map shipped one (never seen in a private match - measure it)

    anchor = mod_zone_anchor();

    if ( !isdefined( anchor ) )
    {
        mod_host_say( "^1zone: no anchor on this map (no dom/koth/control entities) - HP tiebreak" );
        return 0;
    }

    trig = anchor.trig;
    spawned_trig = 0;

    if ( !isdefined( trig ) )
    {
        // No map volume to reuse: a cylinder at the anchor, the ctf.gsc:637 shape.
        trig = spawn( "trigger_radius", anchor.origin, 0, cfg_zone_radius(), 128 );
        spawned_trig = 1;
    }

    // A script-set targetname is what getentarray finds - helicopter_shared.gsc:394/:870.
    trig.targetname = "gunfight_zone_trigger";

    // The centre: what Onslaught spawns for its own zones (util::spawn_model tag_origin).
    // Placed at the TRIGGER's own origin - the capture point create_use_object marks
    // (:2762), inside the volume by construction - not the anchor's, which for a dom
    // flag is the flag base on the ground. +16 so a floor-plane origin still counts.
    center = spawn( "script_model", trig.origin + ( 0, 0, 16 ) );
    center setmodel( "tag_origin" );
    center.targetname = "gunfight_zone_center";
    center.target = "gf_zone_visual";   // :875 reads it unguarded; empty array when unused

    if ( isdefined( anchor.visual ) )
        anchor.visual.targetname = "gf_zone_visual";   // the flag itself: hidden until overtime by :885

    // The check that decides fatal-or-fine, made with stock's own call (:845).
    if ( !( center istouching( trig ) ) )
    {
        center delete();

        if ( spawned_trig )
            trig delete();
        else
            trig.targetname = anchor.trig_name;

        if ( isdefined( anchor.visual ) )
            anchor.visual.targetname = anchor.visual_name;

        mod_host_say( "^1zone: centre not inside " + trig.classname + " - backed out, HP tiebreak" );
        return 0;
    }

    mod_host_say( "^2zone: " + anchor.src + ( spawned_trig ? " (spawned r" + cfg_zone_radius() + ")" : " (" + trig.classname + ")" ) + " @ " + trig.origin );
    return 1;
}

// The place the zone goes. A struct: origin, src (for the readout), and optionally
// trig (a map trigger to reuse, with trig_name to restore) and visual (a script_model
// to show during overtime, with visual_name to restore). undefined = nothing usable.
function private mod_zone_anchor()
{
    // 1. Domination's neutral B flag - the map's designed centre point, on every dom-capable
    //    map (measured absent live only because gameobjects::main() deletes it before we run;
    //    mod_dom_capture caught it at postinit and cached it in game.).
    b = mod_dom_b();

    if ( isdefined( b ) )
    {
        a = { #origin: b.origin, #src: "dom " + b.label };

        // The flag's own capture trigger, if it survived deletion (a trigger brush is not a
        // gameobject, so like the koth/control triggers it stays). Reuse the authored volume;
        // otherwise mod_zone_synthesize spawns a radius at the cached B origin.
        if ( isdefined( b.target ) )
        {
            trigs = getentarray( b.target, "targetname" );

            if ( trigs.size > 0 )
            {
                a.trig = trigs[ 0 ];
                a.trig_name = b.target;
            }
        }

        return a;
    }

    // 2. Hardpoint, then Control. ⚠ Measured on Zoo 2026-09-12: the *centre* point
    //    entities (koth_zone_center / control_zone_center) are GONE - gameobjects::main()
    //    (globallogic.gsc:5218 -> gameobjects_shared.gsc:590) deletes every gameobject
    //    whose script_gameobjectname is not this gametype's, and that runs before us.
    //    The TRIGGER brushes survive (Zoo: 4 koth, 2 control), and a zone trigger's
    //    .origin is the capture point (create_use_object marks it, :2762). So anchor on
    //    a trigger alone - no centre needed - and spawn our own centre at it.
    a = mod_zone_trigger_pick( "koth_zone_trigger", "hardpoint" );

    if ( !isdefined( a ) )
        a = mod_zone_trigger_pick( "control_zone_trigger", "control" );

    return a;
}

// The zone trigger nearest map centre, reused as the capture volume. No centre entity
// required - Gunfight only needs the trigger; the centre is ours to spawn. Nearest
// level.mapcenter (set by calculate_map_center() before our callback) because a map
// carries several (Hardpoint rotates 4) and Gunfight overtime wants the central one.
function private mod_zone_trigger_pick( trig_name, src )
{
    trigs = getentarray( trig_name, "targetname" );

    if ( trigs.size == 0 )
        return undefined;

    mc = isdefined( level.mapcenter ) ? level.mapcenter : trigs[ 0 ].origin;
    best = undefined;
    best_d = 0;

    foreach ( t in trigs )
    {
        d = mod_dist2d_sq( t.origin, mc );

        if ( !isdefined( best ) || d < best_d )
        {
            best = t;
            best_d = d;
        }
    }

    return { #origin: best.origin, #src: src + " " + trigs.size + "trig", #trig: best, #trig_name: trig_name };
}

// Read-only census of everything the builder could use, to the host's feed. Run this
// BEFORE switching the zone on: it names the anchor the next round would take.
function private zone_report()
{
    self endon( #"disconnect" );

    self iprintln( "gunfight: " + getentarray( "gunfight_zone_center", "targetname" ).size + " centre / " + getentarray( "gunfight_zone_trigger", "targetname" ).size + " trig" );

    // Live flag_primary is deleted by gametype_start; the cache (mod_dom_capture, postinit) is
    // the real readout. Show both so a 0/0 is distinguishable from a capture that never ran.
    self iprintln( "dom live " + getentarray( "flag_primary", "targetname" ).size + " flag_primary" );

    domc = ( isdefined( game.gf_dom ) && isdefined( game.gf_dom_map ) && game.gf_dom_map == mod_mapkey() ) ? game.gf_dom : [];
    cl = "dom cached: " + domc.size + " [" + ( isdefined( game.gf_dom_map ) ? game.gf_dom_map : "-" ) + "]";

    foreach ( e in domc )
        cl += " " + e.label;

    self iprintln( cl );

    b = mod_dom_b();
    if ( isdefined( b ) )
        self iprintln( "cached B @ " + b.origin + ( isdefined( b.target ) ? " -> " + b.target + ( getentarray( b.target, "targetname" ).size > 0 ? " (trig alive)" : " (trig gone)" ) : " (no target)" ) );

    wait( 4 );
    self iprintln( "koth: " + getentarray( "koth_zone_center", "targetname" ).size + " centre / " + getentarray( "koth_zone_trigger", "targetname" ).size + " trig" );
    self iprintln( "control: " + getentarray( "control_zone_center", "targetname" ).size + " centre / " + getentarray( "control_zone_trigger", "targetname" ).size + " trig" );
    self iprintln( "sd bombzone " + getentarray( "bombzone", "targetname" ).size + ", ctf zone " + getentarray( "ctf_flag_zone_trig", "targetname" ).size );

    wait( 4 );
    mc = isdefined( level.mapcenter ) ? level.mapcenter : ( 0, 0, 0 );
    self iprintln( "map centre " + mc );
    anchor = mod_zone_anchor();

    if ( isdefined( anchor ) )
        self iprintln( "next round would use: " + anchor.src + " @ " + ( isdefined( anchor.trig ) ? anchor.trig.origin + " (" + anchor.trig.classname + ")" : anchor.origin + " + spawned r" + cfg_zone_radius() ) );
    else
        self iprintln( "^1next round would use: nothing - no dom flag, no koth/control trigger" );

    self iprintln( "live: level.zones " + ( isdefined( level.zones ) ? level.zones.size : -1 ) + ", extratime " + ( isdefined( level.extratime ) ? level.extratime : -1 ) + "s, capture " + ( isdefined( level.capturetime ) ? level.capturetime : -1 ) + "s" );
}

// ═════════════════════════════════════════════════════════════════════════════
// MENU BOOTSTRAP — host only, on connect (the Atian Menu's proven entry point)
// ═════════════════════════════════════════════════════════════════════════════

function private on_player_connect()
{
    self endon( #"disconnect" );

    if ( !self ishost() )
    {
        return;
    }

    if ( isdefined( self.gfmenu ) )
    {
        return;
    }

    self menu_init( "Gunfight Host" );
    self keys_init();
    self build_tree();

    // Once per match, not per round (self.gfmenu persists across the round boundary
    // and the guard above returns first): whatever map the lobby launched IS the lobby's
    // pick, so a "next:" marker left over from the previous match is stale by definition.
    stage_mark( "", "" );

    self thread menu_think();
    self thread cmd_poll();
    self thread caster_probe();
    level thread roster_publish();     // the app's Players panel reads this (roster_publish)
}

// ── CoD Caster support ───────────────────────────────────────────────────────
// The menu bootstraps once on connect and its threads endon only #disconnect, so they
// keep running when the host later becomes a spectator / CoD Caster. Two things differ
// for a caster and BOTH are engine-decided (not answerable from the dump), so this probe
// measures them in one match:
//   1. RENDER - does either text channel show on a caster's (broadcast) HUD? The probe
//      prints the same line to iprintln AND iprintlnbold; whichever you can read is the
//      channel to set gf_menu_region to while casting.
//   2. INPUT - which buttons does a caster deliver to GSC? The free-cam repurposes the
//      weapon buttons, so the probe lists every button currently pressed; press each and
//      note which appear. keys_init's caster keyset should be set to those.
// Default ON (gf_caster_probe=1) so the first cast is self-diagnosing; turn it off from
// Display -> "Caster input probe" once the mapping is settled. Only runs while casting.
function private caster_probe()
{
    self endon( #"disconnect" );

    n = 0;

    for ( ;; )
    {
        if ( !cfg_geti( #"gf_caster_probe", 1 ) || !( self iscodcaster() ) )
        {
            wait( 1 );
            continue;
        }

        n++;
        b = "";
        if ( self usebuttonpressed() )              b += "use ";
        if ( self jumpbuttonpressed() )             b += "jump ";
        if ( self attackbuttonpressed() )           b += "atk ";
        if ( self adsbuttonpressed() )              b += "ads ";
        if ( self meleebuttonpressed() )            b += "mel ";
        if ( self reloadbuttonpressed() )           b += "rel ";
        if ( self sprintbuttonpressed() )           b += "spr ";
        if ( self stancebuttonpressed() )           b += "stn ";
        if ( self actionslotonebuttonpressed() )    b += "as1 ";
        if ( self actionslottwobuttonpressed() )    b += "as2 ";
        if ( self actionslotthreebuttonpressed() )  b += "as3 ";
        if ( self actionslotfourbuttonpressed() )   b += "as4 ";
        if ( b == "" )
            b = "-none-";

        line = "^3caster probe " + n + " ^7" + b;
        self iprintln( line );        // does the lower-left feed show for a caster?
        self iprintlnbold( line );    // does the centre show for a caster?

        wait( 0.5 );
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// COMMAND POLLER — lets the Windows control app (tools/gf-control) drive actions
// ═════════════════════════════════════════════════════════════════════════════
// The app writes CONFIG dvars (gf_team_size, gf_timer_seconds, ...) which mod_apply
// re-reads at each match start - those need nothing here. ACTIONS (map/gametype
// switch, bots, restart) are one-shots, so the app stages them as gf_cmd_* dvars and
// raises gf_cmd_go; this poller runs the operation host-side and clears the flag.
// Runs on the host player (started in on_player_connect), endon disconnect so it
// survives the round boundary (game_ended is match-end, not per round).
function private cmd_poll()
{
    self endon( #"disconnect" );

    for ( ;; )
    {
        if ( cfg_geti( #"gf_cmd_go", 0 ) == 1 )
        {
            cfg_seti( #"gf_cmd_go", 0 );   // clear FIRST so a slow action cannot re-fire
            self cmd_dispatch();
        }

        wait( 0.25 );
    }
}

// One command per gf_cmd_go pulse. Bots/restart take priority; otherwise a map and/or
// gametype present means a SESSION switch (the app's proper path - the map() carry
// cannot carry a gametype), or with gf_cmd_stage=1 a stage: the load half only, for
// the lobby to show when the match ends. Each trigger is cleared as it is consumed.
function private cmd_dispatch()
{
    cfg_load();
    // Broadcast + pause channels (Host page verbs, for the app / in-context bridge).
    say = getdvarstring( #"gf_cmd_say", "" );
    if ( say != "" )
    {
        cfg_seti( #"gf_cmd_say", "" );
        loc = cfg_geti( #"gf_cmd_say_loc", 0 );   // 0 centre (iprintlnbold), 1 feed (iprintln)
        dur = cfg_geti( #"gf_cmd_say_dur", 0 );   // 0 once; > 0 hold N s; < 0 fixed until Clear
        level thread broadcast_hold( say, loc, dur );   // no prefix - shows exactly what was typed
        return;
    }

    // Generic action channel: gf_cmd_action names a menu act_* verb to run on the host,
    // gf_cmd_arg is its parameter. Lets the app fire the menu-only player/weapon verbs.
    action = getdvarstring( #"gf_cmd_action", "" );
    if ( action != "" )
    {
        cfg_seti( #"gf_cmd_action", "" );
        arg = getdvarstring( #"gf_cmd_arg", "" );
        cfg_seti( #"gf_cmd_arg", "" );
        self cmd_action( action, arg );
        return;
    }

    map = tolower( getdvarstring( #"gf_cmd_map", "" ) );
    gt  = tolower( getdvarstring( #"gf_cmd_gametype", "" ) );

    if ( map == "" && gt == "" )
    {
        return;
    }

    // gf_cmd_stage=1 alongside the map/gametype = the menu's "Stage for lobby" verb:
    // load only, the lobby shows it when the match ends. 0 (default) = switch NOW.
    stage = cfg_geti( #"gf_cmd_stage", 0 );

    cfg_seti( #"gf_cmd_map", "" );
    cfg_seti( #"gf_cmd_gametype", "" );
    cfg_seti( #"gf_cmd_stage", 0 );

    if ( map == "" )
    {
        map = tolower( getdvarstring( #"sv_mapname", "" ) );
    }

    if ( gt == "" )
    {
        gt = tolower( getdvarstring( #"g_gametype", "" ) );
    }

    // Same guard the in-game gametype action uses: refuse a name the engine rejects
    // rather than hand switchmap_load a bad gametype and find out live.
    if ( !isvalidgametype( gt ) )
    {
        self menu_say( "^1app: engine rejects gametype " + gt );
        return;
    }

    if ( stage )
    {
        self menu_say( "^2app: staging " + map + " / " + gt + " - do not end the match until STAGE READY" );
        self thread do_session_stage( map, gt );
        return;
    }

    self menu_say( "^3app: switching to " + map + " / " + gt + "..." );
    self thread do_session_switch( map, gt );
}

// The gf_cmd_* channels above ARE reachable from the Windows app now: the in-context DLL
// bridge (tools/gf-bridge/gf_bridge.dll) runs `set gf_cmd_* ...` in-process via cwpatch's
// executor, and that DOES reach the GSC dvar store getdvarint reads - proven in-game
// 2026-09-13 (T1 = Outcome A; the earlier "external WPM can't reach the store" is about a
// remote WriteProcessMemory, a different path). tools/gf-control drives them.

// Re-apply the live-tunable config immediately, with NO restart (gf_cmd_apply, the app's
// "Apply now"). This is the idempotent subset of mod_apply: movement / bots / periods (each
// a plain dvar/setting re-assert) and, in a Gunfight match, the gametype-settings block. The
// STRUCTURAL parts of mod_apply (level.zones + overtime-zone synth, presentation fixups,
// spawn-anchor build) are match/round-start work and are deliberately NOT re-run here. The
// round timer needs nothing - level.gettimelimit stays installed and re-reads every 0.25s.
// A comma token list contains name? (the app's Apply-now scope: "move,bots,periods,timer").
function private scope_has( scope, name )
{
    toks = strtok( scope, "," );

    if ( !isdefined( toks ) )
        return false;

    foreach ( tk in toks )
    {
        if ( tk == name )
            return true;
    }

    return false;
}

// "Apply now" from the app. scope names which live subsystems actually changed, so an app
// apply re-asserts ONLY what the in-game menu would for that one setting - not the whole live
// blob. This is why a menu gravity pick never restarts but an app apply used to: cmd_apply_live
// ran mod_periods every time, and its prematch/preround setgametypesetting reloads the match.
// (gts_set already no-ops an unchanged write; scoping means the write is not even attempted for
// an untouched subsystem.) Empty / "all" = everything, for an older app that sends no scope.
function private cmd_apply_live( scope )
{
    if ( !isdefined( scope ) || scope == "" )
        scope = "all";

    all = ( scope == "all" );

    if ( all || scope_has( scope, "move" ) )
        mod_movement();

    if ( all || scope_has( scope, "bots" ) )
        mod_bots();

    if ( all || scope_has( scope, "periods" ) )
        mod_periods();

    // Refresh the round-timer cache so a timer change takes effect this round (the gettimelimit
    // hook reads the cache). "Next round" skips this. Cheap and reload-free, so always safe -
    // done whenever the timer is in scope or the scope is unknown.
    if ( all || scope_has( scope, "timer" ) )
        level.gf_timelimit_cache = cfg_timer_seconds() / 60;

    // Vehicle mode: everyone alive dismounts and remounts the (re-resolved) ride now. Only on
    // an explicit scope - never on "all", which an older app sends for any apply.
    if ( scope_has( scope, "veh" ) )
        veh_mode_refresh();

    // ⚠ Apply-now applies ONLY mid-match-safe subsystems: movement, bots, periods, timer.
    // It never setgametypesetting's maxplayers / customcac / profile / loadout / spyplane / round
    // limits - those reload the match, so mod_apply lands them on the NEXT round, or + Restart now.
}

// Run a menu act_* verb by name on the host, for the app's Actions (gf_cmd_action + gf_cmd_arg).
// Reuses the exact functions the in-game menu uses: each takes ( item, data... ) and acts on
// self, using item only for the on-screen marker - so a throwaway spawnstruct() as the item is
// safe, and self is the host (cmd_poll runs on the host). arg is a string; int() where an id is
// wanted; giveweapon takes the weapon name. Unknown names are reported, not fatal.
function private cmd_action( action, arg )
{
    it = spawnstruct();
    switch ( action )
    {
        case "fly":         self act_fly( it );                  break;
        case "godmode":     self act_godmode( it );              break;
        case "maxammo":     self act_maxammo( it );              break;
        case "thirdperson": self act_thirdperson( it );          break;
        case "dropweapon":  self act_dropweapon( it );           break;
        case "unlockall":   self act_unlockall( it );            break;
        case "freeze":      self act_freeze_all( it );           break;
        // The four hub verbs go through cmd_hub_verb pinned to the HOST, so an app command
        // never lands on a client the in-game menu happens to have targeted at that moment.
        case "giveweapon":  self cmd_hub_verb( self, &act_giveweapon, arg, arg ); break;
        case "camo":        self cmd_hub_verb( self, &act_camo, int( arg ) );     break;
        case "operator":    self cmd_hub_verb( self, &act_skin, int( arg ) );     break;
        case "outfit":      self cmd_hub_verb( self, &act_outfit, int( arg ) );   break;
        case "announce":    self act_announce( it );             break;
        case "countdown":   self act_countdown( it );            break;
        // Per-player verbs (2026-09-15, app parity): gf_cmd_target names the player as shown
        // in game (case-insensitive, prefix match accepted); arg = team for move.
        case "move":        self act_move( it, cmd_target(), ( tolower( arg ) == "axis" ) ? #"axis" : #"allies" ); break;
        case "spectate":    self act_spectate( it, cmd_target() ); break;
        case "freezeone":   self act_freeze_player( it, cmd_target() ); break;
        // Per-client verbs (2026-09-15, the Players page): same target rule; arg = weapon
        // name / camo-operator-outfit id / speed percent (0 = back to global) where taken.
        case "godone":      self act_c_god( it, cmd_target() );                     break;
        case "ammoone":     self act_c_ammo( it, cmd_target() );                    break;
        case "thirdone":    self act_c_thirdperson( it, cmd_target() );             break;
        case "flyone":      self act_c_fly( it, cmd_target() );                     break;
        case "killone":     self act_c_kill( it, cmd_target() );                    break;
        case "kickone":     self act_c_kick( it, cmd_target() );                    break;
        case "takeone":     self act_c_takeweapon( it, cmd_target() );              break;
        case "stripone":    self act_c_strip( it, cmd_target() );                   break;
        case "speedone":    self act_c_speed_set( it, cmd_target(), int( arg ) );   break;
        case "giveone":     self cmd_hub_verb( cmd_target(), &act_giveweapon, arg, arg ); break;
        case "camoone":     self cmd_hub_verb( cmd_target(), &act_camo, int( arg ) );     break;
        case "operatorone": self cmd_hub_verb( cmd_target(), &act_skin, int( arg ) );     break;
        case "outfitone":   self cmd_hub_verb( cmd_target(), &act_outfit, int( arg ) );   break;
        // Teleport (docs/notes/teleport.md): arg = where (me|aim|saved|centre) for tpall /
        // tpteam / tpenemy, (aim|saved|centre) for tpme, host|all for the gun / grenade
        // toggles, tome|metothem|swap with gf_cmd_target for tpplayer.
        case "tpall":       self act_tp_all( it, tolower( arg ), "all" );                 break;
        case "tpteam":      self act_tp_all( it, tolower( arg ), "team" );                break;
        case "tpenemy":     self act_tp_all( it, tolower( arg ), "enemy" );               break;
        case "tpme":        self act_tp_me( it, tolower( arg ) );                         break;
        case "tpsave":      self act_tp_save( it );                                       break;
        case "tpgun":       self act_tpgun( it, tolower( arg ) );                         break;
        case "tpnade":      self act_tpnade( it, tolower( arg ) );                        break;
        case "tpplayer":    self act_tp_player( it, cmd_target(), tolower( arg ) );       break;
        // Folded from dedicated gf_cmd_* trigger dvars into this verb channel (dvar-pool
        // budget, 2026-09-15): the app writes gf_cmd_action instead of a dvar per command.
        case "fillbots":    self thread fill_bots();                                      break;
        case "removebots":  bot::remove_bots( #"allies" ); bot::remove_bots( #"axis" ); self menu_say( "^2app: bots removed" ); break;
        case "addbot":      self thread add_one_bot( ( tolower( arg ) == "allies" ) ? #"allies" : ( ( tolower( arg ) == "axis" ) ? #"axis" : undefined ) ); break;
        case "removebot":   self thread remove_one_bot( undefined );                      break;
        case "evenbots":    self thread even_up_bots();                                   break;
        case "restart":     self menu_say( "^3app: restarting..." ); veh_sweep_for_transition( "restart" ); map_restart(); break;
        case "pause":       match_pause();                                                break;
        case "resume":      self thread match_resume();                                   break;
        case "apply":       self cmd_apply_live( arg ); self menu_say( "^2app: config applied live" ); break;
        case "sayclear":    level notify( #"gf_say_stop" ); broadcast_hint_stop(); self menu_say( "^2app: broadcast cleared" ); break;
        // Destructibles / exploders / projectiles / props (2026-09-17): arg = aim|near|all for
        // destruct; next|prev|again|stop|all|stopall for exploder; host|all|off for proj;
        // a weapon asset name for projweapon; ms for projrate; a model or label for prop.
        case "destruct":
            if ( tolower( arg ) == "aim" )       self act_destruct_aim( it );
            else if ( tolower( arg ) == "near" ) self act_destruct_all( it, 1, 600 );
            else                                 self act_destruct_all( it, 0, 0 );
            break;
        case "exploder":    self act_exp( it, tolower( arg ) );                                break;
        case "proj":        self act_proj( it, tolower( arg ) );                               break;
        case "projweapon":  self act_proj_weapon( it, tolower( arg ), tolower( arg ) );         break;
        case "projrate":    self act_proj_rate( it, int( arg ) );                              break;
        case "projhoming":  self act_proj_homing( it );                                        break;
        case "projtrail":   self act_proj_trail( it );                                         break;
        case "prop":        self cmd_prop( arg );                                              break;
        case "propundo":    self act_prop_delete( it, 0 );                                     break;
        case "propclear":   self act_prop_delete( it, 1 );                                     break;
        // Vehicles (the Vehicles page, app parity 2026-09-18): arg = the veh_master() INDEX - a
        // vehicle asset name does not fit the 47-byte bridge slot - spawned ahead of the host
        // exactly like the page row (isassetloaded-gated, so a non-resident pick just says so);
        // vehenter = the vehicle the host aims at; vehclear = sweep every EMPTY vehicle this menu
        // spawned (page rows + vehicle mode), stock's streak vehicles untouched.
        case "vehspawn":    self cmd_vehspawn( arg );                                          break;
        case "vehenter":    self veh_enter( it );                                              break;
        case "vehclear":    self act_vehclear( it );                                           break;
        default:            self menu_say( "^1app: unknown action '" + action + "'" ); break;
    }
}

// The player gf_cmd_target names: exact name first, then a case-insensitive prefix; the
// dvar is consumed. undefined (with a feed line) when nobody matches, and the act_* verbs
// already answer "player left" to undefined.
function private cmd_target()
{
    want = getdvarstring( #"gf_cmd_target", "" );
    cfg_seti( #"gf_cmd_target", "" );

    if ( want == "" )
    {
        self menu_say( "^1app: no target player named" );
        return undefined;
    }

    lw = tolower( want );
    hit = undefined;
    foreach ( player in getplayers() )
    {
        if ( !isdefined( player.name ) )
            continue;
        pn = tolower( player.name );
        if ( pn == lw )
            return player;
        if ( !isdefined( hit ) && pn.size >= lw.size && getsubstr( pn, 0, lw.size ) == lw )
            hit = player;
    }

    if ( !isdefined( hit ) )
        self menu_say( "^1app: no player named '" + want + "'" );

    return hit;
}

// Run a shared-hub verb (act_giveweapon / act_camo / act_skin / act_outfit) against one
// player for the app: pin the target for the call, then restore whatever the open menu
// had. player undefined (no such name) was already reported by cmd_target.
function private cmd_hub_verb( player, fn, a, b )
{
    if ( !isdefined( player ) || !isplayer( player ) )
        return;

    saved = self.gfmenu.target;
    self.gfmenu.target = player;

    if ( isdefined( b ) )
        self [[ fn ]]( spawnstruct(), a, b );
    else
        self [[ fn ]]( spawnstruct(), a );

    self.gfmenu.target = saved;
}

function private menu_restart()
{
    self notify( #"gfmenu_restart" );
    waitframe( 1 );
    self thread menu_think();
}

// ═════════════════════════════════════════════════════════════════════════════
// MENU ENGINE — translated from t8-atian-menu menu.gsc
// ═════════════════════════════════════════════════════════════════════════════

function private menu_init( title )
{
    self.gfmenu = {
        #current: "",
        #menus: [],
        #lastmsg: ""     // SPLIT layout folds confirmations here (no toast region)
    };

    self menu_add( "start_menu", title, "" );
}

// BOCW gives a host-only SERVER script exactly two text regions, and no more: the
// lower-left notification feed (iprintln) and the center of the screen (iprintlnbold).
// Both take ^N colors and both FADE, which is why menu_think repaints. The live PANEL
// goes to one region; transient confirmations ("toasts") go to the OTHER, so a
// confirmation never scribbles across the panel. gf_menu_region flips which is which -
// the two regions cap visible line counts differently and only an in-game look tells
// you which one shows the whole panel cleanly on a given build.
// The lower-left feed shows only com_gameMsgWindow1LineCount lines at once (~4-5
// stock), which clipped the panel to its last few rows. Raising it grows the feed on
// the HOST's own client only - it is a com_ display dvar the local HUD reads, not a
// replicated gametype setting, so joiners keep their stock feed. Re-applied on every
// repaint because it costs nothing and self-heals if anything resets it. 0 = leave
// the stock value untouched.
function private menu_feed_height()
{
    n = cfg_feed_lines();

    if ( n <= 0 )
        return;

    // iprintln might feed a different window index than the cfg's #1; set them all.
    setdvar( #"com_gameMsgWindow0LineCount", n );
    setdvar( #"com_gameMsgWindow1LineCount", n );
    setdvar( #"com_gameMsgWindow2LineCount", n );
    setdvar( #"com_gameMsgWindow3LineCount", n );
}

// Region 4 (HINT) never paints through here - the panel is one sethintstring call in
// menu_render_hint - so a stray menu_draw in that layout goes nowhere rather than into
// the feed it is supposed to leave alone.
function private menu_paint( txt )
{
    if ( cfg_menu_region() == 4 )
        return;

    if ( cfg_menu_region() == 1 )
        self iprintlnbold( txt );
    else
        self iprintln( txt );
}

function private menu_toast( txt )
{
    if ( cfg_menu_region() == 1 )
        self iprintln( txt );
    else
        self iprintlnbold( txt );
}

// The names the rest of the file already calls. menu_draw = the panel region,
// menu_say = the toast (opposite) region. In SPLIT (region 2) there is no opposite
// region free - the feed holds status and the centre holds the list - so a toast would
// either be buried by the next status repaint or scribble the list. Instead it folds
// into the status block's last line (menu_status_block reads self.gfmenu.lastmsg), which
// is repainted with the rest of the status and so persists until the next action.
function private menu_draw( txt ) { self menu_paint( txt ); }
function private menu_say( txt )
{
    // HINT: the panel has room for a last-action row that persists until the next action
    // (the widget does not fade), so a confirmation folds into it while the menu is open.
    // With the menu closed there is no panel, so it goes to the centre - the same one-line
    // toast region 0 uses - instead of vanishing.
    if ( cfg_menu_region() == 4 )
    {
        self.gfmenu.lastmsg = txt;

        if ( self.gfmenu.current == "" )
            self iprintlnbold( txt );

        return;
    }

    // Both SPLIT layouts (2 and 3) have no free toast region, so confirmations fold into
    // the status block's last line (region 2) or onto the one-line centre status (region 3).
    if ( cfg_menu_region() >= 2 )
    {
        self.gfmenu.lastmsg = txt;
        return;
    }

    self menu_toast( txt );
}

// A page. create_switch = 1 also adds an item in the parent that opens it.
// enter_func, if given, runs with (menu) every time the page is entered - the
// Players page uses it to rebuild itself from getplayers().
function private menu_add( id, name, parent_id, create_switch = 0, enter_func = undefined )
{
    menu = {
        #id: id,
        #cursor: 0,
        #name: name,
        #parent_id: parent_id,
        #enter_func: enter_func,
        #items: []
    };

    self.gfmenu.menus[ id ] = menu;

    if ( create_switch )
    {
        self menu_item( parent_id, name, &menu_switch, id );
    }

    return menu;
}

// An item. action is called as  self [[ action ]]( item, data1, data2 ).
// Return false from an action to close the menu; anything else keeps it open.
function private menu_item( menu_id, name, action, data1 = undefined, data2 = undefined, group = undefined, gval = undefined )
{
    if ( !isdefined( self.gfmenu.menus[ menu_id ] ) )
    {
        self menu_say( "^1menu bug: no page " + menu_id );
        return undefined;
    }

    item = {
        #name: name,
        #action: action,
        #activated: 0,
        #data1: data1,
        #data2: data2,
        #group: group,   // dvar this choice writes (for the live "current" marker)
        #gval: gval       // the value this choice represents
    };

    // Bind the &array param to a struct FIELD the way the Atian source does
    // (array::add( parent.sub_menus, item )), not to a nested index expression.
    parent = self.gfmenu.menus[ menu_id ];
    array::add( parent.items, item );
    return item;
}

function private menu_clear_items( menu_id )
{
    if ( isdefined( self.gfmenu.menus[ menu_id ] ) )
    {
        self.gfmenu.menus[ menu_id ].items = [];
        self.gfmenu.menus[ menu_id ].cursor = 0;
    }
}

function private menu_switch( item, menu_id )
{
    if ( !isdefined( menu_id ) )
    {
        menu_id = "";
    }

    self.gfmenu.current = menu_id;
    menu = self.gfmenu.menus[ menu_id ];

    if ( isdefined( menu ) )
    {
        menu.cursor = 0;

        if ( isdefined( menu.enter_func ) )
        {
            self [[ menu.enter_func ]]( menu );
        }
    }

    return true;
}

function private menu_current()
{
    return self.gfmenu.menus[ self.gfmenu.current ];
}

function private menu_run_item( item )
{
    if ( !isdefined( item.action ) )
    {
        return true;
    }

    if ( isdefined( item.data2 ) )
    {
        return self [[ item.action ]]( item, item.data1, item.data2 );
    }

    if ( isdefined( item.data1 ) )
    {
        return self [[ item.action ]]( item, item.data1 );
    }

    return self [[ item.action ]]( item );
}

// ── Target context (2026-09-15, klaze: "a client menu that can control connected clients").
// The Weapons / Camo / Operator / Outfit hubs are shared: opened from the root they act on
// the host as before; opened from a client's page (act_c_hub) they act on that client, and
// the hub's parent_id is pointed back at the client page so V returns there. The target is
// dropped the moment the current page leaves that family (menu_target_sync, first thing in
// menu_render), which also restores the hubs' parents - so the root Weapons page can never
// silently keep giving to the last client picked. ─────────────────────────────────────────
function private menu_target_in_scope( id )
{
    if ( id == "weapons" || id == "camo" || id == "camo_byid" || id == "operator" || id == "outfit" )
        return true;

    return id.size > 3 && getsubstr( id, 0, 3 ) == "wp_";
}

function private menu_target_sync()
{
    if ( !isdefined( self.gfmenu.target ) && !is_true( self.gfmenu.target_set ) )
        return;

    if ( menu_target_in_scope( self.gfmenu.current ) )
        return;

    self menu_target_clear();
}

function private menu_target_clear()
{
    self.gfmenu.target = undefined;
    self.gfmenu.target_set = 0;
    self.gfmenu.menus[ "weapons" ].parent_id = "start_menu";
    self.gfmenu.menus[ "camo" ].parent_id = "start_menu";
    self.gfmenu.menus[ "operator" ].parent_id = "start_menu";
    self.gfmenu.menus[ "outfit" ].parent_id = "start_menu";
}

// Who the shared hubs act on: the targeted client while one is set and still in the
// match (entity refs go undefined on disconnect), else the host.
function private menu_target()
{
    t = self.gfmenu.target;

    if ( isdefined( t ) && isplayer( t ) )
        return t;

    return self;
}

// " -> <name>" for a confirmation when a hub verb landed on a client rather than the host.
function private target_tail( p )
{
    if ( p == self || !isdefined( p.name ) )
        return "";

    return " -> " + p.name;
}

// Page name for the headers: "Weapons @name" while a client is targeted.
function private menu_page_title( menu )
{
    t = self.gfmenu.target;

    if ( isdefined( t ) && isplayer( t ) && isdefined( t.name ) && menu_target_in_scope( menu.id ) )
        return menu.name + " @" + t.name;

    return menu.name;
}

function private menu_think()
{
    self endon( #"disconnect" );
    self endon( #"gfmenu_restart" );
    level endon( #"game_ended" );

    lines = cfg_menu_lines();

    // Panel is 1 header + <lines> item rows. Prime the region with that many blanks
    // so the first real paint lands as a stable block. Kept small on purpose: the
    // lower-left feed only shows a handful of lines and the dvar that sizes it
    // (com_gameMsgWindow1LineCount) is latched at HUD build, not honored mid-match.
    // The HINT layout has nothing to prime - its panel is one widget, not a feed.
    if ( cfg_menu_region() != 4 )
    {
        for ( i = 0; i < lines + 1; i++ )
        {
            self menu_draw( "" );
        }
    }

    ts = 0;

    for ( ;; )
    {
        m = self.gfmenu;

        if ( m.current !== "" && !isdefined( m.menus[ m.current ] ) )
        {
            m.current = "";
        }

        render = 0;

        if ( m.current == "" )
        {
            if ( self key_pressed( #"open_menu", 1 ) )
            {
                m.current = "start_menu";
                // The key legend is a transient centre toast in the non-split layouts only;
                // in SPLIT it would land in the left details pane (menu_say folds to the
                // status there) and klaze wants that pane to stay pure state, no controls.
                if ( cfg_menu_region() < 2 )
                    self menu_say( "^7RMB^8 up  ^7LMB^8 down  ^7R^8 select  ^7V^8 back" );
                render = 1;
            }
            else
            {
                waitframe( 1 );
                continue;
            }
        }
        else if ( self key_pressed( #"parent_page", 1 ) )
        {
            menu = self menu_current();
            m.current = isdefined( menu ) ? menu.parent_id : "";
            render = 1;
        }
        else if ( self key_pressed( #"last_item", 1 ) )
        {
            menu = self menu_current();

            if ( isdefined( menu ) )
            {
                if ( menu.cursor == 0 || menu.cursor >= menu.items.size )
                {
                    menu.cursor = menu.items.size - 1;
                }
                else
                {
                    menu.cursor--;
                }

                render = 1;
            }
        }
        else if ( self key_pressed( #"next_item", 1 ) )
        {
            menu = self menu_current();

            if ( isdefined( menu ) )
            {
                if ( menu.cursor < menu.items.size - 1 )
                {
                    menu.cursor++;
                }
                else
                {
                    menu.cursor = 0;
                }

                render = 1;
            }
        }
        else if ( self key_pressed( #"select_item", 1 ) )
        {
            menu = self menu_current();

            if ( isdefined( menu ) )
            {
                item = menu.items[ menu.cursor ];

                if ( isdefined( item ) )
                {
                    res = self menu_run_item( item );

                    if ( isdefined( res ) && !res )
                    {
                        m.current = "";
                    }
                }
                else
                {
                    m.current = "";
                }

                render = 1;
            }
        }
        else
        {
            // Nothing pressed: redraw every 2s so iprintln does not fade the menu.
            nts = gettime();

            if ( nts > ts )
            {
                ts = nts + 2000;

                // The Players list follows joins / leaves / team moves while it is open
                // (klaze 2026-09-15), cursor kept on the same player.
                if ( m.current == "players" )
                    self players_refresh();

                render = 1;
            }
            else
            {
                waitframe( 1 );
                continue;
            }
        }

        if ( render )
        {
            self menu_render( lines );
        }

        waitframe( 1 );
    }
}

// The panel. Fixed height every frame (1 header + <lines> rows + 3 footer) so a
// repaint lands as one stable block instead of a jittering pile. The item list is a
// WINDOW that scrolls with the cursor - 28 maps read as one smooth list, not 14 pages
// of two. Header carries the breadcrumb + position; footer carries live match state
// and the key legend, so the host always sees what is actually set.
// The panel, compact so it survives the ~4-line feed. Exactly 1 header + <lines>
// item rows every frame (default lines=3, cursor centered as prev/here/next). The
// header does double duty: on the ROOT page it is the full state readout klaze
// wanted to keep; on a sub-page it is page name + position + a short state tail, so
// one line still says both "where am I" and "what is set". The divider/state/legend
// footer of the tall version is gone - it pushed the list off the top of the feed.
function private menu_render( lines )
{
    // Drop a client target the moment we are outside the Weapons/Camo/Operator/Outfit
    // family (menu_target_sync) - before any header below is painted.
    self menu_target_sync();

    // SPLIT: status and the navigable list in separate regions, both at once.
    //  region 2 = status in the lower-left feed, list in the centre (⚠ the centre caps at
    //             ONE visible line, so the list shows only the current item there);
    //  region 3 = list in the lower-left feed (the only MULTI-line region, ~4 rows) and a
    //             one-line status in the centre - use this when you want more menu rows.
    if ( cfg_menu_region() == 4 )
    {
        self menu_render_hint();
        return;
    }

    // Region 2 (the DEFAULT since 2026-09-14, klaze: "menu in the middle, info in the feed
    // and in the hint") uses the hint row for its info line, so it keeps the trigger; every
    // other layout drops it here so a stale panel never sits under the text one.
    if ( cfg_menu_region() == 2 )
    {
        self menu_render_split( lines, 1 );
        return;
    }

    self menu_hint_hide();
    if ( cfg_menu_region() == 3 )
    {
        self menu_render_split( lines, 0 );
        return;
    }

    menu = self menu_current();

    if ( !isdefined( menu ) )
    {
        for ( i = 0; i < lines + 1; i++ )
            self menu_draw( "" );
        return;
    }

    n = menu.items.size;

    start = 0;
    if ( n > lines )
    {
        start = menu.cursor - int( lines / 2 );
        if ( start < 0 )
            start = 0;
        if ( start > n - lines )
            start = n - lines;
    }
    end = int( min( start + lines, n ) );

    pos = ( n == 0 ) ? "-/-" : ( "" + ( menu.cursor + 1 ) + "/" + n );

    // Root header = the full state readout klaze wanted kept; sub-page header =
    // page name + position + short state tail. The position counter is the scroll
    // indicator (no caret/arrow glyphs - they do not render reliably in this font).
    if ( menu.id == "start_menu" )
        self menu_draw( self menu_state_line() );
    else
        self menu_draw( "^2" + self menu_page_title( menu ) + " " + pos + "  > " + self menu_state_compact() );

    if ( n == 0 )
    {
        self menu_draw( "     ^8(empty)" );
        for ( i = 1; i < lines; i++ )
            self menu_draw( "" );
    }
    else
    {
        for ( i = start; i < end; i++ )
            self menu_draw( self menu_item_line( menu, i ) );
        for ( i = end - start; i < lines; i++ )
            self menu_draw( "" );
    }
}

// SPLIT layout: klaze's "status on the left, menu in the centre" (2026-09-12). The
// status block goes to the lower-left feed (iprintln) and the navigable list to the
// centre (iprintlnbold), painted together every repaint so both are always on screen.
// ⚠ The centre's visible-line capacity is unverified on this build (the same caveat the
// region comment above carries) - if it clips the list, lower gf_menu_lines or revert to
// region 0 from the Display page. The lower-left feed still caps ~4 lines, so the status
// block is built to fit that (menu_status_block).
// list_center = 1: status in the feed (multi-line block), list in the centre (region 2).
// list_center = 0: list in the feed (multi-line), one-line status in the centre (region 3).
// The centre (iprintlnbold) only shows ONE line on this engine - no dvar grows it, unlike
// the lower-left feed (com_gameMsgWindow1LineCount, ~4). So region 3 is the one that gives a
// multi-row menu; region 2's centre list is effectively just the current item.
function private menu_render_split( lines, list_center )
{
    menu = self menu_current();

    if ( list_center )
    {
        // Region 2: full multi-line status block -> feed; the menu is ONE line in the
        // centre (all the centre can show), rendered as a HORIZONTAL carousel - the items
        // side by side with the current one bracketed, sliding as you scroll. This is the
        // usable form of "menu in the centre" given the centre's one-line limit.
        foreach ( l in self menu_status_block() )
            self iprintln( l );

        self iprintlnbold( isdefined( menu ) ? self menu_hline( menu ) : "" );

        // The hint row (use-prompt widget: one non-wrapping line that does not fade) carries
        // the info line - page, position, the compact state, the last action - while the
        // menu is open; the trigger goes with the menu.
        if ( isdefined( menu ) )
        {
            n = menu.items.size;
            info = "^2" + self menu_page_title( menu ) + " " + ( ( n == 0 ) ? "-/-" : ( "" + ( menu.cursor + 1 ) + "/" + n ) ) + " | " + self menu_state_compact();
            if ( isdefined( self.gfmenu.lastmsg ) && self.gfmenu.lastmsg != "" )
                info += " | " + self.gfmenu.lastmsg;
            trig = self menu_hint_trigger();
            trig sethintstring( info );
        }
        else
        {
            self menu_hint_hide();
        }
        return;
    }

    // Region 3: one-line status -> centre (fold confirmations onto it, no toast region);
    // the menu is the normal vertical windowed list in the multi-line feed.
    s = self menu_state_line();
    if ( isdefined( self.gfmenu.lastmsg ) && self.gfmenu.lastmsg != "" )
        s += "  ^8| ^7" + self.gfmenu.lastmsg;
    self iprintlnbold( s );

    if ( !isdefined( menu ) )
    {
        for ( i = 0; i < lines + 1; i++ )
            self iprintln( "" );
        return;
    }

    n = menu.items.size;

    start = 0;
    if ( n > lines )
    {
        start = menu.cursor - int( lines / 2 );
        if ( start < 0 )
            start = 0;
        if ( start > n - lines )
            start = n - lines;
    }
    end = int( min( start + lines, n ) );

    pos = ( n == 0 ) ? "-/-" : ( "" + ( menu.cursor + 1 ) + "/" + n );

    self iprintln( "^5" + self menu_page_title( menu ) + " ^7" + pos );

    if ( n == 0 )
    {
        self iprintln( "     ^8(empty)" );
        for ( i = 1; i < lines; i++ )
            self iprintln( "" );
    }
    else
    {
        for ( i = start; i < end; i++ )
            self iprintln( self menu_item_line( menu, i ) );
        for ( i = end - start; i < lines; i++ )
            self iprintln( "" );
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// HINT LAYOUT (region 4) — the panel as a trigger hint string
// ═════════════════════════════════════════════════════════════════════════════
// Why a trigger: T9 retail has no hudelem builtins (funcs_cw.csv lists none, and the stock
// hud_util_shared.gsc builders are dev-only newdebughudelem), so a server script has
// exactly three ways to put FREE TEXT on a client: the feed, the centre line, and a hint
// string on a trigger the player is standing in, drawn by the stock use-prompt widget.
// (luinotifyevent is a fourth channel for stock WIDGETS - measured 2026-09-13, the TIMEOUT
// overlay via #"esports_game_paused" - but it takes hashes and numbers, not a menu row;
// docs/notes/lui-events.md.)
// The third is what the "full HUD" Cold War GSC menus actually use (SoCanKam's PS4/PC
// menu, Lucy-Base - docs/notes/ecosystem-survey.md), and it has none of the feed's
// problems: no fade, no ~4-line cap, no scrolling pile; one call replaces the panel.
// Every call below is a stock MP-retail shape: ctf.gsc:637-639 spawns a trigger_radius,
// sethintstring's it and setcursorhint( "HINT_NOICON" )s the icon away;
// laststand.gsc:1463-1469 is the same trigger made to FOLLOW a player
// (setmovingplatformenabled + enablelinkto + linkto - the revive prompt); vip.gsc:1433-1435
// restricts a trigger_radius to one player with setvisibletoplayer, which is what keeps a
// joiner who walks up to the host from reading his menu.
// ⚠ Built 2026-09-13, never run. Unmeasured: whether the widget shows while the host is
// dead / spectating / in the pre-round countdown; whether it honours a newline
// (gf_hint_newlines); how long a string it takes before truncating (gf_hint_lines);
// whether the linked trigger keeps the host inside it while he moves (if the panel drops
// out when he walks, replace the link with trig.origin = self.origin on each repaint -
// SoCanKam's form).

// The host's hint trigger, made on first use. Radius is generous so the host is inside
// it even if the link lags a frame; height covers a jump.
function private menu_hint_trigger()
{
    if ( isdefined( self.gfmenu_hint ) )
        return self.gfmenu_hint;

    trig = spawn( "trigger_radius", self.origin, 0, 96, 128 );
    // ⚠ NO setcursorhint: HINT_NOICON renders a compact single-line prompt that CLIPS the
    // string at the screen edge (measured 2026-09-14). SoCanKam's working CW menu sets no
    // cursor hint and the use-prompt widget WRAPS its 15-item pipe-joined string across
    // lines - that wrap is how a hint panel becomes multi-row. Leave the cursor hint unset.
    trig triggerignoreteam();
    trig setvisibletoplayer( self );
    trig setmovingplatformenabled( 1 );
    trig enablelinkto();
    trig.origin = self.origin;
    trig linkto( self );

    self.gfmenu_hint = trig;
    self thread menu_hint_cleanup( trig );
    self thread menu_hint_cleanup_match( trig );
    return trig;
}

// Close = delete the trigger: the widget clears with it, and the next open spawns a fresh
// one. Also ends both watchers so they do not pile up across opens.
function private menu_hint_hide()
{
    self notify( #"gfhint_hide" );

    if ( isdefined( self.gfmenu_hint ) )
    {
        self.gfmenu_hint delete();
    }

    self.gfmenu_hint = undefined;
}

// The trigger is its own entity: it would outlive the host and the match. Two watchers,
// both retired by menu_hint_hide, take it down with either.
function private menu_hint_cleanup( trig )
{
    self endon( #"gfhint_hide" );

    self waittill( #"disconnect" );

    if ( isdefined( trig ) )
        trig delete();
}

function private menu_hint_cleanup_match( trig )
{
    self endon( #"gfhint_hide" );
    self endon( #"disconnect" );

    level waittill( #"game_ended" );

    if ( isdefined( trig ) )
        trig delete();
}

// The panel as ONE string: header, the item window, then a footer with the position, the
// key legend and the last action. Rows are joined by a dim bar (gf_hint_newlines 0 - the
// form both open menus ship, so the proven one) or a real newline (1, to measure). The
// item window is the same cursor-centred scroll as the feed layout, gf_hint_lines tall.
function private menu_render_hint()
{
    menu = self menu_current();

    if ( !isdefined( menu ) )
    {
        self menu_hint_hide();
        return;
    }

    lines = cfg_hint_lines();
    if ( lines < 1 )
        lines = 1;

    n = menu.items.size;

    start = 0;
    if ( n > lines )
    {
        start = menu.cursor - int( lines / 2 );
        if ( start < 0 )
            start = 0;
        if ( start > n - lines )
            start = n - lines;
    }
    end = int( min( start + lines, n ) );

    pos = ( n == 0 ) ? "-/-" : ( "" + ( menu.cursor + 1 ) + "/" + n );

    rows = [];

    // Root header = the full state readout; sub-page header = page name + short state tail.
    if ( menu.id == "start_menu" )
        rows[ rows.size ] = self menu_state_line();
    else
        rows[ rows.size ] = "^2" + self menu_page_title( menu ) + "  > " + self menu_state_compact();

    if ( n == 0 )
    {
        rows[ rows.size ] = "^2(empty)";
    }
    else
    {
        for ( i = start; i < end; i++ )
            rows[ rows.size ] = self menu_item_line( menu, i );
    }

    foot = "^2" + pos + "  RMB up LMB down R select V back";
    if ( isdefined( self.gfmenu.lastmsg ) && self.gfmenu.lastmsg != "" )
        foot += "  | " + self.gfmenu.lastmsg;
    rows[ rows.size ] = foot;

    // ⚠ A real newline (\n) in sethintstring CLOSES THE MATCH — the stock use-prompt
    // widget cannot take an embedded newline (measured in-game 2026-09-14). Packed only.
    sep = " ^8| ";
    txt = "";
    for ( i = 0; i < rows.size; i++ )
        txt += ( ( i > 0 ) ? sep : "" ) + rows[ i ];

    trig = self menu_hint_trigger();
    trig sethintstring( txt );
}

// The menu as a single horizontal line for the one-line centre (region 2). A left-anchored
// window: page + position, then the items from one before the cursor onward, current one
// bracketed and bright, the rest dim. Extra items past the screen edge clip on the right;
// the current item sits near the left so it is always visible, and the strip slides left as
// you scroll down - horizontal scrolling in place of vertical.
function private menu_hline( menu )
{
    n = menu.items.size;
    head = "^2" + self menu_page_title( menu ) + " " + ( ( n == 0 ) ? "-/-" : ( "" + ( menu.cursor + 1 ) + "/" + n ) );

    if ( n == 0 )
        return head + " (empty)";

    // FIXED window of gf_menu_hspan entries (default 4), clamped like the vertical list so
    // the bar always shows the same number of items instead of growing/shrinking as you
    // scroll. < / > hints mean there are more entries off that end.
    win = cfg_menu_hspan();
    if ( win < 1 )
        win = 1;
    if ( win > n )
        win = n;

    start = menu.cursor - int( win / 2 );
    if ( start < 0 )
        start = 0;
    if ( start > n - win )
        start = n - win;

    strip = "";
    for ( i = start; i < start + win; i++ )
        strip += " " + self menu_hitem( menu, i );

    lead = ( start > 0 ) ? " ^2<" : "";
    tail = ( start + win < n ) ? " ^2>" : "";

    return head + lead + strip + tail;
}

// One item for the horizontal strip: current = ^2[name], others dim; a live-matching choice
// gets a trailing *. Same active test as menu_item_line, kept short (no submenu caret).
function private menu_hitem( menu, i )
{
    it = menu.items[ i ];

    active = 0;
    if ( isdefined( it.group ) && isdefined( it.gval ) )
        active = ( cfg_geti( it.group, -2147483647 ) == it.gval );
    else if ( menu.id == "gametype" && isdefined( it.data1 ) )
        active = ( tolower( getdvarstring( #"g_gametype", "" ) ) == it.data1 );

    submenu = isdefined( it.data1 ) && isstring( it.data1 ) && isdefined( self.gfmenu.menus[ it.data1 ] );
    body = it.name + ( active ? "*" : "" ) + ( submenu ? ">" : "" );

    // Same scheme as the vertical rows: red brackets = current, green = the rest. The
    // brackets are the "you are here" marker in the sideways strip.
    if ( menu.cursor == i )
        return "^1[" + body + "]";

    return "^2" + body;
}

// The full status block for the SPLIT layout - "status of everything and what we have
// enabled" (klaze), condensed to fit the ~4-line feed. L1 core, L2 map/seats/method/next,
// L3 the enabled non-defaults, L4 the last action (folded from menu_say).
function private menu_status_block()
{
    out = [];

    ts = cfg_team_size();
    seated = getplayers( #"allies" ).size + getplayers( #"axis" ).size;
    budget = getdvarint( #"com_maxclients", 0 );
    map = getdvarstring( #"sv_mapname", "?" );
    gt = getdvarstring( #"g_gametype", "?" );
    meth = cfg_map_method() ? "SESSION" : "carry";

    // L1 adds round + round-win score (Gunfight teamscores = rounds won), so the pane shows
    // where the match stands, not just the config. "R3 2-1" = round 3, allies 2 / axis 1.
    out[ out.size ] = "^2GF " + ts + "v" + ts + " | " + cfg_timer_label() + " | " + gt + " | R" + info_round() + " " + info_score( #"allies" ) + "-" + info_score( #"axis" );

    l2 = "^2" + map + " | " + seated + "/" + budget + " | " + meth;
    staged = tolower( getdvarstring( #"gf_staged_map", "" ) );
    if ( staged != "" && staged != tolower( map ) )
        l2 += " | next:" + staged;
    out[ out.size ] = l2;

    flags = self menu_enabled_flags();
    if ( flags != "" )
        out[ out.size ] = "^2on: " + flags;

    if ( isdefined( self.gfmenu.lastmsg ) && self.gfmenu.lastmsg != "" )
        out[ out.size ] = self.gfmenu.lastmsg;

    return out;
}

// ── Live match-state readers (for the status pane + the info dump) ────────────
// Round-win score = game.stat teamscores (what gunfight.gsc onendround writes). Guarded so
// a pre-match / non-round read shows 0 rather than erroring.
function private info_score( team )
{
    if ( isdefined( game.stat ) && isdefined( game.stat[ #"teamscores" ] ) && isdefined( game.stat[ #"teamscores" ][ team ] ) )
        return game.stat[ #"teamscores" ][ team ];

    return 0;
}

function private info_round()
{
    return isdefined( game.roundsplayed ) ? ( game.roundsplayed + 1 ) : 1;
}

function private info_bots( team )
{
    n = 0;
    foreach ( p in getplayers( team ) )
    {
        if ( isbot( p ) )
            n++;
    }
    return n;
}

function private info_loadout()
{
    lo = cfg_loadout();
    return lo == 0 ? "default" : ( lo == 1 ? "snipers" : ( lo == 2 ? "blueprints" : ( lo == 3 ? "melee" : ( "set" + lo ) ) ) );
}

// On-demand full readout to the feed (paged, like spawn_report/zone_report), for everything
// the ~4-line status pane cannot hold at once: gametype + map + staged, round/score, team
// breakdown (humans vs bots) vs budget, timer + limits, loadout/camo/spyplane, spawn guard,
// zone, movement. Read-only. Display -> "Show match info".
function private match_info()
{
    self endon( #"disconnect" );

    ts = cfg_team_size();

    self iprintln( "^3== match info ==" );
    self iprintln( "^7mode ^3" + getdvarstring( #"g_gametype", "?" ) + " ^7on ^3" + getdvarstring( #"sv_mapname", "?" ) + " ^7(" + ( cfg_map_method() ? "session" : "carry" ) + ")" );
    st = tolower( getdvarstring( #"gf_staged_map", "" ) );
    if ( st != "" )
        self iprintln( "^7staged next ^3" + st + " / " + getdvarstring( #"gf_staged_gt", "" ) );
    wait( 4 );

    self iprintln( "^7round ^3" + info_round() + "  ^7score ^3" + info_score( #"allies" ) + "-" + info_score( #"axis" ) );
    self iprintln( "^7teams ^3" + ts + "v" + ts + "  ^7A ^3" + getplayers( #"allies" ).size + "(" + info_bots( #"allies" ) + "b) ^7X ^3" + getplayers( #"axis" ).size + "(" + info_bots( #"axis" ) + "b) ^7budget ^3" + getdvarint( #"com_maxclients", 0 ) );
    wait( 4 );

    self iprintln( "^7timer ^3" + cfg_timer_label() + "  ^7win ^3" + ( cfg_roundwinlimit() >= 0 ? ( "" + cfg_roundwinlimit() ) : "stock" ) + "  ^7cap ^3" + ( cfg_roundlimit() >= 0 ? ( "" + cfg_roundlimit() ) : "stock" ) + "  ^7rot ^3" + ( cfg_rounds_loadout() >= 0 ? ( "" + cfg_rounds_loadout() ) : "stock" ) );
    self iprintln( "^7loadout ^3" + info_loadout() + "  ^7camo ^3" + ( cfg_camo() != -1 ? camo_label( cfg_camo() ) : "stock" ) + "  ^7spyplane ^3" + cfg_spyplane() );
    self iprintln( "^7pre-match ^3" + ( cfg_prematch() >= 0 ? ( cfg_prematch() + "s" ) : "lobby" ) + "  ^7pre-round ^3" + ( cfg_preround() >= 0 ? ( cfg_preround() + "s" ) : "lobby" ) );
    wait( 4 );

    gd = cfg_spawn_guard();
    self iprintln( "^7spawn ^3" + ( gd == 2 ? "AUTO" : ( gd == 1 ? "FORCE" : "off" ) ) + "  ^7zone ^3" + ( cfg_zone() ? ( "on ot" + cfg_zone_overtime() + " cap" + cfg_zone_capture() ) : "off" ) );
    self iprintln( "^7gravity ^3" + cfg_gravity() + "  ^7jump ^3" + ( cfg_jump() >= 0 ? ( "" + cfg_jump() ) : "stock" ) + "  ^7boost ^3" + cfg_jump_boost() + "  ^7speed ^3" + cfg_speed() + "%  ^7fall ^3" + ( cfg_falldamage() ? "stock" : "off" ) + "  ^7oob ^3" + ( cfg_oob() ? "off" : "stock" ) );
}

// Everything switched on beyond its default, one short line. Empty when nothing is on
// (stock Gunfight), so the status block stays short until the host changes something.
function private menu_enabled_flags()
{
    s = "";

    lo = cfg_loadout();
    if ( lo != 0 )
        s = menu_join( s, lo == 1 ? "snipers" : ( lo == 2 ? "blueprints" : ( lo == 3 ? "melee" : ( "loadout" + lo ) ) ) );

    cm = cfg_camo();
    if ( cm != -2 )
        s = menu_join( s, "camo:" + camo_label( cm ) );

    sp = cfg_spyplane();
    if ( sp != 0 )
        s = menu_join( s, sp == 3 ? "spyplane*" : "spyplane" );

    if ( cfg_zone() )
        s = menu_join( s, "zone" );

    sg = cfg_spawn_guard();
    if ( sg == 1 )
        s = menu_join( s, "spawn:FORCE" );
    else if ( sg == 2 )
        s = menu_join( s, "spawn:AUTO" );

    if ( cfg_roundwinlimit() >= 0 )
        s = menu_join( s, "first" + cfg_roundwinlimit() );
    if ( cfg_roundlimit() >= 0 )
        s = menu_join( s, "cap" + cfg_roundlimit() );
    if ( cfg_rounds_loadout() >= 0 )
        s = menu_join( s, "rot" + cfg_rounds_loadout() );
    // The countdowns have non-stock defaults (15 / 7), so only a change FROM those is news.
    if ( cfg_prematch() != 15 )
        s = menu_join( s, "prematch" + ( cfg_prematch() >= 0 ? ( "" + cfg_prematch() ) : ":lobby" ) );
    if ( cfg_preround() != 7 )
        s = menu_join( s, "preround" + ( cfg_preround() >= 0 ? ( "" + cfg_preround() ) : ":lobby" ) );
    if ( cfg_gravity() != 800 )
        s = menu_join( s, "grav" + cfg_gravity() );
    if ( cfg_jump() >= 0 )
        s = menu_join( s, "jump" + cfg_jump() );
    if ( cfg_jump_boost() > 0 )
        s = menu_join( s, "boost" + cfg_jump_boost() );
    if ( cfg_speed() != 100 )
        s = menu_join( s, "speed" + cfg_speed() );
    if ( !cfg_falldamage() )
        s = menu_join( s, "nofall" );
    if ( isdefined( level.gf_paused ) && level.gf_paused )
        s = menu_join( s, "^1PAUSED^7" );
    else if ( isdefined( level.gf_frozen_all ) && level.gf_frozen_all )
        s = menu_join( s, "^1FROZEN^7" );

    // Bots: one tag when both sides agree, A/B when they differ, nothing while the
    // lobby's own row is in charge on both sides.
    da = cfg_bot_diff_allies();
    dx = cfg_bot_diff_axis();
    if ( da == dx && da >= 0 )
        s = menu_join( s, "bots:" + bot_diff_label( da ) );
    else if ( da >= 0 || dx >= 0 )
        s = menu_join( s, "bots:" + bot_diff_label( da ) + "/" + bot_diff_label( dx ) );
    if ( cfg_bot_passive() )
        s = menu_join( s, "bots:passive" );

    return s;
}

function private menu_join( s, add )
{
    return ( s == "" ) ? add : ( s + " ^8| ^7" + add );
}

// One rendered row. Cursor row is bright with a > caret; other rows dim. A choice
// that matches its live dvar gets a ^2* and trailing <; a sub-page gets a ^5> ; an
// .activated toggle shows [ON].
function private menu_item_line( menu, i )
{
    it = menu.items[ i ];
    cur = ( menu.cursor == i );

    // menu_switch stores the target page id in data1, so data1 naming a real page
    // means this row opens a submenu.
    submenu = isdefined( it.data1 ) && isstring( it.data1 ) && isdefined( self.gfmenu.menus[ it.data1 ] );

    active = 0;
    if ( isdefined( it.group ) && isdefined( it.gval ) )
        active = ( cfg_geti( it.group, -2147483647 ) == it.gval );
    else if ( menu.id == "gametype" && isdefined( it.data1 ) )
        active = ( tolower( getdvarstring( #"g_gametype", "" ) ) == it.data1 );

    // Colour scheme (klaze, 2026-09-14: "every menu and entry green, the selected one red"):
    //   ^1 red    = the selected row - caret and label
    //   ^2 green  = every other row, page rows included, and the markers (* / > / [ON])
    // The markers stay suffixes in a fixed order so columns line up down the list; the
    // sub-page > and the current-value * still tell "opens" from "is set" by shape.
    namecol = cur ? "^1" : "^2";

    line = ( cur ? "^1> " : "^2  " ) + namecol + it.name;

    if ( active )
        line += " ^2*";
    if ( submenu )
        line += " ^2>";
    if ( it.activated )
        line += " ^2[ON]";

    return line;
}

// Short state tail for sub-page headers: team size, timer, gametype - the three
// most-changed settings, kept short so the header never wraps.
function private menu_state_compact()
{
    ts = cfg_team_size();
    return ts + "v" + ts + " " + cfg_timer_label() + " " + getdvarstring( #"g_gametype", "?" );
}

// Start > Map > 6v6 maps  - walk parent_id up to the root.
function private menu_breadcrumb( menu )
{
    trail = menu.name;
    p = menu.parent_id;

    for ( guard = 0; guard < 12 && p != ""; guard++ )
    {
        par = self.gfmenu.menus[ p ];
        if ( !isdefined( par ) )
            break;
        trail = par.name + " ^5> ^3" + trail;
        p = par.parent_id;
    }

    return trail;
}

// The always-on state readout: team size, timer, current map+gametype, seated
// players against the client budget, and the map method. Everything the host would
// otherwise have to trigger something to find out.
function private menu_state_line()
{
    ts = cfg_team_size();
    seated = getplayers( #"allies" ).size + getplayers( #"axis" ).size;
    budget = getdvarint( #"com_maxclients", 0 );
    map = getdvarstring( #"sv_mapname", "?" );
    gt = getdvarstring( #"g_gametype", "?" );
    meth = cfg_map_method() ? "SESSION" : "carry";

    line = "^2" + ts + "v" + ts + " | " + cfg_timer_label() + " | " + map + " | " + gt + " | " + seated + "/" + budget + " | " + meth;

    // A staged pick, until it is either started from the lobby or overtaken by a NOW
    // switch. Shown only while it differs from where we are, so a stage of the current
    // map (or a stale marker) never reads as pending.
    staged = tolower( getdvarstring( #"gf_staged_map", "" ) );
    if ( staged != "" && staged != tolower( map ) )
        line += " | next:" + staged;

    return line;
}

// ═════════════════════════════════════════════════════════════════════════════
// KEYS — translated from t8-atian-menu keymanager.gsc, same bindings
// ═════════════════════════════════════════════════════════════════════════════

// Combos are built with [] and index assignment rather than bare array( ... ).
// ⚠ Not because array() is missing: the engine table lists it (array, 0-100
// args). But stock MP scripts contain ZERO bare array() calls - every stock use
// is the array:: namespace - so under ACTS it is a builtin with no precedent in
// the code we link against, and a link-time failure on a key table would take
// the whole menu with it. [] construction is the form that cannot fail either
// way. (A commit message once said "array is a namespace under T9" as if that
// were the whole story; it is a namespace AND a builtin.)
function private keys_init()
{
    self.gfkeys = [];

    open = [];
    open[ 0 ] = #"ads";
    open[ 1 ] = #"melee";
    self.gfkeys[ #"open_menu" ] = open;

    self.gfkeys[ #"parent_page" ] = key_single( #"melee" );
    self.gfkeys[ #"last_item" ]   = key_single( #"ads" );
    self.gfkeys[ #"next_item" ]   = key_single( #"attack" );
    self.gfkeys[ #"select_item" ] = key_single( #"reload" );

    // Caster keyset — used automatically when the host is a CoD Caster (key_pressed picks
    // it on iscodcaster()). A caster's weapon buttons are eaten by the free-cam, so this
    // maps to spectate-plausible inputs. ⚠ BEST GUESS pending the in-game caster probe
    // (Display -> "Caster input probe"): the probe prints which buttons a caster actually
    // delivers to GSC; correct this mapping to those. Chosen non-overlapping so no combo
    // shadows another: open = use+jump, nav = the four action slots.
    self.gfkeys_caster = [];
    copen = [];
    copen[ 0 ] = #"use";
    copen[ 1 ] = #"jump";
    self.gfkeys_caster[ #"open_menu" ]   = copen;
    self.gfkeys_caster[ #"last_item" ]   = key_single( #"as1" );   // up
    self.gfkeys_caster[ #"next_item" ]   = key_single( #"as2" );   // down
    self.gfkeys_caster[ #"select_item" ] = key_single( #"as3" );   // select
    self.gfkeys_caster[ #"parent_page" ] = key_single( #"as4" );   // back
}

function private key_single( key )
{
    combo = [];
    combo[ 0 ] = key;
    return combo;
}

// All keys of the combo down; with wait_release, also wait until they are all up,
// so one press is one action.
function private key_pressed( id, wait_release = 0 )
{
    // A CoD Caster's weapon buttons are repurposed by the free-cam, so while casting the
    // menu reads the caster keyset instead (see keys_init). iscodcaster() is false for a
    // normal alive host, so ordinary play is unchanged.
    combo = self.gfkeys[ id ];

    if ( isdefined( self.gfkeys_caster ) && self iscodcaster() && isdefined( self.gfkeys_caster[ id ] ) )
    {
        combo = self.gfkeys_caster[ id ];
    }

    if ( !isdefined( combo ) )
    {
        return false;
    }

    for ( i = 0; i < combo.size; i++ )
    {
        if ( !self key_down( combo[ i ] ) )
        {
            return false;
        }
    }

    if ( !wait_release )
    {
        return true;
    }

    for ( ;; )
    {
        any_down = 0;

        for ( i = 0; i < combo.size; i++ )
        {
            if ( self key_down( combo[ i ] ) )
            {
                any_down = 1;
            }
        }

        if ( !any_down )
        {
            break;
        }

        waitframe( 1 );
    }

    return true;
}

function private key_down( key )
{
    switch ( key )
    {
        case #"ads":    return self adsbuttonpressed();
        case #"attack": return self attackbuttonpressed();
        case #"melee":  return self meleebuttonpressed();
        case #"reload": return self reloadbuttonpressed();
        case #"use":    return self usebuttonpressed();
        // Caster-plausible inputs (the free-cam repurposes the weapon buttons). Which of
        // these a CoD Caster actually delivers to GSC is what the caster probe measures.
        case #"jump":   return self jumpbuttonpressed();
        case #"sprint": return self sprintbuttonpressed();
        case #"stance": return self stancebuttonpressed();
        case #"as1":    return self actionslotonebuttonpressed();
        case #"as2":    return self actionslottwobuttonpressed();
        case #"as3":    return self actionslotthreebuttonpressed();
        case #"as4":    return self actionslotfourbuttonpressed();
        default:        return false;
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// THE TREE
// ═════════════════════════════════════════════════════════════════════════════

function private build_tree()
{
    // ── Teams ────────────────────────────────────────────────────────────────
    self menu_add( "teams", "Teams", "start_menu", 1 );
    self menu_item( "teams", "2v2", &act_team_size, 2, undefined, #"gf_team_size", 2 );
    self menu_item( "teams", "3v3", &act_team_size, 3, undefined, #"gf_team_size", 3 );
    self menu_item( "teams", "4v4", &act_team_size, 4, undefined, #"gf_team_size", 4 );
    self menu_item( "teams", "5v5", &act_team_size, 5, undefined, #"gf_team_size", 5 );
    // 6v6 = 12 clients = exactly the com_maxclients lobby_state read in a Gunfight session
    // after a SESSION map switch (2026-09-12). clamp_team_size() bounds it at budget/2, so
    // in an 8- or 10-slot lobby this item degrades to 4v4 / 5v5 and says so.
    self menu_item( "teams", "6v6", &act_team_size, 6, undefined, #"gf_team_size", 6 );
    // Spectator slots added to maxplayers on top of the team size (default 2 = the caster
    // allowance) so a spectator does not eat a player slot at bot fill / join time.
    self menu_item( "teams", "Spectator slots 0", &act_spec_slots, 0, undefined, #"gf_spec_slots", 0 );
    self menu_item( "teams", "Spectator slots 2", &act_spec_slots, 2, undefined, #"gf_spec_slots", 2 );
    self menu_item( "teams", "Spectator slots 4", &act_spec_slots, 4, undefined, #"gf_spec_slots", 4 );
    self menu_item( "teams", "Fill with bots", &act_fill_bots );
    self menu_item( "teams", "Remove all bots", &act_remove_bots );

    // ── Bots — add / remove / even-up, difficulty, passive. docs/notes/bots.md ─
    // Fill and Remove-all stay on Teams too (the documented 6v6 recipe goes through
    // Teams); everything else about bots lives here. Add/remove act on ONE bot: "auto"
    // = the smaller side, tie -> the side opposite the host, so a solo host builds
    // opponents first. Even up = the fewest bots that make the sides equal (an odd
    // human count is the case it exists for): it removes surplus bots from the bigger
    // side before it adds any.
    self menu_add( "bots", "Bots", "start_menu", 1 );
    self menu_item( "bots", "Add bot - auto, smaller side", &act_bot_add, 0 );
    self menu_item( "bots", "Add bot - allies", &act_bot_add, 1 );
    self menu_item( "bots", "Add bot - axis", &act_bot_add, 2 );
    self menu_item( "bots", "Remove one bot", &act_bot_remove );
    self menu_item( "bots", "Even up teams - odd humans", &act_bot_even );
    self menu_item( "bots", "Fill to team size", &act_fill_bots );
    self menu_item( "bots", "Remove all bots", &act_remove_bots );
    self menu_item( "bots", "Passive - bots ignore everyone", &act_bot_passive, undefined, undefined, #"gf_bot_passive", 1 );

    // Difficulty. The "both" rows write both per-team settings; the * marker follows the
    // allies dvar, so a split pick (Per team page) shows no * on this page - by design,
    // the status tail says A/B. "Lobby's value" hands both rows back to the custom-games
    // menu (dvar -1: mod_bots writes nothing, the setting keeps whatever the lobby set).
    self menu_add( "botdiff", "Bot difficulty", "bots", 1, &bot_diff_enter );
    self menu_item( "botdiff", "Recruit", &act_bot_diff, 0, undefined, #"gf_bot_diff_allies", 0 );
    self menu_item( "botdiff", "Regular", &act_bot_diff, 1, undefined, #"gf_bot_diff_allies", 1 );
    self menu_item( "botdiff", "Hardened", &act_bot_diff, 2, undefined, #"gf_bot_diff_allies", 2 );
    self menu_item( "botdiff", "Veteran", &act_bot_diff, 3, undefined, #"gf_bot_diff_allies", 3 );
    self menu_item( "botdiff", "CUSTOM - the tuning page", &act_bot_diff, 4, undefined, #"gf_bot_diff_allies", 4 );
    self menu_item( "botdiff", "Lobby's value - stock row", &act_bot_diff, -1, undefined, #"gf_bot_diff_allies", -1 );
    self menu_add( "botdiff_team", "Per team", "botdiff", 1 );
    self menu_item( "botdiff_team", "Allies: Recruit", &act_bot_diff_team, "allies", 0, #"gf_bot_diff_allies", 0 );
    self menu_item( "botdiff_team", "Allies: Regular", &act_bot_diff_team, "allies", 1, #"gf_bot_diff_allies", 1 );
    self menu_item( "botdiff_team", "Allies: Hardened", &act_bot_diff_team, "allies", 2, #"gf_bot_diff_allies", 2 );
    self menu_item( "botdiff_team", "Allies: Veteran", &act_bot_diff_team, "allies", 3, #"gf_bot_diff_allies", 3 );
    self menu_item( "botdiff_team", "Allies: CUSTOM", &act_bot_diff_team, "allies", 4, #"gf_bot_diff_allies", 4 );
    self menu_item( "botdiff_team", "Allies: lobby's value", &act_bot_diff_team, "allies", -1, #"gf_bot_diff_allies", -1 );
    self menu_item( "botdiff_team", "Axis: Recruit", &act_bot_diff_team, "axis", 0, #"gf_bot_diff_axis", 0 );
    self menu_item( "botdiff_team", "Axis: Regular", &act_bot_diff_team, "axis", 1, #"gf_bot_diff_axis", 1 );
    self menu_item( "botdiff_team", "Axis: Hardened", &act_bot_diff_team, "axis", 2, #"gf_bot_diff_axis", 2 );
    self menu_item( "botdiff_team", "Axis: Veteran", &act_bot_diff_team, "axis", 3, #"gf_bot_diff_axis", 3 );
    self menu_item( "botdiff_team", "Axis: CUSTOM", &act_bot_diff_team, "axis", 4, #"gf_bot_diff_axis", 4 );
    self menu_item( "botdiff_team", "Axis: lobby's value", &act_bot_diff_team, "axis", -1, #"gf_bot_diff_axis", -1 );
    // The custom profile: rebuilt from the dvars every time it opens (bot_custom_enter),
    // each row shows its live value and SELECT cycles it. Presets at the top.
    self menu_add( "botcustom", "Custom bot tuning", "botdiff", 1, &bot_custom_enter );

    // ── Players — rebuilt from getplayers() every time the page opens ────────
    self menu_add( "players", "Players", "start_menu", 1, &players_enter );

    // ── Round ────────────────────────────────────────────────────────────────
    self menu_add( "round", "Round", "start_menu", 1 );
    self menu_item( "round", "Timer 20s", &act_timer, 20, undefined, #"gf_timer_seconds", 20 );
    self menu_item( "round", "Timer 30s", &act_timer, 30, undefined, #"gf_timer_seconds", 30 );
    self menu_item( "round", "Timer 40s", &act_timer, 40, undefined, #"gf_timer_seconds", 40 );
    self menu_item( "round", "Timer 60s", &act_timer, 60, undefined, #"gf_timer_seconds", 60 );
    self menu_item( "round", "Timer 90s", &act_timer, 90, undefined, #"gf_timer_seconds", 90 );
    self menu_item( "round", "Timer 120s", &act_timer, 120, undefined, #"gf_timer_seconds", 120 );
    // 0 = no timer at all (see mod_gettimelimit). Elimination is the only way a round ends.
    self menu_item( "round", "Timer unlimited", &act_timer, 0, undefined, #"gf_timer_seconds", 0 );
    // Pre-match / pre-round countdowns (mod_periods). Defaults 15s / 7s. A pick lands on the
    // NEXT countdown - the current one was read before the menu existed this round. "Lobby's
    // value" hands the row back to the custom-games menu (dvar -1).
    self menu_add( "periods", "Pre-match / pre-round", "round", 1 );
    self menu_item( "periods", "Pre-match 5s", &act_prematch, 5, undefined, #"gf_prematch", 5 );
    self menu_item( "periods", "Pre-match 10s", &act_prematch, 10, undefined, #"gf_prematch", 10 );
    self menu_item( "periods", "Pre-match 15s", &act_prematch, 15, undefined, #"gf_prematch", 15 );
    self menu_item( "periods", "Pre-match 30s", &act_prematch, 30, undefined, #"gf_prematch", 30 );
    self menu_item( "periods", "Pre-match lobby's value", &act_prematch, -1, undefined, #"gf_prematch", -1 );
    self menu_item( "periods", "Pre-round off", &act_preround, 0, undefined, #"gf_preround", 0 );
    self menu_item( "periods", "Pre-round 3s", &act_preround, 3, undefined, #"gf_preround", 3 );
    self menu_item( "periods", "Pre-round 5s", &act_preround, 5, undefined, #"gf_preround", 5 );
    self menu_item( "periods", "Pre-round 7s", &act_preround, 7, undefined, #"gf_preround", 7 );
    self menu_item( "periods", "Pre-round 10s", &act_preround, 10, undefined, #"gf_preround", 10 );
    self menu_item( "periods", "Pre-round lobby's value", &act_preround, -1, undefined, #"gf_preround", -1 );
    self menu_item( "round", "Restart match", &act_restart );

    // ── Loadout set — B6, never run ──────────────────────────────────────────
    self menu_add( "loadout", "Loadout", "start_menu", 1 );
    self menu_item( "loadout", "Default", &act_loadout, 0, undefined, #"gf_loadout", 0 );
    self menu_item( "loadout", "Snipers", &act_loadout, 1, undefined, #"gf_loadout", 1 );
    self menu_item( "loadout", "Blueprints", &act_loadout, 2, undefined, #"gf_loadout", 2 );
    self menu_item( "loadout", "Melee", &act_loadout, 3, undefined, #"gf_loadout", 3 );
    // The custom-classes gate. OFF = real Gunfight (fixed loadouts). It is what a switch
    // from another mode leaves ON by accident (the settings blob carries), see mod_apply.
    self menu_item( "loadout", "Custom classes OFF - Gunfight loadouts", &act_customcac, 0, undefined, #"gf_customcac", 0 );
    self menu_item( "loadout", "Custom classes ON", &act_customcac, 1, undefined, #"gf_customcac", 1 );
    // The real Gunfight blob (column A) asserted at every Gunfight match start, so a Case-B
    // launch (TDM lobby config) plays as real Gunfight. OFF = watch the raw hybrid on purpose.
    self menu_item( "loadout", "Gunfight profile ON - real blob", &act_profile, 1, undefined, #"gf_profile", 1 );
    self menu_item( "loadout", "Gunfight profile OFF - raw hybrid", &act_profile, 0, undefined, #"gf_profile", 0 );

    // ── Loadout-pool camo — every pool weapon, every player, every spawn. A pick repaints
    //    everyone NOW as well (Gunfight has no respawn, so "next spawn" is next round).
    //    Mastery and Pack-a-Punch by name; the rest of the 1-121 table by id. Untested. ──
    self menu_add( "poolcamo", "Pool camo", "loadout", 1 );
    self menu_item( "poolcamo", "Random each round", &act_poolcamo, -2, undefined, #"gf_camo", -2 );
    self menu_item( "poolcamo", "Random per player", &act_poolcamo, -3, undefined, #"gf_camo", -3 );
    self menu_item( "poolcamo", "Stock - pool's own look", &act_poolcamo, -1, undefined, #"gf_camo", -1 );
    self menu_item( "poolcamo", "Random: separate per weapon", &act_poolcamo_split, 1, undefined, #"gf_camo_split", 1 );
    self menu_item( "poolcamo", "Random: same for both", &act_poolcamo_split, 0, undefined, #"gf_camo_split", 0 );
    self menu_item( "poolcamo", "Gold", &act_poolcamo, 61, undefined, #"gf_camo", 61 );
    self menu_item( "poolcamo", "Diamond", &act_poolcamo, 62, undefined, #"gf_camo", 62 );
    self menu_item( "poolcamo", "DM Ultra", &act_poolcamo, 63, undefined, #"gf_camo", 63 );
    self menu_item( "poolcamo", "Golden Viper (ZM gold)", &act_poolcamo, 64, undefined, #"gf_camo", 64 );
    self menu_item( "poolcamo", "Plague Diamond (ZM)", &act_poolcamo, 65, undefined, #"gf_camo", 65 );
    self menu_item( "poolcamo", "Dark Aether (ZM)", &act_poolcamo, 66, undefined, #"gf_camo", 66 );
    self menu_item( "poolcamo", "Pack-a-Punch 1", &act_poolcamo, 67, undefined, #"gf_camo", 67 );
    self menu_item( "poolcamo", "Pack-a-Punch 2", &act_poolcamo, 68, undefined, #"gf_camo", 68 );
    self menu_item( "poolcamo", "Pack-a-Punch 3", &act_poolcamo, 69, undefined, #"gf_camo", 69 );
    self menu_item( "poolcamo", "PaP Mauer der Toten 1", &act_poolcamo, 116, undefined, #"gf_camo", 116 );
    self menu_item( "poolcamo", "PaP Mauer der Toten 2", &act_poolcamo, 117, undefined, #"gf_camo", 117 );
    self menu_item( "poolcamo", "PaP Mauer der Toten 3", &act_poolcamo, 118, undefined, #"gf_camo", 118 );
    self menu_item( "poolcamo", "PaP Forsaken 1", &act_poolcamo, 119, undefined, #"gf_camo", 119 );
    self menu_item( "poolcamo", "PaP Forsaken 2", &act_poolcamo, 120, undefined, #"gf_camo", 120 );
    self menu_item( "poolcamo", "PaP Forsaken 3", &act_poolcamo, 121, undefined, #"gf_camo", 121 );
    self menu_item( "poolcamo", "Random pool: mastery + PaP", &act_poolcamo_pool, 0, undefined, #"gf_camo_pool", 0 );
    self menu_item( "poolcamo", "Random pool: all 1-121", &act_poolcamo_pool, 1, undefined, #"gf_camo_pool", 1 );
    self menu_add( "poolcamo_byid", "Pool camo by ID (1-121)", "poolcamo", 1 );
    for ( ci = 1; ci <= 121; ci++ )
        self menu_item( "poolcamo_byid", "Camo " + ci, &act_poolcamo, ci, undefined, #"gf_camo", ci );

    // ── Spy plane — value 3 is the one the rules menu hides. B7, never run ───
    self menu_add( "spyplane", "Spy plane", "start_menu", 1 );
    self menu_item( "spyplane", "Off", &act_spyplane, 0, undefined, #"gf_spyplane", 0 );
    self menu_item( "spyplane", "On", &act_spyplane, 1, undefined, #"gf_spyplane", 1 );
    self menu_item( "spyplane", "Shared - hidden value", &act_spyplane, 3, undefined, #"gf_spyplane", 3 );

    // ── Spawns — #spawn_guard. Default OFF, UNTESTED: test SOLO first ─────────
    self menu_add( "spawns", "Spawns", "start_menu", 1 );
    self menu_item( "spawns", "Spawn guard OFF", &act_spawn_guard, 0, undefined, #"gf_spawn_guard", 0 );
    self menu_item( "spawns", "Spawn guard AUTO (only bad maps)", &act_spawn_guard, 2, undefined, #"gf_spawn_guard", 2 );
    self menu_item( "spawns", "Spawn guard FORCE (every map)", &act_spawn_guard, 1, undefined, #"gf_spawn_guard", 1 );
    // Anti-stack net: fans out anyone who spawns on top of another player, on any map. Default ON.
    self menu_item( "spawns", "Anti-stack net ON", &act_spawn_antistack, 1, undefined, #"gf_spawn_antistack", 1 );
    self menu_item( "spawns", "Anti-stack net OFF", &act_spawn_antistack, 0, undefined, #"gf_spawn_antistack", 0 );
    // Crossroads under Gunfight loads the full 12v12 map (its script opens it for every
    // gametype outside its Strike list). ON keeps the Strike clips by renaming them before
    // the map deletes them. No-op on other maps.
    self menu_item( "spawns", "Crossroads: Strike layout ON", &act_strike, 1, undefined, #"gf_strike", 1 );
    self menu_item( "spawns", "Crossroads: full map - stock", &act_strike, 0, undefined, #"gf_strike", 0 );
    // Which markers become the two sides: near = around the centre at the gap (TDM's
    // respawn zone, the "closer up" spawns); far ends = the two extremes (TDM's openings).
    self menu_item( "spawns", "Pick: near - gap based", &act_spawn_pick, 0, undefined, #"gf_spawn_pick", 0 );
    self menu_item( "spawns", "Pick: far ends - like TDM openings", &act_spawn_pick, 1, undefined, #"gf_spawn_pick", 1 );
    // How far apart the guard puts the two sides (units between the side centres).
    self menu_item( "spawns", "Guard gap 1200", &act_spawn_gap, 1200, undefined, #"gf_spawn_gap", 1200 );
    self menu_item( "spawns", "Guard gap 1800", &act_spawn_gap, 1800, undefined, #"gf_spawn_gap", 1800 );
    self menu_item( "spawns", "Guard gap 2400", &act_spawn_gap, 2400, undefined, #"gf_spawn_gap", 2400 );
    self menu_item( "spawns", "Guard gap 3200", &act_spawn_gap, 3200, undefined, #"gf_spawn_gap", 3200 );
    self menu_item( "spawns", "Spawn report", &act_spawn_report );
    // The evidence rows (docs/notes/spawn-system.md) - debug-feed toggles: one complete line
    // every 3 s while on. Placements need gf_spawn_diag 1 (default) to be recorded.
    self menu_item( "spawns", "Debug: spawn placements this round", &act_dbg_spawn, undefined, undefined, #"gf_dbg_spawn", 1 );
    self menu_item( "spawns", "Debug: spawn structs + engine lists", &act_dbg_structs, undefined, undefined, #"gf_dbg_structs", 1 );
    self menu_item( "spawns", "Debug: spawn families + guard state", &act_dbg_families, undefined, undefined, #"gf_dbg_families", 1 );
    self menu_item( "spawns", "Debug: marker flags census", &act_dbg_flags, undefined, undefined, #"gf_dbg_flags", 1 );
    // Which mode's markers the guard builds from (every spawn on them when set).
    self menu_item( "spawns", "Family: AUTO - authored S&D starts, else TDM starts", &act_spawn_family, 8, undefined, #"gf_spawn_family", 8 );
    self menu_item( "spawns", "Family: none - engine / geometric", &act_spawn_family, 0, undefined, #"gf_spawn_family", 0 );
    self menu_item( "spawns", "Family: S&D markers", &act_spawn_family, 2, undefined, #"gf_spawn_family", 2 );
    self menu_item( "spawns", "Family: TDM markers", &act_spawn_family, 1, undefined, #"gf_spawn_family", 1 );
    self menu_item( "spawns", "Family: Domination markers", &act_spawn_family, 3, undefined, #"gf_spawn_family", 3 );
    self menu_item( "spawns", "Family: CTF markers", &act_spawn_family, 4, undefined, #"gf_spawn_family", 4 );
    self menu_item( "spawns", "Family: Hardpoint markers", &act_spawn_family, 5, undefined, #"gf_spawn_family", 5 );
    self menu_item( "spawns", "Family: Control markers", &act_spawn_family, 6, undefined, #"gf_spawn_family", 6 );
    self menu_item( "spawns", "Family: FFA markers", &act_spawn_family, 7, undefined, #"gf_spawn_family", 7 );

    // ── Display — the text layout. SPLIT is klaze's "status left, menu centre". Kept a
    // live toggle so a build where the centre clips the list can be reverted in-menu. ──
    self menu_add( "display", "Display", "start_menu", 1 );
    // Region 4 = the HINT panel: the use-prompt widget, fed by sethintstring on a trigger
    // linked to the host. No fade, no line cap, one call per repaint - the layout every
    // "full HUD" Cold War GSC menu really uses (menu_render_hint). Never run here; the two
    // knobs under it are the measurements it needs.
    self menu_item( "display", "Layout: HINT panel, use-prompt widget", &act_menu_region, 4, undefined, #"gf_menu_region", 4 );
    self menu_item( "display", "Hint rows 6", &act_hint_lines, 6, undefined, #"gf_hint_lines", 6 );
    self menu_item( "display", "Hint rows 8", &act_hint_lines, 8, undefined, #"gf_hint_lines", 8 );
    self menu_item( "display", "Hint rows 12", &act_hint_lines, 12, undefined, #"gf_hint_lines", 12 );
    // Newline separator removed: a \n in sethintstring closes the match (measured 2026-09-14).
    // Rows are always packed with ^8| now; menu_render_hint hardcodes the separator.
    // The centre shows only ONE line (engine limit), so region 2 renders the menu there as
    // a HORIZONTAL carousel (items side by side, current bracketed, sliding as you scroll).
    // Region 3 puts a vertical multi-row list in the ~4-line lower-left feed instead.
    self menu_item( "display", "Layout: status left + menu centre, sideways scroll", &act_menu_region, 2, undefined, #"gf_menu_region", 2 );
    self menu_item( "display", "Layout: menu left + status centre", &act_menu_region, 3, undefined, #"gf_menu_region", 3 );
    self menu_item( "display", "Layout: all in lower-left feed", &act_menu_region, 0, undefined, #"gf_menu_region", 0 );
    self menu_item( "display", "Layout: all in centre", &act_menu_region, 1, undefined, #"gf_menu_region", 1 );
    // Region-2 carousel width (entries shown at once in the centre bar).
    self menu_item( "display", "Centre width 3", &act_menu_hspan, 3, undefined, #"gf_menu_hspan", 3 );
    self menu_item( "display", "Centre width 4", &act_menu_hspan, 4, undefined, #"gf_menu_hspan", 4 );
    self menu_item( "display", "Centre width 5", &act_menu_hspan, 5, undefined, #"gf_menu_hspan", 5 );
    // Full state readout to the feed (more than the pane can hold at once).
    self menu_item( "display", "Show match info", &act_match_info );
    // Debug feed: every debug tool as an on/off that prints ONE complete feed line every
    // 3 s while on (klaze, 2026-09-14). Persists across matches (dvars), restarts at match
    // start. See DEBUG FEED.
    self menu_add( "debug", "Debug feed", "display", 1 );
    self menu_item( "debug", "Settings census: AS LAUNCHED", &act_dbg_census, 1, undefined, #"gf_census", 1 );
    self menu_item( "debug", "Settings census: LIVE", &act_dbg_census, 2, undefined, #"gf_census", 2 );
    self menu_item( "debug", "Spawn placements this round", &act_dbg_spawn, undefined, undefined, #"gf_dbg_spawn", 1 );
    self menu_item( "debug", "Spawn structs + engine lists", &act_dbg_structs, undefined, undefined, #"gf_dbg_structs", 1 );
    self menu_item( "debug", "Spawn families + guard state", &act_dbg_families, undefined, undefined, #"gf_dbg_families", 1 );
    self menu_item( "debug", "Marker flags census", &act_dbg_flags, undefined, undefined, #"gf_dbg_flags", 1 );
    self menu_item( "debug", "Match info", &act_dbg_match, undefined, undefined, #"gf_dbg_match", 1 );
    self menu_item( "debug", "Asset census: vehicles + props + destructibles", &act_dbg_assets, undefined, undefined, #"gf_dbg_assets", 1 );
    self menu_item( "debug", "Everything off", &act_dbg_all_off );
    // Caster diagnosis: prints button/render probe lines while the host is a CoD Caster.
    self menu_item( "display", "Caster input probe ON", &act_caster_probe, 1, undefined, #"gf_caster_probe", 1 );
    self menu_item( "display", "Caster input probe OFF", &act_caster_probe, 0, undefined, #"gf_caster_probe", 0 );

    // ── Overtime zone — default OFF. Run the census first. docs/notes/overtime-zone.md ─
    self menu_add( "zone", "Overtime zone", "start_menu", 1 );
    self menu_item( "zone", "Zone census - read only", &act_zone_census );
    self menu_item( "zone", "Zone OFF - HP tiebreak", &act_zone, 0, undefined, #"gf_zone", 0 );
    self menu_item( "zone", "Zone ON - from next round", &act_zone, 1, undefined, #"gf_zone", 1 );
    self menu_item( "zone", "Overtime 10s", &act_zone_overtime, 10, undefined, #"gf_zone_overtime", 10 );
    self menu_item( "zone", "Overtime 20s", &act_zone_overtime, 20, undefined, #"gf_zone_overtime", 20 );
    self menu_item( "zone", "Overtime 30s", &act_zone_overtime, 30, undefined, #"gf_zone_overtime", 30 );
    self menu_item( "zone", "Capture 3s", &act_zone_capture, 3, undefined, #"gf_zone_capture", 3 );
    self menu_item( "zone", "Capture 5s", &act_zone_capture, 5, undefined, #"gf_zone_capture", 5 );
    self menu_item( "zone", "Capture 10s", &act_zone_capture, 10, undefined, #"gf_zone_capture", 10 );

    // ── Match — first-to / round cap / loadout rotation. Keys verified in source ─
    self menu_add( "match", "Match", "start_menu", 1 );
    self menu_item( "match", "First to 2", &act_roundwinlimit, 2, undefined, #"gf_roundwinlimit", 2 );
    self menu_item( "match", "First to 4", &act_roundwinlimit, 4, undefined, #"gf_roundwinlimit", 4 );
    self menu_item( "match", "First to 6", &act_roundwinlimit, 6, undefined, #"gf_roundwinlimit", 6 );
    self menu_item( "match", "First to 10", &act_roundwinlimit, 10, undefined, #"gf_roundwinlimit", 10 );
    self menu_item( "match", "Round cap 6", &act_roundlimit, 6, undefined, #"gf_roundlimit", 6 );
    self menu_item( "match", "Round cap 10", &act_roundlimit, 10, undefined, #"gf_roundlimit", 10 );
    // Rotates the loadout AND switches sides every N rounds - stock couples both to this one
    // setting (gunfight.gsc onendround). "Rotate 1" = switch every round.
    self menu_item( "match", "Loadout+sides every 1", &act_rounds_loadout, 1, undefined, #"gf_rounds_loadout", 1 );
    self menu_item( "match", "Loadout+sides every 2", &act_rounds_loadout, 2, undefined, #"gf_rounds_loadout", 2 );
    self menu_item( "match", "Loadout+sides every 3", &act_rounds_loadout, 3, undefined, #"gf_rounds_loadout", 3 );
    // Who flips the sides: the mod (bundle gate forced on, generic roundswitch path silenced -
    // one flip per rotation) or stock (both paths live; two flips on one boundary cancel).
    self menu_item( "match", "Side switch: mod-owned, one flip", &act_switch_sides, 1, undefined, #"gf_switch_sides", 1 );
    self menu_item( "match", "Side switch: stock paths", &act_switch_sides, 0, undefined, #"gf_switch_sides", 0 );

    // ── Movement — a hub of sub-pages (the window is ~3 rows): gravity (verified),
    // jump (builtin, untested) + jump BOOST (setvelocity, stock's shape), speed
    // (setmovespeedscale, stock's scaler), fall damage, and the host's fly mode. ─────────
    self menu_add( "movement", "Movement", "start_menu", 1 );
    self menu_item( "movement", "Fly mode - host", &act_fly );
    self menu_add( "mv_gravity", "Gravity", "movement", 1 );
    self menu_item( "mv_gravity", "Gravity normal 800", &act_gravity, 800, undefined, #"gf_gravity", 800 );
    self menu_item( "mv_gravity", "Gravity low 400", &act_gravity, 400, undefined, #"gf_gravity", 400 );
    self menu_item( "mv_gravity", "Gravity moon 200", &act_gravity, 200, undefined, #"gf_gravity", 200 );
    self menu_item( "mv_gravity", "Gravity floaty 100", &act_gravity, 100, undefined, #"gf_gravity", 100 );
    self menu_item( "mv_gravity", "Gravity space 40", &act_gravity, 40, undefined, #"gf_gravity", 40 );
    // Boost = extra upward velocity at takeoff; apex figures assume stock gravity.
    self menu_add( "mv_jump", "Jump", "movement", 1 );
    self menu_item( "mv_jump", "Boost off - stock jump", &act_jump_boost, 0, undefined, #"gf_jump_boost", 0 );
    self menu_item( "mv_jump", "Boost low ~100u apex", &act_jump_boost, 150, undefined, #"gf_jump_boost", 150 );
    self menu_item( "mv_jump", "Boost mid ~260u", &act_jump_boost, 400, undefined, #"gf_jump_boost", 400 );
    self menu_item( "mv_jump", "Boost high ~700u", &act_jump_boost, 800, undefined, #"gf_jump_boost", 800 );
    self menu_item( "mv_jump", "Boost extreme ~1500u", &act_jump_boost, 1300, undefined, #"gf_jump_boost", 1300 );
    self menu_item( "mv_jump", "Boost insane ~3000u", &act_jump_boost, 1900, undefined, #"gf_jump_boost", 1900 );
    // The setjumpheight builtin rows, kept: no stock caller, never watched - if a pick
    // visibly changes the jump, it works and this comment goes.
    self menu_item( "mv_jump", "Builtin jump: leave stock", &act_jump, -1, undefined, #"gf_jump", -1 );
    self menu_item( "mv_jump", "Builtin jump 70", &act_jump, 70, undefined, #"gf_jump", 70 );
    self menu_item( "mv_jump", "Builtin jump 200", &act_jump, 200, undefined, #"gf_jump", 200 );
    self menu_item( "mv_jump", "Builtin jump 500", &act_jump, 500, undefined, #"gf_jump", 500 );
    self menu_item( "mv_jump", "Builtin jump 1000", &act_jump, 1000, undefined, #"gf_jump", 1000 );
    self menu_add( "mv_speed", "Speed", "movement", 1 );
    self menu_item( "mv_speed", "Speed 50%", &act_speed, 50, undefined, #"gf_speed", 50 );
    self menu_item( "mv_speed", "Speed 75%", &act_speed, 75, undefined, #"gf_speed", 75 );
    self menu_item( "mv_speed", "Speed 100% - stock", &act_speed, 100, undefined, #"gf_speed", 100 );
    self menu_item( "mv_speed", "Speed 125%", &act_speed, 125, undefined, #"gf_speed", 125 );
    self menu_item( "mv_speed", "Speed 150%", &act_speed, 150, undefined, #"gf_speed", 150 );
    self menu_item( "mv_speed", "Speed 200%", &act_speed, 200, undefined, #"gf_speed", 200 );
    self menu_item( "mv_speed", "Speed 300%", &act_speed, 300, undefined, #"gf_speed", 300 );
    self menu_add( "mv_fall", "Fall damage", "movement", 1 );
    self menu_item( "mv_fall", "Fall damage: stock", &act_falldamage, 1, undefined, #"gf_falldamage", 1 );
    self menu_item( "mv_fall", "Fall damage: OFF", &act_falldamage, 0, undefined, #"gf_falldamage", 0 );
    // The restricted-area warning + death, everyone. Default OFF (gf_oob 1). Applies now and
    // re-applies every spawn (stock nukes the flag per life).
    self menu_add( "mv_oob", "Out of bounds", "movement", 1 );
    self menu_item( "mv_oob", "Out of bounds OFF - no warning, no death", &act_oob, 1, undefined, #"gf_oob", 1 );
    self menu_item( "mv_oob", "Out of bounds: stock", &act_oob, 0, undefined, #"gf_oob", 0 );
    self menu_add( "mv_fly", "Fly speed", "movement", 1 );
    self menu_item( "mv_fly", "Fly 10 / sprint 30", &act_fly_speed, 10, 30, #"gf_fly_speed", 10 );
    self menu_item( "mv_fly", "Fly 20 / sprint 60", &act_fly_speed, 20, 60, #"gf_fly_speed", 20 );
    self menu_item( "mv_fly", "Fly 40 / sprint 120", &act_fly_speed, 40, 120, #"gf_fly_speed", 40 );
    self menu_item( "mv_fly", "Fly 80 / sprint 240", &act_fly_speed, 80, 240, #"gf_fly_speed", 80 );

    // ── Host — pause / freeze / broadcast ────────────────────────────────────
    self menu_add( "host", "Host", "start_menu", 1 );
    self menu_item( "host", "Pause - freeze all, hold timer, banner", &act_pause );
    self menu_item( "host", "Freeze everyone - no banner", &act_freeze_all );
    self menu_item( "host", "Countdown 5..1 GO - bold", &act_countdown );
    self menu_item( "host", "Announce settings to all", &act_announce );
    self menu_add( "say", "Broadcast a message", "host", 1 );
    self menu_item( "say", "Welcome - custom Gunfight, host menu on", &act_say, "Welcome! Custom Gunfight - the host runs the settings" );
    self menu_item( "say", "Starting soon - get ready", &act_say, "Starting soon - get ready" );
    self menu_item( "say", "Map switch next round", &act_say, "Map switch next round - stay in the lobby" );
    self menu_item( "say", "Sides switch next round", &act_say, "Sides switch next round" );
    self menu_item( "say", "Bots joining to fill teams", &act_say, "Bots joining to fill the teams" );
    self menu_item( "say", "Custom rules on - ask the host", &act_say, "Custom rules are ON - ask the host" );
    self menu_item( "say", "Do not leave - wait for the host", &act_say, "Do not leave - wait for the host" );
    self menu_item( "say", "GG - lobby after this", &act_say, "GG! Back to the lobby after this one" );
    self menu_item( "say", "One more round", &act_say, "One more round!" );
    // Links coloured (^5 cyan) so they stand out from the message text.
    self menu_item( "say", "Visit us at gunfight.us", &act_say, "Visit us at ^5gunfight.us" );
    self menu_item( "say", "Join us at discord.gg/blackops", &act_say, "Join us at ^5discord.gg/blackops" );
    // Hint-banner broadcasts: a PERSISTENT line at the use-prompt anchor, held until Clear
    // (the centre/feed items above send once). broadcast_hint_start( msg, -1 ).
    self menu_item( "say", "Banner: gunfight.us [held]", &act_banner, "^7Custom Gunfight  ^5gunfight.us" );
    self menu_item( "say", "Banner: discord.gg/blackops [held]", &act_banner, "^7Join  ^5discord.gg/blackops" );
    self menu_item( "say", "Banner: waiting for host [held]", &act_banner, "^3Waiting for the host..." );
    self menu_item( "say", "Clear banner", &act_banner_clear, undefined );

    // ── Vehicles — built per map from what is resident (veh_page_build) ──────
    self menu_add( "vehicles", "Vehicles", "start_menu", 1 );
    self veh_mode_page_build();     // Vehicle MODE: everyone spawns riding (docs/notes/vehicle-mode.md)
    self veh_page_build();          // rows = what THIS map has resident (veh_master)

    // ── Destructibles + radiant exploders — docs/notes/destructibles.md. Both pages are
    //    rebuilt on entry (live counts, the map's own table). Nothing here has run in-game. ──
    self menu_add( "destruct", "Destructibles + exploders", "start_menu", 1, &destruct_enter );
    self menu_add( "exploders", "Radiant exploders", "destruct", 0, &exp_enter );

    // ── Projectiles — docs/notes/projectiles.md: every shot also fires a projectile of the
    //    chosen weapon down the aim line (magicbullet), rate-gated; optional homing. Per match. ──
    self menu_add( "proj", "Projectiles", "start_menu", 1 );
    self menu_item( "proj", "Fire mode - host", &act_proj, "host" );
    self menu_item( "proj", "Fire mode - everyone", &act_proj, "all" );
    self menu_item( "proj", "Everything OFF", &act_proj, "off" );
    self menu_item( "proj", "Homing - lock the enemy I face", &act_proj_homing );
    self menu_item( "proj", "Smoke trail FX (untested)", &act_proj_trail );
    self menu_add( "proj_weapon", "Projectile", "proj", 1 );
    self menu_item( "proj_weapon", "RPG rocket (free-fire launcher)", &act_proj_weapon, #"launcher_freefire_t9", "RPG rockets" );
    self menu_item( "proj_weapon", "Cigma missile (lock-on launcher)", &act_proj_weapon, #"launcher_standard_t9", "Cigma missiles" );
    self menu_item( "proj_weapon", "Crossbow bolt", &act_proj_weapon, #"special_crossbow_t9", "crossbow bolts" );
    self menu_item( "proj_weapon", "M79 grenade", &act_proj_weapon, #"special_grenadelauncher_t9", "M79 grenades" );
    self menu_item( "proj_weapon", "Combat bow arrow (explosive)", &act_proj_weapon, #"sig_bow_flame", "combat bow arrows" );
    self menu_item( "proj_weapon", "Strafe run rocket", &act_proj_weapon, #"straferun_rockets", "strafe run rockets" );
    self menu_item( "proj_weapon", "Cruise missile bomblet", &act_proj_weapon, #"remote_missile_bomblet", "cruise missile bomblets" );
    self menu_item( "proj_weapon", "Jet fighter missile", &act_proj_weapon, #"jetfighter_missile", "jet fighter missiles" );
    self menu_item( "proj_weapon", "Frag grenade", &act_proj_weapon, #"frag_grenade", "frag grenades" );
    self menu_add( "proj_rate", "Rate", "proj", 1 );
    self menu_item( "proj_rate", "One per 1000 ms", &act_proj_rate, 1000 );
    self menu_item( "proj_rate", "One per 600 ms", &act_proj_rate, 600 );
    self menu_item( "proj_rate", "One per 300 ms - default", &act_proj_rate, 300 );
    self menu_item( "proj_rate", "One per 150 ms", &act_proj_rate, 150 );
    self menu_item( "proj_rate", "EVERY shot (full-auto test)", &act_proj_rate, 0 );

    // ── Props — docs/notes/static-props.md: this map's Prop Hunt table + a universal set,
    //    placed where the host looks. Rebuilt on entry. ─────────────────────────────────────
    self menu_add( "props", "Props", "start_menu", 1, &props_enter );
    self menu_add( "props_map", "This map's Prop Hunt set", "props", 0, &props_map_enter );
    self menu_add( "props_univ", "Universal props", "props", 0, &props_univ_enter );

    // ── Player tools — host only ─────────────────────────────────────────────
    self menu_add( "player", "Player", "start_menu", 1 );
    self menu_item( "player", "Godmode", &act_godmode );
    self menu_item( "player", "Third person", &act_thirdperson );
    self menu_item( "player", "Give max ammo", &act_maxammo );
    self menu_item( "player", "Drop weapon", &act_dropweapon );
    self menu_item( "player", "Unlock all (best-effort)", &act_unlockall );

    // ── Teleport — a hub (docs/notes/teleport.md): everyone / a side to a point, me to a
    // point, and the teleport gun / grenade toggles. The per-player rows (to me / me to
    // them / swap) live on the Players page. "Crosshair" = where the host aims, floored;
    // "saved point" = Save point below (game., survives rounds); "map centre" =
    // level.mapcenter. Nothing here has run in-game yet (2026-09-15). ────────────────
    self menu_add( "teleport", "Teleport", "start_menu", 1 );
    self menu_add( "tp_all", "Everyone to...", "teleport", 1 );
    self menu_item( "tp_all", "All to me", &act_tp_all, "me", "all" );
    self menu_item( "tp_all", "All to my crosshair", &act_tp_all, "aim", "all" );
    self menu_item( "tp_all", "All to saved point", &act_tp_all, "saved", "all" );
    self menu_item( "tp_all", "All to map centre", &act_tp_all, "centre", "all" );
    self menu_item( "tp_all", "My team to me", &act_tp_all, "me", "team" );
    self menu_item( "tp_all", "Other team to me", &act_tp_all, "me", "enemy" );
    self menu_item( "tp_all", "My team to crosshair", &act_tp_all, "aim", "team" );
    self menu_item( "tp_all", "Other team to crosshair", &act_tp_all, "aim", "enemy" );
    self menu_add( "tp_me", "Me to...", "teleport", 1 );
    self menu_item( "tp_me", "Me to crosshair", &act_tp_me, "aim" );
    self menu_item( "tp_me", "Me to saved point", &act_tp_me, "saved" );
    self menu_item( "tp_me", "Me to map centre", &act_tp_me, "centre" );
    self menu_item( "tp_me", "Save point = where I stand", &act_tp_save );
    self menu_add( "tp_gun", "Teleport gun / grenade", "teleport", 1 );
    self menu_item( "tp_gun", "Teleport gun - host", &act_tpgun, "host" );
    self menu_item( "tp_gun", "Teleport gun - everyone", &act_tpgun, "all" );
    self menu_item( "tp_gun", "Teleport grenade - host", &act_tpnade, "host" );
    self menu_item( "tp_gun", "Teleport grenade - everyone", &act_tpnade, "all" );

    // ── Weapons — every MP loadout weapon, by class. The 64 names are the complete set
    // gamedata/weapons/mp/mp_gunlevels.csv levels (= the custom-games restriction enum,
    // ddl/mp_custom_game.ddl); the extras at the end are BO4 leftovers the shipped Atian
    // menu lists for MP. Display names: docs/reference/bocw-weapons.md - the ones marked ?
    // are inferred from the internal name and unverified in-game. There is NO rock /
    // gulag / throwable weapon anywhere in the T9 data (the Warzone gulag rock is an IW8
    // asset) - see the reference note. ──────────────────────────────────────────────────
    self menu_add( "weapons", "Weapons", "start_menu", 1 );
    self menu_add( "wp_ar", "Assault rifles", "weapons", 1 );
    self menu_item( "wp_ar", "XM4", &act_giveweapon, #"ar_standard_t9", "XM4" );
    self menu_item( "wp_ar", "AK-47", &act_giveweapon, #"ar_damage_t9", "AK-47" );
    self menu_item( "wp_ar", "Krig 6", &act_giveweapon, #"ar_accurate_t9", "Krig 6" );
    self menu_item( "wp_ar", "QBZ-83", &act_giveweapon, #"ar_fastfire_t9", "QBZ-83" );
    self menu_item( "wp_ar", "FFAR 1", &act_giveweapon, #"ar_fasthandling_t9", "FFAR 1" );
    self menu_item( "wp_ar", "Groza", &act_giveweapon, #"ar_mobility_t9", "Groza" );
    self menu_item( "wp_ar", "FARA 83", &act_giveweapon, #"ar_slowfire_t9", "FARA 83" );
    self menu_item( "wp_ar", "C58", &act_giveweapon, #"ar_slowhandling_t9", "C58" );
    self menu_item( "wp_ar", "EM2", &act_giveweapon, #"ar_british_t9", "EM2" );
    self menu_item( "wp_ar", "Vargo 52 ?", &act_giveweapon, #"ar_season6_t9", "Vargo 52 (ar_season6)" );
    self menu_item( "wp_ar", "Grav ?", &act_giveweapon, #"ar_soviet_t9", "Grav (ar_soviet)" );
    self menu_add( "wp_smg", "SMGs", "weapons", 1 );
    self menu_item( "wp_smg", "MP5", &act_giveweapon, #"smg_standard_t9", "MP5" );
    self menu_item( "wp_smg", "Milano 821", &act_giveweapon, #"smg_handling_t9", "Milano 821" );
    self menu_item( "wp_smg", "AK-74u", &act_giveweapon, #"smg_heavy_t9", "AK-74u" );
    self menu_item( "wp_smg", "KSP 45", &act_giveweapon, #"smg_burst_t9", "KSP 45" );
    self menu_item( "wp_smg", "Bullfrog", &act_giveweapon, #"smg_capacity_t9", "Bullfrog" );
    self menu_item( "wp_smg", "MAC-10", &act_giveweapon, #"smg_fastfire_t9", "MAC-10" );
    self menu_item( "wp_smg", "LC10", &act_giveweapon, #"smg_accurate_t9", "LC10" );
    self menu_item( "wp_smg", "PPSh-41", &act_giveweapon, #"smg_spray_t9", "PPSh-41" );
    self menu_item( "wp_smg", "OTs 9 ?", &act_giveweapon, #"smg_cqb_t9", "OTs 9 (smg_cqb)" );
    self menu_item( "wp_smg", "TEC-9 ?", &act_giveweapon, #"smg_semiauto_t9", "TEC-9 (smg_semiauto)" );
    self menu_item( "wp_smg", "LAPA ?", &act_giveweapon, #"smg_season6_t9", "LAPA (smg_season6)" );
    self menu_item( "wp_smg", "smg_flechette_t9 - unknown", &act_giveweapon, #"smg_flechette_t9", "smg_flechette_t9" );
    self menu_add( "wp_tr", "Tactical rifles", "weapons", 1 );
    self menu_item( "wp_tr", "M16", &act_giveweapon, #"tr_powerburst_t9", "M16" );
    self menu_item( "wp_tr", "AUG ?", &act_giveweapon, #"tr_longburst_t9", "AUG (tr_longburst)" );
    self menu_item( "wp_tr", "CARV.2", &act_giveweapon, #"tr_fastburst_t9", "CARV.2" );
    self menu_item( "wp_tr", "DMR 14", &act_giveweapon, #"tr_precisionsemi_t9", "DMR 14" );
    self menu_item( "wp_tr", "Type 63", &act_giveweapon, #"tr_damagesemi_t9", "Type 63" );
    self menu_add( "wp_lmg", "LMGs", "weapons", 1 );
    self menu_item( "wp_lmg", "Stoner 63", &act_giveweapon, #"lmg_light_t9", "Stoner 63" );
    self menu_item( "wp_lmg", "RPD", &act_giveweapon, #"lmg_slowfire_t9", "RPD" );
    self menu_item( "wp_lmg", "M60", &act_giveweapon, #"lmg_fastfire_t9", "M60" );
    self menu_item( "wp_lmg", "MG 82", &act_giveweapon, #"lmg_accurate_t9", "MG 82" );
    self menu_add( "wp_sniper", "Snipers", "weapons", 1 );
    self menu_item( "wp_sniper", "Pelington 703", &act_giveweapon, #"sniper_standard_t9", "Pelington 703" );
    self menu_item( "wp_sniper", "LW3 Tundra", &act_giveweapon, #"sniper_quickscope_t9", "LW3 Tundra" );
    self menu_item( "wp_sniper", "M82", &act_giveweapon, #"sniper_powersemi_t9", "M82" );
    self menu_item( "wp_sniper", "ZRG 20mm ?", &act_giveweapon, #"sniper_cannon_t9", "ZRG 20mm (sniper_cannon)" );
    self menu_item( "wp_sniper", "Swiss K31 ?", &act_giveweapon, #"sniper_accurate_t9", "Swiss K31 (sniper_accurate)" );
    self menu_add( "wp_shotgun", "Shotguns", "weapons", 1 );
    self menu_item( "wp_shotgun", "Hauer 77", &act_giveweapon, #"shotgun_pump_t9", "Hauer 77" );
    self menu_item( "wp_shotgun", "Gallo SA12", &act_giveweapon, #"shotgun_fullauto_t9", "Gallo SA12" );
    self menu_item( "wp_shotgun", "Streetsweeper", &act_giveweapon, #"shotgun_semiauto_t9", "Streetsweeper" );
    self menu_item( "wp_shotgun", ".410 Ironhide", &act_giveweapon, #"shotgun_leveraction_t9", ".410 Ironhide" );
    self menu_add( "wp_pistol", "Pistols", "weapons", 1 );
    self menu_item( "wp_pistol", "1911", &act_giveweapon, #"pistol_semiauto_t9", "1911" );
    self menu_item( "wp_pistol", "Magnum", &act_giveweapon, #"pistol_revolver_t9", "Magnum" );
    self menu_item( "wp_pistol", "Diamatti", &act_giveweapon, #"pistol_burst_t9", "Diamatti" );
    self menu_item( "wp_pistol", "AMP63", &act_giveweapon, #"pistol_fullauto_t9", "AMP63" );
    self menu_item( "wp_pistol", "Marshal", &act_giveweapon, #"pistol_shotgun_t9", "Marshal" );
    self menu_item( "wp_pistol", "1911 akimbo", &act_giveweapon, #"pistol_semiauto_t9_dw", "1911 akimbo" );
    self menu_item( "wp_pistol", "Magnum akimbo", &act_giveweapon, #"pistol_revolver_t9_dw", "Magnum akimbo" );
    self menu_item( "wp_pistol", "Diamatti akimbo", &act_giveweapon, #"pistol_burst_t9_dw", "Diamatti akimbo" );
    self menu_item( "wp_pistol", "AMP63 akimbo", &act_giveweapon, #"pistol_fullauto_t9_dw", "AMP63 akimbo" );
    self menu_item( "wp_pistol", "Marshal akimbo", &act_giveweapon, #"pistol_shotgun_t9_dw", "Marshal akimbo" );
    self menu_add( "wp_special", "Launchers + special", "weapons", 1 );
    self menu_item( "wp_special", "Cigma 2", &act_giveweapon, #"launcher_standard_t9", "Cigma 2" );
    self menu_item( "wp_special", "RPG-7", &act_giveweapon, #"launcher_freefire_t9", "RPG-7" );
    self menu_item( "wp_special", "M79", &act_giveweapon, #"special_grenadelauncher_t9", "M79" );
    self menu_item( "wp_special", "R1 Shadowhunter", &act_giveweapon, #"special_crossbow_t9", "R1 Shadowhunter" );
    self menu_item( "wp_special", "Nail Gun", &act_giveweapon, #"special_nailgun_t9", "Nail Gun" );
    self menu_item( "wp_special", "Ballistic Knife", &act_giveweapon, #"special_ballisticknife_t9_dw", "Ballistic Knife" );
    self menu_add( "wp_melee", "Melee", "weapons", 1 );
    self menu_item( "wp_melee", "Knife", &act_giveweapon, #"knife_loadout", "Knife" );
    self menu_item( "wp_melee", "Sledgehammer", &act_giveweapon, #"melee_sledgehammer_t9", "Sledgehammer" );
    self menu_item( "wp_melee", "Wakizashi", &act_giveweapon, #"melee_wakizashi_t9", "Wakizashi" );
    self menu_item( "wp_melee", "Machete", &act_giveweapon, #"melee_machete_t9", "Machete" );
    self menu_item( "wp_melee", "E-Tool", &act_giveweapon, #"melee_etool_t9", "E-Tool" );
    self menu_item( "wp_melee", "Baseball Bat", &act_giveweapon, #"melee_baseballbat_t9", "Baseball Bat" );
    self menu_item( "wp_melee", "Mace", &act_giveweapon, #"melee_mace_t9", "Mace" );
    self menu_item( "wp_melee", "Sai", &act_giveweapon, #"melee_sai_t9_dw", "Sai" );
    self menu_item( "wp_melee", "Cane", &act_giveweapon, #"melee_cane_t9", "Cane" );
    self menu_item( "wp_melee", "Battle Axe", &act_giveweapon, #"melee_battleaxe_t9", "Battle Axe" );
    self menu_item( "wp_melee", "Hammer & Sickle ?", &act_giveweapon, #"melee_coldwar_t9_dw", "Hammer & Sickle (melee_coldwar_dw)" );
    self menu_item( "wp_melee", "melee_scythe_t9 - unknown", &act_giveweapon, #"melee_scythe_t9", "melee_scythe_t9" );
    self menu_item( "wp_melee", "Bowie Knife", &act_giveweapon, #"melee_bowie", "Bowie Knife" );
    self menu_item( "wp_melee", "Bowie Knife - bloody", &act_giveweapon, #"melee_bowie_bloody", "Bowie Knife (bloody)" );
    self menu_item( "wp_melee", "Knife - Scream", &act_giveweapon, #"hash_28fdaa999c8aa3af", "Knife (Scream)" );
    self menu_item( "wp_melee", "Knife - Infected", &act_giveweapon, #"hash_3f47e8be065a0dc0", "Knife (Infected)" );
    // BO4 hero/streak guns still in the T9 data and listed for MP by the Atian menu.
    // Loadable there; whether each one FIRES here is untested.
    self menu_add( "wp_fun", "Fun - BO4 leftovers, untested", "weapons", 1 );
    self menu_item( "wp_fun", "Ray Gun", &act_giveweapon, #"ray_gun", "Ray Gun" );
    self menu_item( "wp_fun", "Flamethrower - Purifier", &act_giveweapon, #"hero_flamethrower", "Flamethrower" );
    self menu_item( "wp_fun", "Annihilator", &act_giveweapon, #"hero_annihilator", "Annihilator" );
    self menu_item( "wp_fun", "War Machine - pineapple gun", &act_giveweapon, #"hero_pineapplegun", "War Machine" );
    self menu_item( "wp_fun", "Death Machine - sig_lmg", &act_giveweapon, #"sig_lmg", "Death Machine" );
    self menu_item( "wp_fun", "Sparrow bow - sig_bow_flame", &act_giveweapon, #"sig_bow_flame", "Sparrow" );
    self menu_item( "wp_fun", "Turret gun - ultimate_turret", &act_giveweapon, #"ultimate_turret", "Turret gun" );

    // ── Camo — applied to the current weapon, ownership ignored ───────────────
    self menu_add( "camo", "Camo", "start_menu", 1 );
    self menu_item( "camo", "Gold", &act_camo, 61 );
    self menu_item( "camo", "Diamond", &act_camo, 62 );
    self menu_item( "camo", "DM Ultra", &act_camo, 63 );
    self menu_item( "camo", "Gold (Zombies)", &act_camo, 64 );
    self menu_item( "camo", "Diamond (Zombies)", &act_camo, 65 );
    self menu_item( "camo", "Dark Aether", &act_camo, 66 );
    self menu_item( "camo", "Pack-a-Punch 1", &act_camo, 67 );
    self menu_item( "camo", "Pack-a-Punch 2", &act_camo, 68 );
    self menu_item( "camo", "Pack-a-Punch 3", &act_camo, 69 );
    self menu_add( "camo_byid", "Camo by ID (0-149)", "camo", 1 );
    for ( ci = 0; ci < 150; ci++ )
        self menu_item( "camo_byid", "Camo " + ci, &act_camo, ci );

    // ── Operator (skin) ───────────────────────────────────────────────────────
    self menu_add( "operator", "Operator", "start_menu", 1 );
    self menu_item( "operator", "Invisible", &act_skin, 0 );
    self menu_item( "operator", "Adler", &act_skin, 1 );
    self menu_item( "operator", "Portnova", &act_skin, 2 );
    self menu_item( "operator", "Garcia", &act_skin, 3 );
    self menu_item( "operator", "Baker", &act_skin, 4 );
    self menu_item( "operator", "Sims", &act_skin, 5 );
    self menu_item( "operator", "Hunter", &act_skin, 6 );
    self menu_item( "operator", "Vargas", &act_skin, 7 );
    self menu_item( "operator", "Stone", &act_skin, 8 );
    self menu_item( "operator", "Song", &act_skin, 9 );
    self menu_item( "operator", "Powers", &act_skin, 10 );
    self menu_item( "operator", "Baker (2)", &act_skin, 11 );
    self menu_item( "operator", "Zeyna", &act_skin, 12 );
    self menu_item( "operator", "Wolf", &act_skin, 13 );
    self menu_item( "operator", "Beck", &act_skin, 14 );
    self menu_item( "operator", "Knight", &act_skin, 15 );
    self menu_item( "operator", "Antonov", &act_skin, 16 );
    self menu_item( "operator", "Park", &act_skin, 17 );
    self menu_item( "operator", "Stitch", &act_skin, 18 );
    self menu_item( "operator", "Bulldozer", &act_skin, 19 );
    self menu_item( "operator", "CDL 1", &act_skin, 20 );
    self menu_item( "operator", "CDL 2", &act_skin, 21 );
    self menu_item( "operator", "Woods", &act_skin, 22 );
    self menu_item( "operator", "Rivas", &act_skin, 23 );
    self menu_item( "operator", "Naga", &act_skin, 24 );
    self menu_item( "operator", "Maxis", &act_skin, 25 );
    self menu_item( "operator", "John Doe", &act_skin, 26 );
    self menu_item( "operator", "Jane Doe", &act_skin, 27 );
    self menu_item( "operator", "Base (M)", &act_skin, 28 );
    self menu_item( "operator", "Base (F)", &act_skin, 29 );
    self menu_item( "operator", "Wraith", &act_skin, 30 );
    self menu_item( "operator", "Baker (3)", &act_skin, 31 );
    self menu_item( "operator", "Park (2)", &act_skin, 32 );
    self menu_item( "operator", "Price", &act_skin, 33 );
    self menu_item( "operator", "John McClane", &act_skin, 34 );
    self menu_item( "operator", "Rambo", &act_skin, 35 );
    self menu_item( "operator", "Weaver", &act_skin, 36 );
    self menu_item( "operator", "Jackal", &act_skin, 37 );
    self menu_item( "operator", "Salah", &act_skin, 38 );
    self menu_item( "operator", "Kitsune", &act_skin, 39 );
    self menu_item( "operator", "Stryker", &act_skin, 40 );
    self menu_item( "operator", "Arthur Kingsley", &act_skin, 41 );
    self menu_item( "operator", "Hudson", &act_skin, 42 );
    self menu_item( "operator", "Mason", &act_skin, 43 );
    self menu_item( "operator", "Scream", &act_skin, 44 );
    self menu_item( "operator", "Fuze", &act_skin, 45 );
    self menu_item( "operator", "Zombie (F)", &act_skin, 46 );
    self menu_item( "operator", "Zombie (M)", &act_skin, 47 );
    self menu_item( "operator", "Lazar", &act_skin, 48 );

    // ── Outfit — by id (per-operator outfits) ─────────────────────────────────
    self menu_add( "outfit", "Outfit", "start_menu", 1 );
    for ( oi = 0; oi < 24; oi++ )
        self menu_item( "outfit", "Outfit " + oi, &act_outfit, oi );

    // ── Map ──────────────────────────────────────────────────────────────────
    // Every label is "<in-game display name>  [<map name>]". Names audited 2026-09-12
    // against the dump's map table (36 mp_* maptableentry assets, no 37th), the CoD
    // wiki's per-map `console` field, and per-map asset fingerprints; the table with
    // the provenance is docs/reference/bocw-maps.md. The labels this file carried
    // before were guesses and several were wrong (mp_dune is Collateral, not Rush;
    // mp_village_rm is Standoff; mp_cliffhanger is Yamantau; mp_kgb is Checkmate).
    // Selecting any map (or a gametype, below) opens the stage/now page - see "── Map"
    // in the actions: "Stage for lobby - next match" or "Switch NOW".
    self menu_add( "map", "Map", "start_menu", 1 );
    // (ON) = SESSION, the default: the lobby follows the switch. Off = the old Atian
    // load-time carry. Seeded from the dvar so the marker is right on first open.
    // Only "Switch NOW" honours it; a stage is the session route by definition.
    it = self menu_item( "map", "Session switch (lobby follows)", &act_map_method );
    it.activated = cfg_map_method();
    // How long "Switch NOW" waits for #"switchmap_preload_finished" before committing.
    // 25 = stock ZM's cap and the measured-working form, but only the FIRST switch of a
    // session gets the notify - later ones sit the whole 25s (klaze, 2026-09-13: "works,
    // long delay"). "none" is stock CAMPAIGN's immediate form: one network frame, then
    // switch (cp_common/load.gsc:412-414). Untested in MP - flip it and look.
    self menu_item( "map", "Switch wait: 25s - proven", &act_switch_wait, 25, undefined, #"gf_switch_wait", 25 );
    self menu_item( "map", "Switch wait: 5s", &act_switch_wait, 5, undefined, #"gf_switch_wait", 5 );
    self menu_item( "map", "Switch wait: none - cp form, untested", &act_switch_wait, 0, undefined, #"gf_switch_wait", 0 );
    // (Zoo lives in the 6v6 folder like every other map - the old root "Zoo - verified"
    // shortcut was removed 2026-09-13 at klaze's request.)
    self menu_add( "map_6v6", "6v6 maps", "map", 1 );
    self menu_add( "map_gf", "Gunfight maps", "map", 1 );
    self menu_add( "map_large", "12v12 layouts - TDM 10v10", "map", 1 );
    self menu_add( "map_ft", "Fireteam maps - untested", "map", 1 );

    // 6v6 maps. The three large maps are ONE file each whose script picks the 12v12 or
    // the Strike boundary from the g_gametype string at level_init (bocw-maps.md):
    // under gunfight, mp_black_sea and mp_dune come up as their STRIKE layouts and
    // mp_tundra comes up as the FULL 12v12 map ("gunfight" is not in Crossroads' 6v6
    // token list). The labels say which layout the switch will actually produce.
    self menu_item( "map_6v6", "Amerika  [mp_amerika]", &act_map, "mp_amerika" );
    self menu_item( "map_6v6", "Apocalypse  [mp_apocalypse]", &act_map, "mp_apocalypse" );
    self menu_item( "map_6v6", "Armada Strike  [mp_black_sea]", &act_map, "mp_black_sea" );
    self menu_item( "map_6v6", "Cartel  [mp_cartel]", &act_map, "mp_cartel" );
    self menu_item( "map_6v6", "Checkmate  [mp_kgb]", &act_map, "mp_kgb" );
    self menu_item( "map_6v6", "Collateral Strike  [mp_dune]", &act_map, "mp_dune" );
    self menu_item( "map_6v6", "Crossroads - full 12v12 layout  [mp_tundra]", &act_map, "mp_tundra" );
    self menu_item( "map_6v6", "Deprogram  [mp_firebase]", &act_map, "mp_firebase" );
    self menu_item( "map_6v6", "Diesel  [mp_sm_gas_station]", &act_map, "mp_sm_gas_station" );
    self menu_item( "map_6v6", "Drive-In  [mp_drivein_rm]", &act_map, "mp_drivein_rm" );
    self menu_item( "map_6v6", "Echelon  [mp_echelon]", &act_map, "mp_echelon" );
    self menu_item( "map_6v6", "Express  [mp_express_rm]", &act_map, "mp_express_rm" );
    self menu_item( "map_6v6", "Garrison  [mp_tank]", &act_map, "mp_tank" );
    self menu_item( "map_6v6", "Hijacked  [mp_hijacked_rm]", &act_map, "mp_hijacked_rm" );
    self menu_item( "map_6v6", "Jungle  [mp_jungle_rm]", &act_map, "mp_jungle_rm" );
    self menu_item( "map_6v6", "Miami  [mp_miami]", &act_map, "mp_miami" );
    self menu_item( "map_6v6", "Miami Strike  [mp_miami_strike]", &act_map, "mp_miami_strike" );
    self menu_item( "map_6v6", "Moscow  [mp_moscow]", &act_map, "mp_moscow" );
    self menu_item( "map_6v6", "Nuketown '84  [mp_nuketown6]", &act_map, "mp_nuketown6" );
    self menu_item( "map_6v6", "Raid  [mp_raid_rm]", &act_map, "mp_raid_rm" );
    self menu_item( "map_6v6", "Rush  [mp_paintball_rm]", &act_map, "mp_paintball_rm" );
    self menu_item( "map_6v6", "Satellite  [mp_satellite]", &act_map, "mp_satellite" );
    self menu_item( "map_6v6", "Slums  [mp_slums_rm]", &act_map, "mp_slums_rm" );
    self menu_item( "map_6v6", "Standoff  [mp_village_rm]", &act_map, "mp_village_rm" );
    self menu_item( "map_6v6", "The Pines  [mp_mall]", &act_map, "mp_mall" );
    self menu_item( "map_6v6", "WMD  [mp_russianbase_rm]", &act_map, "mp_russianbase_rm" );
    self menu_item( "map_6v6", "Yamantau  [mp_cliffhanger]", &act_map, "mp_cliffhanger" );
    self menu_item( "map_6v6", "Zoo  [mp_zoo_rm]", &act_map, "mp_zoo_rm" );

    // Gunfight / Face Off maps, plus the two the stock Gunfight rotation borrows.
    self menu_item( "map_gf", "Amsterdam  [mp_sm_amsterdam]", &act_map, "mp_sm_amsterdam" );
    self menu_item( "map_gf", "Diesel  [mp_sm_gas_station]", &act_map, "mp_sm_gas_station" );
    self menu_item( "map_gf", "Game Show  [mp_sm_game_show]", &act_map, "mp_sm_game_show" );
    self menu_item( "map_gf", "Gluboko  [mp_sm_vault]", &act_map, "mp_sm_vault" );
    self menu_item( "map_gf", "ICBM  [mp_sm_central]", &act_map, "mp_sm_central" );
    self menu_item( "map_gf", "KGB  [mp_sm_finance]", &act_map, "mp_sm_finance" );
    self menu_item( "map_gf", "Mansion  [mp_sm_market]", &act_map, "mp_sm_market" );
    self menu_item( "map_gf", "Nuketown '84  [mp_nuketown6]", &act_map, "mp_nuketown6" );
    self menu_item( "map_gf", "Showroom  [mp_sm_deptstore]", &act_map, "mp_sm_deptstore" );
    self menu_item( "map_gf", "U-Bahn  [mp_sm_berlin_tunnel]", &act_map, "mp_sm_berlin_tunnel" );

    // The full 12v12 layouts of the large maps. Same files as above; the map scripts
    // open the 12v12 boundary only when g_gametype is a 10v10/12v12 string, so these
    // switch the SESSION to map + "tdm10v10" (gametypetableentry teamdeathmatch_10v10
    // exists in the dump). Not Gunfight, and not yet run: the *10v10 strings have only
    // been seen inside matchmade playlists. Crossroads' full layout is what gunfight
    // already gets (above); it is here so all three read the same way.
    self menu_item( "map_large", "Armada 12v12 - TDM 10v10  [mp_black_sea]", &act_map_gt, "mp_black_sea", "tdm10v10" );
    self menu_item( "map_large", "Collateral 12v12 - TDM 10v10  [mp_dune]", &act_map_gt, "mp_dune", "tdm10v10" );
    self menu_item( "map_large", "Crossroads 12v12 - TDM 10v10  [mp_tundra]", &act_map_gt, "mp_tundra", "tdm10v10" );

    // Fireteam / Multi-team maps (40-player, dedicated-server modes). The wz_* scripts
    // link core_common only and fireteam.gsc registers tdm spawn points, so a 6v6 mode
    // is not ruled out by the script layer - but nobody has loaded one this way.
    self menu_item( "map_ft", "Alpine  [wz_ski_slopes]", &act_map, "wz_ski_slopes" );
    self menu_item( "map_ft", "Duga  [wz_duga]", &act_map, "wz_duga" );
    self menu_item( "map_ft", "Golova  [wz_golova]", &act_map, "wz_golova" );
    self menu_item( "map_ft", "Ruka  [wz_forest]", &act_map, "wz_forest" );
    self menu_item( "map_ft", "Sanatorium  [wz_sanatorium]", &act_map, "wz_sanatorium" );

    // ── Gametype — the SESSION switch with the gametype swapped and the map kept ─
    // The Atian source's dead func_set_gametype(), wired in. Strings are the gametype
    // SCRIPT names (scripts/mp_common/gametypes/<name>.gsc). Workflow this enables:
    // create the lobby under TDM (any map is selectable there, 12 slots), start, then
    // switch to gunfight here; the map and the session stay. The Gunfight fixes in
    // mod_apply are gated on the gametype, so the menu is safe to link into TDM.
    self menu_add( "gametype", "Gametype", "start_menu", 1 );
    // Auto-switch to Gunfight on match start when this match is not Gunfight (mod_autoswitch).
    // ON survives to the next match; set it, restart, and injecting lands you in Gunfight.
    self menu_item( "gametype", "Auto-Gunfight on inject: ON", &act_autoswitch, 1, undefined, #"gf_autoswitch", 1 );
    self menu_item( "gametype", "Auto-Gunfight on inject: OFF", &act_autoswitch, 0, undefined, #"gf_autoswitch", 0 );
    self menu_item( "gametype", "Gunfight", &act_gametype, "gunfight" );
    self menu_item( "gametype", "Gunfight 3v3", &act_gametype, "gunfight_3v3" );
    self menu_item( "gametype", "TDM", &act_gametype, "tdm" );
    self menu_item( "gametype", "Free-for-all", &act_gametype, "dm" );
    self menu_item( "gametype", "Domination", &act_gametype, "dom" );
    self menu_item( "gametype", "Hardpoint", &act_gametype, "koth" );
    self menu_item( "gametype", "Search & Destroy", &act_gametype, "sd" );
    self menu_item( "gametype", "Kill Confirmed", &act_gametype, "conf" );
    self menu_item( "gametype", "Control", &act_gametype, "control" );
    self menu_item( "gametype", "Capture the Flag", &act_gametype, "ctf" );
    self menu_item( "gametype", "Demolition", &act_gametype, "dem" );
    self menu_item( "gametype", "Infected", &act_gametype, "infect" );
    self menu_item( "gametype", "Gun Game", &act_gametype, "gun" );
    self menu_item( "gametype", "Prop Hunt", &act_gametype, "prop" );
    self menu_item( "gametype", "Sticks and Stones", &act_gametype, "sas" );
    self menu_item( "gametype", "One in the Chamber", &act_gametype, "oic" );
    self menu_item( "gametype", "Dropkick", &act_gametype, "dropkick" );
    self menu_item( "gametype", "VIP Escort", &act_gametype, "vip" );
    self menu_item( "gametype", "Team War", &act_gametype, "war" );
    self menu_item( "gametype", "Cranked", &act_gametype, "cranked" );
}

// ═════════════════════════════════════════════════════════════════════════════
// ACTIONS
// ═════════════════════════════════════════════════════════════════════════════

// ── Teams ────────────────────────────────────────────────────────────────────

function private act_spec_slots( item, value )
{
    cfg_seti( #"gf_spec_slots", value );
    gts_set( #"maxplayers", maxplayers_value( clamp_team_size( cfg_team_size() ) ) );
    self menu_say( "^2spectator slots " + value + " - maxplayers now " + census_v( getgametypesetting( #"maxplayers" ) ) + " (budget " + getdvarint( #"com_maxclients", 0 ) + ")" );
    return true;
}

function private act_team_size( item, per_side )
{
    clamped = clamp_team_size( per_side );
    cfg_seti( #"gf_team_size", clamped );
    gts_set( #"maxplayers", maxplayers_value( clamped ) );

    if ( clamped < per_side )
    {
        self menu_say( "^3team size " + clamped + "v" + clamped + " - lobby budget is " + getdvarint( #"com_maxclients", 0 ) + " clients" );
    }
    else
    {
        self menu_say( "^2team size " + clamped + "v" + clamped );
    }

    return true;
}

function private act_fill_bots( item )
{
    self thread fill_bots();
    return true;
}

function private fill_bots()
{
    self endon( #"disconnect" );

    target = cfg_team_size();
    added = 0;

    teams = [];
    teams[ 0 ] = #"allies";
    teams[ 1 ] = #"axis";

    foreach ( team in teams )
    {
        need = target - getplayers( team ).size;

        for ( i = 0; i < need; i++ )
        {
            b = bot::add_bot( team );

            if ( !isdefined( b ) )
            {
                self menu_say( "^1bot refused at " + getplayers( #"allies" ).size + "v" + getplayers( #"axis" ).size + " - clients " + getplayers().size + " / budget " + getdvarint( #"com_maxclients", 0 ) + " / maxplayers " + census_v( getgametypesetting( #"maxplayers" ) ) );
                return;
            }

            added++;
            waitframe( 1 );
        }
    }

    self menu_say( "^2" + added + " bots added: " + getplayers( #"allies" ).size + "v" + getplayers( #"axis" ).size );
}

function private act_remove_bots( item )
{
    bot::remove_bots( #"allies" );
    bot::remove_bots( #"axis" );
    self menu_say( "^2bots removed" );
    return true;
}

// ═════════════════════════════════════════════════════════════════════════════
// BOTS — add / remove one, even-up, difficulty (stock levels + a CUSTOM struct), passive
// ═════════════════════════════════════════════════════════════════════════════
// docs/notes/bots.md is the full note. The short version, all from the dump:
//
//   * A bot's difficulty is the STRUCT on bot.bot.difficulty. Stock installs it in
//     bot_difficulty::assign() (bot_difficulty.gsc:34): read the per-team gametype setting
//     bot_difficulty_<team> (0 recruit .. 3 veteran; the custom-games "Bot Difficulty" row -
//     hash cracked exactly 2026-09-12), getscriptbundle() the matching
//     scriptbundle/botdifficulty/t9_bot_difficulty_mp_*.json, store it, fire the
//     #"bot_difficulty_assigned" callback. assign() runs on join (on_joined_team), on the
//     round-boundary reconnect (bot.gsc:239) and whenever we call it ourselves.
//   * EVERY consumer reads the struct's fields with a default and nothing else
//     (bot_weapons.gsc:2970-3288, bot_actions.gsc:362/431, bot_stance.gsc:53/111,
//     bot.gsc:397) - so a struct we build ourselves IS a difficulty. That is the custom level.
//   * The one post-assign side effect is bot.gsc:395: the flag var_ea800f8 picks the look
//     scalar handed to function_3ca49c4e (0.8 flag on / 0.1 off; init_bot uses 1). Our hook
//     re-issues it from our own flag so registration order between systems cannot matter.
//   * The fields (cracked names in quotes, else the var_ hash; stock recruit/regular/hardened/veteran):
//       "shoothitchance"       var_d20ff29c  40/50/60/90   % a fire cycle is aimed on-target (bot_weapons:3243)
//       "shootheadchance"      var_fa680c5e  0/3/10/20     % an on-target cycle aims at j_head (:3288)
//       "shootdelay"           var_d70788cb  1.4/1.1/.7/.3 s of aim before the fire window (:3158)
//       shoottime                            .3/.4/.5/.7   s the fire window lasts (:3124)
//       "hitchancefalloffmin"  var_65a25108  1             hit-chance scale at min range (:3253)
//       "hitchancefalloffmax"  var_e0e4be1b  1/.8/.66/.5   hit-chance scale at max range (:3254)
//       (hipfire scale)        var_363a4bcd  .5/.5/.6/.7   hit-chance scale when not ADS (:3261)
//       "singleshotdelay"      var_b489efb7  .8/.6/.4/.15  s between semi-auto taps (:2970)
//       burstdelay                           1.2/.9/.7/.25 s between bursts (:2974)
//       "allowmoveandshoot"    var_33be320f  0/0/1/1       off = hold position with a target in view (:3109)
//       (fast look)            var_ea800f8   0/0/1/1       -> function_3ca49c4e( 0.8 : 0.1 ) (bot.gsc:397)
//       allowsprint/allowmelee/allowprone/allowslide/allowcrouch   veteran has all five
//
// ⚠ NEVER RUN. The setting write is the same setgametypesetting() every other knob uses;
//   bot_difficulty::assign() is stock's own re-read; the custom struct is the untested part.

// -1 lobby / 0-3 stock / 4 custom -> the stock LEVEL to write. Custom rides on veteran so a
// bot that joins before our hook lands is the strongest stock bot, not the weakest.
function private bot_diff_stock( d )
{
    if ( d == 4 )
        return 3;
    return d;
}

function private bot_diff_label( d )
{
    switch ( d )
    {
        case 0:  return "recruit";
        case 1:  return "regular";
        case 2:  return "hardened";
        case 3:  return "veteran";
        case 4:  return "CUSTOM";
        default: return "lobby";
    }
}

function private bot_diff_for_team( team )
{
    if ( isdefined( team ) && team == #"axis" )
        return cfg_bot_diff_axis();
    return cfg_bot_diff_allies();
}

// The look scalar behind the fast-look flag. 0.1 / 0.8 are the two values stock hands
// function_3ca49c4e after an assign (bot.gsc:399/403); 1 is init_bot's (bot.gsc:975).
// Nothing outside that set is ever passed.
function private bot_aim_scalar()
{
    f = cfg_bot_fastaim();
    if ( f <= 0 )
        return 0.1;
    if ( f == 1 )
        return 0.8;
    return 1;
}

// Our difficulty. Same field set as the stock bundles, values from the gf_bot_* dvars,
// percent/ms knobs scaled to the fractions the readers expect. A fresh struct per call
// (they are shared read-only, so handing every bot the same one would also be fine).
function private bot_custom_profile()
{
    d = spawnstruct();
    d.name = "gf_custom";
    d.var_d20ff29c = cfg_bot_hit();            // shoothitchance %
    d.var_fa680c5e = cfg_bot_head();           // shootheadchance %
    d.var_d70788cb = cfg_bot_react() / 1000;   // shootdelay s
    d.shoottime    = cfg_bot_fire() / 1000;    // s
    d.var_65a25108 = 1;                        // hitchancefalloffmin (stock: always 1)
    d.var_e0e4be1b = cfg_bot_far() / 100;      // hitchancefalloffmax
    d.var_363a4bcd = cfg_bot_hip() / 100;      // hipfire scale
    d.var_b489efb7 = cfg_bot_semi() / 1000;    // singleshotdelay s
    d.burstdelay   = cfg_bot_burst() / 1000;   // s
    d.var_33be320f = cfg_bot_moveshoot();      // allowmoveandshoot
    d.var_ea800f8  = ( cfg_bot_fastaim() >= 1 ) ? 1 : 0;
    d.allowsprint  = cfg_bot_sprint();
    d.allowmelee   = cfg_bot_melee();
    d.allowprone   = cfg_bot_prone();
    d.allowslide   = cfg_bot_slide();
    d.allowcrouch  = cfg_bot_crouch();
    return d;
}

// self = the bot. Runs after every stock install (registered in __init__), so this is
// the one place the custom struct and the passive flag are applied: join, round
// boundary, our re-assign - all of them come through here.
function private bot_on_difficulty_assigned()
{
    if ( !isbot( self ) || !isdefined( self.bot ) )
        return;

    // Stock .ignoreall (rat.gsc:48, bot_devgui "Ignore All"): bot_action::function_a43bc7e2
    // and bot_orders:51 skip the engage decision while it is set. 0 is the stock default.
    self.ignoreall = cfg_bot_passive();

    team = isdefined( self.pers[ #"team" ] ) ? self.pers[ #"team" ] : self.team;

    if ( bot_diff_for_team( team ) != 4 )
        return;

    self.bot.difficulty = bot_custom_profile();
    self function_3ca49c4e( bot_aim_scalar() );
}

// Write the per-team settings (sentinel -1 = leave the lobby's row alone) and re-run
// stock's assign on every live bot so a pick lands NOW, not at the next join. Called
// from mod_bots each round and from every bot action in the menu.
function private bot_diff_apply()
{
    da = cfg_bot_diff_allies();
    dx = cfg_bot_diff_axis();

    if ( da >= 0 )
        gts_set( #"bot_difficulty_allies", bot_diff_stock( da ) );
    if ( dx >= 0 )
        gts_set( #"bot_difficulty_axis", bot_diff_stock( dx ) );
    // bot_difficulty.gsc:63 reads bot_difficulty_vs_bots INSTEAD of the per-team pair when the
    // lobby's vs-bots flag (hash_c6a2e6c3e86125a, uncracked) is set. Mirror an agreed pick
    // there too so that mode follows; a split pick has no single value to mirror.
    if ( da >= 0 && da == dx )
        gts_set( #"bot_difficulty_vs_bots", bot_diff_stock( da ) );

    n = 0;

    foreach ( p in getplayers() )
    {
        // .bot undefined = a bot the round has not re-inited yet; its own connect path
        // will assign (bot.gsc:239) and our hook fires from there.
        if ( !isbot( p ) || !isdefined( p.bot ) )
            continue;

        p bot_difficulty::assign();
        n++;
    }

    return n;
}

function private mod_bots()
{
    bot_diff_apply();
}

function private bots_of( team )
{
    out = [];

    foreach ( p in getplayers( team ) )
    {
        if ( isbot( p ) )
            out[ out.size ] = p;
    }

    return out;
}

function private humans_on( team )
{
    n = 0;

    foreach ( p in getplayers( team ) )
    {
        if ( !isbot( p ) )
            n++;
    }

    return n;
}

function private bot_other_team( team )
{
    return ( team == #"allies" ) ? #"axis" : #"allies";
}

// "auto": the smaller side; tie -> the side opposite the host, so a solo host's first
// add is an opponent. A spectating host has no side; tie then goes to axis.
function private bot_auto_team()
{
    a = getplayers( #"allies" ).size;
    x = getplayers( #"axis" ).size;

    if ( a < x )
        return #"allies";
    if ( x < a )
        return #"axis";

    mine = self.pers[ #"team" ];
    if ( isdefined( mine ) && mine == #"axis" )
        return #"allies";
    return #"axis";
}

function private bot_sides()
{
    return getplayers( #"allies" ).size + "v" + getplayers( #"axis" ).size;
}

function private bot_team_name( team )
{
    return ( team == #"axis" ) ? "axis" : "allies";
}

// One bot. The same bot::add_bot( team ) fill_bots uses (C7-proven); undefined back means
// addtestclient refused, which is the client budget (com_maxclients), not a team cap.
function private add_one_bot( team )
{
    if ( !isdefined( team ) )
        team = bot_auto_team();

    b = bot::add_bot( team );

    if ( !isdefined( b ) )
    {
        self menu_say( "^1bot refused at " + bot_sides() + " - client budget " + getdvarint( #"com_maxclients", 0 ) + " hit" );
        return;
    }

    waitframe( 1 );
    self menu_say( "^2bot added to " + bot_team_name( team ) + ": " + bot_sides() );
}

// One bot off. Auto = the bigger side; tie -> the host's own side, so the opponents
// stay. bot::remove_bot is stock's own drop (isbot + not player-controlled -> botdropclient).
function private remove_one_bot( team )
{
    if ( !isdefined( team ) )
    {
        a = getplayers( #"allies" ).size;
        x = getplayers( #"axis" ).size;

        if ( a > x )
            team = #"allies";
        else if ( x > a )
            team = #"axis";
        else
        {
            mine = self.pers[ #"team" ];
            team = ( isdefined( mine ) && mine == #"axis" ) ? #"axis" : #"allies";
        }
    }

    bots = bots_of( team );

    if ( bots.size == 0 )
    {
        team = bot_other_team( team );
        bots = bots_of( team );
    }

    if ( bots.size == 0 )
    {
        self menu_say( "^3no bots to remove" );
        return;
    }

    bot::remove_bot( bots[ bots.size - 1 ] );
    waitframe( 1 );
    self menu_say( "^2bot removed from " + bot_team_name( team ) + ": " + bot_sides() );
}

// The fewest bots that make the sides equal. Planned from ONE read of the counts so a
// drop that takes a frame to leave getplayers() cannot be counted twice: the side with
// more humans sets the size, each side then wants (size - its humans) bots - surplus off
// first, then adds. 3 humans as 2v1 -> one bot -> 2v2. 4v2 with two allied bots -> both
// off -> 2v2. Refusals stop at the first, like fill_bots.
function private even_up_bots()
{
    self endon( #"disconnect" );

    teams = [];
    teams[ 0 ] = #"allies";
    teams[ 1 ] = #"axis";

    ha = humans_on( #"allies" );
    hx = humans_on( #"axis" );
    size = ( ha > hx ) ? ha : hx;

    if ( size == 0 )
    {
        self menu_say( "^3even up: no humans on a team yet" );
        return;
    }

    want = [];
    want[ #"allies" ] = size - ha;
    want[ #"axis" ] = size - hx;

    added = 0;
    removed = 0;

    foreach ( team in teams )
    {
        bots = bots_of( team );

        for ( i = bots.size - 1; i >= want[ team ]; i-- )
        {
            bot::remove_bot( bots[ i ] );
            removed++;
        }

        for ( i = bots.size; i < want[ team ]; i++ )
        {
            b = bot::add_bot( team );

            if ( !isdefined( b ) )
            {
                self menu_say( "^1bot refused at " + bot_sides() + " - client budget hit; " + added + " added, " + removed + " removed" );
                return;
            }

            added++;
            waitframe( 1 );
        }
    }

    waitframe( 1 );

    if ( added == 0 && removed == 0 )
        self menu_say( "^2teams already even: " + bot_sides() );
    else
        self menu_say( "^2evened up: " + added + " added, " + removed + " removed -> " + bot_sides() );
}

function private bot_passive_apply()
{
    n = 0;

    foreach ( p in getplayers() )
    {
        if ( !isbot( p ) )
            continue;

        p.ignoreall = cfg_bot_passive();
        n++;
    }

    return n;
}

// ── Bots menu actions ───────────────────────────────────────────────────────

// which: 0 auto / 1 allies / 2 axis
function private act_bot_add( item, which )
{
    team = undefined;
    if ( which == 1 )
        team = #"allies";
    else if ( which == 2 )
        team = #"axis";

    self thread add_one_bot( team );
    return true;
}

function private act_bot_remove( item )
{
    self thread remove_one_bot( undefined );
    return true;
}

function private act_bot_even( item )
{
    self thread even_up_bots();
    return true;
}

function private act_bot_passive( item )
{
    cfg_seti( #"gf_bot_passive", cfg_bot_passive() ? 0 : 1 );
    n = bot_passive_apply();
    self menu_say( cfg_bot_passive() ? ( "^2bots passive - " + n + " ignoring everyone" ) : ( "^2bots active again - " + n + " re-armed" ) );
    return true;
}

// Entering the difficulty page reads the LIVE settings back, so the host sees what the
// lobby (or a previous pick) actually holds, independent of our dvars.
function private bot_diff_enter( menu )
{
    a = getgametypesetting( #"bot_difficulty_allies" );
    x = getgametypesetting( #"bot_difficulty_axis" );
    self menu_say( "^7live setting: allies " + bot_diff_label( isdefined( a ) ? int( a ) : -1 ) + " ^8| ^7axis " + bot_diff_label( isdefined( x ) ? int( x ) : -1 ) + " ^8| ^7bots " + bots_of( #"allies" ).size + "v" + bots_of( #"axis" ).size );
}

function private act_bot_diff( item, d )
{
    cfg_seti( #"gf_bot_diff_allies", d );
    cfg_seti( #"gf_bot_diff_axis", d );
    n = bot_diff_apply();
    self menu_say( "^2bots: " + bot_diff_label( d ) + " both sides - " + n + " re-assigned now" );
    return true;
}

function private act_bot_diff_team( item, team_str, d )
{
    if ( team_str == "axis" )
        cfg_seti( #"gf_bot_diff_axis", d );
    else
        cfg_seti( #"gf_bot_diff_allies", d );

    n = bot_diff_apply();
    self menu_say( "^2bots: " + team_str + " " + bot_diff_label( d ) + " - " + n + " re-assigned now" );
    return true;
}

// ── Custom tuning page ──────────────────────────────────────────────────────
// One row per knob, label + live value, SELECT steps to the next value in the ring and
// re-applies. The ring is the whole choice set, so the page never needs more rows than
// knobs - the 3-row window scrolls it.

function private ring( a, b, c, d, e, f, g, h, i )
{
    r = [];
    if ( isdefined( a ) ) r[ r.size ] = a;
    if ( isdefined( b ) ) r[ r.size ] = b;
    if ( isdefined( c ) ) r[ r.size ] = c;
    if ( isdefined( d ) ) r[ r.size ] = d;
    if ( isdefined( e ) ) r[ r.size ] = e;
    if ( isdefined( f ) ) r[ r.size ] = f;
    if ( isdefined( g ) ) r[ r.size ] = g;
    if ( isdefined( h ) ) r[ r.size ] = h;
    if ( isdefined( i ) ) r[ r.size ] = i;
    return r;
}

function private bot_knob( idx, label, values, unit, labels = undefined )
{
    k = spawnstruct();
    k.idx = idx;   // packed-field index into gf_bot (dvar-pool budget), was a dvar hash
    k.label = label;
    k.values = values;
    k.unit = unit;
    k.labels = labels;   // when set, printed instead of value+unit (index-aligned with values)
    return k;
}

function private bot_knobs()
{
    onoff = ring( "OFF", "ON" );
    ks = [];
    ks[ ks.size ] = bot_knob( 0,                 "Hit chance",          ring( 10, 25, 40, 50, 60, 75, 90, 100 ), "%" );
    ks[ ks.size ] = bot_knob( 1,                "Headshot chance",     ring( 0, 3, 10, 20, 35, 50, 75, 100 ), "%" );
    ks[ ks.size ] = bot_knob( 2,               "Aim delay",           ring( 0, 100, 200, 300, 500, 700, 1100, 1400, 2000 ), "ms" );
    ks[ ks.size ] = bot_knob( 3,                "Fire window",         ring( 300, 400, 500, 700, 1000, 1500, 2000 ), "ms" );
    ks[ ks.size ] = bot_knob( 4,                 "Hipfire accuracy",    ring( 25, 50, 60, 70, 85, 100 ), "%" );
    ks[ ks.size ] = bot_knob( 5,                 "Long-range accuracy", ring( 25, 50, 66, 80, 90, 100 ), "%" );
    ks[ ks.size ] = bot_knob( 6,                "Semi-auto tap delay", ring( 50, 100, 150, 250, 400, 600, 800 ), "ms" );
    ks[ ks.size ] = bot_knob( 7,               "Burst delay",         ring( 50, 100, 250, 500, 700, 900, 1200 ), "ms" );
    ks[ ks.size ] = bot_knob( 8,           "Move while shooting", ring( 0, 1 ), "", onoff );
    ks[ ks.size ] = bot_knob( 9,             "Look speed",          ring( 0, 1, 2 ), "", ring( "slow - recruit", "fast - veteran", "max" ) );
    ks[ ks.size ] = bot_knob( 10,             "Sprint",              ring( 0, 1 ), "", onoff );
    ks[ ks.size ] = bot_knob( 11,              "Melee",               ring( 0, 1 ), "", onoff );
    ks[ ks.size ] = bot_knob( 12,              "Prone",               ring( 0, 1 ), "", onoff );
    ks[ ks.size ] = bot_knob( 13,              "Slide",               ring( 0, 1 ), "", onoff );
    ks[ ks.size ] = bot_knob( 14,             "Crouch",              ring( 0, 1 ), "", onoff );
    return ks;
}

function private ring_index( values, v )
{
    for ( i = 0; i < values.size; i++ )
    {
        if ( values[ i ] == v )
            return i;
    }

    return -1;
}

function private bot_knob_text( k )
{
    v = bot_num( k.idx, k.values[ 0 ] );

    if ( isdefined( k.labels ) )
    {
        i = ring_index( k.values, v );
        if ( i >= 0 )
            return k.labels[ i ];
    }

    return "" + v + k.unit;
}

function private bot_custom_enter( menu )
{
    self menu_clear_items( "botcustom" );
    self menu_item( "botcustom", "Preset: Veteran+ (custom default)", &act_bot_preset, 0 );
    self menu_item( "botcustom", "Preset: Godlike", &act_bot_preset, 1 );
    self menu_item( "botcustom", "Preset: stock Veteran copy", &act_bot_preset, 2 );
    self menu_item( "botcustom", "Preset: Potato", &act_bot_preset, 3 );

    ks = bot_knobs();

    for ( i = 0; i < ks.size; i++ )
        self menu_item( "botcustom", ks[ i ].label + ": ^3" + bot_knob_text( ks[ i ] ), &act_bot_cycle, i );
}

// Rebuild the page's rows (their labels carry the values) without losing the cursor.
function private bot_custom_refresh()
{
    menu = self menu_current();

    if ( !isdefined( menu ) || menu.id != "botcustom" )
        return;

    at = menu.cursor;
    self bot_custom_enter( menu );
    menu.cursor = at;
}

function private act_bot_cycle( item, ki )
{
    ks = bot_knobs();
    k = ks[ ki ];
    cur = bot_num( k.idx, k.values[ 0 ] );
    next = ring_index( k.values, cur ) + 1;

    if ( next >= k.values.size )
        next = 0;

    bot_set_field( k.idx, k.values[ next ] );
    n = bot_diff_apply();
    self bot_custom_refresh();
    self menu_say( "^2" + k.label + " " + bot_knob_text( k ) + " - " + n + " bots re-assigned" );
    return true;
}

// id: 0 Veteran+ (the dvar defaults) / 1 Godlike / 2 stock veteran, as a copy to edit
// from / 3 Potato. A preset also selects CUSTOM on both sides - picking one and not
// having it apply would be the surprise.
function private act_bot_preset( item, id )
{
    hit = 100; head = 50; react = 100; fire = 1000; hip = 100; far = 90; semi = 100; burst = 100;
    moveshoot = 1; fastaim = 1; sprint = 1; melee = 1; prone = 1; slide = 1; crouch = 1;

    if ( id == 1 )
    {
        head = 100; react = 0; fire = 2000; far = 100; semi = 50; burst = 50; fastaim = 2;
    }
    else if ( id == 2 )
    {
        hit = 90; head = 20; react = 300; fire = 700; hip = 70; far = 50; semi = 150; burst = 250;
    }
    else if ( id == 3 )
    {
        hit = 10; head = 0; react = 2000; fire = 300; hip = 25; far = 25; semi = 800; burst = 1200;
        moveshoot = 0; fastaim = 0; sprint = 0; melee = 0; prone = 0; slide = 0; crouch = 0;
    }

    // one packed string, same field order as bot_num (dvar-pool budget)
    cfg_seti( #"gf_bot", hit + "," + head + "," + react + "," + fire + "," + hip + "," + far + "," + semi + "," + burst );
    cfg_seti( #"gf_bot2", moveshoot + "," + fastaim + "," + sprint + "," + melee + "," + prone + "," + slide + "," + crouch );
    cfg_seti( #"gf_bot_diff_allies", 4 );
    cfg_seti( #"gf_bot_diff_axis", 4 );

    n = bot_diff_apply();
    self bot_custom_refresh();

    names = ring( "Veteran+", "Godlike", "stock Veteran copy", "Potato" );
    self menu_say( "^2custom preset " + names[ id ] + " - CUSTOM on both sides, " + n + " bots re-assigned" );
    return true;
}

// ── Players ──────────────────────────────────────────────────────────────────

function private players_enter( menu )
{
    self menu_clear_items( "players" );

    // Humans first, then bots (same verbs - handy for a solo test), the host tagged so
    // his own row is obvious.
    for ( pass = 0; pass < 2; pass++ )
    {
        foreach ( player in getplayers() )
        {
            bot = isbot( player ) ? 1 : 0;

            if ( bot != pass )
                continue;

            tag = team_tag( player );

            if ( bot )
                tag = "bot " + tag;
            else if ( player ishost() )
                tag = "host " + tag;

            self menu_item( "players", player.name + "  ^0" + tag, &act_player_page, player );
        }
    }
}

// Rebuild the list in place while it is open: same rows as players_enter, but the cursor
// stays on the player it was on (found again by entity), or is clamped if that player
// left - a join or leave never yanks the selection to the top.
function private players_refresh()
{
    menu = self.gfmenu.menus[ "players" ];

    if ( !isdefined( menu ) )
        return;

    keep = undefined;
    cursor = menu.cursor;

    if ( cursor >= 0 && cursor < menu.items.size && isdefined( menu.items[ cursor ] ) )
        keep = menu.items[ cursor ].data1;          // the row's player; undefined once gone

    self players_enter( menu );                      // clears + rebuilds, cursor -> 0

    if ( isdefined( keep ) )
    {
        for ( i = 0; i < menu.items.size; i++ )
        {
            if ( isdefined( menu.items[ i ].data1 ) && menu.items[ i ].data1 == keep )
            {
                menu.cursor = i;
                return;
            }
        }
    }

    if ( menu.items.size > 0 )
        menu.cursor = int( min( cursor, menu.items.size - 1 ) );
}

function private team_tag( player )
{
    t = player.pers[ #"team" ];

    if ( !isdefined( t ) )
    {
        return "?";
    }

    if ( t == #"spectator" )
    {
        return "spec";
    }

    if ( t == #"allies" )
    {
        return "allies";
    }

    if ( t == #"axis" )
    {
        return "axis";
    }

    return "?";
}

// ── Roster publisher (2026-09-15, klaze: "can't we pull client names ... for the app").
// The app cannot READ game state - the bridge is app -> game only, and the dvar store is
// unreadable from outside (hud-and-control-app memory) - but a read-only memory scan of
// the game from outside IS proven safe mid-match (dvar_backend --finddvar: pure
// ReadProcessMemory, no thread, no write). So the mod keeps ONE marked string alive in
// level.gf_roster - the script string heap holds it in plain ASCII while it is referenced -
// and the app's Players panel (tools/gf-control/roster_scan.py) scans the game's private
// writable memory for the marker and parses it. Rebuilt only when the roster CHANGES, so
// the string sits at one address for long stretches and the app's cached re-read hits;
// the tick lets the app prefer the newest of any stale copies the pool has not reused.
// The marker is assembled at runtime ("GFRO" + "STER") so the payload's own string table
// never carries a decoy. Format, one line:
//   GFROSTER|<gettime>|<count>|<name>;<team>;<host|bot|human>;<xuid>|...|END
// ⚠ Built 2026-09-15, never run. Unmeasured: whether the VM keeps the concatenated string
// contiguous and plain in memory (expected - it is what iprintln renders from).
function private roster_publish()
{
    if ( isdefined( level.gf_roster_on ) && level.gf_roster_on )
        return;

    level.gf_roster_on = 1;

    for ( ;; )
    {
        body = roster_build();

        if ( !isdefined( level.gf_roster_body ) || level.gf_roster_body != body )
        {
            level.gf_roster_body = body;
            level.gf_roster = "GFRO" + "STER|" + gettime() + "|" + body + "|END";
        }

        wait 2;
    }
}

// ── GAME->APP config readback (config_scan.py, the app's "Load current") ──────
// The bridge is app->game only and the GSC dvar store cannot be read from outside, so the
// live config is published the roster's way: one marked string kept alive in level.gf_cfgpub,
// swept read-only from memory by tools/gf-control/config_scan.py. The app has no other way
// to know what is actually set - its fields are otherwise just its own launch defaults, and a
// value changed from the in-game menu (or a previous app run) is invisible to it. This echoes
// the RAW packed chunk dvars gf_c0..gf_c8 (a menu pick writes them via cfg_write_chunk, an app
// apply writes them over the bridge - so both show up), plus gf_oob and the two bot-knob packs;
// the app resolves an empty field to its own default exactly as cfg_load does here. Assembled
// at runtime ("GF"+"CFG") so the payload's string table carries no decoy. Refreshed every 2 s;
// the tick lets the newest copy win over a stale one the string pool has not reused.
function private config_publish()
{
    if ( isdefined( level.gf_cfgpub_on ) && level.gf_cfgpub_on )
        return;

    level endon( #"game_ended" );
    level.gf_cfgpub_on = 1;

    for ( ;; )
    {
        s = "GF" + "CFG|" + gettime();

        for ( c = 0; c <= 8; c++ )
            s += "|" + getdvarstring( "gf_c" + c, "" );

        s += "|oob=" + cfg_oob();
        s += "|veh=" + cfg_vehmode() + "," + cfg_veh_lock() + "," + cfg_veh_hp() + "," + cfg_veh_alt();
        s += "|bot=" + getdvarstring( #"gf_bot", "" );
        s += "|bot2=" + getdvarstring( #"gf_bot2", "" );
        s += "|" + "END";
        level.gf_cfgpub = s;
        wait 2;
    }
}

function private roster_build()
{
    players = getplayers();
    s = "" + players.size;

    foreach ( p in players )
    {
        if ( !isdefined( p.name ) )
            continue;

        kind = "human";

        if ( isbot( p ) )
            kind = "bot";
        else if ( p ishost() )
            kind = "host";

        xuid = isbot( p ) ? "" : p getxuid();
        s += "|" + p.name + ";" + team_tag( p ) + ";" + kind + ";" + ( isdefined( xuid ) ? ( "" + xuid ) : "" );
    }

    return s;
}

function private act_player_page( item, player )
{
    if ( !client_ok( player ) )
        return true;

    id = "player_" + player getentitynumber();
    self menu_add( id, player.name, "players", 0 );
    self menu_clear_items( id );
    self client_page_build( id, player );

    return self menu_switch( undefined, id );
}

// ⚠ C11's mechanism, never run in-game. [[ level.autoassign ]]( 0, team ) with
// comingfrommenu = 0 lands in team_assignment.gsc:419, which uses the team verbatim
// with no fullness check - the branch klaze already sees fire when "a spot is open
// on the join". comingfrommenu MUST be 0; 1 skips that branch.
function private act_move( item, player, team )
{
    if ( !isdefined( player ) )
    {
        self menu_say( "^1player left" );
        return true;
    }

    // Harden C11: guard the function-pointer deref so a build without level.autoassign
    // fails with a message instead of a runtime error, and no-op if already on the team.
    if ( !isdefined( level.autoassign ) )
    {
        self menu_say( "^1move unavailable (level.autoassign undefined)" );
        return true;
    }

    name = ( team == #"allies" ) ? "allies" : "axis";

    if ( isdefined( player.team ) && player.team == team )
    {
        self menu_say( "^3" + player.name + " already on " + name );
        return true;
    }

    player [[ level.autoassign ]]( 0, team, undefined );
    self menu_say( "^2" + player.name + " -> " + name );
    return true;
}

function private act_spectate( item, player )
{
    if ( !isdefined( player ) )
    {
        self menu_say( "^1player left" );
        return true;
    }

    if ( !isdefined( level.spectator ) )
    {
        self menu_say( "^1spectate unavailable (level.spectator undefined)" );
        return true;
    }

    player [[ level.spectator ]]();
    self menu_say( "^2" + player.name + " -> spectator" );
    return true;
}

// ── Client control (2026-09-15) — the per-player page. klaze: "a client menu that can
// control connected clients - give god mode, ammo, weapon, etc". Every verb runs on the
// HOST (self) against `player`, so the confirmations land on the host's feed and the
// client just gets the effect. All of it is server-side builtins on the player entity
// (enableinvulnerability, givemaxammo, giveweapon, setclientthirdperson, setmovespeedscale,
// setcamo / setspecialistindex / setcharacteroutfit, takeweapon, kick) - the joiner-safe
// class of docs/notes/game-systems.md §10: the host is the server and owns the entity, a
// vanilla joiner needs nothing installed. Godmode / third person / speed persist across
// that player's respawns (mod_spawn_place re-asserts gf_god / gf_tp on whoever spawns;
// speed_apply reads gf_speed_pct). Weapons / camo / operator / outfit reuse the shared hubs
// through the target context (menu_target, above the menu engine). Fly is the host's
// fly_think threaded on the client - it reads that player's own sprint/jump/crouch input.
// ⚠ Built 2026-09-15, never run in-game: docs/notes/client-control.md has the test order.
// ─────────────────────────────────────────────────────────────────────────────────────

function private client_page_build( id, player )
{
    it = self menu_item( id, "Godmode", &act_c_god, player );
    it.activated = is_true( player.gf_god );
    self menu_item( id, "Max ammo - every weapon", &act_c_ammo, player );
    self menu_item( id, "Give weapon", &act_c_hub, "weapons", player );
    it = self menu_item( id, "Fly", &act_c_fly, player );
    it.activated = is_true( player.gf_fly );
    it = self menu_item( id, "Third person", &act_c_thirdperson, player );
    it.activated = is_true( player.gf_tp );
    self menu_item( id, "Speed: " + client_speed_label( player ), &act_c_speed, player );
    self menu_item( id, "Kill", &act_c_kill, player );
    // (bocw-8a: teleport rows)
    self menu_item( id, "Teleport to me", &act_tp_player, player, "tome" );
    self menu_item( id, "Teleport me to them", &act_tp_player, player, "metothem" );
    self menu_item( id, "Swap places with me", &act_tp_player, player, "swap" );
    self menu_item( id, "Camo", &act_c_hub, "camo", player );
    self menu_item( id, "Operator", &act_c_hub, "operator", player );
    self menu_item( id, "Outfit", &act_c_hub, "outfit", player );
    self menu_item( id, "Take current weapon", &act_c_takeweapon, player );
    self menu_item( id, "Strip all weapons", &act_c_strip, player );
    self menu_item( id, is_true( player.gf_frozen ) ? "Unfreeze" : "Freeze - can look, not move", &act_freeze_player, player );
    self menu_item( id, "To Allies", &act_move, player, #"allies" );
    self menu_item( id, "To Axis", &act_move, player, #"axis" );
    self menu_item( id, "To Spectator", &act_spectate, player );

    // Kick: humans only (bots have the Bots page), never the host.
    if ( !isbot( player ) && !( player ishost() ) )
        self menu_item( id, "Kick from the match", &act_c_kick, player );
}

// A row's player may have left since the page was built: entity refs go undefined on
// disconnect, so one check covers "left" and "never valid".
function private client_ok( player )
{
    if ( isdefined( player ) && isplayer( player ) )
        return true;

    self menu_say( "^1player left" );
    return false;
}

// Open a shared hub (weapons / camo / operator / outfit) aimed at this client: set the
// target, point the hub back at this page for V, go. menu_target_sync drops it on the
// way out. data1 is the page id so the row gets the submenu > marker.
function private act_c_hub( item, page, player )
{
    if ( !client_ok( player ) )
        return true;

    self.gfmenu.target = player;
    self.gfmenu.target_set = 1;
    self.gfmenu.menus[ page ].parent_id = self.gfmenu.current;

    return self menu_switch( undefined, page );
}

function private act_c_god( item, player )
{
    if ( !client_ok( player ) )
        return true;

    on = !is_true( player.gf_god );
    player.gf_god = on;
    item.activated = on;

    if ( on )
        player enableinvulnerability();
    else
        player disableinvulnerability();

    self menu_say( "^2" + player.name + " godmode " + ( on ? "ON" : "OFF" ) );
    return true;
}

// Every carried weapon incl. offhands (getweaponslist( 1 ), the scavenger's list -
// ammo_shared.gsc:69), minus the base melee.
function private act_c_ammo( item, player )
{
    if ( !client_ok( player ) )
        return true;

    if ( !isalive( player ) )
    {
        self menu_say( "^1" + player.name + " is not alive" );
        return true;
    }

    n = 0;

    foreach ( w in player getweaponslist( 1 ) )
    {
        if ( isdefined( level.weaponbasemelee ) && w == level.weaponbasemelee )
            continue;

        player givemaxammo( w );
        n++;
    }

    self menu_say( "^2" + player.name + ": max ammo on " + n + " weapons" );
    return true;
}

function private act_c_fly( item, player )
{
    if ( !client_ok( player ) )
        return true;

    if ( is_true( player.gf_fly ) )
    {
        player notify( #"gf_fly_stop" );
        item.activated = 0;
        self menu_say( "^2" + player.name + " fly OFF" );
        return true;
    }

    if ( !isalive( player ) )
    {
        self menu_say( "^1" + player.name + " is not alive" );
        return true;
    }

    player thread fly_think();
    item.activated = 1;
    self menu_say( "^2" + player.name + " fly ON - sprint fast, jump up, crouch down" );
    return true;
}

function private act_c_thirdperson( item, player )
{
    if ( !client_ok( player ) )
        return true;

    on = !is_true( player.gf_tp );
    player.gf_tp = on;
    item.activated = on;
    player setclientthirdperson( on );
    self menu_say( "^2" + player.name + ( on ? " third person" : " first person" ) );
    return true;
}

// Per-player move speed: the row cycles global -> 150 -> 200 -> 50 -> global. Held in
// gf_speed_pct (undefined = follow gf_speed) and read by speed_apply, so it survives that
// player's respawns until set back to global. act_c_speed_set is the app's form (pct).
function private client_speed_label( player )
{
    return isdefined( player.gf_speed_pct ) ? ( "" + player.gf_speed_pct + "%" ) : "global";
}

function private act_c_speed( item, player )
{
    if ( !client_ok( player ) )
        return true;

    cur = isdefined( player.gf_speed_pct ) ? player.gf_speed_pct : 0;

    if ( cur == 0 )
        nxt = 150;
    else if ( cur == 150 )
        nxt = 200;
    else if ( cur == 200 )
        nxt = 50;
    else
        nxt = 0;

    return self act_c_speed_set( item, player, nxt );
}

function private act_c_speed_set( item, player, pct )
{
    if ( !client_ok( player ) )
        return true;

    if ( !isdefined( pct ) || pct <= 0 )
        player.gf_speed_pct = undefined;
    else
        player.gf_speed_pct = int( min( pct, 1000 ) );

    if ( isalive( player ) )
        player speed_apply();

    item.name = "Speed: " + client_speed_label( player );
    self menu_say( "^2" + player.name + " speed " + client_speed_label( player ) );
    return true;
}

// Stock's own kill-a-player sequence (oob.gsc:869-873): the hurt-trigger damage, then
// suicide() for a player - which is what actually lands on an invulnerable or frozen one.
function private act_c_kill( item, player )
{
    if ( !client_ok( player ) )
        return true;

    if ( !isalive( player ) )
    {
        self menu_say( "^1" + player.name + " is already dead" );
        return true;
    }

    player dodamage( player.health + 10000, player.origin, undefined, undefined, "none", "MOD_TRIGGER_HURT", 8192 | 16384 );

    if ( isalive( player ) )
        player suicide();

    self menu_say( "^2" + player.name + " killed" );
    return true;
}

function private act_c_takeweapon( item, player )
{
    if ( !client_ok( player ) )
        return true;

    w = player getcurrentweapon();

    if ( isdefined( w ) && player hasweapon( w ) )
    {
        player takeweapon( w );
        self menu_say( "^2weapon taken from " + player.name );
    }
    else
    {
        self menu_say( "^1" + player.name + " holds nothing to take" );
    }

    return true;
}

function private act_c_strip( item, player )
{
    if ( !client_ok( player ) )
        return true;

    player takeallweapons();
    self menu_say( "^2" + player.name + " stripped of all weapons" );
    return true;
}

// kick( entnum, reason ): the stock inactivity drop (challenges_shared.gsc:1208); the
// reason is a localized key the vanilla client already carries. Back to the Players
// page afterwards - this page's rows point at a leaving entity.
function private act_c_kick( item, player )
{
    if ( !client_ok( player ) )
        return true;

    if ( player ishost() )
    {
        self menu_say( "^1not kicking the host" );
        return true;
    }

    name = player.name;
    kick( player getentitynumber(), "GAME/DROPPEDFORINACTIVITY" );
    self menu_say( "^2kicked " + name );

    return self menu_switch( undefined, "players" );
}

// ── Round ────────────────────────────────────────────────────────────────────

function private act_timer( item, seconds )
{
    cfg_seti( #"gf_timer_seconds", seconds );
    // Lands within ~0.25s: updategametypedvars() re-reads gettimelimit every loop.
    if ( seconds > 0 )
        self menu_say( "^2round timer " + seconds + "s" );
    else
        self menu_say( "^2round timer off - elimination only" );
    return true;
}

// Pre-match / pre-round countdown picks. The setting is written now so the next read
// takes it; the live level var is NOT touched - this load's countdown already ran, and
// mod_periods re-derives everything on the next load anyway.
function private act_prematch( item, secs )
{
    periods_snapshot();
    cfg_seti( #"gf_prematch", secs );
    v = periods_value( secs, game.gf_lobby_prematch );
    if ( isdefined( v ) )
        gts_set( #"prematchperiod", v );
    self menu_say( "^2pre-match countdown " + ( secs >= 0 ? ( secs + "s" ) : "lobby's value" ) + " - next match" );
    return true;
}

function private act_preround( item, secs )
{
    periods_snapshot();
    cfg_seti( #"gf_preround", secs );
    v = periods_value( secs, game.gf_lobby_preround );
    if ( isdefined( v ) )
        gts_set( #"preroundperiod", v );
    self menu_say( "^2pre-round countdown " + ( secs >= 0 ? ( secs + "s" ) : "lobby's value" ) + " - from next round" );
    return true;
}

function private act_restart( item )
{
    self menu_say( "^3restarting..." );
    // Threaded: the sweep waits two frames and this runs inside menu_think, which the menu
    // close (return false) must not be able to cut short of the restart itself.
    self thread restart_after_sweep();
    return false;
}

function private restart_after_sweep()
{
    self endon( #"disconnect" );
    veh_sweep_for_transition( "restart" );
    map_restart();
}

// ── Loadout ──────────────────────────────────────────────────────────────────

function private act_loadout( item, index )
{
    cfg_seti( #"gf_loadout", index );
    gts_set( #"gunfightloadoutindex", index );

    // gunfight.gsc:81 picks the loadout set only while game.var_96a8ff4a is
    // undefined. Clear the latch once so the NEXT round re-picks from the new set.
    game.var_96a8ff4a = undefined;

    self menu_say( "^2loadout set " + index + " - takes effect next round" );
    return true;
}

// The gate is read once, at match start (gunfight.gsc:102 in onstartgametype), so a live
// toggle only writes the setting for the NEXT match or switch - mod_apply / mode_profile_prime
// assert it from the dvar at both.
function private act_customcac( item, value )
{
    cfg_seti( #"gf_customcac", value );
    dcc = value ? 0 : 1;
    gts_set( #"disablecustomcac", dcc );
    self menu_say( value ? "^2custom classes ON - next match / switch" : "^2custom classes OFF - Gunfight loadouts next match / switch" );
    return true;
}

// ── Loadout-pool camo ────────────────────────────────────────────────────────

function private act_poolcamo( item, value )
{
    cfg_seti( #"gf_camo", value );
    self mod_camo_repaint_all( value == -1 );
    self menu_say( "^2pool camo: " + camo_label( value ) + ( value == -1 ? " - bare until next round" : "" ) );
    return true;
}

// Repaint everyone on the spot, bots included, so a pick can be judged this round (Gunfight
// has no respawn, so "next spawn" would mean next round). Rolls already made are stale.
// Stock strips to bare (index 0) until the next spawn rebuilds the pool's own look, a
// blueprint's included - there is no way to put a blueprint's camo back from here.
function private mod_camo_repaint_all( strip )
{
    level.gfmenu_camo = undefined;

    foreach ( p in getplayers() )
        p mod_camo_start( strip ? 0 : undefined );
}

function private act_poolcamo_pool( item, value )
{
    cfg_seti( #"gf_camo_pool", value );
    if ( cfg_camo() <= -2 )               // only a random mode has rolls to redo
        self mod_camo_repaint_all( 0 );
    self menu_say( "^2random camo pool: " + ( value == 1 ? "all 1-121" : "mastery + PaP" ) );
    return true;
}

function private act_poolcamo_split( item, value )
{
    cfg_seti( #"gf_camo_split", value );
    if ( cfg_camo() <= -2 )
        self mod_camo_repaint_all( 0 );
    self menu_say( "^2random camo: " + ( value ? "primary and secondary roll separately" : "one roll for both" ) );
    return true;
}

// ── Spy plane ────────────────────────────────────────────────────────────────

function private act_spyplane( item, value )
{
    cfg_seti( #"gf_spyplane", value );
    gts_set( #"gunfightspyplane", value );
    self menu_say( "^2spy plane " + value + " - next round" );
    return true;
}

// ── Spawns ─────────────────────────────────────────────────────────────────

function private act_spawn_report( item )
{
    self thread spawn_report();
    return true;
}

// ── Display ────────────────────────────────────────────────────────────────
// Switch the text layout live. menu_paint/menu_render read gf_menu_region every repaint,
// so the change lands on the next frame; the old region's leftover text just fades. In
// SPLIT this confirmation folds into the status block (menu_say), so it is visible there.
function private act_menu_region( item, value )
{
    cfg_seti( #"gf_menu_region", value );
    msg = "^2layout: all in feed";
    if ( value == 1 )
        msg = "^2layout: all in centre";
    else if ( value == 2 )
        msg = "^2layout: status left, menu centre - scrolls sideways";
    else if ( value == 3 )
        msg = "^2layout: menu left, status centre - raise gf_menu_lines for more rows";
    else if ( value == 4 )
        msg = "^2layout: HINT panel - the use-prompt widget";
    self menu_say( msg );
    return true;
}

// ── HINT panel knobs (region 4) ───────────────────────────────────────────────
function private act_hint_lines( item, value )
{
    cfg_seti( #"gf_hint_lines", value );
    self menu_say( "^2hint panel shows " + value + " rows" );
    return true;
}

function private act_hint_newlines( item, value )
{
    cfg_seti( #"gf_hint_newlines", value );
    self menu_say( value ? "^2hint rows on newlines - one long line means the widget ignores them" : "^2hint rows packed on one line" );
    return true;
}

function private act_caster_probe( item, value )
{
    cfg_seti( #"gf_caster_probe", value );
    self menu_say( value ? "^2caster probe ON - prints while you cast" : "^2caster probe OFF" );
    return true;
}

function private act_match_info( item )
{
    self thread match_info();
    return true;
}

// ── Settings census ──────────────────────────────────────────────────────────
// The rest of the mode-remnant question is answered by measurement, not by the dump: the
// per-mode default blobs live in the LUI presets, which the dump does not carry (the DDL
// only declares the fields). This reads the settings that shape a Gunfight match, key=value.
// Run it ONCE in a Gunfight launched from a lobby with Gunfight selected (the real blob) and
// ONCE in a Gunfight launched from a TDM-config lobby (klaze's Case B, the hybrid); the diff
// is the remnant list, and docs/notes/mode-remnants.md is where it goes. Every key below is
// a declared field of ddl/mp_gametype_settings.ddl; values print raw (bools 0/1, fixed-point
// as the engine returns it, "-" for a key this build does not know).
//
// SNAPSHOT AT LAUNCH (2026-09-14). A census read from the menu mid-match sees the values
// mod_apply has ALREADY asserted (customcac, loadoutindex, spyplane, roundwinlimit,
// maxplayers, ...) - not the blob the lobby launched with, which is the thing the diff is
// about. So census_snapshot() runs FIRST THING in mod_apply, before any write, once per
// (gametype, map) per match (game. survives the round boundary; a NOW switch changes the key
// and re-snapshots), and keeps the lines in game.gf_census. The menu shows that snapshot;
// a second row shows the live values for comparison.
//
// DISPLAY (klaze, 2026-09-14): one complete feed line, continuously, while gf_census is on -
// see DEBUG FEED below (census_line). 1 = the launch snapshot, 2 = live. Short keys, legend
// in docs/notes/mode-remnants.md.
function private census_v( v )
{
    return isdefined( v ) ? ( "" + v ) : "-";
}

function private census_s( key )
{
    return census_v( getgametypesetting( key ) );
}

function private census_key()
{
    return tolower( getdvarstring( #"g_gametype", "?" ) ) + "|" + getdvarstring( #"sv_mapname", "?" );
}

// The blob as the match launched with it. Called before mod_apply writes anything; once per
// (gametype, map) - round 2 of the same match keeps round 1's snapshot, which is the clean one.
function private census_snapshot()
{
    key = census_key();

    if ( isdefined( game.gf_census_key ) && game.gf_census_key == key )
        return;

    game.gf_census_key = key;
    game.gf_census = census_lines();
}

// Five lines: [0] centre, [1] hint (wide), [2..4] feed. The tag is added at display time.
function private census_lines()
{
    l = [];

    c = "tl=" + census_s( #"timelimit" ) + " sl=" + census_s( #"scorelimit" ) + " rl=" + census_s( #"roundlimit" ) + " rwl=" + census_s( #"roundwinlimit" );
    c += " cum=" + census_s( #"cumulativeroundscores" ) + " rsw=" + census_s( #"roundswitch" ) + " spk=" + census_s( #"teamscoreperkill" );
    c += " fr=" + census_s( #"playerforcerespawn" ) + " qr=" + census_s( #"playerqueuedrespawn" ) + " rd=" + census_s( #"playerrespawndelay" ) + " nl=" + census_s( #"playernumlives" );
    l[ 0 ] = c;

    h = "mp=" + census_s( #"maxplayers" ) + " tc=" + census_s( #"teamcount" ) + " hc=" + census_s( #"hardcoremode" ) + " spec=" + census_s( #"spectatetype" );
    h += " cac=" + census_s( #"disablecustomcac" ) + " cls=" + census_s( #"disableclassselection" ) + " prk=" + census_s( #"perksenabled" ) + " att=" + census_s( #"disableattachments" );
    h += " wd=" + census_s( #"disableweapondrop" ) + " lks=" + census_s( #"loadoutkillstreaksenabled" ) + " tch=" + census_s( #"allowingameteamchange" ) + " tac=" + census_s( #"disabletacinsert" );
    h += " gfr=" + census_s( #"gunfightroundsperloadout" ) + " gfs=" + census_s( #"gunfightspyplane" ) + " gfl=" + census_s( #"gunfightloadoutindex" );
    l[ 1 ] = h;

    f = "cap=" + census_s( #"capturetime" ) + " ext=" + census_s( #"extratime" ) + " pre=" + census_s( #"prematchperiod" ) + " prr=" + census_s( #"preroundperiod" );
    f += " hp=" + census_s( #"playermaxhealth" ) + " reg=" + census_s( #"playerhealthregentime" ) + " ah=" + census_s( #"autoheal" ) + " dmg=" + census_s( #"bulletdamagescalar" );
    l[ 2 ] = f;

    f = "rad=" + census_s( #"forceradar" ) + " exd=" + census_s( #"roundstartexplosivedelay" ) + " skd=" + census_s( #"roundstartkillstreakdelay" ) + " spr=" + census_s( #"playersprinttime" );
    f += " bnd=" + ( isdefined( level.var_d1455682 ) ? "y" : "n" ) + " ssg=" + census_v( isdefined( level.var_d1455682 ) ? level.var_d1455682.switchsides : undefined );
    f += " lrs=" + census_v( level.roundswitch ) + " ss=" + census_v( game.switchedsides ) + " rp=" + census_v( game.roundsplayed );
    l[ 3 ] = f;

    l[ 4 ] = getdvarstring( #"g_gametype", "?" ) + "/" + getdvarstring( #"sv_mapname", "?" ) + " cfg cac=" + cfg_customcac() + " sw=" + cfg_switch_sides();

    return l;
}

function private census_host()
{
    foreach ( player in getplayers() )
    {
        if ( player ishost() )
            return player;
    }

    return undefined;
}

// The hint trigger is the broadcast banner's (broadcast_hint_make, host only here). Left
// alone when a banner is running - it owns the trigger then.
function private census_hint_clear()
{
    if ( isdefined( level.gf_hint_msg ) )
        return;

    host = census_host();

    if ( isdefined( host ) && isdefined( host.gf_say_trig ) )
    {
        host.gf_say_trig delete();
        host.gf_say_trig = undefined;
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// DEBUG FEED — one complete line per tool, continuously, while the tool is on.
// klaze, 2026-09-14: "the feed can hold very long lines of text - every debug tool gets an
// enable option that auto-prints just ONE full line with every data point needed for that
// debug in the feed, continuously, while the option is on." So: one level thread, a 3 s
// tick (the feed fades in about that), and each enabled tool contributes one line to the
// HOST's feed per tick. Nothing here uses the centre or the hint row any more.
//   gf_census        0 off · 1 the settings blob AS LAUNCHED (the snapshot mod_apply took
//                    before its own writes) · 2 the LIVE values      -> census_line
//   gf_dbg_spawn     this round's engine placements, every player   -> spawn_line
//   gf_dbg_structs   the mp_spawn_point schema + engine list names  -> structs_line
//   gf_dbg_families  spawn-struct family counts + guard state       -> families_line
//   gf_dbg_match     the match/config readout (Show match info)     -> match_line
// Display -> Debug feed page toggles them; the app's Display section carries the dvars.
// The loop starts at every match start when any is on, and from every toggle.
// ═════════════════════════════════════════════════════════════════════════════
function private cfg_dbg_census()   { return cfg_geti( #"gf_census", 0 ); }
function private cfg_dbg_spawn()    { return cfg_geti( #"gf_dbg_spawn", 0 ); }
function private cfg_dbg_structs()  { return cfg_geti( #"gf_dbg_structs", 0 ); }
function private cfg_dbg_families() { return cfg_geti( #"gf_dbg_families", 0 ); }
function private cfg_dbg_match()    { return cfg_geti( #"gf_dbg_match", 0 ); }
function private cfg_dbg_assets()   { return cfg_geti( #"gf_dbg_assets", 0 ); }

function private debug_feed_any()
{
    return cfg_dbg_census() || cfg_dbg_spawn() || cfg_dbg_structs() || cfg_dbg_families() || cfg_dbg_match() || cfg_dbg_flags() || cfg_dbg_assets() || cfg_dbg_veh();
}

function private debug_feed_start()
{
    if ( isdefined( level.gf_dbgfeed_on ) && level.gf_dbgfeed_on )
        return;

    level thread debug_feed_loop();
}

function private debug_feed_loop()
{
    level endon( #"game_ended" );

    level.gf_dbgfeed_on = 1;

    while ( debug_feed_any() )
    {
        host = census_host();

        if ( isdefined( host ) )
        {
            if ( cfg_dbg_census() )
                host iprintln( census_line( cfg_dbg_census() == 2 ) );
            if ( cfg_dbg_spawn() )
                host iprintln( spawn_line() );
            if ( cfg_dbg_structs() )
                host iprintln( structs_line() );
            if ( cfg_dbg_families() )
            {
                host iprintln( families_line() );
                host iprintln( starts_line() );
            }
            if ( cfg_dbg_flags() )
            {
                host iprintln( flags_line() );
                host iprintln( flags_line2() );
            }
            if ( cfg_dbg_match() )
                host iprintln( match_line() );
            if ( cfg_dbg_assets() )
            {
                host iprintln( assets_line_v() );
                host iprintln( assets_line_p() );
                host iprintln( assets_line_d() );
            }
            if ( cfg_dbg_veh() )
                host iprintln( veh_line() );
        }

        wait 3;
    }

    level.gf_dbgfeed_on = 0;
}

// Menu toggles. value: the dvar value to set (0 = off). A toggle on a running tool turns
// it off; the loop notices on its next tick and ends itself when nothing is left on.
function private act_dbg( item, dvar, value, label )
{
    // Through the config store (bocw-85 F1, 2026-09-17): six of these dvars live in the PACKED
    // store, whose readers (cfg_dbg_*) never saw a direct setdvar - the toggles were dead. Plain
    // dvars (gf_dbg_veh) fall through cfg_geti/cfg_seti to getdvarint/setdvar unchanged.
    cur = cfg_geti( dvar, 0 );
    nv = ( cur == value ) ? 0 : value;
    cfg_seti( dvar, nv );

    if ( nv )
    {
        debug_feed_start();
        self menu_say( "^2debug feed: " + label + " ON - one line every 3 s until switched off" );
    }
    else
    {
        self menu_say( "^2debug feed: " + label + " off" );
    }

    return true;
}

function private act_dbg_census( item, value )     { return self act_dbg( item, #"gf_census", value, value == 2 ? "settings census LIVE" : "settings census AS LAUNCHED" ); }
function private act_dbg_spawn( item )             { return self act_dbg( item, #"gf_dbg_spawn", 1, "spawn placements" ); }
function private act_dbg_structs( item )           { return self act_dbg( item, #"gf_dbg_structs", 1, "spawn structs" ); }
function private act_dbg_families( item )          { return self act_dbg( item, #"gf_dbg_families", 1, "spawn families" ); }
function private act_dbg_match( item )             { return self act_dbg( item, #"gf_dbg_match", 1, "match info" ); }
function private act_dbg_assets( item )            { return self act_dbg( item, #"gf_dbg_assets", 1, "asset census (vehicles + props + destructibles)" ); }

function private act_dbg_all_off( item )
{
    cfg_seti( #"gf_census", 0 );
    cfg_seti( #"gf_dbg_spawn", 0 );
    cfg_seti( #"gf_dbg_structs", 0 );
    cfg_seti( #"gf_dbg_families", 0 );
    cfg_seti( #"gf_dbg_match", 0 );
    cfg_seti( #"gf_dbg_flags", 0 );
    cfg_seti( #"gf_dbg_assets", 0 );
    cfg_seti( #"gf_dbg_veh", 0 );
    self menu_say( "^2debug feed: everything off" );
    return true;
}

// ── The five line builders ───────────────────────────────────────────────────

// The 46 settings, short keys (legend: docs/notes/mode-remnants.md), one line.
function private census_line( live )
{
    if ( live || !isdefined( game.gf_census ) )
    {
        l = census_lines();
        tag = "^3CENSUS LIVE^7 ";
    }
    else
    {
        l = game.gf_census;
        tag = "^2CENSUS LAUNCH^7 ";
    }

    return tag + l[ 4 ] + " | " + l[ 0 ] + " | " + l[ 1 ] + " | " + l[ 2 ] + " | " + l[ 3 ];
}

// This round's placements as the engine (or the guard) made them - every player - plus the
// guard's state. Entries come from spawn_log_record (level.gf_spawn_round, per round).
function private spawn_line()
{
    rp = isdefined( game.roundsplayed ) ? game.roundsplayed : 0;
    gd = cfg_spawn_guard();
    hook = isdefined( level.var_cda5136b ) ? "y" : "n";
    anchors = isdefined( level.gfmenu_spawn ) ? ( level.gfmenu_spawn.team1.size + "+" + level.gfmenu_spawn.team2.size ) : "none";
    sw = ( isdefined( game.switchedsides ) && game.switchedsides ) ? 1 : 0;

    line = "^3SPAWN^7 r" + rp + " guard=" + ( gd == 2 ? "AUTO" : ( gd == 1 ? "FORCE" : "off" ) ) + " hook=" + hook + " anchors=" + anchors + " switched=" + sw + " players=" + getplayers().size;

    if ( !isdefined( level.gf_spawn_round ) || level.gf_spawn_round.size == 0 )
        return line + " | no spawns recorded this round";

    line += " |";
    foreach ( e in level.gf_spawn_round )
        line += " " + e;

    return line;
}

// The map's mp_spawn_point schema and the engine's list names. Built once per level.
function private structs_line()
{
    if ( isdefined( level.gf_structs_line ) )
        return level.gf_structs_line;

    arr = struct::get_array( "mp_spawn_point", "targetname" );
    na = struct::get_array( "mp_spawn_point_allies", "targetname" );
    nx = struct::get_array( "mp_spawn_point_axis", "targetname" );
    line = "^3STRUCTS^7 mp_spawn_point=" + ( isdefined( arr ) ? arr.size : 0 ) + " allies=" + ( isdefined( na ) ? na.size : 0 ) + " axis=" + ( isdefined( nx ) ? nx.size : 0 );

    for ( i = 0; i < 3; i++ )
    {
        if ( isdefined( arr ) && i < arr.size )
            line += " | #" + i + spawn_struct_fields( arr[ i ] );
    }

    lists = getspawnlists();
    if ( isdefined( lists ) && isarray( lists ) )
    {
        line += " | lists n=" + lists.size + ":";
        foreach ( x in lists )
            line += " " + spawn_fv( x );
    }
    else
    {
        line += " | lists: " + spawn_fv( lists );
    }

    // Gametype spawn ENTITIES (getentarray by classname - getspawnpointarray's form,
    // zm spawnlogic:317). MP never deletes unused-gametype spawns (only ZM does), so if a
    // map ships dedicated S&D bases they persist through a Gunfight match and we can place
    // players at them - EXACTLY S&D's fixed opposite-side spawns. This line says whether
    // this map has them: sd=attacker/defender, tdm=allies/axis/generic, dom/ctf likewise.
    line += " | ENT sd=" + spawn_ent_n( "mp_sd_spawn_attacker" ) + "/" + spawn_ent_n( "mp_sd_spawn_defender" )
        + " tdm=" + spawn_ent_n( "mp_tdm_spawn_allies_start" ) + "/" + spawn_ent_n( "mp_tdm_spawn_axis_start" ) + "/" + spawn_ent_n( "mp_tdm_spawn" )
        + " dom=" + spawn_ent_n( "mp_dom_spawn_allies_start" ) + "/" + spawn_ent_n( "mp_dom_spawn_axis_start" )
        + " ctf=" + spawn_ent_n( "mp_ctf_spawn_allies_start" ) + "/" + spawn_ent_n( "mp_ctf_spawn_axis_start" )
        + " dm=" + spawn_ent_n( "mp_dm_spawn" );

    level.gf_structs_line = line;
    return line;
}

// count spawn ENTITIES of a classname (getspawnpointarray's form, zm spawnlogic:317)
function private spawn_ent_n( classname )
{
    a = getentarray( classname, "classname" );
    return isdefined( a ) ? a.size : 0;
}

// Every spawn family this map places (non-zero only), the legacy detector's numbers, and
// what the guard built. Built once per level.
function private families_line()
{
    if ( isdefined( level.gf_families_line ) )
        return level.gf_families_line;

    line = "^3FAMILIES^7 strike=" + ( isdefined( level.gf_strike_status ) ? level.gf_strike_status : "?" );
    if ( isdefined( level.gf_area_radius ) )
        line += " area=" + spawn_fv( level.gf_area_center ) + " r=" + int( level.gf_area_radius );
    line += " |";
    n = 0;
    foreach ( name in mod_spawn_families() )
    {
        arr = struct::get_array( name, "targetname" );

        if ( !isdefined( arr ) || arr.size == 0 )
            continue;

        line += " " + name + "=" + arr.size;
        n++;
    }

    if ( n == 0 )
        line += " none-by-any-known-targetname";

    starts = mod_gather_named( mod_start_families() );
    obj = mod_gather_named( mod_obj_families() );
    line += " | legacy starts=" + starts.size + " obj=" + obj.size;

    if ( starts.size >= 2 && obj.size >= 4 )
    {
        c = mod_centroid( obj );
        line += " objr=" + int( mod_mean_dist2d( obj, c ) ) + " startmin=" + int( mod_min_dist2d( starts, c ) ) + " trip=" + cfg_spawn_autospread();
    }

    line += " | pick=" + ( cfg_spawn_pick() ? "far" : "near" ) + " family=" + family_name( cfg_spawn_family() ) + ( ( isdefined( level.gf_family_note ) && level.gf_family_note != "" ) ? ( " " + level.gf_family_note ) : "" );

    if ( isdefined( level.gfmenu_spawn ) )
    {
        c1 = mod_centroid( level.gfmenu_spawn.team1 );
        c2 = mod_centroid( level.gfmenu_spawn.team2 );
        line += " | guard armed " + level.gfmenu_spawn.team1.size + "+" + level.gfmenu_spawn.team2.size + " sep=" + int( sqrt( mod_dist2d_sq( c1, c2 ) ) ) + " gap=" + cfg_spawn_gap();
    }
    else
    {
        line += " | guard not armed";
    }

    level.gf_families_line = line;
    return line;
}

// Show match info, on one line.
function private match_line()
{
    ts = cfg_team_size();
    gd = cfg_spawn_guard();
    st = tolower( getdvarstring( #"gf_staged_map", "" ) );

    line = "^3MATCH^7 " + getdvarstring( #"g_gametype", "?" ) + "/" + getdvarstring( #"sv_mapname", "?" ) + " " + ( cfg_map_method() ? "session" : "carry" );
    if ( st != "" )
        line += " next=" + st + "/" + getdvarstring( #"gf_staged_gt", "" );
    line += " | R" + info_round() + " " + info_score( #"allies" ) + "-" + info_score( #"axis" );
    line += " | " + ts + "v" + ts + " A=" + getplayers( #"allies" ).size + "(" + info_bots( #"allies" ) + "b) X=" + getplayers( #"axis" ).size + "(" + info_bots( #"axis" ) + "b) budget=" + getdvarint( #"com_maxclients", 0 );
    line += " | timer=" + cfg_timer_label() + " win=" + ( cfg_roundwinlimit() >= 0 ? ( "" + cfg_roundwinlimit() ) : "stock" ) + " cap=" + ( cfg_roundlimit() >= 0 ? ( "" + cfg_roundlimit() ) : "stock" ) + " rot=" + ( cfg_rounds_loadout() >= 0 ? ( "" + cfg_rounds_loadout() ) : "stock" );
    line += " | loadout=" + info_loadout() + " camo=" + ( cfg_camo() != -1 ? camo_label( cfg_camo() ) : "stock" ) + " spy=" + cfg_spyplane() + " cac=" + cfg_customcac() + " profile=" + cfg_profile();
    line += " | pre=" + ( cfg_prematch() >= 0 ? ( cfg_prematch() + "s" ) : "lobby" ) + "/" + ( cfg_preround() >= 0 ? ( cfg_preround() + "s" ) : "lobby" );
    line += " | spawn=" + ( gd == 2 ? "AUTO" : ( gd == 1 ? "FORCE" : "off" ) ) + " zone=" + ( cfg_zone() ? ( "ot" + cfg_zone_overtime() + "/cap" + cfg_zone_capture() ) : "off" );
    line += " | grav=" + cfg_gravity() + " jump=" + ( cfg_jump() >= 0 ? ( "" + cfg_jump() ) : "stock" ) + " boost=" + cfg_jump_boost() + " speed=" + cfg_speed() + "% fall=" + ( cfg_falldamage() ? "stock" : "off" );

    return line;
}

function private act_menu_hspan( item, value )
{
    cfg_seti( #"gf_menu_hspan", value );
    self menu_say( "^2centre bar shows " + value + " at once" );
    return true;
}

// ── Overtime zone ────────────────────────────────────────────────────────────

function private act_zone_census( item )
{
    self thread zone_report();
    return true;
}

function private act_zone( item, value )
{
    cfg_seti( #"gf_zone", value );

    if ( value )
        self menu_say( "^3overtime zone ON from next round - run the census first" );
    else
        self menu_say( "^2overtime zone OFF - HP tiebreak at time limit" );

    return true;
}

function private act_zone_overtime( item, seconds )
{
    cfg_seti( #"gf_zone_overtime", seconds );
    level.extratime = seconds;   // overtime() reads it at expiry, so this round counts too
    self menu_say( "^2overtime " + seconds + "s" );
    return true;
}

function private act_zone_capture( item, seconds )
{
    cfg_seti( #"gf_zone_capture", seconds );
    level.capturetime = seconds;
    self menu_say( "^2zone capture " + seconds + "s" );
    return true;
}

function private act_spawn_pick( item, value )
{
    cfg_seti( #"gf_spawn_pick", value );
    if ( cfg_spawn_guard() )
        mod_spawn_build();
    self menu_say( value ? "^2spawn pick: far ends - the two outermost groups, like TDM openings" : "^2spawn pick: near - gap based, the closer-up version" );
    return true;
}

function private act_spawn_gap( item, value )
{
    cfg_seti( #"gf_spawn_gap", value );
    if ( cfg_spawn_guard() )
        mod_spawn_build();
    self menu_say( "^2guard gap " + value + "u between the sides" + ( isdefined( level.gfmenu_spawn ) ? ( " - rebuilt, next spawns use it" ) : "" ) );
    return true;
}

function private act_spawn_guard( item, value )
{
    cfg_seti( #"gf_spawn_guard", value );

    if ( value )
    {
        // Build the anchors now so the guard also applies to THIS round, not only from next
        // round's mod_apply. Safe from a player context - mod_spawn_build only touches
        // level.* and getplayers(). In AUTO this also runs the detector; if it decides the
        // map is fine, gfmenu_spawn stays undefined and stock spawns stand.
        mod_spawn_build();
        level.var_cda5136b = &mod_spawn_override;
        armed = isdefined( level.gfmenu_spawn );
        if ( value == 2 )
            self menu_say( armed ? "^2spawn guard AUTO - engine start spawns when it has them, anchors when it has none" : "^3spawn guard AUTO - no anchors on this map, too few markers; stock spawns" );
        else
            self menu_say( armed ? "^3spawn guard FORCE - anchors on every spawn from now" : "^3spawn guard FORCE - no anchors on this map, too few markers; stock spawns" );
    }
    else
    {
        level.var_cda5136b = undefined;
        self menu_say( "^2spawn guard OFF - stock spawns" );
    }

    return true;
}

function private act_spawn_antistack( item, value )
{
    cfg_seti( #"gf_spawn_antistack", value );
    self menu_say( value ? "^2anti-stack net ON - stacked spawns fan out side by side" : "^2anti-stack net OFF" );
    return true;
}

// ── Match-length knobs. Verified stock keys; sentinel -1 elsewhere = untouched. ──

function private act_roundwinlimit( item, value )
{
    cfg_seti( #"gf_roundwinlimit", value );
    gts_set( #"roundwinlimit", value );
    self menu_say( "^2first to " + value + " rounds - applies next round" );
    return true;
}

function private act_roundlimit( item, value )
{
    cfg_seti( #"gf_roundlimit", value );
    gts_set( #"roundlimit", value );
    self menu_say( "^2round cap " + value + " - applies next round" );
    return true;
}

function private act_rounds_loadout( item, value )
{
    cfg_seti( #"gf_rounds_loadout", value );
    gts_set( #"gunfightroundsperloadout", value );
    // The live level var the round-end check actually reads (see mod_apply), plus the
    // side-switch gate - so a mid-match pick takes effect this match, not only next match.
    level.gunfightroundsperloadout = value;
    if ( isdefined( level.var_d1455682 ) )
        level.var_d1455682.switchsides = 1;
    self menu_say( "^2loadout + sides switch every " + value + " round(s)" );
    return true;
}

// Live: the gate and the generic path are level state read at each round end, so this
// takes effect at the next boundary of THIS match. Stock (0) restores the bundle's own
// flag only in the sense of leaving it - a flag already forced on this match stays on;
// the generic path is re-armed from the setting.
function private act_switch_sides( item, value )
{
    cfg_seti( #"gf_switch_sides", value );

    if ( value )
    {
        if ( isdefined( level.var_d1455682 ) )
            level.var_d1455682.switchsides = 1;
        level.roundswitch = 0;
        self menu_say( "^2sides: mod-owned - one flip per loadout rotation" );
    }
    else
    {
        level.roundswitch = getgametypesetting( #"roundswitch" );
        self menu_say( "^2sides: stock paths - roundswitch=" + census_v( level.roundswitch ) );
    }

    return true;
}

// ── Movement ───────────────────────────────────────────────────────────────

function private act_gravity( item, value )
{
    cfg_seti( #"gf_gravity", value );
    setdvar( #"bg_gravity", value );
    self menu_say( "^2gravity " + value + ( value == 800 ? " (normal)" : "" ) );
    return true;
}

function private act_jump( item, value )
{
    cfg_seti( #"gf_jump", value );

    if ( value >= 0 )
    {
        setjumpheight( value );
        self menu_say( "^3jump height " + value + " - untested builtin, watch your jump" );
    }
    else
    {
        self menu_say( "^2jump left at engine default" );
    }

    return true;
}

function private act_jump_boost( item, value )
{
    cfg_seti( #"gf_jump_boost", value );

    if ( value > 0 )
        self menu_say( "^2jump boost +" + value + " - everyone, next jump" );
    else
        self menu_say( "^2jump boost off" );

    return true;
}

function private act_speed( item, pct )
{
    cfg_seti( #"gf_speed", pct );
    speed_apply_all();
    self menu_say( "^2move speed " + pct + "% - everyone, now" );
    return true;
}

function private act_falldamage( item, value )
{
    cfg_seti( #"gf_falldamage", value );
    mod_falldamage_apply();
    self menu_say( value ? "^2fall damage: stock" : "^2fall damage OFF" );
    return true;
}

function private act_fly_speed( item, normal, fast )
{
    cfg_seti( #"gf_fly_speed", normal );
    cfg_seti( #"gf_fly_fast", fast );
    self menu_say( "^2fly speed " + normal + " / sprint " + fast );
    return true;
}

function private act_fly( item )
{
    if ( isdefined( self.gf_fly ) && self.gf_fly )
    {
        self notify( #"gf_fly_stop" );
        item.activated = 0;
        self menu_say( "^2fly OFF" );
        return true;
    }

    if ( !isalive( self ) )
    {
        self menu_say( "^1fly: spawn first" );
        return true;
    }

    self thread fly_think();
    item.activated = 1;
    self menu_say( "^2fly ON - sprint fast, jump up, crouch down" );
    return true;
}

// ── Host: pause / freeze / broadcast ───────────────────────────────────────

function private act_pause( item )
{
    if ( isdefined( level.gf_paused ) && level.gf_paused )
    {
        item.activated = 0;
        self thread match_resume();
        self menu_say( "^2resuming in 5..." );
        return true;
    }

    match_pause();
    item.activated = 1;
    self menu_say( "^2match PAUSED - everyone frozen, timer held" );
    return true;
}

function private act_freeze_all( item )
{
    on = !( isdefined( level.gf_frozen_all ) && level.gf_frozen_all );
    freeze_all_set( on );
    item.activated = on;
    self menu_say( on ? "^2everyone frozen" : "^2everyone released" );
    return true;
}

function private act_freeze_player( item, player )
{
    if ( !isdefined( player ) )
    {
        self menu_say( "^1player left" );
        return true;
    }

    on = !( isdefined( player.gf_frozen ) && player.gf_frozen );
    freeze_set( player, on );
    item.name = on ? "Unfreeze" : "Freeze - can look, not move";
    self menu_say( on ? ( "^2" + player.name + " frozen" ) : ( "^2" + player.name + " released" ) );
    return true;
}

function private act_countdown( item )
{
    self thread broadcast_countdown();
    self menu_say( "^2countdown sent" );
    return true;
}

function private act_announce( item )
{
    broadcast_settings();
    self menu_say( "^2settings announced" );
    return true;
}

function private act_say( item, msg )
{
    broadcast_bold( msg );              // no prefix - shows exactly what the host typed
    self menu_say( "^2sent: " + msg );
    return true;
}

// A held hint banner (loc 2) instead of a one-shot centre print. broadcast_hint_start
// handles the per-player glued triggers; -1 = fixed until Clear banner / gf_cmd_say_clear.
function private act_banner( item, msg )
{
    broadcast_hint_start( msg, -1 );
    self menu_say( "^2banner shown [hint] - Clear banner to remove" );
    return true;
}

function private act_banner_clear( item, msg )
{
    broadcast_hint_stop();
    self menu_say( "^2banner cleared" );
    return true;
}

// ── Vehicles ───────────────────────────────────────────────────────────────
// Spawn a drivable vehicle ahead of the host. The mechanism is the shipped Atian
// menu's (menu_funcs.gsc func_spawn_vehicle): spawnvehicle + makeusable, with physics
// and helicopter handling. ⚠ Vehicle ASSETS only exist on maps that ship them - the
// Combined-Arms / 12v12-layout maps - so isassetloaded() gates it and says so on a
// Gunfight map instead of failing. ⚠ Whole feature UNTESTED in this project.

// ── Vehicles page, built PER MAP (2026-09-15) ────────────────────────────────
// The dump ships tables/bgcache/<zone>.csv - every asset a zone precaches - and a map runs
// with core_bootstrap + core_common + mp_common + its own zone, so the union of their
// `vehicle` rows is what isassetloaded( "vehicle", name ) says yes to. MEASURED: Standoff's
// census (gf_dbg_assets) found exactly the four streak vehicles core_common / mp_common
// carry, nothing else; drivables ship only with Armada (boats), Crossroads (T-72,
// snowmobile), Collateral (FAV, motorcycle, quad, trucks, Hind), Cartel, Checkmate / Diesel
// (APC) and the Fireteam maps. tools/mapdata-extract.py regenerates docs/data/map-assets.json
// from those tables. Rather than carry a per-map table here, the page asks the engine at
// build time over the MASTER list below (every vehicle row of every MP / Fireteam zone,
// docs/notes/map-data.md) and shows only what is resident on THIS map: drivables on the
// page, streaks / the map's intro-cinematic vehicle / turrets on a sub-page. Hashed keys
// are names the dump could not resolve; spawnvehicle( #"hash_..." ) is stock syntax
// (vip.gsc:125), so they are offered by hash, labelled by the scene that uses them.
function private veh_def( m, key, label, kind, text )
{
    e = spawnstruct();
    e.key = key;
    e.label = label;
    e.kind = kind;                         // 0 drivable, 1 other (streak / intro / turret)
    e.text = isdefined( text ) ? text : key;
    m[ m.size ] = e;
    return m;
}

function private veh_master()
{
    if ( isdefined( level.gf_veh_master ) )
        return level.gf_veh_master;

    m = [];
    // drivables (bgcache: mp_black_sea, mp_dune, mp_tundra, mp_cartel, mp_kgb, mp_sm_gas_station, wz_*).
    // 2026-09-16 cross-check against the 205-name universe (vehicles.md §7): six rows that sit in
    // NO zone were dropped (veh_boct_mil_jetski, veh_quad_player_wz_tan, vehicle_boct_mil_boat_pbr,
    // vehicle_t8_mil_tank_wz_base_mg, ..._hind_wz, vehicle_t9_plane_flyable_prototype - the
    // isassetloaded filter hid them, but a tempting name that can never resolve is noise) and the
    // two resident names the master lacked were added (snowmobile single seat, BO4 air transport).
    m = veh_def( m, "vehicle_t9_mil_fav_light", "Light buggy (FAV)", 0 );
    m = veh_def( m, "vehicle_t9_mil_fav_light_alt", "Light buggy (FAV) alt", 0 );
    m = veh_def( m, "veh_mil_ru_fav_heavy", "Heavy buggy (FAV)", 0 );
    m = veh_def( m, "vehicle_motorcycle_mil_us_offroad", "Motorcycle", 0 );
    m = veh_def( m, "vehicle_motorcycle_mil_us_offroad_alt", "Motorcycle alt", 0 );
    m = veh_def( m, #"hash_4b89aa566bff8383", "Motorcycle (slow)", 0, "vehicle_motorcycle_mil_us_offroad_slow" );
    m = veh_def( m, "veh_quad_player_wz_pc", "Quad / ATV", 0 );
    m = veh_def( m, "vehicle_t9_mil_snowmobile", "Snowmobile", 0 );
    m = veh_def( m, "vehicle_t9_mil_snowmobile_alt", "Snowmobile alt", 0 );
    m = veh_def( m, "vehicle_t9_mil_snowmobile_alt_single_seat", "Snowmobile (single seat)", 0 );
    m = veh_def( m, "vehicle_t9_civ_ru_sedan_80s_player", "Sedan", 0 );
    m = veh_def( m, "vehicle_t9_civ_ru_sedan_80s_player_alt", "Sedan alt", 0 );
    m = veh_def( m, #"hash_985b7e40ee02aa2", "Sedan (BO4 midsize)", 0, "vehicle_t8_soviet_civ_sedan_midsize" );
    m = veh_def( m, "vehicle_t9_mil_ru_truck_light_player", "Light truck", 0 );
    m = veh_def( m, "vehicle_t9_mil_ru_truck_light_player_alt", "Light truck alt", 0 );
    m = veh_def( m, #"hash_1bdb534f1e8e23f5", "Light truck (base)", 0, "vehicle_t9_mil_ru_truck_light" );
    m = veh_def( m, "vehicle_t9_mil_ru_truck_transport_player", "Transport truck", 0 );
    m = veh_def( m, "vehicle_t9_mil_ru_truck_transport_player_alt", "Transport truck alt", 0 );
    m = veh_def( m, "vehicle_t9_mil_ru_truck_transport_player_obj_sr", "Transport truck (objective)", 0 );
    m = veh_def( m, "vehicle_t9_mil_ru_tank_t72_sr", "Tank T-72", 0 );
    m = veh_def( m, "vehicle_t9_mil_ru_tank_t72_alt", "Tank T-72 alt", 0 );
    m = veh_def( m, #"hash_28d512b739c9d9c1", "Tank T-72 (base)", 0, "vehicle_t9_mil_ru_tank_t72" );
    m = veh_def( m, #"hash_1a60a087a340574b", "APC (heavy)", 0, "vehicle_t9_mil_ru_apc_heavy" );
    m = veh_def( m, #"hash_7c54a264a26cb1eb", "APC (heavy, open turret)", 0, "vehicle_t9_mil_ru_apc_heavy_open_turret" );
    m = veh_def( m, #"hash_6595f5efe62a4ec", "Hind gunship", 0, "vehicle_t9_mil_ru_heli_gunship_hind" );
    m = veh_def( m, "vehicle_t9_mil_us_helicopter_large_cp_armada_player", "Armada heli (campaign)", 0 );
    m = veh_def( m, "vehicle_t9_mil_boat_jetski", "Jetski", 0 );
    m = veh_def( m, "vehicle_t9_mil_boat_jetski_alt", "Jetski alt", 0 );
    m = veh_def( m, "vehicle_t9_mil_boat_tactical_raft", "Tactical raft", 0 );
    m = veh_def( m, "vehicle_t9_mil_boat_tactical_raft_alt", "Tactical raft alt", 0 );
    m = veh_def( m, "vehicle_boct_mil_boat_tactical_raft_gry_pc", "Tactical raft (grey)", 0 );
    m = veh_def( m, #"hash_51c4f4dc2591b475", "Tactical raft (grey, base)", 0, "vehicle_boct_mil_boat_tactical_raft_gry" );
    m = veh_def( m, "vehicle_t9_mil_us_boat_pgb_double_gun", "PBR gunboat", 0 );
    m = veh_def( m, "vehicle_t9_mil_us_boat_pgb_double_gun_alt", "PBR gunboat alt", 0 );
    // other resident vehicles: streaks, turrets, the map's intro cinematic. Untested; may not be enterable.
    m = veh_def( m, "veh_t9_mil_us_helicopter_large_chopper_gunner", "Chopper Gunner (streak)", 1 );
    // ⭐ MEASURED FLYABLE ON EVERY MAP (klaze, 2026-09-16). It is in core_common, so it is resident
    // on all 36 MP maps, and it has NO vehiclecustomsettings bundle - which is why it sat at kind=1
    // ("untested, may not be enterable") until it was flown. See vehicles.md §7: the settings-bundle
    // signal is one-directional, and absence is not evidence against drivability. The other universal
    // streak vehicles below are untested candidates for the same promotion.
    m = veh_def( m, "vehicle_t9_mil_helicopter_care_package", "Care package heli - FLIES ON EVERY MAP", 0 );
    m = veh_def( m, #"hash_4209c5ff3b969c7a", "Vehicle-drop heli (streak)", 1, "vehicle_t9_mil_ru_heli_transport_vehicle_drop" );
    m = veh_def( m, "vehicle_t9_rcxd_racing", "RC-XD", 1 );
    m = veh_def( m, "vehicle_t9_rcxd_racing_alt", "RC-XD alt", 1 );
    m = veh_def( m, #"hash_58cc8ce25d32031f", "Exfil chopper (VIP escort)", 1, "hash_58cc8ce25d32031f" );      // vip.gsc:125
    m = veh_def( m, #"hash_437293ae239af1ab", "Exfil helicopter (Fireteam)", 1, "hash_437293ae239af1ab" );     // zm_silver_main_quest.gsc:3031
    m = veh_def( m, "veh_t8_ac130_gunship_mp", "AC-130 gunship (streak)", 1 );
    m = veh_def( m, "veh_t8_helicopter_gunship_mp", "Attack helicopter (streak)", 1 );
    m = veh_def( m, "veh_t8_helicopter_gunship_mp_guard", "Attack helicopter guard (streak)", 1 );
    m = veh_def( m, "vehicle_t9_mil_ru_air_vtol_forger", "VTOL Forger (streak)", 1 );
    m = veh_def( m, "vehicle_straferun_mp", "Strafe run plane (streak)", 1 );
    m = veh_def( m, "vehicle_t9_mil_air_transport_hpc_intro", "Air transport (intro)", 1 );
    m = veh_def( m, "vehicle_t8_mil_air_transport_infiltration", "Air transport (infiltration, BO4)", 1 );
    m = veh_def( m, #"hash_536eec4bf6424551", "Mounted MG tripod", 1, "veh_boct_turret_manned_tripod_mp" );
    m = veh_def( m, #"hash_5477254cf96259f4", "Express train", 1, "veh_boct_train" );
    // the pre-match intro cinematic vehicle of a 6v6 map (scriptbundle/scene/cin_mp_<map>_intro_*)
    m = veh_def( m, #"hash_60868aaa45d05ffe", "Intro cinematic vehicle (Checkmate / Satellite)", 1, "hash_60868aaa45d05ffe" );
    m = veh_def( m, #"hash_550d303ee2de9a65", "Intro cinematic tank (Garrison / Amerika)", 1, "hash_550d303ee2de9a65" );
    m = veh_def( m, #"hash_4dfaa11717f3881", "Intro cinematic vehicle (Garrison)", 1, "hash_4dfaa11717f3881" );
    m = veh_def( m, #"hash_1e00d92ee0b1bf4c", "Intro cinematic vehicle (Miami)", 1, "hash_1e00d92ee0b1bf4c" );
    m = veh_def( m, #"hash_4c21aec4081d030d", "Intro cinematic vehicle (Moscow cia)", 1, "hash_4c21aec4081d030d" );
    m = veh_def( m, #"hash_62d385495a2ba813", "Intro cinematic vehicle (Moscow kgb)", 1, "hash_62d385495a2ba813" );
    m = veh_def( m, #"hash_13c60e71eef46ebb", "Intro cinematic helicopter (The Pines)", 1, "hash_13c60e71eef46ebb" );
    m = veh_def( m, #"hash_5405b8cdc93df2b4", "Intro cinematic APC (The Pines)", 1, "hash_5405b8cdc93df2b4" );
    m = veh_def( m, #"hash_15e59336c36ee995", "Intro cinematic APC (Amerika)", 1, "hash_15e59336c36ee995" );
    m = veh_def( m, #"hash_7c74af55b6caaaf5", "Intro cinematic vehicle (Echelon)", 1, "hash_7c74af55b6caaaf5" );
    m = veh_def( m, #"hash_c07fec522db452c", "Intro cinematic vehicle (Yamantau)", 1, "hash_c07fec522db452c" );
    m = veh_def( m, #"hash_1c5963188cf189df", "Intro cinematic vehicle (Apocalypse)", 1, "hash_1c5963188cf189df" );
    m = veh_def( m, #"hash_20966d639ebe6604", "Intro cinematic vehicle (Cartel)", 1, "hash_20966d639ebe6604" );
    m = veh_def( m, #"hash_4bfd80fe09072db3", "Intro cinematic vehicle (Collateral cia)", 1, "hash_4bfd80fe09072db3" );
    m = veh_def( m, #"hash_3efa223f4a0bffcd", "Intro cinematic vehicle (Collateral kgb)", 1, "hash_3efa223f4a0bffcd" );
    m = veh_def( m, #"hash_1f5c1aa7b1348d33", "Intro cinematic vehicle (Crossroads kgb)", 1, "hash_1f5c1aa7b1348d33" );
    m = veh_def( m, #"hash_3463002d802c1a98", "Intro cinematic vehicle (Crossroads)", 1, "hash_3463002d802c1a98" );
    m = veh_def( m, #"hash_581bb1b0fa4a3139", "Intro cinematic vehicle (Crossroads kgb 2)", 1, "hash_581bb1b0fa4a3139" );
    m = veh_def( m, #"hash_61b8f8f61f4b9ce7", "Intro cinematic vehicle (Crossroads cia)", 1, "hash_61b8f8f61f4b9ce7" );
    level.gf_veh_master = m;
    return m;
}

// Is this master key an aircraft? By the plain name (e.text carries it for hashed keys): every
// heli / chopper / gunship / VTOL / plane / air transport / AC-130 / strafe run in the master
// matches one of these; "boat_pgb_double_gun" does not ("gunship" is the token, not "gun").
function private veh_is_air_key( key )
{
    text = undefined;

    foreach ( e in veh_master() )
    {
        if ( e.key === key )
        {
            text = e.text;
            break;
        }
    }

    if ( !isdefined( text ) )
        text = isstring( key ) ? key : "";

    text = tolower( text );
    return veh_text_has( text, "heli" ) || veh_text_has( text, "chopper" ) || veh_text_has( text, "gunship" )
        || veh_text_has( text, "vtol" ) || veh_text_has( text, "plane" ) || veh_text_has( text, "air_transport" )
        || veh_text_has( text, "ac130" ) || veh_text_has( text, "straferun" );
}

// Substring test (GSC has no builtin for it): does `s` contain `sub`?
function private veh_text_has( s, sub )
{
    if ( sub.size == 0 || s.size < sub.size )
        return false;

    for ( i = 0; i + sub.size <= s.size; i++ )
    {
        if ( getsubstr( s, i, i + sub.size ) == sub )
            return true;
    }

    return false;
}

// Rows for one page: every master entry of `kind` resident on this map. Returns the count.
function private veh_page_rows( page, kind )
{
    n = 0;

    foreach ( e in veh_master() )
    {
        if ( e.kind != kind || !isassetloaded( "vehicle", e.key ) )
            continue;

        self menu_item( page, "Spawn " + e.label, &veh_spawn, e.key );
        n++;
    }

    return n;
}

// The Vehicles page + its "other" sub-page, from what THIS map has resident.
function private veh_page_build()
{
    n = self veh_page_rows( "vehicles", 0 );

    if ( n == 0 )
        self menu_item( "vehicles", "(no drivable vehicle assets on this map)", undefined );

    self menu_item( "vehicles", "Enter vehicle I am aiming at", &veh_enter );
    self menu_item( "vehicles", "Remove empty spawned vehicles", &act_vehclear );
    self menu_add( "veh_other", "Other resident vehicles - streaks / intro, untested", "vehicles", 1 );

    if ( self veh_page_rows( "veh_other", 1 ) == 0 )
        self menu_item( "veh_other", "(none resident on this map)", undefined );
}

// The resident vehicle keys as one comma list (the GFMAPVEH channel); kind -1 = all.
function private veh_resident_list( kind )
{
    out = "";

    foreach ( e in veh_master() )
    {
        if ( ( kind >= 0 && e.kind != kind ) || !isassetloaded( "vehicle", e.key ) )
            continue;

        out += ( out == "" ? "" : "," ) + e.text;
    }

    return out;
}

// ── GAME->APP map census: three marked strings tools/gf-control/mapdata_scan.py sweeps ──
// The roster channel's sibling (roster_publish): a marked string alive in a level field is
// found by the app's read-only memory sweep. One line per subject so none grows past the
// script string budget; markers assembled at runtime so the payload's own string table
// carries no decoy. Built once the level has settled, held for the whole level; the app
// files them per map (mapdata/<map>.json) - the per-map database fills itself as klaze
// plays. Formats (docs/notes/map-data.md):
//   GFMAPVEH|<map>|<gametype>|<key>,<key>,...|END          resident vehicles, drivables first
//   GFMAPPROP|<map>|tbl=1|rows=13|<model>:<size>,...|END   the Prop Hunt table (first 48 rows)
//   GFMAPSPAWN|<map>|<STARTS tally>|<family note>|END      the spawn keys read on this map
//   GFMAPDEST|<map>|n=<count>|kinds=<k>|<def>x<count>,...|END  the destructibles, by real def name
function private mapdata_publish()
{
    if ( isdefined( level.gf_mapdata_v ) )
        return;                            // this level already published

    level endon( #"game_ended" );
    wait 6;

    map = getdvarstring( #"sv_mapname", "?" );
    gt = tolower( getdvarstring( #"g_gametype", "?" ) );

    level.gf_mapdata_v = "GFMAP" + "VEH|" + map + "|" + gt + "|" + veh_resident_list( 0 ) + "|" + veh_resident_list( 1 ) + "|END";

    props = "tbl=0";
    mapname = level.script;
    if ( !isdefined( mapname ) )
        mapname = util::get_map_name();
    path = "gamedata/tables/mp/" + mapname + "_ph.csv";

    if ( isassetloaded( "stringtable", path ) )
    {
        numrows = tablelookuprowcount( path );
        if ( !isdefined( numrows ) )
            numrows = 0;

        props = "tbl=1|rows=" + numrows + "|";
        for ( i = 0; i < numrows && i < 48; i++ )
        {
            model = assets_table_cell( path, i, 0 );
            size = assets_table_cell( path, i, 1 );
            props += ( i > 0 ? "," : "" ) + model + ":" + size;
        }
    }

    level.gf_mapdata_p = "GFMAP" + "PROP|" + map + "|" + props + "|END";

    note = isdefined( level.gf_family_note ) ? level.gf_family_note : "";
    level.gf_mapdata_s = "GFMAP" + "SPAWN|" + map + "|" + mod_starts_tally() + " NAMED" + mod_named_tally( mod_gather_spawns() ) + mod_groups_tally() + "|" + note + "|END";

    dt = destruct_tally();
    level.gf_mapdata_d = "GFMAP" + "DEST|" + map + "|n=" + dt.n + "|kinds=" + dt.names.size + "|" + destruct_tally_text( dt, 40 ) + "|END";
}

function private veh_spawn( item, type )
{
    if ( !isassetloaded( "vehicle", type ) )
    {
        self menu_say( "^1no vehicle assets on this map - try a 12v12-layout map" );
        return true;
    }

    ang = self getplayerangles();
    flat = ( 0, ang[ 1 ], 0 );                                   // level, keep the yaw
    spot = self.origin + vectorscale( anglestoforward( flat ), 250 ) + ( 0, 0, 25 );

    // Air vehicles spawn ABOVE the host, not on the ground ahead (klaze 2026-09-18: "so they
    // aren't stuck in the ground"): gf_veh_alt (300) up, ceiling-traced, a little ahead so a
    // descending heli does not land on him. The asset is judged by its name (veh_is_air_key) -
    // the spawned entity's isairborne() only answers after the spawn has already placed it.
    if ( veh_is_air_key( type ) )
        spot = veh_mode_air_spot( self.origin + vectorscale( anglestoforward( flat ), 120 ), cfg_veh_alt() );

    veh = spawnvehicle( type, spot, flat );

    if ( !isdefined( veh ) )
    {
        self menu_say( "^1spawn failed" );
        return true;
    }

    veh makeusable();
    veh.gf_spawned = 1;                        // ours: the round-end sweep / act_vehclear delete it

    if ( isdefined( veh.isphysicsvehicle ) && veh.isphysicsvehicle )
        veh setbrake( 1 );

    // One frame for the entity to settle where it was placed before the rotor spins up
    // (bocw-0f, 2026-09-18: rotor-on in the same frame as a possibly embedded spawn is the
    // physics-risky combination).
    if ( isairborne( veh ) )
    {
        waitframe( 1 );

        if ( !isdefined( veh ) )
        {
            self menu_say( "^1spawn failed" );
            return true;
        }

        veh setrotorspeed( 1.0 );
    }

    self menu_say( "^2vehicle spawned ahead - walk into it and hold Use" );
    return true;
}

function private veh_enter( item )
{
    eye = self geteye();
    tr = bullettrace( eye, eye + vectorscale( anglestoforward( self getplayerangles() ), 400 ), 1, self );
    ent = tr[ #"entity" ];

    if ( isdefined( ent ) && isvehicle( ent ) )
    {
        ent usevehicle( self, 0 );
        self menu_say( "^2entering" );
    }
    else
    {
        self menu_say( "^1look right at a vehicle first" );
    }

    return true;
}

// ═════════════════════════════════════════════════════════════════════════════
// VEHICLE MODE — everyone spawns already riding. docs/notes/vehicle-mode.md
// klaze, 2026-09-17: "on maps with motorcycles, players spawn already driving one and
// cannot get off it, so it's a gunfight on bikes. and maybe gunfight in attack helicopters."
// ═════════════════════════════════════════════════════════════════════════════
// Mechanism = stock's own spawn-in-vehicle shape, the Fireteam squad spawn
// (spawning_squad.gsc:1578 spawninvehicle, reached from spawning_shared.gsc:250 right after
// self spawn( origin, angles )):
//     player.var_5a44792f = 1;   vehicle usevehicle( player, seat );
// The flag makes vehicle_shared's enter handler return before the enter animation
// (vehicle_shared.gsc:5362 codecallback_vehicleenter), so the rider is seated the instant
// the spawn lands. The vehicle itself is Path B (vehicles.md §1): spawnvehicle( key, spot,
// yaw ) at the player's spawn point, key gated on isassetloaded( "vehicle", key ) with the
// PLAIN-STRING type argument (the hashed form says yes to everything - vehicles.md §5), so a
// class whose ride this map does not carry leaves everyone on foot and says so.
//
// "Cannot get off" - two layers, neither measured yet:
//  (a) the registered player value disable_usability (values_shared.gsc:59 -> disableusability(),
//      what Fireteam's parachute insertion sets while the player is in the air,
//      player_insertion.gsc:2464), layered on the rider under our own id gf_veh. Leaving a
//      vehicle is a hold-Use action (vehicle.showHoldToExitPrompt, vehicle_shared.gsc:90), so
//      this is expected to swallow it. Stock nukes every value layer per spawn
//      (globallogic_spawn.gsc:612), so it is set per life, after the seat.
//  (b) belt and braces: a per-life watcher re-seats the rider the frame the engine reports
//      him out of the driver's seat. ⚠ usevehicle TOGGLES - on a seated player it is the
//      exit, which is exactly how stock ejects occupants (vehicle_death_shared.gsc:307,
//      bot_devgui.gsc:935) - so the watcher only calls it while seat 0 is actually empty,
//      and gives up after 20 re-seats in one life rather than fight the engine every frame.
// A vehicle's death kills its occupants (player_vehicle.gsc:101 vehkilloccupantsondeath = 1),
// so a downed Hind is an elimination with stock attribution; a rider shot off a bike is a
// plain player death and the empty bike is deleted 3 s later.
//
// Ground rides spawn at the spawn point, braked until the pre-round countdown ends (stock's
// enter handler RELEASES the brake, player_vehicle.gsc:1266, so it is re-set after the
// seat). Air rides spawn at GO instead - a frozen pilot's heli would drift into the map -
// gf_veh_alt above the spawn point, ceiling-traced, rotor up (the veh_spawn shape).
//
// Config (plain dvars, NOT the packed store - inserting a packed key shifts every chunk
// position for a stale app, the gf_oob precedent):
//   gf_vehmode  0 off | 1 bikes | 2 attack helis (Hind) | 3 care-package heli (every map) |
//               4 snowmobiles | 5 quads + buggies | 6 tanks + APCs | 7 cars + trucks |
//               8 streak gunship (universal asset, seat UNTESTED) | 9 AUTO (1,4,5,7,6,3 first hit)
//   gf_veh_lock 1 = locked in (default) / 0 = free to leave
//   gf_veh_hp   vehicle health in PERCENT of the asset's default, 100 = stock
//   gf_veh_alt  air spawn height above the spawn point (units), default 300
//   gf_dbg_veh  1 = the VEHMODE debug line in the feed (one line, every 3 s)
// Per-map coverage is offline data (docs/data/map-assets.json, vehicles.md §6-7): bikes on
// Diesel / Cartel / Collateral / the Fireteam maps, the Hind on Collateral + Fireteam maps,
// snowmobiles on Crossroads / Alpine, quads + buggies on Collateral + Fireteam, tanks on
// Crossroads (APCs on Diesel / Checkmate), the care package heli everywhere (measured flying
// on every map, klaze 2026-09-16). A hashed key below is the FNV1a64 of the plain name it is
// commented with (verified: all of veh_master's hashed labels hash back exactly).

function private cfg_vehmode()  { return cfg_geti( #"gf_vehmode", 0 ); }
function private cfg_veh_lock() { return cfg_geti( #"gf_veh_lock", 1 ); }
function private cfg_veh_hp()   { return cfg_geti( #"gf_veh_hp", 100 ); }
function private cfg_veh_alt()  { return cfg_geti( #"gf_veh_alt", 300 ); }
function private cfg_dbg_veh()  { return cfg_geti( #"gf_dbg_veh", 0 ); }

// One class = a name, air or ground, and an ORDERED candidate list; the first key resident
// on this map (and not retired by a failed seat) is the round's ride.
function private veh_mode_def( id, name, air )
{
    cls = spawnstruct();
    cls.id = id;
    cls.name = name;
    cls.air = air;
    cls.klist = [];
    cls.tlist = [];
    return cls;
}

function private veh_mode_add( cls, key, text )
{
    cls.klist[ cls.klist.size ] = key;
    cls.tlist[ cls.tlist.size ] = text;
    return cls;
}

function private veh_mode_classes()
{
    if ( isdefined( level.gf_vm_classes ) )
        return level.gf_vm_classes;

    c = [];

    k = veh_mode_def( 1, "BIKES", 0 );
    k = veh_mode_add( k, "vehicle_motorcycle_mil_us_offroad", "motorcycle" );
    k = veh_mode_add( k, "vehicle_motorcycle_mil_us_offroad_alt", "motorcycle alt" );
    k = veh_mode_add( k, #"hash_4b89aa566bff8383", "motorcycle slow" );                 // vehicle_motorcycle_mil_us_offroad_slow (Cartel)
    c[ 1 ] = k;

    k = veh_mode_def( 2, "ATTACK HELIS", 1 );
    k = veh_mode_add( k, #"hash_6595f5efe62a4ec", "Hind gunship" );                     // vehicle_t9_mil_ru_heli_gunship_hind (Collateral, Fireteam maps)
    c[ 2 ] = k;

    k = veh_mode_def( 3, "HELIS ANY MAP", 1 );
    k = veh_mode_add( k, "vehicle_t9_mil_helicopter_care_package", "care package heli" );   // core_common: every MP map, flies (klaze 09-16)
    c[ 3 ] = k;

    k = veh_mode_def( 4, "SNOWMOBILES", 0 );
    k = veh_mode_add( k, "vehicle_t9_mil_snowmobile_alt_single_seat", "snowmobile single seat" );
    k = veh_mode_add( k, "vehicle_t9_mil_snowmobile", "snowmobile" );
    k = veh_mode_add( k, "vehicle_t9_mil_snowmobile_alt", "snowmobile alt" );
    c[ 4 ] = k;

    k = veh_mode_def( 5, "QUADS + BUGGIES", 0 );
    k = veh_mode_add( k, "veh_quad_player_wz_pc", "quad / ATV" );
    k = veh_mode_add( k, "vehicle_t9_mil_fav_light", "light buggy (FAV)" );
    k = veh_mode_add( k, "vehicle_t9_mil_fav_light_alt", "light buggy (FAV) alt" );
    k = veh_mode_add( k, "veh_mil_ru_fav_heavy", "heavy buggy (FAV)" );
    c[ 5 ] = k;

    k = veh_mode_def( 6, "TANKS + APCS", 0 );
    k = veh_mode_add( k, "vehicle_t9_mil_ru_tank_t72_sr", "tank T-72" );
    k = veh_mode_add( k, #"hash_28d512b739c9d9c1", "tank T-72 (base)" );                // vehicle_t9_mil_ru_tank_t72
    k = veh_mode_add( k, "vehicle_t9_mil_ru_tank_t72_alt", "tank T-72 alt" );
    k = veh_mode_add( k, #"hash_1a60a087a340574b", "APC (heavy)" );                     // vehicle_t9_mil_ru_apc_heavy (Diesel, Checkmate)
    k = veh_mode_add( k, #"hash_7c54a264a26cb1eb", "APC (heavy, open turret)" );        // vehicle_t9_mil_ru_apc_heavy_open_turret
    c[ 6 ] = k;

    k = veh_mode_def( 7, "CARS + TRUCKS", 0 );
    k = veh_mode_add( k, "vehicle_t9_civ_ru_sedan_80s_player", "sedan" );
    k = veh_mode_add( k, "vehicle_t9_civ_ru_sedan_80s_player_alt", "sedan alt" );
    k = veh_mode_add( k, "vehicle_t9_mil_ru_truck_light_player", "light truck" );
    k = veh_mode_add( k, "vehicle_t9_mil_ru_truck_light_player_alt", "light truck alt" );
    k = veh_mode_add( k, #"hash_1bdb534f1e8e23f5", "light truck (base)" );              // vehicle_t9_mil_ru_truck_light (Cartel)
    k = veh_mode_add( k, "vehicle_t9_mil_ru_truck_transport_player", "transport truck" );
    k = veh_mode_add( k, "vehicle_t9_mil_ru_truck_transport_player_alt", "transport truck alt" );
    c[ 7 ] = k;

    // The MP Attack Helicopter streak asset: universal (core_common + mp_common) and a gunship,
    // but AI-flown in stock - whether seat 0 takes a player is exactly what a run measures.
    // A failed seat retires the key for the match (veh_mode_ride), so trying costs one round.
    k = veh_mode_def( 8, "STREAK GUNSHIP", 1 );
    k = veh_mode_add( k, "veh_t8_helicopter_gunship_mp", "attack heli (streak asset)" );
    k = veh_mode_add( k, "veh_t8_helicopter_gunship_mp_guard", "attack heli guard (streak asset)" );
    c[ 8 ] = k;

    level.gf_vm_classes = c;
    return c;
}

function private veh_mode_class( id )
{
    c = veh_mode_classes();

    if ( isdefined( c[ id ] ) )
        return c[ id ];

    return undefined;
}

function private veh_mode_name( mode )
{
    if ( mode <= 0 )
        return "OFF";
    if ( mode == 9 )
        return "AUTO";

    cls = veh_mode_class( mode );
    return isdefined( cls ) ? cls.name : ( "mode " + mode );
}

// The per-round counters the VEHMODE feed line reads (level is rebuilt every round).
function private veh_mode_state()
{
    if ( !isdefined( level.gf_vm ) )
    {
        st = spawnstruct();
        st.spawned = 0;   // spawnvehicle calls
        st.seated = 0;    // riders confirmed in seat 0 a frame later
        st.fail = 0;      // spawn returned undefined / the seat did not take
        st.exits = 0;     // frames the watcher found a rider out of the seat
        st.reseat = 0;    // usevehicle re-seats it issued
        st.shots = 0;     // weapon_fired notifies from seated riders (can the rider shoot?)
        st.gaveup = 0;    // riders whose watcher hit the 20 re-seat cap
        level.gf_vm = st;
    }

    return level.gf_vm;
}

// Resolve this map's ride for the configured mode: the first candidate of the class (AUTO:
// classes 1,4,5,7,6,3 in that order) that is resident and not retired. Cached on level for
// the round; veh_mode_refresh drops the cache so a mid-round mode change re-resolves.
function private veh_mode_resolve()
{
    level.gf_veh_resolved = 1;
    level.gf_veh_key = undefined;
    level.gf_veh_text = "-";
    level.gf_veh_cls = undefined;
    mode = cfg_vehmode();

    if ( mode <= 0 )
        return 0;

    if ( !isdefined( game.gf_veh_dead ) )
        game.gf_veh_dead = [];

    order = [];

    if ( mode == 9 )
    {
        order[ 0 ] = 1;
        order[ 1 ] = 4;
        order[ 2 ] = 5;
        order[ 3 ] = 7;
        order[ 4 ] = 6;
        order[ 5 ] = 3;
    }
    else
    {
        order[ 0 ] = mode;
    }

    foreach ( id in order )
    {
        cls = veh_mode_class( id );

        if ( !isdefined( cls ) )
            continue;

        for ( i = 0; i < cls.klist.size; i++ )
        {
            if ( isdefined( game.gf_veh_dead[ id * 100 + i ] ) )
                continue;                                   // retired: would not seat a player this match

            if ( !isassetloaded( "vehicle", cls.klist[ i ] ) )
                continue;

            level.gf_veh_key = cls.klist[ i ];
            level.gf_veh_text = cls.tlist[ i ];
            level.gf_veh_cls = cls;
            level.gf_veh_slot = id * 100 + i;
            return 1;
        }
    }

    return 0;
}

function private veh_mode_key()
{
    if ( !isdefined( level.gf_veh_resolved ) )
        veh_mode_resolve();

    return level.gf_veh_key;
}

// Round start (mod_apply, every gametype): resolve and tell the host what this round rides.
function private veh_mode_announce()
{
    level.gf_veh_resolved = undefined;

    if ( cfg_vehmode() <= 0 )
        return;

    if ( veh_mode_resolve() )
        mod_host_say( "^3vehicle mode ^7" + veh_mode_name( cfg_vehmode() ) + " -> " + level.gf_veh_text + ( cfg_veh_lock() ? " (locked in)" : " (free to leave)" ) );
    else
        mod_host_say( "^1vehicle mode " + veh_mode_name( cfg_vehmode() ) + ": no such ride resident on this map - everyone on foot" );
}

// on_spawned, every player, bots included (a bot sits still, a target on wheels).
function private mod_spawn_vehicle()
{
    if ( !isplayer( self ) || cfg_vehmode() <= 0 )
        return;

    self thread veh_mode_ride( 0 );
}

// One life's ride: spawn the vehicle at the rider's spawn point, seat him the stock way,
// hold / lock / clean up. now = 1 when re-applied mid-round (a frame's grace for a dismount).
function private veh_mode_ride( now )
{
    self endon( #"disconnect" );
    self endon( #"death" );
    self notify( #"gf_veh_ride_restart" );   // never two per life
    self endon( #"gf_veh_ride_restart" );

    if ( now )
        waitframe( 1 );

    key = veh_mode_key();

    if ( !isdefined( key ) || !isalive( self ) || self isinvehicle() )
        return;

    cls = level.gf_veh_cls;
    st = veh_mode_state();

    // Air: a heli with a frozen pilot drifts into the map - spawn it at GO. Ground rides sit
    // braked through the countdown instead (below), so the riders see themselves mounted.
    if ( cls.air )
    {
        while ( is_true( level.inprematchperiod ) )
            waitframe( 1 );

        if ( !isalive( self ) || self isinvehicle() )
            return;
    }

    ang = self getplayerangles();
    yaw = ( 0, ang[ 1 ], 0 );                 // level, facing the way the spawn faces
    spot = self.origin + ( 0, 0, 12 );

    if ( cls.air )
        spot = veh_mode_air_spot( self.origin, cfg_veh_alt() );

    veh = spawnvehicle( key, spot, yaw );
    st.spawned++;

    if ( !isdefined( veh ) )
    {
        st.fail++;
        return;
    }

    veh.gf_veh_mode = 1;
    veh.gf_veh_rider = self;
    veh thread veh_mode_life( self );        // owns the cleanup from here on

    self.var_5a44792f = 1;                   // stock's spawn-in-vehicle flag: no enter animation
    veh usevehicle( self, 0 );
    waitframe( 1 );

    if ( !isdefined( veh ) )
    {
        st.fail++;
        return;
    }

    if ( !self isinvehicle() )
    {
        // This asset takes no player at seat 0 here. Retire the key for the match so the next
        // round falls through to the class's next candidate (or on foot), and say so once.
        st.fail++;
        game.gf_veh_dead[ level.gf_veh_slot ] = 1;
        level.gf_veh_resolved = undefined;
        veh delete();
        mod_host_say( "^1vehicle mode: " + level.gf_veh_text + " would not seat " + self.name + " - retired for this match" );
        return;
    }

    st.seated++;
    self.gf_veh = veh;
    self.gf_veh_reseats = 0;
    veh_mode_hp_apply( veh );

    if ( cls.air )
        veh setrotorspeed( 1.0 );            // a frame after the spawn, with the pilot aboard

    if ( !cls.air )
        self thread veh_mode_hold( veh );

    if ( cfg_veh_lock() )
        self val::set( #"gf_veh", "disable_usability", 1 );

    self thread veh_mode_lock_think( veh );
    self thread veh_mode_shots_think( veh );
}

// gf_veh_alt above the spawn point, but under any ceiling: trace up, keep 120 u of clearance
// (a Hind is ~110 u tall with the rotor). An indoor spawn still gets its heli, just low.
function private veh_mode_air_spot( origin, alt )
{
    if ( alt < 40 )
        alt = 40;

    top = origin + ( 0, 0, alt + 120 );
    tr = bullettrace( origin + ( 0, 0, 8 ), top, 0, undefined );
    room = tr[ #"position" ][ 2 ] - origin[ 2 ] - 120;

    if ( room < alt )
        alt = room;

    if ( alt < 40 )
        alt = 40;

    return origin + ( 0, 0, alt );
}

// Ground rides: brake through the pre-round countdown (stock released it on the seat), off at GO.
function private veh_mode_hold( veh )
{
    self endon( #"death", #"disconnect", #"gf_veh_release" );
    veh endon( #"death" );

    if ( !is_true( veh.isphysicsvehicle ) )
        return;

    veh setbrake( 1 );

    while ( is_true( level.inprematchperiod ) )
        waitframe( 1 );

    if ( isdefined( veh ) )
        veh setbrake( 0 );
}

// The re-seat watcher (layer b). Reads gf_veh_lock live: the host can free the riders mid-round.
function private veh_mode_lock_think( veh )
{
    self notify( #"gf_veh_lock_restart" );
    self endon( #"gf_veh_lock_restart", #"death", #"disconnect", #"gf_veh_release" );
    veh endon( #"death" );
    st = veh_mode_state();

    for ( ;; )
    {
        waitframe( 1 );

        if ( !isdefined( veh ) )
            return;

        if ( !cfg_veh_lock() )
            continue;

        if ( self isinvehicle() )
        {
            // Still aboard. A seat change (the bike has a passenger seat) leaves the driver's
            // seat empty: hop back - exit (toggle) this frame, re-enter seat 0 the next.
            if ( self getvehicleoccupied() == veh && veh getoccupantseat( self ) != 0 && !veh isvehicleseatoccupied( 0 ) )
            {
                veh usevehicle( self, veh getoccupantseat( self ) );
                waitframe( 1 );

                if ( isdefined( veh ) && isalive( self ) && !self isinvehicle() )
                {
                    self.var_5a44792f = 1;
                    veh usevehicle( self, 0 );
                    st.reseat++;
                }
            }

            continue;
        }

        st.exits++;

        if ( veh isvehicleseatoccupied( 0 ) )
            continue;                           // mid-exit: the engine still counts him in the seat

        if ( self.gf_veh_reseats >= 20 )
        {
            if ( self.gf_veh_reseats == 20 )
            {
                st.gaveup++;
                self.gf_veh_reseats++;
                mod_host_say( "^1vehicle mode: " + self.name + " keeps leaving his ride - re-seat cap hit, letting him" );
            }

            continue;
        }

        self.var_5a44792f = 1;
        veh usevehicle( self, 0 );
        self.gf_veh_reseats++;
        st.reseat++;
    }
}

// Debug: does a seated rider's own weapon fire at all (the bike's driver seat may forbid it)?
function private veh_mode_shots_think( veh )
{
    self notify( #"gf_veh_shots_restart" );
    self endon( #"gf_veh_shots_restart", #"death", #"disconnect", #"gf_veh_release" );
    veh endon( #"death" );
    st = veh_mode_state();

    for ( ;; )
    {
        self waittill( #"weapon_fired" );

        if ( self isinvehicle() )
            st.shots++;
    }
}

// On the vehicle: when its rider dies or leaves the match, delete the empty ride 3 s later. A
// DESTROYED vehicle ends this first (endon death) - stock's wreck handling owns that case.
function private veh_mode_life( player )
{
    self endon( #"death" );
    player waittill( #"death", #"disconnect" );
    wait 3;

    if ( isdefined( self ) && veh_mode_empty( self ) )
        self delete();
}

function private veh_mode_delete_soon( delay )
{
    self endon( #"death" );
    wait delay;

    if ( isdefined( self ) && veh_mode_empty( self ) )
        self delete();
}

function private veh_mode_empty( veh )
{
    occ = veh getvehoccupants();
    return !isdefined( occ ) || occ.size == 0;
}

// gf_veh_hp: scale the asset's default health (player_vehicle.gsc:1301 reads healthdefault
// into maxhealth on the first enter; both are written so the HUD bar and the kill agree).
function private veh_mode_hp_apply( veh )
{
    pct = cfg_veh_hp();

    if ( pct <= 0 || pct == 100 )
        return;

    base = isdefined( veh.healthdefault ) ? veh.healthdefault : veh.health;

    if ( !isdefined( base ) || base <= 0 )
        return;

    hp = int( base * pct / 100 );

    if ( hp < 1 )
        hp = 1;

    veh.maxhealth = hp;
    veh.health = hp;
}

// Free one rider: lock layer off, out of the seat (usevehicle toggles), the ride deleted once empty.
function private veh_mode_dismount()
{
    self notify( #"gf_veh_release" );
    self val::reset( #"gf_veh", "disable_usability" );
    veh = self.gf_veh;
    self.gf_veh = undefined;

    if ( !isdefined( veh ) )
        return;

    if ( self isinvehicle() && self getvehicleoccupied() == veh )
        veh usevehicle( self, veh getoccupantseat( self ) );

    veh thread veh_mode_delete_soon( 0.5 );
}

// Mid-round apply (menu "Apply to everyone alive NOW", the app's Apply now with the veh scope):
// everyone alive dismounts, then remounts the (re-resolved) ride if the mode is on.
function private veh_mode_refresh()
{
    level.gf_veh_resolved = undefined;
    on = ( cfg_vehmode() > 0 && isdefined( veh_mode_key() ) );

    foreach ( p in getplayers() )
    {
        if ( !isalive( p ) )
            continue;

        if ( isdefined( p.gf_veh ) )
            p veh_mode_dismount();

        if ( on )
            p thread veh_mode_ride( 1 );
    }
}

// The timer tiebreak (mod_ontimelimit) sums player health; a rider's armour is his vehicle,
// so a full-health ride counts +100 for its side (0..100 by health fraction).
function private veh_mode_hp_bonus( p )
{
    if ( !isdefined( p.gf_veh ) || !isalive( p.gf_veh ) || !p isinvehicle() )
        return 0;

    mh = isdefined( p.gf_veh.maxhealth ) ? p.gf_veh.maxhealth : p.gf_veh.healthdefault;

    if ( !isdefined( mh ) || mh <= 0 )
        return 0;

    return int( 100 * p.gf_veh.health / mh );
}

// The VEHMODE debug line (gf_dbg_veh): every data point, one line, re-printed every 3 s.
function private veh_line()
{
    st = veh_mode_state();
    mode = cfg_vehmode();
    key = veh_mode_key();
    riding = 0;
    alive = 0;
    vhp = "-";

    foreach ( p in getplayers() )
    {
        if ( !isalive( p ) )
            continue;

        alive++;

        if ( isdefined( p.gf_veh ) && p isinvehicle() )
        {
            riding++;

            if ( isdefined( p.gf_veh.health ) )
                vhp = "" + int( p.gf_veh.health );
        }
    }

    vehs = getvehiclearray();
    nveh = isdefined( vehs ) ? vehs.size : 0;
    resolved = isdefined( key ) ? 1 : 0;

    return "^3VEHMODE ^7" + veh_mode_name( mode ) + " ^5" + level.gf_veh_text + " ^7res:" + resolved
        + " air:" + ( ( isdefined( level.gf_veh_cls ) && level.gf_veh_cls.air ) ? 1 : 0 )
        + " riding:" + riding + "/" + alive + " vehs:" + nveh + " lastvhp:" + vhp
        + " ^3spawned:" + st.spawned + " seated:" + st.seated + " fail:" + st.fail
        + " exits:" + st.exits + " reseat:" + st.reseat + " gaveup:" + st.gaveup + " shots:" + st.shots
        + " ^7pre:" + ( is_true( level.inprematchperiod ) ? 1 : 0 ) + " lock:" + cfg_veh_lock() + " hp:" + cfg_veh_hp() + "% alt:" + cfg_veh_alt();
}

// ── Menu: Vehicles -> "Vehicle MODE" page + options ─────────────────────────
function private veh_mode_page_build()
{
    self menu_add( "vehmode", "Vehicle MODE - everyone spawns riding", "vehicles", 1 );
    self menu_item( "vehmode", "Mode OFF - on foot", &act_vehmode, 0, undefined, #"gf_vehmode", 0 );
    self menu_item( "vehmode", "Motorcycles - Diesel / Cartel / Collateral / Fireteam maps", &act_vehmode, 1, undefined, #"gf_vehmode", 1 );
    self menu_item( "vehmode", "Attack helicopters - Hind: Collateral / Fireteam maps", &act_vehmode, 2, undefined, #"gf_vehmode", 2 );
    self menu_item( "vehmode", "Helicopters ANY map - care package heli, unarmed", &act_vehmode, 3, undefined, #"gf_vehmode", 3 );
    self menu_item( "vehmode", "Snowmobiles - Crossroads / Alpine", &act_vehmode, 4, undefined, #"gf_vehmode", 4 );
    self menu_item( "vehmode", "Quads + buggies - Collateral / Fireteam maps", &act_vehmode, 5, undefined, #"gf_vehmode", 5 );
    self menu_item( "vehmode", "Tanks + APCs - Crossroads; APC on Diesel / Checkmate", &act_vehmode, 6, undefined, #"gf_vehmode", 6 );
    self menu_item( "vehmode", "Cars + trucks - Cartel / Fireteam maps", &act_vehmode, 7, undefined, #"gf_vehmode", 7 );
    self menu_item( "vehmode", "Streak gunship heli - ANY map, seat UNTESTED", &act_vehmode, 8, undefined, #"gf_vehmode", 8 );
    self menu_item( "vehmode", "AUTO - this map's lightest ride, else the care package heli", &act_vehmode, 9, undefined, #"gf_vehmode", 9 );
    self menu_item( "vehmode", "Apply to everyone alive NOW", &act_vehmode_now );
    self menu_add( "vehmode_opt", "Vehicle mode options", "vehmode", 1 );
    self menu_item( "vehmode_opt", "Locked in - cannot get off (default)", &act_veh_lock, 1, undefined, #"gf_veh_lock", 1 );
    self menu_item( "vehmode_opt", "Free - may get off", &act_veh_lock, 0, undefined, #"gf_veh_lock", 0 );
    self menu_item( "vehmode_opt", "Vehicle HP 25%", &act_veh_hp, 25, undefined, #"gf_veh_hp", 25 );
    self menu_item( "vehmode_opt", "Vehicle HP 50%", &act_veh_hp, 50, undefined, #"gf_veh_hp", 50 );
    self menu_item( "vehmode_opt", "Vehicle HP 100% - stock", &act_veh_hp, 100, undefined, #"gf_veh_hp", 100 );
    self menu_item( "vehmode_opt", "Vehicle HP 200%", &act_veh_hp, 200, undefined, #"gf_veh_hp", 200 );
    self menu_item( "vehmode_opt", "Vehicle HP 400%", &act_veh_hp, 400, undefined, #"gf_veh_hp", 400 );
    self menu_item( "vehmode_opt", "Heli spawn height 150", &act_veh_alt, 150, undefined, #"gf_veh_alt", 150 );
    self menu_item( "vehmode_opt", "Heli spawn height 300 - default", &act_veh_alt, 300, undefined, #"gf_veh_alt", 300 );
    self menu_item( "vehmode_opt", "Heli spawn height 600", &act_veh_alt, 600, undefined, #"gf_veh_alt", 600 );
    self menu_item( "vehmode_opt", "Heli spawn height 1000", &act_veh_alt, 1000, undefined, #"gf_veh_alt", 1000 );
    self menu_item( "vehmode_opt", "Debug line: VEHMODE to the feed", &act_dbg_veh, undefined, undefined, #"gf_dbg_veh", 1 );
}

function private act_vehmode( item, mode )
{
    cfg_seti( #"gf_vehmode", mode );
    level.gf_veh_resolved = undefined;

    if ( mode <= 0 )
    {
        self menu_say( "^2vehicle mode OFF - next spawn on foot (Apply NOW frees everyone alive)" );
        return true;
    }

    if ( veh_mode_resolve() )
        self menu_say( "^2vehicle mode " + veh_mode_name( mode ) + " -> " + level.gf_veh_text + " from the next spawn (or Apply NOW)" );
    else
        self menu_say( "^1vehicle mode " + veh_mode_name( mode ) + ": no such ride resident on this map - everyone stays on foot" );

    return true;
}

function private act_vehmode_now( item )
{
    veh_mode_refresh();
    self menu_say( cfg_vehmode() > 0 ? "^2vehicle mode applied to everyone alive" : "^2everyone alive dismounted" );
    return true;
}

function private act_veh_lock( item, value )
{
    cfg_seti( #"gf_veh_lock", value );

    // Live: the watcher reads the dvar; the usability layer follows it here.
    foreach ( p in getplayers() )
    {
        if ( !isdefined( p.gf_veh ) )
            continue;

        if ( value )
            p val::set( #"gf_veh", "disable_usability", 1 );
        else
            p val::reset( #"gf_veh", "disable_usability" );
    }

    self menu_say( value ? "^2riders locked in - cannot get off" : "^2riders free to get off" );
    return true;
}

function private act_veh_hp( item, value )
{
    cfg_seti( #"gf_veh_hp", value );
    self menu_say( "^2vehicle HP " + value + "% of stock - from the next ride" );
    return true;
}

function private act_veh_alt( item, value )
{
    cfg_seti( #"gf_veh_alt", value );
    self menu_say( "^2heli spawn height " + value + " u above the spawn point" );
    return true;
}

function private act_dbg_veh( item ) { return self act_dbg( item, #"gf_dbg_veh", 1, "vehicle mode (VEHMODE)" ); }

// ── App parity for the Vehicles page ─────────────────────────────────────────
// The app names a vehicle by its veh_master() index (tools/gf-control reads the same list out of
// this file at startup, so the two cannot drift); veh_spawn does the residency check and the
// "no vehicle assets on this map" answer itself.
function private cmd_vehspawn( arg )
{
    m = veh_master();

    if ( !isdefined( arg ) || arg == "" )
    {
        self menu_say( "^1app: vehspawn needs a vehicle index" );
        return;
    }

    i = int( arg );

    if ( i < 0 || i >= m.size )
    {
        self menu_say( "^1app: no vehicle #" + arg + " (0-" + ( m.size - 1 ) + ")" );
        return;
    }

    self veh_spawn( spawnstruct(), m[ i ].key );
    self menu_say( "^2app: " + m[ i ].label );
}

// Delete every vehicle THIS menu spawned (page rows tag gf_spawned, vehicle mode tags gf_veh_mode)
// that nobody is sitting in. Stock's own vehicles (streaks, map intro) carry neither tag.
function private act_vehclear( item )
{
    n = veh_sweep_tagged();
    self menu_say( "^2removed " + n + " empty spawned vehicle(s)" );
    return true;
}

function private veh_sweep_tagged()
{
    n = 0;
    vehs = getvehiclearray();

    if ( !isdefined( vehs ) )
        return 0;

    foreach ( v in vehs )
    {
        if ( !isdefined( v ) || ( !is_true( v.gf_spawned ) && !is_true( v.gf_veh_mode ) ) )
            continue;

        if ( !veh_mode_empty( v ) )
            continue;                          // never delete a vehicle with someone in it

        v delete();
        n++;
    }

    return n;
}

// The SAME sweep before every level transition THIS menu starts - Stage (the load half runs while
// the match continues), Switch NOW, the legacy carry, a restart. The 3rd crash (2026-09-18, dump
// 000325, the same signature C55D66DA) was a Gas Station page-spawned vehicle riding a session
// switch into Sanatorium: none of those paths sets level.gameended, so the round-end poll never
// ran. Synchronous from the caller's thread (every caller is threaded): dismount, a frame, delete
// the empties, a frame, once more. A rider the engine will not eject keeps his vehicle - it is
// never deleted with a player inside - and the host hears about it.
function private veh_sweep_for_transition( why )
{
    riders = 0;

    foreach ( p in getplayers() )
    {
        if ( isdefined( p.gf_veh ) )
        {
            p veh_mode_dismount();
            riders++;
        }
    }

    waitframe( 1 );
    n = veh_sweep_tagged();
    waitframe( 1 );
    n += veh_sweep_tagged();
    left = veh_count_tagged();

    if ( left > 0 )
        mod_host_say( "^1VEHMODE " + why + ": " + left + " spawned vehicle(s) still occupied - could not remove before the load" );
    else if ( cfg_dbg_veh() && ( n > 0 || riders > 0 ) )
        mod_host_say( "^3VEHMODE ^7" + why + ": swept " + n + " spawned vehicle(s), " + riders + " rider(s) dismounted" );
}

// How many menu-spawned vehicles still exist (occupied ones included).
function private veh_count_tagged()
{
    n = 0;
    vehs = getvehiclearray();

    if ( !isdefined( vehs ) )
        return 0;

    foreach ( v in vehs )
    {
        if ( isdefined( v ) && ( is_true( v.gf_spawned ) || is_true( v.gf_veh_mode ) ) )
            n++;
    }

    return n;
}

// No menu-spawned vehicle survives a round transition. level.gameended is set at EVERY round end
// (globallogic.gsc:2329 function_d8d30361, from end_round) and map_restart( 1 ) follows only after
// the round-end presentation (display_round_end, >= 1.5 s later, :2058) - so a 0.25 s poll sees it
// in time. Riders are dismounted first the way stock ejects occupants before freeing a vehicle
// (vehicle_death_shared.gsc:307 usevehicle toggle, then free) - a vehicle is never deleted with a
// player inside; the second sweep catches the ones veh_mode_delete_soon released. One thread per
// level (level is rebuilt each round). Prime-suspect fix for the 2026-09-18 Miami crash
// (0x91f84370 at a round transition, a page-spawned heli stuck in the ground at the time).
function private veh_round_end_sweep()
{
    if ( isdefined( level.gf_veh_sweep_on ) )
        return;

    level.gf_veh_sweep_on = 1;

    while ( !is_true( level.gameended ) )
        wait 0.25;

    foreach ( p in getplayers() )
    {
        if ( isdefined( p.gf_veh ) )
            p veh_mode_dismount();
    }

    waitframe( 1 );
    n = veh_sweep_tagged();
    wait 0.6;
    n += veh_sweep_tagged();

    if ( cfg_dbg_veh() && n > 0 )
        mod_host_say( "^3VEHMODE ^7round end: swept " + n + " spawned vehicle(s) before the restart" );
}

// ── Player tools ─────────────────────────────────────────────────────────────
// Host-only (self = the host). Godmode/third person are re-applied on spawn by
// mod_spawn_place. Same builtins the Atian menu uses (menu_funcs.gsc).

function private act_godmode( item )
{
    if ( !isdefined( self.gf_god ) )
        self.gf_god = 0;
    self.gf_god = !self.gf_god;
    item.activated = self.gf_god;

    if ( self.gf_god )
    {
        self enableinvulnerability();
        self menu_say( "^2godmode ON" );
    }
    else
    {
        self disableinvulnerability();
        self menu_say( "^2godmode OFF" );
    }

    return true;
}

function private act_thirdperson( item )
{
    if ( !isdefined( self.gf_tp ) )
        self.gf_tp = 0;
    self.gf_tp = !self.gf_tp;
    item.activated = self.gf_tp;
    self setclientthirdperson( self.gf_tp );
    self menu_say( self.gf_tp ? "^2third person" : "^2first person" );
    return true;
}

function private act_maxammo( item )
{
    w = self getcurrentweapon();
    if ( isdefined( w ) )
        self givemaxammo( w );
    self menu_say( "^2max ammo" );
    return true;
}

function private act_dropweapon( item )
{
    w = self getcurrentweapon();
    if ( isdefined( w ) && self hasweapon( w ) )
        self takeweapon( w );
    self menu_say( "^2dropped" );
    return true;
}

// ── Weapons ──────────────────────────────────────────────────────────────────
// data1 is the weapon's hashed name (#"ar_standard_t9" etc. - real T9 names from the
// dump), data2 the label. getweapon takes the hash, giveweapon + switch to it.

function private act_giveweapon( item, whash, label )
{
    // The host, or the client a Players page aimed this hub at (menu_target).
    p = self menu_target();

    if ( p != self && !isalive( p ) )
    {
        self menu_say( "^1" + p.name + " is not alive" );
        return true;
    }

    w = getweapon( whash );

    if ( isdefined( w ) )
    {
        p giveweapon( w );
        p switchtoweapon( w );
        self menu_say( "^2gave " + label + self target_tail( p ) );
    }
    else
    {
        self menu_say( "^1weapon not found: " + label );
    }

    return true;
}

// ── Cosmetics — force-applied via builtins, so they work regardless of whether
//    the item is actually unlocked/owned (that is the point of the menu). ──────

function private act_camo( item, id )
{
    p = self menu_target();
    w = p getcurrentweapon();
    if ( isdefined( w ) )
        p setcamo( w, id );
    self menu_say( "^2camo " + id + " on current weapon" + self target_tail( p ) );
    return true;
}

// Clear the per-slot customization so an operator/outfit change looks clean. All
// confirmed builtins; mirrors the Atian menu's func_skin/func_outfit.
function private cos_clear()
{
    self function_ab96a9b5( "head", 0 );
    self function_ab96a9b5( "headgear", 0 );
    self function_ab96a9b5( "arms", 0 );
    self function_ab96a9b5( "torso", 0 );
    self function_ab96a9b5( "legs", 0 );
    self function_ab96a9b5( "palette", 0 );
    self function_ab96a9b5( "warpaint", 0 );
    self function_ab96a9b5( "decal", 0 );
}

function private act_skin( item, id )
{
    p = self menu_target();
    p setspecialistindex( id );
    p setcharacteroutfit( 0 );
    p setcharacterwarpaintoutfit( 0 );
    p cos_clear();
    self menu_say( "^2operator " + id + self target_tail( p ) );
    return true;
}

function private act_outfit( item, id )
{
    p = self menu_target();
    p setcharacteroutfit( id );
    p setcharacterwarpaintoutfit( 0 );
    p cos_clear();
    self menu_say( "^2outfit " + id + self target_tail( p ) );
    return true;
}

// loot_fakeall is the engine dvar cwpatch sets at launch to fake-unlock loot; it is
// NOT in the dump, so a mid-match set is best-effort and mostly touches frontend menus.
// The camo/operator/outfit pages already apply any item regardless of ownership, which
// is the real in-match "use anything". Full unlock = cwpatch / CW_Soft_Unlock.dll
// (docs/notes/unlock-dlls.md).
function private act_unlockall( item )
{
    setdvar( #"loot_fakeall", 1 );
    self menu_say( "^3loot_fakeall=1 - best-effort; cwpatch does the real unlock" );
    return true;
}

// ═════════════════════════════════════════════════════════════════════════════
// TELEPORT — docs/notes/teleport.md
// ═════════════════════════════════════════════════════════════════════════════
// Moving a player is three builtins in a fixed order, the shape stock's own retail MP
// fast-travel uses on a live player (red_door.gsc:492 function_2aed1d83, :155): dontinterpolate()
// so the client snaps instead of lerping across the map, setorigin(), setvelocity( (0,0,0) )
// because the old momentum survives the move (:496), then setplayerangles(). Entity state on
// the server, so a vanilla joiner is moved exactly like the host. The tools are the Atian
// menu's tpgun / func_teleport and the (compiled-out) dev warp, dev.gsc:279 - a ring of
// players in front of the target, each spot floored, all facing the target.
//
// Two things a bare setorigin gets wrong, both handled in tp_place / tp_floor:
//   - a FLYING player is linked to the fly anchor and the link owns the origin: move the
//     anchor instead (fly_think stores it as self.gf_fly_anchor; Atian's future_tp);
//   - a point on a wall or in the air leaves the player half in the surface or falling:
//     the aim point is pushed 12u out along the hit normal, then every destination is
//     dropped onto the floor under it with playerphysicstrace, the capsule sweep Prop Hunt
//     uses to re-materialise a prop as a player (_prop_controls.gsc:1260-1265).
// A player in a vehicle is skipped (the seat owns him); dead players and spectators are
// skipped; bots are moved like anyone else, so a solo host with bots can see it work.
// The teleport GUN and GRENADE are per-life player threads re-armed on every spawn
// (mod_spawn_place -> tp_spawn_rearm). "Everyone" flags live in game. so they survive the
// round boundary and reset at match end, and never include bots (a bot fires constantly).
// Nothing here has run in-game yet (2026-09-15); the note carries the test sheet.

// One player to pos (feet origin), facing angles (undefined = keep the view). 0 = not moved.
function private tp_place( player, pos, angles )
{
    if ( !isdefined( player ) || !isalive( player ) || !isdefined( pos ) )
        return 0;

    if ( isdefined( player getvehicleoccupied() ) )
        return 0;

    if ( isdefined( player.gf_fly ) && player.gf_fly && isdefined( player.gf_fly_anchor ) )
    {
        player.gf_fly_anchor.origin = pos;

        if ( isdefined( angles ) )
            player setplayerangles( angles );

        return 1;
    }

    player dontinterpolate();
    player setorigin( pos );
    player setvelocity( ( 0, 0, 0 ) );

    if ( isdefined( angles ) )
        player setplayerangles( angles );

    return 1;
}

// The floor under pos for a standing player: the capsule sweep from a hand above pos down
// 2000u (stock's own span, _prop_controls.gsc:1263), which answers the feet origin, or
// undefined / the bottom of the segment when it starts in solid or finds nothing; then a
// plain bullettrace floor; then pos itself (mid-air: the player drops, like any menu's tp).
function private tp_floor( pos )
{
    top = pos + ( 0, 0, 16 );
    bottom = pos - ( 0, 0, 2000 );

    p = playerphysicstrace( top, bottom );

    if ( isdefined( p ) && p[ 2 ] > bottom[ 2 ] + 1 )
        return p;

    tr = bullettrace( top, bottom, 0, undefined );

    if ( tr[ #"fraction" ] < 1 )
        return tr[ #"position" ];

    return pos;
}

// ── Anti-stack net (F5b) ───────────────────────────────────────────────────────
// on_spawned, after mod_spawn_place, for every player (bots included). Records each spawn's
// final 2D origin for the round; if a new spawn lands within a body-width of one already placed,
// fans it out to the nearest clear, floored spot that is not on top of anyone. Map-agnostic: it
// fixes stacking from ANY cause (too few guard anchors, the engine handing the same start, the
// map-centre pile) with no per-map data. The placed list resets when game.roundsplayed changes
// (Gunfight is one spawn wave per round). A player already in a vehicle (vehicle mode) is left
// in its seat. If no clear spot is found the player is left where they are - never made worse.
function private mod_spawn_antistack()
{
    if ( !isplayer( self ) || !isdefined( self.origin ) )
        return;

    if ( !cfg_spawn_antistack() )
        return;

    if ( isdefined( self getvehicleoccupied() ) )
        return;

    rp = isdefined( game.roundsplayed ) ? game.roundsplayed : 0;

    if ( !isdefined( level.gf_antistack ) || !isdefined( level.gf_antistack_round ) || level.gf_antistack_round != rp )
    {
        level.gf_antistack = [];
        level.gf_antistack_round = rp;
    }

    minsep = 48;
    minsep_sq = minsep * minsep;
    stacked = false;

    foreach ( o in level.gf_antistack )
    {
        if ( mod_dist2d_sq( self.origin, o ) < minsep_sq )
        {
            stacked = true;
            break;
        }
    }

    if ( stacked )
    {
        spot = mod_antistack_spot( self.origin, level.gf_antistack, minsep );

        if ( isdefined( spot ) )
        {
            self dontinterpolate();
            self setorigin( spot );

            if ( cfg_spawn_diag() )
                self.gf_spawn_how = ( isdefined( self.gf_spawn_how ) ? self.gf_spawn_how : "" ) + "+unstack";
        }
    }

    level.gf_antistack[ level.gf_antistack.size ] = self.origin;
}

// A clear, floored spot near center at least minsep from every placed origin. Rings outward
// (minsep .. 3x) at 8 angles; each candidate floored (tp_floor) and rejected if it dropped off a
// ledge (|z| > 128) or sits within minsep of another placed player. undefined = nothing found.
function private mod_antistack_spot( center, placed, minsep )
{
    minsep_sq = minsep * minsep;

    steps = [];
    steps[ 0 ] = minsep;
    steps[ 1 ] = minsep + minsep / 2;
    steps[ 2 ] = minsep * 2;
    steps[ 3 ] = minsep * 3;

    for ( s = 0; s < steps.size; s++ )
    {
        r = steps[ s ];

        for ( a = 0; a < 360; a += 45 )
        {
            cand = tp_floor( center + ( r * cos( a ), r * sin( a ), 0 ) );

            if ( abs( cand[ 2 ] - center[ 2 ] ) > 128 )
                continue;

            clear = true;

            foreach ( o in placed )
            {
                if ( mod_dist2d_sq( cand, o ) < minsep_sq )
                {
                    clear = false;
                    break;
                }
            }

            if ( clear )
                return cand;
        }
    }

    return undefined;
}

// Where the host is aiming: eye + view forward, 10000u, characters count (the Atian
// get_look_trace), pushed 12u back out of the surface along its normal so a wall shot lands
// beside the wall. undefined on a miss (the sky) - nobody moves on a miss.
function private tp_aim()
{
    eye = self geteye();
    tr = bullettrace( eye, eye + vectorscale( anglestoforward( self getplayerangles() ), 10000 ), 1, self );

    if ( tr[ #"fraction" ] >= 1 )
        return undefined;

    pos = tr[ #"position" ];

    if ( isdefined( tr[ #"normal" ] ) )
        pos += vectorscale( tr[ #"normal" ], 12 );

    return pos;
}

function private tp_fmt( v )
{
    return int( v[ 0 ] ) + " " + int( v[ 1 ] ) + " " + int( v[ 2 ] );
}

// Spot i of n around centre: one ring, radius 80u (grows past six so nobody overlaps), each
// spot floored. A spot whose floor is more than 128u off the centre's (off a ledge, through
// a floor) or with no clear chest-height line from the centre (through a wall) falls back
// to the centre itself - players overlap there and walk apart; MP does not telefrag.
function private tp_ring_spot( centre, i, n )
{
    if ( n <= 0 )
        return centre;

    // 2026-09-15 (klaze: "everyone to me just restarts the match"): with the host in a tight
    // spot every ring position failed its checks and EVERY player landed on the host's exact
    // origin - a stack, enemies point-blank, the round over in a second. So a failed ring
    // position now shrinks toward the host (80 -> 48 -> 24 u) before giving up, and the
    // last resort is a 16 u nudge, never the same point twice.
    a = 360 * i / n;
    base = ( n > 6 ) ? ( 80 * n / 6 ) : 80;

    for ( k = 0; k < 3; k++ )
    {
        radius = ( k == 0 ) ? base : ( ( k == 1 ) ? 48 : 24 );
        spot = tp_floor( centre + ( radius * cos( a ), radius * sin( a ), 0 ) );

        if ( abs( spot[ 2 ] - centre[ 2 ] ) > 128 )
            continue;

        if ( !bullettracepassed( centre + ( 0, 0, 40 ), spot + ( 0, 0, 40 ), 0, undefined ) )
            continue;

        return spot;
    }

    return centre + ( 16 * cos( a ), 16 * sin( a ), 0 );
}

// A short invulnerability after a mass teleport, so a group dropped point-blank (or onto
// the host) does not decide the round in the same second. God mode is left as it was.
function private tp_grace( secs )
{
    self endon( #"disconnect" );
    self endon( #"death" );
    self enableinvulnerability();
    wait secs;

    if ( !is_true( self.gf_god ) )
        self disableinvulnerability();
}

// The spot 80u in front of origin (yaw), floored and checked the same way; origin when
// the front is blocked. The per-player "to me" / "me to them" landing.
function private tp_front( origin, yaw )
{
    spot = tp_floor( origin + vectorscale( anglestoforward( ( 0, yaw, 0 ) ), 80 ) );

    if ( abs( spot[ 2 ] - origin[ 2 ] ) > 128 )
        return origin;

    if ( !bullettracepassed( origin + ( 0, 0, 40 ), spot + ( 0, 0, 40 ), 0, undefined ) )
        return origin;

    return spot;
}

// Everyone alive but the host (no spectators, no vehicle seats) to the host's area. who =
// "all" | "team" (the host's side) | "enemy". Returns how many moved.
// ⚠ "all" (BOTH teams to ONE point) reloaded the round - MEASURED 2026-09-18 even with every
// player FROZEN, so it is NOT combat (invulnerability cannot help): the engine ends the round
// when both teams occupy one cluster. "team"/"enemy" move a single team and are fine. So "all"
// is split into two independent single-team gathers at two centres a real distance apart -
// each is exactly the working single-team case, and the two teams are never co-located.
function private tp_gather( centre, who )
{
    if ( who != "all" )
        return self tp_gather_ring( centre, who );

    ang = self getplayerangles();
    fwd = anglestoforward( ( 0, ang[ 1 ], 0 ) );
    c2 = tp_floor( centre + vectorscale( fwd, 384 ) );

    // If the forward offset collapsed back onto the host (blocked / off a ledge), go sideways.
    if ( distancesquared( centre, c2 ) < ( 220 * 220 ) )
        c2 = tp_floor( centre + vectorscale( ( 0 - fwd[ 1 ], fwd[ 0 ], 0 ), 384 ) );

    return ( self tp_gather_ring( centre, "team" ) ) + ( self tp_gather_ring( c2, "enemy" ) );
}

// One ring of one team around one centre - the single-team primitive "all" is built from.
function private tp_gather_ring( centre, who )
{
    list = [];

    foreach ( player in getplayers() )
    {
        if ( player == self || !isalive( player ) )
            continue;

        if ( !isdefined( player.team ) || player.team == #"spectator" )
            continue;

        if ( who == "team" && player.team != self.team )
            continue;

        if ( who == "enemy" && player.team == self.team )
            continue;

        list[ list.size ] = player;
    }

    moved = 0;

    for ( i = 0; i < list.size; i++ )
    {
        spot = tp_ring_spot( centre, i, list.size );
        face = ( distancesquared( centre, spot ) > 1 ) ? vectortoangles( centre - spot ) : self getplayerangles();

        p = list[ i ];

        if ( tp_place( p, spot, ( 0, face[ 1 ], 0 ) ) )
        {
            moved++;
            p thread tp_grace( 1.5 );
            p iprintln( "^3teleported by the host" );
        }
        else
        {
            self menu_say( "^3" + p.name + " is in a vehicle - skipped" );
        }
    }

    return moved;
}

// A destination by name: "aim" (the crosshair, floored), "saved" (game.gf_tp_point, a spot
// someone stood on), "centre" (level.mapcenter, the minimap box centre stock's fourth spawn
// path piles players on - globallogic.gsc:5500 - floored). Struct { origin, angles, label },
// or undefined after saying why.
function private tp_dest( where )
{
    if ( where == "aim" )
    {
        pos = self tp_aim();

        if ( !isdefined( pos ) )
        {
            self menu_say( "^1aim at something first (that was the sky)" );
            return undefined;
        }

        return { #origin: tp_floor( pos ), #label: "crosshair" };
    }

    if ( where == "saved" )
    {
        if ( !isdefined( game.gf_tp_point ) )
        {
            self menu_say( "^1no saved point - Me to... > Save point first" );
            return undefined;
        }

        return { #origin: game.gf_tp_point.origin, #angles: game.gf_tp_point.angles, #label: "saved point" };
    }

    if ( where == "centre" )
    {
        if ( !isdefined( level.mapcenter ) )
        {
            self menu_say( "^1no map centre on this map" );
            return undefined;
        }

        return { #origin: tp_floor( level.mapcenter ), #label: "map centre" };
    }

    self menu_say( "^1teleport: unknown destination '" + where + "'" );
    return undefined;
}

function private act_tp_save( item )
{
    if ( !isalive( self ) )
    {
        self menu_say( "^1spawn first" );
        return true;
    }

    ang = self getplayerangles();
    game.gf_tp_point = { #origin: self.origin, #angles: ang };
    self menu_say( "^2point saved: " + tp_fmt( self.origin ) );
    return true;
}

function private act_tp_me( item, where )
{
    if ( !isalive( self ) )
    {
        self menu_say( "^1spawn first" );
        return true;
    }

    dest = self tp_dest( where );

    if ( !isdefined( dest ) )
        return true;

    if ( tp_place( self, dest.origin, dest.angles ) )
        self menu_say( "^2teleported to " + dest.label );
    else
        self menu_say( "^1get out of the vehicle first" );

    return true;
}

// where = "me" | a tp_dest name; who = "all" | "team" | "enemy".
function private act_tp_all( item, where, who )
{
    if ( !isalive( self ) )
    {
        self menu_say( "^1spawn first" );
        return true;
    }

    if ( where == "me" )
    {
        centre = self.origin;
        label = "you";
    }
    else
    {
        dest = self tp_dest( where );

        if ( !isdefined( dest ) )
            return true;

        centre = dest.origin;
        label = dest.label;
    }

    n = self tp_gather( centre, who );

    if ( n > 0 && who != "team" && where == "me" )
        self thread tp_grace( 1.5 );        // enemies just arrived in your face too

    self menu_say( "^2" + n + " moved to " + label );
    return true;
}

// Players page rows: "tome" (in front of me, facing me), "metothem" (in front of them,
// facing them), "swap" (exchange positions and views; nobody moves if either is seated).
function private act_tp_player( item, player, verb )
{
    if ( !isdefined( player ) )
    {
        self menu_say( "^1player left" );
        return true;
    }

    if ( !isalive( self ) || !isalive( player ) )
    {
        self menu_say( "^1both must be alive" );
        return true;
    }

    switch ( verb )
    {
        case "tome":
            ang = self getplayerangles();
            ok = tp_place( player, tp_front( self.origin, ang[ 1 ] ), ( 0, ang[ 1 ] + 180, 0 ) );
            self menu_say( ok ? ( "^2" + player.name + " brought to you" ) : ( "^1" + player.name + " is in a vehicle" ) );
            if ( ok )
                player iprintln( "^3teleported by the host" );
            break;
        case "metothem":
            ang = player getplayerangles();
            ok = tp_place( self, tp_front( player.origin, ang[ 1 ] ), ( 0, ang[ 1 ] + 180, 0 ) );
            self menu_say( ok ? ( "^2teleported to " + player.name ) : "^1get out of the vehicle first" );
            break;
        case "swap":
            if ( isdefined( self getvehicleoccupied() ) || isdefined( player getvehicleoccupied() ) )
            {
                self menu_say( "^1one of you is in a vehicle - no swap" );
                break;
            }
            a = self.origin;
            aa = self getplayerangles();
            b = player.origin;
            ba = player getplayerangles();
            tp_place( self, b, ba );
            tp_place( player, a, aa );
            player iprintln( "^3swapped places with the host" );
            self menu_say( "^2swapped places with " + player.name );
            break;
        default:
            self menu_say( "^1teleport: unknown verb '" + verb + "'" );
            break;
    }

    return true;
}

// ── Teleport gun / grenade ───────────────────────────────────────────────────

function private tpgun_wanted( player )
{
    if ( isdefined( player.gf_tpgun ) && player.gf_tpgun )
        return true;

    return isdefined( game.gf_tpgun_all ) && game.gf_tpgun_all && !isbot( player );
}

function private tpnade_wanted( player )
{
    if ( isdefined( player.gf_tpnade ) && player.gf_tpnade )
        return true;

    return isdefined( game.gf_tpnade_all ) && game.gf_tpnade_all && !isbot( player );
}

// (Re)start a player's gun / grenade thread to match what he wants right now; a stop is a
// restart that finds nothing wanted. Called from every spawn and from the toggles.
function private tpgun_rearm( player )
{
    player notify( #"gf_tpgun_restart" );

    if ( isalive( player ) && tpgun_wanted( player ) )
        player thread tpgun_think();
}

function private tpnade_rearm( player )
{
    player notify( #"gf_tpnade_restart" );

    if ( isalive( player ) && tpnade_wanted( player ) )
        player thread tpnade_think();
}

// mod_spawn_place: the per-life threads for whoever wants them (bots never do).
function private tp_spawn_rearm()
{
    if ( !isplayer( self ) )
        return;

    tpgun_rearm( self );
    tpnade_rearm( self );
}

// The host's menu is open: its next-item key is ATTACK (keys_init), so a shot fired while
// navigating the menu is a menu press, not a teleport. Joiners have no gfmenu.
function private tp_menu_open()
{
    return isdefined( self.gfmenu ) && isdefined( self.gfmenu.current ) && self.gfmenu.current != "";
}

// One shot = one move, to where the shot lands: the engine raises weapon_fired on the
// player for every shot (weapons.gsc:1034 event_handler -> the notify placeables.gsc:215
// waits on), so full-auto is a move per bullet - the classic feel. The view is kept.
// Shots while the host's menu is open are menu navigation and ignored.
function private tpgun_think()
{
    self notify( #"gf_tpgun_restart" );
    self endon( #"gf_tpgun_restart" );
    self endon( #"disconnect" );
    self endon( #"death" );

    for ( ;; )
    {
        self waittill( #"weapon_fired" );

        if ( !tpgun_wanted( self ) )
            return;

        if ( self tp_menu_open() )
            continue;

        pos = self tp_aim();

        if ( isdefined( pos ) )
            tp_place( self, tp_floor( pos ), undefined );
    }
}

// The thrown grenade's detonation point becomes the thrower's position: grenade_fire hands
// over the projectile (weapons.gsc:1583; _prop_controls.gsc:1820 reads res.projectile),
// explode carries res.position (_prop_controls.gsc:1836). A grenade that dies without
// exploding (thrown back, fizzled) moves nobody - the empgrenade.gsc:252 _notify test.
function private tpnade_think()
{
    self notify( #"gf_tpnade_restart" );
    self endon( #"gf_tpnade_restart" );
    self endon( #"disconnect" );
    self endon( #"death" );

    for ( ;; )
    {
        res = self waittill( #"grenade_fire" );

        if ( !tpnade_wanted( self ) )
            return;

        if ( isdefined( res.projectile ) )
            self thread tpnade_follow( res.projectile );
    }
}

function private tpnade_follow( nade )
{
    self endon( #"gf_tpnade_restart" );
    self endon( #"disconnect" );
    self endon( #"death" );

    res = nade waittill( #"explode", #"death" );

    if ( res._notify != "explode" || !isdefined( res.position ) )
        return;

    tp_place( self, tp_floor( res.position + ( 0, 0, 8 ) ), undefined );
}

// who = "host" (self.gf_tpgun) | "all" (game.gf_tpgun_all, humans only). Toggles.
function private act_tpgun( item, who )
{
    if ( who == "all" )
    {
        on = !( isdefined( game.gf_tpgun_all ) && game.gf_tpgun_all );
        game.gf_tpgun_all = on;
        item.activated = on;

        foreach ( player in getplayers() )
            tpgun_rearm( player );

        broadcast_feed( on ? "^3teleport gun ON - shoot to go there" : "^3teleport gun OFF" );
        self menu_say( on ? "^2teleport gun ON for everyone (not bots)" : "^2teleport gun OFF for everyone" );
        return true;
    }

    if ( who != "host" )
    {
        self menu_say( "^1teleport gun: host or all" );
        return true;
    }

    on = !( isdefined( self.gf_tpgun ) && self.gf_tpgun );
    self.gf_tpgun = on;
    item.activated = on;
    tpgun_rearm( self );
    self menu_say( on ? "^2teleport gun ON - shoot to go there" : "^2teleport gun OFF" );
    return true;
}

function private act_tpnade( item, who )
{
    if ( who == "all" )
    {
        on = !( isdefined( game.gf_tpnade_all ) && game.gf_tpnade_all );
        game.gf_tpnade_all = on;
        item.activated = on;

        foreach ( player in getplayers() )
            tpnade_rearm( player );

        broadcast_feed( on ? "^3teleport grenade ON - you appear where it blows" : "^3teleport grenade OFF" );
        self menu_say( on ? "^2teleport grenade ON for everyone (not bots)" : "^2teleport grenade OFF for everyone" );
        return true;
    }

    if ( who != "host" )
    {
        self menu_say( "^1teleport grenade: host or all" );
        return true;
    }

    on = !( isdefined( self.gf_tpnade ) && self.gf_tpnade );
    self.gf_tpnade = on;
    item.activated = on;
    tpnade_rearm( self );
    self menu_say( on ? "^2teleport grenade ON - you appear where it blows" : "^2teleport grenade OFF" );
    return true;
}



// ═════════════════════════════════════════════════════════════════════════════
// DESTRUCTIBLES + RADIANT EXPLODERS — docs/notes/destructibles.md. Built 2026-09-17, never run.
// ═════════════════════════════════════════════════════════════════════════════
// The map's own breakables. One call enumerates them - getentarray( "destructible",
// "targetname" ), the read stock's own preinit makes (destructible.gsc:23) - and each entity
// carries .destructibledef, the asset name, as a plain string (stock getsubstr()s it, :30).
// Breaking one is dodamage ON THE ENTITY: breakafter (destructible.gsc:613) is
// `self dodamage( damage, self.origin )`, and simple_explosion (:210) passes the attacker as
// arg 3 so a kill by the blast credits him. The explosion visual rides STOCK's own clientfield
// (start_destructible_explosion, :23) down stock's own path, so a vanilla joiner draws it -
// the favourable half of Gate 2 (vehicles.md §3). Nothing is spawned: no residency question,
// no per-map gating; a map with none simply yields an empty array (Nuketown lists 13 defs,
// Miami 30, the manifests say - counts of DEFINITIONS, the census reads the instances).
//
// Radiant exploders are the map's authored FX / light / sound triggers. exploder::exploder( id )
// branches on the argument's type (exploder_shared.gsc:278): an int fires a SCRIPT exploder,
// anything else the RADIANT one by name (:731 -> activateclientradiantexploder). The bgcache
// lists every radiant name per map as a HASH, and the call takes one: frontend.csc:3881 passes
// #"hash_..." to this very function, and "" + #"hash" (the notify it builds first) is a stock
// idiom (archetype_avogadro.gsc:49). exp_table() is GENERATED from tables/bgcache/<map>.csv by
// tools/exploders-gen.py - 699 rows over 32 maps, 34 with a name cracked against the strings
// map scripts fire themselves, the rest by index. Firing an unnamed one is trial and error BY
// DESIGN: the walker prints the index it fired so a good one can be written down
// (docs/data/map-exploders.json is the index -> hash lookup). Stop is the builtin
// deactivateclientradiantexploder( id ) called direct - stock's delete_exploder_on_clients
// (:858) only reaches it for a string, and ours are hashes.
//
// ⚠ Both are WRITES that change the match (cover gone, effects playing). One per match on the
//   first run, the src/README.md rule; nothing here has run in-game.

function private destruct_list()
{
    ents = getentarray( "destructible", "targetname" );
    return isdefined( ents ) ? ents : [];
}

// The asset name a destructible carries, or "?" - a string on every stock read of it.
function private destruct_def( e )
{
    if ( isdefined( e.destructibledef ) && isstring( e.destructibledef ) )
        return e.destructibledef;

    return "?";
}

// simple_explosion's own shape: a damage no piece survives, at the entity, from the attacker.
function private destruct_break( e, attacker )
{
    if ( !isdefined( e ) )
        return;

    if ( isdefined( attacker ) )
        e dodamage( 20000, e.origin + ( 0, 0, 5 ), attacker );
    else
        e dodamage( 20000, e.origin + ( 0, 0, 5 ) );
}

// The destructible the host is looking at: the trace's own entity when it is one, else the
// nearest destructible within 160 u of where the shot would land (a barrel behind a railing).
function private destruct_aimed()
{
    eye = self geteye();
    tr = bullettrace( eye, eye + vectorscale( anglestoforward( self getplayerangles() ), 4000 ), 0, self );
    ent = tr[ #"entity" ];

    if ( isdefined( ent ) && isdefined( ent.destructibledef ) )
        return ent;

    if ( tr[ #"fraction" ] >= 1 )
        return undefined;

    pos = tr[ #"position" ];
    best = undefined;
    bestd = 160 * 160;

    foreach ( e in destruct_list() )
    {
        d = distancesquared( e.origin, pos );

        if ( d < bestd )
        {
            bestd = d;
            best = e;
        }
    }

    return best;
}

function private act_destruct_aim( item )
{
    e = self destruct_aimed();

    if ( !isdefined( e ) )
    {
        self menu_say( "^1no destructible where you are looking" );
        return true;
    }

    name = destruct_def( e );
    destruct_break( e, self );
    self menu_say( "^2broke " + name );
    return true;
}

// near = 1: only those within radius of the host. Spread over frames so a 100-barrel map
// does not detonate in one server frame.
function private act_destruct_all( item, near, radius )
{
    if ( !isdefined( near ) )
        near = 0;

    if ( !isdefined( radius ) )
        radius = 600;

    n = destruct_list().size;

    if ( n == 0 )
    {
        self menu_say( "^1this map has no destructibles" );
        return true;
    }

    self thread destruct_break_all_think( near, radius );
    self menu_say( near ? ( "^3breaking every destructible within " + radius + " u..." ) : ( "^3breaking all " + n + " destructibles..." ) );
    return true;
}

function private destruct_break_all_think( near, radius )
{
    level endon( #"game_ended" );
    self endon( #"disconnect" );

    n = 0;
    r2 = radius * radius;

    foreach ( e in destruct_list() )
    {
        if ( !isdefined( e ) )
            continue;

        if ( near && distancesquared( e.origin, self.origin ) > r2 )
            continue;

        destruct_break( e, self );
        n++;

        if ( n % 6 == 0 )
            waitframe( 1 );
    }

    self menu_say( "^2broke " + n + " destructibles" );
}

// The Destructibles page is rebuilt on entry so its header row carries the live count.
function private destruct_enter( menu )
{
    self menu_clear_items( "destruct" );

    t = destruct_tally();
    self menu_item( "destruct", "(" + t.n + " destructibles here, " + t.names.size + " kinds, " + t.veh + " cars)", undefined );
    self menu_item( "destruct", "Break the one I am looking at", &act_destruct_aim );
    self menu_item( "destruct", "Break everything within 600 u of me", &act_destruct_all, 1, 600 );
    self menu_item( "destruct", "Break EVERY destructible on the map", &act_destruct_all, 0, 0 );
    self menu_item( "destruct", "Census line to the feed (DESTRUCT)", &act_dbg_assets, undefined, undefined, #"gf_dbg_assets", 1 );
    self menu_item( "destruct", "Radiant exploders (" + exp_table().size + " listed)", &menu_switch, "exploders" );
}

// ── Radiant exploders: the walker ─────────────────────────────────────────────

function private exp_add( e, key, label )
{
    st = spawnstruct();
    st.key = key;
    st.label = label;
    e[ e.size ] = st;
    return e;
}

function private exp_label( i )
{
    t = exp_table();

    if ( i < 0 || i >= t.size )
        return "?";

    tag = ( i + 1 ) + "/" + t.size;

    if ( t[ i ].label != "" )
        return tag + " " + t[ i ].label;

    return tag + " (unnamed - map-exploders.json #" + ( i + 1 ) + ")";
}

// dir: next / prev / again / stop / all / stopall. The index lives on level, so it resets
// with the level (per round in Gunfight) - the walk restarts at 1 each round.
function private act_exp( item, dir )
{
    t = exp_table();

    if ( dir == "stopall" )
    {
        level notify( #"gf_exp_stop" );
        self menu_say( "^2exploder walk stopped" );
        return true;
    }

    if ( t.size == 0 )
    {
        self menu_say( "^1no radiant exploders listed for this map (tools/exploders-gen.py)" );
        return true;
    }

    if ( !isdefined( level.gf_exp_i ) )
        level.gf_exp_i = -1;

    switch ( dir )
    {
        case "next":
            level.gf_exp_i = ( level.gf_exp_i + 1 ) % t.size;
            break;
        case "prev":
            level.gf_exp_i = ( level.gf_exp_i - 1 + t.size ) % t.size;
            break;
        case "again":
            if ( level.gf_exp_i < 0 )
                level.gf_exp_i = 0;
            break;
        case "stop":
            if ( level.gf_exp_i >= 0 )
            {
                deactivateclientradiantexploder( t[ level.gf_exp_i ].key );
                self menu_say( "^2stopped exploder " + exp_label( level.gf_exp_i ) );
            }
            else
            {
                self menu_say( "^1nothing fired yet" );
            }
            return true;
        case "all":
            self thread exp_fire_all_think();
            self menu_say( "^3firing all " + t.size + " exploders, one every 0.5 s (Stop walk ends it)" );
            return true;
        default:
            self menu_say( "^1exploder: unknown verb '" + dir + "'" );
            return true;
    }

    exploder::exploder( t[ level.gf_exp_i ].key );
    self menu_say( "^2fired exploder " + exp_label( level.gf_exp_i ) );
    return true;
}

function private exp_fire_all_think()
{
    level notify( #"gf_exp_stop" );        // a walk already running ends here, before our endon
    level endon( #"gf_exp_stop" );
    level endon( #"game_ended" );
    self endon( #"disconnect" );

    t = exp_table();

    for ( i = 0; i < t.size; i++ )
    {
        level.gf_exp_i = i;
        exploder::exploder( t[ i ].key );
        self menu_say( "^2fired exploder " + exp_label( i ) );
        wait 0.5;
    }
}

function private exp_enter( menu )
{
    self menu_clear_items( "exploders" );

    t = exp_table();
    self menu_item( "exploders", "(" + t.size + " radiant exploders listed for this map)", undefined );
    self menu_item( "exploders", "Fire NEXT", &act_exp, "next" );
    self menu_item( "exploders", "Fire PREVIOUS", &act_exp, "prev" );
    self menu_item( "exploders", "Fire the current one again", &act_exp, "again" );
    self menu_item( "exploders", "Stop the current one", &act_exp, "stop" );
    self menu_item( "exploders", "Fire ALL, one every 0.5 s", &act_exp, "all" );
    self menu_item( "exploders", "Stop the walk", &act_exp, "stopall" );

    // The named ones as their own rows (34 across all maps): a label is a known effect.
    for ( i = 0; i < t.size; i++ )
    {
        if ( t[ i ].label != "" )
            self menu_item( "exploders", "Fire " + ( i + 1 ) + ": " + t[ i ].label, &act_exp_at, i );
    }
}

function private act_exp_at( item, i )
{
    t = exp_table();

    if ( i < 0 || i >= t.size )
        return true;

    level.gf_exp_i = i;
    exploder::exploder( t[ i ].key );
    self menu_say( "^2fired exploder " + exp_label( i ) );
    return true;
}

// [exploders-gen BEGIN]
// GENERATED by tools/exploders-gen.py from tables/bgcache/<map>.csv - do not edit by hand.
// 699 radiant exploders over 32 maps, 34 named (string form), the rest by #"hash" literal in manifest order. 2026-09-17.
function private exp_table()
{
    if ( isdefined( level.gf_exp_table ) )
        return level.gf_exp_table;

    // sv_mapname: measured a plain string on every map (the census prints it); level.script
    // may be a hash in this VM and a switch on it would match nothing.
    mapname = tolower( getdvarstring( #"sv_mapname", "" ) );

    e = [];

    switch ( mapname )
    {
        case "mp_amerika": e = exp_rows_mp_amerika(); break;
        case "mp_apocalypse": e = exp_rows_mp_apocalypse(); break;
        case "mp_black_sea": e = exp_rows_mp_black_sea(); break;
        case "mp_cartel": e = exp_rows_mp_cartel(); break;
        case "mp_cliffhanger": e = exp_rows_mp_cliffhanger(); break;
        case "mp_drivein_rm": e = exp_rows_mp_drivein_rm(); break;
        case "mp_dune": e = exp_rows_mp_dune(); break;
        case "mp_echelon": e = exp_rows_mp_echelon(); break;
        case "mp_express_rm": e = exp_rows_mp_express_rm(); break;
        case "mp_firebase": e = exp_rows_mp_firebase(); break;
        case "mp_kgb": e = exp_rows_mp_kgb(); break;
        case "mp_mall": e = exp_rows_mp_mall(); break;
        case "mp_miami": e = exp_rows_mp_miami(); break;
        case "mp_miami_strike": e = exp_rows_mp_miami_strike(); break;
        case "mp_moscow": e = exp_rows_mp_moscow(); break;
        case "mp_nuketown6": e = exp_rows_mp_nuketown6(); break;
        case "mp_russianbase_rm": e = exp_rows_mp_russianbase_rm(); break;
        case "mp_satellite": e = exp_rows_mp_satellite(); break;
        case "mp_slums_rm": e = exp_rows_mp_slums_rm(); break;
        case "mp_sm_game_show": e = exp_rows_mp_sm_game_show(); break;
        case "mp_sm_gas_station": e = exp_rows_mp_sm_gas_station(); break;
        case "mp_tank": e = exp_rows_mp_tank(); break;
        case "mp_tundra": e = exp_rows_mp_tundra(); break;
        case "mp_village_rm": e = exp_rows_mp_village_rm(); break;
        case "mp_zoo_rm": e = exp_rows_mp_zoo_rm(); break;
        case "wz_doa": e = exp_rows_wz_doa(); break;
        case "wz_duga": e = exp_rows_wz_duga(); break;
        case "wz_forest": e = exp_rows_wz_forest(); break;
        case "wz_golova": e = exp_rows_wz_golova(); break;
        case "wz_sanatorium": e = exp_rows_wz_sanatorium(); break;
        case "wz_ski_slopes": e = exp_rows_wz_ski_slopes(); break;
        case "wz_zoo": e = exp_rows_wz_zoo(); break;
    }

    level.gf_exp_table = e;
    return e;
}

function private exp_rows_mp_amerika()
{
    e = [];
    e = exp_add( e, #"hash_31ab44849655bc7", "" );
    e = exp_add( e, #"hash_af9fd7358a3405e", "" );
    e = exp_add( e, #"hash_c57a2da83d8c1b4", "" );
    e = exp_add( e, #"hash_d1d401c4c43e4cb", "" );
    e = exp_add( e, #"hash_17d9a01a470deaea", "" );
    e = exp_add( e, #"hash_17e08c1a4713e79c", "" );
    e = exp_add( e, #"hash_17e7181a4719412e", "" );
    e = exp_add( e, #"hash_20f7d2d794092f78", "" );
    e = exp_add( e, #"hash_20fb58d7940c4901", "" );
    e = exp_add( e, #"hash_20fe5ed7940e890a", "" );
    e = exp_add( e, #"hash_210f5cd7941cf8d7", "" );
    e = exp_add( e, #"hash_456b357497c1d5d3", "" );
    e = exp_add( e, #"hash_4ce6066ccc53ef8b", "" );
    e = exp_add( e, #"hash_6ebf2d83afff910d", "" );
    return e;
}

function private exp_rows_mp_apocalypse()
{
    e = [];
    e = exp_add( e, #"hash_82e65e0f722e7b9", "" );
    e = exp_add( e, #"hash_cb2b8a13ad44823", "" );
    e = exp_add( e, #"hash_ec32cf4638ad910", "" );
    e = exp_add( e, #"hash_ec9b8f4639032a2", "" );
    e = exp_add( e, #"hash_ecd3ef463934c2b", "" );
    e = exp_add( e, #"hash_ed3caf46398a5bd", "" );
    e = exp_add( e, #"hash_1526dd1a5a09f02b", "" );
    e = exp_add( e, #"hash_1f146aa949511632", "" );
    e = exp_add( e, #"hash_208d61d26e1026a8", "" );
    e = exp_add( e, #"hash_22b6e6f9ff37d864", "" );
    e = exp_add( e, #"hash_25c919e0f966cf23", "" );
    e = exp_add( e, #"hash_3ac6fc928bf95cae", "" );
    e = exp_add( e, #"hash_42cb2f6b196f0835", "" );
    e = exp_add( e, #"hash_42d1b66b19745948", "" );
    e = exp_add( e, #"hash_42d1bb6b197461c7", "" );
    e = exp_add( e, #"hash_42d1bd6b1974652d", "" );
    e = exp_add( e, #"hash_517b9fb392d6f3b6", "" );
    e = exp_add( e, #"hash_59784d54005f0e4e", "" );
    e = exp_add( e, #"hash_6063d291057197ae", "" );
    e = exp_add( e, #"hash_6063d39105719961", "" );
    e = exp_add( e, #"hash_6063d49105719b14", "" );
    e = exp_add( e, #"hash_62a72dc2581c5829", "" );
    e = exp_add( e, #"hash_62b13fc25824cb44", "" );
    e = exp_add( e, #"hash_62b82bc2582ac7f6", "" );
    e = exp_add( e, #"hash_6de0cc93f60dc52e", "" );
    e = exp_add( e, #"hash_7d58ae66d975538c", "" );
    return e;
}

function private exp_rows_mp_black_sea()
{
    e = [];
    e = exp_add( e, #"hash_9d3da0e8279d1f", "" );
    e = exp_add( e, #"hash_c7318700eae462", "" );
    e = exp_add( e, #"hash_701f1c2fc19e39f", "" );
    e = exp_add( e, #"hash_82ecd8f228232cd", "" );
    e = exp_add( e, #"hash_9884a03921e97ee", "" );
    e = exp_add( e, #"hash_d0a47a0486b26aa", "" );
    e = exp_add( e, #"hash_dbde0a22345a3b3", "" );
    e = exp_add( e, #"hash_e092aea86d2b6d2", "" );
    e = exp_add( e, #"hash_f78fc3818d2224e", "" );
    e = exp_add( e, #"hash_fe6cc1b10ff8056", "" );
    e = exp_add( e, #"hash_111c09c22d3c7f0c", "" );
    e = exp_add( e, #"hash_111c0ac22d3c80bf", "" );
    e = exp_add( e, #"hash_111c0cc22d3c8425", "" );
    e = exp_add( e, #"hash_11709d4893f302cd", "" );
    e = exp_add( e, #"hash_1a82af9b3d783b33", "" );
    e = exp_add( e, #"hash_20ac174de0e714bf", "" );
    e = exp_add( e, #"hash_233964ade2cc2273", "" );
    e = exp_add( e, #"hash_2478c1c94c653e3a", "" );
    e = exp_add( e, #"hash_262d6e22a70a8cd3", "" );
    e = exp_add( e, #"hash_27fb35330563274b", "" );
    e = exp_add( e, #"hash_2a39680d37cc34b0", "" );
    e = exp_add( e, "exp_lgt_12v12", "exp_lgt_12v12" );
    e = exp_add( e, #"hash_2ca2a57d22caaae6", "" );
    e = exp_add( e, #"hash_2eb213b6939bd388", "" );
    e = exp_add( e, #"hash_2eb59cb6939ef22a", "" );
    e = exp_add( e, #"hash_2eb91fb693a2069a", "" );
    e = exp_add( e, #"hash_2ebc85b693a4e9c3", "" );
    e = exp_add( e, #"hash_2ebf8bb693a729cc", "" );
    e = exp_add( e, #"hash_2ec311b693aa4355", "" );
    e = exp_add( e, #"hash_3ed3c0000b7422d7", "" );
    e = exp_add( e, #"hash_41877167642ecf9d", "" );
    e = exp_add( e, #"hash_42ef89558771eb78", "" );
    e = exp_add( e, #"hash_43f9fba42420c1c1", "" );
    e = exp_add( e, #"hash_46da1922898414d3", "" );
    e = exp_add( e, #"hash_487a72df53fd4e25", "" );
    e = exp_add( e, #"hash_496026f849b0a3ba", "" );
    e = exp_add( e, #"hash_4fced2b74e4dc411", "" );
    e = exp_add( e, #"hash_565f18232f3617ca", "" );
    e = exp_add( e, #"hash_5cf18753a47e6f2a", "" );
    e = exp_add( e, #"hash_61f89a169a76269a", "" );
    e = exp_add( e, #"hash_62028c169a7e6355", "" );
    e = exp_add( e, #"hash_620612169a817cde", "" );
    e = exp_add( e, #"hash_620617169a81855d", "" );
    e = exp_add( e, #"hash_64c38ebcc7416bbd", "" );
    e = exp_add( e, #"hash_650664cd4a95eb47", "" );
    e = exp_add( e, "fxexp_main_ship_oil_fire_level", "fxexp_main_ship_oil_fire_level" );
    return e;
}

function private exp_rows_mp_cartel()
{
    e = [];
    e = exp_add( e, #"hash_2e512deef15d28b", "" );
    e = exp_add( e, #"hash_f84ddec2d1bd178", "" );
    e = exp_add( e, #"hash_f84deec2d1bd32b", "" );
    e = exp_add( e, #"hash_f84e3ec2d1bdbaa", "" );
    e = exp_add( e, #"hash_f84e4ec2d1bdd5d", "" );
    e = exp_add( e, #"hash_189e37fafdad4b75", "" );
    e = exp_add( e, #"hash_38edb091c511069b", "" );
    e = exp_add( e, #"hash_51fc3f803f47cdcb", "" );
    e = exp_add( e, #"hash_51fc40803f47cf7e", "" );
    e = exp_add( e, #"hash_52c098e84cf1b40b", "" );
    e = exp_add( e, #"hash_61f89a169a76269a", "" );
    e = exp_add( e, #"hash_61fc00169a7909c3", "" );
    e = exp_add( e, #"hash_61ff06169a7b49cc", "" );
    e = exp_add( e, #"hash_62028c169a7e6355", "" );
    e = exp_add( e, #"hash_620612169a817cde", "" );
    e = exp_add( e, #"hash_620617169a81855d", "" );
    e = exp_add( e, #"hash_64868c1e234e1812", "" );
    e = exp_add( e, #"hash_650664cd4a95eb47", "" );
    return e;
}

function private exp_rows_mp_cliffhanger()
{
    e = [];
    e = exp_add( e, #"hash_19e3c5f6f176128", "" );
    e = exp_add( e, #"hash_1a4c85f6f1cbaba", "" );
    e = exp_add( e, #"hash_1af3a5f6f25d0f5", "" );
    e = exp_add( e, #"hash_56589f16c6d138d", "" );
    e = exp_add( e, #"hash_7f7c32bbbf5f06a", "" );
    e = exp_add( e, #"hash_16dd4bd8ba4ce1f7", "" );
    e = exp_add( e, #"hash_1a1edfbed03f9728", "" );
    e = exp_add( e, #"hash_1d1b47209cabd570", "" );
    e = exp_add( e, #"hash_29be60e5193780f2", "" );
    e = exp_add( e, #"hash_31ebc2998066ccb1", "" );
    e = exp_add( e, #"hash_32b6cad0f21380b4", "" );
    e = exp_add( e, #"hash_32b9d0d0f215c0bd", "" );
    e = exp_add( e, #"hash_32bd36d0f218a3e6", "" );
    e = exp_add( e, #"hash_37be461a70adaea6", "" );
    e = exp_add( e, #"hash_38aae9f1fa54808c", "" );
    e = exp_add( e, #"hash_3cdba0315d0e6a9d", "" );
    e = exp_add( e, #"hash_3f4acffbe5ab0693", "" );
    e = exp_add( e, #"hash_425972f003c192de", "" );
    e = exp_add( e, #"hash_428d86d65652dcc9", "" );
    e = exp_add( e, #"hash_534b40f16922ed49", "" );
    e = exp_add( e, #"hash_5b88962bd232e0f2", "" );
    e = exp_add( e, #"hash_601059fa5e8e96aa", "" );
    e = exp_add( e, #"hash_7140bfb7afdc3728", "" );
    e = exp_add( e, #"hash_7547e0a43cff339c", "" );
    return e;
}

function private exp_rows_mp_drivein_rm()
{
    e = [];
    e = exp_add( e, #"hash_d1d401c4c43e4cb", "" );
    e = exp_add( e, #"hash_3601eb67de812145", "" );
    return e;
}

function private exp_rows_mp_dune()
{
    e = [];
    e = exp_add( e, #"hash_70c75bb40235f3b", "" );
    e = exp_add( e, #"hash_220b90fc54be9f51", "" );
    e = exp_add( e, #"hash_220f16fc54c1b8da", "" );
    e = exp_add( e, #"hash_222014fc54d028a7", "" );
    e = exp_add( e, #"hash_2483fc06d24579d6", "" );
    e = exp_add( e, #"hash_3601eb67de812145", "" );
    e = exp_add( e, #"hash_364c0a77d0fb618d", "" );
    e = exp_add( e, #"hash_3a35df59758f6f08", "" );
    e = exp_add( e, #"hash_3a8288f573dca8c1", "" );
    e = exp_add( e, #"hash_40ecb95335967f20", "" );
    e = exp_add( e, #"hash_445e64afbe06d34f", "" );
    e = exp_add( e, #"hash_467f547f158267c1", "" );
    e = exp_add( e, #"hash_4ec98d433d82a148", "" );
    e = exp_add( e, #"hash_4f082f236207db3a", "" );
    e = exp_add( e, #"hash_514a446163004912", "" );
    e = exp_add( e, #"hash_5668e8fa68d4ed43", "" );
    e = exp_add( e, #"hash_5f9dca26dc2b46a3", "" );
    e = exp_add( e, #"hash_6aeae8e0c4d6c96a", "" );
    e = exp_add( e, #"hash_6af4dae0c4df0625", "" );
    e = exp_add( e, #"hash_6affbbafd80aae05", "" );
    e = exp_add( e, #"hash_6b0647afd8100797", "" );
    return e;
}

function private exp_rows_mp_echelon()
{
    e = [];
    e = exp_add( e, #"hash_bd0d252e2f7c1b", "" );
    e = exp_add( e, #"hash_d1d401c4c43e4cb", "" );
    e = exp_add( e, #"hash_17704dff62173070", "" );
    e = exp_add( e, #"hash_1773d3ff621a49f9", "" );
    e = exp_add( e, #"hash_177759ff621d6382", "" );
    e = exp_add( e, #"hash_1784d1ff6228b9c6", "" );
    e = exp_add( e, #"hash_178857ff622bd34f", "" );
    e = exp_add( e, #"hash_35bd08c5d958a48a", "" );
    e = exp_add( e, #"hash_3601eb67de812145", "" );
    e = exp_add( e, #"hash_3bdbfd8345effb03", "" );
    e = exp_add( e, #"hash_3da9886c761ac183", "" );
    e = exp_add( e, #"hash_467f547f158267c1", "" );
    e = exp_add( e, #"hash_687793b1e0fd3346", "" );
    e = exp_add( e, #"hash_6a8669638afe57c9", "" );
    e = exp_add( e, #"hash_6a89ef638b017152", "" );
    e = exp_add( e, #"hash_6a8d75638b048adb", "" );
    e = exp_add( e, #"hash_6a907b638b06cae4", "" );
    e = exp_add( e, #"hash_6a9401638b09e46d", "" );
    e = exp_add( e, #"hash_6a9767638b0cc796", "" );
    e = exp_add( e, #"hash_6a9aed638b0fe11f", "" );
    e = exp_add( e, #"hash_6a9e73638b12faa8", "" );
    e = exp_add( e, #"hash_6aa179638b153ab1", "" );
    return e;
}

function private exp_rows_mp_express_rm()
{
    e = [];
    e = exp_add( e, "fxexp_trigger_train_debris_g", "fxexp_trigger_train_debris_g" );
    e = exp_add( e, "fxexp_trigger_train_debris_f", "fxexp_trigger_train_debris_f" );
    e = exp_add( e, "fxexp_trigger_train_debris_e", "fxexp_trigger_train_debris_e" );
    e = exp_add( e, "fxexp_trigger_train_debris_d", "fxexp_trigger_train_debris_d" );
    e = exp_add( e, "fxexp_trigger_train_debris_c", "fxexp_trigger_train_debris_c" );
    e = exp_add( e, "fxexp_trigger_train_debris_b", "fxexp_trigger_train_debris_b" );
    e = exp_add( e, "fxexp_trigger_train_debris_a", "fxexp_trigger_train_debris_a" );
    e = exp_add( e, "fxexp_trigger_train_gate_bot_dust", "fxexp_trigger_train_gate_bot_dust" );
    e = exp_add( e, "fxexp_trigger_train_sparks_d", "fxexp_trigger_train_sparks_d" );
    e = exp_add( e, "fxexp_trigger_train_sparks_e", "fxexp_trigger_train_sparks_e" );
    e = exp_add( e, "fxexp_trigger_train_sparks_f", "fxexp_trigger_train_sparks_f" );
    e = exp_add( e, "fxexp_trigger_train_sparks_g", "fxexp_trigger_train_sparks_g" );
    e = exp_add( e, "fxexp_trigger_train_sparks_a", "fxexp_trigger_train_sparks_a" );
    e = exp_add( e, "fxexp_trigger_train_sparks_b", "fxexp_trigger_train_sparks_b" );
    e = exp_add( e, "fxexp_trigger_train_sparks_c", "fxexp_trigger_train_sparks_c" );
    e = exp_add( e, "fxexp_trigger_train_gate_top_dust", "fxexp_trigger_train_gate_top_dust" );
    return e;
}

function private exp_rows_mp_firebase()
{
    e = [];
    e = exp_add( e, #"hash_5bb5c25fc63a85a", "" );
    e = exp_add( e, #"hash_10423f056b122715", "" );
    e = exp_add( e, #"hash_136739312926bbc4", "" );
    e = exp_add( e, #"hash_1777b65a96b25e68", "" );
    e = exp_add( e, #"hash_1781a85a96ba9b23", "" );
    e = exp_add( e, #"hash_29dd5689b7cb7a1a", "" );
    e = exp_add( e, #"hash_2aa980e3873f2af4", "" );
    e = exp_add( e, #"hash_2ef2f614107ed2d5", "" );
    e = exp_add( e, #"hash_2ef67c141081ec5e", "" );
    e = exp_add( e, #"hash_2efa0214108505e7", "" );
    e = exp_add( e, "fxexp_red_door_enter_mall", "fxexp_red_door_enter_mall" );
    e = exp_add( e, #"hash_31d7dfb632a882ff", "" );
    e = exp_add( e, #"hash_420492bff8b35639", "" );
    e = exp_add( e, #"hash_49f778f1e10c10c6", "" );
    e = exp_add( e, #"hash_4f383f77dc1b4927", "" );
    e = exp_add( e, "fxexp_red_door_enter_temple", "fxexp_red_door_enter_temple" );
    e = exp_add( e, #"hash_610f74031c693074", "" );
    e = exp_add( e, #"hash_61127a031c6b707d", "" );
    e = exp_add( e, #"hash_6115e0031c6e53a6", "" );
    e = exp_add( e, #"hash_7d0184c1d786103d", "" );
    e = exp_add( e, #"hash_7d04eac1d788f366", "" );
    e = exp_add( e, #"hash_7f5fdb8e28d1723b", "" );
    return e;
}

function private exp_rows_mp_kgb()
{
    e = [];
    e = exp_add( e, #"hash_3223f1221fb79548", "" );
    e = exp_add( e, #"hash_322afd221fbdc85a", "" );
    e = exp_add( e, #"hash_322e63221fc0ab83", "" );
    e = exp_add( e, #"hash_3234ef221fc60515", "" );
    e = exp_add( e, #"hash_330c7b1b627e2b7d", "" );
    e = exp_add( e, #"hash_330fe11b62810ea6", "" );
    e = exp_add( e, #"hash_4c443dcf99dde02c", "" );
    e = exp_add( e, #"hash_4c443fcf99dde392", "" );
    e = exp_add( e, #"hash_4c4440cf99dde545", "" );
    e = exp_add( e, #"hash_7e1f1b242f5fc4e2", "" );
    return e;
}

function private exp_rows_mp_mall()
{
    e = [];
    e = exp_add( e, #"hash_5c44200d1fc9d68", "" );
    e = exp_add( e, #"hash_5cace00d201f6fa", "" );
    e = exp_add( e, #"hash_5d84600d20d4d3e", "" );
    e = exp_add( e, #"hash_5dbcc00d21066c7", "" );
    e = exp_add( e, #"hash_ca9b3e99ae37236", "" );
    e = exp_add( e, #"hash_15a3190a4d63d1b0", "" );
    e = exp_add( e, #"hash_16dd4bd8ba4ce1f7", "" );
    e = exp_add( e, #"hash_32b6cad0f21380b4", "" );
    e = exp_add( e, #"hash_32b9d0d0f215c0bd", "" );
    e = exp_add( e, #"hash_32bd36d0f218a3e6", "" );
    e = exp_add( e, #"hash_38aae9f1fa54808c", "" );
    e = exp_add( e, #"hash_3cdba0315d0e6a9d", "" );
    e = exp_add( e, #"hash_44c9690a169830e3", "" );
    e = exp_add( e, #"hash_5992a364d9560448", "" );
    e = exp_add( e, #"hash_5b88962bd232e0f2", "" );
    e = exp_add( e, #"hash_5dd24a1bd2b31702", "" );
    e = exp_add( e, #"hash_6eb49b83aff64472", "" );
    e = exp_add( e, #"hash_6eb82183aff95dfb", "" );
    e = exp_add( e, #"hash_6ebba783affc7784", "" );
    e = exp_add( e, #"hash_6ebf2d83afff910d", "" );
    e = exp_add( e, #"hash_6ec29383b0027436", "" );
    return e;
}

function private exp_rows_mp_miami()
{
    e = [];
    e = exp_add( e, #"hash_c7318700eae462", "" );
    e = exp_add( e, #"hash_2d847292a2628f2", "" );
    e = exp_add( e, #"hash_bf29c2dcd82eb3b", "" );
    e = exp_add( e, #"hash_d1d401c4c43e4cb", "" );
    e = exp_add( e, #"hash_22080afc54bb85c8", "" );
    e = exp_add( e, #"hash_220b90fc54be9f51", "" );
    e = exp_add( e, #"hash_221908fc54c9f595", "" );
    e = exp_add( e, #"hash_221c8efc54cd0f1e", "" );
    e = exp_add( e, #"hash_222014fc54d028a7", "" );
    e = exp_add( e, #"hash_26465fd9778f60f5", "" );
    e = exp_add( e, #"hash_27e335f7c6461435", "" );
    e = exp_add( e, #"hash_2ad4b5995ad267f6", "" );
    e = exp_add( e, #"hash_30369917c77999fe", "" );
    e = exp_add( e, #"hash_3a2b572bccda0871", "" );
    e = exp_add( e, #"hash_3e4347363cb68624", "" );
    e = exp_add( e, #"hash_3e4db9363cbf9c5f", "" );
    e = exp_add( e, #"hash_41723b7f9cf1ff10", "" );
    e = exp_add( e, #"hash_43bd7489fb5f9a98", "" );
    e = exp_add( e, #"hash_4513b383965d6b02", "" );
    e = exp_add( e, #"hash_46a961a787226c27", "" );
    e = exp_add( e, #"hash_51c8d8fafe6c5173", "" );
    e = exp_add( e, #"hash_5c2c54129741e90e", "" );
    e = exp_add( e, #"hash_5e32868524b90f99", "" );
    e = exp_add( e, #"hash_6195807a10c66bf9", "" );
    e = exp_add( e, #"hash_6ae145afd7f0e7f4", "" );
    e = exp_add( e, #"hash_6ae44bafd7f327fd", "" );
    e = exp_add( e, #"hash_6aeebdafd7fc3e38", "" );
    e = exp_add( e, #"hash_6af549afd80197ca", "" );
    e = exp_add( e, #"hash_6af8afafd8047af3", "" );
    e = exp_add( e, #"hash_6affbbafd80aae05", "" );
    e = exp_add( e, #"hash_6b0341afd80dc78e", "" );
    e = exp_add( e, #"hash_6b0647afd8100797", "" );
    e = exp_add( e, #"hash_741270afdd4bf847", "" );
    e = exp_add( e, #"hash_744b4ae7d0136f15", "" );
    return e;
}

function private exp_rows_mp_miami_strike()
{
    e = [];
    e = exp_add( e, #"hash_2d847292a2628f2", "" );
    e = exp_add( e, #"hash_bf29c2dcd82eb3b", "" );
    e = exp_add( e, #"hash_26465fd9778f60f5", "" );
    e = exp_add( e, #"hash_27e335f7c6461435", "" );
    e = exp_add( e, #"hash_3a2b572bccda0871", "" );
    e = exp_add( e, #"hash_3e4347363cb68624", "" );
    e = exp_add( e, #"hash_3e4db9363cbf9c5f", "" );
    e = exp_add( e, #"hash_51c8d8fafe6c5173", "" );
    e = exp_add( e, #"hash_744b4ae7d0136f15", "" );
    return e;
}

function private exp_rows_mp_moscow()
{
    e = [];
    e = exp_add( e, #"hash_e7cc9aaa227b2c9", "" );
    e = exp_add( e, #"hash_1138f73062f8e390", "" );
    e = exp_add( e, #"hash_14a322ac1c7dfd5f", "" );
    e = exp_add( e, #"hash_20056b5135034d39", "" );
    e = exp_add( e, #"hash_2073823d3debc662", "" );
    e = exp_add( e, #"hash_26465fd9778f60f5", "" );
    e = exp_add( e, #"hash_27e335f7c6461435", "" );
    e = exp_add( e, #"hash_30369917c77999fe", "" );
    e = exp_add( e, #"hash_3a2b572bccda0871", "" );
    e = exp_add( e, #"hash_4135cecccca7e173", "" );
    e = exp_add( e, #"hash_6205fd4a2cb0a432", "" );
    e = exp_add( e, #"hash_62c983c592c7b982", "" );
    e = exp_add( e, #"hash_6affef43c291ff4b", "" );
    e = exp_add( e, #"hash_73a566372f4aef12", "" );
    e = exp_add( e, #"hash_74ffaca929a3eb70", "" );
    e = exp_add( e, #"hash_750332a929a704f9", "" );
    e = exp_add( e, #"hash_7509bea929ac5e8b", "" );
    e = exp_add( e, #"hash_750d44a929af7814", "" );
    e = exp_add( e, #"hash_7510caa929b2919d", "" );
    e = exp_add( e, #"hash_751430a929b574c6", "" );
    e = exp_add( e, #"hash_7517b6a929b88e4f", "" );
    e = exp_add( e, #"hash_7521c8a929c1016a", "" );
    e = exp_add( e, #"hash_75252ea929c3e493", "" );
    e = exp_add( e, #"hash_7caa83373480acb0", "" );
    e = exp_add( e, #"hash_7cae09373483c639", "" );
    e = exp_add( e, #"hash_7cb18f373486dfc2", "" );
    e = exp_add( e, #"hash_7cb4953734891fcb", "" );
    e = exp_add( e, #"hash_7cd38b3734a3bf5c", "" );
    e = exp_add( e, #"hash_7cd6913734a5ff65", "" );
    e = exp_add( e, #"hash_7d9c3b334f0033d1", "" );
    e = exp_add( e, #"hash_7d9fc1334f034d5a", "" );
    e = exp_add( e, #"hash_7e1cf3a92eee824d", "" );
    return e;
}

function private exp_rows_mp_nuketown6()
{
    e = [];
    e = exp_add( e, "fxexp_halloween", "fxexp_halloween" );
    e = exp_add( e, #"hash_2430d4b23d41e709", "" );
    e = exp_add( e, #"hash_25767f8a25fcee58", "" );
    e = exp_add( e, #"hash_25dfb047cbce7197", "" );
    e = exp_add( e, #"hash_2879aedec8c2586f", "" );
    e = exp_add( e, "fxexp_holiday", "fxexp_holiday" );
    e = exp_add( e, #"hash_32930a1245030bf7", "" );
    e = exp_add( e, #"hash_334932d16e831867", "" );
    e = exp_add( e, #"hash_3359f3899cf9bcbc", "" );
    e = exp_add( e, #"hash_43606ae615359f06", "" );
    return e;
}

function private exp_rows_mp_russianbase_rm()
{
    e = [];
    e = exp_add( e, #"hash_7e17d35a668424", "" );
    e = exp_add( e, "fxexp_cleanroom_on", "fxexp_cleanroom_on" );
    e = exp_add( e, "fxexp_controlroom_off", "fxexp_controlroom_off" );
    e = exp_add( e, "fxexp_center_event", "fxexp_center_event" );
    e = exp_add( e, "fxexp_gantry_off", "fxexp_gantry_off" );
    e = exp_add( e, "fxexp_gantry_on", "fxexp_gantry_on" );
    e = exp_add( e, "fxexp_glass_shatter", "fxexp_glass_shatter" );
    e = exp_add( e, "fxexp_cleanroom_off", "fxexp_cleanroom_off" );
    e = exp_add( e, "fxexp_controlroom_on", "fxexp_controlroom_on" );
    return e;
}

function private exp_rows_mp_satellite()
{
    e = [];
    e = exp_add( e, #"hash_3e3ecc51ceb204", "" );
    e = exp_add( e, #"hash_c7318700eae462", "" );
    e = exp_add( e, #"hash_2123dc6830d24c6", "" );
    e = exp_add( e, #"hash_2123ec6830d2679", "" );
    e = exp_add( e, #"hash_936c67103a44270", "" );
    e = exp_add( e, #"hash_9445e7103afcf14", "" );
    e = exp_add( e, #"hash_94ed07103b8e54f", "" );
    e = exp_add( e, #"hash_109427174cced852", "" );
    e = exp_add( e, #"hash_18f3a50d5ff5ff46", "" );
    e = exp_add( e, #"hash_1c8106ce6b0633e4", "" );
    e = exp_add( e, #"hash_1ddeb5f54da521bd", "" );
    e = exp_add( e, #"hash_211946b17b40363f", "" );
    e = exp_add( e, #"hash_22b02dd9e719d482", "" );
    e = exp_add( e, #"hash_3324523ffa4b519f", "" );
    e = exp_add( e, #"hash_40d307143c78ce05", "" );
    e = exp_add( e, #"hash_4c443dcf99dde02c", "" );
    e = exp_add( e, #"hash_4c443fcf99dde392", "" );
    e = exp_add( e, #"hash_4c4440cf99dde545", "" );
    e = exp_add( e, #"hash_6c046d6a4664bf66", "" );
    e = exp_add( e, #"hash_7cfe13caff08c008", "" );
    e = exp_add( e, #"hash_7d051fcaff0ef31a", "" );
    e = exp_add( e, #"hash_7d0885caff11d643", "" );
    e = exp_add( e, #"hash_7d0b8bcaff14164c", "" );
    e = exp_add( e, #"hash_7d161dcaff1d62e7", "" );
    e = exp_add( e, #"hash_7f1f4f9f550d4417", "" );
    return e;
}

function private exp_rows_mp_slums_rm()
{
    e = [];
    e = exp_add( e, #"hash_7e17d35a668424", "" );
    e = exp_add( e, #"hash_7b5e2758caead77", "" );
    e = exp_add( e, #"hash_30621110a92705ef", "" );
    return e;
}

function private exp_rows_mp_sm_game_show()
{
    e = [];
    e = exp_add( e, "fxexp_flag_confetti", "fxexp_flag_confetti" );
    return e;
}

function private exp_rows_mp_sm_gas_station()
{
    e = [];
    e = exp_add( e, #"hash_a7bb341b0967857", "" );
    e = exp_add( e, #"hash_f54ec79bab2067d", "" );
    e = exp_add( e, #"hash_209e0b05ba07fce3", "" );
    e = exp_add( e, #"hash_209e0c05ba07fe96", "" );
    e = exp_add( e, #"hash_300a582685b742d8", "" );
    e = exp_add( e, #"hash_306d2e5d79349711", "" );
    e = exp_add( e, #"hash_3f02b046e6b77ab7", "" );
    e = exp_add( e, #"hash_435a41c5a7cb7c1c", "" );
    e = exp_add( e, #"hash_4ec98d433d82a148", "" );
    e = exp_add( e, #"hash_556ebf89cc84d091", "" );
    e = exp_add( e, #"hash_556ec089cc84d244", "" );
    e = exp_add( e, #"hash_556ec189cc84d3f7", "" );
    e = exp_add( e, #"hash_556ec289cc84d5aa", "" );
    e = exp_add( e, #"hash_710edab7e627de38", "" );
    e = exp_add( e, #"hash_711260b7e62af7c1", "" );
    e = exp_add( e, #"hash_712664b7e63ba797", "" );
    return e;
}

function private exp_rows_mp_tank()
{
    e = [];
    e = exp_add( e, #"hash_31ab44849655bc7", "" );
    e = exp_add( e, #"hash_892cc30ddfdbf81", "" );
    e = exp_add( e, #"hash_af9fd7358a3405e", "" );
    e = exp_add( e, #"hash_c57a2da83d8c1b4", "" );
    e = exp_add( e, #"hash_2515cfc90cc9b5bd", "" );
    e = exp_add( e, #"hash_2569e9a0323ffa54", "" );
    e = exp_add( e, #"hash_3e1f23621f34bccf", "" );
    e = exp_add( e, #"hash_4536276dc8823013", "" );
    e = exp_add( e, #"hash_51711b3e5a87f3c5", "" );
    e = exp_add( e, #"hash_553c5b98b01dea8c", "" );
    e = exp_add( e, #"hash_62b54409a6e97528", "" );
    e = exp_add( e, #"hash_62b84a09a6ebb531", "" );
    e = exp_add( e, #"hash_62c94809a6fa24fe", "" );
    e = exp_add( e, #"hash_69c8d0d32552de37", "" );
    return e;
}

function private exp_rows_mp_tundra()
{
    e = [];
    e = exp_add( e, #"hash_ebfc2581ee067", "" );
    e = exp_add( e, #"hash_38d34ab72a5059a", "" );
    e = exp_add( e, #"hash_5833711e52101b8", "" );
    e = exp_add( e, #"hash_5833811e521036b", "" );
    e = exp_add( e, #"hash_5833911e521051e", "" );
    e = exp_add( e, #"hash_5833e11e5210d9d", "" );
    e = exp_add( e, #"hash_63cca56ee201771", "" );
    e = exp_add( e, #"hash_6404d56ee232be1", "" );
    e = exp_add( e, #"hash_643b656ee261423", "" );
    e = exp_add( e, #"hash_6473c56ee292dac", "" );
    e = exp_add( e, #"hash_64ac256ee2c4735", "" );
    e = exp_add( e, #"hash_64dc856ee2e873e", "" );
    e = exp_add( e, #"hash_b965f4d758fa573", "" );
    e = exp_add( e, #"hash_cd9833064f03c4a", "" );
    e = exp_add( e, #"hash_d1d401c4c43e4cb", "" );
    e = exp_add( e, #"hash_da904db6470a75c", "" );
    e = exp_add( e, #"hash_115ebbc6b4cc0162", "" );
    e = exp_add( e, #"hash_13d4b1e8ef456b19", "" );
    e = exp_add( e, #"hash_15b78afa9ab10140", "" );
    e = exp_add( e, #"hash_15b78cfa9ab104a6", "" );
    e = exp_add( e, #"hash_1efd1a80af011449", "" );
    e = exp_add( e, #"hash_238602b0f86fdb90", "" );
    e = exp_add( e, #"hash_24e905182a31d745", "" );
    e = exp_add( e, #"hash_26e470cbab746b15", "" );
    e = exp_add( e, #"hash_296c8d3a69986907", "" );
    e = exp_add( e, "exp_lgt_12v12", "exp_lgt_12v12" );
    e = exp_add( e, #"hash_2a8142796ff6fc4a", "" );
    e = exp_add( e, #"hash_318a168c475aa18d", "" );
    e = exp_add( e, #"hash_32137422fe736600", "" );
    e = exp_add( e, #"hash_35923beb06e46e15", "" );
    e = exp_add( e, #"hash_3601eb67de812145", "" );
    e = exp_add( e, #"hash_37f7dd427c099b2e", "" );
    e = exp_add( e, #"hash_3c1588a458b636e5", "" );
    e = exp_add( e, #"hash_4649983af76ddb84", "" );
    e = exp_add( e, #"hash_4a1c1f99fe6ad778", "" );
    e = exp_add( e, #"hash_4a3f57c6e51253a0", "" );
    e = exp_add( e, #"hash_4cc070d61b8244b9", "" );
    e = exp_add( e, #"hash_4ccc49996872d760", "" );
    e = exp_add( e, #"hash_4ccc4b996872dac6", "" );
    e = exp_add( e, #"hash_4ccc4c996872dc79", "" );
    e = exp_add( e, #"hash_4d9b09880791e43d", "" );
    e = exp_add( e, #"hash_4f9d4e3a0467f00a", "" );
    e = exp_add( e, #"hash_4fd419fee307f988", "" );
    e = exp_add( e, #"hash_4fd41cfee307fea1", "" );
    e = exp_add( e, #"hash_569a040365df3d73", "" );
    e = exp_add( e, #"hash_56f6cebde79d621b", "" );
    e = exp_add( e, #"hash_570446bde7a8b85f", "" );
    e = exp_add( e, #"hash_58d9e201e0ba4df3", "" );
    e = exp_add( e, #"hash_58d9e301e0ba4fa6", "" );
    e = exp_add( e, #"hash_58d9e401e0ba5159", "" );
    e = exp_add( e, #"hash_598314df8f2c9d6b", "" );
    e = exp_add( e, #"hash_5a681359b2d128dc", "" );
    e = exp_add( e, #"hash_5cc9076a3dfd8563", "" );
    e = exp_add( e, #"hash_5d12668b51054246", "" );
    e = exp_add( e, #"hash_5d2c088316ab74e8", "" );
    e = exp_add( e, "fxexp_tundra_6v6", "fxexp_tundra_6v6" );
    e = exp_add( e, #"hash_5e1df17985575eb2", "" );
    e = exp_add( e, #"hash_64972b3227a51a7b", "" );
    e = exp_add( e, #"hash_6a41b7a9e8220cce", "" );
    e = exp_add( e, #"hash_6b3e549b11f65a59", "" );
    e = exp_add( e, #"hash_6f22582a0eec74b8", "" );
    e = exp_add( e, #"hash_6f22592a0eec766b", "" );
    e = exp_add( e, #"hash_6f225a2a0eec781e", "" );
    e = exp_add( e, #"hash_7051940df89840d9", "" );
    e = exp_add( e, #"hash_72ce95173f87eacb", "" );
    e = exp_add( e, #"hash_732e6992318b295a", "" );
    e = exp_add( e, #"hash_75bd81fad69b9fe0", "" );
    e = exp_add( e, #"hash_79c93dde06972f86", "" );
    e = exp_add( e, #"hash_7bb830c655af911f", "" );
    e = exp_add( e, #"hash_7fa2ed52f28da888", "" );
    e = exp_add( e, #"hash_7fa2f452f28db46d", "" );
    return e;
}

function private exp_rows_mp_village_rm()
{
    e = [];
    e = exp_add( e, #"hash_d1d401c4c43e4cb", "" );
    e = exp_add( e, #"hash_3601eb67de812145", "" );
    return e;
}

function private exp_rows_mp_zoo_rm()
{
    e = [];
    e = exp_add( e, #"hash_3601eb67de812145", "" );
    e = exp_add( e, #"hash_5668e8fa68d4ed43", "" );
    return e;
}

function private exp_rows_wz_doa()
{
    e = [];
    e = exp_add( e, #"hash_7e8da32604c7cb", "" );
    e = exp_add( e, #"hash_350d8aaeeba88f8", "" );
    e = exp_add( e, #"hash_530a5f1a27fe0fa", "" );
    e = exp_add( e, #"hash_81cf3a457b564fd", "" );
    e = exp_add( e, #"hash_b4f91b69b05d17b", "" );
    e = exp_add( e, #"hash_d1d401c4c43e4cb", "" );
    e = exp_add( e, #"hash_f68bbd4064e6432", "" );
    e = exp_add( e, #"hash_1502bf859b7889e6", "" );
    e = exp_add( e, #"hash_171f550e0f24178a", "" );
    e = exp_add( e, #"hash_1863b0f17a1a33c2", "" );
    e = exp_add( e, #"hash_1cb2cd0929630709", "" );
    e = exp_add( e, #"hash_1da6cb0676c67cb9", "" );
    e = exp_add( e, #"hash_1e6963ebf91cea84", "" );
    e = exp_add( e, #"hash_217d9aa69b19648d", "" );
    e = exp_add( e, #"hash_257029acaf013f31", "" );
    e = exp_add( e, #"hash_2d1c33a97a7024d0", "" );
    e = exp_add( e, #"hash_2d1f720237a649e1", "" );
    e = exp_add( e, #"hash_2dd2c119c6f86f8d", "" );
    e = exp_add( e, #"hash_2e56718473ad0b69", "" );
    e = exp_add( e, #"hash_2f287ea3f0a71680", "" );
    e = exp_add( e, #"hash_31cdbcd23682bd36", "" );
    e = exp_add( e, #"hash_37823734e5f7a03e", "" );
    e = exp_add( e, #"hash_379e63750a2a82c8", "" );
    e = exp_add( e, #"hash_37a393fa2a09ab82", "" );
    e = exp_add( e, #"hash_38235e16dba81b26", "" );
    e = exp_add( e, #"hash_3e9d1a772e1f0b76", "" );
    e = exp_add( e, #"hash_3f568425fe077841", "" );
    e = exp_add( e, #"hash_3fb6a73c102285c1", "" );
    e = exp_add( e, #"hash_418f7e626f2b435d", "" );
    e = exp_add( e, #"hash_45c02840a9491b8e", "" );
    e = exp_add( e, #"hash_47721fe6e866d544", "" );
    e = exp_add( e, #"hash_4891af0924b4ba31", "" );
    e = exp_add( e, #"hash_4a36f339dbe0059f", "" );
    e = exp_add( e, #"hash_513ab7c4bac94289", "" );
    e = exp_add( e, #"hash_5243eed77981c13a", "" );
    e = exp_add( e, #"hash_549ed74648cc1cd2", "" );
    e = exp_add( e, #"hash_54eefdf357f1b41d", "" );
    e = exp_add( e, #"hash_59920be393555928", "" );
    e = exp_add( e, #"hash_5abb920ce1aac328", "" );
    e = exp_add( e, #"hash_5b532a08a60c0047", "" );
    e = exp_add( e, #"hash_5d95b7ba6bf32739", "" );
    e = exp_add( e, #"hash_6143289e9cab2b29", "" );
    e = exp_add( e, #"hash_6b19780729b8f6c6", "" );
    e = exp_add( e, #"hash_6d9fb0cc2acd616f", "" );
    e = exp_add( e, #"hash_713d156c4e2a95d7", "" );
    e = exp_add( e, #"hash_74c29d4ac89aaec6", "" );
    e = exp_add( e, #"hash_75283517c09df85a", "" );
    e = exp_add( e, #"hash_7566183f1103905b", "" );
    e = exp_add( e, #"hash_789bb5ed772830e8", "" );
    e = exp_add( e, #"hash_790977376fb05ed3", "" );
    return e;
}

function private exp_rows_wz_duga()
{
    e = [];
    e = exp_add( e, #"hash_7aac4ff7e7defdd", "" );
    e = exp_add( e, #"hash_d1d401c4c43e4cb", "" );
    e = exp_add( e, #"hash_1b8ccc2a9c77dcf0", "" );
    e = exp_add( e, #"hash_21ce3cafbaf75f91", "" );
    e = exp_add( e, #"hash_3601eb67de812145", "" );
    e = exp_add( e, #"hash_392656daeab6717c", "" );
    e = exp_add( e, #"hash_3a35df59758f6f08", "" );
    e = exp_add( e, #"hash_40ecb95335967f20", "" );
    e = exp_add( e, #"hash_5668e8fa68d4ed43", "" );
    e = exp_add( e, #"hash_585aa09c3fcfd971", "" );
    e = exp_add( e, #"hash_650664cd4a95eb47", "" );
    e = exp_add( e, #"hash_66147455862dfeb2", "" );
    e = exp_add( e, #"hash_6eead413c6501c99", "" );
    e = exp_add( e, #"hash_7cd770d54ad70617", "" );
    e = exp_add( e, #"hash_7e6db5d8f095cfd4", "" );
    e = exp_add( e, #"hash_7e6db6d8f095d187", "" );
    e = exp_add( e, #"hash_7e6db8d8f095d4ed", "" );
    return e;
}

function private exp_rows_wz_forest()
{
    e = [];
    e = exp_add( e, #"hash_466b4524d8d3cce", "" );
    e = exp_add( e, #"hash_466b6524d8d4034", "" );
    e = exp_add( e, #"hash_466b7524d8d41e7", "" );
    e = exp_add( e, #"hash_466b9524d8d454d", "" );
    e = exp_add( e, #"hash_5da24454366b345", "" );
    e = exp_add( e, #"hash_664374a18da43ef", "" );
    e = exp_add( e, #"hash_7aac4ff7e7defdd", "" );
    e = exp_add( e, #"hash_a4b9ecc46770dc9", "" );
    e = exp_add( e, #"hash_a666e72c5004f49", "" );
    e = exp_add( e, #"hash_d1d401c4c43e4cb", "" );
    e = exp_add( e, #"hash_dc94651f9fc6c30", "" );
    e = exp_add( e, #"hash_dcccc51f9ff85b9", "" );
    e = exp_add( e, #"hash_dd05251fa029f42", "" );
    e = exp_add( e, #"hash_dd35851fa04df4b", "" );
    e = exp_add( e, #"hash_de15051fa110f0f", "" );
    e = exp_add( e, #"hash_13d82495c548497d", "" );
    e = exp_add( e, #"hash_14c5e232646c1190", "" );
    e = exp_add( e, #"hash_14cc6e3264716b22", "" );
    e = exp_add( e, #"hash_14cff432647484ab", "" );
    e = exp_add( e, #"hash_14df74e691c24573", "" );
    e = exp_add( e, #"hash_16d56f51ff385ce0", "" );
    e = exp_add( e, #"hash_16d8f551ff3b7669", "" );
    e = exp_add( e, #"hash_16dbfb51ff3db672", "" );
    e = exp_add( e, #"hash_16df8151ff40cffb", "" );
    e = exp_add( e, #"hash_16e30751ff43e984", "" );
    e = exp_add( e, #"hash_16e68d51ff47030d", "" );
    e = exp_add( e, #"hash_16e9f351ff49e636", "" );
    e = exp_add( e, #"hash_16e9f851ff49eeb5", "" );
    e = exp_add( e, #"hash_16ecf951ff4c263f", "" );
    e = exp_add( e, #"hash_17050351ff60c91e", "" );
    e = exp_add( e, #"hash_17088951ff63e2a7", "" );
    e = exp_add( e, #"hash_18d3b1739a18f31d", "" );
    e = exp_add( e, #"hash_1e2e98520302b910", "" );
    e = exp_add( e, #"hash_1e319e520304f919", "" );
    e = exp_add( e, #"hash_1e49a85203199bf8", "" );
    e = exp_add( e, #"hash_1e503452031ef58a", "" );
    e = exp_add( e, #"hash_1e5379fdc0667bdc", "" );
    e = exp_add( e, #"hash_1e539a520321d8b3", "" );
    e = exp_add( e, #"hash_1e5720520324f23c", "" );
    e = exp_add( e, #"hash_1e5aa65203280bc5", "" );
    e = exp_add( e, #"hash_1e5e2c52032b254e", "" );
    e = exp_add( e, #"hash_1e613252032d6557", "" );
    e = exp_add( e, #"hash_25e3703522d7fbc6", "" );
    e = exp_add( e, #"hash_2b9b24c7aa4ff20c", "" );
    e = exp_add( e, #"hash_31195bd8473a4c2c", "" );
    e = exp_add( e, #"hash_31195cd8473a4ddf", "" );
    e = exp_add( e, #"hash_31195dd8473a4f92", "" );
    e = exp_add( e, #"hash_32a1eed48d303c7b", "" );
    e = exp_add( e, #"hash_32a1efd48d303e2e", "" );
    e = exp_add( e, #"hash_32a1f1d48d304194", "" );
    e = exp_add( e, #"hash_3601eb67de812145", "" );
    e = exp_add( e, #"hash_371c978ddaaab67f", "" );
    e = exp_add( e, #"hash_39138ae11c6b64db", "" );
    e = exp_add( e, #"hash_3a35df59758f6f08", "" );
    e = exp_add( e, #"hash_3b726a2d7c417cb6", "" );
    e = exp_add( e, #"hash_3cbca90c4e0f48f2", "" );
    e = exp_add( e, #"hash_40ecb95335967f20", "" );
    e = exp_add( e, #"hash_410e13b64a0b672a", "" );
    e = exp_add( e, #"hash_4334f5f60ffd7b7e", "" );
    e = exp_add( e, #"hash_4334f6f60ffd7d31", "" );
    e = exp_add( e, #"hash_51ba5f64d31a9e1c", "" );
    e = exp_add( e, #"hash_53d5e94fb2c3dfbb", "" );
    e = exp_add( e, #"hash_5668e8fa68d4ed43", "" );
    e = exp_add( e, #"hash_5aa0968f07933184", "" );
    e = exp_add( e, #"hash_5c205a6d18c7f9df", "" );
    e = exp_add( e, #"hash_6339328e9143f079", "" );
    e = exp_add( e, #"hash_63e9ed274082cf68", "" );
    e = exp_add( e, #"hash_63e9f3274082d99a", "" );
    e = exp_add( e, #"hash_63e9f4274082db4d", "" );
    e = exp_add( e, #"hash_64b027d8f1da8845", "" );
    e = exp_add( e, #"hash_650664cd4a95eb47", "" );
    e = exp_add( e, #"hash_658bed06abdb3cd9", "" );
    e = exp_add( e, #"hash_66147455862dfeb2", "" );
    e = exp_add( e, #"hash_6b8fea72ed5ae965", "" );
    e = exp_add( e, #"hash_6cd27a9f0c35caef", "" );
    e = exp_add( e, #"hash_6d2eb5bdf8932dd4", "" );
    e = exp_add( e, #"hash_6eead413c6501c99", "" );
    e = exp_add( e, #"hash_6f582adc1a5980f1", "" );
    e = exp_add( e, #"hash_72f6a2b622b809cd", "" );
    e = exp_add( e, #"hash_79c8a76f0eea433f", "" );
    e = exp_add( e, #"hash_7a78d5b68df4b41e", "" );
    e = exp_add( e, #"hash_7cd770d54ad70617", "" );
    e = exp_add( e, #"hash_7d7f3f796dbe399b", "" );
    e = exp_add( e, #"hash_7d8cb7796dc98fdf", "" );
    e = exp_add( e, #"hash_7d903d796dcca968", "" );
    e = exp_add( e, #"hash_7e6db5d8f095cfd4", "" );
    e = exp_add( e, #"hash_7e6db6d8f095d187", "" );
    e = exp_add( e, #"hash_7e6db8d8f095d4ed", "" );
    return e;
}

function private exp_rows_wz_golova()
{
    e = [];
    e = exp_add( e, #"hash_7aac4ff7e7defdd", "" );
    e = exp_add( e, #"hash_d1d401c4c43e4cb", "" );
    e = exp_add( e, #"hash_3601eb67de812145", "" );
    e = exp_add( e, #"hash_3a35df59758f6f08", "" );
    e = exp_add( e, #"hash_40ecb95335967f20", "" );
    e = exp_add( e, #"hash_43184cf64995fb19", "" );
    e = exp_add( e, #"hash_5668e8fa68d4ed43", "" );
    e = exp_add( e, #"hash_650664cd4a95eb47", "" );
    e = exp_add( e, #"hash_66147455862dfeb2", "" );
    e = exp_add( e, #"hash_6d81feeba7bda2d4", "" );
    e = exp_add( e, #"hash_6eead413c6501c99", "" );
    e = exp_add( e, #"hash_7cd770d54ad70617", "" );
    e = exp_add( e, #"hash_7e6db5d8f095cfd4", "" );
    e = exp_add( e, #"hash_7e6db6d8f095d187", "" );
    e = exp_add( e, #"hash_7e6db8d8f095d4ed", "" );
    return e;
}

function private exp_rows_wz_sanatorium()
{
    e = [];
    e = exp_add( e, #"hash_9e9be9feb628a64", "" );
    e = exp_add( e, #"hash_d1d401c4c43e4cb", "" );
    e = exp_add( e, #"hash_16e291af57e24bfc", "" );
    e = exp_add( e, #"hash_1aa0910bab9dad08", "" );
    e = exp_add( e, #"hash_1b8ccc2a9c77dcf0", "" );
    e = exp_add( e, #"hash_2181a746a7a30685", "" );
    e = exp_add( e, #"hash_299aeb1daeea4a1d", "" );
    e = exp_add( e, #"hash_2c68a99e217132b6", "" );
    e = exp_add( e, #"hash_3601eb67de812145", "" );
    e = exp_add( e, #"hash_3a35df59758f6f08", "" );
    e = exp_add( e, #"hash_40ecb95335967f20", "" );
    e = exp_add( e, #"hash_4133cbd1b321ab21", "" );
    e = exp_add( e, "lgtexp_lightstate2", "lgtexp_lightstate2" );
    e = exp_add( e, #"hash_4e2d16119c238986", "" );
    e = exp_add( e, #"hash_522a128a675cfb72", "" );
    e = exp_add( e, #"hash_527072edb27db4ec", "" );
    e = exp_add( e, #"hash_527073edb27db69f", "" );
    e = exp_add( e, #"hash_527074edb27db852", "" );
    e = exp_add( e, #"hash_5668e8fa68d4ed43", "" );
    e = exp_add( e, #"hash_63783eafe27148f8", "" );
    e = exp_add( e, #"hash_650664cd4a95eb47", "" );
    e = exp_add( e, #"hash_66147455862dfeb2", "" );
    e = exp_add( e, #"hash_6dcd3d3bdbae6bfc", "" );
    e = exp_add( e, #"hash_6e25d2e8badf4bbd", "" );
    e = exp_add( e, #"hash_6eead413c6501c99", "" );
    e = exp_add( e, #"hash_76190bbf0ac1354a", "" );
    e = exp_add( e, #"hash_7cd770d54ad70617", "" );
    e = exp_add( e, #"hash_7e6db5d8f095cfd4", "" );
    e = exp_add( e, #"hash_7e6db6d8f095d187", "" );
    e = exp_add( e, #"hash_7e6db8d8f095d4ed", "" );
    return e;
}

function private exp_rows_wz_ski_slopes()
{
    e = [];
    e = exp_add( e, #"hash_59b51d6297a9a6c", "" );
    e = exp_add( e, #"hash_7aac4ff7e7defdd", "" );
    e = exp_add( e, #"hash_d1d401c4c43e4cb", "" );
    e = exp_add( e, #"hash_2058d1e36fdbb825", "" );
    e = exp_add( e, #"hash_246719aae602e0e1", "" );
    e = exp_add( e, #"hash_3601eb67de812145", "" );
    e = exp_add( e, #"hash_392656daeab6717c", "" );
    e = exp_add( e, #"hash_3a35df59758f6f08", "" );
    e = exp_add( e, #"hash_40ecb95335967f20", "" );
    e = exp_add( e, #"hash_4c86198df3a33436", "" );
    e = exp_add( e, #"hash_5668e8fa68d4ed43", "" );
    e = exp_add( e, #"hash_585aa09c3fcfd971", "" );
    e = exp_add( e, #"hash_650664cd4a95eb47", "" );
    e = exp_add( e, #"hash_6b2698098fc3d1ae", "" );
    e = exp_add( e, #"hash_6b2699098fc3d361", "" );
    e = exp_add( e, #"hash_6eead413c6501c99", "" );
    e = exp_add( e, #"hash_7cd770d54ad70617", "" );
    e = exp_add( e, #"hash_7e6db5d8f095cfd4", "" );
    e = exp_add( e, #"hash_7e6db6d8f095d187", "" );
    e = exp_add( e, #"hash_7e6db8d8f095d4ed", "" );
    return e;
}

function private exp_rows_wz_zoo()
{
    e = [];
    e = exp_add( e, #"hash_d1d401c4c43e4cb", "" );
    e = exp_add( e, #"hash_3601eb67de812145", "" );
    e = exp_add( e, #"hash_3a35df59758f6f08", "" );
    e = exp_add( e, #"hash_40ecb95335967f20", "" );
    e = exp_add( e, #"hash_5668e8fa68d4ed43", "" );
    e = exp_add( e, #"hash_650664cd4a95eb47", "" );
    e = exp_add( e, #"hash_68d31d90ab323c55", "" );
    e = exp_add( e, #"hash_7032245d6e5c26a4", "" );
    e = exp_add( e, #"hash_7cd770d54ad70617", "" );
    return e;
}
// [exploders-gen END]

// ═════════════════════════════════════════════════════════════════════════════
// PROJECTILES — docs/notes/projectiles.md. Built 2026-09-17, never run.
// ═════════════════════════════════════════════════════════════════════════════
// "Turn bullets into rockets": there is no set-this-weapon's-projectile call in T9, so the SHOT
// is intercepted and a projectile of our own is fired down the same line. The hook is the
// weapon_fired notify the engine raises on the player for every shot (weapons.gsc:1034, the
// event_handler that also drives callback::on_weapon_fired) - the same notify the teleport gun
// rides (tpgun_think), with .weapon on the result (placeables.gsc:215 reads it). The spawn is
// magicbullet( weapon, start, end, owner ) (remotemissile_shared.gsc:415, straferun.gsc:897),
// which RETURNS the projectile entity; a 5th arg / missile_settarget( ent ) makes it HOME
// (helicopter_shared.gsc:3276, straferun.gsc:899). The owner is the shooter, so the kill and
// the killcam credit him (.ismagicbullet is what stock's attribution consults).
//
// Every projectile weapon here is UNIVERSAL - resident on all 36 MP maps by the bgcache
// (projectiles.md §6: launcher_freefire_t9 / launcher_standard_t9 / special_crossbow_t9 /
// special_grenadelauncher_t9 / sig_bow_flame / straferun_rockets / remote_missile_bomblet /
// jetfighter_missile / frag_grenade sit in core_common or mp_common) - so there is no per-map
// gating; getweapon( name ) != level.weaponnone is still checked, stock's own sentinel
// (weapons.gsc:30). ⚠ crossbow_special_t8, the name §2 first listed, is in ZERO zones.
//
// The four unknowns the note names, and what this build does about each:
//   1 full-auto = a magicbullet per shot (~12/s on an AR): a per-player minimum gap, default
//     300 ms, walkable to "every shot" from the Rate page. That is the measurement.
//   2 self-damage: the rocket starts 32 u ahead of the eye, or at the eye when a wall is
//     closer than 64 u (it will then explode in the shooter's face - RPG rules).
//   3 residency - answered offline, above.
//   4 the real bullet still fires: this is "bullets PLUS rockets" until measured otherwise.
// Trail FX: playfxontag( "destruct/fx8_atk_chppr_smk_trail", rocket, "tag_origin" ) - a plain
// path the way infect.gsc:1229 passes one, universal by the fx rows - OFF by default: the
// rocket weapons carry their own trails, and an FX call is the one line here stock never
// makes on a magicbullet.
//
// State is per MATCH (game. / player fields, like the teleport gun) - not dvars, so the
// packed store and the app's key list stay untouched: game.gf_proj_all (everyone, humans),
// player.gf_proj (one player), game.gf_proj_wkey (weapon name), game.gf_proj_ms (min gap),
// game.gf_proj_homing, game.gf_proj_trail. Shots while the host's menu is open are menu
// navigation (ATTACK = next item) and ignored, as the teleport gun does.

function private proj_wkey()
{
    if ( isdefined( game.gf_proj_wkey ) )
        return game.gf_proj_wkey;

    return #"launcher_freefire_t9";
}

function private proj_ms()
{
    if ( isdefined( game.gf_proj_ms ) )
        return game.gf_proj_ms;

    return 300;
}

function private proj_wanted( player )
{
    if ( isdefined( player.gf_proj ) && player.gf_proj )
        return true;

    return isdefined( game.gf_proj_all ) && game.gf_proj_all && !isbot( player );
}

function private proj_rearm( player )
{
    player notify( #"gf_proj_restart" );

    if ( isalive( player ) && proj_wanted( player ) )
        player thread proj_think();
}

// mod_spawn_place: the per-life thread for whoever wants it.
function private proj_spawn_rearm()
{
    if ( !isplayer( self ) )
        return;

    proj_rearm( self );
}

function private proj_think()
{
    self notify( #"gf_proj_restart" );
    self endon( #"gf_proj_restart" );
    self endon( #"disconnect" );
    self endon( #"death" );

    w = getweapon( proj_wkey() );

    if ( !isdefined( w ) || w == level.weaponnone )
    {
        mod_host_say( "^1projectiles: weapon not found on this map" );
        return;
    }

    self.gf_proj_last = 0;

    for ( ;; )
    {
        res = self waittill( #"weapon_fired" );

        if ( !proj_wanted( self ) )
            return;

        if ( self tp_menu_open() )
            continue;

        // our own launcher / the projectile weapon itself: never chain
        if ( isdefined( res.weapon ) && res.weapon == w )
            continue;

        now = gettime();

        if ( now - self.gf_proj_last < proj_ms() )
            continue;

        self.gf_proj_last = now;
        self proj_fire( w );
    }
}

function private proj_fire( w )
{
    eye = self geteye();
    fwd = anglestoforward( self getplayerangles() );
    start = eye + vectorscale( fwd, 32 );
    tr = bullettrace( eye, eye + vectorscale( fwd, 64 ), 0, self );

    if ( tr[ #"fraction" ] < 1 )
        start = eye;

    p = magicbullet( w, start, eye + vectorscale( fwd, 10000 ), self );

    if ( !isdefined( p ) )
        return;

    if ( isdefined( game.gf_proj_homing ) && game.gf_proj_homing )
    {
        target = self proj_target( eye, fwd );

        if ( isdefined( target ) )
            p missile_settarget( target, ( 0, 0, 0 ) );
    }

    if ( isdefined( game.gf_proj_trail ) && game.gf_proj_trail )
        playfxontag( "destruct/fx8_atk_chppr_smk_trail", p, "tag_origin" );
}

// The living enemy nearest the crosshair inside a ~45 degree cone (dot > 0.7), bots included.
// A shooter with no team, or on the free team, may lock anyone but himself.
function private proj_target( eye, fwd )
{
    best = undefined;
    bestdot = 0.7;

    foreach ( player in getplayers() )
    {
        if ( player == self || !isalive( player ) )
            continue;

        if ( isdefined( self.team ) && isdefined( player.team ) && self.team == player.team && self.team != #"free" )
            continue;

        dot = vectordot( fwd, vectornormalize( ( player.origin + ( 0, 0, 40 ) ) - eye ) );

        if ( dot > bestdot )
        {
            bestdot = dot;
            best = player;
        }
    }

    return best;
}

// who = "host" (self.gf_proj) | "all" (game.gf_proj_all, humans only) | "off" (everything).
function private act_proj( item, who )
{
    if ( who == "off" )
    {
        game.gf_proj_all = 0;

        foreach ( player in getplayers() )
        {
            player.gf_proj = 0;
            proj_rearm( player );
        }

        broadcast_feed( "^3projectile fire OFF" );
        self menu_say( "^2projectiles OFF for everyone" );
        return true;
    }

    if ( who == "all" )
    {
        on = !( isdefined( game.gf_proj_all ) && game.gf_proj_all );
        game.gf_proj_all = on;
        item.activated = on;

        foreach ( player in getplayers() )
            proj_rearm( player );

        broadcast_feed( on ? ( "^3your shots now fire " + proj_wname() ) : "^3projectile fire OFF" );
        self menu_say( on ? ( "^2projectiles ON for everyone (not bots): " + proj_wname() ) : "^2projectiles OFF for everyone" );
        return true;
    }

    if ( who != "host" )
    {
        self menu_say( "^1projectiles: host, all or off" );
        return true;
    }

    on = !( isdefined( self.gf_proj ) && self.gf_proj );
    self.gf_proj = on;
    item.activated = on;
    proj_rearm( self );
    self menu_say( on ? ( "^2projectiles ON - your shots fire " + proj_wname() ) : "^2projectiles OFF" );
    return true;
}

function private proj_wname()
{
    if ( isdefined( game.gf_proj_wname ) )
        return game.gf_proj_wname;

    return "RPG rockets";
}

// A weapon pick: stored, validated against level.weaponnone, live threads restarted so the
// next shot uses it. name = the weapon asset (hash), label = what the feed says.
function private act_proj_weapon( item, name, label )
{
    w = getweapon( name );

    if ( !isdefined( w ) || w == level.weaponnone )
    {
        self menu_say( "^1" + label + ": weapon not found on this map" );
        return true;
    }

    game.gf_proj_wkey = name;
    game.gf_proj_wname = label;
    self menu_mark_only( "proj_weapon", item );

    foreach ( player in getplayers() )
        proj_rearm( player );

    self menu_say( "^2projectile: " + label );
    return true;
}

function private act_proj_rate( item, ms )
{
    game.gf_proj_ms = ms;
    self menu_mark_only( "proj_rate", item );
    self menu_say( ms > 0 ? ( "^2projectile rate: one per " + ms + " ms" ) : "^2projectile rate: EVERY shot" );
    return true;
}

function private act_proj_homing( item )
{
    on = !( isdefined( game.gf_proj_homing ) && game.gf_proj_homing );
    game.gf_proj_homing = on;
    item.activated = on;
    self menu_say( on ? "^2homing ON - locks the enemy you face" : "^2homing OFF" );
    return true;
}

function private act_proj_trail( item )
{
    on = !( isdefined( game.gf_proj_trail ) && game.gf_proj_trail );
    game.gf_proj_trail = on;
    item.activated = on;
    self menu_say( on ? "^2smoke trail ON (untested FX call)" : "^2smoke trail OFF" );
    return true;
}

// The [ON] marker as a radio group for game.-backed choices (the * marker reads dvars).
function private menu_mark_only( page, item )
{
    menu = self.gfmenu.menus[ page ];

    if ( !isdefined( menu ) )
        return;

    foreach ( it in menu.items )
        it.activated = 0;

    if ( isdefined( item ) )
        item.activated = 1;
}

// ═════════════════════════════════════════════════════════════════════════════
// PROPS — docs/notes/static-props.md. Built 2026-09-17, never run.
// ═════════════════════════════════════════════════════════════════════════════
// A prop is Prop Hunt's own recipe (prop.gsc:1946): spawn( "script_model", origin ) +
// setmodel( name ) + setscale( scale ). A plain replicated entity - Gate 2 does not apply, a
// vanilla joiner sees it - and the only gate is the xmodel being resident, which
// isassetloaded( "xmodel", name ) answers (MEASURED 2026-09-15: row-0 of Diesel's table read
// res=1 with the bogus control at 0, so "xmodel" IS a valid type string; static-props.md).
//
// Two sources, both self-configuring:
//   - THIS MAP's curated Prop Hunt table, gamedata/tables/mp/<map>_ph.csv (prop.gsc:1850):
//     model, size, scale, offsets, rotation - the per-map list Treyarch hand-tuned. Read at
//     runtime with tablelookuprowcount / tablelookuprow (the census already does). Maps with
//     no table (Ruka measured tbl=0) get only the universal set.
//   - the UNIVERSAL set: the 12 *_prophunt models (all in mp_common) + a hand-picked slice of
//     the 338 p9_* props core_bootstrap / core_common / mp_common carry (static-props.md §5b),
//     resident on every MP map by construction. Every row is still gated by isassetloaded.
// Placement: where the host is looking (the teleport's trace), pushed 24 u off the surface,
// dropped to the floor (playerphysicstrace), turned to face the host. Props are tracked on
// level.gf_props for delete-last / delete-all; level is rebuilt per round, so a round
// boundary clears the list (the engine deletes the entities with the level).

function private prop_universal()
{
    if ( isdefined( level.gf_prop_universal ) )
        return level.gf_prop_universal;

    m = [];
    // the 12 Treyarch authored FOR Prop Hunt, all mp_common
    m = prop_def( m, "p9_barrel_metal_rusted_01_prophunt", "Rusted barrel (PH)" );
    m = prop_def( m, "p9_krail_concrete_worn_01_prophunt", "Concrete K-rail (PH)" );
    m = prop_def( m, "p9_rm_rai_dub_vase_prophunt", "Vase (PH)" );
    m = prop_def( m, "p9_ang_satellite_panel_02_prophunt", "Satellite panel (PH)" );
    m = prop_def( m, "p9_ang_satellite_panel_03_prophunt", "Satellite panel 3 (PH)" );
    m = prop_def( m, "p9_ang_satellite_capsule_plate_02_prophunt", "Capsule plate (PH)" );
    m = prop_def( m, "p9_nt6_abandoned_mattress_01_prophunt", "Mattress (PH)" );
    m = prop_def( m, "p9_nt6_mannequin_clothes_female_02_dmg_full_prophunt", "Mannequin F2 (PH)" );
    m = prop_def( m, "p9_nt6_mannequin_clothes_female_03_dirty_full_prophunt", "Mannequin F3 (PH)" );
    m = prop_def( m, "p9_nt6_mannequin_clothes_male_01_dirty_full_prophunt", "Mannequin M1 (PH)" );
    m = prop_def( m, "p9_ger_tank_computer_server_diagnostic_01_silver_prophunt", "Server rack (PH)" );
    m = prop_def( m, "p9_ger_tank_tank_tread_rolls_01_prophunt", "Tank tread rolls (PH)" );
    // universal p9_* scenery (static-props.md §5b)
    m = prop_def( m, "p9_usa_bench_01", "Park bench" );
    m = prop_def( m, "p9_usa_bicycle_01", "Bicycle" );
    m = prop_def( m, "p9_usa_couch_04", "Couch" );
    m = prop_def( m, "p9_usa_dumpster_01_full", "Dumpster" );
    m = prop_def( m, "p9_usa_mailbox_01", "Mailbox" );
    m = prop_def( m, "p9_usa_street_light_01", "Street light" );
    m = prop_def( m, "p9_usa_vending_machine_soda_02", "Soda machine" );
    m = prop_def( m, "p9_usa_kgb_target_dummy_01", "Target dummy" );
    m = prop_def( m, "p9_usa_chair_beach", "Beach chair" );
    m = prop_def( m, "p9_usa_surf_longboard_01", "Surfboard" );
    m = prop_def( m, "p9_nt6_arcade_game", "Arcade game" );
    m = prop_def( m, "p9_nt6_machine_washing_dirty", "Washing machine" );
    m = prop_def( m, "p9_nt6_refrigerator_vintage_closed_02", "Vintage fridge" );
    m = prop_def( m, "p9_nt6_chair_wood", "Wooden chair" );
    m = prop_def( m, "p9_nt6_barricade_tire_01", "Tire barricade" );
    m = prop_def( m, "p9_nt6x_win_snowman", "Snowman" );
    m = prop_def( m, "p9_mal_arcade_cabinet_08", "Arcade cabinet" );
    m = prop_def( m, "p9_mal_rocket_ride_01", "Kiddie rocket ride" );
    m = prop_def( m, "p9_mal_scissor_lift_01", "Scissor lift" );
    m = prop_def( m, "p9_mal_bean_bag_chair_sml", "Bean bag" );
    m = prop_def( m, "p9_rus_amk_telephonebooth_01_closed_v2_wet", "Phone booth" );
    m = prop_def( m, "p9_rus_bench_park_long", "Long park bench" );
    m = prop_def( m, "p9_rus_oil_drum_01", "Oil drum" );
    m = prop_def( m, "p9_rus_computer_server_02", "Computer server" );
    m = prop_def( m, "p9_ger_kgb_mount_barrier_concrete_144", "Concrete barrier 144" );
    m = prop_def( m, "p9_ger_tank_barrel_metal_01", "Metal barrel" );
    m = prop_def( m, "p9_ger_tank_gas_pump_01", "Gas pump" );
    m = prop_def( m, "p9_lat_sandbag_cover_02_grime", "Sandbag cover" );
    m = prop_def( m, "p9_lat_hedgehog_metal_snow", "Czech hedgehog" );
    m = prop_def( m, "p9_usa_large_ammo_crate_01", "Large ammo crate" );
    m = prop_def( m, "p9_rm_zoo_hay_bale_sqr", "Hay bale" );
    m = prop_def( m, "p9_rm_pai_wooden_spool", "Wooden spool" );
    m = prop_def( m, "p9_rm_rai_water_cooler_metal_full", "Water cooler" );
    m = prop_def( m, "p9_foliage_tree_palm_coconut_lrg_01", "Palm tree" );
    m = prop_def( m, "p9_pot_of_gold_pristine", "Pot of gold" );
    m = prop_def( m, "p9_wz_dirty_bomb_01", "Dirty bomb" );
    m = prop_def( m, "p9_m114_155mm_artillery_gun_01_pickup", "155mm artillery gun" );
    level.gf_prop_universal = m;
    return m;
}

function private prop_def( m, model, label )
{
    st = spawnstruct();
    st.model = model;
    st.label = label;
    st.scale = 1;
    m[ m.size ] = st;
    return m;
}

// This map's Prop Hunt table as rows (model, size text, scale), or an empty array.
function private prop_map_rows()
{
    if ( isdefined( level.gf_prop_maprows ) )
        return level.gf_prop_maprows;

    rows = [];
    mapname = level.script;

    if ( !isdefined( mapname ) )
        mapname = util::get_map_name();

    path = "gamedata/tables/mp/" + mapname + "_ph.csv";

    if ( isassetloaded( "stringtable", path ) )
    {
        numrows = tablelookuprowcount( path );

        if ( !isdefined( numrows ) )
            numrows = 0;

        for ( i = 0; i < numrows && i < 64; i++ )
        {
            model = assets_table_cell( path, i, 0 );

            if ( !isdefined( model ) || model == "" )
                continue;

            size = assets_table_cell( path, i, 1 );
            scale = float( assets_table_cell( path, i, 2 ) );

            if ( !isdefined( scale ) || scale == 0 )
                scale = 1;

            st = spawnstruct();
            st.model = model;
            st.label = prop_short( model ) + " (" + size + ")";
            st.scale = scale;
            rows[ rows.size ] = st;
        }
    }

    level.gf_prop_maprows = rows;
    return rows;
}

// "p9_usa_bench_01" -> "usa_bench_01": the family prefix carries no information on a row.
function private prop_short( model )
{
    if ( model.size > 3 && getsubstr( model, 0, 3 ) == "p9_" )
        return getsubstr( model, 3 );

    if ( model.size > 3 && getsubstr( model, 0, 3 ) == "p8_" )
        return getsubstr( model, 3 );

    return model;
}

// Where a prop goes: the aim point pushed 24 u off the surface and floored; a shot into the
// sky puts it 200 u ahead of the host, floored.
function private prop_spot()
{
    eye = self geteye();
    fwd = anglestoforward( self getplayerangles() );
    tr = bullettrace( eye, eye + vectorscale( fwd, 4000 ), 0, self );

    if ( tr[ #"fraction" ] >= 1 )
        return tp_floor( self.origin + vectorscale( ( fwd[ 0 ], fwd[ 1 ], 0 ), 200 ) );

    pos = tr[ #"position" ];

    if ( isdefined( tr[ #"normal" ] ) )
        pos += vectorscale( tr[ #"normal" ], 24 );

    return tp_floor( pos );
}

function private act_prop_spawn( item, model, scale )
{
    if ( !isdefined( scale ) )
        scale = 1;

    if ( !isassetloaded( "xmodel", model ) )
    {
        self menu_say( "^1model not resident on this map: " + model );
        return true;
    }

    spot = self prop_spot();

    if ( !isdefined( spot ) )
    {
        self menu_say( "^1no spot found" );
        return true;
    }

    ang = self getplayerangles();
    prop = spawn( "script_model", spot );

    if ( !isdefined( prop ) )
    {
        self menu_say( "^1spawn failed" );
        return true;
    }

    prop.targetname = "gf_prop";
    prop setmodel( model );

    if ( scale != 1 )
        prop setscale( scale );

    prop.angles = ( 0, ang[ 1 ] + 180, 0 );

    if ( !isdefined( level.gf_props ) )
        level.gf_props = [];

    level.gf_props[ level.gf_props.size ] = prop;
    self menu_say( "^2placed " + prop_short( model ) + " (" + level.gf_props.size + " this round)" );
    return true;
}

function private act_prop_delete( item, all )
{
    if ( !isdefined( level.gf_props ) || level.gf_props.size == 0 )
    {
        self menu_say( "^1no props placed this round" );
        return true;
    }

    if ( all )
    {
        n = 0;

        foreach ( p in level.gf_props )
        {
            if ( isdefined( p ) )
            {
                p delete();
                n++;
            }
        }

        level.gf_props = [];
        self menu_say( "^2removed " + n + " props" );
        return true;
    }

    last = level.gf_props[ level.gf_props.size - 1 ];
    kept = [];

    for ( i = 0; i < level.gf_props.size - 1; i++ )
        kept[ kept.size ] = level.gf_props[ i ];

    level.gf_props = kept;

    if ( isdefined( last ) )
        last delete();

    self menu_say( "^2removed the last prop (" + kept.size + " left)" );
    return true;
}

// Rebuilt on entry: the map's table can only be read once the level is up, and the
// resident filter is per map.
function private props_enter( menu )
{
    self menu_clear_items( "props" );

    rows = prop_map_rows();
    self menu_item( "props", "Remove the last prop I placed", &act_prop_delete, 0 );
    self menu_item( "props", "Remove every prop I placed", &act_prop_delete, 1 );
    self menu_item( "props", "This map's Prop Hunt set (" + rows.size + ")", &menu_switch, "props_map" );
    self menu_item( "props", "Universal props", &menu_switch, "props_univ" );
}

function private props_map_enter( menu )
{
    self menu_clear_items( "props_map" );

    n = 0;

    foreach ( r in prop_map_rows() )
    {
        if ( !isassetloaded( "xmodel", r.model ) )
            continue;

        self menu_item( "props_map", "Place " + r.label, &act_prop_spawn, r.model, r.scale );
        n++;
    }

    if ( n == 0 )
        self menu_item( "props_map", "(no Prop Hunt table on this map - use Universal)", undefined );
}

function private props_univ_enter( menu )
{
    self menu_clear_items( "props_univ" );

    n = 0;

    foreach ( r in prop_universal() )
    {
        if ( !isassetloaded( "xmodel", r.model ) )
            continue;

        self menu_item( "props_univ", "Place " + r.label, &act_prop_spawn, r.model, r.scale );
        n++;
    }

    if ( n == 0 )
        self menu_item( "props_univ", "(none of the universal models read resident here)", undefined );
}

// App verb: place a universal prop by its model name or label prefix (case-insensitive).
function private cmd_prop( arg )
{
    want = tolower( arg );

    foreach ( r in prop_universal() )
    {
        if ( tolower( r.model ) == want || tolower( r.label ) == want )
            return self act_prop_spawn( spawnstruct(), r.model, r.scale );
    }

    foreach ( r in prop_map_rows() )
    {
        if ( tolower( r.model ) == want )
            return self act_prop_spawn( spawnstruct(), r.model, r.scale );
    }

    if ( want != "" && isassetloaded( "xmodel", arg ) )
        return self act_prop_spawn( spawnstruct(), arg, 1 );

    self menu_say( "^1prop: no such model here '" + arg + "'" );
    return true;
}


// ── Map ──────────────────────────────────────────────────────────────────────
//
// A map or gametype pick no longer switches on the spot: it opens one more page with
// the two verbs klaze asked for (2026-09-12).
//
//   Stage for lobby   switchmap_load( map, gametype ) and NOTHING else. The match keeps
//                     running where it is; when it ends, the pregame lobby comes up
//                     with the staged map already selected, ready to start. klaze
//                     measured this by ending a match during the 25s wait below, i.e.
//                     after the load half and before switchmap_switch() - the lobby
//                     showed the new map. That is the lobby's own selection reached
//                     from in-match GSC (the layer docs/notes/lobby-setters.md targets
//                     with a native call), so the next match launches from the lobby
//                     the normal way. docs/notes/session-switch.md - "Stage".
//                     ⚠ 2026-09-14: the load is ASYNC - a match ended before it completes
//                     discards the stage (measured: Stage gunfight + immediate end = lobby
//                     still TDM). The verb now waits for the load notify and prints STAGE
//                     READY; end the match after that. do_session_stage has the record.
//   Switch NOW        switchmap_load + switchmap_switch: the verified in-match session
//                     switch, unchanged.
//
// The 12v12-layout entries and the Gametype page go through the same page, so a
// gametype can be staged too. ⚠ Inferred from the map result - same builtin, same two
// arguments - not measured on its own yet.

function private act_switch_wait( item, secs )
{
    cfg_seti( #"gf_switch_wait", secs );
    self menu_say( secs > 0 ? ( "^2switch waits up to " + secs + "s for the load notify" ) : "^2switch commits after one network frame - cp form" );
    return true;
}

function private act_map_method( item )
{
    method = cfg_map_method() ? 0 : 1;
    cfg_seti( #"gf_map_method", method );
    item.activated = method;
    self menu_say( method ? "^2map method: SESSION - lobby follows, restart via lobby or F7" : "^3map method: CARRY - load-time only, lobby stays stale, F7 ONLY" );
    return true;
}

// A map pick: the current gametype rides along.
// A pick of the CURRENT map is allowed on purpose (klaze, 2026-09-13): it is a forced
// reload through the same session route - Stage / Switch NOW confirm it, so nothing
// happens on the first press.
function private act_map( item, map_name )
{
    current = tolower( getdvarstring( #"sv_mapname" ) );

    if ( current == map_name )
        self menu_say( "^3" + map_name + " is the current map - this will RELOAD it" );

    return self map_pick_open( map_name, tolower( getdvarstring( #"g_gametype" ) ), item.name );
}

// Map AND gametype in one pick - the "12v12 layouts" entries, whose map scripts only
// open the large boundary for a 10v10/12v12 gametype string. Always the session route:
// the map() carry cannot carry a gametype at all (roadmap Goal B).
function private act_map_gt( item, map_name, gametype )
{
    return self map_pick_open( map_name, gametype, item.name );
}

// The stage/now page. Rebuilt on every pick the way act_player_page rebuilds a player's
// page; its parent is the list the pick came from, so V (back) returns there. Stage is
// the first row on purpose: it is the verb that cannot pull a live match out from under
// everybody, so a double-tap on R stages rather than switches.
function private map_pick_open( map_name, gametype, label )
{
    self.gfmenu.pick = { #map: map_name, #gt: gametype };
    self menu_add( "map_pick", label, self.gfmenu.current, 0 );
    self menu_item( "map_pick", "Stage for lobby - next match", &act_pick_stage );
    self menu_item( "map_pick", "Switch NOW", &act_pick_now );
    return self menu_switch( undefined, "map_pick" );
}

function private act_pick_stage( item )
{
    p = self.gfmenu.pick;
    self menu_say( "^2staging " + p.map + " / " + p.gt + " - do not end the match until STAGE READY" );
    self thread do_session_stage( p.map, p.gt );
    return false;
}

function private act_pick_now( item )
{
    p = self.gfmenu.pick;
    self menu_say( "^3loading " + p.map + " / " + p.gt + "..." );

    // Threaded onto the PLAYER with no endons. See the header: this satisfies
    // both the endon theory (A4) and the self=player theory (A4 run 4) at once,
    // without deciding between them.
    self thread do_map_switch( p.map, p.gt );
    return false;
}

// gf_staged_* feed the state line's "next:" tail and nothing else - the engine's own
// staged map is not readable from script. Cleared at every match start (whatever the
// lobby launched IS the lobby's pick) and by any NOW switch, which supersedes a stage.
function private stage_mark( map_name, gametype )
{
    cfg_seti( #"gf_staged_map", map_name );
    cfg_seti( #"gf_staged_gt", gametype );
}

// The load half of the session switch, never the switch half. Threaded off the menu
// loop like the switch so a slow load cannot stall menu_think; no endons for the same
// reason as do_session_switch. Marked AFTER the call so the state line never claims a
// stage the engine has not seen.
// A deliberate pick of a NON-Gunfight gametype means the host wants that mode - so disarm
// auto-Gunfight, or the next match would immediately switch back. Gunfight picks leave it
// armed. Called on the host, where self.gfmenu exists (menu action); the autoswitch path
// only ever passes "gunfight" here, so the menu_say branch never runs off a bare host.
function private autoswitch_disarm_for( gametype )
{
    if ( !cfg_autoswitch() )
        return;

    if ( gametype == "gunfight" || gametype == "gunfight_3v3" )
        return;

    cfg_seti( #"gf_autoswitch", 0 );
    self menu_say( "^3auto-Gunfight off - you picked " + gametype );
}

function private do_session_stage( map_name, gametype )
{
    self autoswitch_disarm_for( gametype );
    veh_sweep_for_transition( "stage" );      // no menu-spawned vehicle may sit through a level load
    mode_profile_prime( gametype );
    switchmap_load( map_name, gametype );
    stage_mark( map_name, gametype );

    // MEASURED 2026-09-14 (klaze): Stage followed by an immediate End Game left the lobby
    // on the OLD gametype (TDM match -> Stage gunfight -> end -> lobby still TDM), while the
    // very same load reached through Switch NOW - end the match DURING its wait - put
    // Gunfight in the lobby (and the 2026-09-12 Stage discovery was made that way too).
    // The load is asynchronous: the engine commits the pair to the session when the load
    // completes, and a match ended before that discards it. So this holds for the same
    // notify the switch waits on and SAYS when it lands - the host ends the match after
    // the STAGE READY line, not before. Only the first load of a session is known to fire
    // the notify (later ones sit the cap, docs/notes/session-switch.md); past the cap the
    // load has still almost certainly completed, so the message says that, not "failed".
    // No endons: the thread must survive the menu closing, like do_session_switch.
    self menu_say( "^3staging " + map_name + " / " + gametype + " - wait for STAGE READY before ending the match" );

    w = cfg_switch_wait();
    if ( w <= 0 )
        w = 25;

    r = level waittilltimeout( w, #"switchmap_preload_finished" );

    if ( isdefined( r ) && isdefined( r._notify ) && r._notify == #"timeout" )
        self iprintlnbold( "^3STAGE READY (no load notify in " + w + "s - normal after the first switch): " + map_name + " / " + gametype );
    else
        self iprintlnbold( "^2STAGE READY - load finished: " + map_name + " / " + gametype + " - end the match when you like" );
}

// What the session switch does NOT move: the settings blob. switchmap_load moves the
// session's map and gametype (the lobby's summary header follows), but the mode config the
// lobby launched with - MODE line, rules, compat set - stays, and its settings survive into
// the next match (LS6). So a Gunfight reached from TDM is "Gunfight on TDM's settings".
// This writes the settings the target mode cannot run without, BEFORE the load, so they
// travel with the session (Stage: into the lobby's next launch; NOW: into the new match).
// mod_apply asserts the same at match start, which covers a lobby launch that rebuilds
// the blob. Only the Gunfight-critical key is known; everything else in the blob is
// measured by the census (Display -> Settings census) before it gets baked in here.
// ── The Gunfight profile: column A, measured 2026-09-14 ─────────────────────
// docs/notes/mode-remnants.md "Column A". A Gunfight level reached by an in-match Switch NOW
// from TDM runs g_gametype=gunfight on the TDM match's settings blob (LS6), and klaze sees
// TDM rules bleed into play. (A LOBBY launch does not do this - column B == A, see
// profile_is_hybrid.) These are the REAL Gunfight blob's values, read with the launch
// census, for every key the mod does not already manage (timer -> gf_timer;
// rounds-per-loadout / spy plane / loadout index / customcac / maxplayers / prematch /
// preround / roundswitch -> their own settings), asserted so the hybrid plays as A.
//
// Two writes per key. The SETTING, so every later read agrees and so a stage carries it
// across a round boundary. And, in-match only, the
// LEVEL VAR globallogic copied out of the blob BEFORE this callback ran - function_b9b7618
// (globallogic.gsc:5030-5188) and the util.gsc register* calls from init() (:364-369) - which
// is what THIS round actually reads: a setting written here alone would take effect one
// round late. in_match is kept for a settings-only caller; every current caller is in-match.
//
// The first thing a TDM blob breaks is playerNumLives (unlimited = respawns inside a round
// and no elimination round-end, gunfight.gsc ondeadevent via globallogic's numlives gate)
// and scoreLimit (a kill limit Gunfight never reaches as 0). disableClassSelection is now
// READ as 1 in A, so the 2026-09-13 caveat against forcing it is lifted - it is asserted
// with customcac (0 when the host wants custom classes, which need class selection).
// gf_profile 0 turns the whole assertion off (to watch the raw hybrid on purpose).
// Is this level running Gunfight on ANOTHER mode's blob? MEASURED 2026-09-14: a lobby launch
// rebuilds the blob from the SESSION gametype's preset - a Case-B lobby (TDM config, gunfight
// session) launched column B == column A, the real Gunfight blob. The only way a TDM blob
// reaches a Gunfight level is an in-match Switch NOW (LS6: the current match's settings ride
// the switch). So the profile must fire there and NOWHERE else - on a real Gunfight blob it
// would trample the host's own Gunfight rules-page choices (round win limit 4, rounds per
// loadout 3, ...) with A's constants. The real blob always has playerNumLives=1 and a
// roundWinLimit of 1-6 (the Gunfight rules row publishes 1-6, never 0); TDM's has 0 and 0
// (column T). Read BEFORE anything writes them; latched per level.
function private profile_is_hybrid()
{
    if ( isdefined( level.gf_hybrid ) )
        return level.gf_hybrid;

    nl = getgametypesetting( #"playernumlives" );
    rwl = getgametypesetting( #"roundwinlimit" );
    level.gf_hybrid = ( !isdefined( nl ) || nl != 1 || !isdefined( rwl ) || rwl == 0 ) ? 1 : 0;

    if ( level.gf_hybrid )
        broadcast_feed( "^3profile: Gunfight on another mode's blob - asserting the real one" );

    return level.gf_hybrid;
}

function private mode_profile_gunfight( in_match )
{
    if ( !cfg_profile() || !profile_is_hybrid() )
        return;

    // Round rules.
    gts_set( #"playernumlives", 1 );
    gts_set( #"scorelimit", 0 );
    gts_set( #"cumulativeroundscores", 0 );
    gts_set( #"teamscoreperkill", 0 );
    rwl = ( cfg_roundwinlimit() >= 0 ) ? cfg_roundwinlimit() : 6;
    rl = ( cfg_roundlimit() >= 0 ) ? cfg_roundlimit() : 0;
    gts_set( #"roundwinlimit", rwl );
    gts_set( #"roundlimit", rl );

    // Respawn shape.
    gts_set( #"playerforcerespawn", 1 );
    gts_set( #"playerqueuedrespawn", 0 );
    gts_set( #"playerrespawndelay", 0 );

    // Loadout surface.
    dcs = cfg_customcac() ? 0 : 1;
    gts_set( #"disableclassselection", dcs );
    gts_set( #"perksenabled", 0 );
    gts_set( #"loadoutkillstreaksenabled", 0 );
    gts_set( #"disableattachments", 0 );
    gts_set( #"disableweapondrop", 0 );
    gts_set( #"disabletacinsert", 0 );

    // Health, damage, radar, pacing.
    gts_set( #"playermaxhealth", 150 );
    gts_set( #"playerhealthregentime", 5 );
    gts_set( #"autoheal", 0 );
    gts_set( #"bulletdamagescalar", 1 );
    gts_set( #"forceradar", 0 );
    gts_set( #"roundstartexplosivedelay", 5 );
    gts_set( #"roundstartkillstreakdelay", 10 );
    gts_set( #"playersprinttime", 4 );
    gts_set( #"spectatetype", 6 );

    if ( !in_match )
        return;

    level.numlives = 1;
    level.graceperiod = 15;                 // function_b9b7618 :5321 derives it from numlives
    level.scorelimit = 0;
    level.cumulativeroundscores = 0;
    level.teamscoreperkill = 0;
    level.roundwinlimit = rwl;
    level.roundlimit = rl;
    level.playerforcerespawn = 1;
    level.playerqueuedrespawn = 0;
    level.playerrespawndelay = 0;
    level.disableclassselection = dcs;
    level.perksenabled = 0;
    level.loadoutkillstreaksenabled = 0;    // player_loadout.gsc:252 copied it at init
    level.disableattachments = 0;
    level.disableweapondrop = 0;
    level.disabletacinsert = 0;
    level.playermaxhealth = 150;
    level.var_90bb9821 = 0;                 // :5172 = playermaxhealth - 150
    level.playerhealthregentime = 5;
    level.autoheal = 0;
    level.bulletdamagescalar = 1;
    level.forceradar = 0;
    level.roundstartexplosivedelay = 5;
    level.roundstartkillstreakdelay = 10;
    level.playersprinttime = 4;
    level.spectatetype = 6;
}

function private act_profile( item, value )
{
    cfg_seti( #"gf_profile", value );
    self menu_say( value ? "^2Gunfight profile ON - the real blob is asserted at every Gunfight match start" : "^3Gunfight profile OFF - a Case-B launch runs on the lobby config's raw blob" );
    return true;
}

function private mode_profile_prime( gametype )
{
    if ( gametype != "gunfight" && gametype != "gunfight_3v3" )
        return;

    dcc = cfg_customcac() ? 0 : 1;
    gts_set( #"disablecustomcac", dcc );
    // Nothing else is primed: MEASURED 2026-09-14, a lobby launch rebuilds the blob from the
    // session gametype's preset (column B == A), so settings written here never reach it.
    // The profile fires in the switched level's own mod_apply instead.
}

function private do_map_switch( map_name, gametype )
{
    // The legacy carry - the Atian Menu's func_set_map, call for call. Load-time only:
    // the lobby keeps its old map and a lobby-route restart discards it. It cannot carry
    // a gametype, so a pick that changes the gametype takes the session route regardless.
    if ( cfg_map_method() == 0 && gametype == tolower( getdvarstring( #"g_gametype" ) ) )
    {
        stage_mark( "", "" );
        veh_sweep_for_transition( "carry" );
        map( map_name );
        wait( 1 );
        switchmap_switch();
        return;
    }

    do_session_switch( map_name, gametype );
}

// ✅ The SESSION move stock's own transitions use - lobby, scoreboard and slot budget
// follow, which the map() carry never did. Runs on the PLAYER with no endons (see header).
//
// The sequence is stock's ZM one VERBATIM - zm_common/zm_utility_zsurvival.gsc:153-155:
// switchmap_load, wait (≤25s) for #"switchmap_preload_finished", switchmap_switch - and it
// is the sequence klaze measured working on 2026-09-12 (the session moved, the lobby
// followed, com_maxclients read 12).
//
// ⚠ REVERTED 2026-09-13. For a few hours today this called switchmap_PRELOAD instead, on
// the theory that only preload fires the notify; klaze reported "Switch NOW seems unstable"
// on that build, and the theory does not survive the dump: Treyarch waits on the notify
// right after switchmap_LOAD (zsurvival above), while switchmap_preload's only callers are
// the campaign's BACKGROUND preload - armed at a checkpoint long before the transition,
// with a cancel_preload path (cp_common/load.gsc:373-376, :388-406) - and the side-mission
// countdown (callbacks_shared.gsc:2227-2231). Nothing in MP preloads. Measured on the old
// build: only the FIRST switch of a session gets the notify, later ones sit the full 25s.
// The half-load report that motivated the change is still open; if it recurs, the next
// stock form to try is the campaign's IMMEDIATE one - switchmap_load, util::wait_network_frame(1),
// switchmap_switch (cp_common/load.gsc:412-414), which never waits on the notify at all.
// ── Auto-switch to Gunfight on a non-Gunfight match ──────────────────────────
// "Make Gunfight the gametype when we inject" (klaze, 2026-09-13). Inject in a TDM lobby,
// restart to link, and this fires the SAME session switch the menu's "Switch NOW" does -
// switchmap_load( current map, "gunfight" ) - so the match becomes real Gunfight without
// touching the menu. Opt-in (gf_autoswitch, default 0) so it changes nothing until asked
// and cannot confound anything else; set it to 1 from the control app (or the Gametype
// page) BEFORE the match restart and it takes on the first linked match. Once we trust it
// the default can flip to 1. ⚠ Built 2026-09-13, never run.
//   - Fires ONCE (game.gf_autoswitch_done - game. survives a round boundary, unlike level.,
//     so a round-based mode cannot re-fire a second concurrent switch during the wait);
//     re-armed from act_autoswitch. Post-switch the match is Gunfight, so mod_is_gunfight()
//     short-circuits before the guard even matters - no reload loop.
//   - A DELIBERATE non-Gunfight pick disarms it (autoswitch_disarm_for in do_session_*),
//     so choosing TDM from the menu does not bounce you straight back to Gunfight.
//   - Fires only AFTER the pre-match countdown (level.inprematchperiod), the mid-match state
//     klaze's manual NOW switches were measured in - not during the frozen countdown.
//   - Needs a host ENTITY, not a live one, so it still fires when klaze hosts as CoD Caster
//     or spectator (ishost(), no isalive requirement).
//   - Keeps the CURRENT map (a big TDM map under Gunfight leans on the spawn guard; pick a
//     Gunfight map from the menu after if you want one). The ~25s switch delay applies
//     (gf_switch_wait); the host loads the original mode first, then gets moved.
function private mod_autoswitch()
{
    if ( !cfg_autoswitch() || mod_is_gunfight() )
        return;

    if ( is_true( game.gf_autoswitch_done ) )
        return;

    game.gf_autoswitch_done = 1;
    level thread mod_autoswitch_do();
}

function private mod_autoswitch_do()
{
    level endon( #"game_ended" );

    // The host ENTITY - not necessarily alive: klaze may host as CoD Caster / spectator, and
    // the switch only needs a player to thread on. Bounded wait (~600 frames, ~30s at a 20Hz
    // server) for it to connect; a match always has a host, so this resolves near instantly.
    host = undefined;
    for ( i = 0; i < 600 && !isdefined( host ); i++ )
    {
        players = getplayers();
        for ( j = 0; j < players.size; j++ )
        {
            if ( players[ j ] ishost() )
                host = players[ j ];
        }

        if ( isdefined( host ) )
            break;

        waitframe( 1 );
    }

    if ( !isdefined( host ) )
        return;

    // Land the switch in the SAME mid-match state klaze's manual NOW switches were measured in.
    // isalive() is already true during the frozen pre-match countdown, so gate on the countdown
    // itself the way stock does (ctf.gsc:725, control.gsc:1109, clean.gsc:683). level endon
    // above bounds it.
    while ( is_true( level.inprematchperiod ) )
        waitframe( 1 );

    map = getdvarstring( #"sv_mapname", "" );
    if ( map == "" )
        return;

    host iprintlnbold( "^3Auto-Gunfight: switching..." );
    host thread do_session_switch( map, "gunfight" );
}

function private do_session_switch( map_name, gametype )
{
    self autoswitch_disarm_for( gametype );

    // A NOW switch supersedes whatever was staged: the lobby will show the map we land on.
    stage_mark( "", "" );
    veh_sweep_for_transition( "switch" );     // the 3rd crash: a Gas Station heli rode a switch into Sanatorium
    mode_profile_prime( gametype );
    switchmap_load( map_name, gametype );

    // ✅ klaze, 2026-09-13, on this sequence: TDM -> Gunfight "actually changes the mode
    // fully" in-match (the lobby's own game options stay on the old mode - that is the
    // lobby config layer, docs/notes/mode-remnants.md). The delay he sees is this wait:
    // gf_switch_wait 25 = stock ZM's cap (proven); 0 = stock campaign's immediate form,
    // one network frame then switch (cp_common/load.gsc:412-414) - untested in MP.
    w = cfg_switch_wait();
    if ( w > 0 )
        level waittilltimeout( w, #"switchmap_preload_finished" );
    else
        util::wait_network_frame( 1 );

    switchmap_switch();
}

// ── Gametype ─────────────────────────────────────────────────────────────────

function private act_autoswitch( item, value )
{
    cfg_seti( #"gf_autoswitch", value );

    // Re-arm: clear the once-per-session guard so enabling it again fires even if a previous
    // arm already switched this game session (game.gf_autoswitch_done would otherwise persist).
    if ( value )
        game.gf_autoswitch_done = undefined;

    if ( value && !mod_is_gunfight() )
        self menu_say( "^2auto-Gunfight ON - switches at the next match start (and on inject)" );
    else if ( value )
        self menu_say( "^2auto-Gunfight ON - already Gunfight, fires when a non-Gunfight match starts" );
    else
        self menu_say( "^2auto-Gunfight OFF" );

    return true;
}

function private act_gametype( item, gt )
{
    current = tolower( getdvarstring( #"g_gametype", "" ) );

    // The current mode is a valid pick: a forced reload of the same mode on the same map
    // (klaze, 2026-09-13). The Stage / Switch NOW page is the confirmation.
    if ( current == gt )
        self menu_say( "^3" + gt + " is the current mode - this will RELOAD it" );

    // Real engine builtin, no stock caller (cw-builtins.md sec 2); lobby_probe linked
    // and ran with it. Refusing here beats handing switchmap_load a name the engine
    // does not know and finding out what that does to a live session.
    if ( !isvalidgametype( gt ) )
    {
        self menu_say( "^1engine rejects gametype " + gt );
        return true;
    }

    // Same stage/now page as a map pick, with the map kept and the gametype swapped.
    return self map_pick_open( tolower( getdvarstring( #"sv_mapname", "" ) ), gt, item.name );
}
