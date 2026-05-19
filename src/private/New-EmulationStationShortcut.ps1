function New-EmulationStationShortcut {
    <#
    .SYNOPSIS
    Creates a Windows .lnk shortcut pointing at the given EmulationStation executable.

    .DESCRIPTION
    Uses the WScript.Shell COM object — the standard way to write shortcuts on Windows.
    Idempotent: overwrites any existing shortcut at the same path. Creates parent dirs if
    needed.

    .PARAMETER TargetExe
    The .exe the shortcut should launch. Must exist (we throw if not — no dangling shortcuts).

    .PARAMETER ShortcutPath
    Where to write the .lnk file.

    .PARAMETER WorkingDirectory
    Optional working directory for the shortcut. Defaults to the directory of TargetExe.

    .PARAMETER Description
    Optional tooltip. Defaults to 'EmulationStation'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $TargetExe,

        [Parameter(Mandatory)]
        [string] $ShortcutPath,

        [string] $WorkingDirectory,

        [string] $Description = 'EmulationStation'
    )

    if (-not (Test-Path -LiteralPath $TargetExe -PathType Leaf)) {
        throw "TargetExe not found: $TargetExe"
    }

    $destDir = Split-Path -Parent $ShortcutPath
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $null
    try {
        $shortcut = $wsh.CreateShortcut($ShortcutPath)
        $shortcut.TargetPath       = $TargetExe
        $shortcut.WorkingDirectory = if ($WorkingDirectory) { $WorkingDirectory } else { Split-Path -Parent $TargetExe }
        $shortcut.Description      = $Description
        $shortcut.Save()
    }
    finally {
        if ($shortcut) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) | Out-Null }
        if ($wsh)      { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh)      | Out-Null }
    }
}
