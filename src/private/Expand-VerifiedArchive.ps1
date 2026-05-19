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
        '.7z' {
            $sevenZip = Get-Command 7z -ErrorAction SilentlyContinue
            if (-not $sevenZip) {
                throw "7z.exe not found on PATH. Install with: winget install 7zip.7zip"
            }
            $args = @('x', "-o$Destination", '-y', $Path)
            & $sevenZip.Source @args | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "7z exited with code $LASTEXITCODE for $Path"
            }
        }
        default {
            throw "Unsupported archive extension: '$ext' (path: $Path). Supported: .zip, .7z"
        }
    }
}
