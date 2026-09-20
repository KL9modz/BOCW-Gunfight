#!/usr/bin/env python3
"""Capture OutputDebugStringA system-wide (the DBWIN protocol) and print it - a terminal DebugView.

    python tools/dbwin-capture.py [--filter gf_luihook] [--seconds 60]

Read-only: it creates the DBWIN shared buffer + events and prints whatever any process (e.g. the game
with gf_luihook.dll loaded) sends via OutputDebugStringA. One line per message, so the DLL's one-line
debug feed lands here directly. Only ONE debug monitor can capture at a time - close DebugView first.
"""
import argparse, ctypes, struct, sys, time
from ctypes import wintypes

k32 = ctypes.WinDLL('kernel32', use_last_error=True)
HANDLE, LPVOID, DWORD, BOOL = ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD, wintypes.BOOL
LPCSTR, SIZE_T = ctypes.c_char_p, ctypes.c_size_t

k32.CreateEventA.restype = HANDLE
k32.CreateEventA.argtypes = [LPVOID, BOOL, BOOL, LPCSTR]
k32.CreateFileMappingA.restype = HANDLE
k32.CreateFileMappingA.argtypes = [HANDLE, LPVOID, DWORD, DWORD, DWORD, LPCSTR]
k32.MapViewOfFile.restype = LPVOID
k32.MapViewOfFile.argtypes = [HANDLE, DWORD, DWORD, DWORD, SIZE_T]
k32.SetEvent.restype = BOOL
k32.SetEvent.argtypes = [HANDLE]
k32.WaitForSingleObject.restype = DWORD
k32.WaitForSingleObject.argtypes = [HANDLE, DWORD]

PAGE_READWRITE, FILE_MAP_READ, WAIT_OBJECT_0 = 0x04, 0x0004, 0
INVALID = HANDLE(-1)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--filter', default='', help='only print lines containing this substring')
    ap.add_argument('--seconds', type=float, default=0, help='stop after N seconds (0 = run until Ctrl-C)')
    a = ap.parse_args()

    # events: monitor sets BUFFER_READY (buffer free), writer sets DATA_READY (message waiting)
    buf_ready = k32.CreateEventA(None, False, False, b'DBWIN_BUFFER_READY')
    data_ready = k32.CreateEventA(None, False, False, b'DBWIN_DATA_READY')
    if not buf_ready or not data_ready:
        print('CreateEvent failed (%d) - another debug monitor (DebugView?) is running' % ctypes.get_last_error())
        return 1
    hmap = k32.CreateFileMappingA(INVALID, None, PAGE_READWRITE, 0, 4096, b'DBWIN_BUFFER')
    if not hmap:
        print('CreateFileMapping failed (%d) - another monitor holds DBWIN_BUFFER' % ctypes.get_last_error())
        return 1
    view = k32.MapViewOfFile(hmap, FILE_MAP_READ, 0, 0, 4096)
    if not view:
        print('MapViewOfFile failed (%d)' % ctypes.get_last_error()); return 1

    print('[dbwin] capturing (filter=%r) - inject the DLL / load into a match now' % (a.filter or None))
    sys.stdout.flush()
    k32.SetEvent(buf_ready)
    t0 = time.time()
    try:
        while True:
            r = k32.WaitForSingleObject(data_ready, 500)
            if r == WAIT_OBJECT_0:
                pid = struct.unpack_from('<I', ctypes.string_at(view, 4))[0]
                msg = ctypes.string_at(view + 4).decode('ascii', 'replace').rstrip('\r\n')
                if not a.filter or a.filter in msg:
                    print('[pid %d] %s' % (pid, msg)); sys.stdout.flush()
                k32.SetEvent(buf_ready)
            if a.seconds and (time.time() - t0) >= a.seconds:
                print('[dbwin] done (%.0fs)' % a.seconds); break
    except KeyboardInterrupt:
        print('[dbwin] stopped')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
