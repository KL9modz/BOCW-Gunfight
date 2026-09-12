# Keep cwpatch (F4 lobbylaunchgame / F6 fast_restart / F7 full_restart) in the game's
# discord_game_sdk.dll slot. Battle.net writes the stock 3,891,512-byte SDK back over it
# on repairs AND on routine updates (observed 2026-09-08 twice, 2026-09-11 once), which
# silently turns the hotkeys off until someone notices.
#
#   .\tools\ensure-cwpatch.ps1              check once; restore if the stock SDK is back
#   .\tools\ensure-cwpatch.ps1 -Watch       stay resident; restore within seconds of any overwrite
#   .\tools\ensure-cwpatch.ps1 -Install     register -Watch as a hidden task that starts at logon
#   .\tools\ensure-cwpatch.ps1 -Uninstall   remove that task
#
# The DLL is read once, at game start, so a restore only takes effect on the NEXT launch:
# if the game is running with the stock SDK loaded, this waits for it to exit and restores
# then. It never copies a file whose SHA-256 does not match the recorded cwpatch hash, so
# a damaged backup can not be spread into the game folder.
#
# ⚠ An update can also change BlackOpsColdWar.exe, which is encrypted at rest, so nothing
# here can tell whether cwpatch's offsets still fit the new build. Correct file + dead
# hotkeys = suspect the game binary (tools/README.md).

param(
    [switch]$Watch,
    [switch]$Install,
    [switch]$Uninstall,
    [string]$Game   = 'D:\Battle.net\Call of Duty Black Ops Cold War',
    [string]$Backup = 'C:\bocw\vendor-backup\discord_game_sdk.CWPATCH-13824.dll',
    [string]$Log    = 'C:\bocw\ensure-cwpatch.log'
)
$ErrorActionPreference = 'Stop'

# docs/notes/unlock-dlls.md, computed in full 2026-09-08. Not the truncated ...84f1.
$CwpatchSha256 = 'f72249204ff2cc03620a66e2bda8eb8308023e3a16754f5bfada611e646e84d1'
$CwpatchSize   = 13824
$Slot          = Join-Path $Game 'discord_game_sdk.dll'
$TaskName      = 'BOCW ensure-cwpatch'

function Write-Log([string]$msg) {
    $line = "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg
    Write-Host $line
    try { Add-Content -Path $Log -Value $line } catch {}
}

function Get-Sha([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    (Get-FileHash -Algorithm SHA256 -Path $path).Hash.ToLower()
}

function Test-GameRunning {
    $null -ne (Get-Process -Name 'BlackOpsColdWar' -ErrorAction SilentlyContinue)
}

# Refuse to run at all with an unverified backup - that file is the whole safety net.
function Assert-Backup {
    $sha = Get-Sha $Backup
    if ($sha -ne $CwpatchSha256) {
        Write-Log "BACKUP FAILS VERIFICATION: $Backup sha256=$sha (want $CwpatchSha256). Refusing."
        exit 1
    }
}

# Returns 'ok' (slot already cwpatch), 'restored', 'deferred' (game running), or 'failed'.
function Restore-IfNeeded {
    $sha = Get-Sha $Slot
    if ($sha -eq $CwpatchSha256) { return 'ok' }

    $what = if ($null -eq $sha) { 'MISSING' } else { "sha256=$sha size=$((Get-Item $Slot).Length)" }
    Write-Log "slot is not cwpatch ($what)"

    if (Test-GameRunning) {
        Write-Log "game is running with the wrong DLL loaded - restore deferred until it exits"
        return 'deferred'
    }

    # Battle.net may still hold the file while it finishes writing; back off and retry.
    for ($try = 1; $try -le 10; $try++) {
        try {
            Copy-Item -Path $Backup -Destination $Slot -Force
            if ((Get-Sha $Slot) -eq $CwpatchSha256) {
                Write-Log "RESTORED cwpatch ($CwpatchSize bytes) into $Slot"
                return 'restored'
            }
            Write-Log "copy landed but hash mismatch; retrying ($try/10)"
        } catch {
            Write-Log "copy failed ($try/10): $($_.Exception.Message)"
        }
        Start-Sleep -Seconds 2
    }
    Write-Log "FAILED to restore after 10 attempts"
    return 'failed'
}

if ($Uninstall) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Log "task '$TaskName' removed"
    } else {
        Write-Log "task '$TaskName' was not registered"
    }
    exit 0
}

Assert-Backup

if ($Install) {
    $self   = (Resolve-Path $PSCommandPath).Path
    $pwsh   = (Get-Process -Id $PID).Path
    $action = New-ScheduledTaskAction -Execute $pwsh `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$self`" -Watch -Game `"$Game`" -Backup `"$Backup`" -Log `"$Log`""
    $trigger  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName
    Write-Log "task '$TaskName' registered (at logon, hidden, -Watch) and started"
    exit 0
}

if (-not $Watch) {
    $r = Restore-IfNeeded
    Write-Log "check: $r"
    if ($r -eq 'ok') { Write-Log "cwpatch in place; F4/F6/F7 will be live on the next launch" }
    exit $(if ($r -in 'ok','restored') { 0 } else { 2 })
}

# ── -Watch: resident guard ──────────────────────────────────────────────────────
Write-Log "watching $Slot"
$null = Restore-IfNeeded

$fsw = New-Object System.IO.FileSystemWatcher $Game, 'discord_game_sdk.dll'
$fsw.NotifyFilter = [System.IO.NotifyFilters]'LastWrite, Size, FileName, CreationTime'
$fsw.EnableRaisingEvents = $true
$pending = $false
foreach ($ev in 'Changed', 'Created', 'Renamed', 'Deleted') {
    Register-ObjectEvent -InputObject $fsw -EventName $ev -SourceIdentifier "cwpatch-$ev" -Action { $global:pending = $true } | Out-Null
}

$deferred = $false
$lastPoll = Get-Date
while ($true) {
    Start-Sleep -Seconds 2

    # A write burst from Battle.net fires several events; let it settle, then check once.
    if ($global:pending) {
        $global:pending = $false
        Start-Sleep -Seconds 3
        $r = Restore-IfNeeded
        if ($r -eq 'deferred') { $deferred = $true }
        continue
    }

    # Waiting for the game to exit after a deferred restore.
    if ($deferred -and -not (Test-GameRunning)) {
        Write-Log "game exited; restoring now"
        $r = Restore-IfNeeded
        if ($r -ne 'deferred') { $deferred = $false }
    }

    # Belt and braces: a slow poll in case an overwrite slipped past the watcher.
    if (((Get-Date) - $lastPoll).TotalSeconds -ge 60) {
        $lastPoll = Get-Date
        $r = Restore-IfNeeded
        if ($r -eq 'deferred') { $deferred = $true }
    }
}
