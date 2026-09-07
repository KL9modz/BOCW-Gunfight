# Testing

## Layer 0 — offline, zero risk, works with no game running

```powershell
cd BOCW-Gunfight
.\tools\check-gsc.ps1 .\src\gunfight_tweaks.gsc
```

Three stages: compile → round-trip through the decompiler → resolve every
`namespace::function` call against `bocw-source-main\scripts`.

The harness resolves `ACTS\` and `bocw-source-main\` **two levels up** from itself,
i.e. beside the repo. Missing either is a hard `exit 1` — it will not report PASS
having silently skipped stage 3.

**The third stage is the one that matters.** GSC resolves calls dynamically, so a
misspelled API name **compiles perfectly** and only dies at runtime.

**VERIFIED that the check actually catches this** — typo'ing
`callback::on_start_gametype` into `on_start_gametypo` still compiled cleanly, and
the harness caught it:

```
  ok  callback::on_connect
  NOT FOUND  callback::on_start_gametypo  (namespace exists in callbacks_shared.gsc)
  1 unresolved call(s) - these compile but fail at runtime.
```

A passing run looks like:

```
[1/3] compiling...
[2/3] round-tripping through decompiler...
[3/3] resolving API calls against game source...
  ok  callback::on_connect
  ok  callback::on_start_gametype
  ok  system::register
PASS - compiled to ...\gunfight_tweaks.gscc
```

Expect `Can't read file data for cw` on stderr during stage 2. **That is normal**
— see toolchain.md. Only the exit code means anything.

The harness only checks `ns::fn()` calls. Bare builtins (`iprintln`, `getentarray`,
`setgametypesetting`) and `level.*` field names are **not** validated — for those,
grep `bocw-source-main` by hand.

## Layer 1 — in-game smoke test

Prerequisite: game running. `injectcw` aborts instantly otherwise.

1. Launch Cold War, start a private match **on a real Gunfight map** — a control
   case, so only one variable changes.
2. `acts injectcw gunfight_tweaks.gscc scripts\mp_common\bb.gsc scripts\core_common\clientids_shared.gsc`
3. Look for the `iprintln` on connect. If the message appears, injection +
   `system::register` + callback registration + `level.*` access all work.

**The open question is timing** — UNVERIFIED. Injection patches a scriptparsetree
pool entry, so it takes effect when the game next *links* that script. Best guess:
inject from the lobby, then start or restart the match. If nothing prints, vary
*when* you inject before changing anything else.

## Layer 2 — team size

Same supported map. Bump `level.maxteamplayers` and watch whether capacity
actually changes. Remember the branch at `player_shared.gsc:1317`: it only takes
effect when `teamcount == 0` or `com_maxclients == teamcount`; otherwise
`com_maxclients` wins. See team-sizes.md.

## Layer 3 — Gunfight on a normal map

Only now install the `powrprof.dll` proxy (dll-proxy.md) and use `cwdllgt`.

The prediction to test: on any map without `gunfight_zone_center` entities, the
round-start LUI event never fires and the overtime clock never initialises,
because `onstartgametype()` bails at `gunfight.gsc:121` and `overtime()` dies at
`:946`. **This already matches an in-game observation** — no round-timer control
on a non-standard map — which is the strongest evidence in these notes.

Confirm that first, *then* try the fix. Do not install the proxy and change GSC
in the same step.

## Known-good reference script

`BOCW-Gunfight\src\gunfight_tweaks.gsc` — passes Layer 0, compiles to valid VM38,
all API calls resolve. Use it as the Layer 1 smoke test; it prints on connect.
Re-VERIFIED against ACTS 3.3.0.

## Debug notes

- `iprintln` on the player is the cheapest feedback channel.
- `acts dbg` is a VM debugger; `dfuncscw` / `dpcw` dump function names and pools
  from the live process if you need to inspect state.
- Nothing in these notes has been run inside a live game yet. Treat every
  in-game claim as a hypothesis until Layer 1 passes.
