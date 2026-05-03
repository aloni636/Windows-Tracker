Import-Module Voicemeeter

function Track-Voicemeeter {
    param (
        [Parameter(Mandatory)]
        [string]$XmlPath
    )
    try {
        $xml = [System.IO.Path]::GetFullPath($XmlPath)
        # Run the factory function for required Voicemeeter type
        $vmr = Get-RemotePotato
        $vmr.command.Save($xml)
    } catch {
        Write-Error "Voicemeeter is unavailable or not responding: $($_.Exception.Message)"
    }
    finally { $vmr.Logout() }
}