# Pipeline / toolchain survey — the six candidate repos, checked

**Question answered:** which of the six commonly-cited repos actually help the *compile → inject → run*
pipeline for a T9 MP mod. Checked in-session (Aug 2026), not inherited. Verdicts below; the headline is
that the pipeline is **two repos**, and one of them handed us the MP hook point the public tutorials omit.

## Verdicts

| Repo | Status (verified) | Pipeline value |
|---|---|---|
| **ate47/atian-cod-tools** | **Active**, 1300+ commits | **PRIMARY — compile + dump.** T9 decompile **and** compile both ✅ (rev 37-38). Produced the `bocw-source` dump. No injector (by design) |
| **AuroraDoesCode/t7-compiler-custom** | **Active**, branch `dev_csc_inj` @ `4de00c8` | **PRIMARY — compile + inject.** This is the injector. Its config + example project answered the MP-load-path question (below) |
| **ModzCentral01/Cold-war-Mods** | **Active** (V2 Injector, V5 GSC) | **Reference only.** Ships compiled `.gscc` incl. MP (`BlackOpsColdWar_atianmenu_pc.gscc`), but docs cover **only** ZM injection (`zm_common/load.gsc`); MP placement undocumented. Corroborates the public MP gap, adds no mechanics (no source, own closed injector) |
| **xensik/gsc-tool** | **Active**, but T9 = **WIP** | **Not the T9 toolchain.** Compile/decompile only, no injection, T9 still `*WIP*` in the support table. Dead end stands |
| **ProjectDonetsk/T9** (Defcon) | **Archived** ("no longer maintained") | **Dead end.** Named successor **`xifil/t9-mod` → HTTP 404 (verified this session)**. Both gone |
| **ProjectHiNAtyu/T9_BOCW_GSC_Wiki** | **Dormant** (3 commits) | **No usable content.** "Files that can be used directly are not available to the public." Prose only. Confirmed |

**Net:** the working pipeline is `atian-cod-tools` (compile/dump) **+** `t7-compiler-custom` `dev_csc_inj`
(compile/inject). The other four are dead, closed, or reference — none add pipeline capability.

## The find: t7-compiler-custom documents the MP hook and the load model

Two files in `AuroraDoesCode/t7-compiler-custom` @ `4de00c8` closed the residual load-path unknown.

**`Default Project/T9/gsc.conf`** — the injector's own config, with the recommended hook points:

```
game=T9
mode=zm            # MP, ZM, or common  -> selects which script VM
# *IMPORTANT* This script will not be overwritten. The injector will simply hook this script
#             to execute your script.
# Recommended injection points:
    # MP:           scripts\mp_common\bb.gsc
    # ZM:           scripts\zm_common\load.gsc
    # Frontend:     scripts\core_common\load_shared.gsc
script=scripts\zm_common\load.gsc
```

The injector **hooks** a stock script (does not overwrite it): when the hooked stock function runs, the
injected script's linked functions run too. `mode=` picks the VM. **For MP the recommended hook is
`scripts\mp_common\bb.gsc`** — the answer the public ZM-only tutorials never give.

**`Default Project/T9/scripts/headers.gsc`** — the sanctioned entry pattern:

```
autoexec __init__sytem__()
{
    system::register("clientids_shared", &__init__, undefined, undefined);
}
__init__()
{
    callback::on_start_gametype(&init);
    callback::on_connect(&onPlayerConnect);
    callback::on_spawned(&onPlayerSpawned);
}
```

`autoexec` runs on injected-script load → `system::register` → the registered init adds `callback::on_*`
handlers. This is **identical to the additive model derived from `bocw-source`** — and stock
`scripts/mp_common/bb.gsc` itself uses the exact same shape (`autoexec __init__system__` →
`system::register(#"bb", &preinit, ...)` → `preinit` registers `callback::on_spawned` /
`on_player_killed`). So the injector honoring injected `autoexec` is not a hope — it is the documented,
stock-mirrored contract.

Full consequences for the mod are folded into [[mp-load-path]]; this note records where the answer came
from and the state of the other five repos so none get re-surveyed.

## What is still empirical (small)

The mechanism is verified from source and toolchain docs. What a hello-world still confirms is only that
the injector's `bb.gsc` hook fires in a **custom Gunfight** lobby specifically (not just standard MP),
plus wall-clock timing — a sanity check of a known-good pattern, not an exploration. See [[mp-load-path]]
§ hello-world.
