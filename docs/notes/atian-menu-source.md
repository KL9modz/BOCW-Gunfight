# Atian Menu source survey — the gametype switch already exists

**Source read 2026-09-08** against [`ate47/t8-atian-menu`](https://github.com/ate47/t8-atian-menu)
@ `f78bff6` (2025-05-15), cloned shallow. No game required for any of this.

---

## Headline: the capability the menu walk could not find is written, in the Cold War tree, unexposed

[`menu-map.md`](menu-map.md) records that walking all four pages of the CW Atian Menu found **no
gametype control**. That observation is correct. The conclusion it invites — that the tool cannot do
it — is not.

`coldwar/scripts/core_common/menu_funcs.gsc` defines **three** switch functions. The menu wires
exactly one of them.

| Function | Line | Sets | Wired into the CW menu? |
|---|---|---|---|
| `func_set_map( item, map_name )` | :357 | map only — **`map()` + `wait(1)` + `switchmap_switch()`** | ✅ **yes — 48 entries** |
| `func_set_mapgametype( item, map_name, gametype )` | :348 | **both** | ❌ **dead code** |
| `func_set_gametype( item, gametype )` | :365 | **gametype only, keeps the current map** | ❌ **dead code** |

⚠ **This row said "map only, via `map( map_name )`" until 2026-09-08, and that cost a live test.**
It is right about *what* the function sets and lossy about *how*: `map()` only **stages** the load and
**`switchmap_switch()` is what commits it**. `src/test_mapswitch/` was written from this summary,
called `map()` alone, and **nothing happened at all** — no load, no error. Verbatim:

```gsc
function func_set_map(item, map_name) {
    self menu_drawing_function("loading " + map_name);

    map(map_name);
    wait(1);
    switchmap_switch();
}
```

▶ **The lesson, and this project keeps relearning it: quote the source, never paraphrase a mechanism.**
`func_set_gametype` is quoted verbatim below precisely because its sequence matters — and so does this
one. A summary is fine for *what a thing does*; it is not fine for *how to call it*.

Verified: `grep -c 'func_set_mapgametype' coldwar/scripts/core_common/menu_items.gsc` → **0**, and
every one of the 48 map entries wires `&func_set_map`.

**The pattern is proven elsewhere in the same codebase.** The shared (BO4/Blackout) tree wires
`func_set_mapgametype` extensively — `scripts/core_common/ui/menu_items.gsc:367-392` builds whole
Warzone playlist submenus with it. So this is exercised code that the CW menu tree simply never
exposes.

`func_set_gametype` is the one this project wants, verbatim from source:

```gsc
function func_set_gametype(item, gametype) {
    map_name = util::get_map_name();
    self menu_drawing_function("loading mode " + gametype);

    switchmap_load(map_name, gametype);
    util::wait_network_frame(1);
    switchmap_switch();
}
```

## The builtins exist in the Cold War binary — confirmed from the author's own table

None of the `switchmap_*` names are defined anywhere in the menu repo, so they are engine builtins.
`docs/notes/funcs_cw.csv` is the author's **Cold War** function table and lists all four with
addresses:

| Builtin | args (min/max) | Address |
|---|---|---|
| `switchmap_preload` | 1 / 2 | `BlackOpsColdWar.exe+3b7c6e0` |
| `switchmap_load` | 1 / 2 | `BlackOpsColdWar.exe+3b7c710` |
| `switchmap_switch` | 0 / 0 | `BlackOpsColdWar.exe+3b7c780` |
| `switchmap_setloadingmovie` | 1 / 2 | `BlackOpsColdWar.exe+3b7c790` |

⚠ **`switchmap_load`'s gametype argument is OPTIONAL** (min 1, max 2). That the 2-arg form exists
does not prove the CW build honours the second argument. Untested.

The author's own description, `docs/mapgametypes.md`:

> `map(string map_name)` — it will set the map with the same gametype,
> but you can also use the switchmap functions, it will load the map with a particular gametype,
> **the wait is important, I don't know why.**

```c++
switchmap_load(string map, string gametype);
wait(1);
switchmap_switch();
```

⚠ **The sequencing is empirical, not understood** — by the author's own admission. Keep the wait.

## ⚠ `docs/mapgametypes.md` is a BLACK OPS 4 document. Its gametype list does NOT apply to CW.

It opens with *"[Black ops 4 (T8) information...]"* and lists BO4 maps (`mp_nuketown_4`,
`wz_open_skyscrapers`) and BO4 gametype strings (`tdm`, `sd`, `conf`, `koth`…). **Do not feed those
strings to a Cold War build.** Only the *mechanism* section transfers; the CW-specific evidence is
`funcs_cw.csv` and the `coldwar/` tree.

The CW gametype strings this project already knows, from the dump:
`gunfight` (enum `0x2f`) and `gunfight_3v3`, both in `mp_common/player/player_record.gsc`'s switch.

---

## What this makes testable — and it needs no menu fork

The mechanism is two builtins. `gunfight_mod` already compiles and injects; it does not need the
Atian Menu at all for this.

```gsc
switchmap_load( util::get_map_name(), "gunfight_3v3" );
wait( 1 );                  // load-bearing per the author; reason unknown
switchmap_switch();
```

**Run that from inside a private TDM lobby** — the one measured at **12 slots**
([`team-sizes.md`](team-sizes.md)) — and read `com_maxclients` with
[`../src/mp_probe/`](../../src/mp_probe/), probe `1xxxxx`.

| Reading | Means |
|---|---|
| `100012` | `switchmap_load` reconfigures the session, not just the map. **Larger-than-3v3 Gunfight, reached in script.** |
| `100008` | It re-derived the lobby from the gametype, same as the carry. Slots still fixed at creation |

### Why this is a different bet from the map carry

The carry is `map( map_name )` — the author says it *"will set the map with the same gametype"*, i.e.
a load-time map override that leaves the session alone. That is why
[`menu-map.md`](menu-map.md) finds the scoreboard still naming the old map, and why it cannot move
`com_maxclients`.

`switchmap_load` is a **different builtin taking a gametype**, running a preload → load → switch
sequence. Whether that reaches the playlist layer is exactly the open question — and it is the layer
`com_maxclients` is fixed at. **Unknown, not unlikely. Only a live test settles it.**

## Validate before injecting

`tools/check-gsc.ps1` stage 4 checks that every bare call exists in the dump. Run it on any script
using these four names before the game ever sees it — that is precisely the check that caught the
`logprint` failure (`src/README.md` → *What a harness PASS does and does not mean*).

⚠ A PASS still does not prove runtime behaviour. And ⚠ injecting begins host-side exposure —
[`tac-risk-model.md`](tac-risk-model.md).

## Other things the source settles

**The shipped menu binary is older than master.** The CW source wires **48** map entries (37 of them
`is_multiplayer()`); the walk observed **19** in-game. The injected asset is the `latest_build`
release `.gscc`, not a build of this tree. Either the release predates these entries or the in-game
count was of one page. **Worth re-counting on the next walk**, and worth knowing a source build would
offer more maps.

**The repo's default CW hook is the frontend, not MP.** `coldwar/gsc.conf` sets
`script=scripts\core_common\load_shared.gsc`, and `metadata.json` names the same hook. We inject the
release binary at `scripts\mp_common\bb.gsc` and it works — so the release is built differently from
the repo default, or the hook is not load-bearing for the menu. Not investigated.

**Building from source is possible but untried.** The tree is plain GSC with a `gsc.conf` per target,
which is the same shape as `src/*/gsc.conf` in this repo. ACTS compiles it. Nobody has tried.

## Untried from here

1. **The `switchmap_load` probe above.** Cheapest real test of larger teams the project has.
2. **`switchmap_preload`** — used by `func_set_mapgametype` but not by `func_set_gametype`. Purpose
   and whether it matters: unknown.
3. **`switchmap_setloadingmovie`** — exists, undocumented, unexamined.
4. **A source build of the menu**, which would expose the 48-map list and let the dead
   `func_set_gametype` be wired into the tree directly.
