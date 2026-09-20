# publish.ps1 - build the self-contained single-file Gunfight Host Panel and lay out the bundle
# friends run with nothing installed (the runtime is embedded). Mirrors the old PyInstaller bundle:
#
#   dist\gf-panel\
#     GfPanel.exe                         the panel (~70 MB, .NET 9 runtime inside)
#     acts\                               ACTS (acts injectcw injects the menu payload)
#     gf-bridge\gf_bridge.dll             the in-process bridge DLL (prebuilt, zig cc)
#     vendor\discord_game_sdk.CWPATCH-13824.dll   cwpatch (hash-checked before it is ever copied)
#     payloads\gunfight_menu.gscc         the menu payload (the LIVE build), + any side builds passed in
#
#   powershell -ExecutionPolicy Bypass -File tools\gf-panel\publish.ps1 [-Payload C:\bocw\payloads\gunfight_menu.panel.gscc]
#
# ⚠ Same caveats as the old bundle: pinned to the current game build + cwpatch; AV flags injectors;
#    keep it to a TRUSTED group (the project's throwaway-PC / blast-radius rule).
param(
    [string[]]$Payload = @(),
    [string]$Out = "$PSScriptRoot\dist\gf-panel"
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$proj = "$PSScriptRoot\GfPanel\GfPanel.csproj"
$acts = (Resolve-Path "$repo\..\ACTS\bin" -ErrorAction SilentlyContinue).Path
$bridge = "$repo\tools\gf-bridge\gf_bridge.dll"
$cwpatch = "$repo\..\vendor-backup\discord_game_sdk.CWPATCH-13824.dll"
$livePayload = "$repo\..\payloads\gunfight_menu.gscc"

Write-Host "publishing GfPanel (self-contained, single-file, win-x64)..."
& dotnet publish $proj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -o "$Out" -nologo -v q
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed ($LASTEXITCODE)" }
Get-ChildItem "$Out\*.pdb" -ErrorAction SilentlyContinue | Remove-Item -Force

if ($acts) {
    if (Test-Path "$Out\acts") { Remove-Item "$Out\acts" -Recurse -Force }
    # everything acts injectcw needs, minus the dev scratch (.gsccasm dumps, scans) and the 506 MB
    # decrypted-exe dump in deps\ (only the fastfile/dump tools use it - and it must never ship)
    & robocopy $acts "$Out\acts" /E /NFL /NDL /NJH /NJS /XF BlackOpsColdWar_dump.exe *.gsccasm *.bak /XD scans | Out-Null
    Write-Host "  acts: $acts (without deps\BlackOpsColdWar_dump.exe, *.gsccasm, scans\)"
} else { Write-Warning "ACTS not found beside the repo - the bundle cannot inject the menu" }
New-Item -ItemType Directory -Force "$Out\gf-bridge", "$Out\vendor", "$Out\payloads" | Out-Null
if (Test-Path $bridge) { Copy-Item $bridge "$Out\gf-bridge\" -Force; Write-Host "  bridge: $bridge" } else { Write-Warning "gf_bridge.dll missing" }
if (Test-Path $cwpatch) { Copy-Item $cwpatch "$Out\vendor\" -Force; Write-Host "  cwpatch: $cwpatch" } else { Write-Warning "cwpatch source missing" }
if (Test-Path $livePayload) { Copy-Item $livePayload "$Out\payloads\" -Force; Write-Host "  payload: $livePayload" } else { Write-Warning "live payload missing" }
# -File passes "a,b" as ONE string (no PowerShell parsing), so split on commas ourselves
foreach ($pl in ($Payload -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
    if (Test-Path $pl) { Copy-Item $pl "$Out\payloads\" -Force; Write-Host "  payload: $pl" } else { Write-Warning "payload not found: $pl" }
}

$exe = Get-Item "$Out\GfPanel.exe"
Write-Host ("done: {0}  ({1:N0} B)" -f $exe.FullName, $exe.Length)
$total = (Get-ChildItem $Out -Recurse -File | Measure-Object Length -Sum).Sum
Write-Host ("bundle: {0:N0} B" -f $total)
