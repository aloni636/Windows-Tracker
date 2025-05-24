# This script tracks browser bookmarks, installed apps, and file metadata.

$Now = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$HomeDir = [Environment]::GetFolderPath("UserProfile")
$RepoDir = Join-Path $HomeDir "Documents\TrackedData"
$TrackedFilesDir = Join-Path $RepoDir "files"
# $MetadataPath = Join-Path $RepoDir "file_metadata.json"
$FailureLog = Join-Path $RepoDir "failure.log"

try {
    # $FileMetadata = @{}

    # Define files to track
    $Chromium = @{
        "ChromeBookmarks" = Join-Path $HomeDir "AppData\Local\Google\Chrome\User Data\Default\Bookmarks"
        "EdgeBookmarks"   = Join-Path $HomeDir "AppData\Local\Microsoft\Edge\User Data\Default\Bookmarks"
    }
    $Firefox = Join-Path $HomeDir "AppData\Roaming\Mozilla\Firefox\Profiles"

    # Helper function to record metadata
    <#
    function Add-Metadata($path) {
        if (Test-Path $path) {
            $info = Get-Item $path
            $script:FileMetadata[$path] = [PSCustomObject]@{
                Name          = $info.Name
                OriginalPath  = $path
                LastWriteTime = $info.LastWriteTime
                CreationTime  = $info.CreationTime
                Length        = $info.Length
            }
        }
    }
    #>

    # Copy firefox bookmarks
    # Note: Firefox stores bookmarks in a SQLite database
    if (Test-Path $Firefox) {
        Get-ChildItem -Path $Firefox -Recurse -Filter "places.sqlite" | ForEach-Object {
            $profileName = Split-Path $_.Directory.Name -Leaf
            $dst = Join-Path $TrackedFilesDir ("$profileName\_places.sqlite")
            Copy-Item -Force $_.FullName $dst
            # Add-Metadata $dst
        }
    }

    # Copy Chromium bookmarks
    foreach ($key in $Chromium.Keys) {
        $src = $Chromium[$key]

        if (Test-Path $src) {
            $dst = Join-Path $TrackedFilesDir "$key.json"
            Copy-Item -Force -Path $src -Destination $dst
            # Add-Metadata $dst
        }
    }

    # Export installed Winget apps (constant filename)
    $WingetPath = Join-Path $RepoDir "winget_list.txt"
    winget list | Set-Content $WingetPath
    # Add-Metadata $WingetPath

    # Export PowerShell Gallery modules (constant filename)
    $PsGalleryPath = Join-Path $RepoDir "psgallery_modules.csv"
    Get-InstalledModule | Select-Object Name, Version, Repository | Export-Csv -Path $PsGalleryPath -NoTypeInformation
    # Add-Metadata $PsGalleryPath

    # Export installed programs from registry (constant filename)
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
        # Add-Metadata $AppsPath
    }
    
    # Save all collected metadata once per run
    $FileMetadata.Values | ConvertTo-Json -Depth 4 | Set-Content -Path $MetadataPath -Encoding UTF8
    #>

    # Git commit and push
    Set-Location $RepoDir
    git add .
    git commit -m "Auto snapshot $Now"
    git push origin main

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
