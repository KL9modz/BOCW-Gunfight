# Dump cross-check — five findings, two retractions

`tools/dump-grep.sh` run 2026-09-08 against **`shiversoftdev/t9-src`, `vm-38/`** (VM38 = retail),
cloned beside the repo. Every section returned hits.

⚠ **This is the ALTERNATE dump.** `.claude/CLAUDE.md` rates it *"more hashed — cross-check only"*
against `ate47/bocw-source`, which remains primary. Everything below wants confirming there. It is
recorded now because three of the five findings **changed code that was about to be injected**.

---

## 1 · ⚠️ A RETRACTION THAT WAS ITSELF WRONG — `gunfight_3v3` does exist

**This section first claimed `gunfight_3v3` is not a gametype string. That was wrong, and the primary
dump says so plainly:**

```
scripts/mp_common/player/player_record.gsc:589      case #"gunfight_3v3":
hashed/script/script_74453936abc39adf.gsc:68        case #"gunfight_3v3":
```

**What went wrong, and it is the lesson of this whole note.** The alternate dump leaves that name as
an *unresolved hash*, so a grep for the literal `"gunfight_3v3"` found nothing there. This note's own
caveat said *"absence in the alternate dump is not proof of absence in the game"* — and then the
finding was written up and pushed into `test_switchmap`'s target anyway.

**Absence in the alternate dump is evidence of nothing.** `ate47/bocw-source` resolves far more names;
`shiversoftdev/t9-src` is a cross-check for what it *does* resolve, never an authority on what it does
not. Run `bash tools/dump-grep.sh` with **no argument** — it defaults to the primary dump for exactly
this reason.

`test_switchmap` targets `"gunfight_3v3"` again.

⚠ Note the *hashed* form `#"gunfight_3v3"` is what appears in the switch. Whether `switchmap_load`
wants the plain string or the hash is untested — test C6 ships the plain form, which is what
`func_set_gametype()` passes in the Atian source.

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

**55 call sites in the alternate dump, 132 in the primary — and the picture is the same in both.
Every one sets the team of a world object:**

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

## 6 · 🔓 The FNV1a64 "wall" is passable for a guessable name — and `maxsquadplayers` is through it

`.claude/CLAUDE.md` lists the front end's FNV1a64 hashing under confirmed dead ends: *"this is where
the map list and per-mode `com_maxclients` live, and it is the FNV1a64 wall."* That is true for
arbitrary data. **It is not true for a name a person can guess** — the hash is unsalted, so any
candidate is testable in microseconds and a 63-bit match is proof.

The algorithm, from `atian-cod-tools/src/core/shared/utils/hash_mini.hpp`:

```
Hash64(str) = Hash64A(str, 0xcbf29ce484222325, 0x100000001b3) & 0x7FFFFFFFFFFFFFFF
Hash64A:  h = start;  for c in lower(str):  h = (h ^ c) * iv
```

Shipped as [`../../tools/crack-hash.py`](../../tools/crack-hash.py). It cracked, on the first
wordlist:

```
globallogic.gsc:230   level.var_704bcca1 = getgametypesetting( #"hash_3a4691a853585241" );
                                                                      ^^^^^^^^^^^^^^^^
                      3a4691a853585241  ->  maxsquadplayers
```

### What `maxsquadplayers` actually gates — and what it does not

⚠ **It is a SQUAD cap, and this project's goal is a TEAM cap. Do not conflate them again** — that is
the mistake that produced the `gunfight_3v3` retraction above.

| Path | Bounds on |
|---|---|
| `team_assignment.gsc:148` `function_efe5a681( team )` — **the join gate** | `com_maxclients` (8) |
| `team_assignment.gsc:136` `function_46edfa55()`, `:864`, `:851`, `:1010-1021` — **squad distribution** | `level.var_704bcca1` = `maxsquadplayers` |

So the gate that refuses a joining player uses 8, and `maxsquadplayers` bounds squad size inside the
distribution logic.

### ✅ Confirmed a real, writable custom-games field

The hash appears in the DDL — **and in the custom-games struct specifically**:

```
ddl/mp_custom_game.ddl:3446     uint:6 hash_3a4691a853585241;
```

**`uint:6` — max 63.** So 4, 5 and 6 are all in range, and the field lives in `mp_custom_game.ddl`,
which is this project's exact context.

⚠ **Note the asymmetry with `maxteamplayers`.** [`team-sizes.md`](team-sizes.md) records that
`level.maxteamplayers` is *"absent from `custom_games.ddl`"* — and it is: `maxteamplayers` sits in
`mp_gametype_settings.ddl:2926`, not the custom-games struct. **`maxsquadplayers` is the other way
round.** The squad cap is a custom-game setting; the team cap is not. For a project that is
private-matches-only, that asymmetry favours the squad cap.

**Why it is the best candidate this project has for the 3.** For Gunfight a team *is* a squad — that
is what the mode is. And unlike `com_maxclients`, this is a **gametype setting**, so
`setgametypesetting()` can write it at runtime; the project has already proven that path lands in
~0.25s for `#"timelimit"` (`.claude/CLAUDE.md` → *Timer*).

**Read it before writing it.** `lobby_probe` probe `6xxxxx` now does. In a 3v3 Gunfight lobby:

| Reading | Means |
|---|---|
| **3** | the strongest team-size lead this project has had. Then try `setgametypesetting( #"maxsquadplayers", 4 )` |
| 8, 0, or undefined | not the lever. Record it and go back to the *Untried* list |

⚠ Two hashes did **not** crack: `4091f2d0019b1f4a` (`gunfight.csc:230`, shared with `control.csc` and
`dom.csc`) and `0cd096e90260a26b` (Onslaught). ~15,000 candidates each. **That means the wordlist was
wrong, not that they are unresolvable.**

## 7 · ACTS's `cw_lobby_tool` gametype list is BLACK OPS 4's

`atian-cod-tools/src/core/acts/tools/cw/cw_lobby_tool.cpp` carries a `gametypes[]` table — `conf`,
`ctf`, `dom`, `koth`, `sd`, `tdm` — and includes `<games/bo4/pool.hpp>` and `<games/bo4/offsets.hpp>`.
Despite living under `tools/cw/`, **it is not a Cold War gametype inventory.** Consistent with
[`dll-proxy.md`](dll-proxy.md)'s note that ACTS's hardcoded list omits `gunfight` while the CLI passes
an arbitrary string through. Do not mine it for CW names.

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
