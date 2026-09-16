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
    # Every builtin the ENGINE exports, read off the live exe (4,481 rows). Optional:
    # without it stage 4 falls back to "called somewhere in the dump", which is weaker.
    [string]$Table  = "$PSScriptRoot\..\..\reference\funcs_cw.csv",
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
# String literals are not code. "Unlock all (best-effort)" used to report all() as NOT IN
# DUMP, and the script-function rule below inherits the same false positives ("spawn
# guard (teleport)" -> guard()), so blank every literal before scanning for calls.
$code = [regex]::Replace($text, '"(?:[^"\\]|\\.)*"', '""')
$bare = [regex]::Matches($code, '(?<![\w:.\\&])([a-z_][a-z0-9_]*)\s*\(') |
        ForEach-Object { $_.Groups[1].Value } |
        Where-Object { $keywords -notcontains $_ -and $localFns -notcontains $_ } |
        Sort-Object -Unique

# The engine table, when present. A name in it is a real builtin no matter what else
# the dump says; a name NOT in it that the dump DEFINES as a script function is the
# prop.gsc trap below.
$engine = $null
$tablePath = (Resolve-Path $Table -ErrorAction SilentlyContinue).Path
if ($tablePath) {
    $engine = @{}
    $devonly = @{}
    Import-Csv $tablePath | ForEach-Object {
        if ($_.func) {
            $fn = $_.func.Trim().ToLower()
            $engine[$fn] = 1
            # type column: 0 = normal, 1 = DEV-ONLY (retail refuses it outside /# #/ with
            # "Dev only calls must be wrapped in a devblock" - crashed the game 2026-09-15,
            # function_9e72a96 in the vehicle census). 110 such names in the table.
            if ($_.type -and $_.type.Trim() -eq '1') { $devonly[$fn] = 1 }
        }
    }
    Write-Host ("  engine table: {0} builtins ({1} dev-only)" -f $engine.Count, $devonly.Count) -ForegroundColor DarkGray
} else {
    Write-Host "  (no engine table at $Table - falling back to called-in-dump only)" -ForegroundColor DarkYellow
}

$dumpFiles = @("$Source\scripts\*.gsc","$Source\scripts\*\*.gsc","$Source\scripts\*\*\*.gsc")

foreach ($b in $bare) {
    # ⚠ THE PROP.GSC TRAP (2026-09-15, two game crashes): "called somewhere in the dump" is
    # NOT "is a builtin". prop.gsc defines getmapname() and tablelookupbyrow() as LOCAL
    # script functions and calls them bare; a probe that copied those calls compiled,
    # passed this stage, and crashed the game at runtime. A bare name the dump DEFINES
    # with `function` is a script function, reachable only through its namespace - unless
    # the engine table also lists it (a real builtin that some class happens to shadow).
    $defined = $null
    if (-not ($engine -and $engine.ContainsKey($b))) {
        $defined = Select-String -Path $dumpFiles -Pattern "^\s*function\s+(private\s+|autoexec\s+)*$b\s*\(" -List -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($defined) {
        $where = "{0}:{1}" -f (Split-Path $defined.Path -Leaf), $defined.LineNumber
        Write-Host ("  SCRIPT FUNCTION  {0}()  - defined in {1}, not a builtin. Call it through its namespace or copy it." -f $b, $where) -ForegroundColor Red
        $bad++
        continue
    }
    if ($engine -and $engine.ContainsKey($b)) {
        if ($devonly.ContainsKey($b)) {
            Write-Host ("  DEV-ONLY  {0}()  - engine table type=1; retail refuses it outside a /# #/ devblock (crashes with 'Dev only calls must be wrapped in a devblock')." -f $b) -ForegroundColor Red
            $bad++
        } else {
            Write-Host ("  ok  {0}()" -f $b) -ForegroundColor DarkGray
        }
        continue
    }
    $found = Select-String -Path $dumpFiles -Pattern "\b$b\s*\(" -List -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        # Not in the engine table but stock calls it and nothing defines it: a VM
        # intrinsic (isdefined, wait, waittill, endon, notify, vectorscale ...) or a
        # builtin the table missed. Say which case this is rather than a bare ok.
        if ($engine) {
            Write-Host ("  ok  {0}()  - not in the engine table, but stock calls it undefined (intrinsic)" -f $b) -ForegroundColor DarkGray
        } else {
            Write-Host ("  ok  {0}()" -f $b) -ForegroundColor DarkGray
        }
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
