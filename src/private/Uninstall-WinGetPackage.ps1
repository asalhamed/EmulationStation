function Uninstall-WinGetPackage {
    <#
    .SYNOPSIS
    Idempotently uninstalls a winget package. No-op if the package isn't installed.

    .DESCRIPTION
    Used by Uninstall-EmulationStation when -RemoveWinGetPackages is passed. Checks first;
    only invokes winget uninstall if Find-WinGetInstalledPackage reports the package is present.

    .PARAMETER Id
    The exact winget PackageIdentifier.

    .OUTPUTS
    Hashtable: @{ Status = 'Uninstalled' | 'NotInstalled'; Id }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('hashtable')]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9._-]+$')]
        [string] $Id,

        [int] $TimeoutSec = 300
    )

    $existing = Find-WinGetInstalledPackage -Id $Id
    if (-not $existing) {
        return @{ Status = 'NotInstalled'; Id = $Id }
    }

    if (-not $PSCmdlet.ShouldProcess($Id, 'winget uninstall')) {
        return $null
    }

    Invoke-WinGet -Verb uninstall -Arguments @('--id', $Id, '--exact', '--silent') -TimeoutSec $TimeoutSec | Out-Null

    @{ Status = 'Uninstalled'; Id = $Id }
}
