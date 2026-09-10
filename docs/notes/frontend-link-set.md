# What the FRONTEND actually links — and how CW's script VMs are laid out

Written 2026-09-10 after four launches were spent guessing at a client-side replace target. klaze:
*"it is good to know how the entire game works anyway as i plan to expand the mod."*

## The model: four VMs, two script kinds

| | `.gsc` — SERVER | `.csc` — CLIENT |
|---|---|---|
| what it is | game logic, authoritative | presentation: HUD, LUI, FX, audio |
| in a match | ✅ runs | ✅ runs |
| in the pregame lobby | ✅ **runs** (P1: probe 51 = 63) | 🪦 **injected ones do NOT** (P6b) |
| owns UI models | 🪦 no (P6a) | ✅ yes — 31 `.csc` files call `getuimodel` vs 5 `.gsc` |

▶ **The trap this project fell into:** the layer that owns the map picker (UI models) is client-side,
and the VM we can reliably inject into in the lobby is server-side. Neither half alone is enough.

## Linkage is the `#using` graph — that is what decides what loads

A script is in a VM if something in that VM's tree `#using`s it. So the frontend's client link set is
the transitive closure from `scripts/core/gametypes/frontend.csc`.

**Computed: 46 scripts.** `frontend.csc` `#using`s 22 directly:

```
core_common: activecamo_shared · activecamo_shared_util · animation_shared · array_shared
             audio_shared · battlechatter · callbacks_shared · character_customization
             clientfield_shared · custom_class · exploder_shared · flag_shared · math_shared
             postfx_shared · scene_shared · struct · util_shared · weapon_customization_icon
mp_common:   devgui
hashed:      script_209c9c119ef6fc06 · script_53cd49b939f89fd7 · script_7ca3324ffa5389e4
```

⚠ **Every named one has real content** — smallest in the whole 46 is `weapons/weapon_utils` at 1,228
bytes. **There is no empty script in the frontend link set**, which is the tension that killed the
previous attempt: the 0-byte `.csc` files (`radiation_debug`, `placeables`, `item_world_cleanup`,
`traps_deployable`, `challenges_shared`, `string_shared`) are safe to overwrite *because nothing
references them* — and that same property means the frontend never loads them, so a payload placed
there has nowhere to run. **Empty and linked were mutually exclusive.**

## 🔓 The candidate: `script_7ca3324ffa5389e4`

The one script that satisfies both halves:

| Property | Evidence |
|---|---|
| **Linked in the frontend** | `scripts/core/gametypes/frontend.csc` `#using`s it directly |
| **Empty as a client script** | the dump has `hashed/script/script_7ca3324ffa5389e4.gsc` (4,490 B) and **no `.csc` at all** |
| Also referenced by | `core_common/player/player_free_fall.csc` |

▶ So its **`.gsc`** side is real code, while its **`.csc`** side appears to be an empty stub that
`frontend.csc` nonetheless pulls in. That is exactly "referenced but nothing to lose".

⚠ **Not certain, and the uncertainty is nameable:** the dump may simply be missing that `.csc` rather
than it being empty. The cheap discriminator is that `injectcw` will refuse a replace target that is
not in the scriptparsetree pool — *"Can't find target script"* is a harmless failure.
⚠ **`scene_model_shared` remains the warning**: it looked free and the frontend needed a class it
declared. A script `frontend.csc` explicitly `#using`s is more entangled than one nothing references,
so **test a lobby return** before trusting it.

▶ Second candidate if that fails: `script_612bbf55ca35e077` — same shape (`.gsc` only, no `.csc`) but
**no traceable referrer** in `scripts/`, so its linkage is unproven.

## Where this leaves the map goal

The remaining unknown is narrow and specific: **does an injected client payload run in the frontend VM
when its replace target is one the frontend actually links?** P6b showed it does not with an unlinked
target. That is one testable question, not a search.
