"""Dump EVERY dvar_t in the static dvar arena of the live BOCW process. READ-ONLY.

CW dvar_t (0x40 bytes, measured 2026-09-19 on the live game):
  +0x00 u64 hash (fnv1a63 of the lowercase name)
  +0x08 dvar_t* hashnext (0 or a pointer into the exe image range - the arena is static)
  +0x10 DvarData* value   (4 x 0x20: current, latched, reset, spare)
  +0x18 u32 type          (1 BOOL 2 FLOAT 3-5 FLOAT_2/3/4 6 INT 7 ENUM 8 STRING ...)
  +0x1c u32 flags
  +0x20 domain            (float min,max | int min,max)
  +0x28.. unused
"""
import sys, struct, csv, re, time
from dvar_pool_scan import Proc, MBI, k32, ctypes

TYPES = {0: "INVALID", 1: "BOOL", 2: "FLOAT", 3: "FLOAT_2", 4: "FLOAT_3", 5: "FLOAT_4", 6: "INT", 7: "ENUM",
         8: "STRING", 9: "COLOR", 10: "INT64", 11: "UINT64", 12: "LINEAR_COLOR_RGB", 13: "COLOR_XYZ",
         14: "COLOR_LAB", 15: "SESSIONMODE_BASE"}

proc = Proc()
anchor = proc.base + int(sys.argv[1], 16)
mbi = MBI()
k32.VirtualQueryEx(proc.h, anchor, ctypes.byref(mbi), ctypes.sizeof(mbi))
rbase, rsize = mbi.BaseAddress, mbi.RegionSize
print(f"region: {proc.rva(rbase)} size {rsize:#x}")
t0 = time.perf_counter()
CH = 16 << 20
exe_lo, exe_hi = proc.base, proc.base + proc.size
b5 = bytes([(exe_lo >> 32) & 0xff]); b5b = bytes([(exe_hi >> 32) & 0xff])
PTR = rb".{4}[" + re.escape(b5) + b"-" + re.escape(b5b) + rb"]\x7f\x00\x00"
pat = re.compile(rb".{7}[\x00-\x7f](?:\x00{8}|" + PTR + rb")" + PTR + rb"[\x01-\x0f]\x00\x00\x00", re.DOTALL)
recs = []
off = 0
while off < rsize:
    want = min(CH + 0x100, rsize - off)
    buf = proc.read(rbase + off, want)
    if buf:
        for m in pat.finditer(buf):
            i = m.start()
            if i >= CH:
                break
            a = rbase + off + i
            if a % 16:
                continue
            h, nxt, val, typ, flags = struct.unpack_from("<QQQII", buf, i)
            if h == 0 or not (exe_lo <= val < exe_hi) or val % 16:
                continue
            if nxt and (not (exe_lo <= nxt < exe_hi) or nxt % 16):
                continue
            cur = proc.read(val, 0x80)
            dom = buf[i + 0x20:i + 0x28] if i + 0x28 <= len(buf) else b"\0" * 8
            if typ in (2, 3, 4, 5):
                mn, mx = struct.unpack("<ff", dom)
            else:
                mn, mx = struct.unpack("<ii", dom)

            def dv(o):
                if not cur or len(cur) < o + 0x20:
                    return None
                if typ == 1:
                    return int(cur[o])
                if typ == 2:
                    return round(struct.unpack_from("<f", cur, o)[0], 6)
                if typ in (3, 4, 5):
                    return " ".join(f"{x:.4g}" for x in struct.unpack_from("<4f", cur, o)[:typ - 1])
                if typ in (6, 7):
                    return struct.unpack_from("<i", cur, o)[0]
                if typ == 8:
                    p = struct.unpack_from("<Q", cur, o)[0]
                    s = proc.read(p, 96) if 0x10000 <= p < 0x7fffffffffff else None
                    return s.split(b"\0", 1)[0].decode(errors="replace") if s else f"ptr:{p:#x}"
                if typ in (10, 11):
                    return struct.unpack_from("<q", cur, o)[0]
                return cur[o:o + 8].hex()

            recs.append({"addr": proc.rva(a), "valaddr": proc.rva(val), "hash": f"{h:016x}",
                         "type": TYPES.get(typ, "?"), "flags": f"{flags:#x}", "min": mn, "max": mx,
                         "cur": dv(0), "latched": dv(0x20), "reset": dv(0x40)})
    off += CH
print(f"records: {len(recs)} in {time.perf_counter() - t0:.1f}s")
out = sys.argv[2] if len(sys.argv) > 2 else "dvars_cw_live.csv"
with open(out, "w", newline="", encoding="utf-8", errors="replace") as f:
    w = csv.DictWriter(f, fieldnames=["addr", "valaddr", "hash", "type", "flags", "min", "max", "cur", "latched", "reset"])
    w.writeheader()
    w.writerows(recs)
print("wrote", out)
from collections import Counter
print(Counter(r["type"] for r in recs))
print("unique hashes:", len({r["hash"] for r in recs}))
