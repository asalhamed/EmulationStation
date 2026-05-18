function Get-EmulationStationManifest {
    <#
    .SYNOPSIS
    Reads and validates the system, package, and download manifests, returning their merged content.

    .PARAMETER ManifestRoot
    Directory containing systems.psd1, packages.psd1, and downloads.psd1. Defaults to the
    manifest/ directory shipped with this module.

    .EXAMPLE
    Get-EmulationStationManifest | Select-Object -ExpandProperty Systems
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $ManifestRoot
    )

    if (-not $ManifestRoot) {
        $ManifestRoot = $script:ManifestRoot
    }

    $root = Resolve-Path -LiteralPath $ManifestRoot

    [pscustomobject]@{
        Systems   = (Resolve-Manifest -Path (Join-Path $root 'systems.psd1')).Systems
        Packages  = (Resolve-Manifest -Path (Join-Path $root 'packages.psd1')).Packages
        Downloads = (Resolve-Manifest -Path (Join-Path $root 'downloads.psd1')).Downloads
    }
}
