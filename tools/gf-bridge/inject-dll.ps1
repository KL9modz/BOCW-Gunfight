# inject-dll.ps1 - load a DLL into the running BlackOpsColdWar.exe (classic LoadLibrary inject).
#
#   pwsh tools/gf-bridge/inject-dll.ps1 -Dll C:\bocw\BOCW-Gunfight\tools\gf-bridge\gf_t1.dll
#
# Used to load the T1 test DLL (and, later, the bridge DLL) without rebuilding the cw-loader-shim.
# It does OpenProcess + VirtualAllocEx(path) + CreateRemoteThread(LoadLibraryA, path) - the standard
# injection. LoadLibrary is safe to call on a remote thread (it is NOT a dvar/engine call, so it does
# not touch the lock that wedged earlier attempts); the DLL's own DllMain then spawns its worker.
#
# ⚠ klaze runs this (it touches the game process). The agent wrote it. Run from an ELEVATED shell if
#   OpenProcess is refused. The game must already be running. For the PERSISTENT bridge, prefer chaining
#   the DLL in tools/cw-loader-shim instead (survives nothing-extra, loads at the proven time) - this
#   injector is the quick path for the F8 test.

param(
    [Parameter(Mandatory = $true)][string]$Dll,
    [string]$Proc = 'BlackOpsColdWar'
)
$ErrorActionPreference = 'Stop'

$Dll = (Resolve-Path $Dll).Path
if (-not (Test-Path $Dll)) { Write-Error "DLL not found: $Dll"; exit 1 }

$p = Get-Process -Name $Proc -ErrorAction SilentlyContinue
if (-not $p) { Write-Error "$Proc is not running"; exit 1 }
$pid0 = $p.Id

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Inj {
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr OpenProcess(uint a, bool inh, int pid);
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr addr, uint size, uint type, uint prot);
    [DllImport("kernel32", SetLastError=true)] public static extern bool WriteProcessMemory(IntPtr h, IntPtr addr, byte[] buf, uint size, out UIntPtr wrote);
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr CreateRemoteThread(IntPtr h, IntPtr attr, uint stack, IntPtr start, IntPtr arg, uint flags, IntPtr tid);
    [DllImport("kernel32", SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32", SetLastError=true)] public static extern bool GetExitCodeThread(IntPtr h, out uint code);
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr GetModuleHandleA(string m);
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr GetProcAddress(IntPtr h, string n);
    [DllImport("kernel32", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
}
"@

$PROCESS_ALL = 0x1F0FFF
$MEM_COMMIT_RESERVE = 0x3000
$PAGE_RW = 0x04

$h = [Inj]::OpenProcess($PROCESS_ALL, $false, $pid0)
if ($h -eq [IntPtr]::Zero) { Write-Error "OpenProcess failed ($([ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error()).Message)). Try an elevated shell."; exit 1 }

try {
    $bytes = [Text.Encoding]::ASCII.GetBytes($Dll + "`0")
    $remote = [Inj]::VirtualAllocEx($h, [IntPtr]::Zero, [uint32]$bytes.Length, $MEM_COMMIT_RESERVE, $PAGE_RW)
    if ($remote -eq [IntPtr]::Zero) { Write-Error "VirtualAllocEx failed"; exit 1 }
    $wrote = [UIntPtr]::Zero
    [void][Inj]::WriteProcessMemory($h, $remote, $bytes, [uint32]$bytes.Length, [ref]$wrote)

    $loadlib = [Inj]::GetProcAddress([Inj]::GetModuleHandleA("kernel32.dll"), "LoadLibraryA")
    $thr = [Inj]::CreateRemoteThread($h, [IntPtr]::Zero, 0, $loadlib, $remote, 0, [IntPtr]::Zero)
    if ($thr -eq [IntPtr]::Zero) { Write-Error "CreateRemoteThread failed"; exit 1 }

    [void][Inj]::WaitForSingleObject($thr, 5000)
    $code = 0
    [void][Inj]::GetExitCodeThread($thr, [ref]$code)
    [void][Inj]::CloseHandle($thr)
    if ($code -eq 0) {
        Write-Host "LoadLibrary returned 0 - the DLL's DllMain likely failed, or it was already loaded."
    } else {
        Write-Host ("injected {0} into pid {1} (module base 0x{2:X})" -f (Split-Path $Dll -Leaf), $pid0, $code)
    }
} finally {
    [void][Inj]::CloseHandle($h)
}
