# Reset this laptop so Dyavon can be installed as a brand-new user would: from GitHub, with
# first-run setup and pairing. Run in an elevated PowerShell:
#
#   irm http://192.168.137.2:8000/fresh.txt | iex
#
# It stops mouse-rs and removes what would start or allow it (start-at-login entry, firewall
# rules, administrator login task). It RENAMES the settings folder %USERPROFILE%\.mouse_share
# to .mouse_share.bak, so Dyavon does not pick it up; nothing is deleted. The mouse-rs
# program folder is left where it is. It sends no keyboard or mouse input.
#
# To undo: rename .mouse_share.bak back to .mouse_share and start mouse-rs.exe again.

$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    Write-Host 'STOP: this only runs on Windows. Nothing has been changed.' -ForegroundColor Red
    return
}
$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'STOP: this shell is not elevated. Nothing has been changed.' -ForegroundColor Red
    Write-Host '  Press Win+X, choose "Terminal (Admin)", then run the same line again.'
    return
}

$server = 'http://192.168.137.2'
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$report = New-Object System.Text.StringBuilder
function Say($m) { Write-Host "  $m"; [void]$report.AppendLine($m) }

Write-Host ''
Write-Host 'Fresh start for Dyavon' -ForegroundColor Cyan
[void]$report.AppendLine("fresh start  $stamp  on $env:COMPUTERNAME")

# 1. stop mouse-rs (and any Dyavon already tried), by exact process name
foreach ($name in @('mouse-rs', 'dyavon')) {
    $p = @(Get-Process $name -ErrorAction SilentlyContinue)
    if ($p.Count -gt 0) {
        $p | Stop-Process -Force
        Start-Sleep -Seconds 2
        if (Get-Process $name -ErrorAction SilentlyContinue) {
            Say "STOP: $name is still running and would not stop. Nothing else was changed."
            return
        }
        Say "stopped $name (pid $($p.Id -join ', '))"
    }
}

# 2. start at login
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
foreach ($v in @('mouse-rs', 'mouse_share')) {
    if (Get-ItemProperty -Path $runKey -Name $v -ErrorAction SilentlyContinue) {
        Remove-ItemProperty -Path $runKey -Name $v
        Say "removed start-at-login entry '$v'"
    }
}
$lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\mouse_share.lnk'
if (Test-Path $lnk) { Remove-Item $lnk -Force; Say 'removed the old Python mouse_share Startup shortcut' }

# 3. administrator login task
schtasks.exe /Query /TN 'mouse-rs (elevated)' *> $null
if ($LASTEXITCODE -eq 0) {
    schtasks.exe /Delete /TN 'mouse-rs (elevated)' /F *> $null
    Say "removed the 'mouse-rs (elevated)' login task"
}

# 4. firewall rules (Dyavon asks for its own on first start)
foreach ($rule in @('mouse-rs', 'mouse-rs (elevated)')) {
    netsh advfirewall firewall delete rule name="$rule" *> $null
    if ($LASTEXITCODE -eq 0) { Say "removed firewall rule '$rule'" }
}

# 5. settings: renamed, not deleted
$old = Join-Path $env:USERPROFILE '.mouse_share'
$bak = Join-Path $env:USERPROFILE '.mouse_share.bak'
if (Test-Path $old) {
    if (Test-Path $bak) {
        Say "STOP: $bak already exists, so $old was left in place. Rename or remove the .bak first."
    } else {
        Rename-Item $old '.mouse_share.bak'
        if ((Test-Path $bak) -and -not (Test-Path $old)) { Say "settings kept as $bak" }
        else { Say "WARNING: could not rename $old" }
    }
}
$dy = Join-Path $env:USERPROFILE '.dyavon'
if (Test-Path $dy) { Say "NOTE: $dy exists from an earlier try; Dyavon will reuse it. Delete it for a truly fresh start." }

Write-Host ''
Write-Host 'Done. Now go to https://github.com/prashantpal8980/dyavon and install Dyavon like a new user.' -ForegroundColor Green
try {
    Invoke-WebRequest -Uri "$server`:8001/fresh-$($env:COMPUTERNAME)-$stamp.txt" -Method Put -UseBasicParsing `
        -Body $report.ToString() -ContentType 'text/plain' | Out-Null
} catch {}
