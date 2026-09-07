# MP load path — getting injected GSC to run in the Gunfight VM

**Conclusion.** The MP bootstrap is **solved** — mechanism, hook point, and dispatch ordering all
verified from source and toolchain docs. Inject with the `dev_csc_inj` injector set to `mode=mp`,
`script=scripts\mp_common\bb.gsc` (the injector's own documented MP hook). Your injected script's
`autoexec` runs on load, registers `callback::on_start_gametype(&apply)`, and `apply()` reassigns
`level.ontimelimit` — which lands at `globallogic.gsc:5536`, **before** gunfight's `onstartgametype`
(`:5537`) and the timer loop (`:5539`). The additive `autoexec`+`callback` model is not a hope: stock
`bb.gsc` uses it and the toolchain's own T9 example uses it (see [[pipeline-toolchain-survey]]). What
remains is a one-line hello-world to confirm the hook fires in a **custom Gunfight** lobby specifically.

⚠ Line numbers: game refs against `ate47/bocw-source` @ `edd94bd`; toolchain refs against
`AuroraDoesCode/t7-compiler-custom` `dev_csc_inj` @ `4de00c8`. Quote surrounding code if a dump moved.

---

## Why this is a bootstrap problem, not a rewrite problem

The fix reassigns one function pointer:

```
level.ontimelimit = &my_health_decision;   // -> function_c4915ac()
```

Stock installs that pointer at `scripts/mp_common/gametypes/gunfight.gsc:58`, inside
`function event_handler[gametype_init] main( *eventstruct )` (`:39`). So the whole MP question is: get
*some* injected function to run in the MP VM, at a point where it can overwrite `level.ontimelimit`
before the timer fires. No stock file is touched.

## The registration model — CONFIRMED additive

Two compile-time attributes and one runtime call, all additive:

| Mechanism | How it fires | Evidence @ `edd94bd` |
|---|---|---|
| `function autoexec f()` | runs automatically when the **script is loaded** into the VM | `scripts/mp_common/bb.gsc:12` (the MP hook) and `load.gsc:28`; the attribute appears on 12+ functions across `scripts/mp_common/` |
| `function event_handler[E] f(*es)` | runs when event **E** fires; registered at link time | every MP gametype uses `event_handler[gametype_init] main` — `gunfight.gsc:39`, `dm.gsc:22`, `war.gsc:9`, `dom.gsc:30`, … |
| `callback::on_start_gametype( &f )` | runtime registration; fires at `globallogic.gsc:5536` | the slot the mod uses; `bb.gsc:24` registers `on_spawned` the same way |

**Why "additive" is the load-bearing word.** The event dispatcher reads a *list* and iterates it —
`scripts/core_common/callbacks_shared.gsc` (~`:35`):

```
callbacks = ent._callbacks[ event ];
if ( isdefined( callbacks ) )
    for (i = 0; i < callbacks.size; i++) { ... call callbacks[i] ... }
```

Firing an event calls **every** handler registered for it, not one. An injected handler is simply one
more entry in that list. This is the same mechanism stock uses to let many systems hook one lifecycle
event, so injected code is not doing anything the engine does not already do to itself.

## Injector config — how the buffer reaches the MP VM

The `dev_csc_inj` injector **hooks a stock script** named in `gsc.conf` (it does not overwrite it): when
the hooked stock function runs, the injected script's linked functions run too. `mode=` selects the VM.
For this mod:

```
game=T9
mode=mp
script=scripts\mp_common\bb.gsc     # the injector's documented MP hook point
```

`bb.gsc` is a stock MP-common script present in every MP match (verified `bocw-source@edd94bd`,
`scripts/mp_common/bb.gsc:12` `autoexec __init__system__` → `system::register(#"bb", &preinit, ...)`),
so it runs in a custom Gunfight lobby. ZM uses `zm_common/load.gsc`; Frontend uses
`core_common/load_shared.gsc` — recorded so nobody re-hunts them. Source: `t7-compiler-custom`
`dev_csc_inj@4de00c8`, `Default Project/T9/gsc.conf`.

## Recommended shape — additive, no detour

Mirror the toolchain's own T9 example (`Default Project/T9/scripts/headers.gsc`) and stock `bb.gsc`:

```
// injected into the MP VM, script hooks scripts\mp_common\bb.gsc
autoexec mod_boot()
{
    system::register( #"gunfight_mod", &mod_init, undefined, undefined, undefined );
}

mod_init()
{
    callback::on_start_gametype( &mod_apply );   // additive, alongside stock
}

mod_apply()
{
    // fires at globallogic.gsc:5536 — BEFORE gunfight onstartgametype (:5537) and the timer loop (:5539)
    level.ontimelimit = &my_health_decision;     // overwrites stock's gunfight.gsc:58 -> function_c4915ac()
    // zones guard + latch flags + world uimodel sets per CLAUDE.md's fixup shape
}
```

⚠ **Why `on_start_gametype` is the right slot — verified ordering.** `globallogic.gsc`
`callback_startgametype()` runs, in order:

```
5536:  callback::callback( #"on_start_gametype" );   // <- mod_apply() fires here
5537:  [[ level.onstartgametype ]]();                 // <- gunfight zone setup / early return runs AFTER us
5539:  level thread updategametypedvars();            // <- timer loop (checktimelimit) starts LATER
```

`gametype_init` (which sets `level.ontimelimit` at `gunfight.gsc:58`) runs earlier still, so at `:5536`
the stock pointer is already installed and we cleanly overwrite it — with the timer loop not yet
started. The latch flags likewise: gunfight's early-return at `:5537` *skips* setting them, so anything
we set at `:5536` survives untouched.

Per-round re-entry (round-2+ music) hangs off the round-start path, not `on_start_gametype` (once per
match) — pin the exact round notify in Phase 3 against `scripts/mp_common/gametypes/round.gsc`. The
pointer reassignment is match-level and only needs to happen once.

## Fallback

If a hello-world shows the `bb.gsc` hook does **not** fire in a custom Gunfight lobby (it should — it is
MP-common), fall back to a `replacefunc` detour on `gunfight::main` or `onstartgametype`, re-invoking the
stock body. A detour is a hook, which is the R2 vector in [[tac-risk-model]], so prefer the additive
`bb.gsc` path.

## Hello-world — now a confirmation, not an exploration

The mechanism is verified from source and toolchain docs; the hello-world only confirms the hook fires
in a **custom Gunfight** lobby and checks timing.

1. **hook fires?** Compile with `mode=mp`, `script=scripts\mp_common\bb.gsc`, injected content
   `autoexec f(){ logprint( "MODLOADED mp bb\n" ); }`. Start a Gunfight custom match. String in the
   console log → hook confirmed.
2. **callback fires?** Add `system::register` → `callback::on_start_gametype(&g)`, `g` logging. String
   at gametype start → path confirmed.
3. **pointer reassignable?** In `g`, log `isdefined( level.ontimelimit )`, reassign to a stub, confirm
   the stub runs when the timer expires on a stock map.

**Records to keep** (this becomes the finding when filled):

- Injector build / `dev_csc_inj` commit: `_____`  · Game build / patch: `_____`
- `bb.gsc` hook fired in custom Gunfight: yes / no
- `on_start_gametype` callback fired: yes / no — earliest point the string appeared: `_____`
- `level.ontimelimit` reassignment took effect at timer expiry: yes / no
- Fell back to `replacefunc`: yes / no

## Resolved vs. still-open

**Resolved** (game `edd94bd`, toolchain `4de00c8`):
- MP hook point = `scripts\mp_common\bb.gsc`, `mode=mp` — the injector's documented MP injection point.
- Injector hooks (not overwrites) the named stock script; injected `autoexec` then runs on load.
- Load model = `autoexec` → `system::register` → `callback::on_start_gametype` — used by both stock
  `bb.gsc` and the toolchain's own example, so honoring injected `autoexec` is the documented contract.
- Dispatch ordering verified: `mod_apply` at `globallogic.gsc:5536`, before `onstartgametype` (`:5537`)
  and the timer loop (`:5539`); pointer install (`gunfight.gsc:58`) is earlier still.

**Still open (small):**
- Empirical: does the `bb.gsc` hook fire in a *custom Gunfight* lobby, and with what timing → hello-world.
- CSC (client script): none of the fix needs it — pointer and health decision are server/game-VM. Do not
  spend time on a `.csc` bootstrap.

## Exposure

The additive `bb.gsc` path installs **no hook** in the injected script itself, avoiding the R2 (API-hook)
vector in [[tac-risk-model]] that a `replacefunc` fallback would sit in. Injection itself (R1, R3) still
applies and is host-only. Read [[tac-risk-model]] before injecting on any account you are not prepared to
lose.
