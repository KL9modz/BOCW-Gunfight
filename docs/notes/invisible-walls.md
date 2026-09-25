# Invisible walls — the map's player clip, and the `gf_invwall` switch (2026-09-24)

> **Status: MEASURED 2026-09-24 22:02-22:05, klaze, Diesel (mp_sm_gas_station) TDM:** with the switch OFF
> (`perk 1/1` in the log) **the ceiling passes**, but **some vertical walls around the map still block**.
> Those are not player clip. klaze's read of them is case 2 of §4: clip that also carries utility clip,
> which bullets pass and the perk cannot remove. His call: *"if we cant do anything easily then just make
> invisible-walls ON by default"*. So **`gf_invwall` defaults to 1 (walls OFF)** in the GSC, the menu (OFF row
> first) and the panel Schema. Everything else below was read off the live exe (dated 2026-06-12) with
> `tools/dvar-live` (read-only). The test sheet is §5.

klaze, 2026-09-24: *"create a toggle off by default to disable invisible barriers. most maps have one in
the sky as a ceiling and vertical ones around the map"*. The three map-edge systems:

| System | What it does | Switch |
|---|---|---|
| Out of bounds (`trigger_out_of_bounds`) | "Restricted area" HUD warning, countdown, death | `gf_oob`, default OFF ([[game-systems]] §14d) |
| Death barriers (`trigger_hurt`) | Instant death off a ledge, in water, under the map | `gf_deathbarrier`, default OFF ([death-barriers.md](death-barriers.md)) |
| **Invisible walls (player clip)** | **Physically blocks you: the sky ceiling, the walls at the edge** | **`gf_invwall`, default OFF since 2026-09-24 (this note)** |

## 1. What an invisible wall is (read off the exe)

The engine's material infoParm table at **`exe+0xd66b340`** (rows of `{name*, surfaceFlags, contents}`,
stride 0x18) names every contents bit a map brush can carry:

| infoParm | contents | | infoParm | contents |
|---|---|---|---|---|
| `playerClip` | **0x10000** | | `utilityClip` | **0x100000** |
| `vehicleClip` | 0x200 | | `playerVehicleClip` | 0x40000 |
| `aiClip` | 0x20000 | | `playerSightClip` | 0x80000 |
| `bulletClip` | 0x2000 | | `missileClip` | 0x80 |
| `itemClip` | 0x400 | | `canShootClip` | 0x40 |
| `sky` | 0x800 | | `glass` / `water` / `foliage` | 0x10 / 0x20 / 0x2 |

A living player's movement mask is written in two copies of one routine: **`exe+0x6bca4cb`** and
**`exe+0x8e6d097`** (`mov dword [pm+0x128], 0x00a18011`). 0x00a18011 = solid 0x1, glass 0x10,
**playerClip 0x10000**, and 0x8000 / 0x200000 / 0x800000. No material sets those three, so they are
engine-assigned entity contents. The dvar `0x40094bd3441364e0` (BOOL, current 1) then drops 0x800000.
A dead player gets `0x210011` (no player clip); pm_type 5 drops the player-only bits and adds sky.

**The sky bit (0x800) is not in a living player's mask.** So a ceiling a jump hits is player clip, like the
walls around the edge. It is not the skybox.

## 2. The lever: perk 0xa2

Right after writing the mask, both copies test perks through `exe+0xb625030` (= HasPerk(ps, index); its only
callers are this wrapper and `exe+0xb625050`, per `callers.py`):

```
if ( bg_zombieplayerusesutilityclip && HasPerk( ps, 0x50 ) )  mask = mask & ~0x10000 | 0x100000
if ( HasPerk( ps, 0xa2 ) )                                    mask = mask & ~0x10000 | 0x100000
```

The perk table is at **`exe+0xeb26500`** (fnv1a63 hashes, index = position). Index 0x50 is
`specialty_playeriszombie`. Index **0xa2 is unnamed: `#"hash_3a09b1d7eaa88087"`**. Atian's `perks_cw.txt`
line 163 agrees with both indices, and a curated 1-3 word crack found no name.

A scan of every E8 call to the perk tests, with the index loaded just before:

- **Perk 0x50** has 17 checks, including 15 outside the mask (side effects: the zombie-player state).
- **Perk 0xa2** has 2 checks, both on the mask lines. It swaps player clip for utility clip and does nothing else the scan can see.

No stock script uses it (dump grep). `setperk` takes a hash, and the menu already calls `setperk( #"specialty_fallheight" )`.

## 3. What the menu does

- **INVISIBLE WALLS block** in `gunfight_menu.gsc`: `mod_invwall_apply` sets / strips perk 0xa2 on a living player.
  - Called from `mod_spawn_movement` (every spawn: stock's loadout give runs `clearperks`, `gunfight.gsc:343`) and `mod_movement` (the app's `apply move`).
  - `sandbox_watch` re-grants it every second while on, since a mid-life class change re-gives the loadout.
  - "Stock" strips only the perk this set (the per-player `gf_invwall` mark).
- **Menu:** Movement → Invisible walls (host menu only; granted clients never reach the Movement page).
- **App:** RULES → MOVEMENT → Invisible walls (`gf_invwall`, Scope `move`). The readback goes in the GFCFG `misc=` list, the last field.
- **Debug:** the BARRIER line (`gf_dbg_barrier 1`) now ends its census with `walls:<0|1> iw:<held>/<alive>`, and its host part with `iw:<0|1>`.
- **Status line** (menu state): `walls stock|off`; the enabled-flags line shows `nowalls`.

**Still blocks with walls OFF:**
- world geometry (solid), glass, other players, vehicles (the engine-assigned entity bits);
- a vehicle's own collision (vehicle clip; the perk is on the player, not the vehicle);
- **utility clip**, which the perk ADDS to the mask. It is the zombie clip; no MP map is known to carry it.

## 4. Unknowns

- **The walls that still block (Diesel, 2026-09-24).** With the perk held, the player's mask is solid 0x1, glass 0x10,
  0x8000, utilityClip 0x100000 and 0x200000. A wall that still blocks is one of three kinds:
  - pure **utility clip**: it would NOT block with the switch on Stock;
  - a brush with **both** player clip and utility clip: it blocks either way, and bullets pass;
  - **invisible solid**, or a script entity: it blocks either way, and bullets stop.

  Diesel is not on `zonslaught.gsc`'s Onslaught map list, so zombie clip from Onslaught is not the obvious source there. No GSC call and no engine mask path (except spectators, pm_type 5) drops utility clip for a living player.
- Reading Diesel's clip-map from memory: CLIP_MAP is pool 24 at `exe+0x1273c9f0` (0x20-byte XAssetPool, header 0x1d8 bytes).
  - Header `+0x40` = pointers into pool 7 (XCOLLISION, the static models).
  - No parallel per-brush contents array matched the header counts; the T9 brush layout is still unknown.
- Whether passing a ceiling leaves you standing on top of it. Clip is solid from both sides, but with the perk the player ignores it in both directions, so a fall should drop straight back through.
- Client prediction: both mask copies read the playerstate's perk bits (networked), so the client and server should agree. Unmeasured.

## 5. Test sheet (one match, any map)

1. RULES → MOVEMENT → Invisible walls: **Off - walk through them** (or menu Movement → Invisible walls OFF). The menu says `invisible walls OFF - player clip ignored (perk N/M)`: N should equal M.
2. Jump boost **Insane ~3000u**, jump in the open: does the ceiling stop you? (Before: yes.)
3. Walk or slide into a map-edge wall: do you pass? Out of bounds and death barriers are already off by default.
4. With `gf_dbg_barrier 1`: if something still blocks, send a screenshot of the BARRIER line. Check `iw:1` on the host part.
5. Back to **Stock**: the walls block again (`perk 0/M`).
