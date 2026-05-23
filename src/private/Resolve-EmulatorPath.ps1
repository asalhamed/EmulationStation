function Resolve-EmulatorPath {
    <#
    .SYNOPSIS
    Returns the install directory (or a specific executable path) for an installed winget package
    by querying registry uninstall keys.

    .DESCRIPTION
    Replaces hardcoded paths like 'C:\tools\Dolphin-Beta\Dolphin.exe' with a runtime lookup. Uses
    the package's DisplayName (from winget) to find a matching entry in HKLM / HKLM\WOW6432Node /
    HKCU SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, and returns its InstallLocation.

    .PARAMETER PackageId
    The winget PackageIdentifier of an installed package.

    .PARAMETER ExecutableName
    Optional. If provided, returns the full path to <InstallLocation>\<ExecutableName> after
    verifying it exists. Otherwise returns the install directory.

    .OUTPUTS
    String — install directory or full executable path.
    #>
    [CmdletBinding()]
    [OutputType('string')]
    param(
        [Parameter(Mandatory)]
        [string] $PackageId,

        [string] $ExecutableName
    )

    $pkg = Find-WinGetInstalledPackage -Id $PackageId
    if (-not $pkg) {
        throw "Package '$PackageId' is not installed; cannot resolve its install location."
    }
    $displayName = $pkg.DisplayName

    $hives = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($hive in $hives) {
        if (-not (Test-Path $hive)) { continue }

        $entries = Get-ChildItem -LiteralPath $hive -ErrorAction SilentlyContinue
        foreach ($entry in $entries) {
            $props = Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction SilentlyContinue
            if (-not $props -or -not $props.DisplayName) { continue }

            $nameMatches = $props.DisplayName -eq $displayName -or $props.DisplayName -like "*$displayName*"
            if (-not $nameMatches) { continue }

            # Primary: InstallLocation field
            $loc = $props.InstallLocation

            # Fallback 1: NSIS / installers that don't populate InstallLocation often DO populate
            # UninstallString (or QuietUninstallString) pointing at <install-dir>\uninstall.exe.
            # Derive the install dir from the parent of that path.
            if (-not $loc -or -not (Test-Path -LiteralPath $loc)) {
                $uninst = $props.UninstallString
                if (-not $uninst) { $uninst = $props.QuietUninstallString }
                if ($uninst) {
                    # UninstallString can be quoted (e.g. "C:\Foo\uninstall.exe" /S) — strip quotes + arguments.
                    $exePart = $uninst.Trim()
                    if ($exePart.StartsWith('"')) {
                        $exePart = $exePart.Substring(1, $exePart.IndexOf('"', 1) - 1)
                    } else {
                        # Split on first space to drop trailing args.
                        $spaceIdx = $exePart.IndexOf(' ')
                        if ($spaceIdx -gt 0) { $exePart = $exePart.Substring(0, $spaceIdx) }
                    }
                    if (Test-Path -LiteralPath $exePart -PathType Leaf) {
                        $candidate = Split-Path -Parent $exePart
                        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Container)) {
                            $loc = $candidate
                        }
                    }
                }
            }

            if (-not $loc -or -not (Test-Path -LiteralPath $loc)) { continue }

            if ($ExecutableName) {
                $exePath = Join-Path $loc $ExecutableName
                if (Test-Path -LiteralPath $exePath) {
                    return $exePath
                }
                throw "Executable '$ExecutableName' not found under '$loc' for package '$PackageId'."
            }
            return $loc
        }
    }

    throw "Install location for '$PackageId' (DisplayName '$displayName') not found in registry uninstall keys."
}
