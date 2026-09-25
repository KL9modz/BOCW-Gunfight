# build-menu.ps1 - gunfight_menu.gsc to the LIVE slot in ONE command (klaze 2026-09-24: "yes make the build
# script", after "its taking 20+ minutes just to make any small edit"). The steps CLAUDE.md's GSC crash rules
# require, in order, stopping at the first failure - nothing is promoted unless every step passed:
#
#   1 check    tools\check-gsc.ps1 (compile + decompiler round-trip + every ns::fn and builtin resolves)
#   2 compile  reuses step 1's `acts gscc -g cw -p pc` output (compiles again only if that is missing)
#   3 strip    tools\strip-strhdr.ps1 -> ..\payloads\gunfight_menu.<tag>.gscc (the side build)
#   4 verify   0 strings still carrying the 0x8B header, 0 strings with a byte < 0x20 (one newline sent to a
#              client closes the match), the longest literal < 1024, every -Expect string present, the
#              panel-channel markers present; size and string count compared with the live slot
#   5 promote  back up the live slot as gunfight_menu.safe-<sha8>.bak.gscc (once), copy the build over it, and
#              copy it into tools\gf-panel\dist\gf-panel\payloads\ when that folder exists
#
#   .\tools\build-menu.ps1                                  all five steps
#   .\tools\build-menu.ps1 -Expect 'Ammo Type','Normal bullets'   plus: these strings must be in the build
#   .\tools\build-menu.ps1 -NoPromote                       stop after verify (leaves the side build)
#   .\tools\build-menu.ps1 -Tests                           then run tools\gf-panel\GfPanel.Tests too
#
# Time: ~4 minutes, nearly all of it ACTS working on this 26,500-line file inside check-gsc (MEASURED
# 2026-09-24 with the game running: check 221 s, of which ~130 s is the compile). Strip / verify / promote
# take under a second each.
# The promote never touches a running game: a new payload loads the next time the panel injects, after a game
# relaunch. The script does not message peer sessions - announce shared-file edits yourself.
param(
    [string]$Source = "$PSScriptRoot\..\src\gunfight_menu\scripts\gunfight_menu.gsc",
    [string]$Tag = ('b' + (Get-Date -Format 'MMdd-HHmm')),
    [string[]]$Expect = @(),
    [switch]$NoPromote,
    [switch]$Tests,
    [switch]$ShowCheck
)
$ErrorActionPreference = 'Continue'     # acts writes benign warnings to stderr - gate on exit codes instead
$t0 = Get-Date
$repo = (Resolve-Path "$PSScriptRoot\..").Path
$src = (Resolve-Path $Source).Path
$acts = (Resolve-Path "$repo\..\ACTS\bin\acts.exe" -ErrorAction SilentlyContinue).Path
$payloads = (Resolve-Path "$repo\..\payloads" -ErrorAction SilentlyContinue).Path
$live = if ($payloads) { Join-Path $payloads 'gunfight_menu.gscc' } else { $null }
$distPayloads = Join-Path $repo 'tools\gf-panel\dist\gf-panel\payloads'

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }
function Fail($msg) { Say ("FAILED - " + $msg + "  (nothing promoted)") 'Red'; exit 1 }
function Sha8($path) { (Get-FileHash $path -Algorithm SHA256).Hash.Substring(0, 8) }
function Lap($name, $since) { Say ("  {0} ok ({1:N0} s)" -f $name, ((Get-Date) - $since).TotalSeconds) 'Green' }

if (-not $acts) { Fail "acts.exe not found beside the repo (..\ACTS\bin\acts.exe)" }
if (-not $payloads) { Fail "the payloads folder is not beside the repo (..\payloads)" }

# 1 check - its per-call listing is long; show it only on failure (or with -ShowCheck)
$t = Get-Date
Say "1/5 check-gsc ..."
$checkOut = & "$PSScriptRoot\check-gsc.ps1" $src *>&1 | ForEach-Object { "$_" }
$checkCode = $LASTEXITCODE
if ($ShowCheck -or $checkCode -ne 0) { $checkOut | ForEach-Object { Say "    $_" } }
if ($checkCode -ne 0 -or -not ($checkOut | Where-Object { $_ -like 'PASS*' })) { Fail "check-gsc (exit $checkCode) - see the lines above" }
Lap 'check' $t

# 2 compile - REUSE check-gsc's own compile (the same `acts gscc <src> -g cw -p pc`, written to
# %TEMP%\gsccheck_<name>\<name>.gscc). MEASURED 2026-09-24: ACTS scales with the file - a 176-line script
# compiles in 0.9 s, gunfight_menu.gsc (26,500 lines) in 131 s - so a second compile was 2 of the 6 minutes.
# Its output is NOT byte-stable (two compiles of one source: same size and strings, ~22% of bytes moved -
# the function layout), so a sha change alone does not mean the code changed.
# (acts resolves data\games\cw.json against the working directory - hence the Push-Location.)
$t = Get-Date
Say "2/5 compile ..."
$work = Join-Path $env:TEMP 'gf_build_menu'
New-Item -ItemType Directory -Force $work | Out-Null
$rawBase = Join-Path $work "gunfight_menu.$Tag.raw"
Remove-Item "$rawBase.gscc" -ErrorAction SilentlyContinue
$name = [IO.Path]::GetFileNameWithoutExtension($src)
$checkBuild = Join-Path (Join-Path $env:TEMP "gsccheck_$name") "$name.gscc"
if ((Test-Path $checkBuild) -and (Get-Item $checkBuild).LastWriteTime -ge $t0) {
    Copy-Item $checkBuild "$rawBase.gscc"
    Say "  (check-gsc's compile of this run reused - no second compile)"
}
else {
    Push-Location (Split-Path $acts -Parent)
    try { $compileOut = & $acts gscc $src -g cw -p pc -o $rawBase *>&1 | ForEach-Object { "$_" }; $compileCode = $LASTEXITCODE }
    finally { Pop-Location }
    if ($compileCode -ne 0 -or -not (Test-Path "$rawBase.gscc")) { $compileOut | ForEach-Object { Say "    $_" }; Fail "acts gscc (exit $compileCode)" }
}
Lap 'compile' $t

# 3 strip
$t = Get-Date
Say "3/5 strip ..."
$out = Join-Path $payloads "gunfight_menu.$Tag.gscc"
try { $stripOut = & "$PSScriptRoot\strip-strhdr.ps1" -In "$rawBase.gscc" -Out $out *>&1 | ForEach-Object { "$_" } }
catch { Fail ("strip-strhdr: " + $_.Exception.Message) }
if (-not (Test-Path $out)) { $stripOut | ForEach-Object { Say "    $_" }; Fail "strip-strhdr wrote nothing" }
Remove-Item "$rawBase.gscc" -ErrorAction SilentlyContinue
Lap 'strip' $t

# 4 verify - read the string table the way strip-strhdr does (count @0x18, table @0x30, 8 + 4*nref per entry)
$t = Get-Date
Say "4/5 verify ..."
function Read-Strings([string]$path) {
    $b = [System.IO.File]::ReadAllBytes($path)
    $latin1 = [System.Text.Encoding]::GetEncoding(28591)       # 1 byte = 1 char, so byte tests stay exact
    $count = [System.BitConverter]::ToUInt16($b, 0x18)
    $pos = [int][System.BitConverter]::ToUInt32($b, 0x30)
    $r = [pscustomobject]@{ Size = $b.Length; Count = [int]$count; Headers = 0; Control = @(); Longest = 0; Strings = New-Object System.Collections.Generic.List[string] }
    for ($i = 0; $i -lt $count; $i++) {
        $off = [int][System.BitConverter]::ToUInt32($b, $pos)
        $nref = [int]$b[$pos + 4]
        $pos += 8 + 4 * $nref
        if ($b[$off] -eq 0x8B) { $r.Headers++ }
        $end = [Array]::IndexOf($b, [byte]0, $off)
        $s = $latin1.GetString($b, $off, $end - $off)
        if ($s -match '[\x01-\x1F]') { $r.Control += ($s -replace '[\x00-\x1F]', '?') }
        if ($s.Length -gt $r.Longest) { $r.Longest = $s.Length }
        $r.Strings.Add($s)
    }
    return $r
}
$v = Read-Strings $out
$problems = @()
if ($v.Headers -ne 0) { $problems += "$($v.Headers) strings still carry the 0x8B header (strip failed)" }
if ($v.Control.Count -ne 0) { $problems += "$($v.Control.Count) strings contain a byte < 0x20 - one newline sent to a client closes the match: " + (($v.Control | Select-Object -First 3) -join ' | ') }
if ($v.Longest -ge 1024) { $problems += "a string literal is $($v.Longest) chars (the engine's limit is 1024)" }
# The panel's channel markers (GFLOG / GFSTATE fields the app parses) + whatever the caller asked for.
$markers = @('LOG|', '|mid=', '|mo=', '|ents=', '|lg=', 'Client Menu') + $Expect
$blob = $v.Strings -join "`n"
$missing = @($markers | Where-Object { $blob.IndexOf($_, [StringComparison]::Ordinal) -lt 0 })
if ($missing.Count -ne 0) { $problems += "missing expected strings: " + ($missing -join ', ') }
if ($problems.Count -ne 0) { $problems | ForEach-Object { Say "    $_" 'Red' }; Fail "verify - the side build is left at $out for a look" }
$sha = Sha8 $out
$cmp = ''
if ($live -and (Test-Path $live)) {
    $l = Read-Strings $live
    $cmp = "  vs live {0}: {1:+#,0;-#,0;0} B, {2:+#,0;-#,0;0} strings" -f (Sha8 $live), ($v.Size - $l.Size), ($v.Count - $l.Count)
}
Say ("  {0:N0} B, {1:N0} strings, 0 headers, 0 control bytes, longest {2}, {3} expected strings present, sha {4}{5}" -f $v.Size, $v.Count, $v.Longest, $markers.Count, $sha, $cmp)
Lap 'verify' $t

# 5 promote
if ($NoPromote) {
    Say ("NOT promoted (-NoPromote): side build {0} ({1})  - {2:N0} s total" -f $out, $sha, ((Get-Date) - $t0).TotalSeconds) 'Yellow'
}
else {
    $t = Get-Date
    Say "5/5 promote ..."
    $note = ''
    if (Test-Path $live) {
        $old = Sha8 $live
        if ($old -eq $sha) { $note = "  (identical to the live slot - nothing changed)" }
        else {
            $bak = Join-Path $payloads "gunfight_menu.safe-$old.bak.gscc"
            if (-not (Test-Path $bak)) { Copy-Item $live $bak }
            $note = "  (backup: gunfight_menu.safe-$old.bak.gscc)"
        }
    }
    Copy-Item $out $live -Force
    if ((Sha8 $live) -ne $sha) { Fail "the live slot does not read back as $sha after the copy" }
    if (Test-Path $distPayloads) {
        try { Copy-Item $live $distPayloads -Force -ErrorAction Stop; $note += "  + dist payload" }
        catch { Say ("  dist payload NOT updated: " + $_.Exception.Message) 'Yellow' }
    }
    Lap 'promote' $t
    Say ("LIVE {0} ({1:N0} B, {2:N0} strings){3}  - {4:N0} s total. Inject after a game relaunch." -f $sha, $v.Size, $v.Count, $note, ((Get-Date) - $t0).TotalSeconds) 'Cyan'
}

# optional: the panel's offline checks (they read the .gsc, so a verb or catalog change shows up here)
if ($Tests) {
    $t = Get-Date
    Say "tests: GfPanel.Tests ..."
    $env:GFPANEL_DATADIR = Join-Path $work 'panel-data'
    $testOut = & dotnet run --project (Join-Path $repo 'tools\gf-panel\GfPanel.Tests') *>&1 | ForEach-Object { "$_" }
    $testCode = $LASTEXITCODE
    $testOut | Where-Object { $_ -match 'passed|FAIL|fail ' } | Select-Object -Last 12 | ForEach-Object { Say "    $_" }
    if ($testCode -ne 0) { Say ("  tests FAILED (exit {0}) - the build above stands; fix the panel side" -f $testCode) 'Red'; exit 2 }
    Lap 'tests' $t
}
exit 0
