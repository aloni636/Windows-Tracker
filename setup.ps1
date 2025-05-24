# Elevation check: Relaunch as admin if not already
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Script requires admin to register tasks to the scheduler. Relaunching with sudo..."
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

# Register the task
Register-ScheduledTask -Action $Action `
    -Trigger @($Trigger1, $Trigger2) `
    -Principal $Principal `
    -TaskName "Track System" `
    -Description "Track system info every 4 hours and at logon (non-admin)" `
    -Force

Write-Host "Setup completed at ${RepoDir}. Scheduled task 'Track System' (every 4 hours, fixed windows) created."
