function Write-InstallLog {
    <#
    .SYNOPSIS
    Appends an action to the install log at $LogPath. Creates the file if missing.

    .DESCRIPTION
    The install log is an append-only JSON document recording everything the orchestrator did.
    Schema v1:
        @{
            Version = 1
            Created = '<ISO-8601 UTC>'
            Actions = @( @{ Timestamp; Kind; ...kind-specific... }, ... )
        }
    M9's uninstaller walks Actions in reverse to undo what's undoable.

    Atomic write: serializes to <LogPath>.tmp first, then Move-Item to the final name.

    .PARAMETER LogPath
    Where the log lives. Created if missing.

    .PARAMETER Action
    Hashtable describing the action. 'Timestamp' is injected if absent. 'Kind' is required.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $LogPath,

        [Parameter(Mandatory)]
        [hashtable] $Action
    )

    if (-not $Action.ContainsKey('Kind')) {
        throw "Action must have a 'Kind' key. Got keys: $($Action.Keys -join ', ')"
    }
    if (-not $Action.ContainsKey('Timestamp')) {
        $Action.Timestamp = (Get-Date).ToUniversalTime().ToString('o')
    }

    if (Test-Path -LiteralPath $LogPath) {
        $existing = Get-Content -LiteralPath $LogPath -Raw | ConvertFrom-Json -AsHashtable
    } else {
        $logDir = Split-Path -Parent $LogPath
        if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $existing = @{
            Version = 1
            Created = (Get-Date).ToUniversalTime().ToString('o')
            Actions = @()
        }
    }

    # Normalize Actions to an array (ConvertFrom-Json may give us a single object or @())
    $actionsList = @()
    if ($existing.Actions) {
        $actionsList = @($existing.Actions)
    }
    $actionsList += $Action
    $existing.Actions = $actionsList

    $json = $existing | ConvertTo-Json -Depth 12

    $tmp = "$LogPath.tmp"
    Set-Content -LiteralPath $tmp -Value $json -NoNewline
    Move-Item -LiteralPath $tmp -Destination $LogPath -Force
}
