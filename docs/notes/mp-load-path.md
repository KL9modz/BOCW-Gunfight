# MP load path — getting injected GSC to run in the Gunfight VM

**Conclusion.** The mod does not need to hook a specific "load" script. It needs any code running in
the **MP** script VM at or after `gunfight.gsc` `onstartgametype()` has installed its `level.on*`
function pointers, at which point it reassigns `level.ontimelimit`. The open problem is purely
*bootstrap*: every public T9 workflow threads user code from `scripts/zm_common/load.gsc`, which the
**Zombies** engine calls — and there is no published equivalent for MP. This note ranks the MP
bootstrap candidates and gives the hello-world that decides between them.

⚠ **Confidence.** The injection *mechanism* below is established across the Treyarch GSC stack
(T7/T8/T9). The specific MP *entry point* is the undocumented part and is marked
**[VALIDATE]** wherever it is hypothesis. Nothing here is confirmed against a running game yet; that is
what Phase 3's hello-world is for. Do not treat [VALIDATE] items as facts.

---

## Why this is a bootstrap problem, not a rewrite problem

The gametype installs its round hooks as **function pointers** on `level`
(`gunfight.gsc:58`, per `.claude/CLAUDE.md`). The fix reassigns one of them:

```
level.ontimelimit = &my_health_decision;   // -> function_c4915ac()
```

Reassigning a pointer requires only that *some* injected function execute in the same VM, after
`onstartgametype()` ran. So the whole MP question collapses to two requirements:

1. **Reach.** The injector gets a buffer of compiled GSC linked into the **MP** VM (not the ZM VM).
2. **Timing.** One injected function runs at or after `onstartgametype()` and before the first
   `checktimelimit()` tick that would fire `ontimelimit()` (`globallogic.gsc:3276`).

Requirement 1 is the injector's job and is mode-agnostic at the buffer level — the compiler emits GSC,
the VM is the VM. The unknown is requirement 2: **which entry point reliably runs injected MP code, and
when.**

## The injection mechanism (established)

The AuroraDoesCode `t7-compiler-custom` fork, branch `dev_csc_inj`, with ate47's Cold War injection
support (`.claude/CLAUDE.md` → toolchain):

- Compiles `.gsc` (server/game) and `.csc` (client) to T9 script bytecode.
- Injects the compiled buffer into the running game's script VM and links it so the VM can resolve its
  functions.
- Exposes hook primitives as custom opcodes — the family that matters here is **`replacefunc` /
  detour** (replace an existing script function's body with an injected one) and direct
  function-reference calls. These are how injected code seizes a call site that the engine already
  invokes.

The ZM guides lean on `zm_common/load.gsc` because it is a function the **engine itself calls early**
during zombie match init, giving injected code a guaranteed, well-timed execution point without a
detour. MP needs the same property from a different script.

## MP bootstrap candidates — ranked, all [VALIDATE]

Test in this order; the first that reliably prints wins.

| # | Candidate | Mechanism | Why it might work | Why it might not |
|---|---|---|---|---|
| 1 | `scripts/mp_common/load.gsc` (if it exists) | engine-called init, mirror of the ZM path | direct structural analogue of the known-good ZM hook | may not exist, or may not be threaded the same way in MP |
| 2 | detour `gunfight.gsc` `main()` or `onstartgametype()` via `replacefunc` | replace the gametype entry, call the original, then thread the mod | runs at exactly the right time by construction — after nothing, before the round loop | replacing `onstartgametype` means you must re-invoke the stock body faithfully or you break setup |
| 3 | detour an early `_globallogic` / MP core init function | same as 2 but earlier and mode-independent | fires for every MP mode, not just Gunfight | too early — `level.on*` pointers not installed yet; must defer with a notify wait |
| 4 | thread off a `level` notify (e.g. a round/prematch notify) from any injected init | `level waittill(...)` in an injected function | decouples timing from a specific function body | requires an injected function to already be running to register the wait — chicken/egg with 1–3 |

⚠ **Candidates 2–4 all still need candidate-1-style reach to place the injected init in the first
place.** The detour opcode has to be applied by *some* code the injector runs at load. So the true
dependency order is: (a) confirm the injector's own load-time entry into the MP VM exists at all, then
(b) use it to install one of the timing hooks above.

## Cleanest shape if candidate 2 validates

```
// injected into MP VM
replacefunc( gunfight::onstartgametype, ::hook_onstartgametype );

hook_onstartgametype()
{
    [[ gunfight::_stock_onstartgametype ]]();   // run stock setup untouched
    thread mod_round_fixups();                  // our additive layer
}

mod_round_fixups()
{
    // the additive core from CLAUDE.md, unchanged:
    if ( !isdefined( level.zones ) ) level.zones = [];
    // latch flags, world uimodel sets, round_start notify ...
    level.ontimelimit = &my_health_decision;    // -> function_c4915ac()
}
```

The exact `replacefunc` spelling and how to reference the stock body are compiler-fork specifics to
confirm against the `dev_csc_inj` docs — **[VALIDATE]**.

## Hello-world — the test that decides all of the above

Do this **before** writing any real fixup. One line of observable output per candidate.

1. Compile a minimal script whose injected init calls `iprintln( "MODLOADED mp <candidate#>" )` (or
   `logprint` to the console log if `iprintln` needs an entity/level context that isn't ready).
2. Wire it to candidate 1. Inject. Start a Gunfight custom match. Watch for the string.
3. If nothing prints, move to candidate 2, then 3, then 4.
4. For whichever prints, add a second line inside a `level.ontimelimit`-adjacent check to confirm the
   pointer is reassignable from that context — print `isdefined( level.ontimelimit )` and the result of
   reassigning it to a stub.

**Records to keep** (this becomes the finding when filled):

- Injector build / `dev_csc_inj` commit: `_____`
- Game build / patch: `_____`
- Candidate that printed: `_____`
- Earliest point the string appeared (main menu / map load / round 1 start): `_____`
- `level.on*` pointers defined at that point: yes / no
- Reassignment of `level.ontimelimit` took effect: yes / no

Only after this passes does the Phase 3 order in CLAUDE.md (zones guard → latch flags → `ontimelimit` →
timer) begin.

## What is NOT yet known

- Whether `scripts/mp_common/load.gsc` exists in the T9 dump under that name — **verify against
  `ate47/bocw-source` before assuming candidate 1**. Grep the extracted tree for
  `mp_common/load` and for the MP `main()`/`init()` chain that the engine calls.
- Whether the `dev_csc_inj` injector auto-threads an injected `init()` in MP, or only in ZM. This is the
  single highest-value unknown; if it only primes ZM, the MP path needs a detour (candidate 2+) rather
  than a passive init.
- CSC (client script) side: none of the fix needs client scripts — the round decision and pointer are
  all server/game-VM. Note this so nobody burns time on a `.csc` bootstrap.

## Exposure

Injection is where local exposure begins, and it begins on the **host** only. The detection surface of
loading this buffer — process handle, memory write, any detour hook — is documented separately in
[[tac-risk-model]]. Read it before injecting on any account you are not prepared to lose.
