function Resolve-Manifest {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Manifest not found: $Path"
    }

    $manifest = Import-PowerShellDataFile -LiteralPath $Path

    if ($null -eq $manifest.SchemaVersion) {
        throw "Manifest at $Path is missing required key 'SchemaVersion'."
    }

    if ($manifest.SchemaVersion -ne 1) {
        throw "Manifest at $Path has SchemaVersion '$($manifest.SchemaVersion)'; this build supports only version 1."
    }

    $manifest
}
