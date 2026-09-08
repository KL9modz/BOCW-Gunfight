# Offline validation for Cold War GSC before injecting.
#   .\tools\check-gsc.ps1 .\src\gunfight_tweaks.gsc
# Compiles, round-trips through the decompiler, and verifies every
# namespace::function call resolves to a real function in the game source.
# A typo'd API name compiles fine and only dies at runtime -- this catches it.
#
# ACTS (60 MB) and bocw-source-main (664 MB) are deliberately NOT in this repo.
# They sit beside it, two levels up from this file. On a fresh machine, see
# docs/notes/test-pc-setup.md before running this.
#
# -CompileOnly runs stages 1-2 (compile + round-trip) and NOTHING ELSE. Those need
# only ACTS, not the dump, which makes a bare Windows box with a 60 MB download a
# usable compile gate. It reports COMPILE OK, never PASS - stages 3-4 are what catch
# a typo'd API name, and this script will not claim a pass without them.
# Pair it with tools/check-dump.py, which runs stages 3-4 anywhere Python does.

param(
    [Parameter(Mandatory = $true)][string]$Script,
    [string]$Acts   = "$PSScriptRoot\..\..\ACTS\bin\acts.exe",
    [string]$Source = "$PSScriptRoot\..\..\bocw-source-main",
    [switch]$CompileOnly
)

# NOT 'Stop': acts writes benign warnings ("Can't read file data for cw") to stderr,
# which PowerShell 5.1 would promote to a terminating error. Gate on $LASTEXITCODE instead.
$ErrorActionPreference = 'Continue'
$src = (Resolve-Path $Script).Path
# acts resolves data\games\cw.json against the process working directory, which
# Set-Location alone does not update from inside a script scope.
# Resolve leniently -- on a fresh machine neither may exist yet, and a raw
# Resolve-Path exception is a worse diagnostic than the explicit checks below.
$Acts   = (Resolve-Path $Acts   -ErrorAction SilentlyContinue).Path
$Source = (Resolve-Path $Source -ErrorAction SilentlyContinue).Path

if (-not $Acts) {
    Write-Host "acts.exe not found. Expected it beside the repo, at" -ForegroundColor Red
    Write-Host "  <repo parent>\ACTS\bin\acts.exe" -ForegroundColor Red
    Write-Host "Copy ACTS there, or pass -Acts <path>." -ForegroundColor Yellow
    exit 1
}

# The Set-Location below is required (see the comment above) but must not leak to the
# caller. Without this restore, validating several projects in sequence with relative
# paths works for the FIRST one and then fails with "The term '.\tools\check-gsc.ps1'
# is not recognized" -- a harness artifact that reads as a broken script. finally runs
# on `exit` in PowerShell, so every exit path below is covered.
$origLocation = Get-Location
$origCwd      = [Environment]::CurrentDirectory
try {

Set-Location (Split-Path $Acts -Parent)
[Environment]::CurrentDirectory = Split-Path $Acts -Parent
$work = Join-Path $env:TEMP ("gsccheck_" + [IO.Path]::GetFileNameWithoutExtension($src))
New-Item -ItemType Directory -Force $work | Out-Null
$out = Join-Path $work ([IO.Path]::GetFileNameWithoutExtension($src))

Write-Host "[1/4] compiling..." -ForegroundColor Cyan
& $Acts gscc $src -g cw -p pc -o $out
if ($LASTEXITCODE -ne 0) { Write-Host "COMPILE FAILED" -ForegroundColor Red; exit 1 }

Write-Host "[2/4] round-tripping through decompiler..." -ForegroundColor Cyan
$rt = Join-Path $work 'rt'
Remove-Item $rt -Recurse -Force -ErrorAction SilentlyContinue
& $Acts gscd -g cw -p pc -o $rt "$out.gscc" | Out-Null
# "Can't read file data for cw" here is expected and harmless - it only means acts has no
# hash dictionary for a standalone script, so names stay hashed. Only the exit code matters.
if ($LASTEXITCODE -ne 0) { Write-Host "ROUND-TRIP FAILED (bad bytecode)" -ForegroundColor Red; exit 1 }
if (-not (Get-ChildItem $rt -Recurse -File -ErrorAction SilentlyContinue)) {
    Write-Host "ROUND-TRIP FAILED (decompiler produced nothing)" -ForegroundColor Red; exit 1
}

if ($CompileOnly) {
    Write-Host ""
    Write-Host "COMPILE OK - compiled to $out.gscc and round-tripped." -ForegroundColor Green
    Write-Host ""
    Write-Host "This is NOT a PASS. Stages 3-4 did not run, and they are the ones that" -ForegroundColor Yellow
    Write-Host "catch a typo'd API name - which compiles clean and dies at runtime." -ForegroundColor Yellow
    Write-Host "Run them with:  python3 tools/check-dump.py <script>" -ForegroundColor Yellow
    exit 0
}

Write-Host "[3/4] resolving API calls against game source..." -ForegroundColor Cyan
$text  = Get-Content $src -Raw
# strip comments so commented-out calls don't get checked
$text  = [regex]::Replace($text, '/\*[\s\S]*?\*/|//[^\r\n]*', '')
$calls = [regex]::Matches($text, '(?<![\w\\])([a-z_][a-z0-9_]*)::([a-z_][a-z0-9_]*)\s*\(') |
         ForEach-Object { [pscustomobject]@{ ns = $_.Groups[1].Value; fn = $_.Groups[2].Value } } |
         Sort-Object ns, fn -Unique

if (-not $Source -or -not (Test-Path "$Source\scripts")) {
    Write-Host ""
    Write-Host "bocw-source-main\scripts not found - CANNOT resolve API calls." -ForegroundColor Red
    Write-Host "That is the step that catches typo'd API names, which compile clean" -ForegroundColor Red
    Write-Host "and only die at runtime. Refusing to report PASS without it." -ForegroundColor Red
    Write-Host ""
    Write-Host "Fix: clone the dump beside the repo -" -ForegroundColor Yellow
    Write-Host "  git clone --depth 1 https://github.com/ate47/bocw-source.git bocw-source-main" -ForegroundColor Yellow
    Write-Host "or pass -Source <path>." -ForegroundColor Yellow
    exit 1
}

$bad = 0
foreach ($c in $calls) {
    # find the file(s) declaring this namespace, then look for the function in them
    $files = Select-String -Path "$Source\scripts\*.gsc","$Source\scripts\*\*.gsc","$Source\scripts\*\*\*.gsc" `
                           -Pattern "^#namespace\s+$($c.ns)\s*;" -List -ErrorAction SilentlyContinue
    if (-not $files) {
        Write-Host ("  MISSING NAMESPACE  {0}::{1}" -f $c.ns, $c.fn) -ForegroundColor Red; $bad++; continue
    }
    $hit = Select-String -Path $files.Path -Pattern "^function\s+(private\s+|autoexec\s+)*$($c.fn)\s*\(" -List -ErrorAction SilentlyContinue
    if ($hit) {
        Write-Host ("  ok  {0}::{1}" -f $c.ns, $c.fn) -ForegroundColor DarkGray
    } else {
        Write-Host ("  NOT FOUND  {0}::{1}  (namespace exists in {2})" -f $c.ns, $c.fn, (Split-Path $files[0].Path -Leaf)) -ForegroundColor Red
        $bad++
    }
}

Write-Host "[4/4] checking bare builtin calls exist in the dump..." -ForegroundColor Cyan
# Stage 3 only matches namespace::function calls. Bare builtins were never checked at all.
# That gap is not theoretical: hello_world.gsc called logprint(), which appears ZERO times
# in the dump because it is not a T9 builtin, and it was the first statement of the autoexec
# that runs at script link. The harness reported PASS and the game crashed 1-2s into a map
# load. A call that appears nowhere in 859 stock scripts is the signal this stage looks for.
$keywords = @('if','while','for','foreach','switch','case','return','break','continue',
              'thread','function','autoexec','private','else','do','new')
# Functions the script defines itself are not builtins and must not be flagged.
# The `function` keyword is REQUIRED here. Without it this pattern matches any call at the
# start of a line -- e.g. an indented `println( ... );` -- and silently excludes the very
# builtins this stage exists to check.
$localFns = [regex]::Matches($text, '(?m)^\s*function\s+(?:private\s+|autoexec\s+)*([a-z_][a-z0-9_]*)\s*\(') |
            ForEach-Object { $_.Groups[1].Value }
$bare = [regex]::Matches($text, '(?<![\w:.\\&])([a-z_][a-z0-9_]*)\s*\(') |
        ForEach-Object { $_.Groups[1].Value } |
        Where-Object { $keywords -notcontains $_ -and $localFns -notcontains $_ } |
        Sort-Object -Unique

foreach ($b in $bare) {
    $found = Select-String -Path "$Source\scripts\*.gsc","$Source\scripts\*\*.gsc","$Source\scripts\*\*\*.gsc" `
                           -Pattern "\b$b\s*\(" -List -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        Write-Host ("  ok  {0}()" -f $b) -ForegroundColor DarkGray
    } else {
        Write-Host ("  NOT IN DUMP  {0}()  - no stock script calls this. Not a T9 builtin?" -f $b) -ForegroundColor Red
        $bad++
    }
}

Write-Host ""
if ($bad) {
    Write-Host "$bad unresolved call(s) - these compile but fail at runtime." -ForegroundColor Red
    exit 1
}
Write-Host "PASS - compiled to $out.gscc" -ForegroundColor Green

}
finally {
    Set-Location $origLocation
    [Environment]::CurrentDirectory = $origCwd
}
