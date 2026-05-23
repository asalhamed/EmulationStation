function Expand-VerifiedArchive {
    <#
    .SYNOPSIS
    Extracts a verified .zip or .7z archive to a destination directory.

    .DESCRIPTION
    .zip files extract via the .NET ZipFile API (no shell dependency, works on any Windows box).
    .7z files require 7-Zip on PATH (install with 'winget install 7zip.7zip').

    Replaces upstream's hardcoded C:\Program Files\7-Zip\7z.exe lookup and the name-shadowing of
    PowerShell's built-in Expand-Archive cmdlet.

    .PARAMETER Path
    The archive file to extract.

    .PARAMETER Destination
    Target directory. Created if missing.

    .PARAMETER Force
    Overwrite existing files in the destination.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Destination,

        [switch] $Force
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Archive not found: $Path"
    }

    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    switch ($ext) {
        '.zip' {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            if ($Force) {
                [System.IO.Compression.ZipFile]::ExtractToDirectory($Path, $Destination, $true)
            }
            else {
                [System.IO.Compression.ZipFile]::ExtractToDirectory($Path, $Destination)
            }
        }
        '.exe' {
            # Treated as a 7-Zip self-extracting archive (most Windows installer .exe's that ship
            # an emulator binary are SFX 7z — e.g. mame<ver>b_x64.exe). 7z handles SFX archives
            # natively. If the file isn't actually an SFX archive, 7z will fail with a clear error.
            $sevenZipExe = $null
            $cmd = Get-Command 7z -ErrorAction SilentlyContinue
            if ($cmd) { $sevenZipExe = $cmd.Source }
            else {
                foreach ($candidate in @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe")) {
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $sevenZipExe = $candidate; break }
                }
            }
            if (-not $sevenZipExe) {
                throw "7z.exe not found (needed for .exe SFX extraction). Install with: winget install 7zip.7zip"
            }
            $sevenZipArgs = @('x', "-o$Destination", '-y', $Path)
            & $sevenZipExe @sevenZipArgs | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "7z exited with code $LASTEXITCODE extracting SFX $Path"
            }
        }
        '.7z' {
            # Try PATH first, then known install locations. winget's NSIS installer for 7zip
            # doesn't reliably add to PATH for in-process consumers.
            $sevenZipExe = $null
            $cmd = Get-Command 7z -ErrorAction SilentlyContinue
            if ($cmd) {
                $sevenZipExe = $cmd.Source
            } else {
                foreach ($candidate in @(
                    "$env:ProgramFiles\7-Zip\7z.exe",
                    "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
                )) {
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                        $sevenZipExe = $candidate
                        break
                    }
                }
            }
            if (-not $sevenZipExe) {
                throw "7z.exe not found on PATH or in Program Files\7-Zip. Install with: winget install 7zip.7zip"
            }
            $sevenZipArgs = @('x', "-o$Destination", '-y', $Path)
            & $sevenZipExe @sevenZipArgs | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "7z exited with code $LASTEXITCODE for $Path"
            }
        }
        default {
            throw "Unsupported archive extension: '$ext' (path: $Path). Supported: .zip, .7z, .exe (SFX 7z)"
        }
    }
}
