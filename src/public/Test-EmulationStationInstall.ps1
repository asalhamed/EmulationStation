function Test-EmulationStationInstall {
    <#
    .SYNOPSIS
    Audits the local machine for EmulationStation install readiness, or the post-install state.

    .DESCRIPTION
    With -PreflightOnly, runs the readiness checks (PowerShell version, Windows version, winget,
    disk space, network reach) and returns a typed InstallReport. Without -PreflightOnly, runs the
    full post-install audit. The full audit lands in milestone M10; until then this errors.

    .PARAMETER PreflightOnly
    Run only the readiness checks; do not require an existing install.

    .PARAMETER InstallRoot
    Directory to audit for the post-install state. Defaults to %USERPROFILE%\.emulationstation.

    .EXAMPLE
    Test-EmulationStationInstall -PreflightOnly

    .EXAMPLE
    Test-EmulationStationInstall -PreflightOnly | Format-Table -Property When, OverallPass
    #>
    [CmdletBinding()]
    [OutputType('InstallReport')]
    param(
        [string] $InstallRoot = (Join-Path $env:USERPROFILE '.emulationstation'),
        [switch] $PreflightOnly
    )

    if ($PreflightOnly) {
        $checks      = Assert-Prerequisite
        $report      = [InstallReport]::new()
        $report.When = Get-Date
        $report.Checks = $checks
        $report.OverallPass = (@($checks | Where-Object Status -EQ 'Fail').Count -eq 0)
        return $report
    }

    throw [System.NotImplementedException]::new(
        'Full audit lands in M10. Use -PreflightOnly for now.'
    )
}
