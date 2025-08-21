# This script initializes the Git repo, sets up directory structure and registers scheduled tracking tasks.

# Elevation check: Relaunch as admin if not already
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Script requires admin to register tasks to the scheduler. Relaunching with sudo..."
    sudo powershell -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path
    exit
}

# Ensure the script is using default windows PowerShell
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw "Script is intended to run in Windows PowerShell (not PowerShell Core). Please use the default PowerShell."
}

# Link PowerShell 7 (pwsh.exe) $PROFILE.CurrentUserAllHosts profile to PowerShell 5 profile
if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
    $PwshProfile = & pwsh -NoProfile -Command '$PROFILE.CurrentUserAllHosts'
    New-Item -Force -ItemType SymbolicLink -Path $PROFILE.CurrentUserAllHosts -Target $PwshProfile | Out-Null
    Write-Host "Linked PowerShell 7 profile to Windows PowerShell profile."
}

# Ensure Git is installed
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    Write-Host "Git not found. Installing via winget..."
    winget install --id=Git.Git --silent --accept-package-agreements --accept-source-agreements
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        throw "Git installation failed or not found in PATH. Please install manually."
    }
}

# Ensure config file exists, prompt 
if (-not (Test-Path ".\config.psd1")) {
    throw "Config file .\config.psd1 was not found. Create it with schema from .\config.example.psd1 and run again."
}
$Config = Import-PowerShellDataFile -Path ".\config.psd1"
$TrackingRepo = Resolve-Path $Config.TrackingRepo
$TaskName = "Windows-Tracking"

# Init tracking repo of 
if (-not (Test-Path $TrackingRepo)) {
    Write-Host "$TrackingRepo not found. Creating automatically..."
    New-Item $TrackingRepo -ItemType Directory
}
# Init Git repo if not already
if (-not (Test-Path (Join-Path $TrackingRepo ".git"))) {
    git init $TrackingRepo
}

# Ensure SQLite is installed
if (-not (Get-Command sqlite3.exe -ErrorAction SilentlyContinue)) {
    Write-Host "SQLite not found. Installing via winget..."
    winget install --id=SQLite.sqlite --silent --accept-package-agreements --accept-source-agreements
    if (-not (Get-Command sqlite3.exe -ErrorAction SilentlyContinue)) {
        throw "SQLite installation failed or not found in PATH. Please install manually."
    }
}

# We are using vbs script to launch PowerShell in hidden mode.
# as -WindowStyle Hidden actually minimizes window, not hidding it.
# See: https://github.com/PowerShell/PowerShell/issues/3028
$ScriptPath = Join-Path $PSScriptRoot "track.ps1"
$escapedScriptPath = $ScriptPath.Replace('"', '""')  # Escape quotes for VBScript
$VbsPath = Join-Path $PSScriptRoot "launch_hidden.vbs"

@"
Set objShell = CreateObject("Wscript.Shell")
objShell.Run "powershell.exe -ExecutionPolicy Bypass -File ""$escapedScriptPath"" -TrackingRepo ""$TrackingRepo""", 0, False
"@ | Set-Content -Encoding ASCII -Path $VbsPath

# Register Scheduled Task (every 4 hours, fixed window)
$Action = New-ScheduledTaskAction `
    -Execute "wscript.exe" `
    -Argument "`"$VbsPath`""

# Trigger 1: Every 4 hours starting at the next full 4-hour block
$now = Get-Date
$nextBlock = $now.Date.AddHours(4 * [math]::Ceiling($now.Hour / 4))
$Trigger1 = New-ScheduledTaskTrigger `
    -Once -At $nextBlock `
    -RepetitionInterval (New-TimeSpan -Hours 4) `
    -RepetitionDuration ([TimeSpan]::FromDays(365))

# Trigger 2: At logon
$Trigger2 = New-ScheduledTaskTrigger -AtLogOn

# Simpler principal (non-elevated, uses interactive logon)
$Principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType Interactive

# Task settings
# - Start when available: If the task is missed (for example, when keeping the computer in sleep mode), it will run as soon as I wake it up.
# - Execution time limit: 3 minutes to prevent track.ps1 from running indefinitely in case of issues.
$Settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 3)

# Register the task
Register-ScheduledTask -Action $Action `
    -Trigger @($Trigger1, $Trigger2) `
    -Principal $Principal `
    -Settings $Settings `
    -TaskName "$TaskName" `
    -Description "$TaskName info every 4 hours and at logon (non-admin)" `
    -Force

Write-Host @"

Setup complete.

Run once:
  Start-ScheduledTask -TaskName '$TaskName'

Inspect:
  Get-ScheduledTask -TaskName "$TaskName" | Get-ScheduledTaskInfo
  (Get-ScheduledTask -TaskName "$TaskName").Actions
  (Get-ScheduledTask -TaskName "$TaskName").Triggers
  (Get-ScheduledTask -TaskName "$TaskName").Principal
  (Get-ScheduledTask -TaskName "$TaskName").Settings

Disable:
  sudo powershell -Command "Disable-ScheduledTask -TaskName '$TaskName'"

Delete:
  sudo powershell -Command "Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:0"
"@
