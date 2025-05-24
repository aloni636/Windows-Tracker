# This script initializes the Git repo and sets up directory structure.

$RepoDir = $PSScriptRoot
$ScriptPath = Join-Path $RepoDir "track.ps1"

# Init Git repo if not already
if (-not (Test-Path (Join-Path $RepoDir ".git"))) {
    git init $RepoDir
}

# Register Scheduled Task (at startup only)
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `\"$ScriptPath`\""
$StartupTrigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType S4U -RunLevel Highest
Register-ScheduledTask -Action $Action -Trigger $StartupTrigger -Principal $Principal -TaskName "Track System" -Description "Track system information at startup and every 4 hours after" -Force

# Ignition: run track.ps1 once to schedule the first 4-hour run
Write-Host "Running ignition execution of track.ps1 to schedule first 4-hour run..."
powershell.exe -ExecutionPolicy Bypass -File "$ScriptPath"

Write-Host "Setup completed at $RepoDir. Scheduled task 'Track System' (at startup) created and ignition run performed."
