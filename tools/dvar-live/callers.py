"""Find E8 rel32 calls to given exe RVAs across executable memory. READ-ONLY."""
import re, sys, time, ctypes, struct
from dvar_pool_scan import Proc, MBI, k32
proc = Proc()
targets = {proc.base + int(a, 16): a for a in sys.argv[1:]}
pat = re.compile(rb"\xe8(....)", re.DOTALL)
EXEC = {0x10, 0x20, 0x40, 0x80}
addr = proc.base; end = proc.base + proc.size; mbi = MBI(); CH = 32 << 20
hits = {t: [] for t in targets}
t0 = time.perf_counter()
while addr < end:
    if not k32.VirtualQueryEx(proc.h, addr, ctypes.byref(mbi), ctypes.sizeof(mbi)): break
    base, size = mbi.BaseAddress, mbi.RegionSize
    if mbi.State == 0x1000 and (mbi.Protect & 0xFF) in EXEC and not (mbi.Protect & 0x100):
        off = 0
        while off < size:
            want = min(CH + 8, size - off)
            buf = proc.read(base + off, want)
            if buf:
                for m in pat.finditer(buf):
                    if m.start() >= CH: break
                    tgt = base + off + m.start() + 5 + struct.unpack("<i", m.group(1))[0]
                    if tgt in hits:
                        hits[tgt].append(base + off + m.start())
            off += CH
    addr = base + size
print(f"scanned in {time.perf_counter()-t0:.1f}s")
for t, lst in hits.items():
    print(f"callers of exe+{t-proc.base:#x}: {len(lst)}")
    for a in lst: print(f"   {proc.rva(a)}")
