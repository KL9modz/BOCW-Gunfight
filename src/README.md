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

| Tool | Role |
|---|---|
| `AuroraDoesCode/t7-compiler-custom`, branch `dev_csc_inj` (install `t7c_installer.exe` from Releases) | compiler + injector |
| VS Code + `vscode-txgsc-1.0.8.vsix` (ships in the compiler repo) | editor |

The injector **hooks** the stock script named in `gsc.conf` (`script=scripts\mp_common\bb.gsc`,
`mode=mp`) — it does **not** overwrite it. When `bb.gsc` runs in the MP VM, our injected script's
`autoexec` runs too. Reverting is not injecting; no stock file is ever changed.

## Build + inject

1. Open the project folder (`hello_world/` or `gunfight_mod/`) in VS Code with the txgsc extension.
2. Compile (the extension's build task) → produces a `.gscc` (git-ignored).
3. Start the injector, select the running Cold War process, inject the `.gscc`.
4. Start a **private/custom Gunfight** match.

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

## Known compile-time risk

The mod references stock symbols by their atian-decompiler **hashed names** (`function_c4915ac`,
`var_31f5f23`, `var_a236b703`, `var_61952d8b`). The compiler is expected to round-trip these to their
hashes; if any won't resolve, `gunfight_mod.gsc` carries inline FALLBACKs (the health decision can be
inlined; the latch-flag names are cosmetic and can be dropped). The hello-world uses **no** hashed stock
names, so it validates the load path independently of this risk.
