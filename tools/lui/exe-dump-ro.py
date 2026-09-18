#!/usr/bin/env python3
"""Dump Cold War's DECRYPTED executable out of the RUNNING game, READ-ONLY.

    python tools/lui/exe-dump-ro.py [out.exe]     # default: <repo>/../ACTS/bin/deps/BlackOpsColdWar_dump.exe

The on-disk BlackOpsColdWar.exe is Arxan-encrypted, so ACTS's signature scans (and `acts ljec`, the
Lua compiler) need the DECRYPTED image. ACTS normally gets it with `acts game_dump`, which launches
the exe under a DEBUGGER. This tool gets the same result with only ReadProcessMemory on the already-
running game — the exact read-only access level `tools/lobby-set.py` uses, no debugger, no new
anti-cheat surface. The game must be running and past its Arxan unpack (sitting in any menu/lobby is
enough; a match is not required).

It reproduces ACTS's `exe_dump.cpp::DumpProcess` (scratchpad/dll-re): copy the in-memory image page
by page (skipping uncommitted / no-access / guard pages, like CopyMemorySafe), then patch every
section header so `PointerToRawData = VirtualAddress` (file layout == memory layout). No IAT rebuild —
the cw game config uses none, and `ljec` doesn't need it. The result loads in `acts ljec cw` and any
ACTS tool that takes the dumped exe (its default path is where those tools look for it).

Writes ONLY to disk; touches the game with ReadProcessMemory alone. klaze runs it (it opens the game
process), same as the other read-only probes.
"""
import importlib.util, os, struct, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('lobbyset', os.path.join(HERE, '..', 'lobby-set.py'))
ls = importlib.util.module_from_spec(spec); spec.loader.exec_module(ls)

PAGE_GUARD = 0x100
PAGE_NOACCESS = 0x01
MEM_COMMIT = 0x1000


def read_region(proc, addr, size):
    """Read a committed region in chunks; return bytes (short read tolerated)."""
    out = bytearray()
    off = 0
    while off < size:
        want = min(0x100000, size - off)
        chunk = proc.read(addr + off, want)
        if not chunk:
            break
        out += chunk
        off += len(chunk)
        if len(chunk) < want:
            break
    return bytes(out)


def copy_image_safe(proc, base, total):
    """CopyMemorySafe: walk pages, copy readable committed ones, zero-fill the rest."""
    buf = bytearray(total)
    cur = base
    end = base + total
    while cur < end:
        mbi = proc.query(cur)
        if mbi is None:
            break
        region_base = mbi.BaseAddress
        region_end = region_base + mbi.RegionSize
        if region_end <= cur:
            break
        readable = (mbi.State == MEM_COMMIT
                    and (mbi.Protect & 0xFF) != PAGE_NOACCESS
                    and not (mbi.Protect & PAGE_GUARD)
                    and (mbi.Protect & 0xFF) in ls.READABLE)
        seg_end = min(region_end, end)
        if readable and seg_end > cur:
            data = read_region(proc, cur, seg_end - cur)
            buf[cur - base: cur - base + len(data)] = data
        cur = region_end
    return buf


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.abspath(
        os.path.join(HERE, '..', '..', '..', 'ACTS', 'bin', 'deps', 'BlackOpsColdWar_dump.exe'))
    pid = ls.find_process('BlackOpsColdWar.exe')
    base, modsize = ls.find_module(pid, 'BlackOpsColdWar.exe')
    proc = ls.Proc(pid, write=False)
    print('pid %d, module base %#x, size %#x' % (pid, base, modsize))

    dos = proc.read(base, 0x40)
    if not dos or dos[:2] != b'MZ':
        ls._die('no MZ at module base')
    e_lfanew = struct.unpack_from('<I', dos, 0x3c)[0]
    nt = proc.read(base + e_lfanew, 0x200)               # sig+file+optional64+dirs
    if nt[:4] != b'PE\x00\x00':
        ls._die('no PE signature')
    num_sections = struct.unpack_from('<H', nt, 6)[0]
    size_opt = struct.unpack_from('<H', nt, 20)[0]
    opt = 24                                             # offset of OptionalHeader within nt
    size_of_image = struct.unpack_from('<I', nt, opt + 0x38)[0]
    headers_size = e_lfanew + size_opt + 24
    total = max(size_of_image, headers_size)
    # extend to cover every data directory
    ndir = struct.unpack_from('<I', nt, opt + 0x6c)[0]
    for i in range(min(ndir, 16)):
        va, sz = struct.unpack_from('<II', nt, opt + 0x70 + i * 8)
        total = max(total, va + sz)
    print('SizeOfImage %#x, sections %d, copying %#x bytes...' % (size_of_image, num_sections, total))

    t0 = time.time()
    buf = copy_image_safe(proc, base, total)
    print('copied in %.1fs' % (time.time() - t0))

    # patch section headers: PointerToRawData = VirtualAddress, SizeOfRawData = VirtualSize
    sec0 = e_lfanew + 24 + size_opt
    for i in range(num_sections):
        s = sec0 + i * 40
        vsize = struct.unpack_from('<I', buf, s + 8)[0]
        vaddr = struct.unpack_from('<I', buf, s + 12)[0]
        struct.pack_into('<I', buf, s + 20, vaddr)       # PointerToRawData = VirtualAddress
        if vsize:
            struct.pack_into('<I', buf, s + 16, vsize)   # SizeOfRawData = VirtualSize

    proc.close()
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, 'wb').write(buf)
    print('wrote %s (%#x bytes); use: acts ljec cw <src.lua> <out.luac>' % (out, len(buf)))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
