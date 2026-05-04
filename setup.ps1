# Link PowerShell 7 (pwsh.exe) $PROFILE.CurrentUserAllHosts profile to PowerShell 5 profile
$PwshProfile = Get-Item -LiteralPath (
    & pwsh -NoProfile -Command '$PROFILE.CurrentUserAllHosts'
)
if (-not (Get-Command pwsh.exe -ErrorAction SilentlyContinue)) {
    Write-Host "PowerShell 7 is not available, skipping profile linking."
}
elseif ($PwshProfile.ResolvedTarget -eq $PROFILE.CurrentUserAllHosts
) {
    Write-Host "PowerShell 7 is already linked, skipping profile linking."
}
else {
    Write-Host "Linking PowerShell 7 profile to Windows PowerShell profile."
    New-Item -Force -ItemType SymbolicLink -Path $PROFILE.CurrentUserAllHosts -Target $PwshProfile | Out-Null
}

if (-not (Get-Module -ListAvailable -Name Voicemeeter)) {
    Write-Host "Installing Voicemeeter API wrapper."
    Install-Module -Name Voicemeeter -Scope CurrentUser
}
else {
    Write-Host "Voicemeeter powershell module is already installed."
}