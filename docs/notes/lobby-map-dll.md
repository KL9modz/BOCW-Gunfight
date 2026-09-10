# An auto-loading DLL for Gunfight-on-any-map, from the lobby

klaze: *"I'd love to have a DLL that auto loads like the one I have that just unlocks the map
selection for gunfight pre game lobby like it does in the glitch."*

**Verdict: reachable, and probably cheap — but one measurement stands between here and writing any C,
and it is free.** Two of the routes this project already had written down are dead, and this note kills
them properly rather than leaving them to be discovered at the machine.

---

## 🪦 Dead route 1 — `acts cwdllgt` is dead TWICE OVER

[`dll-proxy.md`](dll-proxy.md) records the first death: deploying ACTS's `acts-bocw.dll` as
`powrprof.dll` **crashes the game at startup**, three of three, `0xc0000005` at an identical offset.
Diagnosed (attach-time init reads the still-encrypted image) but unfixed — it needs an ACTS source
change and a build.

🪦 **And the second death, found 2026-09-09: the exports it calls do not exist.**
`cwdllgt` (`src/core/acts/tools/cw/cw.cpp:1157`) is only a remote-thread caller — it resolves
`ACTS_EXPORT_SetLobbyGameType` and `ACTS_EXPORT_SetLobbyMap` out of the loaded `powrprof.dll` and
`proc.Exec()`s them. In **current ACTS master**, `src/dll/bocw-dll/main.cpp` declares **exactly one
export**, `CallNtPowerInformation`, and the string `SetLobbyMap` appears **nowhere in the tree**.
`src/dll/bocw-dll/systems/` contains one file, `gsc.cpp`.

⚠ **Verify before acting on this.** The clone here is shallow, so history could not be searched, and
the project pins ACTS at **v3.3.0** — a release binary, not master. The v3.3.0 DLL may still export
them. **This is a 30-second offline check on the test box:**

```powershell
dumpbin /exports ACTS\bin\acts-bocw.dll | findstr /i lobby
```

Nothing back → `cwdllgt` cannot work on this version whatever happens to the crash, and the powrprof
track should be dropped rather than repaired.

⚠ Independent of both, `dll-proxy.md` records that `InitDll` calls `EnableHeavyDump()` and
`InstallErrorHooks(true)`. `.claude/CLAUDE.md` records that **TAC detects API hooks**. That DLL is a
materially larger exposure than GSC injection, and that is a reason to prefer any other route even if
someone does fix the crash.

## ✅ The one slot that works, and what it already proves

[`unlock-dlls.md`](unlock-dlls.md): the game `LoadLibrary`s six DLLs by name, and
**`discord_game_sdk.dll` is the only usable slot** — late-loading, single-export, tolerant of failure,
and it loads *after the exe has decrypted itself*. That timing is the whole trick.

🔓 **cwpatch already executes arbitrary console commands from that slot.** Its mechanism, read out of
the binary with Capstone:

```
locate the game's contiguous command-string blob, verify it starts with `host`
per command:  WriteProcessMemory (overwrite the string with ours)
              call r15            (invoke the game's dispatcher)
              WriteProcessMemory (restore the original 48 bytes)
```

Three candidate slots are used (`hostmigration_start\n`, `checkpoint_restart\n`,
`mission_restart\n`). ✅ **`map_restart\n` and `map %s\n` sit in the same blob** — reconstructed by
cwpatch and left unused. `unlock-dlls.md` already concluded **"the technique extends to arbitrary
commands"**.

So the machinery for "auto-loading DLL fires a command in the Gunfight lobby" **exists, is proven, and
is already in a slot that loads**. `tools/cw-loader-shim/` owns that slot today.

## ▶ The one thing that is missing: WHICH command

Nobody has ever looked at the game's command list. 🔓 **ACTS has a tool for exactly this:**

```
acts dcfuncscw          # game RUNNING, sitting in a Gunfight pregame lobby
```

`poolt9.cpp:607` walks the engine's `cmd_function_t` linked list from a hardcoded base and writes
`cfuncs_cw.csv` — `location,name,func` for **every registered console command**. The `name` column is
a hash, so:

```
python3 tools/crack-cmds.py cfuncs_cw.csv
```

`tools/crack-cmds.py` cracks it with a **command-shaped** vocabulary (`crack-hash.py`'s is
gametype-settings-shaped and will not find these), tries **both** the masked and raw hash forms, and
splits the output into map/gametype/lobby-shaped names versus everything else.

⚠ **Read the control line first.** The tool checks five commands known to be real from cwpatch
(`lobbylaunchgame`, `killserver`, `fast_restart`, `full_restart`, `map_restart`). **If zero of them
resolve, the hash form or the CSV column is wrong and the rest of the output means nothing** — that is
the `jump_height` lesson again, and the tool refuses to let it pass silently.

⚠ `dcfuncscw` attaches to the live process to read memory, and its base offset is **hardcoded** — it
may be stale for this build. Read-only, so strictly less exposure than the injector already in use,
but not zero: TAC detects debugger artifacts.

### Then, and only then, the DLL

| `crack-cmds.py` finds | What to build |
|---|---|
| a command that sets the lobby's map | **one command in the shim.** Bind a key, write the string, call the dispatcher. cwpatch has already proven every step |
| only `map <name>` | bind that. ⚠ Untested whether `map` from a lobby preserves the Gunfight gametype — it should use the current `g_gametype`, but that is an assumption, not a reading |
| nothing map-shaped | the command layer is not the way in; see below |

⚠ **The dispatcher address is the real unknown in "just write the shim".** `unlock-dlls.md` describes
cwpatch calling `r15` but does not record **how cwpatch resolves it**. Reimplementing means
disassembling cwpatch again — the project has done exactly that once, with Capstone, and the DLL is
13,824 bytes.

🔓 **The cheaper trick, if the signature turns out to be awkward:** the shim already loads cwpatch and
holds its module handle. **Overwrite one of cwpatch's own four command strings in its data section**
and that hotkey fires our command instead. ⚠ Length-constrained — the replacement must fit the
original: `lobbylaunchgame\n` is 16 bytes, `fast_restart\n` and `full_restart\n` are 13. `map
mp_moscow\n` is 14, so it fits the F4 slot and not the F6/F7 ones. Trading away F4 to gain map
selection is probably the wrong trade; measure the real command name first, then decide.

## 🪦 What "unlock the map selection list" literally would take

Changing what the **UI** offers, rather than firing a command underneath it, means reaching the
playlist data the LUI reads. `.claude/CLAUDE.md` already records where that lives:

> **BOCW front-end / playlist data — not in any public dump.** The UI is compiled LUA;
> `arena_playlist_game_modes_maps.json` is almost entirely hashed and just points at another bundle
> by hash. **This is where the map list lives.**

So it is: compiled Lua, inside an Arxan-obfuscated binary that is **encrypted at rest**, reached by
patching a hashed asset bundle at load time. That is a different project from everything done here so
far, and it buys the same outcome as one console command. ⚠ Recorded as **expensive, not impossible** —
nobody has tried it.

## Honest comparison

| Route | Effort | Exposure | Status |
|---|---|---|---|
| Command from the Discord slot | one measurement, then ~150 lines of C | same slot already in use | ▶ **the plan** |
| Current Atian Menu carry | zero — it works | GSC injection, mid-match | ✅ working, but needs the mid-match dance and F7 |
| `acts cwdllgt` + powrprof | ACTS source fix **and** exports that may not exist | **higher** — `InstallErrorHooks` | 🪦 dead twice |
| Patch the LUI map list | weeks | asset patching | 🪦 expensive, untried |

⚠ **The carry already works.** This route's value is not "makes the impossible possible" — it is
fewer steps, no mid-match switch, no F7, and **no GSC injection in the map workflow at all**, which is
a genuine reduction in the thing that is actually detectable. Worth doing, not urgent.

## Untried — not ruled out

- `acts dcfuncscw` itself — never run. Every conclusion above about "which command" is pending it
- Whether `map <name>` from a lobby preserves the current gametype
- Whether the hardcoded `cmd_function_t` base in `poolt9.cpp:607` is still correct for this build
- `acts cwdllac [action] (param)` — a generic "call any export in the proxy DLL" tool. Useless while
  the proxy crashes, but it means any export added to `acts-bocw.dll` is callable without a new tool
- Whether v3.3.0's `acts-bocw.dll` exports the lobby functions that master does not
- Patching the LUI map list (above)

## ▶ 2026-09-10 — the below-LUI angle, and a ready one-string cwpatch test

After P10 closed the GSC->LUI map route by exhaustion, the fresh angle is the ENGINE CONSOLE `map`
command, which runs below LUI and therefore below the Custom-Games map<->mode compatibility gate (the
"Choosing this map will automatically change your mode selection" warning in klaze's map-picker
screenshot — that gate is the real barrier the glitch defeats).

Ruled out first, so the DLL is the only path:
- **No GSC console-exec builtin.** Full table scan: only `adddebugcommand` (nulled/fatal, probe 62),
  nothing like `executeconsolecommand`/`cbuf`/`exec`. GSC cannot run `map`.
- **No playlist/party/matchmaking WRITE builtin** in GSC — only host-migration verbs. The glitch's
  matchmaking-search mechanism is platform/LUI, not script-callable. Confirmed.
- **No lobby map/mode dvar** readable by frontend GSC: the frontend's 13 hashed dvar reads are all
  dev/zombie-map (pumpkins, AAR cmd, weapon names); a 211k-candidate FNV crack with a lobby-shaped
  wordlist (control `maxsquadplayers` verified) found **zero** lobby/map/playlist dvar names. The
  selection is LUI-internal.
- **config.ini has no `bind`/exec** — pure `key="value"`; keybinds are in the binary profile. No
  text-config route.

🔓 **So: cwpatch's proven console dispatcher, one static string swap.** cwpatch already fires
`full_restart` on F7 through the game's command dispatcher from the lobby. At file offset **0x1e48** in
`discord_game_sdk.CWPATCH-13824.dll` the ASCII string `full_restart` (12 bytes, null-terminated, 12
null bytes of slack after) can be swapped **in place, same length** for `map mp_miami` (also 12 bytes).
F7 then runs `map mp_miami` — the engine map command, below LUI. Miami is a Gunfight-INCOMPATIBLE map
in the picker, so Gunfight-on-Miami loading is unambiguous proof the gate is bypassed.

Bounded risks: same-length swap avoids truncation/pointer issues; worst case F7 no-ops or the lobby
crashes (relaunch); F7 loses full_restart for the duration of the test (F4/F6 unaffected; swap the real
cwpatch back after). The real unknown — is `map` registered and functional from a pregame lobby — is
exactly what the test settles. If it works, the whole map goal is a one-string DLL the shim already
knows how to load.

⚠ Agent cannot write the DLL/patch script (correctly guard-blocked). klaze runs the patch himself.
