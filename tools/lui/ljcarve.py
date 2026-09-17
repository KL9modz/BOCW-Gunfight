#!/usr/bin/env python3
"""Carve Cold War (T9) LuaJIT chunks out of a decompressed fastfile and index their constants.

    python tools/lui/ljcarve.py <zone>.ff.dec <outdir>        # writes <outdir>/<zone>_NNNN_OFFSET.luac + index.json
    python tools/lui/ljcarve.py --names <outdir>... <names.json>   # build the xhash -> name table

WHAT THE FORMAT IS (measured 2026-09-17 on core_ui / core_frontend / mp_common / core_common /
core_bootstrap, 4,735 chunks, 0 parse errors — docs/notes/lui-source.md):

  * The LUI is NOT Havok Script (BO3/BO4).  Every `luafile` asset is LuaJIT 2.1 bytecode with the
    stock magic `1B 4C 4A`, version byte 0x82 and flags 0x18 (FR2 | 0x10).  Flag 0x10 is T9's:
    "xhash constants present, no chunk name".  Debug info is line numbers only.
  * KGC constant types: 0 child, 1 table, 2 i64, 3 u64, **4 XHASH64**, 5 complex, 6+ string
    (len = type-6).  Stock has no 4 and strings at 5+.  KTAB: 0 nil, 1 false, 2 true, 3 int, 4 num,
    **5 XHASH64**, 6+ string.
  * An XHASH64 is two uleb128s, HIGH 32 bits first, then low.  The hash is the script hash the rest of
    the project uses: FNV1a-64 over the LOWERCASED string, masked to 63 bits (tools/crack-hash.py).
    2,523 of the constants hash to a string that appears verbatim elsewhere in the same package,
    which is how the byte order and the function were pinned.
  * One extra opcode, 0x28 = KXHASH (load an xhash constant, KSTR-shaped); every stock opcode from
    KCDATA (0x28) onward is shifted +1.  Pinned by proto tails (RET* = 0x4A..0x4D) and JMP = 0x59.

In the fastfile stream each luafile sits behind its asset header:  u64 name (0 in the stream — the
name lives in the zone's asset list), u32 len, u32 pad, u64 0xFFFFFFFFFFFFFFFF (the buffer pointer),
then `len` bytes of bytecode.  That header is what `carve()` keys on.
"""
import re, struct, sys, os, json, glob

MASK63 = 0x7FFFFFFFFFFFFFFF


def hash64(s):
    """T9 script hash (== tools/crack-hash.py): FNV1a-64, lowercase, 63-bit."""
    h = 0xcbf29ce484222325
    for c in s.lower().encode('latin1', 'replace'):
        h = ((h ^ c) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h & MASK63


def uleb(b, p):
    r = 0; s = 0
    while True:
        c = b[p]; p += 1
        r |= (c & 0x7f) << s; s += 7
        if c < 0x80:
            return r, p


def uleb33(b, p):
    # LuaJIT uleb128_33: bit0 of the first byte = "is a double"
    c = b[p]; p += 1
    isnum = c & 1
    r = (c >> 1) & 0x3f
    s = 6
    if c >= 0x80:
        while True:
            c = b[p]; p += 1
            r |= (c & 0x7f) << s; s += 7
            if c < 0x80:
                break
    return isnum, r, p


class Proto:
    def __init__(self):
        self.flags = 0; self.numparams = 0; self.framesize = 0; self.numuv = 0
        self.bc = []; self.uv = []; self.kgc = []; self.kn = []; self.children = []
        self.firstline = 0; self.numline = 0; self.debug = b''


def parse_proto(b, p, stripped, stack):
    pr = Proto()
    pr.flags, pr.numparams, pr.framesize, pr.numuv = b[p], b[p+1], b[p+2], b[p+3]; p += 4
    numkgc, p = uleb(b, p); numkn, p = uleb(b, p); numbc, p = uleb(b, p)
    debuglen = 0
    if not stripped:
        debuglen, p = uleb(b, p)
        if debuglen:
            pr.firstline, p = uleb(b, p); pr.numline, p = uleb(b, p)
    pr.bc = list(struct.unpack_from('<%dI' % numbc, b, p)); p += 4 * numbc
    pr.uv = list(struct.unpack_from('<%dH' % pr.numuv, b, p)); p += 2 * pr.numuv

    def ktabk(p):
        tt, p = uleb(b, p)
        if tt >= 6:
            l = tt - 6
            return ('str', b[p:p+l].decode('latin1')), p + l
        if tt == 5:
            hi, p = uleb(b, p); lo, p = uleb(b, p)
            return ('xhash', lo | (hi << 32)), p
        if tt == 3:
            v, p = uleb(b, p); return ('int', v), p
        if tt == 4:
            lo, p = uleb(b, p); hi, p = uleb(b, p)
            return ('num', struct.unpack('<d', struct.pack('<II', lo, hi))[0]), p
        return (('nil', 'false', 'true')[tt], None), p

    for _ in range(numkgc):
        t, p = uleb(b, p)
        if t == 0:
            child = stack.pop(); pr.kgc.append(('child', child)); pr.children.append(child)
        elif t == 1:
            narry, p = uleb(b, p); nhash, p = uleb(b, p)
            items = []
            for _ in range(narry):
                v, p = ktabk(p); items.append(v)
            hsh = []
            for _ in range(nhash):
                k, p = ktabk(p); v, p = ktabk(p); hsh.append((k, v))
            pr.kgc.append(('tab', (items, hsh)))
        elif t in (2, 3):
            lo, p = uleb(b, p); hi, p = uleb(b, p)
            pr.kgc.append(('i64' if t == 2 else 'u64', lo | (hi << 32)))
        elif t == 4:
            hi, p = uleb(b, p); lo, p = uleb(b, p)          # T9: high word first (measured)
            pr.kgc.append(('xhash', lo | (hi << 32)))
        elif t == 5:
            a, p = uleb(b, p); c, p = uleb(b, p); e, p = uleb(b, p); f, p = uleb(b, p)
            pr.kgc.append(('complex', (a, c, e, f)))
        else:
            l = t - 6
            pr.kgc.append(('str', b[p:p+l].decode('latin1'))); p += l
    for _ in range(numkn):
        isnum, lo, p = uleb33(b, p)
        if isnum:
            hi, p = uleb(b, p)
            pr.kn.append(struct.unpack('<d', struct.pack('<II', lo, hi))[0])
        else:
            pr.kn.append(lo if lo < 0x80000000 else lo - 0x100000000)
    if debuglen:
        pr.debug = b[p:p+debuglen]; p += debuglen
    return pr, p


def parse_chunk(b):
    assert b[:3] == b'\x1bLJ', 'not a LuaJIT chunk'
    flags = b[4]; p = 5
    stripped = bool(flags & 2)
    stack = []; protos = []
    while p < len(b):
        l, p = uleb(b, p)
        if l == 0:
            break
        pr, q = parse_proto(b, p, stripped, stack)
        if q != p + l:
            raise ValueError('proto size mismatch %d vs %d' % (q - p, l))
        p += l
        stack.append(pr); protos.append(pr)
    return protos, stack          # stack[-1] is the main chunk


def carve(path):
    d = open(path, 'rb').read()
    out = []
    for m in re.finditer(b'\x1bLJ', d):
        p = m.start()
        if p < 0x18 or d[p-8:p] != b'\xff' * 8:
            continue
        ln, pad = struct.unpack_from('<II', d, p - 16)
        if pad != 0 or ln < 8 or ln > 16_000_000:
            continue
        out.append((p, d[p:p+ln]))
    return out


def all_consts(pr, acc=None):
    if acc is None:
        acc = []
    for t, v in pr.kgc:
        if t == 'child':
            all_consts(v, acc)
        elif t in ('str', 'xhash'):
            acc.append((t, v))
        elif t == 'tab':
            items, hsh = v
            for it in items:
                if it[0] in ('str', 'xhash'): acc.append(it)
            for k, vv in hsh:
                if k[0] in ('str', 'xhash'): acc.append(k)
                if vv[0] in ('str', 'xhash'): acc.append(vv)
    return acc


def build_names(outdirs, names_path, extra_sources=()):
    """xhash -> name.  Candidates: every string constant in every chunk, every printable run in the
    decompressed zones (widget/model names), every identifier and quoted literal in the GSC dump."""
    allx = set(); cands = set()
    for d in outdirs:
        for e in json.load(open(os.path.join(d, 'index.json'))):
            allx.update(int(x, 16) for x in e.get('xhashes', []))
            cands.update(e.get('strs', []))
    for src in extra_sources:
        if os.path.isdir(src):
            for dp, _, fs in os.walk(src):
                for f in fs:
                    cands.add(os.path.splitext(f)[0])
                    if f.endswith(('.gsc', '.csc', '.csv', '.json')):
                        try:
                            t = open(os.path.join(dp, f), encoding='utf-8', errors='replace').read()
                        except OSError:
                            continue
                        cands.update(re.findall(r'#?"([^"\n]{1,80})"', t))
                        cands.update(re.findall(r'[A-Za-z_][A-Za-z0-9_/\.]{2,80}', t))
        else:
            data = open(src, 'rb').read()
            for m in re.finditer(rb'[\x20-\x7e]{3,120}', data):
                cands.add(m.group().decode('latin1'))
    for c in list(cands):
        for part in re.split(r'[^A-Za-z0-9_]+', c):
            if 2 < len(part) < 60:
                cands.add(part)
    names = {}
    if os.path.exists(names_path):
        names = {int(k, 16): v for k, v in json.load(open(names_path)).items()}
    for c in cands:
        h = hash64(c)
        if h in allx and h not in names:
            names[h] = c
    json.dump({'%x' % k: v for k, v in sorted(names.items())}, open(names_path, 'w'), indent=0)
    print('xhashes', len(allx), 'candidates', len(cands), 'resolved', len(names))


if __name__ == '__main__':
    if len(sys.argv) >= 4 and sys.argv[1] == '--names':
        *dirs, names_path = sys.argv[2:]
        extra = [d for d in dirs if not os.path.exists(os.path.join(d, 'index.json'))]
        dirs = [d for d in dirs if os.path.exists(os.path.join(d, 'index.json'))]
        build_names(dirs, names_path, extra)
        sys.exit(0)
    src, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    zone = os.path.basename(src).split('.')[0]
    chunks = carve(src)
    index = []; bad = 0
    for i, (off, blob) in enumerate(chunks):
        name = '%s_%04d_%08x' % (zone, i, off)
        open(os.path.join(outdir, name + '.luac'), 'wb').write(blob)
        try:
            protos, stack = parse_chunk(blob)
            consts = all_consts(stack[-1])
            index.append({'name': name, 'off': off, 'len': len(blob), 'nprotos': len(protos),
                          'strs': sorted(set(v for t, v in consts if t == 'str')),
                          'xhashes': sorted(set('%x' % v for t, v in consts if t == 'xhash'))})
        except Exception as e:
            bad += 1
            index.append({'name': name, 'off': off, 'len': len(blob), 'error': str(e)})
    json.dump(index, open(os.path.join(outdir, 'index.json'), 'w'), indent=0)
    print(zone, 'chunks', len(chunks), 'parse errors', bad)
