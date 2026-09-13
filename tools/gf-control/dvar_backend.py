"""Read/write BOCW dvars from an external process, for the Gunfight host control app.

This is the memory layer under gf_control.py. It mirrors tools/lobby-set.py's proven
primitives (OpenProcess + ReadProcessMemory/WriteProcessMemory + VirtualAllocEx +
CreateRemoteThread - the access class TAC has tolerated all session on the test box).

HOW A DVAR GETS WRITTEN - anchored on cwpatch, not on a guessed signature.

  cwpatch (the 13,824-byte discord_game_sdk.dll in the game folder, docs/notes/
  unlock-dlls.md) is loaded INSIDE the game. At DiscordCreate it signature-scans the
  decrypted exe and stores the RESOLVED game pointers in its own .data section. Those
  are readable with a plain ReadProcessMemory - no code has to run, and the exe's
  at-rest encryption is irrelevant because cwpatch already did the scan in-process:

      discord_game_sdk.dll + 0x5658   Dvar_FindVar(u64 hash) -> dvar_t*
                           + 0x5660   Dvar_RegisterBool(hash, 0, 1, 1, 1, 0)
                           + 0x5668   Dvar_SetBool(dvar_t*, 1, 0)
                           + 0x5638   the command executor behind F4/F6/F7
                           + 0x5640/48/50  the "hostmigration_start\\n" /
                                      "checkpoint_restart\\n" / "mission_restart\\n"
                                      string literals it overwrites to run a command

  (Slot RVAs and the seven signatures below were read out of the DLL statically on
  2026-09-12; they are validated on this build by F7/F4 working. The same signatures
  are carried here as a fallback for when Battle.net has put the stock SDK back.)

  Two write routes, both anchored there:

  DIRECT (ints): Dvar_FindVar(hash) on a remote thread - a pure lookup that returns
     NULL on a miss (cwpatch itself calls it from a foreign thread), so no wedge risk -
     gives the real dvar_t*. The value's offset inside it is pinned ONCE by --diff
     (change the dvar in the in-game menu, see which cell moved) and recorded in
     DVAR_INT_PATH. After that a write is one WriteProcessMemory of an int32.
     Strings (gf_cmd_map / gf_cmd_gametype) are refused on this route: a string dvar's
     value is engine-owned storage and must not be poked from outside.

  EXEC (everything): cwpatch's own trick - overwrite one of the string literals with
     "set <dvar> <value>\\n", CreateRemoteThread on the executor, restore the 48 bytes.
     🪦 MEASURED 2026-09-12 AND RULED OUT. The mechanism is right (disassembly confirms
     the executor at +0x5638 reads the command blob and takes no args) and `set` DID
     begin executing - but called via CreateRemoteThread the executor NEVER RETURNS: it
     took the dvar-system lock to create the dvar and then blocked, leaving the lock
     held. Every later dvar call (FindVar included) then hangs until the game is
     relaunched. The game keeps rendering; only the dvar subsystem is wedged. cwpatch
     gets away with this same executor because its commands (fast_restart / full_restart
     / lobbylaunchgame) tear the match down, so "does not return cleanly" never matters;
     `set` is the first caller that needed a clean return and exposed it. So EXEC is a
     relaunch-costing dead end via a remote thread - EXEC_ROUTE_WEDGES below, cmd_exec
     refuses without --force, and the live path is route A only.

  The retired route: calling the GSC `setdvar` builtin (funcs_cw.csv +0x3CD62A0) on a
  remote thread. Measured 2026-09-12: it does its work inline inside the script VM,
  its only calls are error helpers, and a wrong call WEDGES the game (a stuck remote
  thread blocks every later CreateRemoteThread until relaunch). Do not bring it back.

SCOPE / GUARD. Per the project guard, the AGENT writes this tool; KLAZE runs anything
that touches game memory. Dry-run is the default and touches nothing. Live mode needs
--live AND a confirmed route (DVAR_INT_PATH pinned, or EXEC_ROUTE_CONFIRMED) and
refuses otherwise - firing at the wrong place is worse than refusing.

⚠ The in-game side only READS the gf_* dvars (getdvarint with a default), so a dvar
does not exist in the registry until something setdvar()s it - the menu touching it,
or an init-time pre-register in gunfight_menu.gsc. On the DIRECT route Dvar_FindVar
returns NULL for those and the write is refused with a clear log line. The EXEC route
creates them.

CREDIT: Proc/find_process/find_module/scan are lobby-set.py's, trimmed to what the
control app needs. Keep the two in sync if the memory layer changes.
"""

from __future__ import annotations

import ctypes
import re
import struct
import sys
from ctypes import wintypes

PROC_NAME = "BlackOpsColdWar.exe"

# ---- the anchor: cwpatch ----------------------------------------------------
CWPATCH_MODULE = "discord_game_sdk.dll"
CWPATCH_IMAGE_SIZE = 0x9000          # cwpatch's SizeOfImage; the stock Discord SDK is 0x3b8000

# RVAs (from the DLL base) of the qwords cwpatch fills with its scan results.
CWPATCH_SLOTS = {
    "executor":           0x5638,
    "slot_hostmigration": 0x5640,
    "slot_checkpoint":    0x5648,
    "slot_mission":       0x5650,
    "Dvar_FindVar":       0x5658,
    "Dvar_RegisterBool":  0x5660,
    "Dvar_SetBool":       0x5668,
}

# The seven patterns cwpatch scans the main module for (verbatim from its .rdata).
# kind: "callsite" = matches an E8 call, decode rel32 to the callee (cwpatch does the
# same); "prologue" = the match IS the function; "literal" = the string bytes.
CWPATCH_SIGS = {
    "executor": ("48 89 5C 24 08 55 56 57 41 54 41 55 41 56 41 57 48 8B EC 48 81 EC "
                 "?? ?? ?? ?? 48 8D 05 ?? ?? ?? ?? 48 89 45 ??", "prologue"),
    "slot_hostmigration": ("68 6F 73 74 6D 69 67 72 61 74 69 6F 6E 5F 73 74 61 72 74 0A", "literal"),
    "slot_checkpoint":    ("63 68 65 63 6B 70 6F 69 6E 74 5F 72 65 73 74 61 72 74 0A", "literal"),
    "slot_mission":       ("6D 69 73 73 69 6F 6E 5F 72 65 73 74 61 72 74 0A", "literal"),
    "Dvar_FindVar":       ("E8 ?? ?? ?? ?? 48 8B F8 48 85 C0 74 38 F7 40 ?? ?? ?? ?? ??", "callsite"),
    "Dvar_RegisterBool":  ("E8 ?? ?? ?? ?? 0F 28 7C 24 ?? 48 89 05 ?? ?? ?? ?? 48 83 C4 50 5F", "callsite"),
    "Dvar_SetBool":       ("E8 ?? ?? ?? ?? 48 8B 0D ?? ?? ?? ?? 45 33 C0 49 8B D7 E8 ?? ?? ?? ??", "callsite"),
}

SLOT_LITERALS = {
    "slot_hostmigration": b"hostmigration_start\n",
    "slot_checkpoint":    b"checkpoint_restart\n",
    "slot_mission":       b"mission_restart\n",
}

# What --cwpatch resolved on the live game on 2026-09-12 (exe dated 2026-06-12), with
# cwpatch's slots and our scan of the same signatures AGREEING on every entry. Reference
# only - nothing reads this; --cwpatch re-derives it per launch. If a game update moves
# these, both columns move together and --cwpatch says whether they still agree.
REFERENCE_RVAS_2026_09_12 = {
    "executor":           0x3ace080,    # prologue sig: 3 hits, first one (cwpatch takes the first too)
    "slot_hostmigration": 0xd6a5cb0,    # the three literals sit 0x18 / 0xd8 apart
    "slot_checkpoint":    0xd6a5cc8,
    "slot_mission":       0xd6a5d88,
    "Dvar_FindVar":       0xbf88690,
    "Dvar_RegisterBool":  0xbf9d6c0,
    "Dvar_SetBool":       0xbf8dfe0,
}

# ---- what klaze pins after the in-game steps (README, "the write primitive") -----
#
# DIRECT route: where an int dvar's value sits relative to the dvar_t* Dvar_FindVar
# returns. A path is a chain of offsets: every offset but the last is dereferenced as
# a qword pointer, the last is where the int32 lives.
#   (0x18,)       ->  *(int32*)(dvar + 0x18)
#   (0x28, 0x0)   ->  p = *(u64*)(dvar + 0x28);  *(int32*)(p + 0x0)
# () = not pinned yet -> live int writes refuse. --diff prints the path to paste here.
DVAR_INT_PATH: tuple[int, ...] = ()
#
# EXEC route: 🪦 ruled out 2026-09-12 - the executor does not return when called from a
# remote thread and wedges the dvar lock (module docstring). Left False permanently;
# do not flip it. EXEC_ROUTE_WEDGES keeps the measurement next to the switch so nobody
# re-tries it expecting it to work. --exec still exists but refuses without --force.
EXEC_ROUTE_CONFIRMED = False
EXEC_ROUTE_WEDGES = True
EXEC_SLOT = "slot_hostmigration"     # the literal --exec overwrites (cwpatch's first choice)
EXEC_RESTORE_LEN = 48                # cwpatch saves/restores this many bytes around it

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

    def read_u64(self, addr: int) -> int | None:
        b = self.read(addr, 8)
        return int.from_bytes(b, "little") if b and len(b) == 8 else None

    def read_i32(self, addr: int) -> int | None:
        b = self.read(addr, 4)
        return int.from_bytes(b, "little", signed=True) if b and len(b) == 4 else None

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
        """CreateRemoteThread(addr, NULL) and wait. False = it did not return in time
        (the thread is left alone; a stuck one blocks later calls until relaunch)."""
        _k32.CreateRemoteThread.restype = wintypes.HANDLE
        thr = _k32.CreateRemoteThread(self.h, None, 0, ctypes.c_void_p(addr), None, 0, None)
        if not thr:
            raise BackendError(f"CreateRemoteThread failed (error {ctypes.get_last_error()})")
        rc = _k32.WaitForSingleObject(thr, timeout_ms)
        _k32.CloseHandle(thr)
        return rc == 0

    def call(self, func: int, args: tuple[int, ...] = (), timeout_ms: int = 5000) -> int | None:
        """Call func(args...) on a remote thread and return its full 64-bit rax
        (GetExitCodeThread only carries 32 bits, so the stub parks rax in a cell).
        None = the call did not return in time."""
        cell = self.alloc(8, PAGE_READWRITE)
        self.write(cell, b"\x00" * 8)
        stub = _call_stub(func, args, cell)
        pc = self.alloc(len(stub), PAGE_EXECUTE_READWRITE)
        self.write(pc, stub)
        ok = False
        try:
            ok = self.run(pc, timeout_ms)
            return self.read_u64(cell) if ok else None
        finally:
            if ok:                       # a still-running thread must keep its code/cell
                self.free(pc)
                self.free(cell)


# rcx, rdx, r8, r9 <- imm64
_ARG_MOV = (b"\x48\xB9", b"\x48\xBA", b"\x49\xB8", b"\x49\xB9")


def _call_stub(func: int, args: tuple[int, ...], cell: int) -> bytes:
    """sub rsp,28 ; mov <argreg>,imm64 ... ; mov rax,func ; call rax ;
    mov rcx,cell ; mov [rcx],rax ; add rsp,28 ; ret"""
    if len(args) > 4:
        raise BackendError("stub supports at most 4 register args")
    code = b"\x48\x83\xEC\x28"
    for op, a in zip(_ARG_MOV, args):
        code += op + struct.pack("<Q", a & 0xFFFFFFFFFFFFFFFF)
    code += b"\x48\xB8" + struct.pack("<Q", func) + b"\xFF\xD0"
    code += b"\x48\xB9" + struct.pack("<Q", cell) + b"\x48\x89\x01"
    code += b"\x48\x83\xC4\x28" + b"\xC3"
    return code


def dvar_hash(name: str) -> int:
    """FNV1a-63: the hash GSC compiles #\"name\" to (tools/crack-hash.py) and the form
    cwpatch passes to Dvar_FindVar (loot_fakeall -> 0x60cdc482a7d159f8, top bit clear)."""
    h = 0xCBF29CE484222325
    for c in name.lower():
        h = ((h ^ ord(c)) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h & 0x7FFFFFFFFFFFFFFF


def compile_sig(sig: str) -> "re.Pattern[bytes]":
    pat = b"".join(
        (b"." if tok in ("??", "?") else re.escape(bytes([int(tok, 16)])))
        for tok in sig.split()
    )
    return re.compile(pat, re.DOTALL)


class DvarBackend:
    """Config surface for the GUI. In dry-run it records intended writes; in live
    mode it writes through whichever route is confirmed (module docstring)."""

    def __init__(self, dry_run: bool = True):
        self.dry_run = dry_run
        self.proc: Proc | None = None
        self.pid = 0
        self.base = 0
        self.size = 0
        self.cw: dict[str, int] = {}          # cwpatch's resolved pointers, if loaded
        self.cw_base = 0
        self.findvar = 0                      # Dvar_FindVar, absolute
        self.executor = 0                     # cwpatch's command executor, absolute
        self.exec_slot = 0                    # the literal --exec overwrites, absolute
        self.route = "none"                   # "direct" | "exec" | "none"
        self._ptrs: dict[str, int] = {}       # name -> dvar_t* (per launch)
        self.log: list[str] = []

    # -- lifecycle -------------------------------------------------------------
    def attach(self) -> None:
        """Open the game and read cwpatch's pointer slots. No code runs."""
        self.pid = find_process(PROC_NAME)
        self.proc = Proc(self.pid)
        self.base, self.size = find_module(self.pid, PROC_NAME)
        self._log(f"attached pid={self.pid} base={self.base:#x} size={self.size:#x}")
        self.cw = self.read_cwpatch_slots()
        if self.cw:
            self._log(f"cwpatch present @ {self.cw_base:#x}, slots read")
        else:
            self._log("cwpatch NOT loaded (stock Discord SDK in the slot?) - sig fallback only")

    def connect(self) -> None:
        if self.dry_run:
            self._log("dry-run: not attaching to the game")
            return
        self.attach()
        if EXEC_ROUTE_CONFIRMED:
            self.executor = self.resolve("executor")
            self.exec_slot = self.resolve(EXEC_SLOT)
            if not (self.executor and self.exec_slot):
                raise BackendError("EXEC route confirmed but executor/literal not resolved "
                                   "(is cwpatch loaded? run --cwpatch)")
            self.route = "exec"
            self._log(f"route: exec  (executor {self._rva(self.executor)}, slot {self._rva(self.exec_slot)})")
            return
        self.findvar = self.resolve("Dvar_FindVar")
        if not self.findvar:
            raise BackendError("Dvar_FindVar not resolved - cwpatch not loaded and the "
                               "fallback signature found nothing. Run --cwpatch.")
        if not DVAR_INT_PATH:
            raise BackendError(
                "value offset not pinned yet - live writes refused. In-game: "
                "`--findvar gf_menu_lines`, then `--diff <addr>` while changing the dvar "
                "in the menu, paste the path into DVAR_INT_PATH (README, 'the write primitive')."
            )
        self.route = "direct"
        self._log(f"route: direct  (Dvar_FindVar {self._rva(self.findvar)}, path {DVAR_INT_PATH})")

    def close(self) -> None:
        if self.proc:
            self.proc.close()
            self.proc = None

    # -- cwpatch anchor ---------------------------------------------------------
    def read_cwpatch_slots(self) -> dict[str, int]:
        """The qwords cwpatch filled in. {} if cwpatch is not the DLL in the slot."""
        try:
            self.cw_base, sz = find_module(self.pid, CWPATCH_MODULE)
        except BackendError:
            return {}
        if sz != CWPATCH_IMAGE_SIZE:
            self._log(f"{CWPATCH_MODULE} image is {sz:#x}, not cwpatch's {CWPATCH_IMAGE_SIZE:#x}")
            return {}
        out = {}
        for name, rva in CWPATCH_SLOTS.items():
            v = self.proc.read_u64(self.cw_base + rva)
            out[name] = v or 0
        return out

    def scan(self, sig: str) -> list[int]:
        """All matches of sig inside the main module (1 MB chunks, overlap for the sig)."""
        rx = compile_sig(sig)
        hits: list[int] = []
        step = 0x100000
        for off in range(0, self.size, step):
            chunk = self.proc.read(self.base + off, min(step + 64, self.size - off))
            if not chunk:
                continue
            for m in rx.finditer(chunk):
                a = self.base + off + m.start()
                if a not in hits:
                    hits.append(a)
        return hits

    def scan_resolve(self, name: str) -> tuple[int, list[int]]:
        """Resolve one cwpatch target by its signature. Returns (address, raw hits).
        callsite sigs are decoded (E8 rel32 -> callee) and must all agree."""
        sig, kind = CWPATCH_SIGS[name]
        hits = self.scan(sig)
        if not hits:
            return 0, hits
        if kind != "callsite":
            return hits[0], hits
        targets = set()
        for h in hits:
            rel = self.proc.read_i32(h + 1)
            if rel is not None:
                targets.add(h + 5 + rel)
        if len(targets) != 1:
            return 0, hits
        return targets.pop(), hits

    def resolve(self, name: str) -> int:
        """cwpatch's slot if it holds a sane in-module address, else the sig scan."""
        v = self.cw.get(name, 0)
        if v and self.base <= v < self.base + self.size:
            return v
        a, _ = self.scan_resolve(name)
        return a

    # -- the write primitives ----------------------------------------------------
    def find_var(self, name: str) -> int:
        """Dvar_FindVar(hash) -> dvar_t* (0 = not registered). One remote-thread call."""
        if not self.findvar:
            self.findvar = self.resolve("Dvar_FindVar")
            if not self.findvar:
                raise BackendError("Dvar_FindVar not resolved (run --cwpatch)")
        r = self.proc.call(self.findvar, (dvar_hash(name),))
        if r is None:
            raise BackendError("Dvar_FindVar did not return - the game may be wedged")
        return r

    def _lookup(self, name: str) -> int:
        p = self._ptrs.get(name, 0)
        if not p:
            p = self.find_var(name)
            if p:
                self._ptrs[name] = p
        return p

    def value_addr(self, dvar_ptr: int, path: tuple[int, ...] = None) -> int:
        """Follow DVAR_INT_PATH from a dvar_t* to the int32 cell. 0 if a hop is null."""
        path = DVAR_INT_PATH if path is None else path
        p = dvar_ptr
        for off in path[:-1]:
            q = self.proc.read_u64(p + off)
            if not q:
                return 0
            p = q
        return p + path[-1]

    def exec_command(self, cmd: str, timeout_ms: int = 5000) -> bool:
        """cwpatch's route: park cmd in the game's own string literal, run the executor
        on a remote thread, restore the literal. Refuses if the literal is not what we
        expect (wrong slot or already overwritten by someone else)."""
        if not self.executor:
            self.executor = self.resolve("executor")
        if not self.exec_slot:
            self.exec_slot = self.resolve(EXEC_SLOT)
        if not (self.executor and self.exec_slot):
            raise BackendError("executor / literal not resolved (is cwpatch loaded? --cwpatch)")
        lit = SLOT_LITERALS[EXEC_SLOT]
        orig = self.proc.read(self.exec_slot, EXEC_RESTORE_LEN)
        if not orig or not orig.startswith(lit):
            raise BackendError(f"literal at {self.exec_slot:#x} does not read {lit!r} - refusing")
        payload = cmd.encode("ascii") + b"\n\x00"
        if len(payload) > EXEC_RESTORE_LEN:
            raise BackendError(f"command too long ({len(payload)} > {EXEC_RESTORE_LEN} bytes)")
        if not self.proc.write(self.exec_slot, payload):
            raise BackendError("WriteProcessMemory on the literal failed")
        try:
            ok = self.proc.run(self.executor, timeout_ms)
        finally:
            self.proc.write(self.exec_slot, orig)
        return ok

    # -- the GUI-facing surface --------------------------------------------------
    def set_dvar(self, name: str, value) -> bool:
        value = str(value)
        if self.dry_run or not self.proc:
            self._log(f'[dry] set {name} {value}')
            return True
        if self.route == "exec":
            ok = self.exec_command(f"set {name} {value}")
            self._log(f'set {name} {value}  ' + ("ok (exec)" if ok else "EXECUTOR TIMED OUT"))
            return ok
        if self.route != "direct":
            self._log(f'set {name} {value}  REFUSED - no confirmed route (connect first)')
            return False
        try:
            ival = int(value)
        except ValueError:
            self._log(f'set {name} {value}  REFUSED - string dvar; the direct route writes ints '
                      f'only (needs the index encoding or the exec route)')
            return False
        ptr = self._lookup(name)
        if not ptr:
            self._log(f'set {name} {value}  REFUSED - dvar not registered yet '
                      f'(the GSC must setdvar it once: menu touch or init pre-register)')
            return False
        addr = self.value_addr(ptr)
        if not addr:
            self._log(f'set {name} {value}  FAILED - null hop in DVAR_INT_PATH at dvar {ptr:#x}')
            return False
        ok = self.proc.write(addr, struct.pack("<i", ival))
        back = self.proc.read_i32(addr)
        self._log(f'set {name} {value}  ' + (f"ok (readback {back})" if ok and back == ival
                                             else f"FAILED (write={ok}, readback={back})"))
        return ok and back == ival

    def apply(self, settings: dict) -> int:
        """Write a batch of gf_* dvars; returns the number of failures. gf_cmd_go is
        written last and withheld if anything before it failed, so the poller never
        fires on a half-written command."""
        failures = 0
        go = None
        for k, v in settings.items():
            if k == "gf_cmd_go":
                go = v
                continue
            if not self.set_dvar(k, v):
                failures += 1
        if go is not None:
            if failures and not self.dry_run:
                self._log("gf_cmd_go withheld - a trigger write failed above")
                failures += 1
            else:
                if not self.set_dvar("gf_cmd_go", go):
                    failures += 1
        return failures

    # -- internals -------------------------------------------------------------
    def _rva(self, a: int) -> str:
        if self.base <= a < self.base + self.size:
            return f"{PROC_NAME}+{a - self.base:#x}"
        return f"{a:#x}"

    def _log(self, msg: str) -> None:
        self.log.append(msg)


# =============================================================================== CLI
def _attach() -> DvarBackend:
    be = DvarBackend(dry_run=False)
    be.attach()
    for line in be.log:
        print(line)
    be.log.clear()
    return be


def _find_bytes(be: DvarBackend, needle: bytes, writable_only: bool, cap: int = 64) -> list[int]:
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


def _annotate(be: DvarBackend, q: int) -> str:
    if be.base <= q < be.base + be.size:
        return f"-> {PROC_NAME}+{q - be.base:#x}"
    if be.cw_base and be.cw_base <= q < be.cw_base + CWPATCH_IMAGE_SIZE:
        return f"-> {CWPATCH_MODULE}+{q - be.cw_base:#x}"
    if 0x10000 <= q < 0x7FFFFFFFFFFF and be.proc.read(q, 8):
        return "-> readable (heap/other)"
    return f"lo={q & 0xFFFFFFFF} hi={q >> 32}"


def _dump_annotated(be: DvarBackend, where: int, length: int = 0x80) -> None:
    blob = be.proc.read(where, length)
    if not blob:
        print(f"  read failed at {where:#x}")
        return
    for i in range(0, len(blob) - 7, 8):
        q = int.from_bytes(blob[i:i + 8], "little")
        print(f"  +{i:02X}: {q:#018x}   {_annotate(be, q)}")


def _snapshot(be: DvarBackend, addr: int, length: int) -> dict:
    """The struct plus one level of every pointer it holds (0x60 bytes each)."""
    main = be.proc.read(addr, length) or b""
    blocks = {}
    for off in range(0, len(main) - 7, 8):
        q = int.from_bytes(main[off:off + 8], "little")
        if 0x10000 <= q < 0x7FFFFFFFFFFF and q != addr:
            b = be.proc.read(q, 0x60)
            if b:
                blocks[off] = (q, b)
    return {"main": main, "blocks": blocks}


def cmd_cwpatch() -> int:
    """--cwpatch: what cwpatch resolved, cross-checked against our own scan of the
    same signatures. Read-only; nothing runs in the game."""
    be = _attach()
    print(f"\nmain module {PROC_NAME} @ {be.base:#x} ({be.size:#x} bytes)")
    print(f"{'target':20s} {'cwpatch slot':32s} {'our sig scan':32s} agree")
    agree_all = True
    for name in CWPATCH_SLOTS:
        slot = be.cw.get(name, 0)
        ours, hits = be.scan_resolve(name)
        s_txt = be._rva(slot) if slot else "-"
        o_txt = (be._rva(ours) if ours else "-") + (f" ({len(hits)} hit{'s' if len(hits) != 1 else ''})" if hits else "")
        agree = (slot == ours) if (slot and ours) else None
        agree_all = agree_all and bool(agree)
        print(f"{name:20s} {s_txt:32s} {o_txt:32s} {'yes' if agree else ('NO' if agree is False else '?')}")
    print("\n" + ("both methods agree on every target - the anchor is good."
                  if agree_all else
                  "disagreement or gaps above - do not go live until they agree."))
    for name, lit in SLOT_LITERALS.items():
        a = be.resolve(name)
        if a:
            got = be.proc.read(a, len(lit))
            print(f"  {name}: literal reads {got!r}" + ("" if got == lit else "  <<< NOT the expected text"))
    be.close()
    return 0 if agree_all else 1


def cmd_findvar(name: str, xcheck: bool) -> int:
    """--findvar <dvar>: Dvar_FindVar(hash) via one remote-thread call; prints the
    dvar_t* and an annotated dump. --xcheck also hash-scans memory (slow, read-only)
    and says whether the pointer is one of the registry sightings."""
    be = _attach()
    h = dvar_hash(name)
    print(f"\n{name!r}  hash={h:#018x}")
    fv = be.resolve("Dvar_FindVar")
    if not fv:
        print("Dvar_FindVar not resolved (run --cwpatch)"); be.close(); return 1
    be.findvar = fv
    print(f"Dvar_FindVar = {be._rva(fv)}  ... calling")
    ptr = be.find_var(name)
    if not ptr:
        print("  -> NULL: the dvar is not registered. Touch it in the in-game menu (or "
              "pre-register it at init) and retry.")
        be.close(); return 1
    print(f"  -> dvar_t* = {ptr:#x}\n")
    _dump_annotated(be, ptr, 0x80)
    print(f"\nnext:  python dvar_backend.py --diff {ptr:#x}    (then change {name} in the menu)")
    if xcheck:
        hits = _find_bytes(be, struct.pack("<Q", h), writable_only=True, cap=32)
        print(f"\nhash sightings in writable memory: {len(hits)}"
              + ("  - includes the FindVar pointer, consistent" if ptr in hits else
                 "  - FindVar pointer NOT among them (fine if the registry slot is not the dvar_t)"))
    be.close()
    return 0


def cmd_diff(addr_hex: str, length_hex: str = "0x80") -> int:
    """--diff <dvar_t*> [len]: snapshot, wait while you change the dvar in the in-game
    menu, snapshot again, print every int32 that moved - as a DVAR_INT_PATH to paste.
    Read-only."""
    be = _attach()
    addr = int(addr_hex, 16)
    length = int(length_hex, 16)
    a = _snapshot(be, addr, length)
    if not a["main"]:
        print(f"read failed at {addr:#x}"); be.close(); return 1
    print(f"\nsnapshot A taken at {addr:#x} ({len(a['main'])} bytes + {len(a['blocks'])} pointed-to blocks).")
    try:
        input("Now change the dvar IN-GAME (e.g. Menu display -> rows 3 -> 4), then press Enter... ")
    except EOFError:
        pass
    b = _snapshot(be, addr, length)
    changed = []
    for off in range(0, min(len(a["main"]), len(b["main"])) - 3, 4):
        x = int.from_bytes(a["main"][off:off + 4], "little", signed=True)
        y = int.from_bytes(b["main"][off:off + 4], "little", signed=True)
        if x != y:
            changed.append(((off,), addr + off, x, y))
    for poff, (q, ab) in a["blocks"].items():
        if poff not in b["blocks"] or b["blocks"][poff][0] != q:
            print(f"  pointer at +{poff:02X} changed target ({q:#x}) - re-run if nothing else shows")
            continue
        bb = b["blocks"][poff][1]
        for off in range(0, min(len(ab), len(bb)) - 3, 4):
            x = int.from_bytes(ab[off:off + 4], "little", signed=True)
            y = int.from_bytes(bb[off:off + 4], "little", signed=True)
            if x != y:
                changed.append(((poff, off), q + off, x, y))
    if not changed:
        print("nothing moved - did the change apply? (the menu prints the new value)")
        be.close(); return 1
    print("\nint32 cells that changed:")
    for path, absaddr, x, y in changed:
        print(f"  path {path!r:16s} @ {absaddr:#x}   {x} -> {y}")
    print("\nthe cell whose old->new equals the value you set is the dvar's `current`. "
          "Paste its path into DVAR_INT_PATH, then confirm with:\n"
          f"  python dvar_backend.py --poke 0x<that address> <another value>   and open the menu.")
    be.close()
    return 0


def cmd_poke(addr_hex: str, value: str) -> int:
    """--poke <abs addr> <int>: WriteProcessMemory one int32, read it back."""
    be = _attach()
    addr = int(addr_hex, 16)
    before = be.proc.read_i32(addr)
    ok = be.proc.write(addr, struct.pack("<i", int(value, 0)))
    after = be.proc.read_i32(addr)
    print(f"{addr:#x}: {before} -> {after}  ({'written' if ok else 'WRITE FAILED'})")
    be.close()
    return 0 if ok else 1


def cmd_exec(cmd: str, force: bool = False) -> int:
    """--exec "<console command>": the cwpatch executor route, once. 🪦 MEASURED to
    wedge the dvar lock (the executor never returns from a remote thread and leaves the
    lock held - relaunch needed). Refuses without --force so it is not re-run by
    accident; --force runs it anyway for deliberate re-measurement."""
    if EXEC_ROUTE_WEDGES and not force:
        print("--exec is DISABLED: measured 2026-09-12 to wedge the dvar subsystem - the\n"
              "executor does not return from a remote thread and leaves the dvar lock held,\n"
              "so every later dvar call hangs until the game is relaunched. Use route A\n"
              "(direct int write) instead. Pass --force to run it anyway (will wedge).")
        return 2
    be = _attach()
    ex = be.resolve("executor")
    sl = be.resolve(EXEC_SLOT)
    print(f"\nexecutor {be._rva(ex) if ex else '-'}   literal {be._rva(sl) if sl else '-'}")
    if not (ex and sl):
        print("not resolved - is cwpatch loaded? (--cwpatch)"); be.close(); return 1
    print(f"running {cmd!r} ...")
    ok = be.exec_command(cmd)
    print("  executor returned; literal restored." if ok else
          "  EXECUTOR DID NOT RETURN in 5 s - literal restored; the game may be wedged.")
    print("  now look in-game. If the dvar moved, set EXEC_ROUTE_CONFIRMED = True.")
    be.close()
    return 0 if ok else 1


def cmd_dump(rva_hex: str, length_hex: str = "0x120") -> int:
    """--dump 0xRVA [len]: hexdump main-module memory (read-only)."""
    be = _attach()
    rva = int(rva_hex, 16)
    length = int(length_hex, 16)
    data = be.proc.read(be.base + rva, length)
    if not data:
        print(f"read failed at base+{rva:#x}"); be.close(); return 1
    print(f"base={be.base:#x}  dump base+{rva:#x} ({length} bytes):")
    for i in range(0, len(data), 16):
        print(f"  +{rva + i:07X}  {' '.join(f'{b:02X}' for b in data[i:i + 16])}")
    be.close()
    return 0


def cmd_dumpabs(addr_hex: str, length_hex: str = "0x80") -> int:
    """--dumpabs 0xADDR [len]: annotated qword dump at an absolute address (read-only)."""
    be = _attach()
    _dump_annotated(be, int(addr_hex, 16), int(length_hex, 16))
    be.close()
    return 0


def cmd_finddvar(name: str, expect: int | None) -> int:
    """--finddvar <name> [expected-int]: the older read-only hunt - find the hash as a
    u64 key in writable memory and, given a value the dvar holds right now, report
    which offsets hold it. Kept as an independent cross-check of --findvar."""
    be = _attach()
    h = dvar_hash(name)
    print(f"dvar {name!r}  hash={h:#018x}" + (f"  expecting value {expect}" if expect is not None else ""))
    hrefs = _find_bytes(be, struct.pack("<Q", h), writable_only=True, cap=24)
    print(f"{len(hrefs)} hash sightings in writable memory")
    for r in hrefs:
        blob = be.proc.read(r, 0x60)
        if not blob:
            continue
        if expect is not None:
            found = [off for off in range(0x08, 0x60, 4)
                     if int.from_bytes(blob[off:off + 4], "little", signed=True) == expect]
            tag = ("  <<< value at +" + ",+".join(f"{o:#x}" for o in found)) if found else ""
            print(f"  entry @ {r:#x}{tag}")
        else:
            print(f"  entry @ {r:#x}")
            _dump_annotated(be, r, 0x50)
    be.close()
    return 0 if hrefs else 1


def self_test() -> int:
    """--self-test: touches no process."""
    fails = 0

    def check(label, cond):
        nonlocal fails
        print(("  ok   " if cond else "  FAIL ") + label)
        fails += 0 if cond else 1

    check("dvar_hash matches cwpatch's loot_fakeall constant",
          dvar_hash("loot_fakeall") == 0x60cdc482a7d159f8)
    stub = _call_stub(0x1122334455667788, (0xAABBCCDD00112233,), 0x0102030405060708)
    check("call stub: sub rsp,28 / mov rcx,imm64 / mov rax,imm64 / call rax / park rax / ret",
          stub.startswith(b"\x48\x83\xEC\x28\x48\xB9\x33\x22\x11\x00\xDD\xCC\xBB\xAA")
          and b"\x48\xB8\x88\x77\x66\x55\x44\x33\x22\x11\xFF\xD0" in stub
          and stub.endswith(b"\x48\x89\x01\x48\x83\xC4\x28\xC3"))
    check("call stub with 4 args uses rcx,rdx,r8,r9",
          _call_stub(1, (1, 2, 3, 4), 5).count(b"\x49\xB8") == 1
          and _call_stub(1, (1, 2, 3, 4), 5).count(b"\x49\xB9") == 1)
    for name, (sig, kind) in CWPATCH_SIGS.items():
        rx = compile_sig(sig)
        planted = bytes(int(t, 16) if t != "??" else 0x5A for t in sig.split())
        check(f"sig {name} ({kind}, {len(sig.split())} bytes) matches its own bytes",
              rx.search(b"\x00" * 7 + planted + b"\x00" * 7) is not None)
    for name, lit in SLOT_LITERALS.items():
        sig = CWPATCH_SIGS[name][0]
        check(f"literal sig {name} is exactly {lit!r}",
              bytes(int(t, 16) for t in sig.split()) == lit)
    check("E8 rel32 decode is signed", struct.unpack("<i", b"\xCC\xED\xFF\xFF")[0] == -0x1234)
    check("DVAR_INT_PATH / EXEC_ROUTE_CONFIRMED are consistent",
          isinstance(DVAR_INT_PATH, tuple) and isinstance(EXEC_ROUTE_CONFIRMED, bool))
    check("EXEC route stays disabled (measured to wedge the dvar lock)",
          EXEC_ROUTE_WEDGES and not EXEC_ROUTE_CONFIRMED)
    print("\n" + ("all checks passed" if not fails else f"{fails} check(s) FAILED"))
    return 0 if not fails else 1


USAGE = """dvar_backend.py - the memory layer for gf_control.py

  python gf_control.py                 the GUI, dry-run (safe anywhere)
  python gf_control.py --live          writes dvars; needs a confirmed route (README)

In-game, elevated shell, klaze at the keyboard:
  --self-test                          no process touched
  --cwpatch                            read cwpatch's resolved pointers + cross-check by sig (read-only)
  --findvar <dvar> [--xcheck]          Dvar_FindVar(hash) once -> dvar_t* + annotated dump
  --diff <dvar_t*> [len]               snapshot / you change the dvar in the menu / snapshot -> path
  --poke <abs addr> <int>              write one int32, read it back
  --exec "<command>" [--force]         🪦 DISABLED - the executor wedges the dvar lock from a
                                       remote thread (measured 2026-09-12). --force runs it anyway.
  --finddvar <dvar> [expected-int]     older read-only hash hunt (independent cross-check)
  --dump <rva> [len] / --dumpabs <addr> [len]   hexdumps, read-only
"""


def main(argv: list[str]) -> int:
    a = argv
    if "--self-test" in a:
        return self_test()
    if "--cwpatch" in a:
        return cmd_cwpatch()
    if "--findvar" in a:
        i = a.index("--findvar")
        return cmd_findvar(a[i + 1], "--xcheck" in a)
    if "--diff" in a:
        i = a.index("--diff")
        return cmd_diff(a[i + 1], a[i + 2] if len(a) > i + 2 and not a[i + 2].startswith("-") else "0x80")
    if "--poke" in a:
        i = a.index("--poke")
        return cmd_poke(a[i + 1], a[i + 2])
    if "--exec" in a:
        i = a.index("--exec")
        return cmd_exec(a[i + 1], force="--force" in a)
    if "--finddvar" in a:
        i = a.index("--finddvar")
        expect = None
        if len(a) > i + 2 and not a[i + 2].startswith("-"):
            try:
                expect = int(a[i + 2], 0)
            except ValueError:
                expect = None
        return cmd_finddvar(a[i + 1], expect)
    if "--dumpabs" in a:
        i = a.index("--dumpabs")
        return cmd_dumpabs(a[i + 1], a[i + 2] if len(a) > i + 2 else "0x80")
    if "--dump" in a:
        i = a.index("--dump")
        return cmd_dump(a[i + 1], a[i + 2] if len(a) > i + 2 else "0x120")
    print(USAGE)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except IndexError:
        print(USAGE)
        raise SystemExit(2)
    except BackendError as e:
        print(f"error: {e}")
        raise SystemExit(1)
