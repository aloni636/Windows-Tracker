# Link PowerShell 7 (pwsh.exe) $PROFILE.CurrentUserAllHosts profile to PowerShell 5 profile
if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
    Write-Host "Linking PowerShell 7 profile to Windows PowerShell profile."
    $PwshProfile = & pwsh -NoProfile -Command '$PROFILE.CurrentUserAllHosts'
    New-Item -Force -ItemType SymbolicLink -Path $PROFILE.CurrentUserAllHosts -Target $PwshProfile | Out-Null
} else {
    Write-Host "PowerShell 7 is not available, skipping profile linking."
}

if (-not (Get-Module -ListAvailable -Name Voicemeeter)) {
    Write-Host "Installing Voicemeeter API wrapper."
    Install-Module -Name Voicemeeter -Scope CurrentUser
} else {
    Write-Host "Voicemeeter powershell module is already installed."
}