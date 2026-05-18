function Install-EmulationStation {
    <#
    .SYNOPSIS
    Installs EmulationStation and configured emulators. Not yet implemented.

    .DESCRIPTION
    The real implementation lands incrementally across milestones M5-M8. See PLAN.md.
    This stub exists so the module surface is complete from M0.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string[]] $Systems,
        [string]   $InstallRoot = (Join-Path $env:USERPROFILE '.emulationstation'),
        [switch]   $SkipHomebrew
    )

    throw [System.NotImplementedException]::new(
        'Install-EmulationStation lands in M5+. See PLAN.md.'
    )
}
