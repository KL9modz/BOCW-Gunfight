"""Map every live dvar hash to the code address(es) where it appears as a mov r64, imm64 immediate. READ-ONLY."""
import re, csv, time, struct, ctypes
from dvar_pool_scan import Proc, MBI, k32
proc = Proc()
live = {int(r["hash"],16): r for r in csv.DictReader(open("dvars_cw_live_named.csv", newline="", encoding="utf-8"))}
pat = re.compile(rb"[\x48\x49][\xb8-\xbf](.{7}[\x00-\x7f])", re.DOTALL)
EXEC = {0x10, 0x20, 0x40, 0x80}
sites = []   # (code_addr, hash)
t0 = time.perf_counter(); nbytes = 0; nregs = 0
addr = proc.base; end = proc.base + proc.size
mbi = MBI()
CH = 32 << 20
while addr < end:
    if not k32.VirtualQueryEx(proc.h, addr, ctypes.byref(mbi), ctypes.sizeof(mbi)): break
    base, size = mbi.BaseAddress, mbi.RegionSize
    if mbi.State == 0x1000 and (mbi.Protect & 0xFF) in EXEC and not (mbi.Protect & 0x100):
        nregs += 1
        off = 0
        while off < size:
            want = min(CH + 16, size - off)
            buf = proc.read(base + off, want)
            if buf:
                nbytes += len(buf)
                for m in pat.finditer(buf):
                    if m.start() >= CH: break
                    h = int.from_bytes(m.group(1), "little")
                    if h in live:
                        sites.append((base + off + m.start() + 2, h))
            off += CH
    addr = base + size
print(f"exec regions {nregs}, {nbytes/1e6:.0f} MB scanned in {time.perf_counter()-t0:.1f}s, sites {len(sites)}")
sites.sort()
with open("dvar_regmap.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f); w.writerow(["code", "hash", "name", "type", "min", "max", "cur", "reset", "flags"])
    for a, h in sites:
        r = live[h]
        w.writerow([proc.rva(a), r["hash"], r["name"], r["type"], r["min"], r["max"], r["cur"], r["reset"], r["flags"]])
covered = {h for _, h in sites}
print(f"dvars with >=1 site: {len(covered)} / {len(live)}")
