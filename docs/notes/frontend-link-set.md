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

## 🪦 `script_7ca3324ffa5389e4` — CRASHED. And it exposes the real bind.

2026-09-10. `injectcw` **accepted** it as a replace target, which settles one thing: it is a real
client script in the pool, so the dump was missing its `.csc` rather than the game lacking one.

Then the game **crashed**. `frontend.csc` `#using`s it and evidently needs it — `scene_model_shared`
again, in a new place.

### ▶ The bind, stated plainly

| | linked in the frontend? | safe to overwrite? |
|---|---|---|
| the six 0-byte `.csc` files | 🪦 **no** — nothing references them, which is *why* they are empty | ✅ yes |
| every named script in the 46 | ✅ yes | 🪦 **no** — referenced means needed |

**Those are two ends of the same property.** A script is loaded because something references it, and
anything referenced may be depended on. Guessing inside this set is not a search with a good ending.

### 🔓 The escape: LINKED but FUNCTIONALLY DEAD — `mp_common/devgui.csc`

One script in the direct `#using` list is loaded by the frontend and does essentially nothing in
retail:

- **448 lines, 96 dev strings** — nearly all of it inside `/# … #/`, stripped from retail.
- Its **entire retail body** is one statement:
  `preinit() { level.var_f9f04b00 = debug_center_screen::register(); }`
- **Nothing in retail reads `var_f9f04b00`.** The only readers are `devgui.gsc:1125` and `:1127`,
  both inside dev blocks.

▶ So overwriting it costs one variable that no shipping code touches, while keeping the property that
made it a candidate: **`frontend.csc` `#using`s it**, so it is in the frontend VM's link set.

⚠ Not risk-free. It still calls `debug_center_screen::register()` at preinit, and the LUI element that
returns may be expected to exist by something not visible in the dump. **Test a lobby return.**
⚠ If this one also crashes, the honest conclusion is that the frontend link set has no expendable
member, and the client-side route needs a different mechanism entirely — not another target.

## 🪦 CLOSED — injected client scripts DO NOT execute in the frontend VM

2026-09-10, third and final replace target. `mp_common/devgui.csc`: linked by `frontend.csc`,
functionally dead in retail, **did not crash** — and **P = 0**. Our code still never ran.

| Replace target | Linked in frontend? | Expendable? | Result |
|---|---|---|---|
| `radiation_debug.csc` (0 bytes) | 🪦 no | ✅ yes | P = 0, no crash |
| `script_7ca3324ffa5389e4` | ✅ yes | 🪦 no | 💥 **crash** |
| `mp_common/devgui.csc` | ✅ yes | ✅ yes | **P = 0**, no crash |

▶ **The third row is decisive.** It satisfies both conditions the first two failed, and the payload
still did not run. **So linkage of the replace target was never the blocker**, and the model that
drove three launches was wrong. Whatever stops an injected `.csc` executing in the frontend is
upstream of which script it displaces — the hook mechanism, the pool the frontend loads from, or
autoexec dispatch in that VM.

⚠ **Recorded as measured, not as impossible.** Three targets and two hooks (`load_shared.csc`,
`frontend.csc`) is enough to stop guessing; it is not enough to prove no route exists. What is
established is narrow and solid: **this technique, as this project can currently apply it, does not
reach the frontend VM.**

### ✅ What this run banked anyway

🔓 **`mp_common/devgui.csc` is a PROVEN-SAFE client replace target.** It took the replace, the game did
not crash, and the lobby returned cleanly. That is the client-side counterpart to
`clientids_shared.gsc` — which this project spent months without — and it is the thing any future
`.csc` work should use.
⚠ Its one retail effect is `level.var_f9f04b00 = debug_center_screen::register()`, read only from dev
blocks. Losing it costs nothing shipping code touches.

### Untried — not ruled out

- **Whether ANY injected script runs in the frontend client VM**, by any hook. Every attempt used
  `injectcw`'s hook+replace model; a different injection method was never tried.
- **The frontend's own `.gsc` side is NOT affected** — P1/P2/P3 prove server payloads run and write
  there. Only the CLIENT half is closed.
- **LUI models from the match VM.** Untested: the client payload demonstrably runs in the MATCH, and
  nobody has asked whether `lobby_root` resolves there — the assumption that it is lobby-only was
  never checked, and P6a's server-side zero does not settle a client-side question.

### ▶ NEXT PROBE — does `lobby_root` resolve from the MATCH client VM?

Never asked. The assumption that the model tree is lobby-only was inherited, not measured, and the
only zero we have for it came from the **server** VM (P6a), which cannot settle a client-side
question.

**All three pieces are already proven**, so this costs one launch and no new code:

| | |
|---|---|
| hook | `scripts\core_common\load_shared.csc` — runs in the MATCH client VM (prints were seen) |
| replace | `scripts\mp_common\devgui.csc` — proven safe this session |
| payload | `src/test_uimodel_c/` unchanged; it prints `99 P T R LL` directly, no stash needed |

Expect `P ≥ 1` and `T ≥ 1` (it runs there). **`R` and `LL` are the finding**: if the roots resolve in
the match client VM, the UI model API is reachable from a VM we can already inject into — and the
question becomes whether a model written there survives back to the lobby, not whether we can touch
models at all.

## ⚠ Match-VM probe CRASHED — and the cause is ambiguous between two things

2026-09-10. `load_shared.csc` (hook) + `devgui.csc` (replace) + the model payload → **crash**.

**Two candidates, and the run cannot distinguish them:**

1. **`devgui.csc` is safe in the FRONTEND but not in the MATCH VM.** `mp_common/devgui` is a match
   script. In the previous run the payload never executed (P = 0), so devgui's *absence* was the only
   effect and nothing exercised whatever depends on it. This run put the payload in the match VM,
   where devgui normally lives.
2. **The model calls crash in the match VM.** `function_5f72e972()` / `getuimodel()` on a root that
   does not exist there, behaving like `openfile` did earlier tonight — **fatal rather than
   returning undefined**. That failure mode is now measured precedent in this game, not speculation.

⚠ **Do not record either as the cause.** One launch, one variable:

▶ **The disambiguating test: inject the payload with the model calls REMOVED** (leave only the tick
counter and the print), same hook, same replace.
  - still crashes → **`devgui.csc` is an unsafe replace in the match VM**, and hypothesis 1 holds.
  - runs fine → the replace is innocent and **the model calls are fatal there**, hypothesis 2.

⚠ That also matters beyond this route: `devgui.csc` was recorded earlier tonight as a proven-safe
client replace target on the strength of a run where the payload never ran. **That claim is now
provisional** — it is proven safe only for the frontend hook, and only in the case where nothing
executed. Downgraded accordingly.
