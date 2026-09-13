# Bots — add / remove / even-up, difficulty, and a CUSTOM difficulty

**Conclusion.** Bot difficulty in a T9 match is a **struct on the bot** (`bot.bot.difficulty`),
installed by `bot_difficulty::assign()` from a **per-team gametype setting** — `bot_difficulty_allies`
/ `bot_difficulty_axis`, values 0–3 — which is the same key the custom-games "Bot Difficulty" row
writes. Every consumer of the struct reads its fields with a default (`isdefined( x ) ? x : 0`,
`is_true( x )`), so **a struct we build ourselves is a difficulty**: hit chance, headshot chance, aim
delay, fire window, hipfire and range scaling, tap/burst pacing, and the five movement permissions are
all ours to set past the stock ceiling. Add/remove/even-up ride the two primitives `fill_bots` already
proved (`bot::add_bot` / `bot::remove_bot`).

Built into `gunfight_menu` 2026-09-12 as **Bots** (root page) with **Bot difficulty** → **Per team** /
**Custom bot tuning** beneath it; dvars `gf_bot_diff_allies` / `gf_bot_diff_axis` + fifteen `gf_bot_*`
knobs + `gf_bot_passive`; the app's command channel gained `gf_cmd_addbot` / `gf_cmd_removebot` /
`gf_cmd_evenbots`. ⚠ **Never run.** The setting write is the same `setgametypesetting()` every other
knob uses and the re-assign is stock's own function; the custom struct and the post-assign look scalar
are the untested parts — protocol at the bottom.

---

## 1 · Where a bot's difficulty comes from (`scripts/core_common/bots/bot_difficulty.gsc`)

```
preinit()                              :9    callback::on_joined_team( &function_e161bc77 )
  function_e161bc77( *params )         :18   if ( !isbot( self ) ) return;  self assign();
assign()                               :32   switch ( currentsessionmode() ) { case 1 (MP): self function_d46cc4f5(); }
                                       :45   self callback::callback( #"hash_730d00ef91d71acf" )   ← "bot_difficulty_assigned"
  function_d46cc4f5()                  :50   team = pers[team] ?? .team
                                       :54   self.bot.difficulty = level function_abad20c4( level function_c0e2f147( team ) )
  function_c0e2f147( team )            :61   if ( is_true( getgametypesetting( #"hash_c6a2e6c3e86125a" ) ) )     ← vs-bots mode flag
                                       :65       return getgametypesetting( #"bot_difficulty_vs_bots" );
                                       :68   if ( !level.teambased ) team = #"allies";
                                       :78   return getgametypesetting( #"hash_7a5a6325a6e843b7" + level.teams[ team ] );
  function_abad20c4( difficulty = 0 )  :87   0 → getscriptbundle( t9_bot_difficulty_mp_recruit ) · 1 regular · 2 hardened · 3 veteran
```

**The key is cracked exactly.** `tools/crack-hash.py --hash bot_difficulty_` →
`7a5a6325a6e843b7` = `#"hash_7a5a6325a6e843b7"`. The script hashes the prefix and appends the team
string, so the settings are **`bot_difficulty_allies`** and **`bot_difficulty_axis`** — and
`scriptbundle/gamesettings/bot_difficulty_allies.json` / `_axis.json` are exactly those rows:
`setting: bot_difficulty_allies`, `value1..4 = 0..3`, `optionscount 4` (labels hashed; the four stock
bundles name them recruit / regular / hardened / veteran). Per the *hashed ⇒ hidden* classifier in
`.claude/CLAUDE.md` the reverse also holds: a plain-named setting with a bundle is a menu row, which is
why the custom-games lobby shows a per-side Bot Difficulty picker. **The setting is proven writable at
lobby level by stock UI; our runtime `setgametypesetting()` write is the same channel `maxplayers`,
`timelimit` and `gunfightloadoutindex` use.**

⚠ `game-systems.md §19` said the mod should write `bot_difficulty_vs_bots`. **That key is read only
when the vs-bots mode flag (`hash_c6a2e6c3e86125a`, uncracked) is set** (:61–65); in a normal
private match the per-team pair is what counts. The mod writes the pair and mirrors an agreed pick
into `bot_difficulty_vs_bots` so both branches read the same thing.

### When `assign()` runs — the three stock call sites, and why the hook matters

| Site | Line | When |
|---|---|---|
| `callback::on_joined_team` | `bot_difficulty.gsc:11` | the bot is seated on its team — `player_shared.gsc:1039` fires `joined_team` |
| `bot::on_player_connect` | `bot.gsc:239–242` | only if `self.bot` is undefined — `add_bot` inits `.bot` first (:107), so this is the reconnect path. ⚠ *Inferred*, not measured: that the round boundary clears `.bot` (player fields other than `.pers` rebuild with the level) is what makes it the round-boundary re-assign; `mod_bots` re-assigns every round regardless, so nothing rests on it |
| `bot::function_7291a729` | `bot.gsc:371–377` | the `hash_6efb8cec1ca372dc` callback: re-init + re-assign (bot control handed back) |

Every one of them ends in `callback::callback( #"bot_difficulty_assigned" )` on the bot (:45), and
`bot.gsc:81` registers stock's own post-assign step there — so **that event is the one place a
replacement struct can be installed that catches all three paths**. The mod registers
`bot_on_difficulty_assigned` on it (`callback::add_callback`, `callbacks_shared.gsc:120`; callbacks
are appended in registration order and threaded on the bot, :57–107).

## 2 · The struct — `scriptbundle/botdifficulty/t9_bot_difficulty_mp_*.json`

Seventeen fields plus the cac list. Names cracked 2026-09-12 with the T89 32-bit script hash
(`acts h32`, reimplemented in the session scratch — Jenkins one-at-a-time, seed `0x4B9ACE2F`,
`*0x8001` finish); two stayed hashed after ~2M candidates and are labelled by behaviour.

| Field (cracked name) | Recruit | Regular | Hardened | Veteran | Reader | Effect |
|---|---|---|---|---|---|---|
| `var_d20ff29c` **shoothitchance** | 40 | 50 | 60 | 90 | `bot_weapons.gsc:3243` | % that a fire cycle's aim point is *on* the enemy; a miss aims 18–30 units off (`:3193–3230`) |
| `var_fa680c5e` **shootheadchance** | 0 | 3 | 10 | 20 | `:3288` | % that an on-target cycle aims at `j_head` (100 = always) |
| `var_d70788cb` **shootdelay** | 1.4 | 1.1 | 0.7 | 0.3 | `:3158` | seconds of aiming before each fire window; `function_957aa281()` adds more when the target is far or the bot is moving (:3160–3163) |
| `shoottime` | 0.3 | 0.4 | 0.5 | 0.7 | `:3124` | seconds the fire window lasts; the aim point is re-rolled when it expires (:3149–3152). ⚠ `<= 0` disables the cycle entirely (`:3177` returns "may fire" forever, no aim roll) — the menu never offers 0 |
| `var_65a25108` **hitchancefalloffmin** | 1 | 1 | 1 | 1 | `:3253` | hit-chance multiplier at the near end of the falloff band |
| `var_e0e4be1b` **hitchancefalloffmax** | 1 | 0.8 | 0.66 | 0.5 | `:3254` | … at the far end (`lerpfloat( min, max, dist / band )`, band = weapon range × 500…2500, :3248–3256) |
| `var_363a4bcd` *(hipfire scale)* | 0.5 | 0.5 | 0.6 | 0.7 | `:3261` | hit-chance multiplier while `playerads() < 1` |
| `var_b489efb7` **singleshotdelay** | 0.8 | 0.6 | 0.4 | 0.15 | `:2970` | seconds between taps on a `single shot` weapon |
| `burstdelay` | 1.2 | 0.9 | 0.7 | 0.25 | `:2974` | seconds between bursts on a `burst` weapon |
| `var_33be320f` **allowmoveandshoot** | 0 | 0 | 1 | 1 | `:3109` | off: with a target in view the bot sets the hold-position flag (`var_6bea1d82`, honoured at `bot_position.gsc:168`) and stops to shoot |
| `var_ea800f8` *(fast look)* | 0 | 0 | 1 | 1 | `bot.gsc:397` | after every assign: `function_3ca49c4e( 0.8 )` if set, else `( 0.1 )`; `init_bot` starts it at `1` (:975). A bot method, 1 float arg (`funcs_cw.csv`, between `botsetlooksensitivity` and `botsetcustomization`) — a look/turn scalar by placement and by the values stock feeds it |
| `allowsprint` | 0 | 1 | 1 | 1 | `bot_stance.gsc:111` | |
| `allowmelee` | 0 | 0 | 1 | 1 | `bot_actions.gsc:431` | |
| `allowprone` | 0 | 0 | 0 | 1 | (no script reader — engine-side or unused) | |
| `allowslide` | 0 | 0 | 0 | 1 | `bot_stance.gsc:53` | |
| `allowcrouch` | 0 | 0 | 0 | 1 | `bot_actions.gsc:362` | |
| `#hash_ded0efe5` (cac list) | `t9_bot_cac_mp_<level>` | | | | no script reader | bot create-a-class bundle; irrelevant under Gunfight's fixed loadouts |
| `name` | | | | | `bot.gsc:1319` (dev `record3dtext`) | |

**Every reader is `isdefined( d.x ) ? d.x : 0` or `is_true( d.x )` on `self.bot.difficulty`, and
nothing else touches the struct** — `getscriptbundle()` returns a struct, and the readers cannot tell
ours from stock's. That is the whole basis of the custom level.

## 3 · What the mod does (`src/gunfight_menu/scripts/gunfight_menu.gsc`, *BOTS* section)

| Piece | What it is |
|---|---|
| `mod_bots()` | called from `mod_apply` every round, **before** the Gunfight gate — difficulty is a per-team setting in every mode |
| `bot_diff_apply()` | writes `bot_difficulty_allies` / `_axis` from the dvars (sentinel −1 = leave the lobby's row alone; custom rides on 3 = veteran so a bot that joins before our hook lands is the *strongest* stock bot), mirrors an agreed pick into `bot_difficulty_vs_bots`, then `p bot_difficulty::assign()` on every live bot with `.bot` defined — stock's own re-read, so a pick lands now rather than at the next join |
| `bot_on_difficulty_assigned()` | the `#"bot_difficulty_assigned"` hook, self = bot: sets `.ignoreall` from `gf_bot_passive`; if that side is CUSTOM, `self.bot.difficulty = bot_custom_profile()` and `self function_3ca49c4e( bot_aim_scalar() )` — re-issued from *our* flag because stock's `function_8481733a` may run before or after ours (system registration order is not ours to assume). The scalar is only ever 0.1 / 0.8 / 1 — the three values stock itself passes |
| `bot_custom_profile()` | `spawnstruct()` + the seventeen fields from `gf_bot_*`, ms → seconds and % → fraction where the readers want fractions; `name = "gf_custom"` |
| `add_one_bot( team )` | `bot::add_bot( team )`; `team` undefined → the smaller side, tie → the side opposite the host (a solo host's first add is an opponent). `undefined` back = `addtestclient` refused = the client budget (`com_maxclients`), reported as such |
| `remove_one_bot( team )` | `bot::remove_bot()` (`bot.gsc:184` — `isbot` + not player-controlled → `botdropclient`) on the last bot of the bigger side; tie → the host's own side, so the opponents stay; falls over to the other side if that one has none |
| `even_up_bots()` | **the "odd number of humans" verb.** One read of the counts, then a plan: the side with more humans sets the size, each side wants `size − its humans` bots — surplus bots dropped first, then adds. 3 humans as 2v1 → one bot → 2v2; 4v2 with two allied bots → both dropped → 2v2. Planned from one read so a drop that takes a frame to leave `getplayers()` cannot be counted twice |
| `bot_passive_apply()` / `.ignoreall` | stock flag: `bot_action.gsc:161` and `bot_orders.gsc:51` skip the engage decision while set; `rat.gsc:48` and the dev-gui "Ignore All" command are the precedents. Target dummies |
| the pages | **Bots**: add auto / allies / axis · remove one · even up · fill to team size · remove all · passive toggle · → **Bot difficulty**: recruit … veteran (both sides) · CUSTOM · lobby's value · → **Per team** (6 rows a side) · → **Custom bot tuning**: 4 presets + 15 knobs, each row shows its live value and SELECT steps it through a value ring, re-applying to every bot on the spot; the page rebuilds itself on entry and after every step (`bot_custom_enter` / `bot_custom_refresh`) so the labels never go stale |
| presets | **Veteran+** (the dvar defaults: 100 % hit, 50 % head, 100 ms aim, 1 s window, 100 % hip, 90 % far, 100 ms tap/burst, all permissions) · **Godlike** (100 % head, 0 aim delay, 2 s window, 100 % far, 50 ms pacing, look scalar 1) · **stock Veteran copy** (the table above, to edit from) · **Potato** (10 % hit, 2 s aim delay, 25 % hip/far, nothing allowed) |

Entering the difficulty page also reads the **live** `getgametypesetting()` values back and prints
them with the bot counts — what the lobby (or a previous pick) actually holds, independent of our
dvars. The status tail shows `bots:<level>` (or `A/B` when the sides differ) and `bots:passive`.

## 4 · Unverified, in the order they will be measured

1. `setgametypesetting( #"bot_difficulty_allies", N )` **lands at runtime** and `assign()` reads it
   back. Same channel as every other setting the mod writes, but this pair has never been written from
   script.
2. `bot_difficulty::assign()` called by us **re-installs** cleanly on a live bot mid-round (stock calls
   it on reconnect and on control hand-back, never mid-fight).
3. Our `#"bot_difficulty_assigned"` callback **fires** with `self` = the bot — the event literal must
   hash to `hash_730d00ef91d71acf` (`crack-hash.py` says it does).
4. A `spawnstruct()` on `bot.bot.difficulty` **behaves** — the readers dereference it exactly as they do
   the bundle; the one difference is that `getscriptbundle()` may return a shared cached struct and ours
   is per-bot. No reader writes into it, so this should not matter.
5. `function_3ca49c4e( 1 )` after an assign — the "max" look setting. Stock's init value, never
   re-applied by stock after an assign.
6. Whether `allowprone` does anything (no script reader).
7. The even-up plan when a drop is refused (`isautocontrolledplayer`) — it is skipped silently and the
   count comes out one high; the toast shows the sides so it is visible.

## 5 · Test protocol — band B, one control per match, solo host, any map

Read the toast after every step; it prints the sides (`AvX`) or the bot count re-assigned.

| Step | Do | Pass | Fail ⇒ |
|---|---|---|---|
| B1 | **Bots → Add bot – auto** ×2 | 1v1 then … the second lands on the *smaller* side; a tie sends it opposite the host | `add_bot` refused = budget; check `com_maxclients` in the state line |
| B2 | **Remove one bot** | the bigger side loses one; tie → host's side | — |
| B3 | With 2v1 humans (or host + a friend on one side), **Even up teams** | one bot to the short side, `2v2` in the toast | a `refused` = budget again |
| B4 | **Bot difficulty → Recruit**, then **Veteran** — watch the same bot | recruit stops to shoot and never sprints; veteran sprints and shoots on the move. **Enter the page again**: the live-setting line reads back what was picked | the live line shows the lobby's value ⇒ (1) failed — the runtime write did not land |
| B5 | **Bot difficulty → CUSTOM**, then **Custom bot tuning → Preset: Potato** | bots barely hit, stand still, never sprint | no change from veteran ⇒ (3)/(4): the hook did not fire or the struct is not read; try *Godlike* to confirm the direction |
| B6 | **Preset: Godlike** | headshots only, instant reaction | — |
| B7 | Step **Hit chance** down 100 → 10 with SELECT on the row | the row's value changes in place, the toast counts the bots re-assigned, misses become visible within a few cycles | — |
| B8 | **Passive** toggle | bots wander but never engage; toggle off → they fight | — |
| B9 | Let the round end and start the next | the difficulty survives the boundary (bots reconnect → `assign` → our hook) | a revert ⇒ the round-boundary reconnect path did not fire the event; `mod_bots` re-assign should still catch it |

Step B4 needs no code to pass — it is the stock row, written from script. **If B4 passes and B5
fails, the struct is the problem and the stock levels alone are still shippable.**

## 6 · Untried — not ruled out

- **Per-bot difficulty** (one Godlike bot among recruits): the hook already has the bot in `self`;
  a per-name table would do it. Not built — no ask for it.
- **Bot names** via `add_bot( team, name, clanabbrev )` (`addtestclient` takes both).
- **`function_3ca49c4e` outside 0.1 / 0.8 / 1** — a smooth look-speed knob if it is what its
  placement suggests. Measure with the three stock values first.
- **`shoottime <= 0`** — `bot_weapons.gsc:3177` says "may fire" forever with no aim roll; whether that
  is a laser or a bot that never re-aims is a one-match question.
- **Difficulty in the pregame lobby** — the row exists there; `src/test_frontend/` (P-band) could set it
  before anyone is seated, like `maxplayers`.
- **`bot_autofill_<team>`** — a plain-named setting with a menu row and **no script reader**: the
  lobby's auto-fill is engine/frontend-side. Whether writing it at runtime seats bots on its own is
  untested; the menu's fill does the same job explicitly.
