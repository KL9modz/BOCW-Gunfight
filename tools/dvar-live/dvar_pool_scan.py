"""READ-ONLY dvar registry scan of the live BOCW process (no writes, no remote threads).

Step 1 (--find): hash-scan private RW memory for the fnv1a63 of a few KNOWN dvar names,
validate each hit as a BO4-shaped dvar_t (hash@0, null@8, hashnext@0x10, DvarData*@0x18,
type@0x20, flags@0x24, domain@0x28) and print an annotated dump.
Step 2 (--pool <dvar_t addr>): find the pointer array that references it, walk it, dump every
dvar (hash, type, flags, domain, current value) to dvars_cw_live.csv.
"""
import ctypes, re, struct, sys, time, csv
from ctypes import wintypes

MASK64 = 0xFFFFFFFFFFFFFFFF
def fnv1a63(s):
    h = 0xcbf29ce484222325
    for c in s.lower().encode():
        h ^= c
        h = (h * 0x100000001b3) & MASK64
    return h & 0x7FFFFFFFFFFFFFFF

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
PROCESS_VM_READ = 0x10; PROCESS_QUERY_INFORMATION = 0x400
MEM_COMMIT = 0x1000; MEM_PRIVATE = 0x20000; MEM_IMAGE = 0x1000000; PAGE_GUARD = 0x100
WRITABLE = {0x04, 0x08, 0x40, 0x80}

class MBI(ctypes.Structure):
    _fields_ = [("BaseAddress", ctypes.c_ulonglong), ("AllocationBase", ctypes.c_ulonglong),
                ("AllocationProtect", wintypes.DWORD), ("__a", wintypes.DWORD),
                ("RegionSize", ctypes.c_ulonglong), ("State", wintypes.DWORD),
                ("Protect", wintypes.DWORD), ("Type", wintypes.DWORD), ("__b", wintypes.DWORD)]
class MODENTRY(ctypes.Structure):
    _fields_ = [("dwSize", wintypes.DWORD), ("th32ModuleID", wintypes.DWORD), ("th32ProcessID", wintypes.DWORD),
                ("GlblcntUsage", wintypes.DWORD), ("ProccntUsage", wintypes.DWORD),
                ("modBaseAddr", ctypes.POINTER(ctypes.c_byte)), ("modBaseSize", wintypes.DWORD),
                ("hModule", wintypes.HMODULE), ("szModule", ctypes.c_char * 256), ("szExePath", ctypes.c_char * 260)]
class PROCENTRY(ctypes.Structure):
    _fields_ = [("dwSize", wintypes.DWORD), ("cntUsage", wintypes.DWORD), ("th32ProcessID", wintypes.DWORD),
                ("th32DefaultHeapID", ctypes.POINTER(ctypes.c_ulong)), ("th32ModuleID", wintypes.DWORD),
                ("cntThreads", wintypes.DWORD), ("th32ParentProcessID", wintypes.DWORD),
                ("pcPriClassBase", ctypes.c_long), ("dwFlags", wintypes.DWORD), ("szExeFile", ctypes.c_char * 260)]

k32.OpenProcess.restype = wintypes.HANDLE
k32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
k32.ReadProcessMemory.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
k32.VirtualQueryEx.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.POINTER(MBI), ctypes.c_size_t]
k32.VirtualQueryEx.restype = ctypes.c_size_t
k32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
INVALID = ctypes.c_void_p(-1).value

def find_pid(name="BlackOpsColdWar.exe"):
    snap = k32.CreateToolhelp32Snapshot(0x2, 0)
    e = PROCENTRY(); e.dwSize = ctypes.sizeof(PROCENTRY)
    ok = k32.Process32First(snap, ctypes.byref(e))
    while ok:
        if e.szExeFile.decode(errors="ignore").lower() == name.lower():
            k32.CloseHandle(snap); return e.th32ProcessID
        ok = k32.Process32Next(snap, ctypes.byref(e))
    k32.CloseHandle(snap); return 0

def module_range(pid, name="BlackOpsColdWar.exe"):
    snap = k32.CreateToolhelp32Snapshot(0x18, pid)
    e = MODENTRY(); e.dwSize = ctypes.sizeof(MODENTRY)
    ok = k32.Module32First(snap, ctypes.byref(e))
    while ok:
        if e.szModule.decode(errors="ignore").lower() == name.lower():
            k32.CloseHandle(snap)
            return ctypes.cast(e.modBaseAddr, ctypes.c_void_p).value, e.modBaseSize
        ok = k32.Module32Next(snap, ctypes.byref(e))
    k32.CloseHandle(snap); return None

class Proc:
    def __init__(self):
        self.pid = find_pid()
        if not self.pid: raise SystemExit("game not running")
        self.h = k32.OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, False, self.pid)
        if not self.h: raise SystemExit(f"OpenProcess failed: {ctypes.get_last_error()}")
        self.base, self.size = module_range(self.pid)
    def read(self, addr, n):
        buf = ctypes.create_string_buffer(n); got = ctypes.c_size_t(0)
        if k32.ReadProcessMemory(self.h, addr, buf, n, ctypes.byref(got)) and got.value:
            return buf.raw[:got.value]
        return None
    def u64(self, addr):
        b = self.read(addr, 8); return int.from_bytes(b, "little") if b and len(b) == 8 else None
    def u32(self, addr):
        b = self.read(addr, 4); return int.from_bytes(b, "little") if b and len(b) == 4 else None
    def f32(self, addr):
        b = self.read(addr, 4); return struct.unpack("<f", b)[0] if b and len(b) == 4 else None
    def regions(self, image_only=False):
        addr = 0; mbi = MBI()
        while addr < 0x7FFFFFFFFFFF:
            if not k32.VirtualQueryEx(self.h, addr, ctypes.byref(mbi), ctypes.sizeof(mbi)): break
            base, size = mbi.BaseAddress or 0, mbi.RegionSize
            if size == 0: break
            if mbi.State == MEM_COMMIT and (mbi.Protect & 0xFF) in WRITABLE and not (mbi.Protect & PAGE_GUARD):
                inimg = self.base <= base < self.base + self.size
                if not image_only or inimg:
                    yield base, size, mbi.Type, inimg
            addr = base + size
    def rva(self, a):
        return f"exe+{a - self.base:#x}" if self.base <= a < self.base + self.size else f"{a:#x}"

def scan_for(proc, needles, image_first=True, limit_regions=None, cap=64):
    """Scan writable memory for any of the byte needles. Returns {needle: [addr,...]}."""
    pat = re.compile(b"|".join(re.escape(n) for n in needles))
    hits = {n: [] for n in needles}
    regs = list(proc.regions())
    regs.sort(key=lambda r: (0 if r[3] else 1, -r[1]))
    STEP = 8 << 20
    t0 = time.perf_counter(); nbytes = 0
    for base, size, typ, inimg in regs:
        off = 0
        while off < size:
            want = min(STEP + 16, size - off)
            b = proc.read(base + off, want)
            if b:
                nbytes += len(b)
                for m in pat.finditer(b):
                    hits[m.group(0)].append(base + off + m.start())
            off += STEP
        if all(len(v) >= 1 for v in hits.values()) and image_first:
            pass
    print(f"scanned {nbytes/1e9:.2f} GB in {time.perf_counter()-t0:.1f}s")
    return hits

TYPES = {0:"INVALID",1:"BOOL",2:"FLOAT",3:"FLOAT_2",4:"FLOAT_3",5:"FLOAT_4",6:"INT",7:"ENUM",8:"STRING",9:"COLOR",
         10:"INT64",11:"UINT64",12:"LINEAR_COLOR_RGB",13:"COLOR_XYZ",14:"COLOR_LAB",15:"SESSIONMODE_BASE"}

def describe(proc, a, names_by_hash=None):
    """Interpret a as a BO4-shaped dvar_t; return dict or None."""
    b = proc.read(a, 0x40)
    if not b or len(b) < 0x40: return None
    h, null, nxt, val, typ, flags = struct.unpack_from("<QQQQIi", b, 0)
    if h >> 63 or typ < 1 or typ > 15: return None
    d = {"addr": a, "hash": h, "null": null, "next": nxt, "valptr": val, "type": typ, "flags": flags & 0xFFFFFFFF}
    dom = b[0x28:0x38]
    if typ in (2, 3, 4, 5):
        d["min"], d["max"] = struct.unpack_from("<ff", dom, 0)
    elif typ in (6, 7):
        d["min"], d["max"] = struct.unpack_from("<ii", dom, 0)
    else:
        d["min"], d["max"] = struct.unpack_from("<qq", dom, 0)
    cur = proc.read(val, 0x40) if val else None
    d["cur"] = None
    if cur and len(cur) == 0x40:
        if typ == 1: d["cur"] = bool(cur[0])
        elif typ == 2: d["cur"] = struct.unpack_from("<f", cur, 0)[0]
        elif typ in (3,4,5): d["cur"] = struct.unpack_from("<4f", cur, 0)[:typ-1]
        elif typ in (6,7): d["cur"] = struct.unpack_from("<i", cur, 0)[0]
        elif typ == 8:
            p = struct.unpack_from("<Q", cur, 0)[0]
            s = proc.read(p, 64) if p else None
            d["cur"] = s.split(b"\0",1)[0].decode(errors="replace") if s else None
        elif typ in (10, 11): d["cur"] = struct.unpack_from("<q", cur, 0)[0]
        else: d["cur"] = cur[:16].hex()
        # reset (default) value = third DvarValue
        if typ == 2: d["reset"] = struct.unpack_from("<f", cur, 0x20)[0]
        elif typ in (6,7): d["reset"] = struct.unpack_from("<i", cur, 0x20)[0]
        elif typ == 1: d["reset"] = bool(cur[0x20])
        else: d["reset"] = None
    return d

def fmt(d, name=""):
    return (f"{proc.rva(d['addr']):>16} hash={d['hash']:016x} {name:<34} {TYPES.get(d['type'],'?'):<8} "
            f"flags={d['flags']:#010x} dom=({d['min']},{d['max']}) cur={d['cur']!r} reset={d.get('reset')!r} "
            f"val@{d['valptr']:#x} next={d['next']:#x} null={d['null']}")

if __name__ == "__main__":
    proc = Proc()
    print(f"pid {proc.pid}  exe @ {proc.base:#x} size {proc.size:#x}")
    if sys.argv[1:] and sys.argv[1] == "--find":
        names = sys.argv[2:] or ["bg_gravity", "slide_subsequentslidescale", "slide_forcebaseslide", "slide_cameraclamp",
                                 "slide_camerapitchoffset", "slide_blur_enabled", "com_maxclients", "player_sprinttime"]
        needles = {struct.pack("<Q", fnv1a63(n)): n for n in names}
        hits = scan_for(proc, list(needles))
        for nd, addrs in hits.items():
            name = needles[nd]
            print(f"\n== {name}  hash={fnv1a63(name):016x}  sightings={len(addrs)}")
            for a in addrs[:12]:
                d = describe(proc, a)
                if d: print("   dvar_t? ", fmt(d, name))
                else: print(f"   {proc.rva(a):>16}  (not dvar_t-shaped)")
    elif sys.argv[1:] and sys.argv[1] == "--pool":
        target = int(sys.argv[2], 16)
        needle = struct.pack("<Q", target)
        hits = scan_for(proc, [needle])[needle]
        print(f"pointers to {target:#x}: {len(hits)}")
        for a in hits[:20]:
            print("  ", proc.rva(a))
    else:
        print(__doc__)
