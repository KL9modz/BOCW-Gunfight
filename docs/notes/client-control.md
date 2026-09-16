# Client control — the per-player page (god mode, ammo, weapons, … for any connected client)

**Conclusion.** Everything klaze asked for ("a client menu that can control connected clients — give god
mode, ammo, weapon, etc") is **server-side builtins on the player entity**, and the host IS the server in a
private match: `enableinvulnerability`, `givemaxammo`, `giveweapon`/`switchtoweapon`, `setclientthirdperson`,
`setmovespeedscale`, `setcamo`/`setspecialistindex`/`setcharacteroutfit`, `takeweapon`/`takeallweapons`,
`dodamage`+`suicide`, `kick`. That is the joiner-safe class of `game-systems.md §10` — a vanilla joiner needs
nothing installed, the effect is the server's to apply. Stock's own dev GUI does exactly this to other
entities from the host (`bot_devgui.gsc`: `bot givemaxammo( weapon )` :1142, `bot val::set( takedamage, 0 )`
:1338, `bot dodamage( bot.health + 1000, bot.origin )` :1363, `bot setplayerangles / setorigin` :1237-1238).

Built into `gunfight_menu` 2026-09-15 as the **Players** page (root) → one page per player. ⚠ **Never run
in-game.** Protocol at the bottom. Sibling feature the same day: bocw-8a's teleport rows on the same page
(`teleport.md`).

---

## 1 · The page

`Players` (rebuilt from `getplayers()` every time it opens — `players_enter`): humans first, then bots
(same verbs, handy for a solo test), tags `host` / `bot` / team. Select a row → `act_player_page` builds
`player_<entnum>` from `client_page_build( id, player )`:

| Row | Verb (self = host, acts on `player`) | Builtin / mechanism | Persists across that player's respawns? |
|---|---|---|---|
| Godmode `[ON]` | `act_c_god` | `enableinvulnerability` / `disable…`, flag `player.gf_god` | yes — `mod_spawn_place` re-asserts `gf_god` on whoever spawns (it already did for the host) |
| Max ammo - every weapon | `act_c_ammo` | `foreach w in player getweaponslist( 1 )` (the scavenger's list, `ammo_shared.gsc:69`) minus `level.weaponbasemelee` → `givemaxammo( w )` | n/a |
| Give weapon `>` | `act_c_hub → "weapons"` | the shared **Weapons** hub, aimed at the client (§2) | weapon lost at respawn like any give |
| Fly `[ON]` | `act_c_fly` | `player thread fly_think()` — the host's fly, threaded on the client; it reads THAT player's sprint/jump/crouch input (`getnormalizedmovement`, `sprintbuttonpressed`, … are server reads of the client's usercmd) | no — stops on death like the host's |
| Third person `[ON]` | `act_c_thirdperson` | `setclientthirdperson`, flag `player.gf_tp` | yes — `mod_spawn_place` |
| Speed: global / 150% / 200% / 50% | `act_c_speed` (cycle) → `act_c_speed_set( pct )` | `player.gf_speed_pct`; `speed_apply()` now reads it in place of `gf_speed` for that player | yes — `speed_apply` runs each spawn; `0` = back to global |
| Kill | `act_c_kill` | stock oob's kill sequence (`oob.gsc:869-873`): `dodamage( health+10000, … "MOD_TRIGGER_HURT", 8192\|16384 )` then `suicide()` if still alive (invulnerable / frozen) | n/a |
| Teleport to me / me to them / swap | bocw-8a's `act_tp_player` | `teleport.md` | n/a |
| Camo `>` · Operator `>` · Outfit `>` | `act_c_hub` | the shared hubs, aimed at the client (§2) | cosmetics are per-life like the host's |
| Take current weapon | `act_c_takeweapon` | `takeweapon( getcurrentweapon() )` | n/a |
| Strip all weapons | `act_c_strip` | `takeallweapons()` | n/a |
| Freeze / Unfreeze | `act_freeze_player` (existing) | layered `freezecontrols_allowlook` + `takedamage 0` | until released |
| To Allies / To Axis / To Spectator | `act_move` / `act_spectate` (existing, C11) | `level.autoassign` / `level.spectator` | — |
| Kick from the match | `act_c_kick` (humans only, never the host) | `kick( entnum, "GAME/DROPPEDFORINACTIVITY" )` — the stock inactivity drop (`challenges_shared.gsc:1208`), a localized key the vanilla client already has; returns to the Players page | — |

Every verb starts with `client_ok( player )`: an entity ref goes **undefined on disconnect**, so one
`isdefined && isplayer` check covers "left since the page was built" and "never valid", and answers
`^1player left` on the host's feed. Confirmations are `menu_say` on the host (self); the client only gets
the effect.

## 2 · Target context — the shared hubs act on a client

The Weapons (80 rows) / Camo / Operator / Outfit hubs are big static trees under the root; duplicating them
per player was not worth it. Instead a **target context** in the menu state:

- `act_c_hub( item, page, player )` sets `self.gfmenu.target = player`, `target_set = 1`, points that
  hub's `parent_id` at the client page (so **V returns to the player**, not the root) and `menu_switch`es
  to it. `data1` is the page id, so the row gets the `>` submenu marker.
- `act_giveweapon` / `act_camo` / `act_skin` / `act_outfit` now act on `p = self menu_target()` — the
  target while it is set and still a player, else the host — and their confirmation carries
  `target_tail( p )` = ` -> <name>`. Root use is unchanged.
- Headers show it: `menu_page_title( menu )` = `Weapons @<name>` on the five header sites (feed, split-2
  info line, split-3, hint, carousel).
- **Auto-drop:** `menu_target_sync()` is the first statement of `menu_render`; whenever the current page
  is outside the family (`weapons`, `wp_*`, `camo`, `camo_byid`, `operator`, `outfit`) — i.e. the moment
  you back out to the player page, close the menu, or open anything else — `menu_target_clear()` drops
  the target and restores the four hubs' `parent_id` to `start_menu`. The root Weapons page can therefore
  never keep giving to the last client picked.
- `menu_item_line` / `menu_hitem` submenu test gained `isstring( it.data1 )`: client rows carry an
  **entity** in `data1` (`&act_c_god, player`), and indexing `menus[ <entity> ]` was an unmeasured
  risk on the old Players page too.

## 3 · App parity (`tools/gf-control`, "Player by name" box)

`cmd_action` cases, same `gf_cmd_target` name rule (exact, then case-insensitive prefix):
`godone` `ammoone` `thirdone` `flyone` `killone` `kickone` `takeone` `stripone` · `speedone` (arg = pct,
`0` = global) · `giveone` (arg = weapon name) · `camoone` / `operatorone` / `outfitone` (arg = id). The
four hub verbs go through **`cmd_hub_verb( player, fn, a, b )`** — pin the target for the call, restore
what the open menu had — and the HOST cases (`giveweapon`/`camo`/`operator`/`outfit`) now go through it
pinned to the host, so an app command never lands on a client the in-game menu happens to have targeted.
GUI: two new button rows in the "Player by name" box (the verbs, Give picked weapon, Camo/Operator/Outfit
id → player, Speed %). ⚠ Kick from the app kicks whoever the prefix resolves to — type the whole name.

## 4 · Live list + the app's "Connected" list (round 2, same day)

**In-game:** the Players page now follows joins / leaves / team moves while it is open —
`menu_think`'s 2 s repaint tick calls `players_refresh()` when the current page is `players`, which
rebuilds the rows and puts the cursor back on the same player (found again by entity; clamped if that
player left).

**App:** the bridge is app → game only and the GSC dvar store is unreadable from outside, so the mod
publishes the roster *the other way round*. `roster_publish()` (level thread, started with the host
bootstrap) keeps ONE marked string alive in `level.gf_roster`:

```
GFROSTER|<gettime>|<count>|<name>;<team>;<host|bot|human>;<xuid>|...|END
```

rebuilt only when the roster changes (so it sits at one address for long stretches). The marker is
assembled at runtime (`"GFRO" + "STER|"`) so the payload's string table never carries a decoy.
`tools/gf-control/roster_scan.py` reads it with a **read-only** ReadProcessMemory sweep — the same
primitive `dvar_backend --finddvar` proved safe in a live match (no thread, no write, no lock) — and the
app's *Connected* combobox (Actions → Player by name) lists the players; picking one fills the Player
box with the exact name. Stale copies (a freed string the pool has not reused) parse fine; the newest
tick wins.

📏 **Measured 2026-09-15 on the live game (read-only, old build running):** the GSC string pool is a
static table in the exe's data — the menu's interned literals sit at `exe+0x420000` inside a **501 MB
private RW region that is part of the image range**, and a literal in the mapped payload appears a
second time there (the interned copy). So the sweep orders the exe-range private RW regions first:
**1.2 s to the first hit**, vs 45–120 s for the full 11.5 GB / 12,689-region private sweep (the
fallback if the pool ever moves). After the first find the cached address is re-read in ~0 s.
⚠ The roster string itself is unmeasured (the new payload was not injected yet) — expected in the same
pool since it is an ordinary script string. If the first *Refresh* after injecting finds nothing while
a match runs, that is the finding to record (then the concatenated string is not interned in the pool
and the region rank needs the address it did land at).

**IPs:** not from GSC (no builtin exposes a client's address); `getxuid()` is the stable identity the
roster carries instead. Addresses exist in the host's memory in the lobby session DDL (`clientlist[]`
with `platformGamertag` / `address` / `netsrc` — strings in the exe) and the engine's client table;
locating either is a further read-only hunt, not started.

## 5 · What is NOT here, and why

- **Invisible / ghost**, **health**, **perks** — cheap to add (`ghost`/`show`, `setnormalhealth`,
  `setperk` all in `funcs_cw.csv`), left out until the core verbs are measured.
- **Everyone at once** — the Host page already has freeze-all; a "God all / Ammo all" fan-out is a
  five-line loop once the single-target verbs are proven.
- A Players-page **kick for bots** — bots have the Bots page.

## 6 · Test order (never run)

Solo with a bot first (the bot row takes every verb), then a joiner:

1. **Page renders** — Players lists `you host allies` + bots; open a bot's page; every layout (feed /
   split 2 default / split 3). This is also the first render of the C11 Players page rows with an entity
   in `data1` — if the list paints, the `isstring` guard is doing its job.
2. **Godmode** on the bot → shoot it. `[ON]` marker; respawn keeps it (`mod_spawn_place`).
3. **Max ammo** — feed says `bot: max ammo on N weapons` (N = primaries + offhands; grenades refilled?).
4. **Give weapon** — header reads `Weapons @<bot>`, give an XM4 → `gave XM4 -> <bot>`; **V** goes back
   to the bot's page, NOT the root; then open the root Weapons page → header has no `@`, a give lands on
   the host. That pair is the whole target-context proof.
5. **Third person** on a joiner (measured for the host only so far; it is a server-set client state, so
   expected to reach a vanilla joiner). **Fly** on a joiner — their own input drives it.
6. **Speed** cycle on a joiner — feels different at 150 / 50, survives their respawn, `global` restores.
7. **Kill** a godmode'd + frozen player — the suicide half is what has to land.
8. **Kick** a joiner — they see the inactivity drop text; Players page rebuilds without them.
9. App: `Player by name` + God mode / Give picked weapon on a joiner.
10. **Live list:** stay on Players while a bot is added from the app (`gf_cmd_addbot`) — the row appears
    within 2 s, cursor unmoved. **App roster:** Actions → *Connected* → Refresh with a match running:
    the names appear (status says `swept ~1 s`), pick one, the Player box fills.

Unknowns to record: whether `getweaponslist( 1 )` includes the alt/underbarrel entries (harmless if so);
whether `suicide()` bypasses `enableinvulnerability` (stock oob relies on it for players); whether the
kick reason key shows the inactivity text or a generic drop; third person on a joiner.
