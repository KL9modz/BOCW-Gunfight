"""Read/write BOCW dvars from an external process, for the Gunfight host control app.

This is the memory layer under gf_control.py. It mirrors tools/lobby-set.py's proven
primitives (OpenProcess + ReadProcessMemory/WriteProcessMemory + VirtualAllocEx +
CreateRemoteThread) - the same access class TAC has tolerated all session on the test
box - and adds a dvar setter built the same way lobby-set.py calls LobbySetMap: alloc
the argument strings, write a tiny stub that loads them into rcx/rdx and calls the
game's own function, run it on a remote thread, free.

SCOPE / GUARD. Per the project guard, the AGENT writes this tool; KLAZE runs anything
that touches game memory. So this defaults to DRY-RUN: it prints what it would write
and touches nothing. Live writes need (a) --live and (b) the dvar-setter signature
CONFIRMED in-game, because BlackOpsColdWar.exe is encrypted at rest and a signature
can only be matched against the decrypted image in memory (lobby-set.py records the
same constraint). Until that sig is confirmed, live mode refuses rather than guessing.

WHY A CONFIRMED SIG AND NOT A GUESS. lobby-set.py cross-validated its LobbySetMap sig
across three sources before trusting it. We have no equally-validated sig for the dvar
setter yet, so `SIG_DVAR_SET` below is a PLACEHOLDER. `python dvar_backend.py --scan`
finds and ranks candidates against the running game; once one is confirmed (see the
README's "confirm the setter" step) paste its bytes into SIG_DVAR_SET and live mode
works. This is the one reverse-engineering step, and it is klaze's to run.

CREDIT: Proc/find_process/find_module/scan are lobby-set.py's, trimmed to what the
control app needs. Keep the two in sync if the memory layer changes.
"""

from __future__ import annotations

import ctypes
import struct
import sys
from ctypes import wintypes

PROC_NAME = "BlackOpsColdWar.exe"

# ---- how we reach the dvar setter --------------------------------------------
# We do NOT guess a signature. ate47's builtin table (t8-atian-menu funcs_cw.csv)
# gives the ADDRESS of the GSC `setdvar` builtin, and that builtin internally calls
# the C dvar-set-from-string function with the two strings. So we read the builtin
# in-game and resolve the call it makes - address-anchored, not sig-guessed.
#
#   RVA = offset from the BlackOpsColdWar.exe module base.
SETDVAR_BUILTIN_RVA = 0x3CD62A0   # GSC setdvar(name,value)  (funcs_cw.csv, this build)
#
# The resolved C setter, as an RVA. 0 until klaze runs `--resolve` and confirms which
# candidate actually moves a dvar (see README, "confirm the setter"). Live writes
# refuse while this is 0, on purpose - firing a stub at the wrong address is worse
# than refusing.
SETTER_RVA = 0
#
# The setter's 3rd arg (r8), if it takes one: Dvar_SetFromStringByName(name, value,
# source). None = call with 2 args. An int = pass it as `source` (T9 wants a valid
# source value or it no-ops the write). Confirm with --try3 which value takes.
SETTER_SOURCE = None
#
# Register order the setter takes its two string args in.
#   "name_value" -> fn(const char* name, const char* value)   rcx=name  rdx=value
#   "value_name" -> fn(const char* value, const char* name)   rcx=value rdx=name
DVAR_SET_ABI = "name_value"
#
# Optional fallback: a validated byte signature, if the address ever drifts across a
# game patch. Empty by default; the RVA path above is preferred.
SIG_DVAR_SET = ""

# ------------------------------------------------------------------ winapi glue
MEM_COMMIT = 0x1000
MEM_RESERVE = 0x2000
MEM_RELEASE = 0x8000
PAGE_READWRITE = 0x04
PAGE_EXECUTE_READWRITE = 0x40
PROCESS_ALL = 0x1F0FFF
TH32_PROC = 0x2
TH32_MODULE = 0x8 | 0x10
INVALID_HANDLE = ctypes.c_void_p(-1).value

_k32 = ctypes.WinDLL("kernel32", use_last_error=True) if sys.platform == "win32" else None


class _PROCENTRY(ctypes.Structure):
    _fields_ = [
        ("dwSize", wintypes.DWORD), ("cntUsage", wintypes.DWORD),
        ("th32ProcessID", wintypes.DWORD),
        ("th32DefaultHeapID", ctypes.POINTER(ctypes.c_ulong)),
        ("th32ModuleID", wintypes.DWORD), ("cntThreads", wintypes.DWORD),
        ("th32ParentProcessID", wintypes.DWORD), ("pcPriClassBase", ctypes.c_long),
        ("dwFlags", wintypes.DWORD), ("szExeFile", ctypes.c_char * 260),
    ]


class _MODENTRY(ctypes.Structure):
    _fields_ = [
        ("dwSize", wintypes.DWORD), ("th32ModuleID", wintypes.DWORD),
        ("th32ProcessID", wintypes.DWORD), ("GlblcntUsage", wintypes.DWORD),
        ("ProccntUsage", wintypes.DWORD), ("modBaseAddr", ctypes.POINTER(ctypes.c_byte)),
        ("modBaseSize", wintypes.DWORD), ("hModule", wintypes.HMODULE),
        ("szModule", ctypes.c_char * 256), ("szExePath", ctypes.c_char * 260),
    ]


class _MBI(ctypes.Structure):
    _fields_ = [
        ("BaseAddress", ctypes.c_ulonglong), ("AllocationBase", ctypes.c_ulonglong),
        ("AllocationProtect", wintypes.DWORD), ("__align", wintypes.DWORD),
        ("RegionSize", ctypes.c_ulonglong), ("State", wintypes.DWORD),
        ("Protect", wintypes.DWORD), ("Type", wintypes.DWORD), ("__align2", wintypes.DWORD),
    ]


class BackendError(RuntimeError):
    pass


def find_process(name: str) -> int:
    snap = _k32.CreateToolhelp32Snapshot(TH32_PROC, 0)
    if snap == INVALID_HANDLE:
        raise BackendError("CreateToolhelp32Snapshot failed")
    try:
        e = _PROCENTRY()
        e.dwSize = ctypes.sizeof(_PROCENTRY)
        ok = _k32.Process32First(snap, ctypes.byref(e))
        while ok:
            if e.szExeFile.decode(errors="ignore").lower() == name.lower():
                return e.th32ProcessID
            ok = _k32.Process32Next(snap, ctypes.byref(e))
    finally:
        _k32.CloseHandle(snap)
    raise BackendError(f"{name} is not running")


def find_module(pid: int, name: str) -> tuple[int, int]:
    snap = _k32.CreateToolhelp32Snapshot(TH32_MODULE, pid)
    if snap == INVALID_HANDLE:
        raise BackendError("module snapshot failed (try running as admin)")
    try:
        e = _MODENTRY()
        e.dwSize = ctypes.sizeof(_MODENTRY)
        ok = _k32.Module32First(snap, ctypes.byref(e))
        while ok:
            if e.szModule.decode(errors="ignore").lower() == name.lower():
                base = ctypes.cast(e.modBaseAddr, ctypes.c_void_p).value
                return base, e.modBaseSize
            ok = _k32.Module32Next(snap, ctypes.byref(e))
    finally:
        _k32.CloseHandle(snap)
    raise BackendError(f"module {name} not found in pid {pid}")


class Proc:
    def __init__(self, pid: int):
        self.h = _k32.OpenProcess(PROCESS_ALL, False, pid)
        if not self.h:
            raise BackendError(
                f"OpenProcess failed (error {ctypes.get_last_error()}). "
                "Run this from an elevated shell."
            )

    def close(self) -> None:
        if self.h:
            _k32.CloseHandle(self.h)
            self.h = None

    def read(self, addr: int, size: int) -> bytes | None:
        buf = (ctypes.c_char * size)()
        got = ctypes.c_size_t(0)
        ok = _k32.ReadProcessMemory(self.h, ctypes.c_void_p(addr), buf, size, ctypes.byref(got))
        return buf.raw[: got.value] if ok else None

    def write(self, addr: int, data: bytes) -> bool:
        put = ctypes.c_size_t(0)
        return bool(_k32.WriteProcessMemory(self.h, ctypes.c_void_p(addr), data, len(data), ctypes.byref(put)))

    def alloc(self, size: int, protect: int) -> int:
        _k32.VirtualAllocEx.restype = ctypes.c_void_p
        p = _k32.VirtualAllocEx(self.h, None, ctypes.c_size_t(size), MEM_COMMIT | MEM_RESERVE, protect)
        if not p:
            raise BackendError(f"VirtualAllocEx failed (error {ctypes.get_last_error()})")
        return p

    def free(self, addr: int) -> None:
        _k32.VirtualFreeEx(self.h, ctypes.c_void_p(addr), 0, MEM_RELEASE)

    def regions(self, writable_only: bool = False):
        """Yield (base, size) for committed, readable memory regions."""
        MEM_COMMIT = 0x1000
        readable = {0x02, 0x04, 0x20, 0x40}          # R, RW, XR, XRW
        writable = {0x04, 0x40}                        # RW, XRW
        addr = 0
        mbi = _MBI()
        while addr < 0x7FFFFFFFFFFF:
            if not _k32.VirtualQueryEx(self.h, ctypes.c_void_p(addr), ctypes.byref(mbi), ctypes.sizeof(mbi)):
                break
            base, size, state, prot = mbi.BaseAddress, mbi.RegionSize, mbi.State, mbi.Protect & 0xFF
            if size == 0:
                break
            ok = state == MEM_COMMIT and prot in (writable if writable_only else readable) \
                and not (mbi.Protect & 0x100)          # skip PAGE_GUARD
            if ok:
                yield base, size
            addr = base + size

    def run(self, addr: int, timeout_ms: int = 5000) -> bool:
        _k32.CreateRemoteThread.restype = wintypes.HANDLE
        thr = _k32.CreateRemoteThread(self.h, None, 0, ctypes.c_void_p(addr), None, 0, None)
        if not thr:
            raise BackendError(f"CreateRemoteThread failed (error {ctypes.get_last_error()})")
        rc = _k32.WaitForSingleObject(thr, timeout_ms)
        _k32.CloseHandle(thr)
        return rc == 0


def _two_arg_stub(func: int, a_rcx: int, a_rdx: int) -> bytes:
    # sub rsp,28 ; mov rcx,a_rcx ; mov rdx,a_rdx ; mov rax,func ; call rax ; add rsp,28 ; ret
    return (
        b"\x48\x83\xEC\x28"
        + b"\x48\xB9" + struct.pack("<Q", a_rcx)
        + b"\x48\xBA" + struct.pack("<Q", a_rdx)
        + b"\x48\xB8" + struct.pack("<Q", func)
        + b"\xFF\xD0"
        + b"\x48\x83\xC4\x28"
        + b"\xC3"
    )


def _three_arg_stub(func: int, a_rcx: int, a_rdx: int, a_r8: int) -> bytes:
    # like above + mov r8, a_r8  (49 B8 imm64). For fn(name, value, source).
    return (
        b"\x48\x83\xEC\x28"
        + b"\x48\xB9" + struct.pack("<Q", a_rcx)
        + b"\x48\xBA" + struct.pack("<Q", a_rdx)
        + b"\x49\xB8" + struct.pack("<Q", a_r8)
        + b"\x48\xB8" + struct.pack("<Q", func)
        + b"\xFF\xD0"
        + b"\x48\x83\xC4\x28"
        + b"\xC3"
    )


class DvarBackend:
    """Config surface for the GUI. In dry-run it records intended writes; in live
    mode it calls the game's dvar setter on a remote thread (needs a confirmed sig)."""

    def __init__(self, dry_run: bool = True):
        self.dry_run = dry_run
        self.proc: Proc | None = None
        self.base = 0
        self.size = 0
        self.setter = 0          # resolved address of the dvar-set function
        self.log: list[str] = []

    # -- lifecycle -------------------------------------------------------------
    def connect(self) -> None:
        if self.dry_run:
            self._log("dry-run: not attaching to the game")
            return
        pid = find_process(PROC_NAME)
        self.proc = Proc(pid)
        self.base, self.size = find_module(pid, PROC_NAME)
        self._log(f"attached pid={pid} base={self.base:#x} size={self.size:#x}")
        self.setter = self._resolve_setter()
        if not self.setter:
            raise BackendError(
                "dvar setter not confirmed yet - live writes refused. Run "
                "`python dvar_backend.py --resolve` in-game, --try the candidates until "
                "one moves a dvar, then set SETTER_RVA (see README, 'confirm the setter')."
            )
        self._log(f"dvar setter @ {self.setter:#x}")

    def close(self) -> None:
        if self.proc:
            self.proc.close()
            self.proc = None

    # -- the one write primitive ----------------------------------------------
    def set_dvar(self, name: str, value) -> None:
        value = str(value)
        if self.dry_run or not self.proc or not self.setter:
            self._log(f'[dry] set {name} {value}')
            return
        raw_n = name.encode("ascii") + b"\x00"
        raw_v = value.encode("ascii") + b"\x00"
        pn = self.proc.alloc(len(raw_n), PAGE_READWRITE)
        pv = self.proc.alloc(len(raw_v), PAGE_READWRITE)
        self.proc.write(pn, raw_n)
        self.proc.write(pv, raw_v)
        rcx, rdx = (pn, pv) if DVAR_SET_ABI == "name_value" else (pv, pn)
        if SETTER_SOURCE is None:
            stub = _two_arg_stub(self.setter, rcx, rdx)
        else:
            stub = _three_arg_stub(self.setter, rcx, rdx, SETTER_SOURCE)
        pc = self.proc.alloc(len(stub), PAGE_EXECUTE_READWRITE)
        self.proc.write(pc, stub)
        ok = self.proc.run(pc)
        self.proc.free(pc)
        self.proc.free(pn)
        self.proc.free(pv)
        self._log(f'set {name} {value}  ' + ("ok" if ok else "TIMED OUT"))

    def apply(self, settings: dict) -> None:
        """Write a batch of gf_* dvars. Config takes effect next round (mod_apply)."""
        for k, v in settings.items():
            self.set_dvar(k, v)

    # -- internals -------------------------------------------------------------
    def _resolve_setter(self) -> int:
        if SETTER_RVA:
            return self.base + SETTER_RVA
        if SIG_DVAR_SET:
            hits = self._scan(SIG_DVAR_SET)
            return hits[0] if hits else 0
        return 0

    def resolve_candidates(self) -> list[int]:
        """Read the setdvar builtin and decode the near-call (E8) targets it makes -
        candidate C dvar-setters. Same E8 rel32 math as lobby-set.py's resolve_call."""
        addr = self.base + SETDVAR_BUILTIN_RVA
        code = self.proc.read(addr, 0x220)
        if not code:
            raise BackendError(f"could not read the setdvar builtin at {addr:#x} "
                               "(is this the right game build? check funcs_cw.csv)")
        out: list[int] = []
        for i in range(len(code) - 5):
            if code[i] == 0xE8:  # call rel32
                rel = int.from_bytes(code[i + 1:i + 5], "little", signed=True)
                tgt = addr + i + 5 + rel
                if self.base <= tgt < self.base + self.size and tgt not in out:
                    out.append(tgt)
        return out

    def call(self, func: int, name: str, value: str, source: int | None = None) -> bool:
        """Call func(name, value[, source]) once on a remote thread. For --try, to test
        a candidate setter without editing the file. source=None -> 2-arg call."""
        raw_n = name.encode("ascii") + b"\x00"
        raw_v = value.encode("ascii") + b"\x00"
        pn = self.proc.alloc(len(raw_n), PAGE_READWRITE)
        pv = self.proc.alloc(len(raw_v), PAGE_READWRITE)
        self.proc.write(pn, raw_n)
        self.proc.write(pv, raw_v)
        rcx, rdx = (pn, pv) if DVAR_SET_ABI == "name_value" else (pv, pn)
        if source is None:
            stub = _two_arg_stub(func, rcx, rdx)
        else:
            stub = _three_arg_stub(func, rcx, rdx, source)
        pc = self.proc.alloc(len(stub), PAGE_EXECUTE_READWRITE)
        self.proc.write(pc, stub)
        ok = self.proc.run(pc)
        self.proc.free(pc); self.proc.free(pn); self.proc.free(pv)
        return ok

    def _scan(self, sig: str) -> list[int]:
        import re
        pat = b"".join(
            (b"." if tok == "??" else re.escape(bytes([int(tok, 16)])))
            for tok in sig.split()
        )
        rx = re.compile(pat, re.DOTALL)
        hits: list[int] = []
        step = 0x100000
        for off in range(0, self.size, step):
            chunk = self.proc.read(self.base + off, min(step + 32, self.size - off))
            if not chunk:
                continue
            for m in rx.finditer(chunk):
                hits.append(self.base + off + m.start())
        return hits

    def _log(self, msg: str) -> None:
        self.log.append(msg)


def _attach() -> DvarBackend:
    pid = find_process(PROC_NAME)
    be = DvarBackend(dry_run=False)
    be.proc = Proc(pid)
    be.base, be.size = find_module(pid, PROC_NAME)
    return be


def _find_bytes(be: "DvarBackend", needle: bytes, writable_only: bool, cap: int = 64) -> list[int]:
    hits: list[int] = []
    for base, size in be.proc.regions(writable_only):
        off = 0
        step = 0x400000
        while off < size:
            chunk = be.proc.read(base + off, min(step + len(needle), size - off))
            if chunk:
                i = chunk.find(needle)
                while i != -1:
                    hits.append(base + off + i)
                    if len(hits) >= cap:
                        return hits
                    i = chunk.find(needle, i + 1)
            off += step
    return hits


def dvar_hash(name: str) -> int:
    """FNV1a-63, the hash GSC compiles #\"name\" to (same as tools/crack-hash.py)."""
    h = 0xCBF29CE484222325
    for c in name.lower():
        h = ((h ^ ord(c)) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h & 0x7FFFFFFFFFFFFFFF


def _dump_struct(be: "DvarBackend", where: int, label: str) -> None:
    print(f"  {label} @ {where:#x}")
    blob = be.proc.read(where, 0x50)
    if blob:
        for i in range(0, len(blob), 8):
            q = int.from_bytes(blob[i:i + 8], "little")
            print(f"    +{i:02X}: {q:#018x}")


def _finddvar(name: str, expect: int | None = None) -> int:
    """--finddvar <name> [expected-int]: locate a dvar's struct (READ-ONLY) by its hash.
    If expected-int is given (a value the dvar holds RIGHT NOW, e.g. com_maxclients 12),
    every offset of each candidate struct is searched for that value and the matching
    offset printed - that pins the value field with no guessing and no menu action."""
    be = _attach()
    h = dvar_hash(name)
    print(f"base={be.base:#x}  dvar {name!r}  hash={h:#018x}"
          + (f"  expecting value {expect}" if expect is not None else ""))

    # 1) find the hash as a u64 key in writable memory (the dvar registry)
    hkey = struct.pack("<Q", h)
    hrefs = _find_bytes(be, hkey, writable_only=True, cap=24)

    # The real registry entry looks like: +00 hash, +08 == 0x0002000f (int-dvar
    # type/flags), +10 = a pointer into the module (the type descriptor). Everything
    # else that merely contains this qword is a false positive (menu tables etc.).
    registry = []
    for r in hrefs:
        blob = be.proc.read(r, 0x30)
        if not blob or len(blob) < 0x18:
            continue
        f08 = int.from_bytes(blob[0x08:0x10], "little")
        f10 = int.from_bytes(blob[0x10:0x18], "little")
        if (f08 & 0xFFFFFFFF) == 0x0002000F and be.base <= f10 < be.base + be.size:
            registry.append(r)

    # Which structs to inspect: the filtered registry entries, or (if the filter
    # matched nothing) every hash sighting, since a read-only value hunt is harmless.
    targets = registry if registry else hrefs
    print(f"\n{len(hrefs)} hash sightings, {len(registry)} match the registry signature.")
    for r in targets:
        blob = be.proc.read(r, 0x60)
        if not blob:
            continue
        if expect is not None:
            found = [off for off in range(0x08, 0x60, 4)
                     if int.from_bytes(blob[off:off + 4], "little") == expect]
            tag = ("  <<< value at +" + ",+".join(f"{o:#x}" for o in found)) if found else ""
            print(f"  entry @ {r:#x}{tag}")
        else:
            v = {off: int.from_bytes(blob[off:off + 4], "little") for off in (0x18, 0x20, 0x28)}
            print(f"  entry @ {r:#x}  +18={v[0x18]} +20={v[0x20]} +28={v[0x28]}")

    # 2) also try the ASCII name -> pointers to it (if the build retained names)
    names = _find_bytes(be, name.encode("ascii") + b"\x00", writable_only=False, cap=8)
    if names:
        print(f"\nASCII name string at: {', '.join(f'{a:#x}' for a in names)}")
        for na in names:
            refs = _find_bytes(be, struct.pack("<Q", na), writable_only=True, cap=6)
            for r in refs:
                _dump_struct(be, r, "name-ptr field @")
    else:
        print("\n(no ASCII name in memory - expected; GSC keys dvars by hash)")

    if not hrefs and not names:
        print("\nnothing found - open the menu or Apply once so the dvar is created, then retry.")
        be.close(); return 1
    be.close(); return 0


def _dump(rva_hex: str, length_hex: str = "0x120") -> int:
    """--dump 0xRVA [len]: hexdump module memory (READ-ONLY, no code runs, safe even
    if the game is wedged). Used to read the setdvar builtin so its real call target
    and arg count can be identified without hammering candidates."""
    be = _attach()
    rva = int(rva_hex, 16)
    length = int(length_hex, 16)
    data = be.proc.read(be.base + rva, length)
    if not data:
        print(f"read failed at base+{rva:#x}")
        be.close(); return 1
    print(f"base={be.base:#x}  dump base+{rva:#x} ({length} bytes):")
    for i in range(0, len(data), 16):
        row = data[i:i + 16]
        hexs = " ".join(f"{b:02X}" for b in row)
        print(f"  +{rva + i:07X}  {hexs}")
    be.close(); return 0


def _resolve() -> int:
    """--resolve: read the setdvar builtin in-game and print the C-setter candidates
    it calls, as RVAs to try. klaze runs this, then --try each until one moves a dvar."""
    be = _attach()
    print(f"attached base={be.base:#x}  setdvar builtin @ base+{SETDVAR_BUILTIN_RVA:#x}")
    cands = be.resolve_candidates()
    if not cands:
        print("no E8 call targets found - wrong build/offset? verify funcs_cw.csv vs this exe.")
        be.close(); return 1
    print(f"{len(cands)} candidate setter(s) - try each with --try, watch a dvar move:")
    for a in cands:
        print(f"  RVA 0x{a - be.base:X}   (abs {a:#x})")
    print("\nnext:  python dvar_backend.py --try 0x<RVA> gf_menu_lines 6")
    print("       then open the in-game menu - if the rows change, that RVA is the setter.")
    print("       put it in SETTER_RVA and live mode works.")
    be.close(); return 0


def _try(rva_hex: str, name: str, value: str, source: int | None = None) -> int:
    """--try 0xRVA name value [source]: call that address once, as fn(name,value) or
    fn(name,value,source) when a source int is given."""
    be = _attach()
    func = be.base + int(rva_hex, 16)
    shown = f'("{name}", "{value}"' + (f", {source})" if source is not None else ")")
    print(f"calling {func:#x}{shown} ...")
    ok = be.call(func, name, value, source)
    print("  returned" if ok else "  TIMED OUT - wrong target or wedged; game may need a look")
    be.close(); return 0 if ok else 1


if __name__ == "__main__":
    a = sys.argv
    if "--finddvar" in a:
        i = a.index("--finddvar")
        expect = None
        if len(a) > i + 2 and not a[i + 2].startswith("-"):
            try:
                expect = int(a[i + 2], 0)
            except ValueError:
                expect = None
        raise SystemExit(_finddvar(a[i + 1], expect))
    if "--dumpabs" in a:
        i = a.index("--dumpabs")
        length = int(a[i + 2], 16) if len(a) > i + 2 else 0x60
        be = _attach()
        addr = int(a[i + 1], 16)
        blob = be.proc.read(addr, length)
        if blob:
            print(f"dump {addr:#x} ({length} bytes):")
            for j in range(0, len(blob), 8):
                q = int.from_bytes(blob[j:j + 8], "little")
                lo = q & 0xFFFFFFFF
                hi = q >> 32
                print(f"  +{j:02X}: {q:#018x}   (lo={lo} hi={hi})")
        else:
            print(f"read failed at {addr:#x}")
        be.close()
        raise SystemExit(0)
    if "--dump" in a:
        i = a.index("--dump")
        raise SystemExit(_dump(a[i + 1], a[i + 2] if len(a) > i + 2 else "0x120"))
    if "--resolve" in a:
        raise SystemExit(_resolve())
    if "--try3" in a:
        i = a.index("--try3")
        try:
            raise SystemExit(_try(a[i + 1], a[i + 2], a[i + 3], int(a[i + 4], 0)))
        except (IndexError, ValueError):
            print("usage: python dvar_backend.py --try3 0x<RVA> <dvar> <value> <source-int>")
            raise SystemExit(2)
    if "--try" in a:
        i = a.index("--try")
        try:
            raise SystemExit(_try(a[i + 1], a[i + 2], a[i + 3]))
        except IndexError:
            print("usage: python dvar_backend.py --try 0x<RVA> <dvar> <value>")
            raise SystemExit(2)
    print("dvar_backend is the memory layer for gf_control.py.")
    print("Run the GUI:   python gf_control.py          (dry-run)")
    print("               python gf_control.py --live    (writes dvars; needs SETTER_RVA)")
    print("Confirm setter: python dvar_backend.py --resolve      (in-game)")
    print("                python dvar_backend.py --try 0x<RVA> gf_menu_lines 6")
