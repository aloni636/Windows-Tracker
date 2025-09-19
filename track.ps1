# This script tracks browser bookmarks, installed apps, and file metadata.

# Conventions: snake_case for filenames

param(
    [switch]$DisableGit,
    [string]$TrackingRepo
)

$HomeDir = [Environment]::GetFolderPath("UserProfile")
$RepoDir = $TrackingRepo
$TrackedFilesDir = $RepoDir
$LogFile = Join-Path $PSScriptRoot "track.log"

$now = Get-Date
$NowIso = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$NowLog = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Make sure the tracked files directory exists
if (-not (Test-Path $TrackedFilesDir)) {
    Write-Host -NoNewline "Creating tracked files directory..."
    New-Item -Path $TrackedFilesDir -ItemType Directory -Force | Out-Null
    Write-Host "Done."
}

try {
    # --- Collect Tracked Files From The System --- #
    # Copy firefox bookmarks
    # Note: Firefox stores bookmarks in a SQLite database
    # --- Firefox bookmarks -> CSV (per-profile) ---
    Write-Host -NoNewline "[Firefox] Exporting bookmarks... "

    $Firefox = Join-Path $HomeDir "AppData\Roaming\Mozilla\Firefox\Profiles"
    if (Test-Path $Firefox) {
        Get-ChildItem -Path $Firefox -Recurse -Filter "places.sqlite" | ForEach-Object {
            $profileName = Split-Path $_.Directory.Name -Leaf

            # Copy DB to a temp file to avoid locks
            $tmpDb = [System.IO.Path]::GetTempFileName()
            Copy-Item -Force $_.FullName $tmpDb

            # Output path
            $outCsv = Join-Path $TrackedFilesDir ("firefox_${profileName}_bookmarks.csv")

            # Export bookmarks:
            # - type=1 = bookmarks (not folders/livemarks)
            # - Build folder_path via recursive CTE over moz_bookmarks parent links
            # - Convert PRTime microseconds -> UTC ISO (seconds for sqlite)
            # - Join moz_places for URL, moz_keywords for keyword
            $query = @"
WITH RECURSIVE
tree(id, parent, name, path) AS (
    SELECT id, parent, COALESCE(title,''), '' FROM moz_bookmarks WHERE parent = 0
    UNION ALL
    SELECT b.id,
        b.parent,
        COALESCE(b.title,''),
        CASE WHEN t.path = '' THEN COALESCE(b.title,'') ELSE t.path || '/' || COALESCE(b.title,'') END
    FROM moz_bookmarks b
    JOIN tree t ON b.parent = t.id
)
SELECT
bm.guid                                           AS guid,
COALESCE(bm.title,'')                             AS title,
mp.url                                            AS url,
tree.path                                         AS folder_path,
strftime('%Y-%m-%dT%H:%M:%SZ', bm.dateAdded/1000000, 'unixepoch')     AS date_added_utc,
strftime('%Y-%m-%dT%H:%M:%SZ', bm.lastModified/1000000, 'unixepoch')  AS last_modified_utc,
COALESCE(mk.keyword,'')                           AS keyword
FROM moz_bookmarks bm
JOIN tree ON tree.id = bm.id
LEFT JOIN moz_places   mp ON mp.id = bm.fk
LEFT JOIN moz_keywords mk ON mk.id = bm.keyword_id
WHERE bm.type = 1
ORDER BY bm.dateAdded ASC;
"@

            sqlite3 $tmpDb ".mode csv" ".headers on" ".output '$outCsv'" $query ".exit"
            Remove-Item $tmpDb -Force
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

    function Copy-HomeMirrored {
        <# Copy one file under $HOME to a mirrored path under another root
        Ignored if no matches are found, errors if founds more than 1 match. #>
        [CmdletBinding(SupportsShouldProcess = $true)]
        param(
            [Parameter(Mandatory)]
            [string]$SourcePattern   # absolute path, may contain wildcards
        )

        $resolved = Get-ChildItem -Path $SourcePattern -File -ErrorAction SilentlyContinue
        if (-not $resolved) {
            return
        }
        if ($resolved.Count -gt 1) {
            $list = $resolved.FullName -join "`n"
            throw "Multiple matches for: $SourcePattern`n$list"
        }

        $src = $resolved[0]
        $full = [IO.Path]::GetFullPath($src.FullName)

        if ($full.StartsWith($HomeDir, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rel = $full.Substring($HomeDir.Length).TrimStart('\', '/')
        }
        else {
            # Source not under HOME; fall back to filename-only mirroring
            $rel = $src.Name
        }

        # To add "flatten" behavior in the future, override $rel here with $src.Name

        $dst = Join-Path $TrackedFilesDir $rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null

        Copy-Item -LiteralPath $src.FullName -Destination $dst -Force

        return $dst
    }

    # Copy PowerShell $PROFILE scripts (CurrentUserAllHosts scope)
    Write-Host -NoNewline "[PowerShell] Copying CurrentUserAllHosts profile script... "
    Copy-HomeMirrored ($PROFILE.CurrentUserAllHosts)
    Write-Host "Done."
    
    # Copy global git config
    Write-Host -NoNewline "[Git] Copying global git config... "
    Copy-HomeMirrored (Join-Path $HomeDir ".gitconfig")
    Write-Host "Done."

    # Copy .gource-config
    Write-Host -NoNewline "[Gource] Copying .gource-config... "
    Copy-HomeMirrored (Join-Path $HomeDir ".gource-config")
    Write-Host "Done."

    # assumes: $HomeDir and $TrackedFilesDir are set
    Write-Host -NoNewline "[WindowsTerminal] Copying settings.json... "
    Copy-HomeMirrored (Join-Path $HomeDir "AppData\Local\Packages\Microsoft.WindowsTerminal_*\LocalState\settings.json")
    Write-Host "Done."

    # --- Push Changes To Github --- #
    if ($DisableGit) {
        Write-Host "Git operations are disabled. Skipping commit and push."
    }
    else {
        Set-Location $RepoDir
        
        git add $TrackedFilesDir
        
        # --- Conditional Tracking --- #
        function Remove-DiffHeaders {
            <#
            This filter method removes diff hunk headers from `git diff -U0` input string.
            Example usage:
                git diff -U0 | Remove-DiffHeaders
            #>
            process {
                $headerSuffixes = @(
                    'diff \-{2}git', # Diff header
                    'index', # Index line
                    '\-{3}', # Old file header
                    '\+{3}', # New file header
                    '@@' # Hunk header
                )
                $pattern = '(?m)^(' + ($headerSuffixes -join '|') + ').*?$'
                return $_ -replace $pattern, ''
                # -replace '^[+-]\s*$', '' # Can be used to remove empty diff lines
                # -replace '(?m)^(@@|\+{3}|\-{3}|index|diff \-{2}git).*$', '' `
            }
        }
        
        # Check if the diff ONLY touches CreationDate in winget_export.json
        # Each time you run `winget export`, it updates the CreationDate field to the current date, which is irrelevant.
        # NOTE: Out-String is used to collapse the output which is array of lines into a single line
        $diffWingetExport = (git diff --staged -U0 $WingetExportPath) | Out-String
        if (($diffWingetExport `
                    -replace '[+-]\s*"CreationDate".*', '' `
                | Remove-DiffHeaders
            ).Trim() -eq '') {
            Write-Output "Skipping winget_export.json: Only CreationDate changed"
            
            # Unstage the file and revert to match HEAD
            git restore --staged $WingetExportPath
            git restore $WingetExportPath
        }

        # Check if the diff ONLY touches date_last_used and/or visit_count in *_bookmarks.json files
        # Those fields are updated by browsers when you visit a bookmark,
        # which is irrelevant for tracking new, modified or deleted bookmarks.
        git diff --staged --name-only | Where-Object { $_ -match '_bookmarks\.json$' } | ForEach-Object {
            $file = $_
            # NOTE: Out-String is used to collapse the output which is array of lines into a single line
            $diff = (git diff --staged -U0 $file) | Out-String 

            if (($diff `
                        -replace '(?m)^[+-]\s*"date_last_used"\s*:\s*".*?",?\s*$', '' `
                        -replace '(?m)^[+-]\s*"visit_count"\s*:\s*\d+,?\s*$', '' `
                    | Remove-DiffHeaders
                ).Trim() -eq '') {
                Write-Output "Skipping ${file}: Only date_last_used and/or visit_count changed"
                   
                # Unstage the file and revert to match HEAD
                git restore --staged $file
                git restore $file
            }
        }
        
        # Check if the diff ONLY touches Winget.Source in microsoft_store_apps.csv
        # Microsoft.Winget.Source is an MSIX file that contains a pre-indexed snapshot 
        # of the Winget community repository (basically a compressed SQLite DB with all the manifests).
        # Due to its update frequency (couple of times per day) and irrelevance, it is ignored.
        $diffMicrosoftStore = (git diff --staged -U0 $MicrosoftStorePath) | Out-String
        if (($diffMicrosoftStore `
                    -replace '(?m)^[+-]\s*".*Microsoft\.Winget\.Source".*$', '' |
                Remove-DiffHeaders).Trim() -eq '') {
            Write-Output 'Skipping microsoft_store_apps.csv: only Winget.Source bumped'
            git restore --staged $MicrosoftStorePath
            git restore $MicrosoftStorePath
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
        git commit -m "Scheduled tracking at $NowIso"
        git push origin main

        # Log success
        $successMessage = "[$NowLog] SUCCESS: Tracking completed successfully."
        Add-Content -Path $LogFile -Value $successMessage
    }

    Write-Host "Tracking complete."
    
    # --- Toast Notifications (Windows 10+ style) --- #
    $nextRun = $now.Date.AddHours(4 * [math]::Ceiling($now.Hour / 4))
    if ($nextRun -le $now) { $nextRun = $nextRun.AddHours(4) }
    $nextRunStr = $nextRun.ToString('H:mm')
    
    # Get latest commit hash for toast link
    $originUrl = git remote get-url origin
    $repoUrl = $originUrl -replace '\.git$', ''
    $commitHash = git rev-parse HEAD
    $commitUrl = if ($stagingFilesCount -gt 0) { "$repoUrl/commit/$commitHash" } else { "" }

    $attribution = if ($stagingFilesCount -gt 0) { "Click to open commit on Github" } else { "" }
    
    $xml = @"
<toast activationType="protocol" launch="$commitUrl" duration="short">
  <visual>
    <binding template="ToastGeneric">
      <text>Tracking Done (next: $nextRunStr)</text>
      <text placement="attribution">${attribution}</text>
    </binding>
  </visual>
</toast>
"@
    $XmlDocument = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]::New()
    $XmlDocument.loadXml($xml)
    $AppId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    $toast = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]::CreateToastNotifier($AppId)
    $toast.Show($XmlDocument)
}
catch {
    # Inside catch block
    $traceString = $_.Exception.StackTrace -replace '\s+', ' ' -replace '[\r\n]+', '; '

    $errorMessage = @"
[$NowLog] ERROR
    Message     : $($_.Exception.Message)
    Script Trace: $_.ScriptStackTrace
    Stack Trace : $traceString
    Exit Code   : $LASTEXITCODE
"@

    Add-Content -Path $LogFile -Value $errorMessage

    # Toast notification for error (Windows 10+ style)
    $truncatedErr = $_.Exception.Message -replace '^(.{100}).+$', '$1...' # truncate to 100 chars
    $escapedErr = [System.Security.SecurityElement]::Escape($truncatedErr)

    $logUri = "vscode://file/$($LogFile)"
    # 4. Escape the URI for the **attribute** slot as well
    $escapedUri = [System.Security.SecurityElement]::Escape($logUri)

    $xml = @"
    <toast activationType="protocol" launch="$escapedUri" duration="short">
    <visual>
        <binding template="ToastGeneric">
        <text>Tracking Failed</text>
        <text>$escapedErr</text>
        <text placement="attribution">Click to open log in VSCode</text>
        </binding>
    </visual>
</toast>
"@
    $XmlDocument = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]::New()
    $XmlDocument.loadXml($xml)
    $AppId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    $toast = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]::CreateToastNotifier($AppId)
    $toast.Show($XmlDocument)
    Write-Warning "Tracking script failed: $_"
}
