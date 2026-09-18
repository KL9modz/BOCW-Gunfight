# The in-match pause menu, read from source (2026-09-17)

klaze: *"investigate leveraging the in-match pause menu GUI for our own menu."* The pause menu's Lua
is now readable ([lui-source](lui-source.md), `C:\bocw\lui-source\`), so this is no longer guesswork.
Two questions: **can we read what the pause menu is** (yes, done below), and **can we put our own rows
in it** (a real route exists, one write primitive from testable — it was never reachable before).

## What the pause menu actually is

The in-match Start menu is `LUI.createMenu["#StartMenu_Main"]` (`lua/core_ui_1029_01e46770.lua`),
opened by the HUD root `core_ui_1547` (`HUD_OpenInGameMenu`) when the engine raises the start-menu
event. It is **client Lua**, not GSC and not a `luielem`/`hudelem`. Its structure:

- A tab bar whose rows come from the **data source `arena_playlist_game_modes_maps`-style feed** — the
  Start menu's is `#hash_520bbde6a8d0a9ac` (`SafeAreaContainer.TabBar.Tabs.grid:setDataSource`), a
  DataSources entry, not a static list. Each tab is a `StartMenuOptions*` element.
- Buttons that talk back to the host GSC through **`Engine.sendmenuresponse(controller, menu, response,
  intpayload)`** — the client→server channel `callbacks_shared.gsc:2054` queues and
  `mp_common/gametypes/menus.gsc:on_menu_response` consumes. The stock in-game responses, read straight
  out of the Lua (`grep sendmenuresponse lua/*.lua`):

  | menu | response | what GSC does with it |
  |---|---|---|
  | `StartMenu_Main` | `menu_opened` | the menu just opened (host bookkeeping) |
  | `StartMenu_Main` | `restartmission`/`restartcheckpoint`/`returntosafehouse` | campaign only |
  | `popup_leavegame` | `endround` / (the leave popup's yes) | `menus.gsc` → `globallogic::forceend()` |
  | `InGameConfirmOverlay` | `confirmresponse` `0/1` | the generic yes/no (CP driver `globallogic_ui.gsc:327`) |
  | `changeteam` / `menu_team` | a team name | `teams::change` path |
  | `spectate` | `clientNum` | spectate that client |

  ⚠ Every `menuNameHash`/`response` here is a hashed string; `menus.gsc` compares against the same
  hashes. A **new** response string is free — `menus.gsc` `register_menu_response_callback(menu, cb)`
  already lets a mod register a handler for any `(menu, response)` it likes.

## The free-text popup — the immediately useful find

The project's standing rule is that server GSC has no free-text HUD channel above the ~4-line feed and
the one-line hint ([lui-elems](lui-elems.md): `luielem` text is localize-key-only, a plain string is a
fatal crash). **The pause-menu popups are an exception, and it is reachable from host GSC today with no
client payload.**

`lui_shared.gsc:1040` `open_generic_script_dialog(title, description)` does
`openluimenu("ScriptMessageDialog_Compact")` + `setluimenudata(dialog, #"title", title)` +
`#"description"`. In the Lua, `ScriptMessageDialog_Compact` (`core_ui_1456:1566`) is a compact-dialog
popup (`menuNameHash #hash_614b2059f27f812d`, `core_ui_1136`) whose title/description frames
(`core_ui_1145/1147/1148/1150/1151…`) render the model value through **`BaseUtility.#hash_1993de65911eb3f`**:

```lua
CoD["#BaseUtility"]["#hash_1993de65911eb3f"] = function (v)   -- core_ui_1364:403
    if type(v) == "xhash" then return Engine.Localize(v) end   -- a hash -> localize
    return v                                                    -- a plain string -> AS-IS
end
```

So a **plain GSC string reaches the screen verbatim** — it is only localized if it is a `#"hash"`. This
is a titled popup with a description line and a Close/Cancel button, drawn by stock client Lua, driven
entirely from host GSC (`openluimenu`/`setluimenudata` are server builtins, `funcs_cw.csv`). It is a
genuinely new free-text channel, unlike the crash-on-plain-string `luielem` path.

⚠ **Read, not measured.** The exact contract to test in-game, on a throwaway launch:
1. `player thread lui::open_generic_script_dialog( "Gunfight Host", "Timer 60s\nTeams 4v4\nMap Hijacked" )`
   — does the plain text render, and does `\n` work (the description element may be multi-line)?
2. Is it **host-only or does it reach a vanilla joiner?** `openluimenu` is on a player entity and the
   menu state is per-client; plausibly per-player-replicated like the hint banner, but untested.
3. `InGameConfirmOverlay` (title is force-localized there, `core_ui_1403:1519`, but description via the
   same conditional helper) is the yes/no variant — its `confirmresponse 0/1` already round-trips to
   GSC, so it is a **host-GSC modal with a callback**, i.e. a real menu primitive, not just a banner.

If (1) renders, the mod menu gains a proper popup surface (title + body + button) for free, and if (3)
works the menu can be *interactive* from GSC with no client payload at all — a strict upgrade on the
feed/hint menu the project ships today.

## Putting our own rows in the pause menu — the real route

Three ways to get custom content into the Start menu, cheapest first:

1. **Drive stock responses / a stock popup from GSC** (above) — no new Lua. A popup and a yes/no modal,
   host-side. This is the one to test first; it may be all that's wanted.
2. **A DataSources row.** The tab bar and most lists are `DataSources` feeds keyed by hash. A client
   `.csc` that runs `DataSources.<x> = CoD.CreateDataSourceSisterAttachment(...)` (the stock idiom,
   `core_ui_1477`) could add a tab/row — but DataSources is client-side, so this needs the **client
   payload** the project already ships for `luielem` (`src/gunfight_menu_c`, hooked at
   `load_shared.csc`), and the row's *action* still has to `sendmenuresponse` back to GSC. Heavier;
   only worth it if the popup route is too limited.
3. **Inject our own menu chunk** (`tools/lui/luapool.py --inject`, [lui-source](lui-source.md)). We can
   now *compile* a T9 LuaJIT chunk (`lj2t9.py`) that does
   `LUI.createMenu["#StartMenu_Main"] = <orig + our rows>` or defines a brand-new menu, and write it
   into the live `luafile` pool exactly as `injectcw` writes GSC. The open question is the **load
   trigger**: a stock `require`/`luiload` of that asset name from an injected `.csc`
   (`luiload("x64:HEX.lua")`), since the UI has already loaded at match start. This is the most powerful
   route (arbitrary UI, our own widgets, colours, layout — the boxed menus other cheats draw) and the
   most work, and it writes game memory, so it is **klaze's to run, and only after the read-only popup
   test settles whether it's even needed.**

⚠ **Scope guard.** The write primitive (`luapool.py --inject`, memory allocate + write) is klaze's to
run, same as every DLL/memory-write in this project. The agent built and read-tested the tools and the
GSC-side popup call; the in-game runs (popup render, joiner visibility, chunk-inject load) are the
human's.

## Untried — not ruled out

- `open_generic_script_dialog` / `InGameConfirmOverlay` plain-string render + `\n` + joiner visibility
  (the three tests above). This is the cheap, high-value one.
- `luapool.py --inject` + `luiload` from the client payload — does an injected chunk load mid-match.
- A **new** `(menu, response)` pair: register `menus.gsc:register_menu_response_callback` for it in the
  mod and fire `sendmenuresponse` from an injected menu row — closes the loop for route 2/3.
- The Start-menu **tab data source** `#hash_520bbde6a8d0a9ac` — whether GSC can push a tab into it via a
  clientfield/uimodel the stock client already reads (the [game-systems](game-systems.md) §2 rule).

## MEASURED in-game 2026-09-17 (klaze) — the popup channel

Ran `src/lui_probe/` (host-GSC, no client payload) in a live MP match:

- ✅ **`ScriptMessageDialog_Compact` renders full-screen in an MP match** — `openluimenu` returns a
  handle and the client draws the dialog (the "Intelligence Information Notice" chrome, its
  categoryType = info/notice).
- ✅ **Plain strings do NOT crash it** — the staged run reached `survived:1` with plain
  `setluimenudata(#"title"/#"description", "...")`. This is the opposite of the LUIelemText result
  ([lui-elems](lui-elems.md)) and confirms the read finding: the dialog's title/description frame
  (lui-source `core_ui_1151`, fields `#Title`/`#Description`) renders through the **localize-if-hash**
  helper (`#hash_1993de65911eb3f`), so a plain string passes through verbatim.
- 🪲 **`closeluimenu` does not dismiss the client overlay.** It closes the server handle (returns
  fine, `close:1`) but the drawn popup lingers, and with `blockDuplicateInstance = true` the v1 probe's
  three staged popups masked each other — only the empty first popup ever showed, so the set text was
  never visible ("can't close"). Input is **not** hard-locked (ESC still opens the pause menu over it).
- ▶ The correct dismiss is the dialog's **Back button → a menuresponse**, which runs the client close
  handler (what stock `lui::open_generic_script_dialog` waits for). `src/lui_probe/` v2 opens ONE popup
  with the text set and waits on the player's Back press to answer: (Q1) does the text render, (Q2) is
  the dialog GSC-dismissable. Field names `#"title"`/`#"description"` are confirmed correct against the
  frame (the `#Title`/`#Description` xhashes equal the lowercased-hash of "title"/"description").

**Net so far:** the pause-menu popup is a real, crash-safe free-text surface reachable from host GSC
with no client payload — the first free-text channel above the ~4-line feed / one-line hint. Whether
it is cleanly *usable* (text renders + dismissable) is what v2 measures. The integrated **tab in
`StartMenu_Main`** (klaze's actual target, seen in-game 2026-09-17) still routes through the
client-inject path, gated on the untested `luiload`-of-an-injected-chunk step.
