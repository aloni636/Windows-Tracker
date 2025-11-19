# See: https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/using-scriptanalyzer?view=ps-modules
# NOTE: If you edit this file, you have to call 'PowerShell: Restart Session' for those settings to be registered by VSCode's Powershell LSP
@{
    ExcludeRules = @(
        # TODO: Wrap write-host with custom endpoint routing to log file and host (if available)
        'PSAvoidUsingWriteHost',
        # This is not a module exporting a public API
        # Ergonomics and internal code clarity are preferred here to ecosystem verb standards
        'PSUseApprovedVerbs'
    )
}
