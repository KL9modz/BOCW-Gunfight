# MP load path — getting injected GSC to run in the Gunfight VM

**Conclusion.** The MP bootstrap is a *solved architecture problem* and a *single open injector question*.
The game exposes an **additive event/registration system**: functions tagged `autoexec` run when their
script loads, functions tagged `event_handler[gametype_init]` run when that event fires, and both feed
handler *lists* that the dispatcher iterates — so injected code can register **alongside** stock with
**no detour and no `replacefunc`**. The only thing not answerable from source is whether the
`dev_csc_inj` injector loads a buffer such that its `autoexec` / `event_handler` registrations are
honored by the VM. That is the one thing the hello-world tests. Everything else below is confirmed
against `ate47/bocw-source` @ `edd94bd`.

⚠ Line numbers are against dump revision **`edd94bd`**. Quote the surrounding code, not just the line,
if the dump has moved.

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
| `function autoexec f()` | runs automatically when the **script is loaded** into the VM | `scripts/mp_common/load.gsc:28` `function autoexec function_aeb1baea()`; the attribute appears on 12+ functions across `scripts/mp_common/` |
| `function event_handler[E] f(*es)` | runs when event **E** fires; registered at link time | every MP gametype uses `event_handler[gametype_init] main` — `gunfight.gsc:39`, `dm.gsc:22`, `war.gsc:9`, `dom.gsc:30`, … |
| `callback::on_game_playing( &f )` | runtime registration; fires at match "playing" transition | `gunfight.gsc:71` (stock registers its own `&ongameplaying` this way) |

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

## Recommended shape — additive, no detour

```
// injected into the MP VM
function autoexec mod_boot()
{
    callback::on_game_playing( &mod_apply );   // additive: runs alongside stock ongameplaying
}

function mod_apply()
{
    // runs AFTER gametype_init, so stock's gunfight.gsc:58 assignment is already in place
    level.ontimelimit = &my_health_decision;   // our value overwrites stock's -> function_c4915ac()
    // zones guard + latch flags + world uimodel sets per CLAUDE.md's fixup shape
}
```

⚠ **Do not reassign at `gametype_init`.** Stock sets `level.ontimelimit` there (`:58`); a second
`event_handler[gametype_init]` has **no guaranteed ordering** against stock's, so it may run *before*
stock and get overwritten. `on_game_playing` fires strictly after `gametype_init` and long before the
40s timer expires, so reassigning there wins deterministically. This ordering point is the one real
subtlety in the whole path.

Per-round re-entry (round-2+ music, the latch flags) hangs off the round-start path, not
`on_game_playing` (which fires once per match) — pin the exact round notify in Phase 3 against
`scripts/mp_common/gametypes/round.gsc`. The pointer reassignment itself is match-level and only needs
to happen once.

## Candidate ranking — resolved

| # | Candidate | Status |
|---|---|---|
| 1 | `scripts/mp_common/load.gsc` exists | **CONFIRMED PRESENT** (3016 B). But it is not a callable `load::main()` — it is `autoexec`-driven. The takeaway is the **`autoexec` mechanism**, not a call target |
| — | **injected `autoexec` + `callback::on_game_playing`** | **RECOMMENDED.** Additive, no detour, deterministic ordering. Lowest detection surface — see below |
| 2 | `replacefunc` detour on `onstartgametype` / `main` | **FALLBACK ONLY.** Use only if the injector does not honor injected `autoexec`/`event_handler`. A detour is a hook, which is exactly what TAC flags (R2 in [[tac-risk-model]]) — prefer additive registration |
| 3–4 | earlier core-init detour / bare level-notify | **DROPPED.** Subsumed by the additive model; no longer needed |

The old candidate list assumed we might have to seize a call site. We don't — the engine hands us a
registration slot.

## The one unknown, precisely scoped

**Does `dev_csc_inj` load an injected buffer so the VM honors its `autoexec` / `event_handler` /
`callback::` registrations?** This is a property of the *injector runtime*, not the game source, so it
cannot be read out of `bocw-source`. Two outcomes:

- **Honored** → the recommended additive shape works as written. Done.
- **Not honored** (injector only executes an entrypoint it calls directly) → fall back to a
  `replacefunc` detour on `gunfight::main` or `onstartgametype`, re-invoking the stock body, and accept
  the added hook-detection surface.

## Hello-world — the test that settles it

Cheapest first:

1. **autoexec fires?** Inject a script whose only content is
   `function autoexec f(){ logprint( "MODLOADED mp autoexec\n" ); }`. Start a Gunfight custom match.
   String in the console log → autoexec is honored, and the recommended shape is unblocked.
2. **runtime callback fires?** Add `callback::on_game_playing( &g )` inside `f`, with `g` logging.
   String at match start → `on_game_playing` path confirmed.
3. **pointer reassignable?** In `g`, log `isdefined( level.ontimelimit )`, reassign it to a stub, and
   confirm the stub runs when the timer expires on a stock map.

If step 1 is silent, skip to the `replacefunc` fallback and hello-world *that* instead.

**Records to keep** (this becomes the finding when filled):

- Injector build / `dev_csc_inj` commit: `_____`
- Game build / patch: `_____`
- autoexec honored: yes / no
- `on_game_playing` fired: yes / no — earliest point the string appeared: `_____`
- `level.ontimelimit` reassignment took effect at timer expiry: yes / no
- Fell back to `replacefunc`: yes / no

## Resolved vs. still-open

**Resolved against `edd94bd`:**
- `mp_common/load.gsc` exists — yes.
- The MP gametype entry is `event_handler[gametype_init] main`, pointers installed at `gunfight.gsc:53–59`.
- Event dispatch is additive (`callbacks_shared.gsc` iterates `ent._callbacks[event]`).
- A runtime hook (`on_game_playing`) is available and used by stock (`gunfight.gsc:71`).

**Still open:**
- Injector honors injected registration? → hello-world, above. **The only blocker.**
- CSC (client script): none of the fix needs it — the pointer and the health decision are all
  server/game-VM. Do not spend time on a `.csc` bootstrap.

## Exposure

The additive approach installs **no hook**, so it avoids the R2 (API-hook) vector in [[tac-risk-model]]
that a `replacefunc` detour would sit in. Injection itself (R1, R3) still applies and is host-only. Read
[[tac-risk-model]] before injecting on any account you are not prepared to lose.
