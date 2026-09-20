"""List live-dvar hashes appearing as 8-byte immediates in a code window (registration order)."""
import sys, csv, struct
from dvar_pool_scan import Proc
proc = Proc()
live = {int(r["hash"],16): r for r in csv.DictReader(open("dvars_cw_live_named.csv", newline="", encoding="utf-8"))}
for arg in sys.argv[1:]:
    lo_s, hi_s = arg.split("-")
    lo, hi = int(lo_s,16), int(hi_s,16)
    buf = proc.read(proc.base + lo, hi - lo)
    print(f"\n=== code exe+{lo:#x}..exe+{hi:#x}  ({len(buf)} bytes)")
    last = None
    for i in range(0, len(buf) - 8):
        v = int.from_bytes(buf[i:i+8], "little")
        if v in live and v != 0:
            r = live[v]
            gap = (lo + i) - last if last is not None else 0
            last = lo + i
            print(f"  exe+{lo+i:#x} (+{gap:#x})  {r['hash']}  {r['name'] or '?':34s} {r['type']:8s} dom=({r['min']},{r['max']}) cur={r['cur']} reset={r['reset']} flags={r['flags']}")
