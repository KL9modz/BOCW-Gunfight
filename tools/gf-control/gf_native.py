"""Native (ctypes) runtime steps for the standalone build - so the packaged .exe needs no
PowerShell or zig on the target, only the game.

  inject_dll(pid, path)          LoadLibrary a prebuilt DLL into the game (ports inject-dll.ps1)
  install_cwpatch(src, game_dir) put the cwpatch discord_game_sdk.dll in the game's slot
                                 (ports the restore half of ensure-cwpatch.ps1, hash-checked)
  game_exe_path(pid) / find_game_dir()  locate the install

Guard: injection and the cwpatch swap are the same operations the repo's PowerShell scripts do;
nothing here is hidden. The human runs the app.
"""
from __future__ import annotations

import ctypes
import ctypes.wintypes as wt
import hashlib
import os
import shutil

# cwpatch identity - docs/notes/unlock-dlls.md (the full hash, not the truncated one).
CWPATCH_SHA256 = "f72249204ff2cc03620a66e2bda8eb8308023e3a16754f5bfada611e646e84d1"
CWPATCH_SIZE = 13824

_k32 = ctypes.WinDLL("kernel32", use_last_error=True)
PROCESS_ALL_ACCESS = 0x1F0FFF
PROCESS_QUERY_LIMITED = 0x1000
MEM_COMMIT_RESERVE = 0x3000
PAGE_READWRITE = 0x04

for _fn, _res, _args in [
    ("OpenProcess", wt.HANDLE, [wt.DWORD, wt.BOOL, wt.DWORD]),
    ("VirtualAllocEx", wt.LPVOID, [wt.HANDLE, wt.LPVOID, ctypes.c_size_t, wt.DWORD, wt.DWORD]),
    ("WriteProcessMemory", wt.BOOL, [wt.HANDLE, wt.LPVOID, wt.LPCVOID, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]),
    ("CreateRemoteThread", wt.HANDLE, [wt.HANDLE, wt.LPVOID, ctypes.c_size_t, wt.LPVOID, wt.LPVOID, wt.DWORD, wt.LPVOID]),
    ("WaitForSingleObject", wt.DWORD, [wt.HANDLE, wt.DWORD]),
    ("GetExitCodeThread", wt.BOOL, [wt.HANDLE, ctypes.POINTER(wt.DWORD)]),
    ("GetModuleHandleA", wt.HMODULE, [wt.LPCSTR]),
    ("GetProcAddress", wt.LPVOID, [wt.HMODULE, wt.LPCSTR]),
    ("QueryFullProcessImageNameW", wt.BOOL, [wt.HANDLE, wt.DWORD, wt.LPWSTR, ctypes.POINTER(wt.DWORD)]),
    ("CloseHandle", wt.BOOL, [wt.HANDLE]),
]:
    getattr(_k32, _fn).restype = _res
    getattr(_k32, _fn).argtypes = _args


TH32CS_SNAPPROCESS = 0x00000002


class _PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [
        ("dwSize", wt.DWORD), ("cntUsage", wt.DWORD), ("th32ProcessID", wt.DWORD),
        ("th32DefaultHeapID", ctypes.POINTER(ctypes.c_ulong)), ("th32ModuleID", wt.DWORD),
        ("cntThreads", wt.DWORD), ("th32ParentProcessID", wt.DWORD),
        ("pcPriClassBase", ctypes.c_long), ("dwFlags", wt.DWORD),
        ("szExeFile", ctypes.c_wchar * 260),
    ]


_k32.CreateToolhelp32Snapshot.restype = wt.HANDLE
_k32.CreateToolhelp32Snapshot.argtypes = [wt.DWORD, wt.DWORD]
_k32.Process32FirstW.argtypes = [wt.HANDLE, ctypes.POINTER(_PROCESSENTRY32W)]
_k32.Process32NextW.argtypes = [wt.HANDLE, ctypes.POINTER(_PROCESSENTRY32W)]


def find_game_pid(name: str = "BlackOpsColdWar.exe") -> int:
    """PID of the running game, or 0 - no subprocess, so it never flashes a console."""
    snap = _k32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if not snap or snap == wt.HANDLE(-1).value:
        return 0
    try:
        e = _PROCESSENTRY32W()
        e.dwSize = ctypes.sizeof(e)
        if not _k32.Process32FirstW(snap, ctypes.byref(e)):
            return 0
        while True:
            if e.szExeFile.lower() == name.lower():
                return e.th32ProcessID
            if not _k32.Process32NextW(snap, ctypes.byref(e)):
                return 0
    finally:
        _k32.CloseHandle(snap)


def game_exe_path(pid: int):
    """Full path to a running process's exe, or None."""
    h = _k32.OpenProcess(PROCESS_QUERY_LIMITED, False, pid)
    if not h:
        return None
    try:
        buf = ctypes.create_unicode_buffer(1024)
        size = wt.DWORD(len(buf))
        if _k32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(size)):
            return buf.value
    finally:
        _k32.CloseHandle(h)
    return None


def find_game_dir(pid: int | None = None):
    """The BOCW install folder: from the running process if given, else common locations."""
    if pid:
        exe = game_exe_path(pid)
        if exe:
            return os.path.dirname(exe)
    for p in (
        r"D:\Battle.net\Call of Duty Black Ops Cold War",
        r"C:\Program Files\Call of Duty Black Ops Cold War",
        r"C:\Program Files (x86)\Battle.net\Call of Duty Black Ops Cold War",
        r"C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Black Ops Cold War",
    ):
        if os.path.exists(os.path.join(p, "BlackOpsColdWar.exe")):
            return p
    return None


def inject_dll(pid: int, dll_path: str) -> str:
    """LoadLibraryA a DLL into pid via a remote thread (the standard, non-evasive load).
    Returns a human-readable status line. Run elevated if OpenProcess is refused."""
    dll_path = os.path.abspath(dll_path)
    if not os.path.exists(dll_path):
        return f"DLL not found: {dll_path}"
    h = _k32.OpenProcess(PROCESS_ALL_ACCESS, False, pid)
    if not h:
        return f"OpenProcess failed (err {ctypes.get_last_error()}) - try running elevated"
    try:
        buf = (dll_path + "\0").encode("ascii")
        remote = _k32.VirtualAllocEx(h, None, len(buf), MEM_COMMIT_RESERVE, PAGE_READWRITE)
        if not remote:
            return "VirtualAllocEx failed"
        wrote = ctypes.c_size_t(0)
        _k32.WriteProcessMemory(h, remote, buf, len(buf), ctypes.byref(wrote))
        loadlib = _k32.GetProcAddress(_k32.GetModuleHandleA(b"kernel32.dll"), b"LoadLibraryA")
        if not loadlib:
            return "could not resolve LoadLibraryA"
        th = _k32.CreateRemoteThread(h, None, 0, loadlib, remote, 0, None)
        if not th:
            return f"CreateRemoteThread failed (err {ctypes.get_last_error()})"
        _k32.WaitForSingleObject(th, 5000)
        code = wt.DWORD(0)
        _k32.GetExitCodeThread(th, ctypes.byref(code))
        _k32.CloseHandle(th)
        if code.value == 0:
            return f"LoadLibrary returned 0 for {os.path.basename(dll_path)} (already loaded, or DllMain failed)"
        return f"injected {os.path.basename(dll_path)} into pid {pid} (module base 0x{code.value:X})"
    finally:
        _k32.CloseHandle(h)


def sha256(path: str):
    if not os.path.exists(path):
        return None
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def install_cwpatch(cwpatch_src: str, game_dir: str, game_running: bool = False) -> str:
    """Put cwpatch in <game_dir>\\discord_game_sdk.dll (backing up the stock SDK once).
    Refuses a source that fails the recorded hash - that file is the whole safety net.
    The slot is read at game start, so a fresh install takes effect on the NEXT launch."""
    if sha256(cwpatch_src) != CWPATCH_SHA256:
        return f"cwpatch source fails its hash check ({cwpatch_src}) - refusing to install"
    if not game_dir or not os.path.isdir(game_dir):
        return "game folder not found - can't install cwpatch"
    slot = os.path.join(game_dir, "discord_game_sdk.dll")
    if sha256(slot) == CWPATCH_SHA256:
        return "cwpatch already in place"
    if game_running:
        return "game is running with the stock DLL loaded - close it, then install cwpatch"
    stock_backup = os.path.join(game_dir, "discord_game_sdk.dll.stock")
    try:
        if os.path.exists(slot) and not os.path.exists(stock_backup):
            shutil.copy2(slot, stock_backup)
        shutil.copy2(cwpatch_src, slot)
    except PermissionError:
        return "can't write the game folder - run elevated (and close the game first)"
    except Exception as e:
        return f"cwpatch copy failed: {e}"
    if sha256(slot) == CWPATCH_SHA256:
        return "cwpatch installed - it loads on the NEXT game launch"
    return "cwpatch copy landed but the hash doesn't match - check the game folder"
