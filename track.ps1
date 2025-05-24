# This script tracks browser bookmarks, installed apps, and file metadata.

# Conventions: snake_case for filenames


$Now = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$HomeDir = [Environment]::GetFolderPath("UserProfile")
$RepoDir = $PSScriptRoot
$TrackedFilesDir = Join-Path $RepoDir "tracked_files"
$FailureLog = Join-Path $RepoDir "failure.log"

# Make sure the tracked files directory exists
if (-not (Test-Path $TrackedFilesDir)) {
    Write-Host -NoNewline "Creating tracked files directory..."
    New-Item -Path $TrackedFilesDir -ItemType Directory -Force | Out-Null
    Write-Host "Done."
}

try {
    # Copy firefox bookmarks
    # Note: Firefox stores bookmarks in a SQLite database
    Write-Host -NoNewline "[Firefox] Copying bookmarks... "
    
    $Firefox = Join-Path $HomeDir "AppData\Roaming\Mozilla\Firefox\Profiles"
    if (Test-Path $Firefox) {
        Get-ChildItem -Path $Firefox -Recurse -Filter "places.sqlite" | ForEach-Object {
            $profileName = Split-Path $_.Directory.Name -Leaf
            $dst = Join-Path $TrackedFilesDir ("firefox_${profileName}_places.sqlite")
            Copy-Item -Force $_.FullName $dst
        }
    }
    
    Write-Host "Done."
    
    
    # Copy Chromium bookmarks (all profiles)
    Write-Host -NoNewline "[Chromium] Copying bookmarks from all profiles... "
    
    $ChromiumBrowsers = @{
        "chrome" = Join-Path $HomeDir "AppData\Local\Google\Chrome\User Data"
        "edge"   = Join-Path $HomeDir "AppData\Local\Microsoft\Edge\User Data"
    }
    foreach ($browser in $ChromiumBrowsers.Keys) {
        $browserPath = $ChromiumBrowsers[$browser]
        if (Test-Path $browserPath) {
            Get-ChildItem -Path $browserPath -Directory | Where-Object { $_.Name -match '^(Default|Profile \\d+)$' } | ForEach-Object {
                $profileName = $_.Name
                $bookmarkPath = Join-Path $_.FullName "bookmarks"
                if (Test-Path $bookmarkPath) {
                    $dst = Join-Path $TrackedFilesDir ("${browser}_${profileName}_bookmarks.json")
                    Copy-Item -Force -Path $bookmarkPath -Destination $dst
                }
            }
        }
    }
    
    Write-Host "Done."

    
    # Export installed programs
    Write-Host -NoNewline "[Registry] Exporting installed programs... "

    $InstalledProgramsPath = Join-Path $TrackedFilesDir "installed_programs.csv"
    Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*, `
            HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, `
            HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
        Sort-Object DisplayName |
        Export-Csv -Path $InstalledProgramsPath -NoTypeInformation -Encoding UTF8
    write-Host "Done."

    
    # Export installed Winget apps
    Write-Host -NoNewline "[Winget] Exporting installed apps... "

    $WingetExportPath = Join-Path $TrackedFilesDir "winget_export.json"
    winget export --output $WingetExportPath 
    
    Write-Host "Done."

    
    # Export PowerShell Gallery modules
    Write-Host -NoNewline "[PowerShell Gallery] Exporting installed modules... "
    
    $PsGalleryPath = Join-Path $TrackedFilesDir "ps_gallery_modules.csv"
    Get-InstalledModule | Select-Object Name, Version, Repository | Export-Csv -Path $PsGalleryPath -NoTypeInformation
    
    Write-Host "Done."

    # Export installed programs from registry
    <#
    $RegistryPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    $AppsPath = Join-Path $RepoDir "installed_programs.csv"
    $apps = @()
    foreach ($path in $RegistryPaths) {
        if (Test-Path $path) {
            $apps += Get-ChildItem $path | ForEach-Object {
                $_ | Get-ItemProperty | Select-Object DisplayName, DisplayVersion, Publisher
            }
        }
    }
    if ($apps.Count -gt 0) {
        $apps | Export-Csv -Path $AppsPath -NoTypeInformation
    }
    #>

    <#
    # Git commit and push
    Set-Location $RepoDir
    git add .
    git commit -m "Auto snapshot $Now"
    git push origin main
    #>

    Write-Host "Tracking complete."

    # Toast notification for success
    [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null
    $toast = New-Object System.Windows.Forms.NotifyIcon
    $toast.Icon = [System.Drawing.SystemIcons]::Information
    $toast.BalloonTipTitle = "Tracking Script Succeeded"
    $toast.BalloonTipText = "Tracking completed successfully."
    $toast.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
    $toast.Visible = $true
    $toast.ShowBalloonTip(10000)
}
catch {
    $errorMessage = "[$(Get-Date)] ERROR: $_"
    Add-Content -Path $FailureLog -Value $errorMessage

    # Notification (minimal disruption)
    [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null
    $balloon = New-Object System.Windows.Forms.NotifyIcon
    $balloon.Icon = [System.Drawing.SystemIcons]::Error
    $balloon.BalloonTipTitle = "Tracking Script Failed"
    $balloon.BalloonTipText = $_.ToString()
    $balloon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Error
    $balloon.Visible = $true
    $balloon.ShowBalloonTip(10000)

    Write-Warning "Tracking script failed: $_"
}
