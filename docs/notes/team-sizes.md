# Team sizes

> ✅ **MEASURED in-game 2026-09-07: `com_maxclients` = 8 — and it is NOT a ceiling.**
>
> `src/mp_probe/` read `getdvarint( #"com_maxclients", 0 )` = **8** in a live private Gunfight lobby.
> The obvious reading — "the ceiling is 8, so 4v4 is reachable" — is **wrong**, and was briefly
> recorded here before being corrected. 8 is the *configured client count of that lobby type*:
> **3v3 Gunfight = 6 players + up to 2 spectators = 8.** The probe measured a playlist config, not an
> engine limit.
>
> ⚠⚠ **Twelve clients runs on these maps stock — but in MATCHMAKING, not private matches.** The eight
> Faceoff/Gunfight maps (Amsterdam, U-Bahn, Game Show, ICBM, Showroom, KGB, Mansion, Glubuko) all run
> **Faceoff 6v6** — Faceoff TDM, Domination and Kill Confirmed — with no mod and no injection.
>
> ⚠ **Scope that correctly.** This project is private-matches-only by its own Scope line, and Faceoff
> is not offered in the private-match UI. So 6v6 is **not** already available within the project's
> scope. An earlier version of this note said "the capability ships" without that qualifier; it ships,
> **just not privately**.
>
> **What it does prove, and it is still the important part:** the engine and those map files support
> twelve clients on those exact maps. So the ceiling is **neither an engine limit nor a map
> property** — it is the private-match UI declining to offer a twelve-client mode on them.
>
> **This changes what the problem is.** "6v6 is not script-reachable; script only ever reads
> `com_maxclients`" remains true *as a statement about script* — but the conclusion that 6v6 is
> therefore out of reach does not follow. The task is not raising a ceiling; it is **getting a private
> lobby configured for twelve clients to run the Gunfight gametype**. Not a GSC problem.
>
> ### ✅ ANSWERED — a private TDM lobby is created with TWELVE slots
>
> **Measured in-game 2026-09-07: `com_maxclients` = 12 in a private TDM lobby on a normal map.**
>
> That settles it. `com_maxclients` is never written by script anywhere in the dump (**0**
> `setdvar` occurrences) and is fixed **at lobby creation by the playlist**, not by the gametype.
>
> **So 6v6 was never an override problem. It is an inheritance one.** Start in a lobby the menu has
> already built with twelve slots, and never be in a Gunfight lobby at all. The slots are sitting
> there unused.
>
> ⚠ This inverts how the project has always framed things. The goal table treats 6v6 as the hard one
> and map-unlock as merely awkward. **6v6 is the easy one** — the menu hands it to you for free the
> moment you stop starting from a Gunfight lobby. What is hard is getting *Gunfight's rules* to run
> in that lobby, which is the layering approach.
>
> **Both headline goals collapse into that one move.** A private TDM lobby on an arbitrary map gives
> you the map *and* the twelve slots; an injected script supplies the rules. Neither goal needs the
> DLL, and neither needs `com_maxclients` touched.
>
> ### What will not help
>
> 🪦 **RESOLVED 2026-09-08 — `maxteamplayers` is never enforced for Gunfight.** `globallogic.gsc:233-240`
> sets `level.multiteam = level.teamcount > 2`, and **both** consumers of `maxteamplayers` are gated on
> it (`team_assignment.gsc:352` and `:1030`). Gunfight is a **two-team** mode, so `multiteam` is false
> and the setting is never read. Our hook runs after `:240` so we *could* overwrite it — it would do
> nothing. The paragraph below reasons about it as a possible half-lever; that reasoning is closed.
> ⚠ This says nothing about team size generally — see [[atian-menu-source]] for the live route.
>
> `#"maxteamplayers"` is a real gametype setting — read 14 times, never set by stock, and
> `setgametypesetting` is callable (78 stock call sites). But it drives **team-balance and spawn
> loops** (`for (idx = 0; idx < level.maxteamplayers; idx++)`), while `com_maxclients` is the
> **client-slot ceiling**. Raising it inside an 8-slot lobby cannot manufacture slots. It is
> plausibly one necessary half of a wider team, never the sufficient one — another reason to start
> from a lobby that is already twelve.
>
> ⚠ **UPDATE 2026-09-08 — there is a second, custom-games-only cap, and it is not this one.**
> `globallogic.gsc:241` reads `getgametypesetting( #"hash_3a4691a853585241" )` into
> `level.var_704bcca1`. The hash cracks to **`maxsquadplayers`** (`uint:6`, max 63).
>
> **The claim above — that `maxteamplayers` is absent from `custom_games.ddl` — is CONFIRMED**, and it
> now cuts a second way. Counted across the four DDLs: `custom_games.ddl` and `gametype_settings.ddl`
> both carry `maxsquadplayers` and `maxplayers` while carrying **no** `maxteamplayers`. So in the
> generic custom-games surface the squad cap is settable and the team cap does not exist.
> Also there: **`uint:7 maxplayers`**, max 127, read at `challenges.gsc:109` and never looked at by
> this project. See [[dump-cross-check]].
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
