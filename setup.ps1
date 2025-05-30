# This script initializes the Git repo, sets up directory structure and registers scheduled tracking tasks.

# Elevation check: Relaunch as admin if not already
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Script requires admin to register tasks to the scheduler. Relaunching with sudo..."
    sudo powershell -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path
    exit
}


$RepoDir = $PSScriptRoot
$ScriptPath = Join-Path $RepoDir "track.ps1"

# Ensure Git is installed
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    Write-Host "Git not found. Installing via winget..."
    winget install --id=Git.Git --silent --accept-package-agreements --accept-source-agreements
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        Write-Host "Git installation failed or not found in PATH. Please install manually."
        exit 1
    }
}

# Init Git repo if not already
if (-not (Test-Path (Join-Path $RepoDir ".git"))) {
    git init $RepoDir
}

# Ensure SQLite is installed
if (-not (Get-Command sqlite3.exe -ErrorAction SilentlyContinue)) {
    Write-Host "SQLite not found. Installing via winget..."
    winget install --id=SQLite.sqlite --silent --accept-package-agreements --accept-source-agreements
    if (-not (Get-Command sqlite3.exe -ErrorAction SilentlyContinue)) {
        Write-Host "SQLite installation failed or not found in PATH. Please install manually."
        exit 1
    }
}

# Register Scheduled Task (every 4 hours, fixed window)
$Action = New-ScheduledTaskAction `
    -Execute "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
    # -WindowStyle Hidden is actually minimized window, not hidden.
    # See: https://github.com/PowerShell/PowerShell/issues/3028

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
    -TaskName "Track System" `
    -Description "Track system info every 4 hours and at logon (non-admin)" `
    -Force

Write-Host @"

Setup completed at ${RepoDir} with 'Track System' task scheduled to run every 4 hours and at logon.

To execute the task manually, run:
    Start-ScheduledTask -TaskName 'Track System'

To examine the task, run:
    Get-ScheduledTask -TaskName 'Track System' | Get-ScheduledTaskInfo

To disable the task, run:
    sudo powershell 'Disable-ScheduledTask -TaskName "Track System" -TaskPath "\"'
"@
