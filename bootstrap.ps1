#Requires -Version 5
<#
    bootstrap.ps1 - set up the BOCW-Gunfight workspace on a fresh machine.

    `git clone` gives you the SOURCE; this fetches/rebuilds the pieces that live OUTSIDE the
    repo (gitignored because they are too big, re-fetchable, or third-party). It creates them
    as SIBLINGS of the repo - the app and check-gsc.ps1 resolve them at "..":

        <root>\
          BOCW-Gunfight\      <- this repo (git clone)
          ACTS\               <- compiler/injector      (download, pinned v3.3.0)
          bocw-source-main\   <- T9 dump, validation only (git clone --depth 1, ~664 MB)
          payloads\           <- built *.gscc            (rebuilt from src\ here)
          vendor-backup\      <- cwpatch (irreplaceable)  (provide with -Cwpatch)

    Run from the repo root:
        .\bootstrap.ps1
        .\bootstrap.ps1 -Cwpatch 'D:\backup\discord_game_sdk.CWPATCH-13824.dll'
        .\bootstrap.ps1 -SkipDump -NoBuild      # skip the 664 MB clone and the payload rebuild

    Idempotent and non-destructive: it only creates/updates the siblings above and the app
    launcher/shortcut. It never deletes your data and never touches the game process.
#>
[CmdletBinding()]
param(
    [string]$Cwpatch,     # path to a cwpatch discord_game_sdk.dll (13,824 bytes) to copy in
    [switch]$SkipDump,    # do not clone bocw-source (only check-gsc stages 3-4 need it)
    [switch]$NoBuild      # do not rebuild the payloads from src\
)

$Repo = $PSScriptRoot
$Root = Split-Path $Repo -Parent
if (-not (Test-Path (Join-Path $Repo 'src')) -or -not (Test-Path (Join-Path $Repo 'tools'))) {
    Write-Host "Run this from the BOCW-Gunfight repo root (it must contain src\ and tools\)." -ForegroundColor Red
    exit 1
}
$ErrorActionPreference = 'Continue'   # report and keep going; we summarise at the end

$script:ok = @(); $script:warn = @(); $script:todo = @()
function Head($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Good($m) { Write-Host "  [ok]   $m" -ForegroundColor Green;   $script:ok   += $m }
function Warn($m) { Write-Host "  [warn] $m" -ForegroundColor Yellow;  $script:warn += $m }
function Todo($m) { Write-Host "  [TODO] $m" -ForegroundColor Magenta; $script:todo += $m }

Head "workspace"
Write-Host "  repo : $Repo"
Write-Host "  root : $Root   (ACTS, bocw-source-main, payloads, vendor-backup live here)"

Head "prerequisites on PATH"
$prereq = @(
    @{ n = 'git';     hint = 'https://git-scm.com' }
    @{ n = 'python';  hint = 'https://python.org (3.x, includes tkinter)' }
    @{ n = 'pythonw'; hint = 'ships with Python on Windows' }
    @{ n = 'zig';     hint = 'https://ziglang.org (to build gf_bridge.dll)' }
)
foreach ($t in $prereq) {
    $c = Get-Command $t.n -ErrorAction SilentlyContinue
    if ($c) { Good ("{0}  ->  {1}" -f $t.n, $c.Source) }
    else    { Todo ("{0} not found - install {1}" -f $t.n, $t.hint) }
}

Head "ACTS (compiler / injector)"
$ActsDir = Join-Path $Root 'ACTS'
$Acts    = Join-Path $ActsDir 'bin\acts.exe'
if (Test-Path $Acts) {
    Good "acts.exe present: $Acts"
} else {
    Todo "acts.exe missing - download ACTS and place it so acts.exe sits at $Acts"
    Todo "  releases: https://github.com/ate47/atian-cod-tools/releases  (project is pinned to v3.3.0)"
}
if (Test-Path (Join-Path $ActsDir 'bin')) {
    # ACTS silently self-updates and can rewrite bin\ mid-run (it once replaced compile output).
    $upd = Join-Path $ActsDir 'bin\acts-updater.json'
    '{ "disabled": true, "timeDelta": 86400000, "lastCheck": 0, "forced": false }' | Set-Content $upd -Encoding ASCII
    Good "ACTS auto-updater disabled"
}

Head "bocw-source dump (check-gsc API validation only)"
$Dump  = Join-Path $Root 'bocw-source-main'
$probe = Join-Path $Dump 'scripts\mp_common\gametypes\gunfight.gsc'
if ($SkipDump) {
    Warn "skipped (-SkipDump) - check-gsc stages 3-4 need it; stages 1-2 still work without it"
} elseif (Test-Path $probe) {
    Good "dump present ($Dump)"
} elseif (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host "  cloning ate47/bocw-source (~664 MB, --depth 1) ..."
    Push-Location $Root
    try { & git clone --depth 1 https://github.com/ate47/bocw-source.git bocw-source-main } finally { Pop-Location }
    if (Test-Path $probe) { Good "dump cloned" }
    else { Warn "clone finished but scripts\ is missing - the GitHub ZIP arrives incomplete; re-clone" }
} else {
    Todo "git missing - install it, or re-run with -SkipDump"
}

Head "cwpatch (the one irreplaceable third-party binary - NOT in the public repo)"
$Vendor = Join-Path $Root 'vendor-backup'
$CwDst  = Join-Path $Vendor 'discord_game_sdk.CWPATCH-13824.dll'
if ($Cwpatch) {
    if (Test-Path $Cwpatch) {
        $len = (Get-Item $Cwpatch).Length
        if ($len -ne 13824) { Warn "the -Cwpatch file is $len bytes, expected 13824 (the cwpatch build) - copying anyway" }
        New-Item -ItemType Directory -Force $Vendor | Out-Null
        Copy-Item $Cwpatch $CwDst -Force
        Good "cwpatch copied to $CwDst"
    } else { Todo "-Cwpatch path not found: $Cwpatch" }
} elseif (Test-Path $CwDst) {
    Good "cwpatch present ($CwDst)"
} else {
    Todo "cwpatch missing - it cannot ship in the public repo. Copy your backup in, or re-run with:"
    Todo "    .\bootstrap.ps1 -Cwpatch '<path to discord_game_sdk.CWPATCH-13824.dll>'"
    Todo "  Then tools\ensure-cwpatch.ps1 keeps it in the game's Discord slot. The bridge is inert without it."
}

Head "payloads (rebuilt from src\)"
$Payloads = Join-Path $Root 'payloads'
if ($NoBuild) {
    Warn "skipped (-NoBuild)"
} elseif (-not (Test-Path $Acts)) {
    Todo "can't build payloads without acts.exe (see ACTS above)"
} else {
    New-Item -ItemType Directory -Force $Payloads | Out-Null
    $strip = Join-Path $Repo 'tools\strip-strhdr.ps1'
    foreach ($proj in @('gunfight_menu', 'gunfight_mod')) {
        $src = Join-Path $Repo "src\$proj\scripts\$proj.gsc"
        if (-not (Test-Path $src)) { Warn "source for $proj not found ($src) - skipping"; continue }
        $tmp = Join-Path $env:TEMP $proj
        Push-Location (Split-Path $Acts -Parent)
        try { & $Acts gscc $src -g cw -p pc -o $tmp *> $null } finally { Pop-Location }
        if (Test-Path "$tmp.gscc") {
            & $strip -In "$tmp.gscc" -Out (Join-Path $Payloads "$proj.gscc") | Out-Null
            Good ("built payloads\{0}.gscc" -f $proj)
        } else { Warn "acts did not produce $proj.gscc" }
    }
    Warn "the Atian-menu payload (BlackOpsColdWar_atianmenu_pc.gscc) is a separate download - not rebuilt here"
}

Head "control app launcher + desktop shortcut"
$pyw = (Get-Command pythonw -ErrorAction SilentlyContinue).Source
if ($pyw) {
    $cmd = Join-Path $Repo 'tools\gf-control\gf-control.cmd'
    if (Test-Path $cmd) {
        (Get-Content $cmd) -replace '^\s*set\s+"PYW=.*"\s*$', ('set "PYW={0}"' -f $pyw) | Set-Content $cmd -Encoding ASCII
        Good "gf-control.cmd PYW -> $pyw"
    }
    $dir = Join-Path $Repo 'tools\gf-control'
    $ico = Join-Path $dir 'assets\logo.ico'
    try {
        $W = New-Object -ComObject WScript.Shell
        $lnk = $W.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Gunfight Host Control.lnk'))
        $lnk.TargetPath = $pyw
        $lnk.Arguments = ('"{0}\gf_control.py" --live' -f $dir)
        $lnk.WorkingDirectory = $dir
        if (Test-Path $ico) { $lnk.IconLocation = "$ico,0" }
        $lnk.Description = 'Gunfight Host Control (LIVE)'
        $lnk.Save()
        Good "desktop shortcut created (with the gunfight.us icon)"
    } catch { Warn "could not create the desktop shortcut: $($_.Exception.Message)" }
} else {
    Todo "pythonw not found - install Python (with tkinter), then re-run to fix the launcher + shortcut"
}

Head "game"
$game = Get-Process -Name BlackOpsColdWar -ErrorAction SilentlyContinue
if ($game) {
    Good "BlackOpsColdWar.exe is RUNNING (pid $($game.Id))"
} else {
    $candidates = @(
        'D:\Battle.net\Call of Duty Black Ops Cold War\BlackOpsColdWar.exe'
        'C:\Program Files\Call of Duty Black Ops Cold War\BlackOpsColdWar.exe'
        'C:\Program Files (x86)\Battle.net\Call of Duty Black Ops Cold War\BlackOpsColdWar.exe'
        'C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Black Ops Cold War\BlackOpsColdWar.exe'
    )
    $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($found) { Good "found (not running): $found" }
    else { Todo "BlackOpsColdWar.exe not found in the common locations - install BOCW (Battle.net) and launch it before injecting" }
}

Head "toolchain smoke test"
if ((Test-Path $Acts) -and (Test-Path $probe)) {
    $smoke = Get-ChildItem (Join-Path $Repo 'src') -Recurse -Filter *.gsc -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -match 'hello|tweaks|gunfight_menu' } | Select-Object -First 1 -ExpandProperty FullName
    if ($smoke) {
        Write-Host "  check-gsc on $((Split-Path $smoke -Leaf)) ..."
        & (Join-Path $Repo 'tools\check-gsc.ps1') $smoke 2>&1 | Select-Object -Last 3 | ForEach-Object { Write-Host "  $_" }
    } else { Warn "no smoke-test script found under src\" }
} else {
    Warn "skipped (needs acts.exe and the dump)"
}

Head "summary"
Write-Host ("  ready:    {0}" -f $script:ok.Count)   -ForegroundColor Green
Write-Host ("  warnings: {0}" -f $script:warn.Count) -ForegroundColor Yellow
if ($script:todo.Count) {
    Write-Host "  STILL NEEDED before you can drive a match:" -ForegroundColor Magenta
    $script:todo | ForEach-Object { Write-Host "    - $_" -ForegroundColor Magenta }
} else {
    Write-Host "`n  All set. Launch the game, run tools\ensure-cwpatch.ps1, then open the" -ForegroundColor Green
    Write-Host "  'Gunfight Host Control' desktop shortcut and use Inject / Status -> Set up all." -ForegroundColor Green
}
