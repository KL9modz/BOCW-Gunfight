# Loadout-pool camo — controlling the camo on Gunfight's rotating loadouts

**Conclusion.** The Gunfight loadout pool never carries a camo: every pool weapon is built bare and
handed over with no weapon options, so the only camo a pool gun ever shows is a blueprint's own. The
camo lives in the *weapon options* of the player's held weapon, and the engine ships a server-side
builtin that rewrites exactly that on a held weapon — **`self setcamo( weapon, camoIndex )`**. Painting
every pool weapon on every spawn, from server GSC, is therefore a per-spawn hook plus one builtin call
per weapon: no loadout rewriting, no bundle authoring, no client-side anything, and **joiners see it with
nothing installed** (the world model and the killcam read the same options).

Built into `gunfight_menu` 2026-09-12 as **Loadout → Pool camo** (dvars `gf_camo` / `gf_camo_pool` /
`gf_camo_split`, also in `tools/gf-control`). **Random is on by default** (2026-09-13): one roll per
weapon per round, everyone sharing the same pair, primary and secondary rolled separately. ⚠ **Never
run.** The builtin is proven (it is Pack-a-Punch's and the reactive camos' own repaint, and the Atian
Menu's Camo page); the *spawn-frame timing* and the *blueprint set* are ours to measure — protocol at
the bottom.

---

## 1 · Why the pool is bare — the give path (`scripts/mp_common/gametypes/gunfight.gsc`)

```
givecustomloadout()                              :237   setloadout( game.var_96a8ff4a[ game.var_b6beb735 ] )
  setloadout( loadout )                          :340   takeallweapons / clearperks / cleartalents
    function_44244433( loadout )                 :608   the give
      primaryweaponstruct = function_d98e2783( loadout, "primary" )      :611
      self giveweapon( primaryweapon, undefined, var_df9e1af5 )          :618   ← options = undefined
      ... same for "secondary"                                           :637
```

`function_d98e2783( loadout, slot )` (:494) is the weapon builder. Two branches on the loadout's
blueprint field (`var_26b5c8ef` primary / `var_4c0d0c4b` secondary, `-1` in the default/sniper/melee
bundles, `0..19` in `mp_gunfight_loadouts_blueprints`):

| branch | code | look |
|---|---|---|
| blueprint `> -1` | `function_f62a996b( name, index + 1 )` → `{ weapon, var_fd90b0bb }`; the second field rides as `giveweapon`'s **third** arg | the blueprint's own cosmetics |
| otherwise | `getweapon( name, attachments )` — attachments only | **bare**: no camo, no reticle, nothing |

`giveweapon` is `giveweapon( weapon, weaponOptions, blueprint, ? )` (1–4 args, `funcs_cw.csv`). Gunfight
always passes `undefined` for the options slot. Compare Gun Game, which is the stock precedent for a
gametype choosing the camo on a script-built weapon (`gun.gsc:331,403,466`):

```gsc
renderoptions = function_ea647602( "camo", weapon );          // the camo render options this weapon has
camooption    = renderoptions[ camoindex ].item_index;          // the camo INDEX
weaponoptions = self function_6eff28b5( camooption, 0, 0 );    // camo index -> weapon options
self giveweapon( weapon, weaponoptions, var_f879230e );        // options ride in at the give
```

So there are two ways to put a camo on a pool gun, and the second is the one the mod uses:

1. **Bake it at the give** — replace `setloadout` and pass `function_6eff28b5( index, 0, 0 )` as the
   options. Clean, but it means re-implementing the 150-line give (talents, both slots, grenades,
   `loadout::function_442539` slot bookkeeping) or take-and-regive after the stock one. Not done.
2. **Repaint the held weapon** — `setcamo( weapon, index )` after the stock give. One call per weapon,
   the stock give untouched. ← **built.**

## 2 · The repaint builtin and its relatives

All in `reference/funcs_cw.csv` (ate47's table, addresses in `BlackOpsColdWar.exe`):

| builtin | shape | stock caller | what it is |
|---|---|---|---|
| **`setcamo`** | player method, `( weapon, camoIndex )` | `item_inventory.gsc:6627` (Pack-a-Punch tiers 67/68/69 onto the held gun) · `activecamo_shared.gsc:954` (reactive camos stepping stages) · `zm_weapons.gsc:615` | **rewrites the camo in a held weapon's options.** The Atian Menu's `func_camo` is this one call on `getcurrentweapon()` |
| `getcamoindex` | function, `( weaponOptions )` | `item_inventory.gsc:6607`, `activecamo_shared.gsc:327` | options → camo index |
| `function_ade49959` | player method, `( weapon )` | same files | held weapon → its options (the read half) |
| `function_6eff28b5` | player method, `( camoIndex, reticle, paintshop, ? )` 2–4 args | `gun.gsc`, `zm_weapons.gsc:2752`, `weapons.gsc:172` | camo index → weapon options (BO3/BO4's `calcweaponoptions`) |
| `function_ea647602` | function, `( "camo", weapon )` | `gun.gsc:331`, `item_inventory.gsc:3731` | the render-option list a weapon supports; each entry has `.item_index` |
| `function_8b51d9d1` | function, `( camoOptionName )` | `activecamo_shared.gsc:227` | camo bundle name/hash → camo index |
| `getactivecamo` | function, `( camoIndex )` | `activecamo_shared.gsc:237` | camo index → reactive-camo bundle name, if it is one |
| `getweaponslistprimaries` | player method, `()` | `prop.gsc:3125`, `dev.gsc:1177` | the held primaries — in T9 terms **primary and secondary**, offhands excluded |

Two stock facts worth having on the record:

- **`wzrandomcamo`** is a gametype setting (`item_inventory.gsc:3728`): when set, every *item pickup* gets a
  random camo via `function_ea647602` → `function_6eff28b5` → `giveweapon`. Its only reader is
  `item_inventory` — the Warzone/Outbreak pickup path, which Gunfight never enters. A one-line "random camo"
  setting for Gunfight does **not** exist; the mod's random modes do the same roll in script.
- **Blueprint weapons and the repaint.** Before putting a Pack-a-Punch camo on a *blueprint* weapon, zombies
  calls `self function_40d6838f( weapon, 0 )` first (`zm_weapons.gsc:605, :748` — only when
  `var_f879230e > 0`, i.e. the give carried a blueprint), then `setcamo`. Semantics unknown (2 args, player
  method, sits between `function_88772f88` and `function_d01c19b3` in the give/take pool). **If the
  Blueprints set ignores `gf_camo`, that call — exact shape, `0` second arg — is the first thing to try.**

## 3 · The index space — `gamedata/weapons/common/camooptions.csv`, the `camo` rows

The number `setcamo` takes is the row index of the `camo` table. 121 rows in the dump; `0` is *none*
(every stock check treats `camoindex == 0` as unpainted, `zm_weapons.gsc:2727` builds "no camo" options
from index 0). The Atian ids klaze already has (61/62/63 Gold/Diamond/DM Ultra, 67–69 PaP) land exactly
on these rows, which is the cross-check that the csv index *is* the `setcamo` index.

| rows | what | notes |
|---|---|---|
| 1–60 | tiers 1–6, interleaved: tier *t* MP = `(t-1)*10 + 1..5`, tier *t* ZM = `(t-1)*10 + 6..10` | `camo_tier1_mp_01` … `camo_tier6_zm_05` |
| 61 / 62 / 63 | `camo_mastery_mp_gold` / `_diamond` / `_darkmatter` | **Gold / Diamond / DM Ultra** |
| 64 / 65 / 66 | `camo_mastery_zm_gold` / `_diamond` / `_darkmatter` | **Golden Viper / Plague Diamond / Dark Aether** |
| 67 / 68 / 69 | hashed names, flag column `1` | **Pack-a-Punch 1/2/3** — `item_inventory.gsc:6608` hard-codes 67/68/69 as the PaP tiers |
| 70–74 / 75–79 | tier 7 MP / ZM | the seventh category, appended after the PaP block |
| 80–115 | `camo_t9_cdl_<team>_{ms,pc,sy}` | 12 CDL teams × 3 (atl chi dal fl la_gor la_optic lon minn nyc par sea tor — the 2020-season branding, OpTic LA not LA Thieves) |
| 116–118 / 119–121 | hashed names, flag `1` | **PaP Mauer der Toten 1–3 / PaP Forsaken 1–3** — labels from the Atian source (`menu_items.gsc:149-154`), not verified here |
| 122+ | not in the dump's csv | the Atian by-id page loops to 149 for no reason the source records; store/reactive camos are camo indices too (`getactivecamo( index )`), so higher ids may exist in the live table — probe with the host Camo page |

**Category names — external, and the tier→name order is a ⚠ guess.** The dump has hashed display
names only. The game's categories, in the order the camo menu lists them:
MP **Spray, Stripes, Classic, Geometric, Flora, Science, Psychedelic** (5 each, 35 total, Gold needs all 35);
Zombies **Grunge, Liquid, Brushstroke, Vintage, Fauna, Topography, Infection** (+ Golden Viper / Plague
Diamond / Dark Aether). The obvious reading is tier1 = Spray, tier7 = Psychedelic (and tier1 = Grunge …),
**but nothing in the dump ties a tier number to a name** — pick id 1 on the by-id page and look at the gun
before writing that down. Sources: [upcomer camo guide](https://upcomer.com/black-ops-cold-war-multiplayer-camo-guide/),
[Charlie INTEL zombies camos](https://www.charlieintel.com/black-ops-cold-war/how-to-unlock-all-zombies-camos-in-black-ops-cold-war-64837/).

The other section of the same csv, 55 `camo_elixir` rows, is a different option type (all hashed names); not
what `setcamo` indexes.

## 4 · What the mod does (`src/gunfight_menu/scripts/gunfight_menu.gsc`, *LOADOUT-POOL CAMO* section)

| dvar | values | default |
|---|---|---|
| `gf_camo` | `-2` random each round (rolls shared by everyone) · `-3` random per player-spawn · `-1` stock (pool's own look) · `N` a camo index | `-2` |
| `gf_camo_pool` | what the random modes draw from: `0` mastery + PaP (61–69, 116–121, 15 ids) · `1` every mapped id 1–121 | `0` |
| `gf_camo_split` | `1` primary and secondary roll **separately** · `0` one roll covers both | `1` |

**Do primary and secondary each get a random, or share one?** Each — by default. The roll is made *per
weapon*, keyed by the weapon's name (`mod_camo_id( w )`), so the two slots get independent draws; with
`gf_camo_split 0` the key collapses to one and both slots take the same roll. Per round (`-2`) the rolls
live in `level.gfmenu_camo[ name ]`: everyone holds the same two weapons in a round, so keying by name
hands every player the same pair, and `level` is rebuilt at every round boundary (mp_probe) so the pair
re-rolls itself. Per player (`-3`) they live on the player (`self.gfmenu_camo`), cleared by every
start, so each spawn is a fresh pair. A fixed index paints both slots the same, as before.

- **Hook:** the existing `on_spawned` handler (`mod_spawn_place`). `callback::on_spawned` fires at
  `globallogic_spawn.gsc:758`; the stock give (`loadout::give_loadout`, :637 → `givecustomloadout`) has
  already run, so the repaint lands on top of it. Gated on `mod_is_gunfight()` — in TDM etc. players hold
  their own classes and their own camos, which this must not touch.
- **What gets painted:** every weapon in `getweaponslistprimaries()` — primary and secondary, whatever the
  set (default, snipers, melee knives, blueprints). Offhands are left alone.
- **When:** on the spawn frame, then again on every `weapon_change` for the life of that spawn
  (`mod_camo_hold`, endon death / disconnect / `spawned_player` / a restart notify). The spawn-frame call
  is the one intended; the switch re-paint is the Atian `force_camo` timing (`header.gsc:250` paints
  *only* on `weapon_change`), kept as belt and braces for a give the engine has not finished raising.
  Both are idempotent, so double-painting costs nothing.
- **A menu pick repaints everyone immediately**, bots included — Gunfight has no respawn, so "next spawn"
  would mean next round — and discards the rolls already made, so a pool or split change re-rolls on the
  spot. `Stock` mid-round strips to index 0 (bare) until the next spawn; a blueprint's own camo cannot be
  put back from script, so that item says so.
- The hold thread re-reads `gf_camo` on every paint, so an app-side change lands at the next weapon
  switch rather than the next round.
- **Flags line** shows `camo:<label>` whenever it is not the default (random each round). **Not** in
  `gunfight_mod` (the no-menu variant stays untouched).

**Joiner safety / disclosure.** Server-side script, nothing on the client. But it is *visible*: a Gold
pool gun in a killcam is an obvious tell that the match is modded (`tac-risk-model.md` — cosmetic, no
gameplay effect, host-side script like everything else in the payload).

## 5 · Unverified, in the order they will be measured

1. `setcamo` on the spawn frame, on a weapon that is **not** the current one (the secondary). Every stock
   caller paints the *current* weapon after the raise settled; ours paints both immediately.
2. Whether a repaint survives the pregame-to-round weapon churn (`function_770b76d3` gives the current AND
   next loadout's weapons for preloading; `takeallweapons` at the next spawn discards them anyway).
3. The **Blueprints** set: does `setcamo` show over a blueprint's own cosmetics, or is `function_40d6838f`
   (§2) needed first.
4. Joiner visibility — expected yes (options are server state), measured never.
5. Tier → category name (§3), and whether ids above 121 render anything.

## 6 · Test protocol — band M, one control per match

Host + at least one bot (a joiner is better: item 4). `gunfight_menu` injected, match restarted.

| step | do | expect | result |
|---|---|---|---|
| 0 | inject, restart, spawn — touch nothing | **random is the default**: both weapons spawn with a mastery / PaP camo, primary ≠ secondary (usually — 15 ids, so 1 in 15 they match) | `______` |
| 1 | Loadout → Pool camo → **Gold** | toast `pool camo: Gold`; the gun in hand turns gold **this round** | `______` |
| 2 | switch to the secondary | gold too (painted at the same time, or on this `weapon_change`) | `______` |
| 3 | let the round end; next round | both weapons spawn gold, no pick needed; flags line shows `camo:Gold` | `______` |
| 4 | get killed by a bot / watch a killcam | the bot's / joiner's weapon is gold | `______` |
| 5 | Pool camo → **Random each round**, play 2 rounds | every player has the same pair within a round (compare a bot's gun in the killcam), a different pair next round; **Random: same for both** makes the pair one camo | `______` |
| 6 | Loadout → **Blueprints**, next round, Pool camo → Gold | gold over the blueprint, **or** the blueprint look wins → try `function_40d6838f( w, 0 )` before `setcamo` (§2) | `______` |
| 7 | Pool camo → **Stock** mid-round | toast says bare until next round; weapons go bare; next round is the pool's own look again | `______` |
| 8 | by-id page: ids 1, 6, 70, 80 | write down which category each is (§3) | `______` |

⚠ A negative on step 1 is a *timing* result, not a "setcamo does not work" result: the same builtin is the
Atian Camo page klaze can press on the same weapon a second later. If 1 fails and the Atian page works,
move the paint to `waittill( #"weapon_change" )` only (drop the spawn-frame call) and re-run.
