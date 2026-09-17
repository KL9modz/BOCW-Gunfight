#!/usr/bin/env python3
"""Carve the English localize table (xhash key -> UI text) from a decompressed localized fastfile.

    python tools/lui/localize.py <en_core_ui.ff.dec> <out.json> [--all-index allindex.json]

WHY THIS IS A HEURISTIC. The authoritative route is `acts fastfile -r cw` (the `localizeentry`
unlinker, `Localize{ const char* val; CWXHash name }`, 0x10) — but that needs
`deps/BlackOpsColdWar_dump.exe` from `acts game_dump cw`, which launches the game exe under a
debugger to get past Arxan (klaze's call, not run here). This tool instead reads the raw decompressed
zone: each localize entry serializes as `FF*8` (the `val` pointer placeholder) + the 8-byte xhash
name, and the English string sits inline a few bytes later. It pairs each `FF*8|xhash` with the next
null-terminated printable run within a 40-byte window. That is right for the vast majority (spot-check:
`#hash_370a9fdc87cd3d48`->"Back", `3a009f37e1567367`->"Notice", "Quit Game", "Custom Class"), but a
minority of `FF*8` sites are other assets or have the string out of window, so the output is filtered
to "texty" values and each entry is flagged `in_lua` when its key is referenced by the decompiled UI
(the keys that actually matter). Treat it as a lookup aid, not a complete table.

The key is the same xhash the Lua uses (FNV1a-64 lowercase & MASK63 of the localize KEY name, not of
the text), so `localize_en.json[hash] ` resolves the `#hash_...` you see in `lui-source/lua/*.lua`.
"""
import re, struct, json, sys

FF = b'\xff' * 8


def carve(path, lua_hashes=None):
    d = open(path, 'rb').read()
    pairs = {}
    for m in re.finditer(re.escape(FF), d):
        p = m.start()
        xh = struct.unpack_from('<Q', d, p + 8)[0]
        if xh in (0, 0xFFFFFFFFFFFFFFFF):
            continue
        win = d[p + 16:p + 16 + 40]
        sm = re.search(rb'[\x20-\x7e]{2,300}\x00', win)
        if not sm:
            continue
        s = sm.group()[:-1].decode('latin1')
        if not re.search(r'[A-Za-z]', s):
            continue
        # "texty": a space, or 4+ chars, or an all-letters token (button words like DRAW, QUIT)
        if not (' ' in s or len(s) >= 4 or s.isalpha()):
            continue
        pairs.setdefault(xh, s)          # first occurrence wins
    return pairs


if __name__ == '__main__':
    src, out = sys.argv[1], sys.argv[2]
    lua_hashes = set()
    if '--all-index' in sys.argv:
        ai = json.load(open(sys.argv[sys.argv.index('--all-index') + 1]))
        lua_hashes = set(int(x, 16) for e in ai.values() for x in e.get('xhashes', []))
    pairs = carve(src)
    obj = {}
    n_lua = 0
    for h, s in sorted(pairs.items()):
        rec = s if not lua_hashes else {'text': s, 'in_lua': h in lua_hashes}
        obj['%016x' % h] = rec
        if lua_hashes and h in lua_hashes:
            n_lua += 1
    json.dump(obj, open(out, 'w'), indent=0, ensure_ascii=False)
    print('wrote %d localize entries to %s%s' % (
        len(obj), out, (' (%d keyed in the LUI Lua)' % n_lua) if lua_hashes else ''))
