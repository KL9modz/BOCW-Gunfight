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
    """The pool row whose items are LuaFile{ name@0, len@8, buffer@(itemSize-8) -> 1B 4C 4A }.

    CW runtime LuaFile is 0x18 (ACTS cw_unlinker_luafile.cpp: {CWXHash name; u32 len; byte* buffer}),
    NOT the 0x20 fastfile-stream layout. buffer is the last field, at itemSize-8, whatever the size."""
    for i, p, isz, cnt, alloc in rows:
        if not p or alloc <= 0 or alloc > 200000 or isz < 0x10 or isz > 0x40:
            continue
        n = min(alloc, 16)
        raw = proc.read(p, isz * n)
        if not raw or len(raw) < isz * n:
            continue
        good = 0
        for j in range(n):
            buf = struct.unpack_from('<Q', raw, isz * j + isz - 8)[0]
            if buf:
                head = proc.read(buf, 4)
                if head and head[:3] == b'\x1bLJ':
                    good += 1
        if good >= 3:
            return i, p, cnt, alloc, isz
    return None


def list_entries(proc, p, alloc, isz, match_dir=None):
    known = {}
    if match_dir:
        import glob, hashlib
        for f in glob.glob(os.path.join(match_dir, '**', '*.luac'), recursive=True):
            known[hashlib.sha1(open(f, 'rb').read()).hexdigest()] = os.path.basename(f)
    raw = proc.read(p, isz * alloc)
    out = []
    for j in range(alloc):
        name = struct.unpack_from('<Q', raw, isz * j)[0]
        ln = struct.unpack_from('<I', raw, isz * j + 8)[0]
        buf = struct.unpack_from('<Q', raw, isz * j + isz - 8)[0]
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
    ap.add_argument('--hijack', help='replacement .luac to put in place of --stock (keeps the stock NAME; WRITES the game)')
    ap.add_argument('--stock', help='carved stock .luac to identify the pool slot by content (for --hijack)')
    a = ap.parse_args()
    if not (a.list or a.inject or a.hijack):
        ap.print_help(); return 0
    pid = ls.find_process('BlackOpsColdWar.exe')
    base, size = ls.find_module(pid, 'BlackOpsColdWar.exe')
    proc = ls.Proc(pid, write=bool(a.inject or a.hijack))
    pool = find_pool(proc, base, size)
    print('xasset pool @ %#x (exe+%#x)' % (pool, pool - base))
    rows = read_rows(proc, pool)
    lf = find_luafile_row(proc, rows)
    if not lf:
        ls._die('no pool row looks like luafile {name,0,len,pad,buffer->1B 4C 4A}')
    idx, p, cnt, alloc, isz = lf
    print('luafile pool = row %d @ %#x, itemSize %#x, count %d, alloc %d' % (idx, p, isz, cnt, alloc))
    entries = list_entries(proc, p, alloc, isz, a.match)
    if a.list:
        for j, name, ln, buf, tag in entries:
            print('%5d  %016x  %8d  %#x  %s' % (j, name, ln, buf, tag))
        print('%d entries' % len(entries))
    if a.hijack:
        import hashlib
        if not a.stock:
            ls._die('--hijack needs --stock <carved stock .luac> to identify the slot by content')
        repl = open(a.hijack, 'rb').read()
        if repl[:3] != b'\x1bLJ' or repl[3] != 0x82:
            ls._die('--hijack replacement is not a T9 LuaJIT chunk')
        stock = open(a.stock, 'rb').read()
        target = hashlib.sha1(stock).hexdigest()
        # find the slot whose buffer content == the stock chunk (same len + sha1)
        hit = None
        for j, name, ln, buf, tag in entries:
            if ln == len(stock) and buf:
                data = proc.read(buf, ln)
                if data and hashlib.sha1(data).hexdigest() == target:
                    hit = (j, name, ln, buf); break
        if hit is None:
            ls._die('stock chunk not found in the pool (len %d) - not loaded yet, or the bytes differ' % len(stock))
        j, name, ln, buf = hit
        old = proc.read(p + isz * j, isz)
        print('hijacking slot %d, name %016x (kept), original len %d buffer %#x' % (j, name, ln, buf))
        print('ORIGINAL entry bytes: %s (write these back to restore)' % old.hex())
        mem = proc.alloc(len(repl) + 16, ls.PAGE_READWRITE)
        if not proc.write(mem, repl):
            ls._die('WriteProcessMemory(buffer) failed')
        entry = bytearray(old)                              # keep name@0, only change len + buffer
        struct.pack_into('<I', entry, 8, len(repl))
        struct.pack_into('<Q', entry, isz - 8, mem)
        if not proc.write(p + isz * j, bytes(entry)):
            ls._die('WriteProcessMemory(entry) failed')
        print('hijacked slot %d: name kept, buffer -> our %d-byte chunk at %#x. The game loads OUR bytes when it (re)reads this chunk.'
              % (j, len(repl), mem))
    if a.inject:
        if not a.as_hex:
            ls._die('--inject needs --as HEX')
        data = open(a.inject, 'rb').read()
        if data[:3] != b'\x1bLJ' or data[3] != 0x82:
            ls._die('not a T9 LuaJIT chunk (compile with tools/lui/lj2t9.py compile)')
        name = asset_name_for(a.as_hex)
        # Free-list-safe target: only ever repoint a slot that is a LIVE luafile (its buffer starts with
        # the LuaJIT magic 1B4C4A) - never a free-list node (whose "buffer" field holds a next-free
        # pointer) and never a non-luafile. Repointing a USED entry's {name,len,buffer} does not touch
        # the free list. Default = the highest-indexed live luafile (a late stock chunk the UI has already
        # cached and will not re-read). Original bytes are printed so the slot can be restored by hand.
        def is_live_luafile(j):
            buf = struct.unpack_from('<Q', proc.read(p + isz * j, isz), isz - 8)[0]
            return bool(buf) and proc.read(buf, 3) == b'\x1bLJ'
        if a.slot is not None:
            slot = a.slot
            if not is_live_luafile(slot):
                ls._die('--slot %d is not a live luafile (buffer lacks the 1B4C4A magic); refusing so we cannot corrupt the free-list' % slot)
        else:
            live = [j for j, *_ in entries if is_live_luafile(j)]
            if not live:
                ls._die('no live luafile slot found to repoint')
            slot = max(live)
        old = proc.read(p + isz * slot, isz)
        print('repointing slot %d (itemSize %#x), a live luafile; ORIGINAL bytes: %s (write these back to restore)' % (slot, isz, old.hex()))
        mem = proc.alloc(len(data) + 16, ls.PAGE_READWRITE)
        if not proc.write(mem, data):
            ls._die('WriteProcessMemory(buffer) failed')
        # LuaFile{ name@0, len@8, buffer@(isz-8) }, rest zero
        entry = bytearray(isz)
        struct.pack_into('<Q', entry, 0, name)
        struct.pack_into('<I', entry, 8, len(data))
        struct.pack_into('<Q', entry, isz - 8, mem)
        if not proc.write(p + isz * slot, bytes(entry)):
            ls._die('WriteProcessMemory(entry) failed')
        print('injected %d bytes as x64:%s.lua (name %016x) at %#x; luiload("x64:%s.lua") from the client script loads it'
              % (len(data), a.as_hex, name, mem, a.as_hex))
    proc.close()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
