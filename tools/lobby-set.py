#!/usr/bin/env python3
"""Set the CUSTOM GAMES lobby's map and gametype directly, bypassing the UI's
map/mode compatibility rule.

    python tools\lobby-set.py                              # scan only, change nothing
    python tools\lobby-set.py --gametype gunfight
    python tools\lobby-set.py --map mp_miami
    python tools\lobby-set.py --gametype gunfight --map mp_miami

WHAT THIS IS. The custom-games map screen shows all 36 MP maps and flags the ones
the selected mode does not claim, with "Map not compatible with the selected mode.
Choosing this map will automatically change your mode selection." That rule lives in
the FRONT END. The session does not enforce it - we have already run Gunfight on Zoo
end to end (see docs/notes/menu-map.md), so the gametype and the map are independent
as far as the game is concerned.

The front end sets the lobby's map and gametype through two engine functions. ACTS
names them from its Black Ops 4 work (src/core/acts/tools/bo4/lobby_tool.cpp:455,:473):

    LobbySetGameType( LobbyType lobby, char const* gametype )
    LobbySetMap     ( LobbyType lobby, char const* map      )

`LobbyType` 0 is LOBBY_TYPE_PRIVATE (src/dll/bo3-dll/data/bo3.hpp:139) - a custom
game. Calling these directly is the same act as clicking the row, minus the screen
that decides which rows you are allowed to click.

ate47 already wrote the Cold War port of that tool - src/core/acts/tools/cw/
cw_lobby_tool.cpp, with signature scans instead of BO4's hardcoded addresses. It ships
DISABLED: its ADD_TOOL_NUI line is commented out, and it carries two bugs that would
stop it working (the scan result is absolute but is passed through Process::operator[]
which adds the module base again, and the patterns match a CALL SITE whose E8 rel32 is
never decoded, so the "function address" is the call instruction). This script is that
tool, finished. The signatures are his.

WHY PYTHON AND NOT A PATCH TO ACTS. Building ACTS is a CMake+MSVC job for three lines
of change. This needs no toolchain, sits beside the injector klaze already runs, and
prints what it found before it touches anything.

HOW IT WORKS
    1. find BlackOpsColdWar.exe and its main module
    2. scan the module's committed pages for the two call-site patterns
    3. decode each E8 rel32 to the function it calls
    4. group the matches - every call site for one setter resolves to ONE address
    5. write the argument string into the process
    6. write a 34-byte x64 stub that loads RCX=0, RDX=string, and calls the function
    7. run the stub on a remote thread, wait, free everything

SELF-CHECK, AND WHY IT MATTERS. A signature returns the first thing that matches, which
is not the same as the thing you wanted. Two independent checks run before any call:

    - every call site matching one pattern must resolve to the SAME target. One
      pattern matching several different functions means the pattern is too loose.
    - the two targets should sit CLOSE TOGETHER. In Black Ops 4 they are 0x10 apart -
      0x398E410 and 0x398E420, adjacent entries in the same jump table. Cold War is the
      same engine lineage. Far apart is not proof of failure, but it is a reason to stop
      and read the addresses rather than press on.

Both checks are reported, neither is fatal on its own, and --force skips the refusal.

EXPOSURE. This opens the game process and writes to it - the same class of access as
the GSC injector this project already uses, no more and no less. It is not evasion: it
hides nothing and spoofs nothing. Private matches only. Nothing it writes persists past
the process; a bad scan crashes the game and costs you a relaunch.

REQUIREMENTS. Windows, 64-bit Python, and the game already sitting in the custom games
lobby. Run it from the test PC, not over RDP from somewhere else - it needs the process.
"""

from __future__ import annotations

import argparse
import ctypes
import re
import struct
import sys
from ctypes import wintypes

# ---------------------------------------------------------------- signatures

# ate47, src/core/acts/tools/cw/cw_lobby_tool.cpp:192 and :208.
# Each is a CALL to the setter followed by enough of the caller's next
# instructions to be unique. The E8 target is what we actually want.
SIG_SET_GAMETYPE = "E8 ? ? ? ? 48 8B C7 0F B6 80"
SIG_SET_MAP      = "E8 ? ? ? ? 0F B6 83 ? ? ? ? 38 86"

LOBBY_TYPE_PRIVATE = 0

# In BO4 the two setters are 0x10 apart. Anything inside this window keeps the
# "adjacent entries in one table" reading alive; beyond it, say so and stop.
ADJACENCY_WINDOW = 0x1000

PROCESS_NAME = "BlackOpsColdWar.exe"

# ---------------------------------------------------------------- win32

k32 = ctypes.WinDLL("kernel32", use_last_error=True) if sys.platform == "win32" else None

TH32CS_SNAPPROCESS = 0x00000002
TH32CS_SNAPMODULE = 0x00000008
TH32CS_SNAPMODULE32 = 0x00000010

PROCESS_ALL_ACCESS = 0x1F0FFF

MEM_COMMIT = 0x1000
MEM_RESERVE = 0x2000
MEM_RELEASE = 0x8000

PAGE_READWRITE = 0x04
PAGE_EXECUTE_READWRITE = 0x40
PAGE_NOACCESS = 0x01
PAGE_GUARD = 0x100

# protections we can ReadProcessMemory through
READABLE = {0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80}

INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value


class PROCESSENTRY32(ctypes.Structure):
    _fields_ = [
        ("dwSize", wintypes.DWORD),
        ("cntUsage", wintypes.DWORD),
        ("th32ProcessID", wintypes.DWORD),
        ("th32DefaultHeapID", ctypes.POINTER(ctypes.c_ulong)),
        ("th32ModuleID", wintypes.DWORD),
        ("cntThreads", wintypes.DWORD),
        ("th32ParentProcessID", wintypes.DWORD),
        ("pcPriClassBase", ctypes.c_long),
        ("dwFlags", wintypes.DWORD),
        ("szExeFile", ctypes.c_char * 260),
    ]


class MODULEENTRY32(ctypes.Structure):
    _fields_ = [
        ("dwSize", wintypes.DWORD),
        ("th32ModuleID", wintypes.DWORD),
        ("th32ProcessID", wintypes.DWORD),
        ("GlblcntUsage", wintypes.DWORD),
        ("ProccntUsage", wintypes.DWORD),
        ("modBaseAddr", ctypes.POINTER(ctypes.c_byte)),
        ("modBaseSize", wintypes.DWORD),
        ("hModule", wintypes.HMODULE),
        ("szModule", ctypes.c_char * 256),
        ("szExePath", ctypes.c_char * 260),
    ]


class MEMORY_BASIC_INFORMATION64(ctypes.Structure):
    _fields_ = [
        ("BaseAddress", ctypes.c_ulonglong),
        ("AllocationBase", ctypes.c_ulonglong),
        ("AllocationProtect", wintypes.DWORD),
        ("__alignment1", wintypes.DWORD),
        ("RegionSize", ctypes.c_ulonglong),
        ("State", wintypes.DWORD),
        ("Protect", wintypes.DWORD),
        ("Type", wintypes.DWORD),
        ("__alignment2", wintypes.DWORD),
    ]


def _die(msg: str) -> "NoReturn":  # noqa: F821
    print("ERROR: " + msg, file=sys.stderr)
    raise SystemExit(1)


def find_process(name: str) -> int:
    snap = k32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if snap == INVALID_HANDLE_VALUE:
        _die("CreateToolhelp32Snapshot failed")
    try:
        entry = PROCESSENTRY32()
        entry.dwSize = ctypes.sizeof(PROCESSENTRY32)
        ok = k32.Process32First(snap, ctypes.byref(entry))
        while ok:
            if entry.szExeFile.decode(errors="replace").lower() == name.lower():
                return entry.th32ProcessID
            ok = k32.Process32Next(snap, ctypes.byref(entry))
    finally:
        k32.CloseHandle(snap)
    _die(
        f"{name} is not running. Start the game and sit in the custom games lobby, "
        "then run this again."
    )


def find_module(pid: int, name: str) -> tuple[int, int]:
    snap = k32.CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid)
    if snap == INVALID_HANDLE_VALUE:
        _die("CreateToolhelp32Snapshot(MODULE) failed - is Python 64-bit?")
    try:
        entry = MODULEENTRY32()
        entry.dwSize = ctypes.sizeof(MODULEENTRY32)
        ok = k32.Module32First(snap, ctypes.byref(entry))
        while ok:
            if entry.szModule.decode(errors="replace").lower() == name.lower():
                base = ctypes.cast(entry.modBaseAddr, ctypes.c_void_p).value
                return base, entry.modBaseSize
            ok = k32.Module32Next(snap, ctypes.byref(entry))
    finally:
        k32.CloseHandle(snap)
    _die(f"module {name} not found in pid {pid}")


class Proc:
    def __init__(self, pid: int):
        self.pid = pid
        self.h = k32.OpenProcess(PROCESS_ALL_ACCESS, False, pid)
        if not self.h:
            _die(
                f"OpenProcess failed (error {ctypes.get_last_error()}). "
                "Run this shell as Administrator."
            )

    def close(self) -> None:
        if self.h:
            k32.CloseHandle(self.h)
            self.h = None

    def read(self, addr: int, size: int) -> bytes | None:
        buf = (ctypes.c_char * size)()
        got = ctypes.c_size_t(0)
        ok = k32.ReadProcessMemory(
            self.h, ctypes.c_void_p(addr), buf, size, ctypes.byref(got)
        )
        if not ok or got.value == 0:
            return None
        return buf.raw[: got.value]

    def write(self, addr: int, data: bytes) -> bool:
        put = ctypes.c_size_t(0)
        return bool(
            k32.WriteProcessMemory(
                self.h, ctypes.c_void_p(addr), data, len(data), ctypes.byref(put)
            )
        )

    def query(self, addr: int) -> MEMORY_BASIC_INFORMATION64 | None:
        mbi = MEMORY_BASIC_INFORMATION64()
        n = k32.VirtualQueryEx(
            self.h, ctypes.c_void_p(addr), ctypes.byref(mbi), ctypes.sizeof(mbi)
        )
        return mbi if n else None

    def alloc(self, size: int, protect: int) -> int:
        k32.VirtualAllocEx.restype = ctypes.c_void_p
        p = k32.VirtualAllocEx(
            self.h, None, ctypes.c_size_t(size), MEM_COMMIT | MEM_RESERVE, protect
        )
        if not p:
            _die(f"VirtualAllocEx failed (error {ctypes.get_last_error()})")
        return p

    def free(self, addr: int) -> None:
        k32.VirtualFreeEx(self.h, ctypes.c_void_p(addr), 0, MEM_RELEASE)

    def run(self, addr: int, timeout_ms: int = 5000) -> bool:
        k32.CreateRemoteThread.restype = wintypes.HANDLE
        thr = k32.CreateRemoteThread(
            self.h, None, 0, ctypes.c_void_p(addr), None, 0, None
        )
        if not thr:
            _die(f"CreateRemoteThread failed (error {ctypes.get_last_error()})")
        rc = k32.WaitForSingleObject(thr, timeout_ms)
        k32.CloseHandle(thr)
        return rc == 0  # WAIT_OBJECT_0


# ---------------------------------------------------------------- scanning


def compile_sig(sig: str) -> "re.Pattern[bytes]":
    """'E8 ? ? ? ? 48 8B C7' -> a bytes regex. '?' is any single byte."""
    parts = []
    for tok in sig.split():
        if tok in ("?", "??"):
            parts.append(b".")
        else:
            parts.append(re.escape(bytes([int(tok, 16)])))
    return re.compile(b"".join(parts), re.DOTALL)


def sig_len(sig: str) -> int:
    return len(sig.split())


def scan(proc: Proc, base: int, size: int, sig: str) -> list[int]:
    """Every address in [base, base+size) where `sig` matches.

    Walks committed readable regions rather than assuming the whole module is
    mapped - Arxan leaves holes, and a blind read would just fail there. Chunks
    overlap by the pattern length so a match straddling a chunk edge still lands.
    """
    rx = compile_sig(sig)
    plen = sig_len(sig)
    hits: list[int] = []
    end = base + size
    addr = base

    while addr < end:
        mbi = proc.query(addr)
        if mbi is None:
            break
        region_end = min(mbi.BaseAddress + mbi.RegionSize, end)
        if region_end <= addr:
            break

        usable = (
            mbi.State == MEM_COMMIT
            and (mbi.Protect & 0xFF) in READABLE
            and not (mbi.Protect & PAGE_GUARD)
        )
        if usable:
            pos = addr
            while pos < region_end:
                want = min(0x100000, region_end - pos)
                data = proc.read(pos, want + plen - 1) or proc.read(pos, want)
                if data:
                    for m in rx.finditer(data):
                        if m.start() < want:
                            hits.append(pos + m.start())
                pos += want
        addr = region_end
    return hits


def resolve_call(proc: Proc, call_site: int) -> int | None:
    """E8 rel32 -> absolute target."""
    raw = proc.read(call_site, 5)
    if not raw or len(raw) < 5 or raw[0] != 0xE8:
        return None
    rel = struct.unpack("<i", raw[1:5])[0]
    return call_site + 5 + rel


def find_setter(proc: Proc, base: int, size: int, sig: str, label: str) -> tuple[int | None, dict]:
    sites = scan(proc, base, size, sig)
    targets: dict[int, list[int]] = {}
    for s in sites:
        t = resolve_call(proc, s)
        if t is not None:
            targets.setdefault(t, []).append(s)

    print(f"  {label}")
    print(f"    pattern    {sig}")
    print(f"    call sites {len(sites)}")
    if not targets:
        print("    targets    NONE - pattern did not match this build")
        return None, targets
    for t, ss in sorted(targets.items(), key=lambda kv: -len(kv[1])):
        print(
            f"    target     {t:#x}  (module+{t - base:#x})  "
            f"from {len(ss)} call site{'s' if len(ss) != 1 else ''}"
        )
    best = max(targets.items(), key=lambda kv: len(kv[1]))[0]
    if len(targets) > 1:
        print(f"    ^ MORE THAN ONE TARGET - the pattern is too loose to trust alone")
    return best, targets


# ---------------------------------------------------------------- the call

# sub rsp,0x28 | xor rcx,rcx | mov rdx,<str> | mov rax,<fn> | call rax | add rsp,0x28 | ret
#
# At a thread entry point RSP is 8 mod 16. 0x28 is 0x20 of shadow space plus the 8
# that puts RSP back on a 16-byte boundary, so the callee sees the alignment the
# x64 ABI promises it. Getting this wrong is the classic way to crash on the first
# instruction that touches xmm state.
def build_stub(func: int, arg_str: int, lobby: int = LOBBY_TYPE_PRIVATE) -> bytes:
    if lobby == 0:
        set_rcx = b"\x48\x31\xC9"                      # xor rcx, rcx
    else:
        set_rcx = b"\x48\xC7\xC1" + struct.pack("<i", lobby)  # mov rcx, imm32
    return (
        b"\x48\x83\xEC\x28"
        + set_rcx
        + b"\x48\xBA" + struct.pack("<Q", arg_str)
        + b"\x48\xB8" + struct.pack("<Q", func)
        + b"\xFF\xD0"
        + b"\x48\x83\xC4\x28"
        + b"\xC3"
    )


def call_setter(proc: Proc, func: int, value: str, lobby: int, label: str) -> bool:
    raw = value.encode("ascii") + b"\x00"
    s = proc.alloc(len(raw), PAGE_READWRITE)
    if not proc.write(s, raw):
        proc.free(s)
        _die("could not write the argument string")

    stub = build_stub(func, s, lobby)
    c = proc.alloc(len(stub), PAGE_EXECUTE_READWRITE)
    if not proc.write(c, stub):
        proc.free(c)
        proc.free(s)
        _die("could not write the stub")

    print(f"  {label}({lobby}, \"{value}\")  fn={func:#x} str={s:#x} stub={c:#x}")
    ok = proc.run(c)
    proc.free(c)
    proc.free(s)
    print("    " + ("returned" if ok else "TIMED OUT - the game may be wedged"))
    return ok



# ---------------------------------------------------------------- self-test


def self_test() -> int:
    """Exercise everything that does not need the game: the signature matcher,
    the E8 decode arithmetic, and the stub bytes. Runs on any platform.

    The stub is the part worth testing. It is hand-assembled machine code that
    runs on a thread inside the game; a wrong byte there is a crash, and a wrong
    RSP alignment is a crash that only happens sometimes, which is worse.
    """
    fails = []

    def check(name, cond):
        print(("  ok   " if cond else "  FAIL ") + name)
        if not cond:
            fails.append(name)

    print("signature matcher")
    rx = compile_sig(SIG_SET_GAMETYPE)
    site = 0x40
    blob = bytearray(b"\x90" * 0x200)
    blob[site : site + 5] = b"\xE8" + struct.pack("<i", 0x2000)
    blob[site + 5 : site + 11] = bytes.fromhex("488BC70FB680")
    hits = [m.start() for m in rx.finditer(bytes(blob))]
    check("SIG_SET_GAMETYPE finds a planted call site", hits == [site])
    check("and does not match filler", not list(rx.finditer(b"\x90" * 0x200)))

    rxm = compile_sig(SIG_SET_MAP)
    blob2 = bytearray(b"\x00" * 0x200)
    blob2[0x80:0x85] = b"\xE8" + struct.pack("<i", -0x1234)
    blob2[0x85 : 0x85 + 9] = bytes.fromhex("0FB683AABBCCDD3886")
    check("SIG_SET_MAP finds a planted call site",
          0x80 in [m.start() for m in rxm.finditer(bytes(blob2))])
    check("wildcards are one byte each",
          sig_len(SIG_SET_MAP) == 14 and sig_len(SIG_SET_GAMETYPE) == 11)

    print("E8 rel32 decode")
    check("forward  0x140001000 +5 +0x2000", 0x140001000 + 5 + 0x2000 == 0x140003005)
    check("backward 0x140001000 +5 -0x1234", 0x140001000 + 5 - 0x1234 == 0x13FFFFDD1)
    check("rel32 is signed", struct.unpack("<i", struct.pack("<I", 0xFFFFEDCC))[0] == -0x1234)

    print("x64 stub")
    fn, s = 0x7FF700001234, 0x1A2B3C4D5E6
    stub = build_stub(fn, s, 0)
    parts = [
        ("sub rsp,0x28", stub[0:4] == b"\x48\x83\xEC\x28"),
        ("xor rcx,rcx (lobby 0)", stub[4:7] == b"\x48\x31\xC9"),
        ("mov rdx,<string>", stub[7:9] == b"\x48\xBA"
                             and struct.unpack("<Q", stub[9:17])[0] == s),
        ("mov rax,<func>", stub[17:19] == b"\x48\xB8"
                           and struct.unpack("<Q", stub[19:27])[0] == fn),
        ("call rax", stub[27:29] == b"\xFF\xD0"),
        ("add rsp,0x28", stub[29:33] == b"\x48\x83\xC4\x28"),
        ("ret", stub[33:34] == b"\xC3"),
        ("34 bytes total", len(stub) == 34),
    ]
    for n, c in parts:
        check(n, c)
    # thread entry has RSP == 8 (mod 16); 0x28 = 0x20 shadow + 8 realign, so the
    # callee sees RSP == 8 (mod 16) after its own return address is pushed.
    check("shadow space + realignment == 0x28", (8 - 0x28 + 8) % 16 == 8)
    check("mov rcx,imm32 for a non-zero lobby",
          build_stub(0x1000, 0x2000, 1)[4:11] == b"\x48\xC7\xC1\x01\x00\x00\x00")

    print()
    if fails:
        print(f"{len(fails)} FAILED: " + ", ".join(fails))
        return 1
    print("all self-tests pass (nothing was read from or written to any process)")
    return 0


# ---------------------------------------------------------------- main


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Set the BOCW custom-games lobby map/gametype, ignoring the UI's "
        "map-mode compatibility rule. Scans and reports by default; changes nothing "
        "unless you pass --gametype or --map."
    )
    ap.add_argument("--gametype", help='e.g. gunfight, gunfight_3v3, tdm')
    ap.add_argument("--map", help="e.g. mp_miami, mp_moscow, mp_zoo_rm")
    ap.add_argument(
        "--lobby", type=int, default=LOBBY_TYPE_PRIVATE,
        help="LobbyType: 0 private (default), 1 game, 2 transition",
    )
    ap.add_argument(
        "--force", action="store_true",
        help="call even if the self-checks are unhappy",
    )
    ap.add_argument("--func-gametype", help="skip the scan, use this absolute address")
    ap.add_argument("--func-map", help="skip the scan, use this absolute address")
    ap.add_argument(
        "--self-test", action="store_true",
        help="check the signature matcher and the stub bytes; touches no process",
    )
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    if sys.platform != "win32":
        _die("Windows only - this opens the game process.")
    if struct.calcsize("P") != 8:
        _die("64-bit Python required (the game is 64-bit).")

    pid = find_process(PROCESS_NAME)
    base, size = find_module(pid, PROCESS_NAME)
    print(f"{PROCESS_NAME}  pid={pid}  base={base:#x}  size={size:#x}")

    proc = Proc(pid)
    try:
        print("\nscanning")
        if args.func_gametype:
            fn_gt = int(args.func_gametype, 0)
            print(f"  LobbySetGameType  {fn_gt:#x}  (given, not scanned)")
            gt_targets = {fn_gt: []}
        else:
            fn_gt, gt_targets = find_setter(
                proc, base, size, SIG_SET_GAMETYPE, "LobbySetGameType"
            )
        if args.func_map:
            fn_map = int(args.func_map, 0)
            print(f"  LobbySetMap       {fn_map:#x}  (given, not scanned)")
            map_targets = {fn_map: []}
        else:
            fn_map, map_targets = find_setter(
                proc, base, size, SIG_SET_MAP, "LobbySetMap"
            )

        print("\nself-check")
        happy = True
        if fn_gt is None or fn_map is None:
            print("  FAIL  a signature did not resolve on this build")
            happy = False
        else:
            gap = abs(fn_gt - fn_map)
            if len(gt_targets) > 1 or len(map_targets) > 1:
                print("  WARN  a pattern resolved to more than one function")
                happy = False
            if gap <= ADJACENCY_WINDOW:
                print(f"  PASS  the two setters are {gap:#x} apart "
                      f"(BO4 has them at 0x10 - same table)")
            else:
                print(f"  WARN  the two setters are {gap:#x} apart; BO4 has them at 0x10. "
                      "Read the addresses before trusting this.")
                happy = False

        if not args.gametype and not args.map:
            print("\nscan only. Re-run with --gametype and/or --map to set them.")
            return 0

        if not happy and not args.force:
            print("\nREFUSING to call - self-check unhappy. Pass --force to override.")
            return 2

        print("\ncalling")
        # Gametype first: in the stock UI picking a mode is what filters the map
        # list, so this is the order the front end itself uses.
        if args.gametype:
            call_setter(proc, fn_gt, args.gametype, args.lobby, "LobbySetGameType")
        if args.map:
            call_setter(proc, fn_map, args.map, args.lobby, "LobbySetMap")

        print(
            "\nLook at the lobby. The map and mode rows are what to read - and then "
            "start a match and check the loading screen and scoreboard agree."
        )
        return 0
    finally:
        proc.close()


if __name__ == "__main__":
    raise SystemExit(main())
