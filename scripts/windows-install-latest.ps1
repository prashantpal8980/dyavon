# Install (or update to) the latest Dyavon release from GitHub on this Windows computer, and
# retire the old mouse-rs. Run in an elevated PowerShell (Win+X, "Terminal (Admin)"):
#
#   irm https://raw.githubusercontent.com/prashantpal8980/dyavon/wip/iced-ui-input-fixes/scripts/windows-install-latest.ps1 | iex
#
# What it does. Every step checks its result; a failed download changes nothing:
#   1. Downloads dyavon.exe and SHA256SUMS from the latest GitHub release and checks the hash.
#   2. Stops mouse-rs and any running Dyavon.
#   3. Puts dyavon.exe in %LOCALAPPDATA%\Programs\Dyavon (where Dyavon's own installer puts it).
#   4. Desktop and Start-menu shortcuts, and an entry in Settings > Apps.
#   5. Firewall: removes the mouse-rs rules, adds the Dyavon rule.
#   6. Start at login: Dyavon on, mouse-rs off. If mouse-rs had the "as administrator"
#      login task, Dyavon gets one instead.
#   7. Starts Dyavon. On its first start it copies the settings and pairings from
#      .mouse_share to .dyavon, so it reconnects to the computers mouse-rs was paired with.
#
# It leaves the old mouse-rs program and %USERPROFILE%\.mouse_share as they were, so going
# back is just starting the old exe. It sends no keyboard or mouse input.

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

$release = 'https://github.com/prashantpal8980/dyavon/releases/latest/download'
$dir     = Join-Path $env:LOCALAPPDATA 'Programs\Dyavon'
$exe     = Join-Path $dir 'dyavon.exe'
$new     = Join-Path $dir 'dyavon.exe.new'
$runKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$appsKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Dyavon'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Say($m) { Write-Host "  $m" }
function Native([scriptblock]$cmd) {
    # Windows PowerShell 5.1 turns a program's error output into a terminating error when
    # $ErrorActionPreference is Stop, so an ordinary "not found" from schtasks or netsh would
    # end the script. Run such programs with Continue and read $LASTEXITCODE instead.
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & $cmd *> $null } finally { $ErrorActionPreference = $prev }
    return $LASTEXITCODE
}
function Run-Helper($argument) {
    # dyavon.exe is a windowed program: PowerShell would not wait for it without -Wait.
    $p = Start-Process -FilePath $exe -ArgumentList $argument -Wait -PassThru -WindowStyle Hidden
    return $p.ExitCode
}

Write-Host ''
Write-Host 'Dyavon: install the latest release' -ForegroundColor Cyan

# --- 1. download and check ------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$sums = (Invoke-WebRequest -Uri "$release/SHA256SUMS" -UseBasicParsing).Content
if ($sums -is [byte[]]) { $sums = [Text.Encoding]::ASCII.GetString($sums) }
$want = [regex]::Match($sums, '(?m)^([A-Fa-f0-9]{64})\s+\*?dyavon\.exe\s*$').Groups[1].Value.ToUpper()
if (-not $want) { Write-Host 'STOP: the release has no checksum for dyavon.exe. Nothing has been changed.' -ForegroundColor Red; return }
Invoke-WebRequest -Uri "$release/dyavon.exe" -OutFile $new -UseBasicParsing
$got = (Get-FileHash $new -Algorithm SHA256).Hash
if ($got -ne $want) {
    Remove-Item $new -Force -ErrorAction SilentlyContinue
    Write-Host "STOP: the download does not match its checksum ($got). Nothing has been changed." -ForegroundColor Red
    return
}
Unblock-File $new
Say 'downloaded the latest dyavon.exe; checksum matches'

# --- 2. stop mouse-rs and Dyavon ------------------------------------------------------
foreach ($name in @('mouse-rs', 'dyavon')) {
    $p = @(Get-Process $name -ErrorAction SilentlyContinue)
    if ($p.Count -gt 0) {
        $p | Stop-Process -Force
        Start-Sleep -Seconds 2
        if (Get-Process $name -ErrorAction SilentlyContinue) {
            Remove-Item $new -Force -ErrorAction SilentlyContinue
            Write-Host "STOP: $name would not stop. Nothing else was changed." -ForegroundColor Red
            return
        }
        Say "stopped $name"
    }
}

# --- 3. program into place ------------------------------------------------------------
Move-Item -Force $new $exe
if ((Get-FileHash $exe -Algorithm SHA256).Hash -ne $want) { throw 'the program in place does not match the download' }
$version = (Get-Item $exe).VersionInfo.ProductVersion
Say "installed: $exe (version $version)"

# --- 4. shortcuts and Settings > Apps ------------------------------------------------
# The icon file is written by Dyavon itself on start, in the colour of its theme.
$ico = Join-Path $dir 'dyavon.ico'
function Lnk($path) {
    $l = (New-Object -ComObject WScript.Shell).CreateShortcut($path)
    $l.TargetPath = $exe; $l.WorkingDirectory = $dir; $l.IconLocation = "$ico,0"
    $l.Description = 'One mouse and keyboard for all your computers'; $l.Save()
}
Lnk (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Dyavon.lnk')
Lnk (Join-Path ([Environment]::GetFolderPath('Programs')) 'Dyavon.lnk')
New-Item -Path $appsKey -Force | Out-Null
Set-ItemProperty $appsKey DisplayName 'Dyavon'
Set-ItemProperty $appsKey DisplayVersion "$version"
Set-ItemProperty $appsKey Publisher 'Dyavon contributors'
Set-ItemProperty $appsKey DisplayIcon "$ico,0"
Set-ItemProperty $appsKey InstallLocation $dir
Set-ItemProperty $appsKey UninstallString ('"' + $exe + '" uninstall')
Set-ItemProperty $appsKey URLInfoAbout 'https://github.com/prashantpal8980/dyavon'
New-ItemProperty $appsKey NoModify -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty $appsKey NoRepair -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty $appsKey EstimatedSize -Value ([int]((Get-Item $exe).Length / 1024)) -PropertyType DWord -Force | Out-Null
Say 'desktop and Start-menu shortcuts made; Dyavon is listed in Settings > Apps'

# --- 5. firewall ----------------------------------------------------------------------
foreach ($rule in @('mouse-rs', 'mouse-rs (elevated)')) {
    if ((Native { netsh advfirewall firewall delete rule name="$rule" }) -eq 0) { Say "removed the old firewall rule '$rule'" }
}
$rc = Run-Helper 'firewall-allow'
if ($rc -eq 0) { Say 'firewall: Dyavon is allowed' }
else { Say "WARNING: could not add the Dyavon firewall rule (exit $rc). Dyavon will offer Allow in its window." }

# --- 6. start at login ----------------------------------------------------------------
if (Get-ItemProperty -Path $runKey -Name 'mouse-rs' -ErrorAction SilentlyContinue) {
    Remove-ItemProperty -Path $runKey -Name 'mouse-rs'
    Say 'mouse-rs no longer starts at login'
}
Set-ItemProperty -Path $runKey -Name 'dyavon' -Value ('"' + $exe + '"')
Say 'Dyavon starts at login'
if ((Native { schtasks.exe /Query /TN 'mouse-rs (elevated)' }) -eq 0) {
    Native { schtasks.exe /Delete /TN 'mouse-rs (elevated)' /F } | Out-Null
    $rc = Run-Helper 'autostart-elevated-on'
    if ($rc -eq 0) { Say "moved the 'as administrator' login task from mouse-rs to Dyavon" }
    else { Say "WARNING: removed the mouse-rs administrator task but could not make Dyavon's (exit $rc). Turn it on in Dyavon's settings." }
}

# --- 7. start Dyavon ------------------------------------------------------------------
# Through Explorer, so Dyavon runs as you and not as administrator like this shell.
Start-Process explorer.exe -ArgumentList ('"' + $exe + '"') | Out-Null
Start-Sleep -Seconds 5
$up = Get-Process dyavon -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $up) {
    Write-Host 'WARNING: Dyavon did not stay running. Start it from the desktop shortcut; if it closes again, the old mouse-rs is still where it was.' -ForegroundColor Yellow
    return
}
Say "Dyavon is running (pid $($up.Id))"
$cfg = Join-Path $env:USERPROFILE '.dyavon\config.json'
if (Test-Path $cfg) { Say "settings and pairings in place: $cfg" }
else { Say 'no earlier settings found; Dyavon starts with first-time setup' }

Write-Host ''
Write-Host 'Done: this computer runs the latest Dyavon.' -ForegroundColor Green
Write-Host "  The old mouse-rs and $(Join-Path $env:USERPROFILE '.mouse_share') were left as they were."
