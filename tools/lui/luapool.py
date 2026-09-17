#!/usr/bin/env python3
"""The live game's `luafile` xasset pool: list it (read-only), or inject a compiled T9 chunk (klaze).

    python tools/lui/luapool.py --list                      # read-only: every luafile entry (name, len, buffer)
    python tools/lui/luapool.py --list --match <luac dir>   # ...and name the ones whose bytes match a carved chunk
    python tools/lui/luapool.py --inject gf_menu.luac --as 1d3b6d5c58f6a1e0 [--slot N]     # WRITES the game

The pool is found the way ACTS's injectcw finds it (cw.cpp ScanPool): the `lea rax,[pool]` at
`48 8D 05 ? ? ? ? 48 C1 E2 ? 48 03 D0`, rel32-resolved. Each pool row is 0x20 bytes
{ void* pool; u32 itemSize; i32 itemCount; bool singleton; i32 itemAllocCount; void* freeHead }
and the luafile row is the one whose items are { u64 name; u64 zero; u32 len; u32 pad; byte* buffer }
(0x20, the layout the fastfile stream serializes — tools/lui/ljcarve.py) with LuaJIT magic at
*buffer. The asset name for a `require("x64:HEX.lua")` is FNV1a-64 of ".lua" SEEDED with HEX,
masked to 63 bits (4,525 of 4,534 stock requires resolve that way), so `--as HEX` is the
require/luiload string you will use and the tool computes the name.

--inject mirrors injectcw exactly (allocate + write the chunk + repoint a pool entry) and is the
one thing here that touches game memory: VirtualAllocEx + WriteProcessMemory, no thread. It
re-uses a slot: by default the LAST allocated entry (an ordinary stock file, which the running UI
has already loaded and never re-reads), or --slot N. The overwritten entry's original 0x20 bytes
are printed so it can be restored by hand. Never run it while a match is loading.
"""
import argparse, importlib.util, os, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('lobbyset', os.path.join(HERE, '..', 'lobby-set.py'))
ls = importlib.util.module_from_spec(spec); spec.loader.exec_module(ls)

POOL_SIG = '48 8D 05 ? ? ? ? 48 C1 E2 ? 48 03 D0'
MASK63 = 0x7FFFFFFFFFFFFFFF


def fnv_seed(s, seed):
    h = seed
    for c in s.encode():
        h = ((h ^ c) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h


def asset_name_for(hex_seed):
    return fnv_seed('.lua', int(hex_seed, 16)) & MASK63


def find_pool(proc, base, size):
    hits = ls.scan(proc, base, size, POOL_SIG)
    if not hits:
        ls._die('xasset pool signature not found (game build changed?)')
    rel = struct.unpack('<i', proc.read(hits[0] + 3, 4))[0]
    return hits[0] + 7 + rel


def read_rows(proc, pool, n=200):
    rows = []
    for i in range(n):
        raw = proc.read(pool + 0x20 * i, 0x20)
        if not raw or len(raw) < 0x20:
            break
        p = struct.unpack_from('<Q', raw, 0)[0]
        isz = struct.unpack_from('<I', raw, 8)[0]
        cnt = struct.unpack_from('<i', raw, 12)[0]
        alloc = struct.unpack_from('<i', raw, 20)[0]
        rows.append((i, p, isz, cnt, alloc))
    return rows


def find_luafile_row(proc, rows):
    """The row whose items look like {name, 0, len, pad, buffer -> 1B 4C 4A}."""
    for i, p, isz, cnt, alloc in rows:
        if isz != 0x20 or not p or alloc <= 0 or alloc > 100000:
            continue
        raw = proc.read(p, 0x20 * min(alloc, 8))
        if not raw:
            continue
        good = 0
        for j in range(min(alloc, 8)):
            name, zero, ln, pad, buf = struct.unpack_from('<QQIIQ', raw, 0x20 * j)
            if buf and 8 < ln < 16_000_000:
                head = proc.read(buf, 4)
                if head and head[:3] == b'\x1bLJ':
                    good += 1
        if good >= 4:
            return i, p, cnt, alloc
    return None


def list_entries(proc, p, alloc, match_dir=None):
    known = {}
    if match_dir:
        import glob, hashlib
        for f in glob.glob(os.path.join(match_dir, '**', '*.luac'), recursive=True):
            known[hashlib.sha1(open(f, 'rb').read()).hexdigest()] = os.path.basename(f)
    raw = proc.read(p, 0x20 * alloc)
    out = []
    for j in range(alloc):
        name, zero, ln, pad, buf = struct.unpack_from('<QQIIQ', raw, 0x20 * j)
        if not buf:
            continue
        tag = ''
        if known and 8 < ln < 16_000_000:
            data = proc.read(buf, ln)
            if data:
                import hashlib
                tag = known.get(hashlib.sha1(data).hexdigest(), '')
        out.append((j, name, ln, buf, tag))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--list', action='store_true')
    ap.add_argument('--match', help='directory of carved .luac chunks to identify entries by content')
    ap.add_argument('--inject', help='compiled T9 .luac to inject (WRITES the game)')
    ap.add_argument('--as', dest='as_hex', help='HEX of the x64:HEX.lua name to give it')
    ap.add_argument('--slot', type=int, help='pool entry index to overwrite (default: the last allocated)')
    a = ap.parse_args()
    if not (a.list or a.inject):
        ap.print_help(); return 0
    pid = ls.find_process('BlackOpsColdWar.exe')
    base, size = ls.find_module(pid, 'BlackOpsColdWar.exe')
    proc = ls.Proc(pid, write=bool(a.inject))
    pool = find_pool(proc, base, size)
    print('xasset pool @ %#x (exe+%#x)' % (pool, pool - base))
    rows = read_rows(proc, pool)
    lf = find_luafile_row(proc, rows)
    if not lf:
        ls._die('no pool row looks like luafile {name,0,len,pad,buffer->1B 4C 4A}')
    idx, p, cnt, alloc = lf
    print('luafile pool = row %d @ %#x, itemSize 0x20, count %d, alloc %d' % (idx, p, cnt, alloc))
    entries = list_entries(proc, p, alloc, a.match)
    if a.list:
        for j, name, ln, buf, tag in entries:
            print('%5d  %016x  %8d  %#x  %s' % (j, name, ln, buf, tag))
        print('%d entries' % len(entries))
    if a.inject:
        if not a.as_hex:
            ls._die('--inject needs --as HEX')
        data = open(a.inject, 'rb').read()
        if data[:3] != b'\x1bLJ' or data[3] != 0x82:
            ls._die('not a T9 LuaJIT chunk (compile with tools/lui/lj2t9.py compile)')
        name = asset_name_for(a.as_hex)
        slot = a.slot if a.slot is not None else max(j for j, *_ in entries)
        old = proc.read(p + 0x20 * slot, 0x20)
        print('overwriting slot %d, original bytes: %s' % (slot, old.hex()))
        mem = proc.alloc(len(data) + 16, ls.PAGE_READWRITE)
        if not proc.write(mem, data):
            ls._die('WriteProcessMemory(buffer) failed')
        entry = struct.pack('<QQIIQ', name, 0, len(data), 0, mem)
        if not proc.write(p + 0x20 * slot, entry):
            ls._die('WriteProcessMemory(entry) failed')
        print('injected %d bytes as x64:%s.lua (name %016x) at %#x; luiload("x64:%s.lua") from the client script loads it'
              % (len(data), a.as_hex, name, mem, a.as_hex))
    proc.close()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
