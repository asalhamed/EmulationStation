function Get-EmulationStationManifest {
    <#
    .SYNOPSIS
    Reads and validates the systems + downloads manifests, returning typed objects.

    .DESCRIPTION
    Loads manifest/systems.psd1 and manifest/downloads.psd1, runs full schema validation through
    Resolve-Manifest, and returns a PSCustomObject with .Systems (EmulatorSystem[]) and
    .Downloads (DownloadSpec[]). On any schema violation, throws with a precise file:path:reason
    error message — bad manifests fail loud and early.

    .PARAMETER ManifestRoot
    Directory containing systems.psd1 and downloads.psd1. Defaults to the manifest/ directory
    shipped with this module.

    .EXAMPLE
    Get-EmulationStationManifest | Select-Object -ExpandProperty Systems

    .EXAMPLE
    (Get-EmulationStationManifest).Downloads | Where-Object Kind -eq 'LibretroCore'
    #>
    [CmdletBinding()]
    [OutputType('pscustomobject')]
    param(
        [string] $ManifestRoot
    )

    if (-not $ManifestRoot) {
        $ManifestRoot = $script:ManifestRoot
    }

    Resolve-Manifest -ManifestRoot $ManifestRoot
}
