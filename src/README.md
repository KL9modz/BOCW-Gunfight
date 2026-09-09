# src — the mod source

Prove the hook, measure, then change behaviour.

```
hello_world/      minimal validator — proves the MP hook fires. ✅ CONFIRMED 2026-09-07
mp_probe/         read-only — com_maxclients, timelimit, zone count, cadence
lobby_probe/      read-only — four player-count builtins + isvalidgametype() over
                  candidate Gunfight strings. NOT YET RUN
gunfight_mod/     the real mod. ✅ ALL FOUR SWITCHES VERIFIED 2026-09-08 —
                  3v3 Gunfight on Zoo, 60s rounds, timed out cleanly, correct HUD

  ── staged tests. ONE PER MATCH. Each WRITES. Lobby return after each. ──
test_maprestart/  B4 · can map_restart replace F7, and drop the cwpatch prerequisite?
test_switchmap/   C6 · gametype switch in a 12-slot TDM lobby. THE team-size question
test_addclients/  C7 · fill until refused — the real client ceiling, measured
test_teamfill/    C8 · fill ONE team until refused — is 8 clients 4v4?
test_latejoin/    C10 · make a mid-match joiner land on a TEAM, not in spectator
test_seatspectator/ C11 · seat an EXISTING spectator, no menu involved.
                  ⬅ SUPERSEDES C10. One stock call, no override at all
test_spawnmode/   B8 · why 4-per-side spawns break, and the one-line candidate fix.
                  Face Off runs 6v6 on the same maps — the map is not the problem
```

B4 is the odd one out: it answers nothing about team size, it makes the **setup** shorter. Every other
test costs a session; that one pays a session back on every future run.

**C11 is the one to run first, and B8 is what makes its result usable.**

Every other team-size test attacks the pregame lobby, where `com_maxclients` is fixed and script
cannot reach. C11 acts on a player already sitting in spectator — script territory — with **one stock
call and no override**: `player [[ level.autoassign ]]( 0, team, undefined )` lands in
`team_assignment.gsc:419`, which uses the team **verbatim, with no fullness check**. That is the same
branch klaze already watches fire whenever "a spot is open on the join"; we hand it the answer instead
of the session.

C10 is the earlier, narrower version — it changes what happens at the *instant* of joining. Keep it as
the fallback; run C11 first.

⚠ Both reach **4v4** — eight clients, zero casters — and stop. 5v5 needs ten.

⚠ **And 4v4 already broke once.** klaze has had four on a Gunfight team via a lobby glitch, and the
spawns went wrong. **B8 is the diagnosis and the candidate fix**, and it is worth running *before*
C11 succeeds, because a working C11 walks straight into the same breakage.
[`../docs/notes/lobby-settings.md`](../docs/notes/lobby-settings.md)

**The queue, with what each reading means:** [`../docs/notes/test-queue.md`](../docs/notes/test-queue.md).

⚠ **Why the three tests are separate projects rather than one with a switch.** An injected payload
that can only do one thing cannot accidentally do another. The "one write per match" rule is then
mechanical rather than a matter of remembering.

⚠ **`test_maprestart`, `test_switchmap` and `test_teamfill` ship with `read_only = 1`.** Run them that way first — the
read-only phase is what confirms you are in the right lobby, and for `test_teamfill` it is what
confirms the team value is the right representation. Flip the switch only after the read phase comes back sane.

⚠ **The four new projects call builtins that no stock script in the dump calls**, taken from ate47's
Cold War function table rather than from `bocw-source`. **Run `tools/check-gsc.ps1` on each before
injecting** — stage 4 is exactly the check for a name that does not exist, and it is the check that
caught `logprint`.

⚠ **Two argument shapes are still unvalidated**: `addtestclient` and `map_restart`. Both are called
in their **zero-argument** form, which is the only one that cannot be wrong about an argument, and
both carry a config switch for the one-arg form if `dump-grep.sh` shows stock passing something.

✅ **`dump-grep.sh` has since been run** against the alternate dump and it corrected three of these
scripts — including replacing `test_setteam` entirely, because `setteam` is an entity function and
would have measured nothing. [`../docs/notes/dump-cross-check.md`](../docs/notes/dump-cross-check.md).
Still worth re-running against `bocw-source`, which is primary.

**`mp_probe/` is the cheap one to reach for.** It writes nothing but its own counter and
answers, per match, questions that otherwise cost menu-walking or guesswork:

| Tag | Question | Why it matters |
|---|---|---|
| `1xxxxx` | `com_maxclients` | The team-size ceiling *of this lobby*. Reads **8** in 3v3 Gunfight, **12** in private TDM. The live question is whether `switchmap_load` or the lobby glitch moves it — see `docs/notes/atian-menu-source.md` |
| `2xxxxx` | live `timelimit` setting | Phase 0 **T0.2** answered numerically instead of by walking menus |
| `3xxxxx` / `4xxxxx` | `timelimitmin` / `timelimitmax` | Confirms the clamp is `[0, 1440]` and not the constraint |
| `5xxxxx` | `gunfight_zone_center` count | **The map dependency.** `0` = unlocked map, `>0` = stock zoned. Classifies any map in one number |
| `6xxxxx` | `on_start` firing count | per-match vs per-round cadence |
| `7xxxxx` | players in match | sanity |

Output is `PROBE_ID * 100000 + VALUE`, one every 2s — so `100012` is probe 1, value 12. Strip
the leading digit. `99999` as the value means undefined at read time. Tagging is necessary
because a literal label renders as nothing on retail (see **Observability** below).

Each is a compiler project: a `gsc.conf` (names the injection hook) plus `scripts/*.gsc`.
Full mechanism and evidence: [`../docs/notes/mp-load-path.md`](../docs/notes/mp-load-path.md).

> ⚠ **Injecting begins host-side exposure.** Read
> [`../docs/notes/tac-risk-model.md`](../docs/notes/tac-risk-model.md) first, and inject only on an
> account you are prepared to lose. Nothing here hides itself from the anti-cheat — that is out of scope.

**Why nothing here uses `replacefunc` or a detour.** Both projects register through
`system::register` → `callback::*` and reassign `level.*` function pointers. Zero `.gsc` file in `src/`
calls `replacefunc` or installs a detour — verified by grep. That is deliberate, and it is the
difference between the two worst rows of the risk register: `tac-risk-model.md` scores API hooks and
detours as **R2, detect confidence HIGH**, and names a `replacefunc`-based MP bootstrap as sitting
directly in it. The callback-and-pointer approach incurs **R3, script-VM modification, MED** instead.

⚠ **That lowers the profile; it does not make the host unexposed.** **R1** — the injector opening a
process handle and writing executable memory — is **unchanged**, because `injectcw` does exactly that
regardless of what the GSC contains. The project accepts the *detection* risk and limits *blast radius*
only. Do not read the paragraph above as "low risk".

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
# 1a. arity — check-gsc.ps1 does NOT check argument counts; this does
python3 tools\check-args.py src\hello_world\scripts\hello_world.gsc

# 1b. name resolution — stages 3-4 without ACTS. Splits "no stock caller" from
#     "does not exist", which plain stage 4 cannot tell apart
python3 tools\check-dump.py src\hello_world\scripts\hello_world.gsc

# 1c. the real harness — compile + round-trip. NEEDS ACTS, Windows only
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
   4. `timer_override` — **ON, and required under a map carry at *any* value.** ⚠ The old guidance
      here ("only if you want >60s, the rules menu already exposes 0/20/30/40/50/60s") is true in a
      plain lobby and **false once the map is carried**: the carry re-initialises gametype settings and
      a menu-set timer reverts to 30. `mod_apply()` reruns on every `on_start_gametype`, which is why
      the override survives. Measured 2026-09-08 — [`../docs/notes/menu-map.md`](../docs/notes/menu-map.md).

## What each stage touches (all reversible by not injecting)

| Switch | Reassigns / sets | Stock ref |
|---|---|---|
| `timelimit_fix` | `level.ontimelimit = &mod_ontimelimit` (reaches `function_c4915ac`, skips the crashing `overtime()`) | `gunfight.gsc:58, 915, 931, 1090` |
| `zones_guard` | `level.zones = []` if undefined (defensive) | `gunfight.gsc:944` |
| `presentation` | latch flags + noRespawnsLeft HUD + `round_start` LUI + round-2 music | `gunfight.gsc:124-137` |
| `timer_override` | `level.gettimelimit = &mod_gettimelimit` | `gunfight.gsc:59, 1137` |

## ⚠ Observability on retail — numbers only

**VERIFIED in-game 2026-09-07.** Design every on-screen instrument around this or it will tell you
nothing.

⚠ **This is a DISPLAY limitation, not a string limitation.** An earlier version of this section said
"literal script strings are compiled out of ship builds", full stop. **That was too broad and is
wrong.** Authored literals work fine for every *functional* purpose — a probe wrote
`setdvar( #"g_gametype", "gunfight" )`, read it back with `getdvarstring`, and the `== "gunfight"`
comparison evaluated **true**. Literals are real and usable in comparisons, dvar values, entity
targetnames and everything else. Only **on-screen rendering** of an authored literal fails.

| Channel | Works on retail? | Evidence |
|---|---|---|
| `println` / `logprint` | **No** | Retail writes no log file at all — install dir and both profile trees checked twice. `logprint` additionally does not exist in T9 (0 occurrences in the dump). |
| `iprintlnbold("literal text")` | **No — display only** | All **401** stock literal call sites decompile to `"<dev string:xNN>"`, so an authored literal renders as nothing. The string itself is fine; the HUD will not show it. |
| `iprintlnbold( runtimeValue )` | **Yes** | **66** stock variable call sites, e.g. `iprintlnbold( numshots )`. |
| `iprintlnbold( #"mp/..." )` | Only if it already exists | **24** stock hashed refs. You cannot add entries to the localization table. |
| literals for comparison / dvars / targetnames | **Yes** | Verified in-game — see the `g_gametype` probe above. |

The hello-world banner read `"^2[GFHELLO] hook live - on_start fired 1x"` and rendered on screen as
the single character **`1`**. That was the success case — the literal text did not render and the
runtime integer did.

**Consequence for instruments only:** encode on-screen findings as *numbers*. A label you write will
not appear, and its absence makes the number that does appear look like a malfunction. Concatenating a
literal with a value (`"count: " + n`) displays as just the value. **None of this restricts what your
logic may do with strings.**

## ⚠ What a harness PASS does and does not mean

Read this before trusting one. A PASS is necessary, not sufficient, and treating it as sufficient is
what put a game-crashing script into an injection.

**It checks:** the file compiles to VM38 bytecode; the bytecode round-trips through the decompiler;
every `namespace::function` call resolves to a real function in the dump (stage 3); every bare call
appears *somewhere* in the dump (stage 4).

⚠ **Stage 4 over-reports, and `tools/check-dump.py` fixes it.** "No stock script calls this" is not
"this does not exist". `isvalidgametype` and `mapexists` sit at real addresses in
`BlackOpsColdWar.exe` and appear in **zero** stock scripts — stage 4 flags them exactly as it flagged
`logprint`, which was fatal because it exists in *neither* place. Cross-checking ate47's engine table
splits the two. Run `check-dump.py` alongside; it reports fatals and unused-by-stock separately.

**It does NOT check:**

- **Argument counts.** `system::register` with 4 args passes stage 3 identically to the correct 5.
  ⚠ `tools/check-args.py` now covers this **for builtins** — every bare call is checked against
  ate47's Cold War table. It does **not** cover namespaced GSC functions like `system::register`
  (they are not in that table), and it cannot check what an argument *means*.
- **Dialect.** `#include` vs `#using`, a missing `function` keyword, a missing `private` — all invisible
  to every stage. Two of the three defects that crashed the game were this class.
- **That a name is really a builtin.** Stage 4 only asks whether the name appears in the dump at all.
  `__init__` and `__init__system__` pass because stock declares them — that is coincidence, not
  correctness.
- **Anything about runtime.** Compiling and resolving is not running.

Stage 4 catches the *non-existent builtin* class specifically — the `logprint` failure. It does not
generalise beyond that. When in doubt, diff your decompiled `.gscc` against the stock file you are
mirroring (`acts gscd`), which is how the original defects were actually found.

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
