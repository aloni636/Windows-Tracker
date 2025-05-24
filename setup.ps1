# This script initializes the Git repo and sets up directory structure.

$RepoDir = $PSScriptRoot
$ScriptPath = Join-Path $RepoDir "track.ps1"

# Init Git repo if not already
if (-not (Test-Path (Join-Path $RepoDir ".git"))) {
    git init $RepoDir
}

# Register Scheduled Task (runs every 4 hours)
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `\"$ScriptPath`\""
$Trigger = New-ScheduledTaskTrigger -Daily -At "00:00AM" -RepetitionInterval (New-TimeSpan -Hours 4) -RepetitionDuration ([TimeSpan]::MaxValue)
$Principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType S4U -RunLevel Highest
Register-ScheduledTask -Action $Action -Trigger $Trigger -Principal $Principal -TaskName "Track System" -Description "Track bookmarks and app list every 4 hours" -Force

Write-Host "Setup completed at $RepoDir. Scheduled task 'Track System' created."
