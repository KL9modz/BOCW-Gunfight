"""roster_scan.py - read the mod's connected-player roster out of the running game. READ-ONLY.

The bridge is app -> game only and the GSC dvar store cannot be read from outside (see the
hud-and-control-app notes), so `gunfight_menu.gsc` publishes the roster the other way round:
`roster_publish()` keeps ONE marked string alive in `level.gf_roster`,

    GFROSTER|<gettime>|<count>|<name>;<team>;<host|bot|human>;<xuid>|...|END

rebuilt only when the roster changes. The script string heap holds it in plain ASCII while
it is referenced, so a plain ReadProcessMemory sweep of the game's private writable memory
finds it. That sweep is the same read-only primitive `dvar_backend.py --finddvar` proved safe
in a live match (no thread, no write, no lock) - it is the ONLY thing this module does to the
game: OpenProcess(VM_READ | QUERY_INFORMATION), VirtualQueryEx, ReadProcessMemory.

    python roster_scan.py            # print the roster + timing (needs the game + the menu injected)
    python roster_scan.py --loop     # every 5 s

The marker is assembled at runtime in the GSC ("GFRO" + "STER") so the payload's own string
table never carries a decoy; here the whole marker is searched. Stale copies (a freed string
the pool has not reused yet) parse fine, so the newest tick wins.
"""
from __future__ import annotations

import ctypes
import re
import sys
import time
from ctypes import wintypes
from dataclasses import dataclass, field

try:
    import gf_native
except Exception:  # pragma: no cover - standalone use
    gf_native = None

_k32 = ctypes.WinDLL("kernel32", use_last_error=True)

PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_VM_READ = 0x0010
MEM_COMMIT = 0x1000
MEM_PRIVATE = 0x20000
PAGE_GUARD = 0x100
_WRITABLE = {0x04, 0x40}           # PAGE_READWRITE, PAGE_EXECUTE_READWRITE

MARK = b"GFROSTER|"
END = b"|END"
_MARK_RE = re.compile(re.escape(MARK))
MAX_LEN = 4096                     # a roster line is a few hundred bytes; cap the parse window


class _MBI(ctypes.Structure):
    _fields_ = [("BaseAddress", ctypes.c_void_p), ("AllocationBase", ctypes.c_void_p),
                ("AllocationProtect", wintypes.DWORD), ("PartitionId", wintypes.WORD),
                ("RegionSize", ctypes.c_size_t), ("State", wintypes.DWORD),
                ("Protect", wintypes.DWORD), ("Type", wintypes.DWORD)]


class _MODENTRY(ctypes.Structure):
    _fields_ = [("dwSize", wintypes.DWORD), ("th32ModuleID", wintypes.DWORD),
                ("th32ProcessID", wintypes.DWORD), ("GlblcntUsage", wintypes.DWORD),
                ("ProccntUsage", wintypes.DWORD), ("modBaseAddr", ctypes.POINTER(ctypes.c_byte)),
                ("modBaseSize", wintypes.DWORD), ("hModule", wintypes.HMODULE),
                ("szModule", ctypes.c_char * 256), ("szExePath", ctypes.c_char * 260)]


TH32_MODULE = 0x8 | 0x10          # TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32
INVALID_HANDLE = ctypes.c_void_p(-1).value


def module_range(pid: int, name: str = "BlackOpsColdWar.exe") -> tuple[int, int] | None:
    """(base, size) of a module in the game process, via Toolhelp - no handle to the game needed."""
    _k32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    snap = _k32.CreateToolhelp32Snapshot(TH32_MODULE, pid)
    if snap == INVALID_HANDLE or not snap:
        return None
    try:
        e = _MODENTRY()
        e.dwSize = ctypes.sizeof(_MODENTRY)
        ok = _k32.Module32First(snap, ctypes.byref(e))
        while ok:
            if e.szModule.decode(errors="ignore").lower() == name.lower():
                return ctypes.cast(e.modBaseAddr, ctypes.c_void_p).value, e.modBaseSize
            ok = _k32.Module32Next(snap, ctypes.byref(e))
    finally:
        _k32.CloseHandle(snap)
    return None


_k32.OpenProcess.restype = wintypes.HANDLE
_k32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
_k32.ReadProcessMemory.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                   ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
_k32.VirtualQueryEx.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.POINTER(_MBI), ctypes.c_size_t]
_k32.VirtualQueryEx.restype = ctypes.c_size_t


@dataclass
class Player:
    name: str
    team: str
    kind: str          # host | bot | human
    xuid: str

    def label(self) -> str:
        tag = self.kind if self.kind != "human" else ""
        return f"{self.name}  ({self.team}{', ' + tag if tag else ''})"


@dataclass
class Roster:
    tick: int
    players: list[Player] = field(default_factory=list)
    addr: int = 0
    scanned_s: float = 0.0
    full_scan: bool = False
    regions: int = 0
    bytes_read: int = 0


class RosterError(RuntimeError):
    pass


def find_game_pid() -> int:
    if gf_native is not None:
        return gf_native.find_game_pid()
    raise RosterError("gf_native not importable; pass the pid")


def parse(buf: bytes, i: int, addr: int = 0) -> Roster | None:
    """Parse one marker hit at buf[i:]; None if it is not a complete, consistent line."""
    j = buf.find(END, i, i + MAX_LEN)
    if j == -1:
        return None
    body = buf[i + len(MARK):j].decode("utf-8", "replace")
    parts = body.split("|")
    if len(parts) < 2:
        return None
    try:
        tick = int(parts[0])
        count = int(parts[1])
    except ValueError:
        return None
    players: list[Player] = []
    for p in parts[2:]:
        f = p.split(";")
        if len(f) != 4 or not f[0]:
            return None
        players.append(Player(f[0], f[1], f[2], f[3]))
    if len(players) != count:
        return None
    return Roster(tick=tick, players=players, addr=addr)


class Scanner:
    """One open handle per game process; remembers where the roster was last seen."""

    def __init__(self, pid: int):
        self.pid = pid
        self.h = _k32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
        if not self.h:
            raise RosterError(f"OpenProcess({pid}) failed, error {ctypes.get_last_error()}")
        self.last_addr: int | None = None
        self.last_tick: int = -1
        self.last_region: tuple[int, int] | None = None
        self.module: tuple[int, int] | None = None

    def close(self) -> None:
        if self.h:
            _k32.CloseHandle(self.h)
            self.h = None

    def _read(self, addr: int, size: int) -> bytes | None:
        buf = (ctypes.c_char * size)()
        got = ctypes.c_size_t(0)
        if not _k32.ReadProcessMemory(self.h, addr, buf, size, ctypes.byref(got)):
            return None
        return buf.raw[: got.value]

    # One reusable 4 MB + overlap buffer for the sweep: allocating (and zeroing) a fresh
    # ctypes buffer per chunk and copying it out cost more than the reads themselves
    # (12k regions / 11 GB measured 60 s; reused buffer + re on a memoryview ~10 s).
    _STEP = 0x400000
    _buf = None

    def _sweep_region(self, base: int, size: int, best: Roster | None) -> tuple[Roster | None, int]:
        if Scanner._buf is None:
            Scanner._buf = (ctypes.c_char * (Scanner._STEP + MAX_LEN))()
        buf = Scanner._buf
        mv = memoryview(buf)
        got = ctypes.c_size_t(0)
        nbytes = 0
        off = 0
        while off < size:
            want = min(Scanner._STEP + MAX_LEN, size - off)
            if _k32.ReadProcessMemory(self.h, base + off, buf, want, ctypes.byref(got)) and got.value:
                n = got.value
                nbytes += n
                for m in _MARK_RE.finditer(mv, 0, n):
                    i = m.start()
                    r = parse(bytes(mv[i: min(n, i + MAX_LEN)]), 0, base + off + i)
                    if r is not None and (best is None or r.tick > best.tick):
                        best = r
            off += Scanner._STEP
        return best, nbytes

    def _regions(self):
        addr = 0
        mbi = _MBI()
        while addr < 0x7FFFFFFFFFFF:
            if not _k32.VirtualQueryEx(self.h, addr, ctypes.byref(mbi), ctypes.sizeof(mbi)):
                break
            base, size = mbi.BaseAddress or 0, mbi.RegionSize
            if size == 0:
                break
            if (mbi.State == MEM_COMMIT and mbi.Type == MEM_PRIVATE
                    and (mbi.Protect & 0xFF) in _WRITABLE and not (mbi.Protect & PAGE_GUARD)):
                yield base, size
            addr = base + size

    def quick(self) -> Roster | None:
        """Re-read the last known address only (fast path for a periodic refresh)."""
        if self.last_addr is None:
            return None
        chunk = self._read(self.last_addr, MAX_LEN)
        if not chunk or not chunk.startswith(MARK):
            return None
        r = parse(chunk, 0, self.last_addr)
        if r is None or r.tick < self.last_tick:
            return None
        return r

    def full(self) -> Roster | None:
        """Sweep every private writable region; the newest complete roster wins."""
        t0 = time.perf_counter()
        best: Roster | None = None
        nreg = 0
        nbytes = 0
        # Order: the region the roster lived in last time (the pool does not move), then the
        # private RW regions INSIDE the exe image range - the script string pool is a static
        # table there (measured 2026-09-15: the menu's interned literals sit at exe+0x420000
        # in a 501 MB private RW region that is part of the image range; ~0.5 s to sweep) -
        # then everything else (11 GB, ~60 s+). Stop at the first region that yields a
        # roster: stale copies live in the same pool, so one region gives the newest tick.
        regions = list(self._regions())
        if self.module is None:
            self.module = module_range(self.pid)

        def rank(r):
            b, s = r
            if self.last_region is not None and b <= self.last_region[0] < b + s:
                return (0, -s)
            if self.module is not None and self.module[0] <= b < self.module[0] + self.module[1]:
                return (1, -s)
            return (2, b)

        regions.sort(key=rank)
        for base, size in regions:
            nreg += 1
            best, n = self._sweep_region(base, size, best)
            nbytes += n
            if best is not None:
                break
        if best is not None:
            self.last_region = next(((b, s) for b, s in regions if b <= best.addr < b + s), None)
            best.scanned_s = time.perf_counter() - t0
            best.full_scan = True
            best.regions = nreg
            best.bytes_read = nbytes
            self.last_addr = best.addr
            self.last_tick = best.tick
        return best

    def read(self, force_full: bool = False) -> Roster | None:
        if not force_full:
            r = self.quick()
            if r is not None:
                return r
        return self.full()


def read_roster(pid: int | None = None, scanner: Scanner | None = None, force_full: bool = False) -> Roster | None:
    """One-shot helper: returns the roster or None (game not up / menu not injected / not found)."""
    own = scanner is None
    if scanner is None:
        pid = pid or find_game_pid()
        if not pid:
            return None
        scanner = Scanner(pid)
    try:
        return scanner.read(force_full)
    finally:
        if own:
            scanner.close()


def _main(argv: list[str]) -> int:
    pid = find_game_pid()
    if not pid:
        print("game not running")
        return 1
    sc = Scanner(pid)
    try:
        while True:
            r = sc.read(force_full="--full" in argv)
            if r is None:
                print("no roster in memory (menu not injected / match not started?)")
            else:
                how = f"full sweep {r.scanned_s:.1f}s, {r.regions} regions, {r.bytes_read / 2**20:.0f} MB" if r.full_scan else "cached address"
                print(f"tick {r.tick}  @0x{r.addr:x}  ({how})")
                for p in r.players:
                    print(f"  {p.label():40s} xuid={p.xuid}")
            if "--loop" not in argv:
                break
            time.sleep(5)
    finally:
        sc.close()
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
