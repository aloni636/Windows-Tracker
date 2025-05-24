# Elevation check: Relaunch as admin if not already
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Script is not running as administrator. Relaunching with sudo..."
    sudo powershell -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path
    exit
}

# This script initializes the Git repo and sets up directory structure.

$RepoDir = $PSScriptRoot
$ScriptPath = Join-Path $RepoDir "track.ps1"

# Init Git repo if not already
if (-not (Test-Path (Join-Path $RepoDir ".git"))) {
    git init $RepoDir
}

# Register Scheduled Task (every 4 hours, fixed window)
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `\"$ScriptPath`\""

$Trigger = New-ScheduledTaskTrigger `
    -Once `
    -At (Get-Date).Date.AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Hours 4) `
    -RepetitionDuration ([TimeSpan]::FromDays(365))  # Or use [TimeSpan]::MaxValue

$Principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType S4U -RunLevel Highest

Register-ScheduledTask -Action $Action -Trigger $Trigger -Principal $Principal `
    -TaskName "Track System" `
    -Description "Track system information every 4 hours" `
    -Force

# Ignition: run track.ps1 once to schedule the first 4-hour run
Write-Host "Running ignition execution of track.ps1 to schedule first 4-hour run..."
powershell.exe -ExecutionPolicy Bypass -File "$ScriptPath"

Write-Host "Setup completed at $RepoDir. Scheduled task 'Track System' (every 4 hours, fixed windows) created."
