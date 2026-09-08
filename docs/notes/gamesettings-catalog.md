# Game-settings bundle catalog — all 427 rules-menu rows

Generated from `scriptbundle/gamesettings/*.json` in `ate47/bocw-source`. **One JSON = one rules-menu
row.** `setting` is the name `getgametypesetting()` / `setgametypesetting()` take; `published` is how
many values the menu offers; **hidden** values are declared in the bundle but not published.

Context and the leads that came out of this: [`lobby-settings.md`](lobby-settings.md).

- **427** bundles, **395** distinct settings
- **184** publish fewer values than they declare
- **17** settings have per-gametype variants (the `_gunfight` / `_dom` / `_ctf` suffix families)

## ⚠ The hidden values are the point

`.claude/CLAUDE.md` records that `time_limit_seconds` "declares 20 values but publishes 6". **That is
not a quirk of the timer — 184 of 427 rows do it.** The menu is a *filtered view* of a wider range, and
`setgametypesetting()` is not filtered. Any row below with a **hidden** list is a setting the game
accepts values for that the menu will not offer.

⚠ A hidden value being declared is not proof the gametype handles it sanely. `time_limit`'s hidden
range is proven good (the clamp is 0–1440 min); nothing else here has been tested.


## Multiplayer — 201 rows

| bundle | setting | published | values |
|---|---|---|---|
| `allow_battle_chatter` | `allowBattleChatter` | 2 | on/off |
| `allow_gestures` | `boastEnabled` | 2 | on/off |
| `allow_gestures_camera_rotate` | `boastAllowCam` | 2 | on/off |
| `allow_hit_markers` | `allowhitmarkers` | 3 | 0 1 2 |
| `allow_ingame_team_change` | `allowInGameTeamChange` | 2 | on/off |
| `allow_killcam` | `killcamMode` | 3 | 0 1 2 |
| `allow_map_scripting` | `allowMapScripting` | 2 | on/off |
| `allow_play_of_the_match` | `allowPlayOfTheMatch` | 2 | on/off |
| `allow_prone` | `allowprone` | 2 | on/off |
| `allow_spectating` | `allowSpectating` | 2 | on/off |
| `auto_decay` | `autoDecayTime` | 12 | 0 1 2 3 4 5 10 15 20 25 30 45 |
| `auto_destroy_time` | `autoDestroyTime` | 9 | 0 30 45 60 90 120 150 180 300 |
| `bag_carrier_move_speed` | `bountyBagOMoneyMoveScale` | 3 | .5 1 1.5 |
| `bleedout_time` | `lastStandTimer` | 12 | 1 2.5 5 7.5 10 15 20 30 45 60 90 120 |
| `bomb_timer` | `bombTimer` | 12 | 2.5 5 7.5 10 15 20 30 45 60 90 120 150 |
| `bonus_lives_for_capturing_zone` | `bonusLivesForCapturingZone` | 29 | 0 1 2 3 4 5 6 7 8 9 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 |
| `boot_time` | `bootTime` | 6 | 0 5 10 15 20 30 |
| `bot_autofill_allies` | `bot_autofill_allies` | 2 | on/off |
| `bot_autofill_axis` | `bot_autofill_axis` | 2 | on/off |
| `bot_autofill_team10` | `bot_autofill_team10` | 2 | on/off |
| `bot_autofill_team3` | `bot_autofill_team3` | 2 | on/off |
| `bot_autofill_team4` | `bot_autofill_team4` | 2 | on/off |
| `bot_autofill_team5` | `bot_autofill_team5` | 2 | on/off |
| `bot_autofill_team6` | `bot_autofill_team6` | 2 | on/off |
| `bot_autofill_team7` | `bot_autofill_team7` | 2 | on/off |
| `bot_autofill_team8` | `bot_autofill_team8` | 2 | on/off |
| `bot_autofill_team9` | `bot_autofill_team9` | 2 | on/off |
| `bot_difficulty_allies` | `bot_difficulty_allies` | 4 | 0 1 2 3 |
| `bot_difficulty_axis` | `bot_difficulty_axis` | 4 | 0 1 2 3 |
| `bot_difficulty_team10` | `bot_difficulty_team10` | 4 | 0 1 2 3 |
| `bot_difficulty_team3` | `bot_difficulty_team3` | 4 | 0 1 2 3 |
| `bot_difficulty_team4` | `bot_difficulty_team4` | 4 | 0 1 2 3 |
| `bot_difficulty_team5` | `bot_difficulty_team5` | 4 | 0 1 2 3 |
| `bot_difficulty_team6` | `bot_difficulty_team6` | 4 | 0 1 2 3 |
| `bot_difficulty_team7` | `bot_difficulty_team7` | 4 | 0 1 2 3 |
| `bot_difficulty_team8` | `bot_difficulty_team8` | 4 | 0 1 2 3 |
| `bot_difficulty_team9` | `bot_difficulty_team9` | 4 | 0 1 2 3 |
| `bot_difficulty_vs_bots` | `bot_difficulty_vs_bots` | 4 | 0 1 2 3 |
| `cap_decay` | `capDecay` | 2 | on/off |
| `capture_time` | `captureTime` | 12 | 1 2.5 5 7.5 10 15 20 30 45 60 90 120 |
| `capture_time_ctf` | `captureTime` | 14 | 0 0.5 1 1.5 2 2.5 3 4 5 6 7 8 9 10 |
| `capture_time_gunfight` | `captureTime` | 7 | 1 2 3 4 5 10 15 · **hidden:** 30 45 60 90 120 |
| `capture_time_koth` | `captureTime` | 11 | 0 1 2 3 4 5 6 7 8 9 10 |
| `carrier_armor` | `carrierArmor` | 4 | 0 100 200 50 |
| `carrier_armor_dropkick` | `dropkickCarrierArmor` | 8 | 0 50 100 150 200 300 400 500 |
| `carrier_drop_bomb` | `carrier_manualDrop` | 2 | on/off |
| `carrier_move_speed` | `carrierMoveSpeed` | 3 | 1 2 3 |
| `carry_score` | `carryScore` | 9 | 1 2 3 4 5 6 7 8 9 |
| `competitive_team_lives` | `competitiveTeamLives` | 2 | on/off |
| `contested_majority_wins` | `gameobjectsContestedMajorityWins` | 3 | 0.5 1 2 |
| `control_overtime` | `overtimeBestTeam` | 2 | 0 1 · **hidden:** 10 15 20 25 30 45 60 4.5 5 |
| `cumulative_round_scores` | `cumulativeRoundScores` | 2 | 1 0 |
| `death_circle` | `deathCircle` | 2 | on/off |
| `decay_captured_zones` | `decayCapturedZones` | 2 | on/off |
| `decay_progress` | `decayProgress` | 2 | on/off |
| `defuse_time` | `defuseTime` | 17 | 1 2.5 3 3.5 4 4.5 5 5.5 6 6.5 7 7.5 8 8.5 9 9.5 10 |
| `destroy_time` | `destroyTime` | 9 | 1 2.5 5 7.5 10 15 20 30 60 |
| `disable_cac` | `disableCustomCAC` | 2 | 0 1 |
| `disable_field_upgrade` | `disableFieldUpgrade` | 2 | 1 0 |
| `disable_lethal` | `disableLethal` | 2 | 1 0 |
| `disable_tactical` | `disableTactical` | 2 | 1 0 |
| `disable_third_person_spectating` | `disableThirdPersonSpectating` | 2 | 1 0 |
| `draft_enabled` | `draftEnabled` | 2 | on/off |
| `draft_every_round` | `draftEveryRound` | 2 | on/off |
| `draft_required_clients` | `draftRequiredClients` | 6 | 0 1 2 3 4 5 |
| `draft_time` | `draftTime` | 6 | 10 15 30 45 60 90 |
| `dropped_tag_respawn` | `droppedTagRespawn` | 2 | on/off |
| `enemy_carrier_visible` | `enemyCarrierVisible` | 3 | 0 1 2 |
| `escalation_enabled` | `escalationEnabled` | 2 | on/off |
| `extra_segment_time_control` | `extraSegmentTime` | 9 | 0 5 10 15 20 25 30 45 60 · **hidden:** 4.5 5 |
| `extra_time` | `extraTime` | 11 | 0 0.5 1 1.5 2 2.5 3 3.5 4 4.5 5 |
| `extra_time_control` | `extraTime` | 11 | 0 0.5 1 1.5 2 2.5 3 3.5 4 4.5 5 |
| `extra_time_seconds` | `extraTime` | 9 | 0 5 10 15 20 25 30 45 60 · **hidden:** 4.5 5 |
| `flag_can_be_neutralized` | `flagCanBeNeutralized` | 2 | on/off |
| `flag_capture_condition` | `flagCaptureCondition` | 2 | 0 1 |
| `flag_capture_rate_increase` | `flagCaptureRateIncrease` | 2 | on/off |
| `flag_respawn_time` | `flagRespawnTime` | 9 | 1 5 10 15 20 30 40 50 60 |
| `force_radar` | `forceRadar` | 3 | 0 1 2 |
| `friendly_fire_type` | `friendlyfiretype` | 4 | 0 1 2 3 |
| `gts_pvp_only` | `pvpOnly` | 2 | on/off |
| `gun_selection` | `gunSelection` | 4 | 0 1 2 3 |
| `gun_selection_sas` | `gunSelection` | 4 | 0 1 2 3 |
| `gunfight_rounds_per_loadout` | `gunfightRoundsPerLoadout` | 6 | 0 1 2 3 4 5 |
| `hardcore_mode` | `hardcoreMode` | 2 | on/off |
| `idle_flag_reset_time` | `idleFlagResetTime` | 9 | 0 5 10 15 20 30 40 50 60 |
| `idle_flag_reset_time_ball` | `idleFlagResetTime` | 7 | 0 5 10 15 30 45 60 |
| `idle_reset_time_dropkick` | `idleFlagResetTime` | 9 | 0 5 10 15 20 30 40 50 60 |
| `incremental_spawn_delay` | `incrementalSpawnDelay` | 17 | 0 1 2 2.5 3 4 5 6 7 8 9 10 15 30 40 50 60 |
| `intro_enabled` | `playIntroCinematics` | 4 | 1 2 3 4 |
| `kill_event_score_multiplier` | `killEventScoreMultiplier` | 9 | 1 1.5 2 2.5 3 3.5 4 4.5 5 |
| `kill_points_in_enemy_protected_zone` | `killPointsInEnemyProtectedZone` | 7 | 0 1 2 3 4 5 10 |
| `killstreak_death_penalty_individual_earn` | `killstreakDeathPenaltyIndividualEarn` | 4 | 0 25 50 100 |
| `killstreaks_give_game_score` | `killstreaksGiveGameScore` | 2 | on/off |
| `loadout_killstreaks_enabled` | `loadoutKillstreaksEnabled` | 2 | on/off |
| `max_allocation` | `maxAllocation` | 15 | 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 |
| `max_players` | `maxPlayers` | 12 | 1 2 3 4 5 6 7 8 9 10 11 12 |
| `momentum_cost_air_patrol` | `momentumCostAirPatrol` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `momentum_cost_armor` | `momentumCostArmor` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `momentum_cost_artillery` | `momentumCostArtillery` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `momentum_cost_attack_helicopter` | `momentumCostAttackHelicopter` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `momentum_cost_bow` | `momentumCostBow` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `momentum_cost_care_package` | `momentumCostCarePackage` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `momentum_cost_chopper_gunner` | `momentumCostChopperGunner` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `momentum_cost_cuav` | `momentumCostCUAV` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `momentum_cost_gunship` | `momentumCostGunship` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `momentum_cost_minigun` | `momentumCostMinigun` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `momentum_cost_napalm` | `momentumCostNapalm` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `momentum_cost_rcxd` | `momentumCostRCXD` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `momentum_cost_recon_plane` | `momentumCostReconPlane` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `momentum_cost_remote_missile` | `momentumCostRemoteMissile` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `momentum_cost_sentry` | `momentumCostSentry` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `momentum_cost_straferun` | `momentumCostStraferun` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `momentum_cost_uav` | `momentumCostUAV` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `momentum_cost_vtol_escort` | `momentumCostVTOL` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `momentum_cost_war_machine` | `momentumCostWarMachine` | 51 | 0 1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 50 60 70 75 95 |
| `mp_friendly_fire_type` | `friendlyfiretype` | 5 | 0 1 2 3 4 |
| `mp_only_execution` | `onlyExecution` | 2 | on/off |
| `mp_only_headshots` | `onlyHeadshots` | 2 | on/off |
| `mp_player_max_health` | `playerMaxHealth` | 31 | 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 110 120 125 130 140 150 160 170 175 180 190 200 300 350 500 |
| `mp_teamkill_punish_count` | `teamKillPunishCount` | 5 | 0 1 2 3 4 |
| `multi_bomb` | `multiBomb` | 2 | on/off |
| `neutral_zone` | `neutralZone` | 2 | on/off |
| `objective_spawn_time` | `objectiveSpawnTime` | 7 | 0 5 10 15 30 45 60 |
| `only_headshots` | `onlyHeadshots` | 2 | on/off |
| `overtime_time_limit` | `OvertimetimeLimit` | 20 | 0 1 1.5 2 2.5 3 4 5 6 7 8 9 10 11 12 13 14 15 20 30 |
| `perks_enabled` | `perksEnabled` | 2 | 0 1 |
| `plant_time` | `plantTime` | 17 | 1 2.5 3 3.5 4 4.5 5 5.5 6 6.5 7 7.5 8 8.5 9 9.5 10 |
| `player_force_respawn` | `playerForceRespawn` | 2 | on/off |
| `player_health_regen_time` | `autoHeal` | 4 | 0 10 5 2 |
| `player_max_health` | `playerMaxHealth` | 27 | 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 110 120 125 130 140 150 160 170 175 180 190 200 |
| `player_num_lives` | `playerNumLives` | 14 | 0 1 2 3 4 5 6 7 8 9 10 15 20 25 |
| `player_respawn_delay` | `playerRespawnDelay` | 16 | 0 1 2 2.5 3 4 5 6 7 7.5 8 9 10 15 20 30 |
| `player_sprint_recovery_delay` | `playerSprintRecoveryDelayOverrideMS` | 12 | 0 1 500 1000 1500 2000 2500 3000 3500 4000 4500 5000 · **hidden:** 90 95 100 110 120 125 130 140 150 160 170 175 180 190 200 |
| `points_for_survival_bonus` | `pointsForSurvivalBonus` | 11 | 0 1 2 3 4 5 6 7 8 9 10 |
| `points_per_melee_kill` | `pointsPerMeleeKill` | 8 | 0 1 2 3 4 5 10 25 |
| `points_per_primary_grenade_kill` | `pointsPerPrimaryGrenadeKill` | 8 | 0 1 2 3 4 5 10 25 |
| `points_per_primary_kill` | `pointsPerPrimaryKill` | 8 | 0 1 2 3 4 5 10 25 |
| `points_per_secondary_kill` | `pointsPerSecondaryKill` | 8 | 0 1 2 3 4 5 10 25 |
| `points_per_weapon_kill` | `pointsPerWeaponKill` | 8 | 0 1 2 3 4 5 10 25 |
| `prematch_period` | `prematchperiod` | 6 | 5 10 15 30 45 60 |
| `prematch_requirement` | `prematchrequirement` | 19 | 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 |
| `preround_period` | `preroundperiod` | 17 | 0 1 2 3 4 5 6 7 8 9 10 12 15 18 20 25 30 |
| `preset_classes_per_team` | `presetClassesPerTeam` | 2 | 0 1 |
| `random_objective_locations` | `randomObjectiveLocations` | 3 | 0 2 1 |
| `random_objective_locations_koth` | `randomObjectiveLocations` | 2 | 0 2 |
| `reboot_players` | `rebootPlayers` | 2 | 0 1 |
| `reboot_time` | `rebootTime` | 16 | 1 2 3 4 5 6 7 8 9 10 15 20 25 30 45 60 |
| `robot_speed` | `robotSpeed` | 3 | 0 1 2 |
| `round_limit` | `roundLimit` | 10 | 0 1 2 3 4 5 6 7 8 9 |
| `round_score_limit` | `roundScoreLimit` | 39 | 0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 150 200 250 300 350 400 450 500 600 700 800 850 |
| `round_score_limit_control` | `scoreLimit` | 19 | 0 25 50 55 60 65 70 75 100 125 150 175 200 225 250 375 500 750 1000 |
| `round_score_limit_dom` | `scoreLimit` | 19 | 0 25 50 55 60 65 70 75 100 125 150 175 200 225 250 375 500 750 1000 |
| `round_start_explosive_delay` | `roundStartExplosiveDelay` | 18 | 0 1 2 3 4 5 6 7 8 9 10 12 15 20 25 30 45 60 |
| `round_start_killstreak_delay` | `roundStartKillstreakDelay` | 18 | 0 1 2 3 4 5 6 7 8 9 10 12 15 20 25 30 45 60 |
| `round_switch` | `roundSwitch` | 5 | 0 1 2 3 4 |
| `round_win_limit` | `roundWinLimit` | 7 | 0 1 2 3 4 5 6 · **hidden:** 7 8 9 |
| `round_win_limit_control` | `roundWinLimit` | 7 | 0 1 2 3 4 5 6 · **hidden:** 7 8 9 10 12 24 |
| `round_win_limit_ctf` | `roundWinLimit` | 7 | 0 1 2 3 4 5 6 · **hidden:** 7 8 9 |
| `round_win_limit_escort` | `roundWinLimit` | 7 | 0 1 2 3 4 5 6 · **hidden:** 7 8 9 10 12 24 |
| `round_win_limit_gunfight` | `roundWinLimit` | 6 | 1 2 3 4 5 6 · **hidden:** 7 8 9 |
| `score_limit` | `scoreLimit` | 43 | 0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 125 150 175 200 225 250 275 300 400 500 600 650 850 |
| `score_limit_ctf` | `scoreLimit` | 7 | 0 1 3 5 10 15 30 |
| `score_limit_ctf_round` | `scoreLimit` | 7 | 0 1 3 5 10 15 30 |
| `score_limit_dom` | `scoreLimit` | 19 | 0 50 100 110 120 130 140 150 200 250 300 350 400 450 500 750 1000 1500 2000 |
| `score_limit_sd_dem` | `scoreLimit` | 12 | 1 2 3 4 5 6 7 8 9 10 12 24 |
| `score_per_player` | `scorePerPlayer` | 2 | 0 1 |
| `score_reset_on_death` | `scoreResetOnDeath` | 2 | on/off |
| `server_msec` | `servermsec` | 2 | 50 16 |
| `setbacks` | `setbacks` | 11 | 0 1 2 3 4 5 6 7 8 9 10 |
| `setbacks_sas` | `setbacks` | 10 | 0 1 2 3 4 5 10 15 25 50 |
| `show_next_zone_objective_koth` | `showNextZoneObjective` | 5 | 0 5 10 30 31 |
| `shutdown_damage` | `shutdownDamage` | 4 | 0 1 2 3 |
| `silent_plant` | `silentPlant` | 2 | on/off |
| `spawn_health_boost_percent` | `killPointsInEnemyProtectedZone` | 4 | 0 25 50 100 · **hidden:** 5 |
| `spawn_health_boost_time` | `killPointsInEnemyProtectedZone` | 7 | 0 1 2 3 4 5 10 |
| `spawn_select` | `spawnSelectEnabled` | 2 | on/off |
| `spawn_suicide_penalty` | `spawnsuicidepenalty` | 17 | 0 1 2 3 4 5 6 7 8 9 10 12 14 15 16 18 20 |
| `spawn_teamkilled_penalty` | `spawnteamkilledpenalty` | 17 | 0 1 2 3 4 5 6 7 8 9 10 12 14 15 16 18 20 |
| `team_num_lives` | `teamNumLives` | 29 | 0 1 2 3 4 5 6 7 8 9 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 |
| `team_score_per_death` | `teamScorePerDeath` | 8 | 0 1 2 3 4 5 10 25 |
| `team_score_per_headshot` | `teamScorePerHeadshot` | 8 | 0 1 2 3 4 5 10 25 |
| `team_score_per_kill` | `teamScorePerKill` | 8 | 0 1 2 3 4 5 10 25 |
| `team_score_per_kill_confirmed` | `teamScorePerKillConfirmed` | 8 | 0 1 2 3 4 5 10 25 |
| `team_score_per_kill_denied` | `teamScorePerKillDenied` | 8 | 0 1 2 3 4 5 10 25 |
| `teamkill_punish_count` | `teamKillPunishCount` | 5 | 0 1 2 3 4 |
| `throw_score` | `throwScore` | 9 | 1 2 3 4 5 6 7 8 9 |
| `time_limit` | `timeLimit` | 20 | 0 1 1.5 2 2.5 3 4 5 6 7 8 9 10 11 12 13 14 15 20 30 |
| `time_limit_dom` | `timeLimit` | 20 | 0 1 1.5 2 2.5 3 4 5 6 7 8 9 10 11 12 13 14 15 20 30 |
| `time_limit_seconds` | `timeLimit` | 6 | 0 20 30 40 50 60 · **hidden:** 4 5 6 7 8 9 10 11 12 13 14 15 20 30 |
| `time_pauses_when_in_zone` | `timePausesWhenInZone` | 2 | on/off |
| `touch_return` | `defuseTime` | 15 | 63 0 0.5 1 1.5 2 2.5 3 4 5 6 7 8 9 10 |
| `use_doors` | `use_doors` | 2 | on/off |
| `use_emblem_instead_of_faction_icon` | `useEmblemInsteadOfFactionIcon` | 2 | on/off |
| `use_item_spawns` | `useItemSpawns` | 2 | on/off |
| `use_spawn_groups` | `useSpawnGroups` | 2 | on/off |
| `vip_armor_amount` | `vipVipArmorAmount` | 3 | 0.5 1 2 |
| `vip_health` | `vipVipHealth` | 3 | 0.5 1 2 |
| `voip_killers_hear_victim` | `voipKillersHearVictim` | 2 | on/off |
| `wave_respawn_delay` | `waveRespawnDelay` | 8 | 0 2.5 5 7.5 10 15 20 30 |
| `wave_respawn_delay_dropkick` | `waveRespawnDelay` | 8 | 0 2.5 5 7.5 10 15 20 30 |
| `zone_count` | `zoneCount` | 5 | 1 2 3 4 5 |

## Spy Hunt — 19 rows

| bundle | setting | published | values |
|---|---|---|---|
| `gunfight_spy_plane` | `gunfightSpyPlane` | 3 | 0 1 2 · **hidden:** 3 |
| `round_limit_spy` | `roundLimit` | 9 | 1 2 3 4 5 6 7 8 9 |
| `spy_air_drop` | `spyModeAirDrop` | 2 | 0 1 · **hidden:** 2 2 2.5 3 3.75 5 6 7 8 9 10 11 12 13 14 15 20 30 |
| `spy_double_agent_max_health` | `doubleAgentMaxHealth` | 31 | 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 110 120 125 130 140 150 160 170 175 180 190 200 300 350 500 |
| `spy_double_agent_passive_skill` | `spyModeDoubleAgentPassiveSkill` | 2 | 0 1 |
| `spy_double_agent_scorestreaks` | `spyModeDoubleAgentScorestreaks` | 2 | 0 1 |
| `spy_doubleagent_armor_amount` | `spyModeDoubleAgentArmorAmount` | 9 | 150 0 100 150 200 250 300 350 400 · **hidden:** 7 8 9 10 11 12 13 14 15 20 30 |
| `spy_investigator_armor_amount` | `spyModeInvestigatorArmorAmount` | 9 | 150 0 100 150 200 250 300 350 400 |
| `spy_investigator_max_health` | `investigatorMaxHealth` | 31 | 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 110 120 125 130 140 150 160 170 175 180 190 200 301 350 500 |
| `spy_investigator_passive_skill` | `spyModeInvestigatorPassiveSkill` | 2 | 0 1 |
| `spy_investigator_scorestreaks` | `spyModeInvestigatorScorestreaks` | 2 | 0 1 |
| `spy_investigator_starting_weapon` | `spyModeInvestigatorStartingWeaponOption` | 9 | 0 1 2 3 4 5 6 7 8 |
| `spy_loot_weapons` | `spyModeLootWeaponsOption` | 5 | 0 1 2 3 4 |
| `spy_operative_armor_amount` | `spyModeOperativeArmorAmount` | 9 | 150 0 100 150 200 250 300 350 400 · **hidden:** 7 8 9 10 11 12 13 14 15 20 30 |
| `spy_operative_max_health` | `operativeMaxHealth` | 31 | 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 110 120 125 130 140 150 160 170 175 180 190 200 300 350 500 |
| `spy_starting_weapon` | `spyModeStartingWeaponOption` | 2 | 0 1 |
| `spy_teamkill_respawn` | `spyModeTeamkillRespawn` | 2 | 0 1 · **hidden:** 2 2 2.5 3 3.75 5 6 7 8 9 10 11 12 13 14 15 20 30 |
| `spy_win_rule` | `spyModeWinRules` | 2 | 0 1 · **hidden:** 2 2 2.5 3 3.75 5 6 7 8 9 10 11 12 13 14 15 20 30 |
| `time_limit_spy` | `timeLimit` | 16 | 0 1.5 2 2.5 3 3.5 3.75 4.5 5 5.5 6 6.5 7.5 8.5 9.5 10.5 · **hidden:** 14 15 20 30 |

## Scream — 6 rows

| bundle | setting | published | values |
|---|---|---|---|
| `scream_heartbeat_radius` | `screamHeartbeatRadius` | 4 | 0 1300 800 2000 |
| `scream_scream_interval` | `screamPlayerScreamTimer` | 7 | 0 10 20 30 40 50 60 |
| `scream_slasher_count` | `screamSlasherCount` | 3 | 0 1 2 |
| `scream_slasher_lethal_equipment` | `screamSlasherLethalEquipment` | 2 | 0 1 |
| `scream_slasher_move_speed` | `screamSlasherMoveSpeedOverride` | 12 | 0 100 110 120 130 140 150 160 170 180 190 200 |
| `scream_survivor_tactical_equipment` | `screamSurvivorTacticalEquipment` | 3 | 0 1 2 |

## Zombies — 201 rows

| bundle | setting | published | values |
|---|---|---|---|
| `zm_barricadestate` | `zmBarricadeState` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_craftingkeyline` | `zmCraftingKeyline` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_crawlerstate` | `zmCrawlerState` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_doorstate` | `zmDoorState` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_elixiraftertaste` | `zmElixirAftertaste` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixiralchemicalantithesis` | `zmElixirAlchemicalAntithesis` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixiralwaysdoneswiftly` | `zmElixirAlwaysDoneSwiftly` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirantientrapment` | `zmElixirAntiEntrapment` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixiranywherebuthere` | `zmElixirAnywhereButHere` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirarsenalaccelerator` | `zmElixirArsenalAccelerator` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirblooddebt` | `zmElixirBloodDebt` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirbulletboost` | `zmElixirBulletBoost` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirburnedout` | `zmElixirBurnedOut` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixircacheback` | `zmElixirCacheBack` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirconflagrationliquidation` | `zmElixirConflagrationLiquidation` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirctrlz` | `zmElixirCtrlZ` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirdeadofnuclearwinter` | `zmElixirDeadOfNuclearWinter` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirdividendyield` | `zmElixirDividendYield` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirequipmint` | `zmElixirEquipMint` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirextracredit` | `zmElixirExtraCredit` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirfreefire` | `zmElixirFreeFire` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirheaddrama` | `zmElixirHeadDrama` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirheadscan` | `zmElixirHeadScan` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirimmolationliquidation` | `zmElixirImmolationLiquidation` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirinplainsight` | `zmElixirInPlainsight` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirjointheparty` | `zmElixirJoinTheParty` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirkilljoy` | `zmElixirKillJoy` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirlicensedcontractor` | `zmElixirLicensedContractor` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirneardeathexperience` | `zmElixirNearDeathExperience` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirnewtoniannegation` | `zmElixirNewtonianNegation` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirnowherebutthere` | `zmElixirNowhereButThere` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirnowyouseeme` | `zmElixirNowYouSeeMe` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirperkaholic` | `zmElixirPerkaholic` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirperkup` | `zmElixirPerkUp` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirphantomreload` | `zmElixirPhantomReload` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirphoenixup` | `zmElixirPhoenixUp` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirpointdrops` | `zmElixirPointDrops` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirpopshocks` | `zmElixirPopShocks` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirpowerkeg` | `zmElixirPowerKeg` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirpowervacuum` | `zmElixirPowerVacuum` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirquacknarok` | `zmElixirQuacknarok` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirrefreshmint` | `zmElixirRefreshMint` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirreigndrops` | `zmElixirReignDrops` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirs` | `zmElixirsEnabled` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirscommon` | `zmElixirsCommon` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirscooldown` | `zmElixirsCooldown` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_elixirsdurables` | `zmElixirsDurables` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirsecretshopper` | `zmElixirSecretShopper` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirsepic` | `zmElixirsEpic` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirshieldsup` | `zmElixirShieldsUp` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirshoppingfree` | `zmElixirShoppingFree` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirslegendary` | `zmElixirsLegendary` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirsrare` | `zmElixirsRare` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirstockoption` | `zmElixirStockOption` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirsuitup` | `zmElixirSuitUp` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirswordflay` | `zmElixirSwordFlay` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirtalkinboutregeneration` | `zmElixirTalkinBoutRegeneration` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirtemporalgift` | `zmElixirTemporalGift` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirundeadmanwalking` | `zmElixirUndeadManWalking` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirwallpower` | `zmElixirWallPower` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirwalltowall` | `zmElixirWallToWall` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_elixirwhoskeepingscore` | `zmElixirWhosKeepingScore` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_enhanceddamagemult` | `zmEnhancedDamageMult` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_enhancedfrequency` | `zmEnhancedSpawnFreq` | 4 | 0 1 2 3 |
| `zm_enhancedhealthmult` | `zmEnhancedHealthMult` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_enhancedstate` | `zmEnhancedState` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_equipcharge` | `zmEquipmentChargeRate` | 3 | 0 1 2 |
| `zm_equipment` | `zmEquipmentIsEnabled` | 2 | 0 1 |
| `zm_friendly_fire_type` | `zmFriendlyFireType` | 4 | 0 1 2 3 |
| `zm_healthdrain` | `zmHealthDrain` | 4 | 0 1 2 3 · **hidden:** 4 5 |
| `zm_healthonkill` | `zmHealthOnKill` | 4 | 0 1 2 3 · **hidden:** 4 5 |
| `zm_healthregendelay` | `zmHealthRegenDelay` | 3 | 0 1 2 · **hidden:** 4 5 6 |
| `zm_healthregenrate` | `zmHealthRegenRate` | 5 | 0 1 2 3 4 · **hidden:** 5 |
| `zm_healthstarting` | `zmHealthStartingBars` | 7 | 0 1 2 3 4 5 6 |
| `zm_heavydamagemult` | `zmHeavyDamageMult` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_heavyfrequency` | `zmHeavySpawnFreq` | 4 | 0 1 2 3 |
| `zm_heavyhealthmult` | `zmHeavyHealthMult` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_heavystate` | `zmHeavyState` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_laststandcount` | `zmLimitedDownsAmount` | 100 | 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 30 32 34 35 39 |
| `zm_laststandduration` | `zmLastStandDuration` | 4 | 0 1 2 3 |
| `zm_minibossdamagemult` | `zmMiniBossDamageMult` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_minibossfrequency` | `zmMinibossSpawnFreq` | 4 | 0 1 2 3 |
| `zm_minibosshealthmult` | `zmMiniBossHealthMult` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_minibossstate` | `zmMiniBossState` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_mysteryboxlimit` | `zmMysteryBoxLimit` | 51 | 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 30 32 34 35 39 |
| `zm_mysteryboxlimitmove` | `zmMysteryBoxLimitMove` | 11 | 0 1 2 3 4 5 6 7 8 9 10 · **hidden:** 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 31 33 35 36 40 |
| `zm_mysteryboxlimitrnd` | `zmMysteryBoxLimitRound` | 11 | 0 1 2 3 4 5 6 7 8 9 10 · **hidden:** 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 31 33 35 36 40 |
| `zm_mysteryboxstate` | `zmMysteryBoxState` | 4 | 0 1 2 3 |
| `zm_pack` | `zmPaPEnabled` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_perkdecay` | `zmPerkDecay` | 2 | 1 2 · **hidden:** 2 3 |
| `zm_perksactive` | `zmPerksActive` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perksbandolier` | `zmPerksBandolier` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perkscooldown` | `zmPerksCooldown` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perksdeadshot` | `zmPerksDeadshot` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perksdeathperception` | `zmPerksDeathPerception` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perksdoubletap2` | `zmPerksDoubletap2` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perksdyingwish` | `zmPerksDyingWish` | 2 | 0 1 |
| `zm_perkselectricburst` | `zmPerksElectricBurst` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perksetherealrazor` | `zmPerksEtherealRazor` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perksjugg` | `zmPerksJuggernaut` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perksmulekick` | `zmPerksMuleKick` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perksphdslider` | `zmPerksPhdSlider` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perksrevive` | `zmPerksQuickRevive` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perkssecretsauce` | `zmPerksSecretSauce` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perksspeed` | `zmPerksSpeed` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perksstaminup` | `zmPerksStaminUp` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perksstonecold` | `zmPerksStoneCold` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perksvictorious` | `zmPerksVictorious` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perkswidow` | `zmPerksWidowsWail` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perkswolfprotector` | `zmPerksWolfProtector` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_perkszombshell` | `zmPerksZombshell` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_pointlossondeath` | `zmPointLossOnDeath` | 100 | 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 30 32 34 35 39 |
| `zm_pointlossondown` | `zmPointLossOnDown` | 100 | 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 30 32 34 35 39 |
| `zm_pointlossonteammatedeath` | `zmPointLossOnTeammateDeath` | 100 | 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 30 32 34 35 39 |
| `zm_pointsfixed` | `zmPointsFixed` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_pointslosspercent` | `zmPointsLossPercent` | 100 | 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 31 33 35 36 40 |
| `zm_pointslosstype` | `zmPointsLossType` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_pointslossvalue` | `zmPointsLossValue` | 100 | 100 200 300 400 500 600 700 800 900 1000 1100 1200 1300 1400 1500 1600 1700 1800 1900 2000 2100 2200 2300 2400 2500 2600 2700 2800 2900 3100 3300 3500 3600 4000 |
| `zm_pointsstarting` | `zmPointsStarting` | 43 | 0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 110 120 130 140 150 160 170 180 200 250 300 325 425 |
| `zm_popcorndamagemult` | `zmPopcornDamageMult` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_popcornhealthmult` | `zmPopcornHealthMult` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_popcornspawnfreq` | `zmPopcornSpawnFreq` | 4 | 0 1 2 3 |
| `zm_popcornstate` | `zmPopcornState` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_powerdoorstate` | `zmPowerDoorState` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_powerstate` | `zmPowerState` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_powerupfrequency` | `zmPowerupFrequency` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_poweruplimit` | `zmPowerupsLimitRound` | 20 | 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 · **hidden:** 20 21 22 23 24 25 26 27 28 30 32 34 35 39 |
| `zm_powerups` | `zmPowerupsActive` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_powerups2x` | `zmPowerupDouble` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_powerupscarpenter` | `zmPowerupCarpenter` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_powerupschaos` | `zmPowerupChaosPoints` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_powerupsfiresale` | `zmPowerupFireSale` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_powerupsinsta` | `zmPowerupInstakill` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_powerupsislimited` | `zmPowerupsIsLimitedRound` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_powerupsmaxammo` | `zmPowerupMaxAmmo` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_powerupsnuke` | `zmPowerupNuke` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_powerupsspecweap` | `zmPowerupSpecialWeapon` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_private_immersive_mode` | `zmPrivateImmersiveMode` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_private_match_type` | `zmPrivateMatchType` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_retainweapons` | `zmRetainWeapons` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_roundcap` | `zmExfilRound` | 2 | 0 20 · **hidden:** 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 30 32 34 35 39 |
| `zm_selfrevivecount` | `zmSelfReviveAmount` | 100 | 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 30 32 34 35 39 |
| `zm_shield` | `zmShieldIsEnabled` | 2 | 0 1 |
| `zm_shielddurability` | `zmShieldDurability` | 3 | 0 1 2 |
| `zm_specweap` | `zmSpecWeaponIsEnabled` | 2 | 0 1 |
| `zm_specweapcharge` | `zmSpecWeaponChargeRate` | 3 | 0 1 2 |
| `zm_superpack` | `zmSuperPaPEnabled` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanboxguaranteeboxonly` | `zmTalismanBoxGuaranteeBoxOnly` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanboxguaranteelmg` | `zmTalismanBoxGuaranteeLMG` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismancoagulant` | `zmTalismanCoagulant` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanextraclaymore` | `zmTalismanExtraClaymore` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanextrafrag` | `zmTalismanExtraFrag` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanextraminiturret` | `zmTalismanExtraMiniturret` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanextramolotov` | `zmTalismanExtraMolotov` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanextraselfrevive` | `zmTalismanExtraSelfRevive` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanextrasemtex` | `zmTalismanExtraSemtex` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanimpatient` | `zmTalismanImpatient` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanperkmodsingle` | `zmTalismanPerkModSingle` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanperkperm1` | `zmTalismanPerkPermanent1` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanperkperm2` | `zmTalismanPerkPermanent2` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanperkperm3` | `zmTalismanPerkPermanent3` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanperkperm4` | `zmTalismanPerkPermanent4` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanperkreducecost1` | `zmTalismanPerkReduceCost1` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanperkreducecost2` | `zmTalismanPerkReduceCost2` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanperkreducecost3` | `zmTalismanPerkReduceCost3` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanperkreducecost4` | `zmTalismanPerkReduceCost4` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanperkstart1` | `zmTalismanPerkStart1` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanperkstart2` | `zmTalismanPerkStart2` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanperkstart3` | `zmTalismanPerkStart3` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanperkstart4` | `zmTalismanPerkStart4` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanpermanentheroweaparmor` | `zmTalismanPermanentHeroweapArmor` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismans` | `zmTalismansEnabled` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanscommon` | `zmTalismansCommon` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismansepic` | `zmTalismansEpic` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanshielddurabilitylegendary` | `zmTalismanShieldDurabilityLegendary` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanshielddurabilityrare` | `zmTalismanShieldDurabilityRare` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanshieldprice` | `zmTalismanShieldPrice` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanslegendary` | `zmTalismansLegendary` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanspecialstart2` | `zmTalismanSpecialStartLvl2` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanspecialstart3` | `zmTalismanSpecialStartLvl3` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanspecialxprate` | `zmTalismanSpecialXPRate` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismansrare` | `zmTalismansRare` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanweaponpapcost` | `zmTalismanReducePAPCost` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanweaponstartar` | `zmTalismanStartWeaponAR` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanweaponstartlmg` | `zmTalismanStartWeaponLMG` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_talismanweaponstartsmg` | `zmTalismanStartWeaponSMG` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_wallbuys` | `zmWallBuysEnabled` | 2 | 0 1 · **hidden:** 2 3 |
| `zm_weapar` | `zmWeaponsAR` | 2 | 0 1 |
| `zm_weapknife` | `zmWeaponsKnife` | 2 | 0 1 |
| `zm_weaplmg` | `zmWeaponsLMG` | 2 | 0 1 |
| `zm_weapmelee` | `zmWeaponsMelee` | 2 | 0 1 |
| `zm_weapshotgun` | `zmWeaponsShotgun` | 2 | 0 1 |
| `zm_weapsmg` | `zmWeaponsSMG` | 2 | 0 1 |
| `zm_weapsniper` | `zmWeaponsSniper` | 2 | 0 1 |
| `zm_weaptr` | `zmWeaponsTR` | 2 | 0 1 |
| `zm_wonderweap` | `zmWonderWeaponIsEnabled` | 2 | 0 1 |
| `zm_zombiedamagemult` | `zmZombieDamageMult` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_zombiehealthmult` | `zmZombieHealthMult` | 3 | 0 1 2 · **hidden:** 3 |
| `zm_zombiespeedmax` | `zmZombieMaxSpeed` | 4 | 0 1 2 3 |
| `zm_zombiespeedmin` | `zmZombieMinSpeed` | 4 | 0 1 2 3 |
| `zm_zombiespread` | `zmZombieSpread` | 3 | 0 1 2 |
