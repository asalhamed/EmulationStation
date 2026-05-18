function Uninstall-EmulationStation {
    <#
    .SYNOPSIS
    Removes EmulationStation artifacts placed by this module. Not yet implemented.

    .DESCRIPTION
    The real implementation lands in milestone M9. See PLAN.md.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $InstallLog,
        [switch] $KeepRoms,
        [switch] $RemoveWinGetPackages
    )

    throw [System.NotImplementedException]::new(
        'Uninstall-EmulationStation lands in M9. See PLAN.md.'
    )
}
