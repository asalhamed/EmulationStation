function Install-EmulationStation {
    <#
    .SYNOPSIS
    Installs EmulationStation and configured emulators end-to-end.

    .DESCRIPTION
    Orchestrates the full install pipeline:
      1. Preflight (Assert-Prerequisite) unless -SkipPreflight.
      2. Read + validate manifest (Resolve-Manifest).
      3. Filter to requested -Systems (or all if unspecified).
      4. For each system: install winget packages, resolve launcher exe path, download
         each artifact (verified), extract or copy to the right place.
      5. Render es_systems.cfg + es_settings.cfg from the typed manifest.

    Failures are aggregated per the working principles: one system erroring does NOT stop
    the others. The returned summary has the full list of failures so callers can decide.

    .PARAMETER Systems
    Which systems to install. Unknown names produce a warning, not an error. Default: every
    system in the manifest.

    .PARAMETER InstallRoot
    Base install directory. Default: %USERPROFILE%\.emulationstation

    .PARAMETER ManifestRoot
    Where to find systems.psd1 + downloads.psd1. Default: the module's bundled manifest/.

    .PARAMETER CacheRoot
    Where to cache downloaded archives. Default: $InstallRoot\.cache

    .PARAMETER SkipPreflight
    Skip Assert-Prerequisite. Testing only.

    .PARAMETER SkipHomebrew
    Don't download/place ROMs of Kind='Rom'. Useful for users supplying their own ROMs.

    .OUTPUTS
    Hashtable with Started, Finished, SystemsInstalled[], Failures[], InstallRoot.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('hashtable')]
    param(
        [string[]] $Systems,
        [string]   $InstallRoot       = (Join-Path $env:USERPROFILE '.emulationstation'),
        [string]   $ManifestRoot,
        [string]   $CacheRoot,
        [switch]   $SkipPreflight,
        [switch]   $SkipHomebrew,
        # M8 ---
        [string]   $EmulationStationExe = (Join-Path ${env:ProgramFiles(x86)} 'EmulationStation\emulationstation.exe'),
        [switch]   $NoShortcuts,
        [switch]   $NoInstallLog,
        # Frontend (ES-DE) ---
        [switch]   $SkipFrontend,
        [string]   $FrontendPackageId = 'ES-DE.EmulationStation-DE',
        [string]   $FrontendExecutableName = 'ES-DE.exe'
    )

    if (-not $ManifestRoot) { $ManifestRoot = $script:ManifestRoot }
    if (-not $CacheRoot)    { $CacheRoot    = Join-Path $InstallRoot '.cache' }

    $started   = Get-Date
    $failures  = [System.Collections.Generic.List[hashtable]]::new()
    $installed = [System.Collections.Generic.List[string]]::new()

    # M8: install log
    $logPath = Join-Path $InstallRoot 'install-log.json'
    function script:Log {
        param([string] $Kind, [hashtable] $Props = @{})
        if ($NoInstallLog) { return }
        $a = @{ Kind = $Kind } + $Props
        try { Write-InstallLog -LogPath $logPath -Action $a } catch {
            Write-Warning "Install log write failed: $($_.Exception.Message)"
        }
    }
    Log -Kind 'Started' -Props @{ Requested = if ($Systems) { @($Systems) } else { '*' }; InstallRoot = $InstallRoot }

    if (-not $SkipPreflight) {
        $checks = Assert-Prerequisite
        $blockers = @($checks | Where-Object Status -EQ 'Fail')
        if ($blockers) {
            $detail = ($blockers | ForEach-Object { "$($_.Name): $($_.Detail)" }) -join '; '
            throw "Preflight failed: $detail"
        }
    }

    $manifest = Resolve-Manifest -ManifestRoot $ManifestRoot

    $filtered = @($manifest.Systems)
    if ($Systems) {
        $known = $manifest.Systems.Name
        foreach ($missing in ($Systems | Where-Object { $_ -notin $known })) {
            Write-Warning "Requested system '$missing' not in manifest; skipping."
        }
        $filtered = @($manifest.Systems | Where-Object { $_.Name -in $Systems })
    }

    foreach ($dir in @($InstallRoot, $CacheRoot, (Join-Path $InstallRoot 'roms'))) {
        if (-not (Test-Path -LiteralPath $dir)) {
            if ($PSCmdlet.ShouldProcess($dir, 'Create directory')) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Log -Kind 'DirectoryCreated' -Props @{ Path = $dir }
            }
        }
    }

    $launcherPaths = @{}
    $downloadsById = @{}
    foreach ($d in $manifest.Downloads) { $downloadsById[$d.Id] = $d }

    foreach ($system in $filtered) {
        Write-Host "==== $($system.Name) ($($system.FullName)) ===="
        $sysSucceeded = $true

        foreach ($pkg in $system.Packages) {
            try {
                Write-Host "  Install package: $($pkg.Id)$(if ($pkg.Version) { " ($($pkg.Version))" })"
                if ($PSCmdlet.ShouldProcess($pkg.Id, 'Install winget package')) {
                    $result = if ($pkg.Version) {
                        Install-WinGetPackage -Id $pkg.Id -Version $pkg.Version
                    } else {
                        Install-WinGetPackage -Id $pkg.Id
                    }
                    Write-Host "    -> $($result.Status) v$($result.Version)"
                    Log -Kind 'WinGetInstall' -Props @{
                        Id      = $result.Id
                        Status  = $result.Status
                        Version = $result.Version
                    }
                }
            }
            catch {
                Write-Warning "  Package install failed: $($_.Exception.Message)"
                $failures.Add(@{ System = $system.Name; Step = "InstallPackage:$($pkg.Id)"; Message = $_.Exception.Message })
                $sysSucceeded = $false
            }
        }

        $launcherPkgId = if ($system.Launcher.Kind -eq 'Libretro') { 'Libretro.RetroArch' } else { $system.Launcher.PackageId }
        $launcherExe   = if ($system.Launcher.Kind -eq 'Libretro') { 'retroarch.exe' }          else { $system.Launcher.ExecutableName }
        try {
            $resolved = Resolve-EmulatorPath -PackageId $launcherPkgId -ExecutableName $launcherExe
            $launcherPaths[$launcherPkgId] = $resolved
            Write-Host "  Resolved $launcherPkgId -> $resolved"
        }
        catch {
            Write-Warning "  Path resolution failed for ${launcherPkgId}: $($_.Exception.Message)"
            $failures.Add(@{ System = $system.Name; Step = "ResolveLauncher:$launcherPkgId"; Message = $_.Exception.Message })
            $sysSucceeded = $false
        }

        $romDir = Join-Path $InstallRoot ('roms\' + $system.Name)
        if (-not (Test-Path -LiteralPath $romDir)) {
            New-Item -ItemType Directory -Path $romDir -Force | Out-Null
        }

        foreach ($artifactKey in $system.Artifacts.Keys) {
            $downloadId = $system.Artifacts[$artifactKey]
            $download   = $downloadsById[$downloadId]
            if (-not $download) {
                Write-Warning "  Artifact '$artifactKey' references unknown download '$downloadId'"
                continue
            }

            if ($SkipHomebrew -and $download.Kind -eq 'Rom') {
                Write-Host "  Skip Rom $downloadId (-SkipHomebrew)"
                continue
            }

            $extension = [System.IO.Path]::GetExtension($download.Url.Split('?')[0])
            $cachePath = Join-Path $CacheRoot ($downloadId + $extension)

            try {
                Write-Host "  Download $downloadId"
                Get-VerifiedDownload -Uri $download.Url -Destination $cachePath -ExpectedSha256 $download.Sha256 | Out-Null
            }
            catch {
                Write-Warning "  Download failed for ${downloadId}: $($_.Exception.Message)"
                $failures.Add(@{ System = $system.Name; Step = "Download:$downloadId"; Message = $_.Exception.Message })
                continue
            }

            switch ([string]$download.Kind) {
                'LibretroCore' {
                    if (-not $launcherPaths.ContainsKey('Libretro.RetroArch')) {
                        Write-Warning "  No RetroArch path; cannot place core $downloadId"
                        continue
                    }
                    $raExe   = $launcherPaths['Libretro.RetroArch']
                    $raDir   = Split-Path -Parent $raExe
                    $coresDir = Join-Path $raDir 'cores'
                    if (-not (Test-Path -LiteralPath $coresDir)) {
                        New-Item -ItemType Directory -Path $coresDir -Force | Out-Null
                    }
                    try {
                        Expand-VerifiedArchive -Path $cachePath -Destination $coresDir -Force
                        Write-Host "    -> core extracted to $coresDir"
                    }
                    catch {
                        Write-Warning "  Core extraction failed: $($_.Exception.Message)"
                        $failures.Add(@{ System = $system.Name; Step = "ExtractCore:$downloadId"; Message = $_.Exception.Message })
                    }
                }
                'Rom' {
                    if ($extension -in @('.zip', '.7z')) {
                        try {
                            Expand-VerifiedArchive -Path $cachePath -Destination $romDir -Force
                            Write-Host "    -> ROM extracted to $romDir"
                        }
                        catch {
                            Write-Warning "  ROM extraction failed: $($_.Exception.Message)"
                            $failures.Add(@{ System = $system.Name; Step = "ExtractRom:$downloadId"; Message = $_.Exception.Message })
                        }
                    }
                    else {
                        Copy-Item -LiteralPath $cachePath -Destination $romDir -Force
                        Write-Host "    -> ROM copied to $romDir"
                    }
                }
                default {
                    Write-Host "  (Kind '$($download.Kind)' not handled in M5)"
                }
            }
        }

        if ($sysSucceeded) {
            $installed.Add($system.Name) | Out-Null
        }
    }

    if ($filtered.Count -gt 0 -and $launcherPaths.Count -gt 0) {
        $esSystemsPath = Join-Path $InstallRoot 'es_systems.cfg'
        try {
            Write-EsSystems -Systems $filtered -InstallRoot $InstallRoot -OutputPath $esSystemsPath -LauncherPaths $launcherPaths
            Write-Host "Wrote $esSystemsPath"
            Log -Kind 'ConfigRendered' -Props @{ Path = $esSystemsPath }

            # ES-DE reads custom_systems/es_systems.xml from its --home directory. We mirror the
            # same content there so ES-DE picks up our generated system definitions when launched
            # with --home <InstallRoot>.
            $esdeCustomDir = Join-Path $InstallRoot 'custom_systems'
            if (-not (Test-Path -LiteralPath $esdeCustomDir)) {
                New-Item -ItemType Directory -Path $esdeCustomDir -Force | Out-Null
                Log -Kind 'DirectoryCreated' -Props @{ Path = $esdeCustomDir }
            }
            $esdeSystemsXml = Join-Path $esdeCustomDir 'es_systems.xml'
            Copy-Item -LiteralPath $esSystemsPath -Destination $esdeSystemsXml -Force
            Write-Host "Mirrored to $esdeSystemsXml (ES-DE custom_systems)"
            Log -Kind 'ConfigRendered' -Props @{ Path = $esdeSystemsXml; Format = 'ESDE' }
        }
        catch {
            Write-Warning "es_systems.cfg generation failed: $($_.Exception.Message)"
            $failures.Add(@{ System = '*'; Step = 'WriteEsSystems'; Message = $_.Exception.Message })
        }

        $esSettingsPath = Join-Path $InstallRoot 'es_settings.cfg'
        try {
            Write-EsSettings -UserProfile $env:USERPROFILE -OutputPath $esSettingsPath
            Write-Host "Wrote $esSettingsPath"
            Log -Kind 'ConfigRendered' -Props @{ Path = $esSettingsPath }
        }
        catch {
            Write-Warning "es_settings.cfg generation failed: $($_.Exception.Message)"
            $failures.Add(@{ System = '*'; Step = 'WriteEsSettings'; Message = $_.Exception.Message })
        }
    }

    # Frontend: install ES-DE and auto-detect its path for shortcut creation.
    $frontendArgs = $null
    if (-not $SkipFrontend) {
        try {
            Write-Host "==== Frontend: $FrontendPackageId ===="
            if ($PSCmdlet.ShouldProcess($FrontendPackageId, 'Install winget package (frontend)')) {
                $r = Install-WinGetPackage -Id $FrontendPackageId
                Write-Host "  -> $($r.Status) v$($r.Version)"
                Log -Kind 'FrontendInstalled' -Props @{ Id = $FrontendPackageId; Status = $r.Status; Version = $r.Version }
            }

            $resolvedFrontend = Resolve-EmulatorPath -PackageId $FrontendPackageId -ExecutableName $FrontendExecutableName
            Write-Host "  Resolved $FrontendPackageId -> $resolvedFrontend"
            Log -Kind 'FrontendResolved' -Props @{ Path = $resolvedFrontend }

            # If the caller didn't override -EmulationStationExe, point shortcut creation at ES-DE.
            if (-not $PSBoundParameters.ContainsKey('EmulationStationExe')) {
                $EmulationStationExe = $resolvedFrontend
            }
            # Pass --home <InstallRoot> so ES-DE reads custom_systems/es_systems.xml from our tree
            # instead of the default %USERPROFILE%\ES-DE\.
            $frontendArgs = "--home `"$InstallRoot`""
        }
        catch {
            Write-Warning "Frontend install/resolution failed: $($_.Exception.Message)"
            $failures.Add(@{ System = '*'; Step = "Frontend:$FrontendPackageId"; Message = $_.Exception.Message })
        }
    }

    # M8: shortcuts
    if (-not $NoShortcuts) {
        if (-not (Test-Path -LiteralPath $EmulationStationExe -PathType Leaf)) {
            Write-Warning "EmulationStation.exe not found at '$EmulationStationExe' — skipping shortcut creation. Pass -EmulationStationExe to override, or -NoShortcuts to silence."
            $failures.Add(@{ System = '*'; Step = 'Shortcuts'; Message = "EmulationStation.exe not at $EmulationStationExe" })
        } else {
            $shortcuts = @(
                Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\EmulationStation.lnk'
                Join-Path $env:USERPROFILE 'Desktop\EmulationStation.lnk'
            )
            foreach ($lnk in $shortcuts) {
                try {
                    $params = @{ TargetExe = $EmulationStationExe; ShortcutPath = $lnk }
                    if ($frontendArgs) { $params.Arguments = $frontendArgs }
                    New-EmulationStationShortcut @params
                    Write-Host "Shortcut: $lnk$(if ($frontendArgs) { ' [args=' + $frontendArgs + ']' })"
                    Log -Kind 'ShortcutCreated' -Props @{ Path = $lnk; Target = $EmulationStationExe; Arguments = $frontendArgs }
                } catch {
                    Write-Warning "Shortcut creation failed for ${lnk}: $($_.Exception.Message)"
                    $failures.Add(@{ System = '*'; Step = 'Shortcut'; Message = $_.Exception.Message; Path = $lnk })
                }
            }
        }
    }

    Log -Kind 'Finished' -Props @{
        SystemsInstalled = $installed.ToArray()
        FailureCount     = $failures.Count
    }

    @{
        Started          = $started
        Finished         = Get-Date
        SystemsRequested = if ($Systems) { @($Systems) } else { @($manifest.Systems.Name) }
        SystemsInstalled = $installed.ToArray()
        Failures         = $failures.ToArray()
        InstallRoot      = $InstallRoot
        LogPath          = if ($NoInstallLog) { $null } else { $logPath }
    }
}
