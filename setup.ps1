# Link PowerShell 7 (pwsh.exe) $PROFILE.CurrentUserAllHosts profile to PowerShell 5 profile
if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
    $PwshProfile = & pwsh -NoProfile -Command '$PROFILE.CurrentUserAllHosts'
    New-Item -Force -ItemType SymbolicLink -Path $PROFILE.CurrentUserAllHosts -Target $PwshProfile | Out-Null
    Write-Host "Linked PowerShell 7 profile to Windows PowerShell profile."
}