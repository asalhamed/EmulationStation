function Update-DownloadHashes {
    <#
    .SYNOPSIS
    Maintainer cmdlet — downloads every artifact in downloads.psd1 and updates its SHA-256.

    .DESCRIPTION
    Iterates the downloads manifest, fetches each URL, computes SHA-256, and rewrites
    downloads.psd1 with real hashes. By default, only entries with the placeholder hash
    ('0' * 64) are updated; use -Force to refresh all.

    This is NOT something end users run. Maintainers run it when artifacts change upstream,
    review the diff, and commit the updated manifest. End-user installs always verify against
    the hashes pinned in the committed manifest.

    .PARAMETER ManifestRoot
    Directory containing downloads.psd1.

    .PARAMETER OutputPath
    Where to write the updated manifest. Defaults to overwriting downloads.psd1 in place.

    .PARAMETER Force
    Refresh all hashes, not only placeholders.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $ManifestRoot,

        [string] $OutputPath,

        [switch] $Force
    )

    $downloadsPath = Join-Path $ManifestRoot 'downloads.psd1'
    if (-not (Test-Path -LiteralPath $downloadsPath)) {
        throw "Manifest not found: $downloadsPath"
    }
    if (-not $OutputPath) {
        $OutputPath = $downloadsPath
    }

    $raw = Import-PowerShellDataFile -LiteralPath $downloadsPath
    $placeholder = '0' * 64

    $updated = @{}
    foreach ($key in $raw.Downloads.Keys) {
        $entry = $raw.Downloads[$key]
        $needsRefresh = $Force -or ($entry.Sha256 -eq $placeholder) -or -not $entry.Sha256
        if (-not $needsRefresh) {
            Write-Host "SKIP  $key (already pinned: $($entry.Sha256.Substring(0,12))..)"
            $updated[$key] = $entry
            continue
        }
        Write-Host "FETCH $key  <- $($entry.Url)"
        try {
            $newHash = Get-RemoteFileHash -Uri $entry.Url
            if (-not $newHash -or $newHash.Length -ne 64) {
                throw "Got back '$newHash' instead of a 64-char SHA-256."
            }
            Write-Host "      $key  =  $newHash"
            $newEntry = @{} + $entry
            $newEntry.Sha256 = $newHash
            $updated[$key] = $newEntry
        }
        catch {
            Write-Warning "Failed to hash $key from $($entry.Url): $($_.Exception.Message). Keeping previous Sha256 ('$($entry.Sha256)')."
            # Preserve whatever was previously there — never write a broken hash back.
            $preserved = @{} + $entry
            if (-not $preserved.Sha256 -or $preserved.Sha256 -eq '') {
                $preserved.Sha256 = $placeholder
            }
            $updated[$key] = $preserved
        }
    }

    if (-not $PSCmdlet.ShouldProcess($OutputPath, 'Write updated download manifest')) {
        return
    }

    $output = "@{`n    SchemaVersion = 1`n    Downloads = @{`n"
    foreach ($key in ($updated.Keys | Sort-Object)) {
        $d = $updated[$key]
        $output += "        '$key' = @{`n"
        $output += "            Url    = '$($d.Url)'`n"
        $output += "            Sha256 = '$($d.Sha256)'`n"
        $output += "            Kind   = '$($d.Kind)'`n"
        if ($d.System) {
            $output += "            System = '$($d.System)'`n"
        }
        $output += "        }`n"
    }
    $output += "    }`n}`n"

    Set-Content -LiteralPath $OutputPath -Value $output
}

function Get-RemoteFileHash {
    <#
    .SYNOPSIS
    Downloads a URL to a temp file, computes SHA-256, deletes the temp. Returns lowercase hex.
    Used by Update-DownloadHashes only; end-user installs always use Get-VerifiedDownload.
    #>
    [CmdletBinding()]
    [OutputType('string')]
    param(
        [Parameter(Mandatory)]
        [string] $Uri,

        [int] $TimeoutSec = 300
    )

    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        Invoke-WebRequest -Uri $Uri -OutFile $tmp -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop | Out-Null
        if (-not (Test-Path -LiteralPath $tmp) -or (Get-Item -LiteralPath $tmp).Length -eq 0) {
            throw "Downloaded file is missing or empty after fetch from $Uri."
        }
        (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}
