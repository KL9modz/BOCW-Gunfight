#!/usr/bin/env python3
"""Embed a compiled T9 .luac as a C byte array for the gf_luihook DLL.

    python tools/lui/gen-bytecode-h.py payloads/gf_loadtest.luac src/gf_luihook/gf_bytecode.h

Writes `static const unsigned char GF_BYTECODE[] = { ... };`. Run after recompiling the chunk:
    python tools/lui/lj2t9.py compile src/gf_lui/gf_loadtest.lua payloads/gf_loadtest.luac
    python tools/lui/lj2t9.py verify  payloads/gf_loadtest.luac      # expect "1 load, 0 fail"
    python tools/lui/gen-bytecode-h.py payloads/gf_loadtest.luac src/gf_luihook/gf_bytecode.h
"""
import sys

def main():
    if len(sys.argv) != 3:
        print(__doc__); return 1
    src, out = sys.argv[1], sys.argv[2]
    bc = open(src, 'rb').read()
    if bc[:4] != b'\x1bLJ\x82':
        print('warning: %s is not a T9 LuaJIT chunk (magic %s)' % (src, bc[:5].hex()))
    rows = ['    ' + ','.join('0x%02x' % b for b in bc[i:i + 16]) + ',' for i in range(0, len(bc), 16)]
    with open(out, 'w', newline='\n') as f:
        f.write('/* %s (%d bytes) - compiled by tools/lui/lj2t9.py from src/gf_lui/gf_loadtest.lua,\n' % (src, len(bc)))
        f.write('   verified correct. Regenerate with tools/lui/gen-bytecode-h.py (see its header). */\n')
        f.write('static const unsigned char GF_BYTECODE[] = {\n')
        f.write('\n'.join(rows) + '\n};\n')
    print('wrote %s (%d bytes, %d rows)' % (out, len(bc), len(rows)))
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
