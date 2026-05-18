function Install-WinGetPackage {
    <#
    .SYNOPSIS
    Idempotently installs a winget package. Queries first; only installs / upgrades when needed.

    .DESCRIPTION
    Returns a hashtable summarising the action taken. If the package is already installed at the
    requested version (or no version was requested), returns Status='AlreadyInstalled' without
    changing system state. If a different version is installed and -Version is specified, runs
    winget upgrade. Otherwise runs winget install.

    .PARAMETER Id
    The exact winget PackageIdentifier (e.g., 'Dolphin.Dolphin').

    .PARAMETER Version
    Optional version pin. Without it, "any installed version" satisfies the idempotency check.

    .PARAMETER UserScope
    Pass --scope user (per-user install). Default is winget's default (typically machine; requires admin).

    .OUTPUTS
    Hashtable: @{ Status = 'Installed' | 'AlreadyInstalled' | 'Upgraded'; Id; DisplayName; Version }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('hashtable')]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9._-]+$')]
        [string] $Id,

        [string] $Version,

        [switch] $UserScope,

        [int] $TimeoutSec = 600
    )

    $existing = Find-WinGetInstalledPackage -Id $Id

    if ($existing) {
        $installedVersion = $existing.Version
        if (-not $Version -or $installedVersion -eq $Version) {
            return @{
                Status      = 'AlreadyInstalled'
                Id          = $Id
                DisplayName = $existing.DisplayName
                Version     = $installedVersion
            }
        }

        # Different version requested — upgrade
        $upgradeArgs = @(
            '--id', $Id, '--exact', '--silent',
            '--accept-package-agreements', '--accept-source-agreements',
            '--version', $Version
        )
        if ($UserScope) { $upgradeArgs += @('--scope', 'user') }

        if (-not $PSCmdlet.ShouldProcess($Id, "Upgrade $installedVersion -> $Version")) {
            return $null
        }

        Invoke-WinGet -Verb upgrade -Arguments $upgradeArgs -TimeoutSec $TimeoutSec | Out-Null

        return @{
            Status      = 'Upgraded'
            Id          = $Id
            DisplayName = $existing.DisplayName
            Version     = $Version
        }
    }

    # Not installed — install
    $installArgs = @(
        '--id', $Id, '--exact', '--silent',
        '--accept-package-agreements', '--accept-source-agreements'
    )
    if ($Version)   { $installArgs += @('--version', $Version) }
    if ($UserScope) { $installArgs += @('--scope', 'user') }

    if (-not $PSCmdlet.ShouldProcess($Id, 'Install')) { return $null }

    Invoke-WinGet -Verb install -Arguments $installArgs -TimeoutSec $TimeoutSec | Out-Null

    $after = Find-WinGetInstalledPackage -Id $Id
    if (-not $after) {
        throw "Install of '$Id' appeared to succeed but post-install query found nothing."
    }

    return @{
        Status      = 'Installed'
        Id          = $Id
        DisplayName = $after.DisplayName
        Version     = $after.Version
    }
}

function Find-WinGetInstalledPackage {
    <#
    .SYNOPSIS
    Returns @{ Id; DisplayName; Version } for a winget package if it's installed locally; $null otherwise.

    .DESCRIPTION
    winget v1.28 does not support --output json on the `list` verb, so we parse the tabular output.
    ANSI color codes (winget highlights the matched name column) are stripped first. Non-zero exit
    from winget — including the "no installed package found" path — is treated as "not installed".
    #>
    [CmdletBinding()]
    [OutputType('hashtable')]
    param(
        [Parameter(Mandatory)]
        [string] $Id
    )

    try {
        $stdout = Invoke-WinGet -Verb list -Arguments @('--id', $Id, '--exact') -TimeoutSec 60
    }
    catch {
        # Non-zero exit can mean "no match" or transient — treat as not installed.
        return $null
    }

    if (-not $stdout) { return $null }

    # Strip ANSI escape sequences (winget reverse-video on the matched column when running on a terminal).
    $clean = $stdout -replace "`e\[[0-9;]*m", ''

    # winget emits standalone CRs for spinner progress; split on any run of CR/LF and discard blanks.
    $lines = $clean -split "[\r\n]+" | Where-Object { $_ -notmatch '^\s*$' }

    # Find header (contains both "Name" and "Id") to discover column positions.
    $header = $lines | Where-Object { $_ -match '\bName\b' -and $_ -match '\bId\b' -and $_ -match '\bVersion\b' } | Select-Object -First 1
    if (-not $header) { return $null }

    $nameCol    = $header.IndexOf('Name')
    $idCol      = $header.IndexOf('Id')
    $versionCol = $header.IndexOf('Version')
    $sourceCol  = $header.IndexOf('Source')
    if ($nameCol -lt 0 -or $idCol -lt 0 -or $versionCol -lt 0) { return $null }

    # Find the data line for our Id.
    $dataLine = $lines | Where-Object { $_ -match "(?:^|\s)$([regex]::Escape($Id))(?:\s|$)" } | Select-Object -First 1
    if (-not $dataLine) { return $null }

    function SafeSubstring([string] $s, [int] $start, [int] $end) {
        if ($start -ge $s.Length) { return '' }
        $len = if ($end -gt $s.Length) { $s.Length - $start } else { $end - $start }
        if ($len -le 0) { return '' }
        $s.Substring($start, $len).Trim()
    }

    $endOfName    = $idCol
    $endOfId      = $versionCol
    $endOfVersion = if ($sourceCol -gt 0) { $sourceCol } else { $dataLine.Length }

    $name    = SafeSubstring $dataLine $nameCol    $endOfName
    $version = SafeSubstring $dataLine $versionCol $endOfVersion

    return @{
        Id          = $Id
        DisplayName = if ($name) { $name } else { $Id }
        Version     = $version
    }
}
