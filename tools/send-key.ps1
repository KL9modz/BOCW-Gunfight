# Send a real keypress to the BOCW window, so the agent can drive the F4/F6/F7
# cwpatch hotkeys without the human touching the keyboard.
#
#   pwsh tools/send-key.ps1 -Key F7      # full_restart  (relink an injection)
#   pwsh tools/send-key.ps1 -Key F6      # fast_restart
#   pwsh tools/send-key.ps1 -Key F4      # lobbylaunchgame
#
# ⚠ USES SCAN CODES, NOT VIRTUAL KEYS, AND THAT IS THE WHOLE POINT. Games read
#   keyboard input through DirectInput / raw input, which is driven by hardware
#   scan codes. SendKeys and PostMessage push virtual-key messages into a window's
#   message queue and games routinely ignore them entirely. SendInput with
#   KEYEVENTF_SCANCODE synthesises an event at the same layer a real key does, so
#   a low-level hook - which is exactly what cwpatch installs for F4/F6/F7 - sees
#   it.
#
# ⚠ Injected input is flagged LLKHF_INJECTED. A hook is free to filter on that, so
#   this working is not guaranteed by construction - it has to be tested. If the
#   key does nothing, that flag is the first suspect, not the scan code.
#
# ⚠ Focuses the game window first. Input goes to the FOREGROUND window, so without
#   this the keypress lands wherever the user was last typing - which, mid-session,
#   is the terminal running this project.

param(
    [ValidateSet('F4','F6','F7')]
    [string]$Key = 'F7'
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Kb {
    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT {
        public ushort wVk; public ushort wScan; public uint dwFlags;
        public uint time; public IntPtr dwExtraInfo;
    }
    [StructLayout(LayoutKind.Explicit, Size=40)]
    public struct INPUT {
        [FieldOffset(0)]  public uint type;
        [FieldOffset(8)]  public KEYBDINPUT ki;
    }
    [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] p, int cb);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
}
"@

# Scan codes (set 1). F1=0x3B..F10=0x44, so F4=0x3E, F6=0x40, F7=0x41.
$scan = @{ 'F4' = 0x3E; 'F6' = 0x40; 'F7' = 0x41 }[$Key]

$proc = Get-Process -Name BlackOpsColdWar -ErrorAction SilentlyContinue
if (-not $proc) { Write-Output "BOCW not running"; exit 1 }

$h = $proc.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { Write-Output "no main window handle"; exit 1 }

[void][Kb]::ShowWindow($h, 9)          # SW_RESTORE, in case it is minimised
[void][Kb]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 600           # let focus actually settle before typing

$KEYEVENTF_SCANCODE = 0x0008
$KEYEVENTF_KEYUP    = 0x0002

$down = New-Object Kb+INPUT
$down.type = 1
$down.ki.wScan = $scan
$down.ki.dwFlags = $KEYEVENTF_SCANCODE

$up = New-Object Kb+INPUT
$up.type = 1
$up.ki.wScan = $scan
$up.ki.dwFlags = $KEYEVENTF_SCANCODE -bor $KEYEVENTF_KEYUP

$sent = [Kb]::SendInput(1, [Kb+INPUT[]]@($down), [Runtime.InteropServices.Marshal]::SizeOf([type][Kb+INPUT]))
Start-Sleep -Milliseconds 80            # a real press is not instantaneous
$sent += [Kb]::SendInput(1, [Kb+INPUT[]]@($up), [Runtime.InteropServices.Marshal]::SizeOf([type][Kb+INPUT]))

Write-Output "$Key (scan 0x$('{0:X2}' -f $scan)) sent to pid $($proc.Id); events accepted: $sent/2"
