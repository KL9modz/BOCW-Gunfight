# MP dvars and movement — what actually takes effect, and what silently does not

**Conclusion up front.** Setting a dvar in MP and reading it back proves nothing. `#"jump_height"`
accepts a value, reports it faithfully, and does not affect MP movement at all, because MP never reads
it. `#"bg_gravity"` does work. The difference is not visible from the dvar API — only from tracing who
consumes the value.

**Status: VERIFIED in-game 2026-09-07.** Gravity modification was observed changing a live Gunfight
match on the test box. This is the first confirmed *gameplay* modification via injected MP GSC, one
step past the hello-world hook gate.

---

## The finding that matters

| Dvar | Set succeeds? | Reads back? | Actually does anything in MP? |
|---|---|---|---|
| `#"jump_height"` | yes | yes | **NO** |
| `#"bg_gravity"` | yes | yes | **yes** |

`jump_height` appears 5 times in the whole dump: `cp_common/gametypes/globallogic.gsc`,
`zm_common/gametypes/globallogic.gsc`, `zm_common/zm_weap_bouncingbetty.gsc`, and twice in
`core_common/vehicles/smart_bomb.gsc` as `self.settings.jump_height` (AI actor settings, unrelated).

**Zero occurrences under `mp_common/` or `mp/`.** It is a campaign and Zombies dvar. Anyone reaching
for it to change MP jump gets a value that sets cleanly and does nothing.

## Why `bg_gravity` works, stated precisely

⚠ Not because script reads it in MP. Its script read-sites are in `cp/cp_nam_armada.gsc`,
`zm/ai/zm_ai_hulk.gsc`, `zm_common/`, and killstreak trajectory math
(`killstreaks/airsupport.gsc:181`, `killstreaks/artillery_barrage_shared.gsc:670`). **None of those
are player movement.** They are scripts doing their own physics arithmetic.

It works because the **engine** consumes `bg_`-prefixed movement dvars natively. That is the useful
generalisation: a dvar's effect in MP depends on whether the *engine* reads it, and script occurrence
counts cannot tell you that either way. `jump_height` has script hits too — in the wrong VMs.

Stock never *sets* `bg_gravity`.

### The mechanism used

Apex height is `v² / 2g`, so dividing gravity by 20 gives 20× apex with jump velocity untouched:
`setdvar( #"bg_gravity", 40 )` against a stock baseline of 800.

**Inherent tradeoff:** descent scales with it, so the result is floaty rather than snappy. For a true
high-jump with a normal fall, `setvelocity` (16 stock uses) is the tool, and stock uses it for exactly
this shape: `player setvelocity( player getvelocity() + direction * strength )`. Multiply jump velocity
by `sqrt(20)` ≈ 4.47 for the same apex under normal gravity. Costs per-player jump detection.

---

## ⚠ The epistemic trap — a readout is not a result

The `jump_height` attempt produced a **numeric readout that confirmed nothing**. The banner printed
`780`. That was true — the dvar really was 780 — while the thing actually being tested was unchanged.

**Reading back a value you just wrote is a closed loop. It proves the write landed and nothing else.**

This matters more here than on other platforms, because retail renders numbers only (see
[[testing]] and `src/README.md`), so a number is the only thing an instrument can show you — and it is
easy to mistake for evidence. A human watching the actual jump is what caught it; the readout alone
looked like a clean pass.

Applies directly to [`src/mp_probe/`](../../src/mp_probe/scripts/mp_probe.gsc): its probes 1-5 and 7
read engine-owned state and are evidence. Probe 6 reads its own counter and is valid only because the
quantity of interest is *how many times the engine called us*, not the number itself.

**Rule: when a probe reports on a change you made, the confirming observation must come from a
different channel than the one you wrote through.**

---

## Do not use — absent from T9

All confirmed at **exactly zero** occurrences across the dump. `tools/check-gsc.ps1` stage 4 rejects
every one of them, which is what that stage is for:

```
setdvarint    setdvarfloat    setdvarifuninitialized    setclientdvar
setgravity    setplayergravity    setjumpheight    launchplayer
makedvarserverinfo    setdvarserverinfo    replicatedvar
```

## Use instead — confirmed present

| Function | Uses in dump |
|---|---|
| `setdvar` | 1294 |
| `getdvarint` | 1897 |
| `getdvarfloat` | 315 |
| `getvelocity` | 114 |
| `setvelocity` | 16 |
