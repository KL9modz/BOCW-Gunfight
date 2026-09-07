# src — the mod source

Two projects. Build the first, prove the hook, then build the second.

```
hello_world/    minimal validator — proves the MP hook fires in a custom Gunfight lobby
gunfight_mod/   the real mod — additive, zero stock files modified
```

Each is a compiler project: a `gsc.conf` (names the injection hook) plus `scripts/*.gsc`.
Full mechanism and evidence: [`../docs/notes/mp-load-path.md`](../docs/notes/mp-load-path.md).

> ⚠ **Injecting begins host-side exposure.** Read
> [`../docs/notes/tac-risk-model.md`](../docs/notes/tac-risk-model.md) first, and inject only on an
> account you are prepared to lose. Nothing here hides itself from the anti-cheat — that is out of scope.

## Toolchain

⚠ **ACTS is the compiler and injector**, pinned at v3.3.0 — not `t7-compiler-custom`. That fork was
the original plan and this file named it until the knowledge base was consolidated; the toolchain
actually in use, and the one `tools/check-gsc.ps1` invokes, is ACTS. Recorded so it is not
re-litigated. Commands and gotchas: [`../docs/notes/toolchain.md`](../docs/notes/toolchain.md).

| Tool | Role |
|---|---|
| [`ate47/atian-cod-tools`](https://github.com/ate47/atian-cod-tools) (ACTS), pinned v3.3.0 | compiler + injector — `acts gscc` / `acts injectcw` |
| VS Code + `vscode-txgsc-1.0.8.vsix` | editor / syntax highlighting only |

The injector **hooks** the stock script rather than overwriting it. When `bb.gsc` runs in the MP VM,
our injected script's `autoexec` runs too. Reverting is not injecting; no stock file is ever changed.
Each project's `gsc.conf` records that hook point (`script=scripts\mp_common\bb.gsc`, `mode=mp`) — it
is `t7-compiler-custom`'s config format, kept as the hook-point record; ACTS takes the same two values
as command-line arguments instead.

## Build + inject

```powershell
# 1. validate offline first — no game needed, catches typo'd API names
.\tools\check-gsc.ps1 .\src\hello_world\scripts\hello_world.gsc

# 2. compile (VM38)
acts gscc src\hello_world\scripts\hello_world.gsc -g cw -p pc -o hello_world

# 3. with Cold War ALREADY RUNNING, inject
acts injectcw hello_world.gscc scripts\mp_common\bb.gsc scripts\core_common\clientids_shared.gsc
```

4. Start a **private/custom Gunfight** match.

⚠ `injectcw` aborts instantly if `BlackOpsColdWar.exe` is not running, and it does **not** apply
detours — override via `callback::*` and `level.*` function pointers, which is what both projects
already do. Swap the paths for `gunfight_mod` once the hello-world has confirmed the hook.

## Order of operations — do not skip

1. **Hello-world first.** Inject `hello_world/`. In a custom Gunfight lobby, confirm the console log
   shows `[GFHELLO] 1/4 … 4/4` and the on-screen `MP injection hook is live` banner.
   - **Count how many times `3/4 on_start_gametype fired` logs per match.** Once = per-match; more =
     per-round (map fast-restart). The real mod's presentation fixes assume per-round — this is the
     one cadence fact source can't settle. Record it in [`../docs/notes/mp-load-path.md`](../docs/notes/mp-load-path.md).
   - If `4/4` shows `UNDEFINED`, stop — the pointer isn't set at that hook; see the doc's fallback.
2. **Then the mod, one stage at a time** via the `level.gfmod` switches in `gunfight_mod.gsc`, **bots
   before humans**:
   1. `zones_guard` only → sanity (nothing should visibly change).
   2. `+ timelimit_fix` → the load-bearing fix. On an **unlocked** map, let the timer expire and
      confirm the round ends on the health decision instead of hanging/among the glitch.
   3. `+ presentation` → verify the five symptoms clear (round-2 music, noRespawnsLeft HUD, round-start
      UI, correct VO, correct lives counter). Cross-check against Phase 2 in `.claude/CLAUDE.md`.
   4. `timer_override` only if you want >60s — and only after Phase 0 **T0.2** shows the menu doesn't
      already expose the timer (see [`../docs/notes/phase-0-1-test-protocol.md`](../docs/notes/phase-0-1-test-protocol.md)).

## What each stage touches (all reversible by not injecting)

| Switch | Reassigns / sets | Stock ref |
|---|---|---|
| `timelimit_fix` | `level.ontimelimit = &mod_ontimelimit` (reaches `function_c4915ac`, skips the crashing `overtime()`) | `gunfight.gsc:58, 915, 931, 1090` |
| `zones_guard` | `level.zones = []` if undefined (defensive) | `gunfight.gsc:944` |
| `presentation` | latch flags + noRespawnsLeft HUD + `round_start` LUI + round-2 music | `gunfight.gsc:124-137` |
| `timer_override` | `level.gettimelimit = &mod_gettimelimit` | `gunfight.gsc:59, 1137` |

## Compile-time risk — CLOSED

The mod references stock symbols by their atian-decompiler **hashed names** (`function_c4915ac`,
`var_31f5f23`, `var_a236b703`, `var_61952d8b`). **They resolve.** `tools/check-gsc.ps1` against ACTS
3.3.0 and dump `edd94bd`, run 2026-09-06, passes all three projects, and stage 3 resolves
`gunfight::function_c4915ac` alongside `gunfight::overtime`, `clientfield::set_world_uimodel`,
`music::setmusicstate` and `util::isfirstround`.

The inline FALLBACKs in `gunfight_mod.gsc` are therefore **not needed** on this toolchain. Leave them
in as insurance against a dump revision or an ACTS version bump, but do not treat this as an open risk.

⚠ This closes the *compile-time* risk only. Everything in-game remains unverified — compiling and
resolving is not running.
