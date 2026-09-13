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
3. **A match launched FROM that lobby is a hybrid**: `g_gametype = gunfight` (the session's) on TDM's
   settings blob (the lobby config's) — "says gunfight but loads TDM rules and custom classes".

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
