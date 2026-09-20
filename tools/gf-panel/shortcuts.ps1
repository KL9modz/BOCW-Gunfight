# shortcuts.ps1 - desktop + Start Menu shortcuts for the Gunfight Host Panel, and a taskbar pin.
#
#   powershell -ExecutionPolicy Bypass -File tools\gf-panel\shortcuts.ps1 [-Exe <path to GfPanel.exe>] [-NoPin]
#
# Default exe = the published bundle (dist\gf-panel\GfPanel.exe); pass -Exe for a copy somewhere else
# (a friend's unzipped bundle). The taskbar pin uses Explorer's own "Pin to taskbar" verb, exposed to
# scripts through a temporary HKCU\Software\Classes\*\shell\{:} handler entry (removed right after) -
# Windows has no supported pin API for unpackaged apps. If the pin does not land on this Windows build
# the script says so; then run the app and right-click its taskbar icon -> Pin to taskbar.
param(
    [string]$Exe = "$PSScriptRoot\dist\gf-panel\GfPanel.exe",
    [string]$Name = "Gunfight Host Panel",
    [switch]$NoPin
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Exe)) { throw "exe not found: $Exe (publish first: publish.ps1)" }
$Exe = (Resolve-Path $Exe).Path

function New-Shortcut([string]$lnk) {
    $ws = New-Object -ComObject WScript.Shell
    $s = $ws.CreateShortcut($lnk)
    $s.TargetPath = $Exe
    $s.WorkingDirectory = Split-Path $Exe
    $s.IconLocation = "$Exe,0"
    $s.Description = "Gunfight Host Panel - runs the modded BOCW Gunfight match"
    $s.Save()
    Write-Host "  shortcut: $lnk"
}

$desktop = [Environment]::GetFolderPath('Desktop')
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) "$Name.lnk"
New-Shortcut (Join-Path $desktop "$Name.lnk")
New-Shortcut $startMenu

if ($NoPin) { return }

# ---- taskbar pin ------------------------------------------------------------------------------
$pinned = Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\$Name.lnk"
if (Test-Path $pinned) { Write-Host "  taskbar: already pinned ($pinned)"; return }

$cmdStore = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\Windows.taskbarpin'
$k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($cmdStore)
if (-not $k) { Write-Warning "no Windows.taskbarpin verb in the CommandStore - pin manually"; return }
$muiVerb = [string]$k.GetValue('MUIVerb')          # "@shell32.dll,-51201"
$handler = [string]$k.GetValue('ExplorerCommandHandler')
$k.Close()

# resolve the localized verb text ("Pin to tas&kbar") so the right verb is invoked on any UI language
$shlwapi = Add-Type -Namespace Win32 -Name Shlwapi -PassThru -MemberDefinition @'
[DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
public static extern int SHLoadIndirectString(string pszSource, System.Text.StringBuilder pszOutBuf, int cchOutBuf, IntPtr ppvReserved);
'@
$sb = New-Object System.Text.StringBuilder 512
[void]$shlwapi::SHLoadIndirectString($muiVerb, $sb, $sb.Capacity, [IntPtr]::Zero)
$verbText = $sb.ToString().Replace('&', '')

# the temporary handler entry: exact key path via the .NET API (a PowerShell registry path with '*'
# would be globbed against every class under HKCU\Software\Classes)
$tmpKey = 'Software\Classes\*\shell\{:}'
$hk = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($tmpKey)
$hk.SetValue('ExplorerCommandHandler', $handler)
$hk.Close()
try {
    $shell = New-Object -ComObject Shell.Application
    $item = $shell.Namespace((Split-Path $startMenu)).ParseName((Split-Path $startMenu -Leaf))
    # Windows 11 24H2+ (measured on 26200): the handler shows up under the raw key name "&{:}", not
    # its localized title - accept either
    $verb = $item.Verbs() | Where-Object { $n = $_.Name.Replace('&', ''); $n -eq $verbText -or $n -eq '{:}' } | Select-Object -First 1
    if ($verb) {
        $verb.DoIt()
        # the pin is written asynchronously (took ~3 s on 26200) - poll for the pinned shortcut
        for ($i = 0; $i -lt 20 -and -not (Test-Path $pinned); $i++) { Start-Sleep -Milliseconds 500 }
    }
    else { Write-Warning "no pin verb appeared on the shortcut - pin manually" }
}
finally {
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($tmpKey, $false)
}
if (Test-Path $pinned) { Write-Host "  taskbar: pinned ($pinned)" }
else { Write-Warning "taskbar pin did not land on this Windows build - run the app, right-click its taskbar icon -> Pin to taskbar" }
