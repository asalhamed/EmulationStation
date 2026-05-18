function Invoke-WinGet {
    <#
    .SYNOPSIS
    Shells out to winget.exe with a controlled argument list, captures stdout/stderr, parses JSON
    when asked. Single chokepoint so other cmdlets can mock this rather than the native binary.

    .DESCRIPTION
    Throws on non-zero exit with stderr in the message. With -ParseJson, runs the verb with
    --output json and returns the parsed object. Without -ParseJson, returns raw stdout as a string.

    .PARAMETER Verb
    The winget subcommand. Constrained to the verbs we use.

    .PARAMETER Arguments
    Additional arguments passed to winget after the verb.

    .PARAMETER TimeoutSec
    Soft timeout: passed to the process wait. Not a hard kill — winget is generally well-behaved.

    .PARAMETER ParseJson
    Append --output json and parse stdout via ConvertFrom-Json.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('list', 'install', 'upgrade', 'search', 'show')]
        [string] $Verb,

        [string[]] $Arguments = @(),

        [int] $TimeoutSec = 600,

        [switch] $ParseJson
    )

    $wingetCmd = Get-Command winget -ErrorAction Stop
    $wingetExe = $wingetCmd.Source

    $allArgs = @($Verb) + $Arguments
    if ($ParseJson) {
        $allArgs += @('--output', 'json')
    }

    Write-Verbose "winget $($allArgs -join ' ')"

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $wingetExe `
            -ArgumentList $allArgs `
            -NoNewWindow `
            -Wait `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError $stderrFile `
            -PassThru

        $stdout = Get-Content -LiteralPath $stdoutFile -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content -LiteralPath $stderrFile -Raw -ErrorAction SilentlyContinue

        if ($proc.ExitCode -ne 0) {
            $msg = "winget $Verb exited with code $($proc.ExitCode)."
            if ($stderr) { $msg += " stderr: $stderr" }
            throw $msg
        }

        if ($ParseJson) {
            if ([string]::IsNullOrWhiteSpace($stdout)) {
                return $null
            }
            try {
                return $stdout | ConvertFrom-Json -Depth 32
            }
            catch {
                throw "Failed to parse winget JSON output: $($_.Exception.Message). Raw output: $stdout"
            }
        }

        return $stdout
    }
    finally {
        Remove-Item -LiteralPath $stdoutFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
    }
}
