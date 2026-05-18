function Get-VerifiedDownload {
    <#
    .SYNOPSIS
    Downloads a file over HTTPS, verifies its SHA-256, writes atomically, idempotent on re-run.

    .DESCRIPTION
    The only sanctioned way for this module to fetch bytes from the network. Rejects http://,
    requires a SHA-256 hash up front, writes to a .partial file, verifies the hash, then renames
    atomically. If the destination already exists with the expected hash, returns immediately
    without touching the network. Retries network errors with exponential backoff; hash mismatches
    and size-cap violations are NOT retried because they're deterministic.

    .PARAMETER Uri
    HTTPS URL to fetch. http:// is rejected at parameter binding.

    .PARAMETER Destination
    Full path where the verified file should land.

    .PARAMETER ExpectedSha256
    64-character hex SHA-256 hash the downloaded content must match. Mismatch aborts.

    .PARAMETER MaxSizeMB
    Refuse downloads larger than this. Default 5000 (5 GB).

    .PARAMETER RetryCount
    Network attempts on transient failure. Default 3.

    .PARAMETER TimeoutSec
    Per-attempt timeout. Default 300 (5 min).

    .PARAMETER InitialBackoffSec
    Base sleep between retries; doubled each attempt. Default 2 (2s, 4s, 8s, ...).

    .OUTPUTS
    System.IO.FileInfo of the verified file at Destination.
    #>
    [CmdletBinding()]
    [OutputType('System.IO.FileInfo')]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({
            if ($_ -notmatch '^https://') {
                throw "Uri must be https://. Got: $_"
            }
            $true
        })]
        [string] $Uri,

        [Parameter(Mandatory)]
        [string] $Destination,

        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-fA-F]{64}$')]
        [string] $ExpectedSha256,

        [int] $MaxSizeMB         = 5000,
        [int] $RetryCount        = 3,
        [int] $TimeoutSec        = 300,
        [int] $InitialBackoffSec = 2
    )

    $expectedHash = $ExpectedSha256.ToUpperInvariant()

    if (Test-Path -LiteralPath $Destination) {
        $existingHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
        if ($existingHash -eq $expectedHash) {
            Write-Verbose "Destination $Destination already exists with matching hash; skipping download."
            return Get-Item -LiteralPath $Destination
        }
        Write-Warning "Destination $Destination exists with hash $existingHash, expected $expectedHash. Replacing."
        Remove-Item -LiteralPath $Destination -Force
    }

    $destDir = Split-Path -Parent $Destination
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $partial   = "$Destination.partial"
    $userAgent = 'EmulationStationSetup/0.1 (PowerShell; +https://github.com/asalh/EmulationStation)'

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            if (Test-Path -LiteralPath $partial) {
                Remove-Item -LiteralPath $partial -Force
            }

            Write-Verbose "Downloading $Uri (attempt $attempt of $RetryCount)"
            Invoke-WebRequest -Uri $Uri `
                -OutFile $partial `
                -TimeoutSec $TimeoutSec `
                -MaximumRedirection 5 `
                -UserAgent $userAgent `
                -ErrorAction Stop

            $sizeMB = (Get-Item -LiteralPath $partial).Length / 1MB
            if ($sizeMB -gt $MaxSizeMB) {
                Remove-Item -LiteralPath $partial -Force
                throw "Download size $([math]::Round($sizeMB, 1)) MB exceeds cap of $MaxSizeMB MB for $Uri."
            }

            $actualHash = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash
            if ($actualHash -eq $expectedHash) {
                Move-Item -LiteralPath $partial -Destination $Destination -Force
                return Get-Item -LiteralPath $Destination
            }

            Remove-Item -LiteralPath $partial -Force
            throw "SHA-256 mismatch for $Uri. Expected $expectedHash, got $actualHash."
        }
        catch {
            $errMsg = $_.Exception.Message

            # Deterministic failures: do not retry.
            if ($errMsg -like 'SHA-256 mismatch*' -or $errMsg -like '*exceeds cap of*') {
                throw
            }

            if ($attempt -lt $RetryCount) {
                $sleep = [int]($InitialBackoffSec * [math]::Pow(2, $attempt - 1))
                Write-Verbose "Attempt $attempt failed ($errMsg). Sleeping ${sleep}s before retry."
                Start-Sleep -Seconds $sleep
                continue
            }

            if (Test-Path -LiteralPath $partial) {
                Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
            }
            throw "Failed to download $Uri after $RetryCount attempts: $errMsg"
        }
    }
}
