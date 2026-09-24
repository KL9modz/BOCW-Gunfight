# BOCW MP weapon names — the complete loadout set, with display names

Source of the NAMES: `gamedata/weapons/mp/mp_gunlevels.csv` in `ate47/bocw-source` (every
weapon with MP gun levels — 64 distinct `#name`s) cross-checked against the custom-games
restriction enum in `ddl/mp_custom_game.ddl` (~200 entries incl. ZM/BO4 leftovers and 19
still-hashed ids). `getweapon( #"<name>" )` takes these. The menu's Weapons page
(`src/gunfight_menu`) and the app's weapon picker (`tools/gf-panel` `Catalog.Weapons`) list all
64 by class plus the BO4 scorestreak guns below.

✅ **Display names VERIFIED 2026-09-23 (bocw-84) against the Call of Duty wiki.** klaze: *"some
weapons dont get given and some give the wrong ones"* — the earlier table was inferred from the
archetype names (`ar_fastfire` = "fast fire" …) and **17 rows named the wrong gun** (e.g. the menu's
"QBZ-83" gave the FFAR 1, "Gallo SA12" gave the Streetsweeper, "M16" gave the AUG). The display names
are not in the dump (no localization), so the check is external: every weapon page on
`callofduty.fandom.com` carries the game's internal names in `<tt>` tags, one per game —
`tr_longburst` (Cold War MP) + `ar_t9longburst` (Warzone) on the *M16* page, and so on. Method:

```
https://callofduty.fandom.com/api.php?action=parse&page=<page>&prop=wikitext&format=json&redirects=1
```

The wiki files each gun under its real-world model, so the page title is often not the Cold War
name (the QBZ-83 lives on *Type 95*, the MG 82 on *Ameli*, the UGR on *APS Underwater Rifle*); the
page's Cold War section says "appears in Black Ops Cold War as the **X**". The **wiki page** column
below is where each id was read. Two corroborations from the dump agree: the shotguns' fire-mode
labels in `gamedata/weapons/mp/mp_attributestable.csv`, and every `*_t9` id matching the Warzone
`xx_t9yyy` id on the same page.

**Zone** = which asset table in `tables/bgcache/` lists the weapon (`weapon,#<name>` rows). A map runs
with core_common + mp_common + its own zone. `MP` = in mp_common (and core_common); `core` = only in
core_common — **every post-launch gun is `core`-only**.
✅ **MEASURED 2026-09-23 (klaze, dm on Zoo): residency is not what stops a give — the inventory limit is.**
Three melee gives took, then nearly every give failed whatever the weapon (the stock Knife and the
`MP` launchers included), while the `core`-only Sai took. klaze: *"the weapons arent broke, they just stop
giving once you are holding too many ... i think the limit is 13"*. A give past the limit is dropped with
no error. The menu's give (`weapon_give_room`) now frees one slot when a give does not take — the oldest
weapon the menu gave, else the gun in hand — and says *"(swapped out X)"*, or *"not given — X (N held)"*
if it still fails (untested).

## There is no "gulag rock" in Cold War

Checked 2026-09-13: no weapon named `*rock*`, `*gulag*`, `*throw*`, `*stone*` anywhere in
the T9 scripts, the two weapon CSVs or the DDL enum; the 19 hashed enum ids were brute-forced
against ~250 melee/throwable words in 1-, 2- and 3-word combinations with no hit
(`crack-hash.py`'s FNV1a64). The Gulag rock is a **Modern Warfare / Warzone (IW8 engine)**
asset; Cold War's own "wz_" maps are Fireteam/Outbreak, not the MW Gulag. Nearest things
here: the melee list (Knife, the Scream/Infected knives) and the stock equipment.

## Assault rifles (11)

| name | display | wiki page | zone |
|---|---|---|---|
| `ar_standard_t9` | XM4 | XM4 | MP |
| `ar_damage_t9` | AK-47 | AK-47 | MP |
| `ar_accurate_t9` | Krig 6 | Krig 6 | MP |
| `ar_mobility_t9` | QBZ-83 | Type 95 | MP |
| `ar_fastfire_t9` | FFAR 1 | FFAR | MP |
| `ar_fasthandling_t9` | Groza | Groza | MP |
| `ar_slowhandling_t9` | FARA 83 | FARA 83 | MP |
| `ar_slowfire_t9` | C58 | C58 | core |
| `ar_british_t9` | EM2 | EM2 | core |
| `ar_soviet_t9` | Vargo 52 | Vargo 52 | core |
| `ar_season6_t9` | Grav | Galil | core |

## SMGs (12)

| name | display | wiki page | zone |
|---|---|---|---|
| `smg_standard_t9` | MP5 | MP5 | MP |
| `smg_handling_t9` | Milano 821 | Milano 821 | MP |
| `smg_heavy_t9` | AK-74u | AK-74u | MP |
| `smg_burst_t9` | KSP 45 | KSP 45 | MP |
| `smg_capacity_t9` | Bullfrog | Bizon | MP |
| `smg_fastfire_t9` | MAC-10 | MAC-10 | MP |
| `smg_accurate_t9` | LC10 | LC10 | MP |
| `smg_spray_t9` | PPSh-41 | PPSh-41 | MP |
| `smg_cqb_t9` | OTs 9 | Kiparis | core |
| `smg_semiauto_t9` | TEC-9 | TEC-9 | core |
| `smg_season6_t9` | LAPA | LAPA | core |
| `smg_flechette_t9` | UGR (added 2022-05-06) | APS Underwater Rifle | core |

## Tactical rifles (5)

| name | display | wiki page | zone |
|---|---|---|---|
| `tr_longburst_t9` | M16 | M16 | MP |
| `tr_powerburst_t9` | AUG | AUG (rifle) | MP |
| `tr_fastburst_t9` | CARV.2 | CARV.2 | MP |
| `tr_precisionsemi_t9` | DMR 14 | M14 | MP |
| `tr_damagesemi_t9` | Type 63 | Type 63 | MP |

## LMGs (4)

| name | display | wiki page | zone |
|---|---|---|---|
| `lmg_accurate_t9` | Stoner 63 | Stoner 63 | MP |
| `lmg_light_t9` | RPD | RPD | MP |
| `lmg_slowfire_t9` | M60 | M60 | MP |
| `lmg_fastfire_t9` | MG 82 | Ameli | MP |

## Snipers (5)

| name | display | wiki page | zone |
|---|---|---|---|
| `sniper_quickscope_t9` | Pelington 703 | R700 | MP |
| `sniper_standard_t9` | LW3 Tundra | L96A1 | MP |
| `sniper_powersemi_t9` | M82 | Barrett .50cal | MP |
| `sniper_cannon_t9` | ZRG 20mm | ZRG 20mm | MP |
| `sniper_accurate_t9` | Swiss K31 | Swiss K31 | MP |

## Shotguns (4)

| name | display | wiki page | zone |
|---|---|---|---|
| `shotgun_pump_t9` | Hauer 77 | Ithaca Model 37 | MP |
| `shotgun_semiauto_t9` | Gallo SA12 (semi-auto) | SPAS-12 | MP |
| `shotgun_fullauto_t9` | Streetsweeper (full-auto) | Striker | MP |
| `shotgun_leveraction_t9` | .410 Ironhide | .410 Ironhide | core |

## Pistols (5, each with a `_dw` akimbo variant)

| name | display | wiki page | zone |
|---|---|---|---|
| `pistol_semiauto_t9` | 1911 | M1911 | MP |
| `pistol_revolver_t9` | Magnum | Magnum (Cold War) | MP |
| `pistol_burst_t9` | Diamatti | M93 Raffica | MP |
| `pistol_fullauto_t9` | AMP63 | PM63 | MP |
| `pistol_shotgun_t9` | Marshal | Marshal 16 | core |

## Launchers + special (6)

| name | display | wiki page | zone |
|---|---|---|---|
| `launcher_standard_t9` | Cigma 2 | Cigma 2 | MP |
| `launcher_freefire_t9` | RPG-7 | RPG-7 | MP |
| `special_grenadelauncher_t9` | M79 | Thumper (weapon) | MP |
| `special_crossbow_t9` | R1 Shadowhunter | Crossbow | MP |
| `special_nailgun_t9` | Nail Gun | Nail Gun | core |
| `special_ballisticknife_t9_dw` | Ballistic Knife | Ballistic Knife | MP |

## Melee (12 in the levels table + 2 hashed knives)

| name | display | wiki page | zone |
|---|---|---|---|
| `knife_loadout` | Knife | — | MP |
| `melee_sledgehammer_t9` | Sledgehammer | Sledgehammer | MP |
| `melee_wakizashi_t9` | Wakizashi | Wakizashi | MP |
| `melee_machete_t9` | Machete | Machete | MP |
| `melee_etool_t9` | E-Tool | Shovel | MP |
| `melee_baseballbat_t9` | Baseball Bat | Baseball Bat | MP |
| `melee_mace_t9` | Mace | Mace (weapon) | MP |
| `melee_cane_t9` | Cane | Cane | MP |
| `melee_sai_t9_dw` | Sai | Sai | core |
| `melee_battleaxe_t9` | Battle Axe | Two-Headed Axe | core |
| `melee_coldwar_t9_dw` | Hammer & Sickle | Hammer and Sickle | core |
| `melee_scythe_t9` | Scythe (added 2022-08-12; the page lists no id — named by the id itself) | Scythe (melee weapon) | core |
| `hash_28fdaa999c8aa3af` | Knife (Scream) — cracked by the Atian menu | — | core |
| `hash_3f47e8be065a0dc0` | Knife (Infected) — cracked by the Atian menu | — | MP |

🪦 **`melee_bowie` / `melee_bowie_bloody` — removed from the menu and the app 2026-09-23.** They are in
the custom-games enum but in **no** zone table at all (not mp_common, not core_common, not a map
zone), so a give can never find the asset. The wiki's only page with `melee_bowie` is the BO4 Carver.

## Scorestreak guns — BO4 leftovers listed for MP by the shipped Atian menu (load; firing untested)

`hero_flamethrower` (Purifier), `hero_annihilator`, `hero_pineapplegun` (War Machine), `sig_lmg`
(Death Machine), `ultimate_turret` (core only) are in mp_common / core_common; `sig_bow_flame`
(Sparrow) is in mp_common only. 🪦 **`ray_gun` is in no MP or core zone** (only the frontend and the
ZM zones) — `killstreaks::give` refused it and `giveweapon` never found it, so the menu (2026-09-21)
and the app (2026-09-23) no longer offer it. Also in the Atian list, not on our page:
`chopper_gunner`, the mortar / napalm / RCXD / remote-missile killstreak "weapons" (hashed ids),
`knife_loadout_t9`.

## Still hashed in the custom-games enum (19)

`hash_7a083f7ba43fa06 hash_18696150427f2efb(chrysalax, ZM) hash_28fdaa999c8aa3af(Scream knife)
hash_2ea46ca74ebdfcac hash_31be8125c7d0f273 hash_3507beb47a6b634e hash_3ab58e40011df941
hash_3f47e8be065a0dc0(Infected knife) hash_4385cf507401820f hash_48206b17d50533c2
hash_4b1854c2ff5135b2 hash_55c23f24d806e3a6(ZM) hash_603c083704cefb0c hash_76b56e7e0b3b7aac
hash_788c96e19cc7a46e hash_7ab3f9a730359659` + 3 more — none matched a rock/throwable name.
