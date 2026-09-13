# Hint panel — the menu drawn by the use-prompt widget (`gf_menu_region 4`)

**Built 2026-09-13, never run.** A fourth layout for `src/gunfight_menu`: the whole panel is one
`sethintstring` on a `trigger_radius` linked to the host, rendered by the stock use-prompt widget. It is
the layout every "full HUD" Cold War GSC menu actually uses, and it sidesteps the feed's ~4-line cap and
fade entirely. Payload rebuilt with it (`/c/bocw/payloads/gunfight_menu.gscc`, 130,031 bytes, 815 strings
stripped; the 01:12 build is kept as `gunfight_menu.pre-hint-0112.gscc`). Default region is unchanged
(0), so the new build behaves exactly as before until *Display → Layout: HINT panel* is picked.

## Why this is the ceiling for GSC text on Cold War

- **T9 retail has no hudelem builtins.** `reference/funcs_cw.csv` (4,482 functions dumped from
  `BlackOpsColdWar.exe`) has no `newclienthudelem`, `newdebughudelem`, `settext`, or hudelem `setshader`.
  Stock `scripts/core_common/hud_util_shared.gsc`'s font/bar builders (`function_665f547d`,
  `function_7a0dd8a9`, …) are `Type: dev` and call `newdebughudelem` — compiled out of retail.
- So a server script has exactly three **free-text** channels: the feed (`iprintln`), the centre line
  (`iprintlnbold`), and a **hint string on a trigger the player stands in**. There is a fourth channel
  for *widgets*, measured live 2026-09-13 (bocw-06 / klaze): `luinotifyevent` on a stock event makes
  the client's shipped LUI draw its own widget — `esports_game_paused` put the TIMEOUT overlay up —
  but those take string hashes and numbers, not free text (a countdown via `create_prematch_timer`,
  yes; a menu row, no). Catalogue and call shapes: [[lui-events]].
- The open menus confirm it (read from source, [[ecosystem-survey]]): SoCanKam's PS4/PC menu
  (`socankam/ColdWarGSCMenu` `initmenu.gsc`) has two styles — *Default* = `spawn("trigger_radius", …)` +
  `triggerignoreteam` + `setvisibletoplayer(player)` + `sethintstring(<title + 15 items + page/keys>)`;
  *iPrintlnBold* = 4 items per page with `.` lines to flush, our feed menu exactly. Lucy-Base
  (`AuroraDoesCode/ColdWar-Lucy-Base` `menu.gsc`) packs 8 items per hint string. Neither uses a HUD element.
- The boxed, highlight-bar menus seen on jailbroken PS4s ("T9 Cheater", 1.27) are **native C++ payloads**
  drawing through the renderer (NickBeHaxing's release text: "jam packed C++ project for cold war ps4") —
  a DLL-domain thing, not a GSC one. [[tac-risk-model]] is where that belongs if it is ever weighed.

## What was built — `gunfight_menu.gsc`

| Piece | What it does | Stock shape it copies |
|---|---|---|
| `menu_hint_trigger()` | spawns `trigger_radius` (r 96, h 128) at the host, `setcursorhint("HINT_NOICON")`, `triggerignoreteam`, `setvisibletoplayer(self)`, `setmovingplatformenabled(1)` + `enablelinkto` + `linkto(self)`; stored as `self.gfmenu_hint` | `mp_common/gametypes/ctf.gsc:637-639` (trigger + hint + no icon), `mp_common/laststand.gsc:1463-1469` (trigger that follows a player — the revive prompt), `mp_common/gametypes/vip.gsc:1433-1435` (`setvisibletoplayer` on a trigger_radius) |
| `menu_render_hint()` | header (root: state line; sub-page: name + compact state) + a cursor-centred window of `gf_hint_lines` rows via `menu_item_line` + footer (position, key legend, last action); rows joined by ` ^8\| ` or `\n`; one `sethintstring` | — |
| `menu_hint_hide()` | deletes the trigger (menu closed, or layout changed away from 4), retires the watchers | — |
| `menu_hint_cleanup*` | delete the trigger on host `disconnect` / level `game_ended` | `laststand.gsc:353-356` deletes its trigger the same way |
| `menu_paint` / `menu_say` | region 4: panel never goes to the feed; confirmations fold into the footer while open, go to the centre when the menu is closed | — |
| Display rows | *Layout: HINT panel* · *Hint rows 6 / 8 / 12* · *Hint rows: packed / newlines* | — |
| dvars | `gf_hint_lines` (8) · `gf_hint_newlines` (0) | — |

`setvisibletoplayer(self)` is what keeps a joiner who walks up to the host from reading the panel — the
hint is a **replicated, stock** mechanism, so without it the trigger would show its text to anyone
inside it. (That same property is the upside: `sethintstringforplayer` could put a line in front of a
joiner — the first host→joiner text channel this project has. Not built.)

Compile: `acts gscc … -g cw -p pc` clean; `tools/check-gsc.ps1` resolves every new call (`sethintstring`,
`setcursorhint`, `triggerignoreteam`, `setvisibletoplayer`, `setmovingplatformenabled`, `enablelinkto`,
`linkto`, `delete`); the `"\n"` literal is a real `0x0A` byte in the string table, and `strip-strhdr`
handles it (815/815).

## What is unmeasured — the test (one match, host only, ~5 minutes)

1. Open the menu (RMB+V) → Display → **Layout: HINT panel**. The panel should appear in the use-prompt
   widget (where "Hold F to …" prompts draw), no icon, feed untouched. ❓ *Does it show at all?* If the
   widget stays empty, the trigger hint is not being displayed for the host standing in his own trigger —
   try `sethintstringforplayer( self, txt )` on the trigger next (`sethintstringforplayer,2,4` in
   funcs_cw.csv), then Lucy's form `self sethintstring( txt )` on the player.
2. **Walk, sprint, jump, slide.** ❓ *Does the panel stay up while moving?* If it drops out, the
   linked trigger's touch test is not following — replace the link with `trig.origin = self.origin` on
   each repaint (SoCanKam's form; 2 s idle repaint + every key press).
3. Display → **Hint rows: newlines**. ❓ *Does the widget honour `\n`?* One long line = no; then leave
   `gf_hint_newlines 0` (packed rows, the proven form) and forget it.
4. Display → **Hint rows 12**, open the Maps page (36 rows). ❓ *Where does the string truncate?* Set
   `gf_hint_lines` to the largest count that renders whole.
5. **Die, and spectate**, with the menu open. ❓ *Is the panel visible while dead / in the pre-round
   countdown?* (The revive prompt is drawn for living players; the host's own case is unknown.)
6. Close the menu (V at root). The widget must clear (trigger deleted). Reopen: fresh trigger.
7. Have a joiner stand on the host with the menu open. ❓ *Joiner sees nothing?* — the
   `setvisibletoplayer` guard. This is the one that matters for the "friends play vanilla" rule.

Record the seven answers in this note; steps 1–2 decide whether the layout exists, 3–5 tune it.

## Untried — not ruled out

- `sethintstringforplayer` as a **per-joiner status line** (e.g. "next: mp_miami — gunfight") — the
  replicated channel the feed can never be. Same trigger, one call per player.
- `setcursorhint( "HINT_INTERACTIVE_PROMPT" )` (`gameobjects_shared.gsc:113`) instead of `HINT_NOICON`
  if the no-icon widget turns out to clip long text.
