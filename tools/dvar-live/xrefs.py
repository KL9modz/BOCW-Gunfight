"""Find RIP-relative `mov r64, [rip+disp32]` reads of a target address range across executable memory. READ-ONLY."""
import re, sys, time, ctypes, struct
from dvar_pool_scan import Proc, MBI, k32
proc = Proc()
lo = proc.base + int(sys.argv[1], 16); hi = proc.base + int(sys.argv[2], 16)
# 48/4C 8B modrm(00 reg 101) disp32   |  also 48 8B 05.. for rax
pat = re.compile(rb"[\x48\x4c]\x8b[\x05\x0d\x15\x1d\x25\x2d\x35\x3d](....)", re.DOTALL)
EXEC = {0x10, 0x20, 0x40, 0x80}
addr = proc.base; end = proc.base + proc.size; mbi = MBI(); CH = 32 << 20
hits = []
t0 = time.perf_counter()
while addr < end:
    if not k32.VirtualQueryEx(proc.h, addr, ctypes.byref(mbi), ctypes.sizeof(mbi)): break
    base, size = mbi.BaseAddress, mbi.RegionSize
    if mbi.State == 0x1000 and (mbi.Protect & 0xFF) in EXEC and not (mbi.Protect & 0x100):
        off = 0
        while off < size:
            want = min(CH + 16, size - off)
            buf = proc.read(base + off, want)
            if buf:
                for m in pat.finditer(buf):
                    if m.start() >= CH: break
                    disp = struct.unpack("<i", m.group(1))[0]
                    ins = base + off + m.start()
                    tgt = ins + 7 + disp
                    if lo <= tgt < hi:
                        hits.append((ins, tgt))
            off += CH
    addr = base + size
hits.sort()
print(f"{len(hits)} reads of [{proc.rva(lo)}..{proc.rva(hi)}) in {time.perf_counter()-t0:.1f}s")
for ins, tgt in hits:
    print(f"  {proc.rva(ins):>16}  reads slot {proc.rva(tgt)}  (+{(tgt-lo)//8})")
