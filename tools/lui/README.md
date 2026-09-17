# tools/lui — Cold War's LUI (Lua) source, offline

The client UI — pause menu, HUD, popups, scoreboard, the custom-games lobby — is Lua. The dump
(`bocw-source-main`) never had it ("the dump ships no Lua"), so every LUI question so far was
answered by crashing the game. This directory extracts and decompiles all of it **from the installed
game's fastfiles, offline** — no game process, no injection, no memory read. 2026-09-17,
`docs/notes/lui-source.md`.

```
bash tools/lui/extract-lui.sh            # ~20 min first run; output /c/bocw/lui-source (gitignored, like bocw-source-main)
```

| File | What it is |
|---|---|
| `extract-lui.sh` | The pipeline: ACTS CASC-backed fastfile decompress → carve → xhash name table → ljd decompile. Idempotent; `JOBS=8`; one zone as `$1` |
| `ljcarve.py` | Offline — carves every `luafile` asset (LuaJIT `1B 4C 4A 82` chunks) out of a decompressed `.ff.dec`, parses the T9 bytecode container, writes `index.json` (every string / xhash constant per chunk — grep this to find a menu), and `--names` builds the xhash → name table by hashing every candidate string (FNV1a-64 lowercase 63-bit, the script hash) |
| `ljd-t9.patch` | The changes that make [Aussiemon/ljd](https://github.com/Aussiemon/ljd) (MIT, `2ed0381`) read T9 chunks: header flag `0x10` + no chunk name, KGC/KTAB xhash constant types, line-info-only debug block, opcode `0x28 = KXHASH` (+1 shift after it), and a writer fix for hashed method calls (`obj["#hash"](obj, args)`). Applied by the script |
| `lj2t9.py` | Offline **T9 Lua compiler**: `compile` (stock LuaJIT via `pip lupa` → T9), `to-stock` (T9 → stock, so any LuaJIT tool reads it), `verify` (load chunks in a real LuaJIT 2.1). `#name` → xhash, `#hash_HEX` → raw hash, everything else plain text |
| `luapool.py` | The live game's `luafile` xasset pool: read-only `--list` (reuses `lobby-set.py`'s scanner) or `--inject a.luac --as HEX` (allocate + write + repoint, like `acts injectcw`; **writes memory — klaze runs it**) |
| `localize.py` | Offline — carve the English localize table (xhash key → UI text) from a decompressed localized zone (`en_core_ui.ff.dec`). Heuristic; `lui-source/localize_en.json` is ~95% clean and flags which keys the UI Lua references |

## What the format turned out to be

- **LuaJIT 2.1**, not Havok Script. Version byte `0x82`, flags `0x18`. Every ACTS/Havok tool
  (`acts luad`, `hksc`) is the wrong family; ACTS's own `luajit` reader stops after the header and its
  `ljec` compiler needs a dumped exe. The patched ljd decompiles **4,735 / 4,735** chunks
  (core_ui 1,558 · mp_common 1,679 · core_frontend 1,443 · core_common 54 · core_bootstrap 1).
- Strings the engine looks up (menu names, model names, localize keys, `Engine.*` function names,
  `CoD.*` table names) are **xhash64 constants** — a new KGC type 4 (two ulebs, high word first)
  loaded by a new opcode. The hash is the project's script hash, so `crack-hash.py`-style guessing
  resolves them: 6,349 of 32,653 distinct hashes resolve from strings found in the packages + the GSC
  dump. Unresolved ones print as `#hash_xxx`; resolved ones as `#name`.
- `Engine["#hash_4f9f1239cfd921fe"]` is **`Engine.Localize`** — it is the function named in the
  2026-09-13 crash dump (`in function '4f9f1239cfd921fe'`), so any widget that wraps a model value in
  it is localized-key-only and a plain string is the same fatal `localizeentry` error.

## Fastfiles

Cold War's zones live in Battle.net's CASC store (`Data/data`, `Data/indices`), 372 `.ff` files.
The five UI-bearing ones are `core_ui`, `mp_common`, `core_frontend`, `core_common`,
`core_bootstrap` (+ `en_core_ui` for localized strings; `tables/`-style assets are in the dump
already). They are **not encrypted** (`enc:false` in the header) — ACTS's `fastfile -r`-less
`-d` dump needs only Oodle (`oo2core_8_win64.dll`, copied from the game dir into `ACTS/bin/deps/`).
`acts fastfile -r cw` (the asset unlinker, which would also give the localize table) additionally
wants `deps/BlackOpsColdWar_dump.exe` from `acts game_dump cw <gamedir>`, which **launches the game
exe under a debugger** to get past Arxan — klaze's call, not run here.
