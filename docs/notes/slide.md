# Slide distance — what the engine does, and the levers (2026-09-20)

**Question:** can the mod change how far a player slides?
**Answer so far:** the distance is not a dvar. It is a fixed **duration** × a **start speed** the engine
computes from a table and the weapon, then friction. Script cannot reach the table, but it CAN scale the
velocity the instant the slide begins — `src/slide_probe/` is built to measure exactly that (never run).
Everything below was read off the LIVE exe (read-only memory scans + capstone, `tools/dvar-live/`), not
guessed. ⚠ Addresses are for the exe dated 2026-06-12 (`BlackOpsColdWar.exe` 321,577,456 B); a patch
moves them, the method does not.

## 1. What script can see (dump)
- `allowslide( bool )` / `isonslide()` — on/off and a query (`funcs_cw.csv`). `specialty_slide` is the
  perk Gunfight gives every loadout (`gunfight.gsc:348`); prop hunt turns sliding off with
  `allowslide( 0 )` (`prop.gsc:1235`).
- `slide_begin` / `slide_end` — engine events with script handlers (`callbacks_shared.gsc:1791/1805`,
  `player_monitor.gsc:479` counts them) AND a notify on the player: `zm_perk_slider.gsc:197` does
  `self waittill( #"slide_begin" )`. Nothing in any VM sets a slide length. The values system
  (`values_shared.gsc`) has no slide scale; `move_speed_scale` → `setmovespeedscale` is its only movement scalar.
- `addtalent` / `removetalent` / `cleartalents` / `hastalent` ARE builtins — they sit in the engine table
  under their T8/T9 script hash (`function_b5feff95` = `addtalent`, method, `exe+0x3e21df0`). The T89
  hash (`tools/dvar-live/t89.py`) resolves 116 of the table's 1,427 unnamed rows from dump identifiers →
  `reference/funcs_cw_resolved.csv` (the authority file is untouched).

## 2. The engine's slide model (live exe, 2026-09-20)
Registration (`Dvar_RegisterBool exe+0xbf9cd30`, `Float exe+0xbf9d2d0`, `Int exe+0xbf9d6c0`) stores each
`dvar_t*` in a pointer-slot array; the slide group is `exe+0x121343f0..0x12134428`:

| slot | dvar | type | live | default | domain | flags |
|---|---|---|---|---|---|---|
| +0 | *(registered just before the group)* | | | | | |
| +8 | `hash_4b70f9308a25eb2c` (unnamed) | BOOL | 1 | 1 | | 0x80 |
| +0x10 | `slide_subsequentslidescale` | FLOAT | **0.1** | 0.15 in code, 0.1 live | 0–0.99 | 0x880 |
| +0x18 | `slide_subsequentslidescalephdflopper` (cracked) | FLOAT | 0.05 | 0.05 | 0–0.99 | 0x80 |
| +0x20 | `slide_camerapitchoffset` | FLOAT | 70 | | −90..90 | |
| +0x28 | `slide_cameraclamp` | INT | 70 | | −90..90 | |
| +0x30 | `slide_blur_enabled` | BOOL | 1 | | | |
| +0x38 | `hash_34c8969093e802ee` (unnamed) | BOOL | 1 | | | |

Plus `slide_forcebaseslide` (BOOL 1, flags 0x8a0) in the BG feature-toggle block next to `juke_enabled`,
`slam_enabled`, `trm_enabled`, `sprint_capspeedenabled` (`exe+0xbdd8704`). **No slide speed / duration
/ friction dvar exists** — 4,497 live dvars enumerated (`reference/dvars_cw_live_2026-09-20.csv`), every
registration site mapped (`reference/dvar_regmap_2026-09-20.csv`), the slide code's dvar reads are the
seven above and nothing else.

The code (`bg_` shared, so host and clients run the same maths):

- **PM_BeginSlide** `exe+0xaf272f4..0xaf2740d` (inside the slide state fn `exe+0xaf26f20`):
  `ps+0x15d4++` (chain counter), `ps+0x15cc = serverTime` (start), movement state `ps+0x120c = 5`,
  `ps.flags |= 0x800000`, then `slide_velocity( pm, pml, idx = 0 )`.
- **slide_velocity** `exe+0xaf28600`: `vel.z = 0; dir = normalize(vel)`;
  `speed = (float) T[idx].speed` (`exe+0xaf280c0`, `T = [pm+8] + 0x8c`, 8-byte rows `{durationMs, speed}`)
  `× weaponScale` (`exe+0x9cb2590`: `ps+0x28 & 0x3ff` → weaponDef → `+0xa38` → float `+0xcbc`, plus the
  attachments' `+0x34c` deltas — a per-weapon/attachment slide speed scale) — then, if the unnamed BOOL
  is set: `× (1 − scale)^n`, `scale = slide_subsequentslidescale`, or the `…phdflopper` value when
  `HasPerk( ps, 0x93 )` (perk index 0x93 = `specialty_mod_phdflopper`, `perks_cw.txt`). `vel = dir × speed`.
  A second path (`pml+0x74 & 2`) only *accelerates* along the wish direction, capped at **200 u/s**.
- **end condition** `exe+0xaf27b00`: `remaining = start + T[idx].durationMs × AEstat( ps+0xe58, 0xc4 ) − now`
  (`exe+0xafa7d60`: the per-client **ability-engine stat 0xc4** — the hook Zombies perk tiers use to
  lengthen slides). Ends when `remaining ≤ 0`, or `|vel| < floor` (`[[pm+0x10]+0xc]`, another constant
  with the phd perk), or jump/other flags. **Duration-based, with a speed floor.**
- **chain window**: the counter resets when `start + 1250 ms < now` (`exe+0xaf2729a`), i.e. only slides
  begun within 1.25 s of the previous slide's START are "subsequent" (2nd ×0.9, 3rd ×0.81, …).
- **in-slide**: `exe+0xaf288f0` (called every frame while sliding) is weapon raise/lower timing (200 ms
  windows); the per-frame velocity is shaped by ordinary friction only. **Nothing re-clamps the speed to
  the table value after the start frame.** ← this is why a script boost should carry into distance.
- The `[pm+8]` struct (table owner) and `[pm+0x10]` (floor) were NOT identified: the dispatcher above
  the slide fn is Arxan-mangled and a shape scan of the exe's writable image regions found no
  `{ms, speed}` row with a plausible pointer at `+0x28`. So `T[0]` is not patchable yet.

## 3. The levers, ranked
1. **Script velocity scale at slide start (mod domain, joiner-safe in principle).** At `slide_begin`
   (notify) or the first `isonslide()` frame, `setvelocity( (vx·k, vy·k, vz) )`. Same shape as the mod's
   `jump_boost_think`. Expected: distance ≈ k × stock, duration unchanged. Unmeasured: whether the
   client's prediction snaps for joiners (the host is the local client — no snap for him).
   Optional **hold** (re-assert the speed every frame while `isonslide()`): the slide keeps its entry
   speed for the whole engine duration — the "long slide". `src/slide_probe/` implements both.
2. **`slide_subsequentslidescale` (dvar, `setdvar` from script — the bg_gravity precedent).**
   0 = chained slides keep full speed (slide-cancel chains stop shrinking); 0.5 = each chained slide
   halves. Not the base distance, but a real feel knob. The unnamed BOOL `#"hash_4b70f9308a25eb2c"`
   gates the whole penalty (ACTS compiles the `hash_` literal to the raw hash, so it is settable too).
3. **`setperk( "specialty_mod_phdflopper" )`** — the engine branch is in shared bg code, so it should
   apply in MP if the perk registers: 5 % chain penalty instead of 10 % + a different speed floor.
   `gf_slidephd` in the probe measures it.
4. **AE stat 0xc4** (per-player duration scale) — the real "slide length" knob, driven by talents.
   No setter found in script (`addtalent` needs a talent asset; the ZM tier talents live in ZM
   fastfiles). Untried, see below.
5. **Memory patch of `T[0]` / the friction constants / the 200 cap** — klaze's domain, and `T` is not
   located yet.

## 4. `src/slide_probe/` — the measurement (built + check-gsc PASS, payload
`/c/bocw/payloads/slide_probe.gscc` 4,186 B / 16 strings stripped, NEVER RUN)
One payload per launch: it runs INSTEAD of gunfight_menu. Dvars (read live; set them with the app's raw
`set` or the console): `gf_slide` (%, 100 = stock), `gf_slidehold` (0/1), `gf_slidechain` (0/1),
`gf_slidephd` (0/1). The line, every 2 s on the host:
`SLIDE pct:100 hold:0 chain:0 phd:0 sub:0.10 | n:3 ev:3 poll:3 | last d:312 t:720 v0:402 v1:155 | best d:340`
- `ev` vs `poll` — whether the `slide_begin` notify reaches MP script at all (poll is the fallback).
- `last d/t/v0/v1` — the host's last slide: 2D distance, ms, entry and exit horizontal speed.

**Test order:** (1) stock: 5 flat slides at pct 100 — record `d`/`t`/`v0` (these are the engine's
numbers; `t` should be constant, `v0` should drop on chained slides). (2) `set gf_slide 200` — does `d`
double? `t` unchanged? (3) `set gf_slidehold 1` — does `d` grow further, `v1 ≈ v0`? (4) `set
gf_slidechain 1` — chained `v0` no longer drops. (5) `set gf_slidephd 1`, respawn — chained `v0` drops
5 %, not 10 %. A joiner on (2)/(3) is the joiner-snap measurement. Then fold the winner into
gunfight_menu as `gf_slide` (Movement page + app Move field) — same per-life thread shape as
`jump_boost_think`.

## 5. Tools (all READ-ONLY, `tools/dvar-live/`)
`dvar_pool_scan.py --find <names>` (hash-scan for known dvars, annotated dump) · `arena_full.py <rva>`
(walk the static dvar arena → every registered dvar with type/flags/domain/current/reset) · `resolve.py`
(name the hashes: BO4 list + every dump literal) · `regmap.py` (every `mov r64, imm64` hash immediate →
registration site) · `xrefs.py lo hi` (who reads a pointer slot) · `callers.py rva…` (E8 callers) ·
`disasm.py rva:len` (capstone with dvar/rip annotations) · `fnv.py` (fnv1a63, dvar/asset names) ·
`t89.py` (the T8/T9 script hash for builtin names). CW `dvar_t` = 0x40 B: hash@0, hashnext@8,
DvarData*@0x10 (4 × 0x20: current/latched/reset/spare), type@0x18, flags@0x1c, domain@0x20.

## Untried — not ruled out
- Whether `setvelocity` at `slide_begin` survives the same frame's movement (the probe's `ev`/`poll` +
  `d` answer it). Whether joiners see a snap.
- Locating `[pm+8]` (the `{ms, speed}` table) — via a Pmove caller not wrapped by Arxan, or a
  client-side (`cg`) reader of the same `+0x8c` table.
- AE stat 0xc4 from script: does MP ship any talent that carries it (`hastalent` sweep of the ZM tier
  names on an MP map); does `addtalent( #"talent_staminup_tier" )` link in MP.
- The two unnamed slide BOOLs (`4b70…`, `34c8…`) and the one after `slide_forcebaseslide` (`22c4…`, 0):
  dictionary passes with ~250 words failed; the first is the chain-penalty gate by disassembly.
- `weaponScale` (`weaponDef+0xa38 → +0xcbc`): which weapons/attachments actually differ (a per-weapon
  `v0` on the line would show it).

## 6. In the menu — the fun pack (2026-09-23, never run)
`gunfight_menu.gsc` Movement → **Slide**: speed 150 / 200 / 300 % (lever 1, the boost at the slide's start),
**Long slide** (lever 1's hold), **No chain penalty** (lever 2, `slide_subsequentslidescale 0`), and
**Super slide** — Project HiNAtyu's idea (it adds +125 u/s along the view every 0.05 s, no ceiling),
rebuilt as a fixed glide speed along the view until JUMP. [[fun-pack]]

⚠ **The menu detects the slide with `issliding()`, not `isonslide()`.** `issliding()` is what stock's own
slide-kill challenge reads (`challenges_shared.gsc:2729` / `:2754`), and `bot_stance.gsc:58`. `isonslide()`
has one stock caller, a vehicle's `touch` handler (`player_vehicle.gsc:1962`), and may mean something
else (on a slide *surface*?). `src/slide_probe/` polls `isonslide()` — **if its `poll` counter stays at 0
while `ev` counts, this is why**; switch the probe to `issliding()` before concluding anything.

