#!/usr/bin/env python3
"""Convert LuaJIT 2.1 bytecode between stock and Cold War (T9) form â€” an offline T9 Lua compiler.

    python tools/lui/lj2t9.py compile  <src.lua> <out.luac>        # stock luajit (lupa) -> T9 chunk
    python tools/lui/lj2t9.py to-stock <t9.luac>  <out.luac>       # T9 chunk -> stock (stripped) chunk
    python tools/lui/lj2t9.py verify   <t9.luac>...                # T9 -> stock -> loadstring() in LuaJIT 2.1

The T9 differences (tools/lui/ljcarve.py, docs/notes/lui-source.md):
  header   1B 4C 4A 82 18            (stock: 02 08 + a chunk name)   â€” T9 has no chunk name
  KGC      4 = XHASH64 (uleb hi, uleb lo), complex 4->5, strings 5+ -> 6+
  KTAB     5 = XHASH64, strings 5+ -> 6+
  opcodes  0x28 = KXHASH (KSTR-shaped), every stock opcode >= 0x28 is +1
  debug    line info only (no upvalue names, no varinfo)

Source convention for the compile direction: a string literal that starts with '#' becomes an xhash
constant — '#name' hashes the name, '#hash_HEX' is the raw value (so decompiler output recompiles) — e.g.  CoD["#menu"], Engine["#sendmenuresponse"](c, "#StartMenu_Main", "#menu_opened", 0),
LUI.createMenu["#MyMenu"] = function ... â€” exactly how the decompiled stock files print.
Everything else stays a plain string (free text: setText("Round timer 60s") never localizes).
"""
import struct, sys, os

MASK63 = 0x7FFFFFFFFFFFFFFF
KSTR, KXHASH = 0x27, 0x28


import re as _re
_RAW = _re.compile(rb'^#hash_([0-9a-fA-F]{1,16})$')


def xhash_of(lit):
    """'#name' -> hash64(name); '#hash_HEX' -> HEX itself (how the decompiler prints unresolved ones)."""
    m = _RAW.match(lit)
    if m:
        return int(m.group(1), 16)
    return hash64(lit[1:].decode('latin1'))


def hash64(s):
    h = 0xcbf29ce484222325
    for c in s.lower().encode('latin1', 'replace'):
        h = ((h ^ c) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h & MASK63


def r_uleb(b, p):
    r = 0; s = 0
    while True:
        c = b[p]; p += 1
        r |= (c & 0x7f) << s; s += 7
        if c < 0x80:
            return r, p


def w_uleb(v):
    out = bytearray()
    while True:
        c = v & 0x7f; v >>= 7
        if v:
            out.append(c | 0x80)
        else:
            out.append(c); return bytes(out)


def r_uleb33(b, p):
    c = b[p]; p += 1
    isnum = c & 1
    r = (c >> 1) & 0x3f; s = 6
    if c >= 0x80:
        while True:
            c = b[p]; p += 1
            r |= (c & 0x7f) << s; s += 7
            if c < 0x80:
                break
    return isnum, r, p


def w_uleb33(isnum, v):
    # inverse of r_uleb33: first byte holds bit0=isnum and 6 value bits
    out = bytearray()
    c = ((v & 0x3f) << 1) | (1 if isnum else 0); v >>= 6
    if v:
        out.append(c | 0x80)
        while True:
            c = v & 0x7f; v >>= 7
            if v:
                out.append(c | 0x80)
            else:
                out.append(c); break
    else:
        out.append(c)
    return bytes(out)


# ---------------------------------------------------------------- generic proto reader/writer
# A proto is kept as a dict of raw pieces so that either direction only touches what differs.

def read_proto(b, p, stripped, t9):
    pr = {}
    pr['hdr4'] = b[p:p+4]; p += 4
    numkgc, p = r_uleb(b, p); numkn, p = r_uleb(b, p); numbc, p = r_uleb(b, p)
    debuglen = 0; firstline = numline = 0
    if not stripped:
        debuglen, p = r_uleb(b, p)
        if debuglen:
            firstline, p = r_uleb(b, p); numline, p = r_uleb(b, p)
    pr['bc'] = list(struct.unpack_from('<%dI' % numbc, b, p)); p += 4 * numbc
    numuv = pr['hdr4'][3]
    pr['uv'] = b[p:p+2*numuv]; p += 2 * numuv
    kgc = []
    str_base = 6 if t9 else 5
    for _ in range(numkgc):
        t, p = r_uleb(b, p)
        if t == 0:
            kgc.append(('child', None))
        elif t == 1:
            narry, p = r_uleb(b, p); nhash, p = r_uleb(b, p)
            items = []
            def ktabk(p):
                tt, p = r_uleb(b, p)
                if tt >= str_base:
                    l = tt - str_base
                    return ('str', b[p:p+l]), p + l
                if t9 and tt == 5:
                    hi, p = r_uleb(b, p); lo, p = r_uleb(b, p)
                    return ('xhash', lo | (hi << 32)), p
                if tt == 3:
                    v, p = r_uleb(b, p); return ('int', v), p
                if tt == 4:
                    lo, p = r_uleb(b, p); hi, p = r_uleb(b, p); return ('num', (lo, hi)), p
                return ('prim', tt), p
            for _ in range(narry):
                v, p = ktabk(p); items.append(v)
            hsh = []
            for _ in range(nhash):
                k, p = ktabk(p); v, p = ktabk(p); hsh.append((k, v))
            kgc.append(('tab', (items, hsh)))
        elif t in (2, 3):
            lo, p = r_uleb(b, p); hi, p = r_uleb(b, p)
            kgc.append(('i64' if t == 2 else 'u64', (lo, hi)))
        elif t9 and t == 4:
            hi, p = r_uleb(b, p); lo, p = r_uleb(b, p)
            kgc.append(('xhash', lo | (hi << 32)))
        elif t == (5 if t9 else 4):
            vals = []
            for _ in range(4):
                v, p = r_uleb(b, p); vals.append(v)
            kgc.append(('complex', vals))
        else:
            l = t - str_base
            kgc.append(('str', b[p:p+l])); p += l
    pr['kgc'] = kgc
    kn = []
    for _ in range(numkn):
        isnum, lo, p = r_uleb33(b, p)
        hi = None
        if isnum:
            hi, p = r_uleb(b, p)
        kn.append((isnum, lo, hi))
    pr['kn'] = kn
    pr['firstline'] = firstline; pr['numline'] = numline
    pr['debug'] = b[p:p+debuglen]; p += debuglen
    return pr, p


def write_proto(pr, t9, stripped):
    out = bytearray(pr['hdr4'])
    out += w_uleb(len(pr['kgc'])) + w_uleb(len(pr['kn'])) + w_uleb(len(pr['bc']))
    dbg = pr['debug']
    if not stripped:
        out += w_uleb(len(dbg))
        if dbg:
            out += w_uleb(pr['firstline']) + w_uleb(pr['numline'])
    out += struct.pack('<%dI' % len(pr['bc']), *pr['bc'])
    out += pr['uv']
    str_base = 6 if t9 else 5

    def wk(v):
        t, x = v
        if t == 'str':
            return w_uleb(str_base + len(x)) + x
        if t == 'xhash':
            assert t9
            return w_uleb(5) + w_uleb(x >> 32) + w_uleb(x & 0xFFFFFFFF)
        if t == 'int':
            return w_uleb(3) + w_uleb(x)
        if t == 'num':
            return w_uleb(4) + w_uleb(x[0]) + w_uleb(x[1])
        return w_uleb(x)
    for t, x in pr['kgc']:
        if t == 'child':
            out += w_uleb(0)
        elif t == 'tab':
            items, hsh = x
            out += w_uleb(1) + w_uleb(len(items)) + w_uleb(len(hsh))
            for it in items:
                out += wk(it)
            for k, v in hsh:
                out += wk(k) + wk(v)
        elif t in ('i64', 'u64'):
            out += w_uleb(2 if t == 'i64' else 3) + w_uleb(x[0]) + w_uleb(x[1])
        elif t == 'xhash':
            assert t9, 'xhash constant in a stock chunk'
            out += w_uleb(4) + w_uleb(x >> 32) + w_uleb(x & 0xFFFFFFFF)
        elif t == 'complex':
            out += w_uleb(5 if t9 else 4)
            for v in x:
                out += w_uleb(v)
        else:
            out += w_uleb(str_base + len(x)) + x
    for isnum, lo, hi in pr['kn']:
        out += w_uleb33(isnum, lo)
        if isnum:
            out += w_uleb(hi)
    if not stripped:
        out += dbg
    return bytes(out)


def read_chunk(b):
    assert b[:3] == b'\x1bLJ', 'not LuaJIT bytecode'
    ver, flags = b[3], b[4]
    t9 = ver == 0x82 and bool(flags & 0x10)
    stripped = bool(flags & 0x02)
    p = 5
    name = b''
    if not stripped and not t9:
        l, p = r_uleb(b, p); name = b[p:p+l]; p += l
    protos = []
    while True:
        l, p2 = r_uleb(b, p)
        if l == 0:
            break
        pr, q = read_proto(b, p2, stripped, t9)
        assert q == p2 + l, 'proto size mismatch'
        protos.append(pr); p = p2 + l
    return {'t9': t9, 'stripped': stripped, 'flags': flags, 'name': name, 'protos': protos}


def write_chunk(ch, t9, stripped, name=b'=?'):
    out = bytearray(b'\x1bLJ')
    if t9:
        out += bytes([0x82, 0x18 | (0x02 if stripped else 0)])
    else:
        out += bytes([0x02, 0x08 | (0x02 if stripped else 0)])
        if not stripped:
            out += w_uleb(len(name)) + name
    for pr in ch['protos']:
        body = write_proto(pr, t9, stripped)
        out += w_uleb(len(body)) + body
    out += b'\x00'
    return bytes(out)


# ---------------------------------------------------------------- the two directions

def kgc_index_for_operand(pr, d):
    """KSTR/TGETS-style operands count from the END of the KGC list."""
    return len(pr['kgc']) - d - 1


def to_stock(ch):
    """T9 -> stock. xhash constants become '#name' strings (or '#hash_x'), KXHASH -> KSTR, opcodes -1."""
    assert ch['t9']
    for pr in ch['protos']:
        kgc = pr['kgc']
        for i, (t, x) in enumerate(kgc):
            if t == 'xhash':
                kgc[i] = ('str', ('#hash_%x' % x).encode())
            elif t == 'tab':
                items, hsh = x
                fix = lambda v: ('str', ('#hash_%x' % v[1]).encode()) if v[0] == 'xhash' else v
                kgc[i] = ('tab', ([fix(v) for v in items], [(fix(k), fix(v)) for k, v in hsh]))
        bc = pr['bc']
        for i, ins in enumerate(bc):
            op = ins & 0xff
            if op == KXHASH:
                bc[i] = (ins & ~0xff) | KSTR
            elif op > KXHASH:
                bc[i] = (ins & ~0xff) | (op - 1)
    return ch


# stock opcodes whose D operand is a jump offset (biased by 0x8000, relative to pc+1)
_JUMP_OPS = {0x58, 0x32, 0x4d, 0x4e, 0x4f, 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x48}
# stock S-variant ops (string-constant operand) -> the V-variant (register operand) the T9 compiler
# uses for xhash keys: it NEVER references an xhash constant from an S-op (0 of 1.07M in the corpus).
_S_TO_V = {0x39: 0x38, 0x3d: 0x3c, 0x06: 0x04, 0x07: 0x05, 0x2f: 0x2e}   # TGETS TSETS ISEQS ISNES USETS


def _rewrite_proto(pr, hashed):
    """Stock bytecode -> T9 bytecode for one proto: KSTR on a hashed constant -> KXHASH; an S-op on a
    hashed constant -> KXHASH into a scratch register + the V-op; every other opcode >= 0x28 shifts by
    +1; jump offsets are relocated across the inserted instructions."""
    bc = pr['bc']
    n = len(pr['kgc'])
    scratch = pr['hdr4'][2]            # old framesize = first free register
    used_scratch = False
    out = []; newpc = []; lines = []
    dbg = pr['debug']
    w = 4 if pr['numline'] >= 65536 else 2 if pr['numline'] >= 256 else 1
    have_lines = len(dbg) >= len(bc) * w
    for pc, ins in enumerate(bc):
        op = ins & 0xff; a = (ins >> 8) & 0xff; d = (ins >> 16) & 0xffff
        newpc.append(len(out))
        line = dbg[pc * w:(pc + 1) * w] if have_lines else b''
        if op in _S_TO_V:
            c = (ins >> 16) & 0xff if op in (0x39, 0x3d) else d
            if n - c - 1 in hashed:
                # KXHASH scratch, K   (D = constant operand, same numbering as the S-op's)
                out.append(KXHASH | (scratch << 8) | (c << 16)); lines.append(line)
                used_scratch = True
                vop = _S_TO_V[op]
                if op in (0x39, 0x3d):       # A, B, C(reg)
                    b = (ins >> 24) & 0xff
                    out.append((vop + 1) | (a << 8) | (scratch << 16) | (b << 24))
                else:                          # A, D(reg)
                    out.append((vop + (1 if vop >= 0x28 else 0)) | (a << 8) | (scratch << 16))
                lines.append(line)
                continue
        if op == KSTR and n - d - 1 in hashed:
            out.append(KXHASH | (ins & ~0xff)); lines.append(line); continue
        if op >= KXHASH:
            ins = (ins & ~0xff) | (op + 1)
        out.append(ins); lines.append(line)
    newpc.append(len(out))
    # relocate jumps (their opcode numbers are now +1; compare against the stock numbers)
    for pc, ins in enumerate(bc):
        op = ins & 0xff
        if op in _JUMP_OPS:
            d = ((ins >> 16) & 0xffff) - 0x8000
            target = pc + 1 + d
            j = newpc[pc]
            nd = newpc[target] - (j + 1)
            out[j] = (out[j] & 0xffff) | ((nd + 0x8000) << 16)
    pr['bc'] = out
    if used_scratch:
        h = bytearray(pr['hdr4']); h[2] = scratch + 1; pr['hdr4'] = bytes(h)
    if have_lines:
        pr['debug'] = b''.join(lines) + dbg[len(bc) * w:]
    return pr


def to_t9(ch):
    """stock -> T9. '#name' strings become xhash constants (see _rewrite_proto for the bytecode)."""
    assert not ch['t9']
    for pr in ch['protos']:
        kgc = pr['kgc']
        hashed = set()
        for i, (t, x) in enumerate(kgc):
            if t == 'str' and x[:1] == b'#':
                kgc[i] = ('xhash', xhash_of(x)); hashed.add(i)
            elif t == 'tab':
                items, hsh = x
                fix = lambda v: ('xhash', xhash_of(v[1])) if v[0] == 'str' and v[1][:1] == b'#' else v
                kgc[i] = ('tab', ([fix(v) for v in items], [(fix(k), fix(v)) for k, v in hsh]))
        _rewrite_proto(pr, hashed)
    return ch


def t9_lineinfo_only(ch):
    """Cut a stock (non-stripped) debug block down to T9's line-info-only form."""
    for pr in ch['protos']:
        dbg = pr['debug']
        if not dbg:
            continue
        n = len(pr['bc'])
        w = 4 if pr['numline'] >= 65536 else 2 if pr['numline'] >= 256 else 1
        pr['debug'] = dbg[:n * w]
    return ch


# ---------------------------------------------------------------- lupa-backed compile / verify

def luajit():
    from lupa import luajit21 as lj
    return lj.LuaRuntime(encoding=None)


def compile_source(src_bytes, chunkname=b'=gf', strip=False):
    L = luajit()
    f = L.eval(b'function(src, name, strip) local fn, err = loadstring(src, name); if not fn then return nil, err end; return string.dump(fn, strip) end')
    r = f(src_bytes, chunkname, strip)
    if isinstance(r, tuple) or r is None:
        raise SystemExit('lua compile error: %r' % (r,))
    return bytes(r)


def loads_in_luajit(stock_bytes):
    L = luajit()
    f = L.eval(b'function(bc) local fn, err = loadstring(bc); if fn then return true, "" end; return false, err end')
    ok, err = f(stock_bytes)
    return bool(ok), bytes(err or b'').decode('latin1', 'replace')


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else ''
    if cmd == 'compile':
        src = open(sys.argv[2], 'rb').read()
        stock = compile_source(src, chunkname=b'=' + os.path.basename(sys.argv[2]).encode())
        ch = read_chunk(stock)
        out = write_chunk(t9_lineinfo_only(to_t9(ch)), t9=True, stripped=False)
        open(sys.argv[3], 'wb').write(out)
        print('compiled %s -> %s (%d bytes, %d protos)' % (sys.argv[2], sys.argv[3], len(out), len(ch['protos'])))
    elif cmd == 'to-stock':
        ch = read_chunk(open(sys.argv[2], 'rb').read())
        out = write_chunk(to_stock(ch), t9=False, stripped=True)
        open(sys.argv[3], 'wb').write(out)
        print('wrote', sys.argv[3], len(out))
    elif cmd == 'verify':
        ok = bad = 0
        for f in sys.argv[2:]:
            ch = read_chunk(open(f, 'rb').read())
            stock = write_chunk(to_stock(ch), t9=False, stripped=True)
            good, err = loads_in_luajit(stock)
            if good:
                ok += 1
            else:
                bad += 1; print('FAIL', f, err[:120])
        print('verify: %d load, %d fail' % (ok, bad))
    else:
        print(__doc__)
