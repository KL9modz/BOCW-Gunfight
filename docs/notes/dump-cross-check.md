# Dump cross-check — five findings, two retractions

`tools/dump-grep.sh` run 2026-09-08 against **`shiversoftdev/t9-src`, `vm-38/`** (VM38 = retail),
cloned beside the repo. Every section returned hits.

⚠ **This is the ALTERNATE dump.** `.claude/CLAUDE.md` rates it *"more hashed — cross-check only"*
against `ate47/bocw-source`, which remains primary. Everything below wants confirming there. It is
recorded now because three of the five findings **changed code that was about to be injected**.

---

## 1 · 🪦 RETRACTION — `gunfight_3v3` is not in this dump

**Zero occurrences**, anywhere. `player_record.gsc:602` carries only:

```gsc
case "gunfight":
```

The project has repeated *"`gunfight` and `gunfight_3v3` are two distinct gametype strings, both in
`player_record.gsc`'s switch"* across [`menu-map.md`](menu-map.md), `.claude/CLAUDE.md` and
[`atian-menu-source.md`](atian-menu-source.md) — and it was baked into `test_switchmap`'s target
string, which would have made **test C6 switch to a gametype that does not exist**.

⚠ **Scoped honestly:** absence in the alternate dump is not proof of absence in the game. A hashed
form (`hash_…`) would not match the grep. But a sibling case would be expected in plain form next to a
plain `"gunfight"`, so the plain-string claim is the part that does not survive.

**Note the stock UI still offers a "3v3 Gunfight" playlist** — that is observed, and
[`menu-map.md`](menu-map.md)'s 8-slot lobby came from selecting it. A playlist name is not a gametype
string. The two were conflated.

**`test_switchmap` now targets `"gunfight"`.**

## 2 · 🔓 The 3-per-team limit is NOT enforced by team assignment

The chain, in full:

```gsc
// player_shared.gsc  function_d36b6597()
var_d13c9b78 = getdvarint( #"com_maxclients", 0 );          // 8
...
if ( level.teamcount == 0 || var_d13c9b78 == level.teamcount && level.maxteamplayers > 0 )
    var_27e8a04e = level.maxteamplayers;
else if ( level.teamcount > 0 )
    var_27e8a04e = var_d13c9b78;                            // <- Gunfight lands here
return var_27e8a04e;
```

Gunfight is `teamcount == 2` with `com_maxclients == 8`, and `8 != 2`, so it returns **8**.

```gsc
// team_assignment.gsc:148  function_efe5a681( team )
max_players  = player::function_d36b6597();                 // 8
team_players = getplayers( team );
if ( team_players.size >= max_players && max_players != 0 )
    return false;
```

**A team is refused only at eight players. Nothing in that path says three.**

So 4v4 inside 8 client slots is not blocked at the script layer — what is blocked is a *ninth client*,
and 4v4 needs only eight. Where the 3-per-team split actually comes from is **still unestablished**,
and is now a much narrower question: it is not `com_maxclients`, not `maxteamplayers` (never enforced
for a two-team mode), and not `function_efe5a681`.

⚠ This does **not** say 4v4 works. It says the obvious script-side blocker is not there. Test C8.

## 3 · 🪦 RETRACTION — `setteam` is an ENTITY function

**55 stock call sites. Every one sets the team of a world object:**

```gsc
supplypod   setteam( attackingplayer getteam() );      // supplypod.gsc:148
vehicle     setteam( #"neutral" );                     // vehicle.gsc:230
grenade     setteam( self.pers[#"team"] );             // weapons.gsc:1627
turret      setteam( attackingplayer.team );           // ultimate_turret_shared.gsc:226
helicopter  setteam( owner.team );                     // helicopter_shared.gsc:124
```

…plus mines, tear gas, trophy systems, ballistic-knife models, bombs. The one player-ish site is
`prop.gsc:4686`, and its neighbours give it away — `setplayercollision(0)`, `makesentient()`,
`setscale(2)`: Prop Hunt converting a player **into a prop**, not reassigning a team.

**The stock player team-change path is `teams::change( team )`** (`teams.gsc:352`), and it is much more
than one call:

```gsc
if ( self.sessionstate != "dead" ) { ...; self suicide(); }
self.pers[#"team"] = team;
self.team          = team;
self.sessionteam   = self.pers[#"team"];
self globallogic_ui::updateobjectivetext();
self spectating::set_permissions();
self openmenu( game.menu[#"menu_start_menu"] );
self notify( #"end_respawn" );
```

⚠ The old `src/test_setteam/` would have called an entity function on a player and most likely
measured nothing. **It has been replaced by `src/test_teamfill/`**, which asks the engine the actual
question — put bots on one team until it refuses — instead of trying to force a move.

**This is exactly what `dump-grep.sh` was built to catch, and it caught it before a match was spent.**

## 4 · `bot::add_bot`, not `addtestclient`

One stock call site for the builtin, and it is wrapped:

```gsc
// bot.gsc:137
bot = addtestclient( name, clanabbrev );
if ( !isdefined( bot ) ) { return undefined; }
bot init_bot();                                   // <- a raw call SKIPS this
```

The public API is **`bot::add_bot( team, name, clanabbrev )`** — it runs `init_bot()`, sets
`bot.botteam`, and handles class selection. Stock calls it as `bot::add_bot( team )` from
`dev.gsc:1705`, `rat.gsc:76` and `_prop_dev.gsc:1421`.

A raw `addtestclient()` produces a half-initialised client. **`test_addclients` now uses the wrapper.**

And it takes a **team**, which is what makes C8 cheap: `team_assignment.gsc:107` gates bot placement on
`getplayers( self.botteam ).size < max_players`, so bots reach the same cap through the bot path.

## 5 · `getplayers()` takes a team filter

`getplayers` is 0–4 args, and `getplayers( team )` appears throughout `team_assignment.gsc`. Both new
tests use it to count one team without iterating and comparing by hand.

---

## What changed in code

| Project | Change |
|---|---|
| `test_switchmap` | target `"gunfight_3v3"` → `"gunfight"` — finding 1 |
| `test_addclients` | raw `addtestclient()` → `bot::add_bot( undefined )` — finding 4 |
| ~~`test_setteam`~~ → `test_teamfill` | rebuilt around the per-team cap — findings 2, 3, 4 |

All still pass `tools/check-args.py` with zero arity mismatches.

## Untried — not ruled out

- **Confirm all five against `ate47/bocw-source`**, the primary dump. `bash tools/dump-grep.sh` with
  no argument does exactly this run against it.
- **Where the 3-per-team split actually comes from.** Narrowed, not answered. Not `com_maxclients`,
  not `maxteamplayers`, not `function_efe5a681`. Candidates: the playlist/DDL layer, or
  `level.var_704bcca1` (`team_assignment.gsc:136`, a second cap in `function_46edfa55` that this pass
  did not chase).
- **`teams::change()` as a direct move.** Has zero callers in this dump — a library function nothing
  uses. Whether it works standalone, and what its `suicide()` and `openmenu()` do to a live match, is
  untested.
- **`bot.botteam = #"spectator"`** (`bot.gsc:156`). Bots can be parked as spectators, which is a way
  to test the spectator half of the 6+2 question directly.
