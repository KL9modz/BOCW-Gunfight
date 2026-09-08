# The Atian Menu — the map carry, and what it does and does not unlock

The private-match **map** restriction is closed. The **team-size** restriction is not closed *by this
menu* — the CW build ships no gametype control. That is an observation about one tool at one version,
**not** a limit on the project. Untried routes are listed at the bottom and none of them is exhausted.

Everything here was established by walking the menu in-game on 2026-09-07/08. The BOCW front end is
compiled LUA and absent from every public dump (`.claude/CLAUDE.md` → dead ends), so none of it is
derivable from `bocw-source`. **Do not try to.**

---

## Verdict

| Goal | Status | By what |
|---|---|---|
| **Any map** | ✅ **CLOSED** | Atian Menu map carry — 19 maps, mid-match, no `cwdllgt`, no DLL proxy |
| **Round timer** | ✅ **CLOSED** | `gunfight_mod` `timer_override` — 60s, and it survives the carry |
| **Correct round flow / HUD** | ✅ **CLOSED** | `zones_guard` + `timelimit_fix` + `presentation`, all verified in-game |
| **Team size** | ⚠️ **3v3 working, larger not yet reached** | Start in the stock `3v3 Gunfight` playlist (8 slots). This menu build has no gametype control, so it cannot itself build a larger lobby — see *Untried* |

**Confirmed end to end 2026-09-08: 3v3 Gunfight on Zoo, 60-second rounds, correct HUD, clean return
to lobby.** Zoo is a 6v6 map, not one of the nine `mp_sm_*` Gunfight maps.

---

## ▶ PROCEDURE — Gunfight, any map, 60-second rounds

### One-time setup

Deploy cwpatch into the Discord slot **with the game closed**. It auto-loads on every launch
afterwards — no injection step — and gives F4/F6/F7 (`lobbylaunchgame` / `fast_restart` /
`full_restart`).

```
cp <cwpatch 13,824-byte dll> "<game>/discord_game_sdk.dll"
```

⚠ Back up the real Discord SDK first (**3,891,512 bytes**). Battle.net restores it on repair, which
silently turns the hotkeys off. **If F4–F7 stop working, check this file's size before anything
else** — 13,824 is cwpatch, 3,891,512 is stock.

### Per session

Injection scripts: [`../../tools/inject.sh`](../../tools/inject.sh) (deployed to `/c/bocw/` on the
test box). Payload build and paths: [`../../tools/README.md`](../../tools/README.md).

| # | Step | Why |
|---|---|---|
| 1 | Start a private match on **`3v3 Gunfight`** — *not* regular Gunfight | Builds an **8-slot** lobby (6 players + 2 spectators) instead of 2v2's. `com_maxclients` is fixed at lobby creation and **cannot be changed later** — this choice is load-bearing and unrecoverable |
| 2 | Load into the match once | Puts `mp_common\bb.gsc` in the scriptparsetree pool. `injectcw` fails until this happens |
| 3 | `inject.sh menu` | Atian Menu |
| 4 | Restart the match (F7, or via lobby — either is fine here) | Injection is inert until a map load links it |
| 5 | `RMB+V` → `Map` → `R` → pick from the 19 | up `RMB` / down `LMB` / select `R` / back `V` |
| 6 | `inject.sh mod` | Replaces the menu — fine, the carry is already done |
| 7 | Restart the match — **F7 ONLY** | Links the mod while keeping the carried map. **The lobby route discards the carry** — see below |
| 8 | Play | 60s rounds, correct Gunfight HUD, clean lobby exit |

Re-run 3–5 to change map again.

### The three traps

**1 — Step 7 must be F7. cwpatch is REQUIRED, not a convenience.**
The carry is a **load-time map override**; the lobby's own state is never changed by it. Returning to
the lobby therefore discards the carry and reloads the lobby's own map. `full_restart` (F7) restarts
the match *without* going through the lobby, which is the only way to link the mod while keeping the
carried map. Step 4 is different — no carry has happened yet, so the lobby route is safe there.

⚠ Consequence: **the workflow cannot be completed at all without cwpatch deployed.**

**2 — The carry RESETS gametype settings.** Setting round time in the stock **Edit Game Rules** menu
works, but carrying to another map discards it and the timer resets to **30**. The carry
re-initialises gametype settings, so *anything* set through the stock rules menu is thrown away.
`timer_override` survives because `mod_apply()` reruns on every `on_start_gametype`, reapplying it
after each carry. **Under a carry the override is needed at *any* value, including ones the rules
menu offers** — not just above 60s.

**3 — Only one payload can be injected at a time.** See *Injection constraints* below. The menu and
the mod share the one known-safe replace target, so the second clobbers the first. That is why the
procedure is sequential.

### Diagnostic: the scoreboard lies, and that is informative

After a carry the scoreboard and menu still name the map the lobby was created on. That staleness is
not a bug to fix — it shows the carry is a **map override at load time**, not a lobby
reconfiguration. Which is exactly why it cannot deliver 6v6.

---

## What the menu is

**Not stock UI, and not a DLL overlay.** It is a precompiled GSC mod menu that we install.

| | |
|---|---|
| Tool | [`ate47/t8-atian-menu`](https://github.com/ate47/t8-atian-menu) — **same author as ACTS** |
| Asset | `BlackOpsColdWar_atianmenu_pc.gscc`, release tag `latest_build`, **66,320 bytes** |
| Header | `80 47 53 43 0d 0a 00 38` — `cw::GSC_MAGIC`, last byte `38` = VM38 retail |
| Injected as | `acts injectcw <gscc> scripts\mp_common\bb.gsc scripts\core_common\clientids_shared.gsc` |
| Reliability | Injected cleanly every attempt. **Must be re-injected after every game restart**, and the match restarted afterwards so the script links |

Because the repo is public, keybinds and structure come from source rather than from walking.

**[`scripts/config/keys.gsc`](https://github.com/ate47/t8-atian-menu/blob/master/scripts/config/keys.gsc), verbatim:**

```gsc
self.menu_open   = "ads+melee";
self.parent_page = "melee";
self.last_item   = "ads";
self.next_item   = "attack";
self.select_item = "use";
```

| Action | Game action | Default PC key |
|---|---|---|
| Open | ADS + Melee | RMB + V |
| Up (`last_item`) | ADS | RMB |
| Down (`next_item`) | Attack | LMB |
| **Select** (`select_item`) | Use | **R** |
| Back (`parent_page`) | Melee | V |

⚠ **`select_item = "use"` does NOT mean F.** On BOCW PC the `use` action resolves to **R (Reload)**.
Confirmed in-game 2026-09-08 after F, E and Space all failed. This one fact is what made the menu
look broken: it opened and scrolled but appeared to select nothing. `select_item` reads like F to
anyone who knows CoD's default Interact key — hence the time it cost, and hence recording it.

---

## The map carry — mechanism, and why it stops short of 6v6

The carry changes the map **inside an already-created lobby**. `com_maxclients` is fixed at lobby
creation *by the playlist* ([`team-sizes.md`](team-sizes.md): 8 measured in a private Gunfight lobby,
12 in a private TDM lobby, both 2026-09-07). Our mod never touches the playlist, so it can never
change the slot count. That is a property of **the carry**, not of the project: any route that
reconfigures the playlist instead of overriding the map at load time is unaffected by it.

### The 3v3 route — available today, and better than 2v2

`gunfight` and `gunfight_3v3` are two distinct gametype strings (both appear in
`mp_common/player/player_record.gsc`'s gametype switch). The stock UI offers 3v3 Gunfight as its own
playlist, which builds an **8-slot** lobby — matching the measured `com_maxclients` of 8.

Because the carry preserves the lobby, starting in 3v3 Gunfight and then carrying keeps those 8
slots. **So 3v3 Gunfight on any of the 19 maps is available now**, with no gametype forcing and no
DLL. Not 6v6, but strictly larger than the 2v2 the project had been assuming, and it needs nothing
that is currently blocked.

### ⚠ The lobby-glitch contrast — and the one measurement that could unlock 6v6

The **map/mode carry glitch** behaves differently: it makes every map selectable *under Gunfight*,
and the game then reports "Gunfight on \<map\>" correctly. That is a genuine **playlist
reconfiguration**, where our carry is only a load-time override. The glitch changes the thing that
sets `com_maxclients`. Our menu cannot.

**So: get into a glitched Gunfight-on-a-6v6-map lobby and inject
[`../src/mp_probe/`](../../src/mp_probe/). Read `1xxxxx`.**

| Reading | Means |
|---|---|
| `100012` | The glitched lobby has **twelve slots** — that is **6v6 Gunfight**, with nothing currently blocked |
| `100008` | The glitch changes the map list but keeps Gunfight's slot count, and 6v6 stays blocked |

The glitch is unreliable, but this only needs it to work **once**.

### Why `maxteamplayers` is not the lever for a two-team mode

`globallogic.gsc:233-240` is the whole chain:

```gsc
level.teamcount      = getgametypesetting( #"teamcount" );
level.teamcount      = math::clamp( level.teamcount, 1, getdvarint( #"com_maxclients", ... ) );
level.multiteam      = level.teamcount > 2;
level.maxteamplayers = getgametypesetting( #"maxteamplayers" );
```

Both consumers of `maxteamplayers` are gated on `multiteam` (`team_assignment.gsc:352` and `:1030`),
and `multiteam` is `teamcount > 2`. Gunfight is a **two-team** mode, so `multiteam` is **false** and
`maxteamplayers` is **never enforced**. Our hook runs after line 240, so we *could* overwrite it — it
would do nothing.

**The binding constraint is `com_maxclients`**, fixed at lobby creation, which script only reads. That
narrows where to look — at lobby *creation*, not at runtime — rather than closing the question.

---

## Injection constraints — only ONE known-safe replace target

`injectcw` takes `(script, target, replace)` and **overwrites the replace script's buffer**. Two
injections sharing a replace clobber each other, which is why injecting `gunfight_mod` kills the
Atian Menu. Coexistence would need two different pairs.

**That was tried and it broke the game.** `gunfight_mod` injected over
`core_common\scene_model_shared.gsc` → leaving a match **hung forever on "connecting to lobby"**.
That file declares `class cscenemodel : csceneobject` with an empty body, which looked free to lose —
but the **frontend** uses scene models for menu backgrounds and character previews, and a subclass
declaration must still exist at link time. **An empty body is not a free loss.**

Rejected for the same class of reason:

| Candidate | Why not |
|---|---|
| `core_common\serverfield_shared.gsc` | defines `register`/`get`, actively used |
| `mp_common\entityheadicons.gsc` | registration wrapper; killing it leaves `land_mine`, `molotov`, `supplydrop` calling `entityheadicons::` against uninitialised state |

**`clientids_shared.gsc` is the only known-safe replace.** Community standard, and its functionality
has been destroyed by every injection all session with no observed consequence. Do not substitute
another without testing a **lobby return** — that is the check that catches frontend breakage, and
it is the one `scene_model_shared` failed.

**Prerequisite for any injection:** the process must have loaded MP scripts once, or the hook is not
in the scriptparsetree pool and `injectcw` reports `Can't find target script`.

---

## The walk — evidence

Walked in full 2026-09-08: all four root pages **and** the `Map` submenu.

### Screens

The root is **paged**, titled `---- Atian Menu CW (n/N) ----`. Observed `(4/4)` — four pages. Paging
uses the same up/down inputs; there is no separate page control.

| # | Screen | Reached from | Contents |
|---|---|---|---|
| 1–3 | `Atian Menu CW (1/4)`–`(3/4)` | root, scroll | Weapons / camera features |
| 4 | `Atian Menu CW (4/4)` | root, scroll | `Vehicle`, `Map` |
| 5 | map list | `(4/4)` → `Map` → **R** | **19 maps.** No gametype control |

⚠ **Pages 1–3 are not transcribed.** They were reported as *"weapons and camera stuff"*, which is
enough to settle the gametype question but not enough to serve as a full index. If a future task
needs a specific weapon/camera capability, they still need a proper pass.

⚠ The upstream README's feature list (Tools / Give weapons / Gun tool / Teleport tool / Loading /
Customization / Internal tools) is written for the **BO4** build and did **not** match what page 4
showed. Do not read it as a CW inventory.

### The entries this project needed

| Target | Found? | Where | Notes |
|---|---|---|---|
| **Map change** | ✅ **works** | `(4/4)` → `Map` → **R** | **19 maps** — not limited to Gunfight's ten. Hijacked and Zoo (both 6v6 maps) are reachable |
| **Gametype / mode change** | ❌ **ABSENT** | — | No gametype control anywhere in the CW build |
| **Team size / max players** | ❌ ABSENT | — | Nothing team- or slot-related on any page |
| **Round timer** | ❌ ABSENT from this menu | — | And the stock rules-menu value does not survive a carry — see trap 2 |

⚠ The upstream README lists *"Set map/gametype"*, and the BO4 build documents a `Loading` section
containing both. **Neither is present in the Cold War build** — there is no `Loading` section at all,
and the map control ships alone. The README describes the tool across both games.

### Map identities — externally confirmed

Per this repo's dump-vs-external rule; the dump cannot resolve UI names to codenames.

| Map | What it is | Source |
|---|---|---|
| **Mansion** | stock BOCW **Gunfight 2v2** map | Call of Duty Wiki, GamesAtlas |
| **Hijacked** | **6v6**, BO2 remake, Season Four (17 June 2021). Not a Gunfight map | callofduty.com Tactical Map Intel |
| **Zoo** | **6v6**. Not one of the nine `mp_sm_*` | — |

---

## `gunfight_mod` — stage status, all verified

| Switch | State | Verified |
|---|---|---|
| `zones_guard` | ON | implicitly — nothing indexed `level.zones` undefined |
| `timelimit_fix` | ON | ✅ **a round ran to zero and ended cleanly** |
| `timer_override` | ON | ✅ 60s held across a map carry |
| `presentation` | ON | ✅ Gunfight HUD renders correctly |

### ✅✅ `timelimit_fix` — the first time that path has ever been exercised

**A round ran to zero and ended properly. No fault, no hang.** Every prior clean match ended by
**elimination** and never reached time expiry; both this note and
[`gunfight-findings.md`](gunfight-findings.md) had it flagged as open.

The failure it avoids is specific: on a zoneless map — which is *every* private Gunfight map,
`setupzones()` returns false, n=2 ICBM and Amsterdam — a round reaching expiry runs `ontimelimit()`
→ `overtime()` → `level.zones[0]` on an undefined array.

So `timelimit_fix` is no longer a reasoned-about safeguard. It is a measured one, and the switch
[`../src/README.md`](../../src/README.md) calls **LOAD-BEARING** has earned the label.

⚠ **Overtime is absent, and that is correct** — `timelimit_fix` deliberately skips the crashing
`overtime()` and lands on the health decision instead.

---

## Corrections — claims made and walked back

Recorded because this note has now been wrong twice in the same direction: too confident, too early.

**1 — "with no GSC, no DLL, and no injector."** This note's original headline. **Wrong.** The carry
was performed *by an injected GSC mod menu*, so it was entirely GSC and the injector. The menu is not
a property of the game; it is something we install, it does not survive a restart, and anyone
reproducing the carry must inject it first. The mechanism is still real and still closes the map goal
without `cwdllgt` — but it is not stock and not free.

**2 — "a Gunfight lobby on Hijacked is the inheritance case, and one probe run there is a cheap
Phase 1."** **Backwards.** `team-sizes.md` says to start in a twelve-slot lobby and *never be in a
Gunfight lobby at all*; the carry produces exactly the configuration it warns against. The slots are
fixed before the map switch can act.

**3 — "R remaps to map change"** (inherited from a session lost to a machine outage; only its
one-line state card survived). Right about the key, **wrong about the scope**. R is the menu's
**global select key** — `select_item`, i.e. `use` — and selects any entry anywhere. The map change
was simply the first thing selected with it. Read the original way, the next walker hunts a
dedicated map-change binding that does not exist and cannot select anything else.

---

## Untried — not ruled out

⚠ **Nothing below has been tested.** This section exists so that "we have not tried it" never gets
recorded as "it cannot be done." Ordered cheapest first.

**Larger teams**

1. **The glitched-lobby measurement.** Glitched Gunfight-on-a-6v6-map lobby + `mp_probe`, read
   `1xxxxx`. The glitch is a real playlist reconfiguration, which is the layer that sets
   `com_maxclients`. Needs the glitch to work once.
2. **Add the control ourselves.** The Atian Menu is **open-source GSC**, and we already compile and
   inject GSC. Its **BO4 build documents a `Loading` section with map *and* gametype** — the CW build
   ships the map half alone. Porting or reimplementing the gametype half is a code task on a public
   repo, not a reverse-engineering problem. **This is the largest untried avenue in the project.**
3. **Other lobby builders.** Only *Private Match* has been walked. `mp_custom_game.ddl` exists as a
   distinct settings struct — whether the **Custom Games** path builds lobbies differently is
   unchecked.
4. **Other stock playlists that build large lobbies**, entered first and then carried, on the
   `3v3 Gunfight` pattern that already works.
5. **Other Gunfight gametype strings.** `gunfight` and `gunfight_3v3` both exist in
   `player_record.gsc`'s switch. Whether the switch holds further variants is not enumerated.
6. **The ACTS exports directly.** `ACTS_EXPORT_SetLobbyGameType` / `SetLobbyMap` are ordinary
   exports; `cwdllgt`'s base-name lookup is what is blocked, not the exports.

**The menu itself**

7. **Pages 1–3.** Untranscribed — reported as weapons/camera.
8. **Host vs joiner.** Only ever opened in a single-player lobby.
9. **In-lobby vs in-match.** Only opened in-match.

⚠ Injecting begins host-side exposure — read [`tac-risk-model.md`](tac-risk-model.md) first.
