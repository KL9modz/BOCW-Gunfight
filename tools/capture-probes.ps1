# Capture the BOCW window repeatedly so probe output can be READ BY THE AGENT
# instead of transcribed by a human.
#
# Every probe test in this project prints PROBE_ID*100000+VALUE via iprintlnbold,
# five seconds apart, and until 2026-09-09 the only way to get those numbers back
# was for klaze to read them off the screen and type them out. That is slow,
# error-prone, and - his words - tiring. GDI capture of the game window works
# (verified 2026-09-09, windowed mode, 2560x1440), so this removes him from the
# loop entirely.
#
#   pwsh tools/capture-probes.ps1                 # 20 frames, 3s apart, 60s total
#   pwsh tools/capture-probes.ps1 -Seconds 90     # longer window
#   pwsh tools/capture-probes.ps1 -Every 2        # tighter interval
#
# ⚠ The probe cadence is 5s per line and a run emits 3-6 lines starting ~10s after
#   the round begins. Default 3s over 60s comfortably covers that with overlap, so
#   no line is missed between frames.
#
# ⚠ Captures the GAME WINDOW ONLY, not the whole desktop - smaller files, and it
#   keeps the terminal (which shows this project's own text, including expected
#   values) out of the frame. Reading an expectation back as a result would be the
#   worst possible failure mode for a measurement tool.
#
# ⚠ GDI capture returns black under exclusive fullscreen. If frames come back
#   black, set the game to Windowed or Borderless.

param(
    [int]$Seconds = 60,
    [double]$Every = 3,
    [string]$OutDir = "$env:TEMP\bocw-probes"
)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string n);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    public struct RECT { public int Left, Top, Right, Bottom; }
    public struct POINT { public int X, Y; }
}
"@

# ⚠ LOAD-BEARING. Without it PowerShell reports window coordinates in LOGICAL
#   pixels while CopyFromScreen works in PHYSICAL ones, so on any scaled display
#   the captured region is offset from the window. Measured 2026-09-09 on a
#   2560x1440 screen: the grab started ~390px left of the game and pulled THE
#   TERMINAL into frame - which at that moment was displaying this project's own
#   predicted probe values. A capture tool that can photograph its own
#   expectations and hand them back as data is worse than no tool at all.
[void][Win]::SetProcessDPIAware()

$proc = Get-Process -Name BlackOpsColdWar -ErrorAction SilentlyContinue
if (-not $proc) { Write-Output "BOCW not running"; exit 1 }

$h = $proc.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { Write-Output "no main window handle"; exit 1 }

$r = New-Object Win+RECT
[void][Win]::GetClientRect($h, [ref]$r)
$p = New-Object Win+POINT
[void][Win]::ClientToScreen($h, [ref]$p)

$w = $r.Right - $r.Left
$ht = $r.Bottom - $r.Top
if ($w -le 0 -or $ht -le 0) { Write-Output "bad window rect ${w}x${ht}"; exit 1 }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Get-ChildItem "$OutDir\*.png" -ErrorAction SilentlyContinue | Remove-Item -Force

Write-Output "capturing ${w}x${ht} at ($($p.X),$($p.Y)) -> $OutDir"

$frames = [math]::Floor($Seconds / $Every)
$origin = New-Object System.Drawing.Point($p.X, $p.Y)
$size = New-Object System.Drawing.Size($w, $ht)

for ($i = 0; $i -lt $frames; $i++) {
    $bmp = New-Object System.Drawing.Bitmap $w, $ht
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($origin, [System.Drawing.Point]::Empty, $size)
    $bmp.Save((Join-Path $OutDir ("f{0:D3}.png" -f $i)), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Start-Sleep -Milliseconds ([int]($Every * 1000))
}

Write-Output "done: $frames frames"
