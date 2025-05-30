# This script tracks browser bookmarks, installed apps, and file metadata.

# Conventions: snake_case for filenames

param(
    [switch]$DisableGit
)

$Now = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$HomeDir = [Environment]::GetFolderPath("UserProfile")
$RepoDir = $PSScriptRoot
$TrackedFilesDir = Join-Path $RepoDir "tracked_files"
$LogFile = Join-Path $RepoDir "track.log"

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
        if (-not (Test-Path $browserPath)) { continue }

        # Retrieve the local state file to get profile names
        $localStatePath = Join-Path $browserPath "Local State"
        $json = $null
        if (Test-Path $localStatePath) {
            $json = Get-Content $localStatePath -Raw | ConvertFrom-Json
        }

        # Iterate through each profile directory
        Get-ChildItem -Path $browserPath -Directory | Where-Object { $_.Name -match '^(Default|Profile \d+)$' } | ForEach-Object {
            # Map profile names to display names
            $profileName = $_.Name
            $outputName = $profileName
            if ($json -and $json.profile.info_cache.$profileName -and $json.profile.info_cache.$profileName.name) {
                $outputName = $json.profile.info_cache.$profileName.name
            }

            # Track bookmarks
            $bookmarkPath = Join-Path $_.FullName "bookmarks"
            if (Test-Path $bookmarkPath) {
    
                $dst = Join-Path $TrackedFilesDir ("${browser}_${outputName}_bookmarks.json")
                # Redact sync metadata from bookmarks JSON file
                Get-Content $bookmarkPath -Encoding UTF8 | ForEach-Object {
                    $_ -replace '("sync_metadata"\s*:\s*)".*?"', '$1"[redacted]"'
                } | Set-Content $dst -Encoding UTF8
             }

            # Track search engines
            $webDataPath = Join-Path $_.FullName "Web Data"
            if (Test-Path $webDataPath) {
                $searchEnginesOut = Join-Path $TrackedFilesDir ("${browser}_${outputName}_search_engines.csv")
                $query = 'SELECT short_name, keyword, url, is_active, date_created FROM keywords ORDER BY id ASC;'
                $tmpDb = [System.IO.Path]::GetTempFileName()
                Copy-Item -Force $webDataPath $tmpDb
                write-host "Copied $webDataPath to $tmpDb"
                sqlite3 $tmpDb ".mode csv" ".headers on" ".output '$searchEnginesOut'" $query ".exit"
                Remove-Item $tmpDb -Force
            }
        }
    }

    Write-Host "Done."


    # Export installed programs (sorted by all properties for guaranteed consistency)
    Write-Host -NoNewline "[Registry] Exporting installed programs... "

    $InstalledProgramsPath = Join-Path $TrackedFilesDir "installed_programs.csv"
    $InstalledProgramsProperties = @("DisplayName", "DisplayVersion", "Publisher", "InstallDate")
    Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*, `
            HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, `
            HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*  |
        Where-Object { $_.DisplayName } |
        Select-Object $InstalledProgramsProperties |
        Sort-Object -Property $InstalledProgramsProperties |
        Export-Csv -Path $InstalledProgramsPath -NoTypeInformation -Encoding UTF8
    
    write-Host "Done."

    
    # Export installed Winget apps
    Write-Host -NoNewline "[Winget] Exporting installed apps... "

    $WingetExportPath = Join-Path $TrackedFilesDir "winget_export.json"
    winget export --output $WingetExportPath 
    
    Write-Host "Done."

    
    # Export PowerShell Gallery modules (sorted by all properties for guaranteed consistency)
    Write-Host -NoNewline "[PowerShell Gallery] Exporting installed modules... "

    $PsGalleryPath = Join-Path $TrackedFilesDir "ps_gallery_modules.csv"
    $PsGalleryProperties = @("Name", "Version", "Repository")
    # Sort by all properties to ensure consistent output
    Get-InstalledModule |
        Select-Object $PsGalleryProperties |
        Sort-Object -Property $PsGalleryProperties |
        Export-Csv -Path $PsGalleryPath -NoTypeInformation
    
    Write-Host "Done."


    # Export Microsoft Store apps (sorted by all properties for guaranteed consistency)
    Write-Host -NoNewline "[Microsoft Store] Exporting installed apps... "
    
    $MicrosoftStorePath = Join-Path $TrackedFilesDir "microsoft_store_apps.csv"
    $MicrosoftStoreProperties = @("Name", "Version", "Publisher", "IsDevelopmentMode", "NonRemovable")
    Get-AppxPackage |
        Select-Object $MicrosoftStoreProperties |
        Sort-Object -Property $MicrosoftStoreProperties |
        Export-Csv -Path $MicrosoftStorePath -NoTypeInformation
    
    Write-Host "Done."


    # Copy PowerShell $PROFILE scripts (all scopes)
    Write-Host -NoNewline "[PowerShell] Copying CurrentUserAllHosts profile script... "
    $profilePath = $PROFILE.CurrentUserAllHosts
    if (Test-Path $profilePath) {
        $dst = Join-Path $TrackedFilesDir (Split-Path $profilePath -Leaf)
        Copy-Item -Force $profilePath $dst
    }
    Write-Host "Done."

    # Copy global git config
    Write-Host -NoNewline "[Git] Copying global git config... "
    $gitConfigPath = Join-Path $HomeDir ".gitconfig"
    if (Test-Path $gitConfigPath) {
        $dst = Join-Path $TrackedFilesDir ".gitconfig"
        Copy-Item -Force $gitConfigPath $dst
    }
    Write-Host "Done."

    # Copy .gource-config if it exists
    Write-Host -NoNewline "[Gource] Copying .gource-config... "
    $gourceConfigPath = Join-Path $HomeDir ".gource-config"
    if (Test-Path $gourceConfigPath) {
        $dst = Join-Path $TrackedFilesDir ".gource-config"
        Copy-Item -Force $gourceConfigPath $dst
    }
    Write-Host "Done."

    # Push changes to Github
    if ($DisableGit) {
        Write-Host "Git operations are disabled. Skipping commit and push."
        return
    }
    Set-Location $RepoDir
    
    git add $TrackedFilesDir
    
    $diff = git diff --cached $WingetExportPath
    # Check if the diff ONLY touches CreationDate
    if ($diff -match '^\+\s*"CreationDate"\s*:\s*".*?"\s*,\s*$' -and
        $diff -match '^\-\s*"CreationDate"\s*:\s*".*?"\s*,\s*$' -and
        ($diff -replace '(\+\s*"CreationDate".*|\-\s*"CreationDate".*)', '').Trim() -eq '') {

        Write-Output "Skipping winget_export.json: Only CreationDate changed"

        # Unstage the file
        git restore --staged $WingetExportPath

        # Optionally revert the file to match HEAD
        git restore $WingetExportPath
    }


    # Get the number of modified files and untracked files in the staging area:
    # | Letter | Meaning                                         |
    # | ------ | ----------------------------------------------- |
    # | `A`    | Added (new files)                               |
    # | `C`    | Copied                                          |
    # | `D`    | Deleted                                         |
    # | `M`    | Modified                                        |
    # | `R`    | Renamed                                         |
    # | `T`    | Type changed (e.g., file <-> symlink)           |
    # | `U`    | Unmerged (conflicts)                            |
    # | `X`    | Unknown (e.g., not tracked in the index)        |
    # | `B`    | Broken pairing (used for rename/copy detection) |
    $modifiedFilesCount = (git diff --cached --name-only --diff-filter=M | Measure-Object).Count
    $untrackedFilesCount = (git diff --cached --name-only --diff-filter=A | Measure-Object).Count
    $stagingFilesCount = (git diff --cached --name-only | Measure-Object).Count

    # get the number of changed files and untracked files expanding untracked directories
    git commit -m "Scheduled tracking at $Now"
    git push origin main

    Write-Host "Tracking complete."

    # Log success
    $successMessage = "[$(Get-Date)] SUCCESS: Tracking completed successfully."
    Add-Content -Path $LogFile -Value $successMessage

    # Toast notification for success
    [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null
    $toast = New-Object System.Windows.Forms.NotifyIcon
    $toast.Icon = [System.Drawing.SystemIcons]::Information
    $toast.BalloonTipTitle = "Tracking Script Succeeded"
    # Calculate next run time based on 4-hour fixed windows
    $now = Get-Date
    $nextRun = $now.Date.AddHours(4 * [math]::Ceiling($now.Hour / 4))
    if ($nextRun -le $now) { $nextRun = $nextRun.AddHours(4) }
    $toast.BalloonTipText = $(
        if ($stagingFilesCount -eq 0) {
            "No changes to push."
        } else {
            "$stagingFilesCount to push ($modifiedFilesCount modified, $untrackedFilesCount untracked)"
        }
    ) + "`nNext run: $($nextRun.ToString('dd/MM/yyyy H:mm'))"
    $toast.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
    $toast.Visible = $true
    $toast.ShowBalloonTip(10000)
}
catch {
    $errorMessage = "[$(Get-Date)] ERROR: $_"
    Add-Content -Path $LogFile -Value $errorMessage

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
