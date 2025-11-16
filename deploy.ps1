# This script initializes the Git repo, sets up directory structure and registers scheduled tracking tasks.

function Write-Deploy {
    param([Parameter(Mandatory)][string] $Message)
    Write-Host "[deploy] $Message"
}

function Import-PowerShellDataFile-With-Validation {
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string[]] $RequiredKeys
    )

    if (-not (Test-Path $Path)) {
        $req = $RequiredKeys -join ", "
        throw "Data file not found: $Path. Required keys: $req"
    }

    $data = Import-PowerShellDataFile -Path $Path

    $missing = $RequiredKeys | Where-Object { -not $data.ContainsKey($_) }

    if ($missing.Count -gt 0) {
        $req = $RequiredKeys -join ", "
        $miss = $missing -join ", "
        throw "Missing required keys in '$Path'. Required: $req. Missing: $miss"
    }

    return $data
}

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

# Ensure Git is installed
Write-Deploy "Validating git.exe installation..."
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    Write-Host "Git not found. Installing via winget..."
    winget install --id=Git.Git --silent --accept-package-agreements --accept-source-agreements
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        throw "Git installation failed or not found in PATH. Please install manually."
    }
}

Write-Deploy "Loading config file '.\config.psd1'"
$Config = Import-PowerShellDataFile-With-Validation -Path ".\config.psd1" -RequiredKeys @(
    "TrackingRepo",
    "Deployment"
)
$TrackingRepo = Resolve-Path $Config.TrackingRepo
$Deployment = New-Item -ItemType Directory -Path $Config.Deployment -Force
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
Write-Deploy "Validating sqlite3.exe installation..."
if (-not (Get-Command sqlite3.exe -ErrorAction SilentlyContinue)) {
    Write-Host "SQLite not found. Installing via winget..."
    winget install --id=SQLite.sqlite --silent --accept-package-agreements --accept-source-agreements
    if (-not (Get-Command sqlite3.exe -ErrorAction SilentlyContinue)) {
        throw "SQLite installation failed or not found in PATH. Please install manually."
    }
}

# Stop task before touching deployment
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
}
# cleanup deployment and copy track.ps1 to deployment
Write-Deploy "Cleaning up '${Deployment}'"
Get-ChildItem $Deployment -Recurse -Force | Remove-Item -Recurse -Force
Copy-Item (Join-Path $PSScriptRoot "track.ps1") -Destination $Deployment -Force

# Point $ScriptPath to deployment version
$ScriptPath = Join-Path $Deployment "track.ps1"
$escapedScriptPath = $ScriptPath.Replace('"', '""')
$VbsPath = Join-Path $Deployment "launch_hidden.vbs"

# We are using vbs script to launch PowerShell in hidden mode.
# as -WindowStyle Hidden actually minimizes window, not hidding it.
# See: https://github.com/PowerShell/PowerShell/issues/3028
Write-Deploy "Creating VBS hidden PS1 launcher script..."
@"
Set objShell = CreateObject("Wscript.Shell")
objShell.Run "powershell.exe -ExecutionPolicy Bypass -File ""$escapedScriptPath"" -RepoDir ""$TrackingRepo""", 0, False
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
Write-Deploy "Registring task..."
Register-ScheduledTask -Action $Action `
    -Trigger @($Trigger1, $Trigger2) `
    -Principal $Principal `
    -Settings $Settings `
    -TaskName "$TaskName" `
    -Description "$TaskName info every 4 hours and at logon (non-admin)" `
    -Force

Write-Deploy @"

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
