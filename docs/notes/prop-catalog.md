# Prop catalog + explosive barrels — full list in the app, favourites in the menu. 2026-09-20

klaze, 2026-09-20: *"since it might be much for the in game menu, lets keep the full list in the new
c# app... and maybe the app can let me choose favorites for the menu?"*

So: the **app (tools/gf-panel)** browses the WHOLE catalog and spawns any of it; the **in-game menu**
shows only a favourites subset the app chooses. This note is the contract between the two.

> **2026-09-25:** klaze removed 58 props by their Forge counter numbers (lids, wheels, parts, decals, test
> models). `tools/props-gen.py` now has `EXCLUDE_MODELS`, which drops them by NAME so a later regeneration
> can't drop the wrong ones. The universal list went 423 → 365, and every later index shifted. The panel
> embeds `map-props.json`, so it was republished with the new build. The counts below are the older state.

## The catalog — `docs/data/map-props.json` (generated, READ-ONLY)

`tools/props-gen.py` reads the T9 dump's per-zone manifests (`tables/data/assets/<zone>.csv`,
`type == xmodel`, prop families `p9_/p8_/p7_`) and writes:

```json
{
  "generated": "2026-09-20",
  "universal_count": 546,
  "universal": [ { "i": 0, "model": "p7_bag_cement_stacked_01", "label": "Bag cement stacked 01", "barrel": false }, ... ],
  "maps": { "mp_miami": [ { "model": "...", "label": "...", "barrel": false }, ... ], ... }
}
```

- **`universal`** — 546 props resident on EVERY MP map (core_bootstrap + core_common + mp_common):
  338 `p9_` + 141 `p8_` + 67 `p7_`. `i` is the **stable index** = the GSC `prop_master()` index =
  the `cmd_propidx` argument. Order = model name sorted; regenerating keeps it stable unless the dump
  changes.
- **`maps`** — each map's OWN props (its zone minus the universal set), 43 maps, ~1,000–2,200 each
  (Miami 2229, Cartel 1361). No index — per-map models are spawned by NAME (`cmd_propname`), because
  embedding 43k model strings in the GSC is not worth it and the app already has them here.
- **`barrel: true`** — a drum / jerrycan / fuel can that reads as an explosive barrel (17 universal,
  incl. the real red one `p7_zm_nac_barrel_explosive_red`). Spawn these via the barrel verbs to get
  the explosion behaviour; spawn them via the plain prop verbs to get an inert prop.

Every spawn is still `isassetloaded( "xmodel", model )`-gated host-side, so a model that a given map
does not actually carry just reports "not resident" instead of spawning nothing.

## Bridge verbs (app → GSC, via `gf_cmd_action` + args)

All are dispatched in `cmd_action()`. Confirmation comes back on `menu_say` (GFSTATE `say=`).

| verb | arg(s) | does |
|---|---|---|
| `propidx` | `gf_cmd_arg` = universal index `0..545` | spawn `prop_master()[i]` as a plain prop |
| `barrelidx` | `gf_cmd_arg` = universal index | spawn `prop_master()[i]` as an **explosive barrel** |
| `propname` | `gf_pn0`(+`gf_pn1`+`gf_pn2`), `gf_cmd_arg` = scale×100 or 0 | spawn an arbitrary model by name (per-map) as a plain prop |
| `barrelname` | same as propname | spawn an arbitrary model by name as an **explosive barrel** |
| `propfavs` | `gf_prop_favs`(+`gf_prop_favs2`) = CSV of universal indices | set the in-game menu's favourites |
| `propundo` | — | delete the last prop/barrel this menu placed |
| `propclear` | — | delete every prop/barrel this menu placed |

### The chunked-name protocol (beats the 47-byte bridge slot — bridge-command-limit.md)

A model name like `p9_ger_tank_computer_server_diagnostic_01_silver_prophunt` (57 chars) does not fit
one `set` command (`set gf_cmd_arg …` overflows at 47 bytes and HARD-crashes the game). So `propname`
/ `barrelname` read the name from up to three small dvars the app sets first, each ≤ 36 chars
UNQUOTED (`set gf_pn0 <=36chars` = 47 bytes exactly):

```
set gf_pn0 p9_ger_tank_computer_server_diagnos     # chunk 0 (<=36)
set gf_pn1 tic_01_silver_prophunt                  # chunk 1 (<=36, omit if not needed)
set gf_pn2                                          # chunk 2 (usually empty)
set gf_cmd_arg 0                                    # scale*100, 0 or "" => scale 1  (e.g. 150 => 1.5x)
set gf_cmd_action propname
```

GSC concatenates `gf_pn0 . gf_pn1 . gf_pn2`, clears them, isassetloaded-gates, spawns. Send one `set`
per bridge message ~0.08 s apart (app-bridge-multiline-fix.md: a loaded gf_bridge.dll runs only the
first line of a multi-line message).

For the **universal** tab the app should prefer `propidx`/`barrelidx` (one command, no chunking) —
chunking is only for the per-map models that have no GSC index.

### Favourites → the in-game menu

The app persists the user's favourites (its own config) and pushes them as a CSV of universal indices:

```
set gf_prop_favs 12,45,88,133,201,225,296,317      # <=47 bytes; split the rest into gf_prop_favs2
set gf_prop_favs2 340,355,356,403,476,485
set gf_cmd_action propfavs                          # (optional; the menu also reads the dvars live on open)
```

The in-game menu's **Props → Favourites** page renders `prop_master()[i]` for each favourite index
that is resident on the current map. With no favourites set it falls back to the built-in curated
scenery slice (the ~49 hand-labelled props). Barrels favourited (or any `barrel:true` index) render
on **Props → Barrels** as explosive spawns.

Favourites are host dvars read at page-build, so the app only needs to have set them before the host
opens the props page; they survive until the game restarts. (A later pass can fold `gf_prop_favs`
into config_publish/readback so the app's "Load current" shows them.)

## Explosive barrels — the mechanism (from cp_explosive_barrel.gsc)

`act_barrel_spawn()` = the plain prop spawn (`act_prop_spawn`) plus the campaign barrel's core recipe
(`cp_common/cp_explosive_barrel.gsc`), MP-portable because the blast is pure server-side:

1. `setcandamage( 1 )`, tag `gf_prop` (so undo/clear and the round-boundary sweep pick it up).
2. Thread: `waittill( #"damage" )`; on a bullet/explosive hit, chip the health, then when it dies:
   - `physicsexplosionsphere( origin+(0,0,50), R, r, force )` — throws nearby physics props/players.
   - `radiusdamage( origin+(0,0,25), R, maxdmg, mindmg, self, "MOD_EXPLOSIVE" )` — hurts players.
   - `playfx` a standard explosion effect at the origin (stock `barrel_effects` clientfield FX is a
     CP-only registration and re-registering clientfields mid-match is the LUI-crash risk, so we use
     a plain fx instead), then swap to a `_dmg_0N`/charred model if resident, else delete.
3. Defaults tuned from the stock barrel: radius ≈ 260, force ≈ 200, damage 25–200. A `gf_barrel_dmg`
   dvar can scale it later.

Joiner-safe: the model replicates as an ordinary entity and the explosion is server-authoritative, so
a vanilla client sees the barrel and takes the blast (same reasoning as static-props.md §4, Gate 2
does not apply — no clientfield gates the prop).

## Destructibles — NOT spawnable, already handled

`destructible` is not a spawnable asset (0 rows in any manifest); they are map-authored Radiant
entities. The menu's **Destructibles** page already enumerates the map's own (`getentarray
"destructible"`) and breaks them via `dodamage` (break-aimed / near / all — `destruct_enter`). Nothing
to add there; "spawn a destructible" is answered by the explosive barrel above.

## GSC pieces (added to gunfight_menu.gsc)

New (all in the props region ~14331–14637, no conflict with the dispatch functions):
`pm()` helper, `prop_master()` (GENERATED between `// [props-gen BEGIN]/END`), `prop_favs()`,
`act_barrel_spawn()` + `barrel_think()`, `cmd_propidx/cmd_propname/cmd_barrelidx/cmd_barrelname`,
`prop_favs_set()`; `props_univ_enter` → renders favourites; `props_enter` → add a **Barrels** row.

Dispatch registrations (MUST wait for a clean tree — a peer's 815-line WIP sits in these):
`cmd_poll()` reads `gf_pn0/1/2`; `cmd_action()` adds the 6 cases above.

## Forge + hint verbs (2026-09-20, docs/notes/forge.md)

| verb | arg(s) | does |
|---|---|---|
| `forge` | `enter`/`exit`/`place`/`next`/`prev`/`clear` | in-game Forge build mode (preview rides the view) |
| `hintset` | `others` or `build`; text in `gf_ho0`(+`gf_ho1`+`gf_ho2`) | set the others-facing welcome line / the build warning (chunked, ≤36 chars each) |

Dvars the app can set directly (int) or via chunked strings: `gf_hint_others_on` (0/1, show the
others line), `gf_hint_glyphs` (0/1, try device bind-glyphs in hints — UNMEASURED), `gf_hint_nav`
(the menu controls legend). The others-line default is the discord welcome; while the host is in
Forge it shows `gf_hint_build` ("DO NOT KILL - host is building") to everyone but the host.

App UI to wire (phase 1): a Forge section — Enter/Exit, Place, Next/Prev model, Clear layout; and a
Hint section — edit the welcome line + build warning (send chunked), toggle gf_hint_others_on, the
nav legend, and a gf_hint_glyphs test switch. Phase 2 (not built): select/nudge/rotate/scale/delete a
placed prop by index, and save/load/share a per-map layout (read game.gf_forge).

## Regenerate

```
python tools/props-gen.py            # rewrites docs/data/map-props.json + the prop_master() block
python tools/props-gen.py --check    # CI: exit 1 if stale
```
