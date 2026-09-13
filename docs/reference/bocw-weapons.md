# BOCW MP weapon names — the complete loadout set, with display names

Source of the NAMES: `gamedata/weapons/mp/mp_gunlevels.csv` in `ate47/bocw-source` (every
weapon with MP gun levels — 64 distinct `#name`s) cross-checked against the custom-games
restriction enum in `ddl/mp_custom_game.ddl` (~200 entries incl. ZM/BO4 leftovers and 19
still-hashed ids). `getweapon( #"<name>" )` takes these. The menu's Weapons page
(`src/gunfight_menu`) lists all 64 by class plus the BO4 leftovers below.

⚠ **Display names are NOT in the dump** (no localization; the memory rule applies). The
mapping below comes from the internal naming (which is descriptive — `smg_burst` = the only
burst SMG, `shotgun_leveraction` = the only lever-action) and from Warzone's mirrored ids
(`iw8_sm_t9capacity` = Bullfrog etc.). **Confidence column: ✅ certain from the name alone /
✔ high / ? inferred, verify in-game.** A `?` label in the menu means the same thing — pick
it, look at the gun, fix the row.

## There is no "gulag rock" in Cold War

Checked 2026-09-13: no weapon named `*rock*`, `*gulag*`, `*throw*`, `*stone*` anywhere in
the T9 scripts, the two weapon CSVs or the DDL enum; the 19 hashed enum ids were brute-forced
against ~250 melee/throwable words in 1-, 2- and 3-word combinations with no hit
(`crack-hash.py`'s FNV1a64). The Gulag rock is a **Modern Warfare / Warzone (IW8 engine)**
asset; Cold War's own "wz_" maps are Fireteam/Outbreak, not the MW Gulag. Nearest things
here: the melee list (Knife, Bowie, the Scream/Infected knives) and the stock equipment.

## Assault rifles (11)

| name | display | conf |
|---|---|---|
| `ar_standard_t9` | XM4 | ✅ (in-game) |
| `ar_damage_t9` | AK-47 | ✅ (in-game) |
| `ar_accurate_t9` | Krig 6 | ✅ (in-game) |
| `ar_fastfire_t9` | QBZ-83 | ✔ |
| `ar_fasthandling_t9` | FFAR 1 | ✔ |
| `ar_mobility_t9` | Groza | ✔ |
| `ar_slowfire_t9` | FARA 83 | ✔ |
| `ar_slowhandling_t9` | C58 | ✔ |
| `ar_british_t9` | EM2 | ✔ |
| `ar_season6_t9` | Vargo 52 | ? |
| `ar_soviet_t9` | Grav | ? |

## SMGs (12)

| name | display | conf |
|---|---|---|
| `smg_standard_t9` | MP5 | ✅ |
| `smg_handling_t9` | Milano 821 | ✅ |
| `smg_fastfire_t9` | MAC-10 | ✅ |
| `smg_heavy_t9` | AK-74u | ✔ |
| `smg_burst_t9` | KSP 45 | ✔ |
| `smg_capacity_t9` | Bullfrog | ✔ |
| `smg_accurate_t9` | LC10 | ✔ |
| `smg_spray_t9` | PPSh-41 | ✔ |
| `smg_cqb_t9` | OTs 9 | ? |
| `smg_semiauto_t9` | TEC-9 | ? |
| `smg_season6_t9` | LAPA | ? |
| `smg_flechette_t9` | **unknown** — has gun levels and an enum slot; possibly the Nail Gun's SMG-class prototype or a cut gun | ? |

## Tactical rifles (5)

| name | display | conf |
|---|---|---|
| `tr_powerburst_t9` | M16 | ✅ |
| `tr_longburst_t9` | AUG | ? |
| `tr_fastburst_t9` | CARV.2 | ✔ |
| `tr_precisionsemi_t9` | DMR 14 | ✔ |
| `tr_damagesemi_t9` | Type 63 | ✔ |

## LMGs (4)

| name | display | conf |
|---|---|---|
| `lmg_light_t9` | Stoner 63 | ✅ |
| `lmg_slowfire_t9` | RPD | ✔ |
| `lmg_fastfire_t9` | M60 | ✔ |
| `lmg_accurate_t9` | MG 82 | ✔ |

## Snipers (5)

| name | display | conf |
|---|---|---|
| `sniper_standard_t9` | Pelington 703 | ✅ |
| `sniper_quickscope_t9` | LW3 Tundra | ✅ |
| `sniper_powersemi_t9` | M82 | ✅ |
| `sniper_cannon_t9` | ZRG 20mm | ? |
| `sniper_accurate_t9` | Swiss K31 | ? |

## Shotguns (4)

| name | display | conf |
|---|---|---|
| `shotgun_pump_t9` | Hauer 77 | ✅ |
| `shotgun_fullauto_t9` | Gallo SA12 | ✅ |
| `shotgun_semiauto_t9` | Streetsweeper | ✔ |
| `shotgun_leveraction_t9` | .410 Ironhide | ✔ |

## Pistols (5, each with a `_dw` akimbo variant)

| name | display | conf |
|---|---|---|
| `pistol_semiauto_t9` | 1911 | ✔ |
| `pistol_revolver_t9` | Magnum | ✅ |
| `pistol_burst_t9` | Diamatti | ✅ |
| `pistol_fullauto_t9` | AMP63 | ✔ |
| `pistol_shotgun_t9` | Marshal | ✔ |

## Launchers + special (6)

| name | display | conf |
|---|---|---|
| `launcher_standard_t9` | Cigma 2 | ✔ |
| `launcher_freefire_t9` | RPG-7 | ✔ |
| `special_grenadelauncher_t9` | M79 | ✔ |
| `special_crossbow_t9` | R1 Shadowhunter | ✔ |
| `special_nailgun_t9` | Nail Gun | ✔ |
| `special_ballisticknife_t9_dw` | Ballistic Knife | ✔ |

## Melee (13 in the levels table + variants)

| name | display | conf |
|---|---|---|
| `knife_loadout` | Knife | ✅ |
| `melee_sledgehammer_t9` | Sledgehammer | ✅ |
| `melee_wakizashi_t9` | Wakizashi | ✅ |
| `melee_machete_t9` | Machete | ✅ |
| `melee_etool_t9` | E-Tool | ✅ |
| `melee_baseballbat_t9` | Baseball Bat | ✅ |
| `melee_mace_t9` | Mace | ✅ |
| `melee_sai_t9_dw` | Sai | ✅ |
| `melee_cane_t9` | Cane | ✅ |
| `melee_battleaxe_t9` | Battle Axe | ✅ |
| `melee_coldwar_t9_dw` | Hammer & Sickle (the dual-wield Soviet pair) | ? |
| `melee_scythe_t9` | **unknown** — no released Cold War scythe; in the levels table and the enum | ? |
| `melee_bowie` / `melee_bowie_bloody` | Bowie Knife (enum only) | ✔ |
| `hash_28fdaa999c8aa3af` | Knife (Scream) — cracked by the Atian menu | ✔ |
| `hash_3f47e8be065a0dc0` | Knife (Infected) — cracked by the Atian menu | ✔ |

## BO4 leftovers listed for MP by the shipped Atian menu (load; firing untested)

`ray_gun`, `hero_flamethrower` (Purifier), `hero_annihilator`, `hero_pineapplegun` (War
Machine), `sig_lmg` (Death Machine), `sig_bow_flame` (Sparrow), `ultimate_turret`. Also in
its list, not on our page: `chopper_gunner`, the mortar / napalm / RCXD / remote-missile
killstreak "weapons" (hashed ids), `knife_loadout_t9`.

## Still hashed in the custom-games enum (19)

`hash_7a083f7ba43fa06 hash_18696150427f2efb(chrysalax, ZM) hash_28fdaa999c8aa3af(Scream knife)
hash_2ea46ca74ebdfcac hash_31be8125c7d0f273 hash_3507beb47a6b634e hash_3ab58e40011df941
hash_3f47e8be065a0dc0(Infected knife) hash_4385cf507401820f hash_48206b17d50533c2
hash_4b1854c2ff5135b2 hash_55c23f24d806e3a6(ZM) hash_603c083704cefb0c hash_76b56e7e0b3b7aac
hash_788c96e19cc7a46e hash_7ab3f9a730359659` + 3 more — none matched a rock/throwable name.
