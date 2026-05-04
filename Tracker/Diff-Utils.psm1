# TODO: Replace git diff with this diff
# TODO: Extract logic and implement for CSV and JSON
# TODO: Add basic file diff for dotfiles
function Compare-Snapshot {
<#
.SYNOPSIS
Updates a CSV snapshot if input objects have changed.

.PARAMETER InputObjects
Collection of objects to snapshot.

.PARAMETER Projection
ScriptBlock that maps each input object to a flat comparable object.

.PARAMETER ComparisonFields
Property names used to determine equality between snapshots.

.PARAMETER Path
File path to the snapshot CSV.

.OUTPUTS
[bool] True if snapshot was updated, otherwise False.
#>
    param(
        [Parameter(Mandatory)]
        [object[]]    $InputObjects,

        [Parameter(Mandatory)]
        [scriptblock] $Projection,

        [Parameter(Mandatory)]
        [string[]]    $ComparisonFields,

        [Parameter(Mandatory)]
        [string]      $Path
    )

    $newSnapshot =
        $InputObjects |
        ForEach-Object $Projection |
        Sort-Object -Property $ComparisonFields

    $oldSnapshot =
        if (Test-Path $Path) {
            Import-Csv $Path
        } else {
            @()
        }

    $diff = Compare-Object `
        -ReferenceObject $oldSnapshot `
        -DifferenceObject $newSnapshot `
        -Property $ComparisonFields

    if ($null -ne $diff) {
        $newSnapshot | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
        return $true
    }

    return $false
}