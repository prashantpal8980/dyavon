# One-time switch of this laptop from mouse-rs to Dyavon. Run once, in an elevated PowerShell:
#
#   irm http://192.168.137.2:8000/rename.txt | iex
#
# What it does, in order. Every step checks its result, and anything that fails stops the
# script with the old mouse-rs still installed and able to start:
#   0. Runs only on Windows, from an elevated shell.
#   1. Downloads dyavon.exe into %USERPROFILE%\dyavon and checks its size and hash.
#   2. Notes how mouse-rs was running, then stops it.
#   3. Moves the verified exe into place.
#   4. Replaces the mouse-rs firewall rules with Dyavon ones.
#   5. If "start at login as administrator" was on, moves that task to Dyavon as well.
#   6. Starts Dyavon the way mouse-rs was running. On first start Dyavon copies the
#      settings and pairings from .mouse_share to .dyavon and swaps the start-at-login
#      entry. If it does not stay up, mouse-rs is started again instead.
#   7. Checks that the settings and the start-at-login entry moved.
#   8. Uploads a report to the Kali machine.
#
# It leaves %USERPROFILE%\mouse-rs and %USERPROFILE%\.mouse_share exactly as they were, so
# going back is just starting the old exe. It sends no keyboard or mouse input.

$ErrorActionPreference = 'Stop'

# Before anything reads a Windows-only path.
if ($env:OS -ne 'Windows_NT') {
    Write-Host 'STOP: this only runs on Windows. Nothing has been changed.' -ForegroundColor Red
    return
}

$server  = 'http://192.168.137.2'
$oldDir  = Join-Path $env:USERPROFILE 'mouse-rs'
$oldExe  = Join-Path $oldDir 'mouse-rs.exe'
$dir     = Join-Path $env:USERPROFILE 'dyavon'
$exe     = Join-Path $dir 'dyavon.exe'
$new     = Join-Path $dir 'dyavon.exe.new'
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$report  = New-Object System.Text.StringBuilder
$runKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

function Say($m) {
    Write-Host "  $m"
    [void]$report.AppendLine($m)
}

function Upload-Report($ok) {
    $name = "rename-$($env:COMPUTERNAME)-$stamp-$(if ($ok) {'ok'} else {'FAILED'}).txt"
    try {
        Invoke-WebRequest -Uri "$server`:8001/$name" -Method Put -UseBasicParsing `
            -Body $report.ToString() -ContentType 'text/plain' | Out-Null
        Write-Host "  report uploaded as $name"
    } catch {
        Write-Host "  could not upload the report ($($_.Exception.Message)); it is printed above."
    }
}

function Fail($m) {
    Say "STOP: $m"
    Upload-Report $false
    throw $m
}

function Hash-Of($path) { (Get-FileHash $path -Algorithm SHA256).Hash }

function Get-ArgsOf($commandLine) {
    $cl = $commandLine.Trim()
    if ($cl.StartsWith('"')) {
        $end = $cl.IndexOf('"', 1)
        if ($end -lt 0) { return '' }
        return $cl.Substring($end + 1).Trim()
    }
    $space = $cl.IndexOf(' ')
    if ($space -lt 0) { return '' }
    return $cl.Substring($space + 1).Trim()
}

function Start-Exe($path, $argString) {
    $params = @{ FilePath = $path; WorkingDirectory = (Split-Path $path); PassThru = $true }
    if ($argString) { $params.ArgumentList = $argString }
    Start-Process @params
}

function Stays-Up($name, $path) {
    Start-Sleep -Seconds 5
    $p = Get-Process $name -ErrorAction SilentlyContinue |
        Where-Object { try { $_.Path -eq $path } catch { $false } }
    return ($p | Select-Object -First 1)
}

function Run-Value($name) {
    try { return (Get-ItemProperty -Path $runKey -Name $name -ErrorAction Stop).$name } catch { return $null }
}

Write-Host ''
Write-Host 'mouse-rs -> Dyavon' -ForegroundColor Cyan
[void]$report.AppendLine("mouse-rs -> Dyavon  $stamp  on $env:COMPUTERNAME")

# --- 0. Windows only, elevated, and not done already ----------------------------------
$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'STOP: this shell is not elevated. Nothing has been changed.' -ForegroundColor Red
    Write-Host '  Press Win+X, choose "Terminal (Admin)", then run the same line again.'
    return
}
Say 'shell is elevated: yes'
if (Test-Path $exe) {
    Write-Host "STOP: Dyavon is already installed at $exe. Nothing has been changed." -ForegroundColor Yellow
    Write-Host '  For a newer build, use the usual update line (u.txt) instead.'
    return
}
$hasOld = Test-Path $oldExe
Say "old mouse-rs.exe at ${oldExe}: $(if ($hasOld) {'yes'} else {'no'})"

# --- 1. download and check ------------------------------------------------------------
$sums = (Invoke-WebRequest -Uri "$server`:8000/CHECKSUM.txt" -UseBasicParsing).Content
if ($sums -is [byte[]]) { $sums = [Text.Encoding]::ASCII.GetString($sums) }
$wantSize = [int64]([regex]::Match($sums, 'dyavon\.exe\s+(\d+)\s+bytes').Groups[1].Value)
$wantHash = [regex]::Match($sums, 'SHA256\s+([A-Fa-f0-9]{64})').Groups[1].Value.ToUpper()
if ($wantSize -le 0 -or -not $wantHash) { Fail 'the server did not say which dyavon.exe to expect' }
Say "expected: $wantSize bytes, SHA256 $wantHash"

New-Item -ItemType Directory -Force -Path $dir | Out-Null
Invoke-WebRequest -Uri "$server`:8000/dyavon.exe" -OutFile $new -UseBasicParsing
$gotSize = (Get-Item $new).Length
$gotHash = Hash-Of $new
if ($gotSize -ne $wantSize -or $gotHash -ne $wantHash) {
    Remove-Item $new -Force -ErrorAction SilentlyContinue
    Fail "the download does not match (size $gotSize, SHA256 $gotHash). mouse-rs was not touched."
}
Unblock-File $new
Say 'download checked: size and hash match'

# --- 2. note how mouse-rs runs, then stop it ------------------------------------------
$running = @(Get-CimInstance Win32_Process -Filter "Name = 'mouse-rs.exe'" -ErrorAction SilentlyContinue)
$argString = ''
if ($running.Count -gt 0) {
    $argString = Get-ArgsOf $running[0].CommandLine
    Say "mouse-rs was running (pid $($running.ProcessId -join ', ')), arguments: '$argString'"
    $running | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
} else {
    Say 'mouse-rs was not running; Dyavon will be started anyway'
}
if (Get-Process mouse-rs -ErrorAction SilentlyContinue) {
    Fail 'mouse-rs is still running and would not stop. Nothing else was changed.'
}
Say 'mouse-rs is stopped'

# From here on, a failure must put mouse-rs back.
function Put-Back($why) {
    if ($hasOld) {
        Start-Exe $oldExe $argString | Out-Null
        Say 'started mouse-rs again, so this laptop is as it was'
    }
    Fail $why
}

# --- 3. exe into place ----------------------------------------------------------------
Move-Item -Force $new $exe
if ((Hash-Of $exe) -ne $wantHash) { Put-Back 'the exe in place does not match the download' }
Say "installed: $exe"

# --- 4. firewall ----------------------------------------------------------------------
foreach ($rule in @('mouse-rs', 'mouse-rs (elevated)')) {
    $out = netsh advfirewall firewall delete rule name="$rule" 2>&1
    if ($LASTEXITCODE -eq 0) { Say "removed firewall rule '$rule'" }
}
& $exe firewall-allow
if ($LASTEXITCODE -ne 0) { Say "WARNING: could not add the Dyavon firewall rule (exit $LASTEXITCODE). Use Allow in the app." }
else { Say 'firewall rule for Dyavon added' }

# --- 5. start at login as administrator -----------------------------------------------
$oldTask = 'mouse-rs (elevated)'
schtasks.exe /Query /TN "$oldTask" *> $null
if ($LASTEXITCODE -eq 0) {
    Say "'$oldTask' task found; moving it to Dyavon"
    schtasks.exe /Delete /TN "$oldTask" /F *> $null
    & $exe autostart-elevated-on
    if ($LASTEXITCODE -ne 0) { Say "WARNING: could not create the Dyavon administrator task (exit $LASTEXITCODE). Turn it on again in the app." }
    else { Say 'Dyavon administrator task created' }
    $oldPf = Join-Path $env:ProgramFiles 'mouse-rs'
    if (Test-Path $oldPf) {
        $other = @(Get-ChildItem $oldPf -Force | Where-Object { $_.Name -notlike 'mouse-rs.exe*' })
        if ($other.Count -eq 0) { Remove-Item $oldPf -Recurse -Force; Say "removed $oldPf" }
        else { Say "left $oldPf in place: it holds files other than mouse-rs.exe" }
    }
} else {
    Say 'no administrator login task to move'
}

# --- 6. start Dyavon ------------------------------------------------------------------
Start-Exe $exe $argString | Out-Null
$up = Stays-Up 'dyavon' $exe
if (-not $up) { Put-Back 'Dyavon did not stay running' }
Say "Dyavon is running (pid $($up.Id))"
Start-Sleep -Seconds 3

# --- 7. post-conditions ---------------------------------------------------------------
$newCfg = Join-Path $env:USERPROFILE '.dyavon\config.json'
$oldCfg = Join-Path $env:USERPROFILE '.mouse_share\config.json'
if (Test-Path $newCfg) { Say "settings in place: $newCfg" }
elseif (Test-Path $oldCfg) { Say "WARNING: $newCfg is missing although $oldCfg exists. Send the report." }
else { Say 'no earlier settings on this laptop; Dyavon starts fresh' }

$oldRun = Run-Value 'mouse-rs'
$newRun = Run-Value 'dyavon'
if ($oldRun) { Say "WARNING: the old start-at-login entry is still there: $oldRun" }
if ($newRun) { Say "start at login: $newRun" } else { Say 'start at login: off' }

Say "kept as they were: $oldDir and $(Join-Path $env:USERPROFILE '.mouse_share'). Delete them after a few days of use."
Write-Host ''
Write-Host 'Done: this laptop now runs Dyavon.' -ForegroundColor Green
Upload-Report $true
