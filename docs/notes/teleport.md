# Teleport — everyone to a point, me to a point, the teleport gun / grenade. 2026-09-15

Goal (klaze): *"teleportation mods, such as teleport all to point or all to me, and maybe the classic
teleport gun mod."* Read out of the T9 dump and the shipped Atian Cold War menu; **built into
`gunfight_menu` (the *Teleport* hub + three per-player rows + app buttons), nothing measured in-game
yet.** Every claim below is a source reference; the test sheet is at the bottom.

**Status: BUILT, UNTESTED. The move itself is three builtins stock uses on players in retail MP; the
two hooks the gun and the grenade ride are stock notifies with retail waiters. The open questions are
all about placement quality (floor sweep, the ring), not about whether a player moves.** Payload
`gunfight_menu.gscc` 259,919 B / 1,592 strings (2026-09-15, with the per-client page, the roster
publish and the asset census built the same evening); `check-gsc` PASS, `check-args` 0 mismatches.

---

## 1. Moving a player is three builtins, in a fixed order — stock's own MP fast-travel

There is no "teleport" builtin. Stock moves a player with `setorigin`, and the one retail MP system
that does it to a *live* player — the red-door fast travel, `mp_common/red_door.gsc` — wraps it the
same way at both of its call sites:

```gsc
// red_door.gsc:492 function_2aed1d83( s_dest )          // and :155 function_fdb3b5
self dontinterpolate();                 // the client snaps instead of lerping across the map
self setorigin( s_dest.origin );
self setvelocity( ( 0, 0, 0 ) );        // :496 - the old momentum survives a setorigin
self setplayerangles( s_dest.angles );  // :159
```

All four are engine methods on the player (`reference/funcs_cw.csv`: `setorigin` exe+4377880,
`dontinterpolate` exe+5d4e0a0, `setvelocity` exe+43a42f0, `setplayerangles` exe+43b5fa0) and none is
shadowed by a script function anywhere in the dump (grepped, per the validator hole
`gunfight-map-marker-debug` measured 2026-09-15). The mod already does the middle two on every
guarded spawn (`mod_spawn_place`, the legacy teleport path) — so the primitive is not new here, only
the ordering and the velocity kill are.

Server-side entity state: a **vanilla joiner is moved exactly like the host**, no client script
involved. That is the whole feature's joiner story and it is the good case (game-systems §2).

### Precedents for the *tools*, not just the move

| tool | precedent | where |
|---|---|---|
| everyone → a player, in a ring | the dev warp (`scr_playerwarp`): spirals every player in front of the target, floors each spot with a down-trace, faces them at the target, `setgoal` for bots | `dev.gsc:279 function_30d59c86`, spiral in `dev_shared.gsc:1078` — `/# #/`, **compiled out of retail**, so it is a design reference only |
| teleport gun | the Atian Cold War menu's `tpgun`: `waittill( "weapon_fired" )` → eye-forward `bullettrace` 10000u → `setorigin( position )`; in fly mode it moves the fly anchor instead (`future_tp`) | `t8-atian-menu/scripts/core_common/threads/gun.gsc:5-60`, `threads/fly.gsc:25` |
| teleport to a point | Atian `func_teleport( item, origin, angles )` — the same three lines plus the fly-anchor case | `coldwar/scripts/core_common/menu_funcs.gsc:740` |

## 2. Two things a bare `setorigin` gets wrong — handled in `tp_place` / `tp_floor`

**A flying player is linked.** Fly mode is `playerlinkto( script_origin )` and a linked entity's
origin belongs to the link; the Atian menu's answer is to move the anchor (`self.originObj.future_tp`,
consumed by its fly loop). `fly_think` now stores its anchor as `self.gf_fly_anchor` (cleared by
`fly_cleanup`) and `tp_place` moves that when the player is flying. A player in a **vehicle** is
skipped — the seat owns him (`getvehicleoccupied()`, the check `player_damage.gsc:1436` makes).

**A point on a wall or in the air is not a standing spot.** The classic gun leaves you half inside
the surface or falling. Two corrections, both from stock:

- the aim point is pushed **12u out along the hit normal** (`trace[ #"normal" ]`, 26 stock readers)
  so a wall shot lands beside the wall;
- the destination is then dropped onto the **floor under it** with `playerphysicstrace( top, bottom )`
  — the capsule sweep Prop Hunt uses to decide where a prop re-materialises as a player
  (`_prop_controls.gsc:1260-1265`, from the origin down 2000u; Demolition uses it to find the floor
  under water, `dem.gsc:1135`). It returns the feet origin, or `undefined` / the segment end when it
  finds nothing; a plain `bullettrace` floor is the fallback, and the raw point after that (mid-air:
  the player drops, the OOB timer or the ground sorts it out — every menu's teleport behaves so).

⚠ **Unmeasured:** what `playerphysicstrace` returns when the sweep *starts* in solid (a low ceiling
16u above a floor point). Guarded by preferring a result above the segment's bottom, then the
bullettrace; if a test shows players placed in a ceiling, the lift (`+16`) is the number to lower.

## 3. The ring — "all to me" without a pile

`tp_ring_spot( centre, i, n )`: one ring, radius 80u (grows as `80·n/6` past six players so nobody
overlaps), spot `i` at `360·i/n` degrees, each floored by §2. A spot is rejected — and the **centre
itself used** — when its floor is more than 128u off the centre's (off a ledge, through a floor) or
when there is no clear chest-height line from the centre to it (`bullettracepassed`, +40u, the 24-site
stock visibility test). Players at the fallback overlap and walk apart; the MP engine does not
telefrag, it resolves the overlap.

Everyone moved faces the centre (`vectortoangles( centre - spot )`), so "all to me" produces a ring
looking at the host — the dev warp's own choice. Bots are moved like anyone else, deliberately: a
solo host with bots is how this gets tested.

Who moves: every player alive, not the host, not spectators (`player.team == #"spectator"`), not
vehicle seats (reported by name); `team` / `enemy` filters are relative to the host's side, so they
survive a side switch.

## 4. The teleport gun and the teleport grenade — two stock notifies

**Gun.** The engine raises `weapon_fired` on the player for every shot:
`weapons.gsc:1034 event_handler[weapon_fired]` → `callback::callback( #"weapon_fired" )`, and the
plain notify that `placeables.gsc:215` waits on (`waitresult.weapon` is the weapon). The mod uses the
notify, per player, per life:

```gsc
self waittill( #"weapon_fired" );
pos = self tp_aim();                       // eye + forward·10000, hitcharacters, normal push
tp_place( self, tp_floor( pos ), undefined );   // keep the view angles
```

Full-auto is one move per bullet — the classic feel; a miss (sky, fraction 1) moves nobody. ⚠ The
menu's *next item* key is ATTACK (`keys_init`), so a shot fired while the host's menu is open is a
menu press and is ignored (`tp_menu_open()` = `self.gfmenu.current != ""`); joiners have no menu. A
`callback::on_weapon_fired( &f )` registration (`callbacks_shared.gsc:899`, threaded per shot by
`_single_thread`) would do the same level-wide; the notify keeps it a plain per-player thread with an
`endon( #"death" )`, re-armed on every spawn by `mod_spawn_place → tp_spawn_rearm`.

⭐ Untried variant for later: `callback::add_weapon_fired( weapon, &f )` (`callbacks_shared.gsc:1417`)
is a **per-WEAPON** hook keyed on the weapon or its `rootweapon` — "only the pistol is the teleport
gun" is one registration away.

**Grenade.** `grenade_fire` hands over the projectile (`weapons.gsc:1583` raises it; Prop Hunt reads
`res.projectile` / `res.weapon` at `_prop_controls.gsc:1820-1822`), and the projectile's `explode`
carries the detonation point (`res.position`, `_prop_controls.gsc:1836-1837`). The mod waits on
`explode` **or** `death` and moves only on `explode` (`waitresult._notify == "explode"`, the
`empgrenade.gsc:252` idiom) — a grenade thrown back or fizzled moves nobody. Tacticals detonate too
(concussion / stun: `explode`), so either Gunfight equipment slot works.

**Everyone modes** exclude bots (a bot fires constantly — it would teleport all over the map on every
burst) and live in `game.` (`game.gf_tpgun_all`, `game.gf_tpnade_all`) so they survive the round
boundary and reset at match end; the host's own toggles are `self.gf_tpgun` / `self.gf_tpnade`
(player fields persist across rounds — `self.gfmenu` already relies on it). The saved point is
`game.gf_tp_point` for the same reason: save it in round 1, use it in round 3.

## 5. What the menu has (Teleport hub, `gunfight_menu.gsc`) and the app

| page | rows | verb |
|---|---|---|
| Teleport → *Everyone to...* | All to me · All to my crosshair · All to saved point · All to map centre · My team to me · Other team to me · My team to crosshair · Other team to crosshair | `act_tp_all( item, where, who )` |
| Teleport → *Me to...* | Me to crosshair · Me to saved point · Me to map centre · Save point = where I stand | `act_tp_me( item, where )`, `act_tp_save` |
| Teleport → *Teleport gun / grenade* | Teleport gun – host · – everyone · Teleport grenade – host · – everyone (toggles) | `act_tpgun( item, who )`, `act_tpnade( item, who )` |
| Players → *\<name\>* | Teleport to me · Teleport me to them · Swap places with me | `act_tp_player( item, player, verb )` (rows live in bocw-95's `client_page_build`) |

"Map centre" is `level.mapcenter` (`globallogic.gsc:5500`, the minimap box centre — the point stock's
fourth spawn path piles players on, so it is survivable), floored.

App (`tools/gf-control`, Actions tab): a *Teleport* box with the same verbs over `gf_cmd_action` —
`tpall` / `tpteam` / `tpenemy` (arg `me|aim|saved|centre`), `tpme` (arg `aim|saved|centre`), `tpsave`,
`tpgun` / `tpnade` (arg `host|all`, toggles) — and three *Player by name* buttons (`tpplayer` with
`gf_cmd_target`, arg `tome|metothem|swap`). "Crosshair" from the app is wherever the host is aiming when
the command lands.

## 6. Unknowns — measurements, not reasoning problems

1. **`dontinterpolate` reach.** It is what stock calls before its own player teleport; whether a
   *joiner's* view snaps or lerps without it is a client detail we cannot read. Harmless either way.
2. **`playerphysicstrace` in solid** (§2). Watch for a player placed inside a ceiling after a
   crosshair shot at a low overhang.
3. **The fallback pile.** Two players at the same origin: expected to push apart within a frame or
   two; a test that leaves someone stuck means the fallback should scatter (±16u) instead.
4. **Freeze / pre-round.** `setorigin` on a `freezecontrols` player is expected to move him (it is
   entity state, not input); the pre-round freeze window is the natural place to gather everyone.
5. **Out of bounds.** A crosshair shot past the play space moves everyone into the OOB timer.
   Expected and left alone; `getnearestpathpoint( pos, 256 )` (`_prop_controls.gsc:1378`, the
   Prop Hunt validity test) is the snap-to-playable-space upgrade if it annoys.
6. **No sound / FX.** Nothing plays on a move. `playfx` is reachable server-side ([[projectiles]] §3)
   if a flash is wanted; no alias was chosen because none is known resident on every MP map.

## 7. Test sheet

⚠ **First run 2026-09-15 (klaze, 269,790 B): "teleport everyone to me just restarts the match."** Diagnosis
(peer session, refined by klaze's second read): *My team to me* and *Other team to me* both work, only
*All to me* restarts — so overlapping `setorigin` does not telefrag and one side point-blank is fine; with
BOTH sides dropped into one cluster in the same frame they annihilate each other simultaneously, both teams
are dead at once, and Gunfight resolves a double elimination by reloading the match. Fixed in 283,546 B:
every mass-teleported player (and the host, when enemies were brought in) gets 1.5 s of
`enableinvulnerability` (`tp_grace`, god mode left as it was), so the round resolves normally; and a failed
ring position now shrinks toward the host (80 → 48 → 24 u) with a 16 u nudge as the last resort, so a tight
spot no longer stacks everyone on one point. Re-test T3–T5 (T4 = *All to me* is the one that failed).
 — one match, bots, Gunfight

Inject `gunfight_menu`, restart, fill with bots. Each line is one press; record what happened.

| # | do | expect | result |
|---|---|---|---|
| T1 | *Me to...* → Save point; walk 30 m; *Me to saved point* | you snap back, facing as saved | |
| T2 | aim at a floor 20 m away → *Me to crosshair* | you stand there, view unchanged | |
| T3 | aim at a WALL at chest height → *Me to crosshair* | beside the wall, on the floor (not inside, not falling) | |
| T4 | aim at the sky → *Me to crosshair* | "aim at something first", no move | |
| T5 | *Everyone to...* → All to me | bots in a ring ~2 m out, all facing you; feed says N moved | |
| T6 | All to my crosshair (open ground) | ring around the aim point | |
| T7 | All to my crosshair (a doorway / narrow spot) | some at the centre (fallback), nobody in a wall | |
| T8 | All to map centre | everyone at the minimap centre, on a floor | |
| T9 | Other team to me / My team to me | only that side moves | |
| T10 | Fly ON, then All to me / Me to crosshair | you move while still flying (anchor moved) | |
| T11 | *Teleport gun – host* ON, shoot the floor / a wall / the sky | move / move beside / nothing | |
| T12 | *Teleport gun – everyone* ON | bots do NOT teleport; a human joiner does | |
| T13 | die, respawn next round with the gun ON | still a teleport gun (re-armed on spawn) | |
| T14 | *Teleport grenade – host* ON, throw a frag; throw a stun | you appear at each detonation | |
| T15 | Players → a bot → Teleport to me / me to them / Swap | in front of you facing you / in front of them / positions exchanged | |
| T16 | app: Actions → Teleport → All to me | same as T5 with no menu open | |

A joiner run adds: does a moved joiner see himself moved (T5 from his side), and T12.

## Untried — not ruled out

- per-weapon teleport gun via `callback::add_weapon_fired` (§4)
- snap destinations to `getnearestpathpoint` (§6.5)
- a `playfx` / sound on the move (§6.6)
- "everyone to spawns" (each side to its `mod_spawn_next_anchor()` — the spawn guard already has the lists)
- teleport as a *round tool*: gather both teams at a chosen arena for a 1v1 in the OT zone
