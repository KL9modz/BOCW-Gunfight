# The client UI is readable: Cold War's LUI Lua, extracted and decompiled offline (2026-09-17)

**Every earlier LUI question in this project was answered by crashing the game, because "the dump
ships no Lua" ([lui-elems](lui-elems.md)). That is over.** The whole client UI — pause menu, HUD,
popups, scoreboard, the custom-games lobby, the store — is 4,735 Lua chunks in five fastfiles, and
they are now decompiled at **`C:\bocw\lui-source\`** (a sibling of `bocw-source-main`, rebuilt by
`bash tools/lui/extract-lui.sh`). Nothing here touched a game process: the zones came out of the
Battle.net CASC store on disk, unencrypted.

This note is the *how* and the format facts. What the pause menu turned out to be, and what that
means for the mod menu, is [pause-menu](pause-menu.md).

## How it came out

| step | tool | fact it rests on |
|---|---|---|
| open the CASC store | `acts casctest <gamedir>` / `acts fastfile -C <gamedir>` | the game's `Data/` is Blizzard CASC (`data`, `indices`, `config`); ACTS 3.3.0 reads it; 372 `.ff` zones |
| decompress a zone | `acts fastfile -C <gamedir> -d -o out 'zone\core_ui.ff'` | header says `v100 comp:oodle_kraken **enc:false** bld:TA-BM-SV-T9-25` — Oodle only, no key. ACTS wants `oo2core_8_win64.dll` in `ACTS/bin/deps/` (copied from the game dir). The `-r cw` asset unlinker (which would also give the localize table) additionally wants `deps/BlackOpsColdWar_dump.exe` from `acts game_dump cw`, which **launches the exe under a debugger** to get past Arxan — not run; the raw `-d` dump was enough |
| carve the Lua | `tools/lui/ljcarve.py` | every `luafile` asset sits behind `{u64 name, u64 0, u32 len, u32 pad, u64 -1}` then the bytecode; magic `1B 4C 4A` |
| name the hashes | `ljcarve.py --names` | see *xhash* below — 6,349 of 32,653 cracked from strings in the packages + the GSC dump |
| decompile | `Aussiemon/ljd` + `tools/lui/ljd-t9.patch` | see *format* below; 4,690 / 4,735 decompiled (45 exceed the decompiler's 300 s cap — their bytecode still indexes) |
| compile | `tools/lui/lj2t9.py compile x.lua x.luac` | stock LuaJIT (via `lupa`) → T9 form; validated by round-tripping all 4,735 stock chunks through a real LuaJIT 2.1 loader (4,735 load, 4,595 re-dump byte-identical, the rest differ only in table-key order) and by executing a converted stress test against its source |

## The format — LuaJIT, not Havok Script

- **LuaJIT 2.1 bytecode** (`1B 4C 4A`, version byte `0x82`, flags `0x18`). Not the HKS bytecode of
  BO3/BO4 — ACTS's `luad`/`hksc` are the wrong family, and its own `luajit` reader stops after the
  header. Flag `0x10` is T9's: *xhash constants present, no chunk name*. Debug info is line
  numbers only.
- **xhash**: a new constant type. KGC `4` (two ulebs, **high word first**), KTAB `5`; strings shift
  to `6+`, complex to `5`. One new opcode, **`0x28 = KXHASH`** (loads one), every stock opcode from
  `0x28` on is `+1`. The hash is **the script hash** — FNV1a-64 over the lowercased string, masked
  to 63 bits, the one `tools/crack-hash.py` computes — so the same guessing cracks it. The T9
  compiler never references an xhash from an S-variant opcode (`TGETS/TSETS/ISEQS/ISNES/USETS` — 0
  of 1.07 M sites); it always materialises the hash with `KXHASH` and uses the register form.
  `lj2t9.py` rewrites accordingly.
- **xhash is a Lua type**: `type(x) == "xhash"` appears in stock code (`BaseUtility`
  `#hash_1993de65911eb3f`, the localize-if-hash helper). Menu names, model field names,
  `Engine.*`/`CoD.*` member names and localize keys are all xhashes; plain strings are plain.
- **Names**: `require("x64:HEX.lua")` resolves to the luafile asset whose name is
  `FNV1a-64(".lua", seed = HEX) & MASK63` — 4,525 of 4,534 stock requires check out. Source paths are
  never stored; the asset list carries no names (all `-1`). `lui-source/index.csv` maps chunk →
  name hash → `x64:` seed.
- **Load model**: five chunks are required by nothing — the engine-loaded roots: `core_ui_1547`
  (the in-game HUD root: `HUD_OpenInGameMenu`, `HUD_Close…`, the `menu_opened` response),
  `core_ui_1528` (the package require list), `core_frontend_1442`, `core_common_0004` (the lobby VM /
  session actions), `core_bootstrap_0000` (empty). Everything else is pulled in by a `require` chain
  from those. The require graph has 9,363 edges over 4,530 distinct assets.

## The four tools (`tools/lui/`)

- **`ljcarve.py`** — carve + index a `.ff.dec`, or `--names` to build the xhash table. A pure Python
  T9 bytecode-container reader; no dependencies.
- **`lj2t9.py`** — the offline T9 Lua **compiler**: `compile` (stock LuaJIT via `lupa` → T9),
  `to-stock` (T9 → stock, so `ljd`/any LuaJIT tool can read it), `verify` (load every chunk in a real
  LuaJIT 2.1). Needs `pip install lupa` (bundles LuaJIT 2.1). `#name` string literals become xhash
  constants; `#hash_HEX` becomes the raw hash (so decompiler output recompiles); everything else stays
  plain text — which is the whole point for free-text UI.
- **`luapool.py`** — the live game's `luafile` xasset pool, **read-only `--list`** (reuses
  `lobby-set.py`'s scanner + the `injectcw` ScanPool sig) or `--inject a.luac --as HEX` (allocate +
  write + repoint one pool entry, exactly like `acts injectcw` does for GSC; no thread). ⚠ **`--inject`
  writes game memory — klaze runs it, not the agent** (same guard as every memory write). Untested.
- **`ljd-t9.patch`** — the vendored decompiler patch (header flag, xhash KGC/KTAB, line-info-only
  debug, the `KXHASH` opcode table, and a writer fix for `obj["#hash"](obj, args)` hashed method calls).

## Untried — not ruled out

- **The localize table.** `en_core_ui.ff` + the `-r cw` unlinker (`localizeentry` asset) would turn
  every `#hash_…` localize key into its English text — the list [lui-elems](lui-elems.md) said "prove
  each key or it crashes" now becomes a lookup. Blocked only on `acts game_dump cw` (launches the exe
  under a debugger — klaze's call).
- **Injecting a chunk (`luapool.py --inject`)** — whether a `luiload("x64:HEX.lua")` from an injected
  `.csc` then loads it, and whether a stock `require` of an overwritten asset re-reads it. The write
  primitive is built and mirrors `injectcw`; the load path is [pause-menu](pause-menu.md)'s open question.
- **The 45 chunks the decompiler times out on** (the big frontend tables) — raise ljd's cap or split
  them; their `.luac` + `index.json` already carry the constants, which is what grep needs.