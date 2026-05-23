function Resolve-Manifest {
    <#
    .SYNOPSIS
    Reads and validates systems.psd1 + downloads.psd1 from a manifest directory.

    .DESCRIPTION
    Performs full schema validation: required fields, regex constraints, enum-valued fields,
    cross-manifest references (every system Artifact must resolve to a download). Throws on
    the first violation with a path-like message ('systems.psd1: Systems[2].Launcher.LibretroCore
    is required when Kind=Libretro'). Returns a PSCustomObject with .Systems (EmulatorSystem[])
    and .Downloads (DownloadSpec[]) — both fully typed and ready for downstream consumption.

    .PARAMETER ManifestRoot
    Directory containing systems.psd1 and downloads.psd1.
    #>
    [CmdletBinding()]
    [OutputType('pscustomobject')]
    param(
        [Parameter(Mandatory)]
        [string] $ManifestRoot
    )

    function ReadPsd1Strict([string]$path, [string]$label) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Manifest not found: $path"
        }
        $data = Import-PowerShellDataFile -LiteralPath $path
        if ($null -eq $data.SchemaVersion) {
            throw "${label}: missing required key 'SchemaVersion'."
        }
        if ($data.SchemaVersion -ne 1) {
            throw "${label}: SchemaVersion '$($data.SchemaVersion)' is not supported (expected 1)."
        }
        $data
    }

    $systemsPath   = Join-Path $ManifestRoot 'systems.psd1'
    $downloadsPath = Join-Path $ManifestRoot 'downloads.psd1'

    $rawSystems   = ReadPsd1Strict -path $systemsPath   -label 'systems.psd1'
    $rawDownloads = ReadPsd1Strict -path $downloadsPath -label 'downloads.psd1'

    # ---- Validate Downloads first so systems can cross-reference them ----
    if ($null -eq $rawDownloads.Downloads) {
        throw "downloads.psd1: missing required key 'Downloads'."
    }

    $validDownloadKinds = @('LibretroCore', 'Rom', 'Theme', 'EmulatorAsset', 'Emulator', 'SystemFile', 'Firmware')
    $downloadIds = [System.Collections.Generic.HashSet[string]]::new()
    $downloadList = [System.Collections.Generic.List[DownloadSpec]]::new()

    foreach ($key in $rawDownloads.Downloads.Keys) {
        $entry = $rawDownloads.Downloads[$key]
        $loc   = "downloads.psd1: '$key'"

        if ($key -cnotmatch '^[a-z][a-z0-9-]*$') {
            throw "${loc}: key must match ^[a-z][a-z0-9-]*$ (lowercase only)"
        }
        if (-not $downloadIds.Add($key)) {
            throw "${loc}: duplicate key"
        }
        if (-not $entry.Url) {
            throw "${loc}: Url is required"
        }
        if ($entry.Url -notmatch '^https://') {
            throw "${loc}: Url must start with https:// (got '$($entry.Url)')"
        }
        if (-not $entry.Sha256) {
            throw "${loc}: Sha256 is required"
        }
        if ($entry.Sha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw "${loc}: Sha256 must be 64 hex characters"
        }
        if (-not $entry.Kind) {
            throw "${loc}: Kind is required"
        }
        if ($entry.Kind -notin $validDownloadKinds) {
            throw "${loc}: Kind must be one of $($validDownloadKinds -join ', ') (got '$($entry.Kind)')"
        }
        if ($entry.Kind -eq 'Rom' -and -not $entry.System) {
            throw "${loc}: System is required when Kind='Rom'"
        }

        $d = [DownloadSpec]::new()
        $d.Id           = $key
        $d.Url          = $entry.Url
        $d.Sha256       = $entry.Sha256.ToLowerInvariant()
        $d.Kind         = $entry.Kind
        $d.System       = $entry.System
        $d.KeepArchive  = [bool]$entry.KeepArchive
        $downloadList.Add($d) | Out-Null
    }

    # ---- Validate Systems ----
    if ($null -eq $rawSystems.Systems) {
        throw "systems.psd1: missing required key 'Systems'."
    }

    $systemList = [System.Collections.Generic.List[EmulatorSystem]]::new()
    $seenNames  = [System.Collections.Generic.HashSet[string]]::new()

    $systemsArr = @($rawSystems.Systems)

    for ($i = 0; $i -lt $systemsArr.Count; $i++) {
        $entry = $systemsArr[$i]
        $loc   = "systems.psd1: Systems[$i]"

        if (-not $entry.Name) {
            throw "${loc}: Name is required"
        }
        if ($entry.Name -cnotmatch '^[a-z][a-z0-9_-]*$') {
            throw "${loc}: Name '$($entry.Name)' must match ^[a-z][a-z0-9_-]*$ (lowercase only)"
        }
        if (-not $seenNames.Add($entry.Name)) {
            throw "${loc}: duplicate Name '$($entry.Name)'"
        }
        if (-not $entry.FullName) {
            throw "${loc}: FullName is required"
        }
        if (-not $entry.RomExtensions -or @($entry.RomExtensions).Count -eq 0) {
            throw "${loc}: RomExtensions must be a non-empty array"
        }
        foreach ($ext in $entry.RomExtensions) {
            if ($ext -cnotmatch '^\.[a-z0-9]+$') {
                throw "${loc}: RomExtension '$ext' must match ^\.[a-z0-9]+$ (lowercase, leading dot)"
            }
        }
        if (-not $entry.Launcher) {
            throw "${loc}: Launcher is required"
        }
        $kind = $entry.Launcher.Kind
        if ($kind -notin @('Libretro', 'Standalone')) {
            throw "${loc}: Launcher.Kind must be 'Libretro' or 'Standalone' (got '$kind')"
        }
        if ($kind -eq 'Libretro') {
            if (-not $entry.Launcher.LibretroCore) {
                throw "${loc}: Launcher.LibretroCore is required when Kind='Libretro'"
            }
            if ($entry.Launcher.LibretroCore -notmatch '\.dll$') {
                throw "${loc}: Launcher.LibretroCore '$($entry.Launcher.LibretroCore)' should end in .dll"
            }
        }
        else {
            foreach ($req in @('PackageId', 'ExecutableName', 'CommandTemplate')) {
                if (-not $entry.Launcher.$req) {
                    throw "${loc}: Launcher.$req is required when Kind='Standalone'"
                }
            }
            # Source defaults to 'WinGet'. 'Manifest' means the emulator binary is downloaded as
            # an Artifact (Kind=Emulator) and the PackageId is just an internal lookup key.
            $source = if ($entry.Launcher.Source) { $entry.Launcher.Source } else { 'WinGet' }
            if ($source -notin @('WinGet', 'Manifest')) {
                throw "${loc}: Launcher.Source must be 'WinGet' or 'Manifest' (got '$source')"
            }
            if ($source -eq 'Manifest') {
                $hasEmulatorArtifact = $false
                if ($entry.Artifacts) {
                    foreach ($v in $entry.Artifacts.Values) {
                        # We can't strictly require Kind='Emulator' here without cross-referencing
                        # Downloads (done above), but the orchestrator will fail loudly if none exists.
                        if ($downloadIds.Contains($v)) { $hasEmulatorArtifact = $true; break }
                    }
                }
                if (-not $hasEmulatorArtifact) {
                    throw "${loc}: Launcher.Source='Manifest' requires at least one Artifacts entry referencing a Download of Kind='Emulator'"
                }
            }
        }

        # Normalize Packages (string or hashtable)
        $packages = @()
        if ($null -ne $entry.Packages) {
            foreach ($p in @($entry.Packages)) {
                if ($p -is [string]) {
                    if ($p -notmatch '^[A-Za-z0-9._-]+$') {
                        throw "${loc}: Package '$p' must match winget ID pattern ^[A-Za-z0-9._-]+$"
                    }
                    $packages += @{ Id = $p; Version = $null }
                }
                elseif ($p -is [hashtable]) {
                    if (-not $p.Id) {
                        throw "${loc}: Package hashtable missing Id"
                    }
                    if ($p.Id -notmatch '^[A-Za-z0-9._-]+$') {
                        throw "${loc}: Package Id '$($p.Id)' must match winget ID pattern"
                    }
                    $packages += @{ Id = $p.Id; Version = $p.Version }
                }
                else {
                    throw "${loc}: Package must be a string or hashtable (got $($p.GetType().Name))"
                }
            }
        }

        # Cross-ref Artifacts → downloads
        $artifacts = if ($entry.Artifacts) { $entry.Artifacts } else { @{} }
        foreach ($k in $artifacts.Keys) {
            $ref = $artifacts[$k]
            if (-not $downloadIds.Contains($ref)) {
                throw "${loc}: Artifacts.$k references download '$ref' which does not exist in downloads.psd1"
            }
        }

        $s = [EmulatorSystem]::new()
        $s.Name          = $entry.Name
        $s.FullName      = $entry.FullName
        $s.Platform      = if ($entry.Platform) { $entry.Platform } else { $entry.Name }
        $s.Theme         = if ($entry.Theme)    { $entry.Theme }    else { $entry.Name }
        $s.RomExtensions = @($entry.RomExtensions)
        $s.Notes         = $entry.Notes
        $s.Launcher      = $entry.Launcher
        $s.Packages      = $packages
        $s.Artifacts     = $artifacts
        $systemList.Add($s) | Out-Null
    }

    [pscustomobject]@{
        Systems   = $systemList.ToArray()
        Downloads = $downloadList.ToArray()
    }
}
