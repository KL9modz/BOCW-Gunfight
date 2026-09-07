# Team sizes

> ✅ **MEASURED in-game 2026-09-07: `com_maxclients` = 8 — and it is NOT a ceiling.**
>
> `src/mp_probe/` read `getdvarint( #"com_maxclients", 0 )` = **8** in a live private Gunfight lobby.
> The obvious reading — "the ceiling is 8, so 4v4 is reachable" — is **wrong**, and was briefly
> recorded here before being corrected. 8 is the *configured client count of that lobby type*:
> **3v3 Gunfight = 6 players + up to 2 spectators = 8.** The probe measured a playlist config, not an
> engine limit.
>
> ⚠⚠ **6v6 ALREADY SHIPS ON THESE MAPS.** The eight Faceoff/Gunfight maps (Amsterdam, U-Bahn, Game
> Show, ICBM, Showroom, KGB, Mansion, Glubuko) all run **Faceoff 6v6** stock — Faceoff TDM,
> Domination and Kill Confirmed. That is twelve clients, on those exact maps, with no mod and no
> injection. So `com_maxclients` there is 12 in a Faceoff lobby and 8 in a 3v3 Gunfight lobby. It is
> **per-playlist configuration**, not a hard limit and not a property of the map.
>
> **This changes what the problem is.** "6v6 is not script-reachable; script only ever reads
> `com_maxclients`" remains true *as a statement about script* — but the conclusion drawn from it,
> that 6v6 is therefore out of reach, does not follow. The capability already exists. The task is not
> raising a ceiling; it is **running the Gunfight gametype inside a lobby the menu has configured for
> twelve clients**. That is a much easier engineering problem, and it is not a GSC one.
>
> It also converges with the any-map goal on a single mechanism — decoupling gametype from the menu's
> playlist configuration. See [[dll-proxy]], which on this evidence is load-bearing for two of the
> project's three headline goals rather than an optional side track.

**Gunfight does not hardcode 2v2.** Grepping `gunfight.gsc` for `teamcount`,
`maxteamplayers`, `multiteam` returns **zero hits** — the 2v2 comes entirely from
the playlist/gametype settings. That is the good news.

## Where the settings actually live

`getgametypesetting` / `setgametypesetting` are **engine builtins**. There is no
GSC definition anywhere — 1086 calls to the getter, 78 to the setter, zero
declarations. They are **not** dvars; there is no `scr_teamcount`.

The backing store is the gametype-settings DDL, so the name you pass is a DDL
field-name hash:

- `ddl\mp_gametype_settings.ddl:2844` — `struct gametypesettings {`
- `:2926` — `uint:6 maxteamplayers;` → **max 63**
- `:3900` — `uint:7 teamcount;` → **max 127**
- `:3072` — `uint:5 prematchrequirement;`

`ddl\mp_custom_game.ddl` carries the same struct plus `gunfightroundsperloadout`,
`gunfightspyplane` and `capturetime` — which is how we know Gunfight is a genuine
custom-game mode, not just a playlist.

## Read once at init

```gsc
// scripts\mp_common\gametypes\globallogic.gsc
level.teamcount      = getgametypesetting( #"teamcount" );       // :233
level.maxteamplayers = getgametypesetting( #"maxteamplayers" );  // :240
```

Nothing re-reads either setting server-side afterwards.

## What you can and cannot override

**`level.maxteamplayers` — override post-init WORKS.** Enforcement reads the
*level var* fresh on every join, via `core_common\player\player_shared.gsc:1300`
`function_d36b6597()` → `teams\team_assignment.gsc:95` `function_efe5a681()`.

But mind this branch:

```gsc
// player_shared.gsc:1317
if ( ( level.teamcount == 0 || max_clients == level.teamcount ) && level.maxteamplayers > 0 )
    var_27e8a04e = level.maxteamplayers;
else if ( level.teamcount > 0 )
    var_27e8a04e = max_clients;          // <-- normal 2-team match lands HERE
```

For a normal two-team match where `com_maxclients != level.teamcount`, your
`maxteamplayers` is **ignored** and `com_maxclients` wins.

**`level.teamcount` — override post-init does NOT work.** `init_teams()`
(`globallogic.gsc:394`, called at `:253`) has already built `level.teams` and
`level.teamindex` from it. You would have to rebuild those yourself, or set the
setting before init reaches `:233`.

**`com_maxclients` is the hard ceiling** — an engine dvar, read live at
`player_shared.gsc:1302`. GSC can only read it.

## The shipped idiom — copy this

Gunfight itself shows the correct pattern at `gunfight.gsc:104-107`: set the
setting **and** assign the cached level var, because the setter does not
retroactively refresh anything already read.

```gsc
setgametypesetting( #"maxteamplayers", 6 );
level.maxteamplayers = 6;
```

## The enforcement gap worth knowing

Only the **auto-assign** join path checks team size. The explicit team-pick path
(`globallogic_ui.gsc:331` `menuteam`) assigns `self.pers[#"team"]` with no
`function_efe5a681()` call at all — no size check. So a cap you set may simply
not apply to players who pick a team manually.

Related: `level.prematchrequirement` (minimum players to start) is read **later**
than init, at `globallogic.gsc:5071`, guarded by `if ( !isdefined( game.gamestarted ) )`
— so an early override of that level var gets clobbered. Override the setting
instead, or replace the whole check via `level.var_f82f37a9` (`globallogic.gsc:4543`).

`level.var_22136656` is a *minimum* players-per-team that cancels the match
(`globallogic.gsc:936-963`), not a maximum — it does not block joins.

## Bots

`scriptbundle\gamesettings\bot_autofill_allies.json` / `_axis.json` exist, plus
`max_players.json` (setting `maxPlayers`, options 1-12). That is how you fill
larger teams in a private match without more humans.
