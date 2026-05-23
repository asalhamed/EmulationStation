function Write-EsSystems {
    <#
    .SYNOPSIS
    Renders es_systems.cfg from a typed EmulatorSystem[] and writes it to disk.

    .DESCRIPTION
    Generates the <systemList> XML directly from the manifest. No GUI launch, no sleep,
    no force-kill — replaces upstream's "launch ES, sleep 60s, kill" config bootstrap.

    For Libretro launchers the <command> is
        "<retroarch.exe>" -L "<core.dll>" %ROM%
    For Standalone launchers the <command> is the manifest's CommandTemplate with %EXE%
    replaced by the resolved executable path. %ROM% (and %ROM_RAW%) are preserved literally
    for EmulationStation's own runtime substitution.

    The rendered output is parsed as [xml] before writing; malformed input throws.

    .PARAMETER Systems
    The validated systems from Resolve-Manifest.

    .PARAMETER InstallRoot
    Base directory for the install — typically %USERPROFILE%\.emulationstation. ROM paths are
    computed as $InstallRoot\roms\<systemName>.

    .PARAMETER OutputPath
    Where to write es_systems.cfg.

    .PARAMETER LauncherPaths
    Hashtable mapping winget PackageId (or 'Libretro.RetroArch' for libretro systems) to the
    resolved executable path. Missing entries for systems that need them throws.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [EmulatorSystem[]] $Systems,

        [Parameter(Mandatory)]
        [string] $InstallRoot,

        [Parameter(Mandatory)]
        [string] $OutputPath,

        [hashtable] $LauncherPaths = @{}
    )

    $templatePath = Join-Path $script:TemplateRoot 'es_systems.cfg.system-block.template'
    if (-not (Test-Path -LiteralPath $templatePath)) {
        throw "Template not found: $templatePath"
    }
    $blockTemplate = Get-Content -LiteralPath $templatePath -Raw

    $blocks = foreach ($s in $Systems) {
        $romPath    = Join-Path $InstallRoot ('roms\' + $s.Name)
        $extensions = ($s.RomExtensions | ForEach-Object { $_, $_.ToUpper() }) -join ' '
        $command    = Build-LauncherCommand -System $s -LauncherPaths $LauncherPaths -InstallRoot $InstallRoot

        Render-Template -Template $blockTemplate -Substitutions @{
            NAME      = $s.Name
            FULLNAME  = $s.FullName
            PATH      = $romPath
            EXTENSION = $extensions
            COMMAND   = $command
            PLATFORM  = $s.Platform
            THEME     = $s.Theme
        }
    }

    $output = "<systemList>`n" + ($blocks -join "`n") + "`n</systemList>`n"

    # Parse to validate well-formedness — throws on malformed XML.
    [xml]$null = $output

    $destDir = Split-Path -Parent $OutputPath
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    Set-Content -LiteralPath $OutputPath -Value $output -NoNewline
}

function Build-LauncherCommand {
    [CmdletBinding()]
    [OutputType('string')]
    param(
        [Parameter(Mandatory)]
        [EmulatorSystem] $System,

        [Parameter(Mandatory)]
        [hashtable] $LauncherPaths,

        [Parameter(Mandatory)]
        [string] $InstallRoot
    )

    if ($System.Launcher.Kind -eq 'Libretro') {
        $raKey = 'Libretro.RetroArch'
        if (-not $LauncherPaths.ContainsKey($raKey)) {
            throw "System '$($System.Name)' is Libretro but no path provided for '$raKey' in -LauncherPaths."
        }
        $raExe = $LauncherPaths[$raKey]

        # Cores live next to retroarch.exe (RetroArch's default + what Place-Artifact actually does).
        # The previous version hardcoded $InstallRoot\systems\retroarch\cores which matched the upstream
        # convention but NOT where we actually drop core DLLs — so RetroArch couldn't find them.
        $coreDir = Join-Path (Split-Path -Parent $raExe) 'cores'
        $core    = Join-Path $coreDir $System.Launcher.LibretroCore
        return "`"$raExe`" -L `"$core`" %ROM%"
    }

    # Standalone
    $pkg = $System.Launcher.PackageId
    if (-not $LauncherPaths.ContainsKey($pkg)) {
        throw "System '$($System.Name)' is Standalone but no path provided for '$pkg' in -LauncherPaths."
    }
    $exeDirOrPath = $LauncherPaths[$pkg]

    # LauncherPaths may carry either the install directory or the full exe path. Resolve to full path.
    $exePath = if ((Test-Path -LiteralPath $exeDirOrPath -PathType Leaf)) {
        $exeDirOrPath
    } else {
        Join-Path $exeDirOrPath $System.Launcher.ExecutableName
    }

    # Per-system ROM directory (used by emulators that take a -rompath/folder argument like MAME).
    $romDir = Join-Path $InstallRoot ('roms\' + $System.Name)

    $cmd = $System.Launcher.CommandTemplate
    $cmd = $cmd -replace '%EXE%',    $exePath
    $cmd = $cmd -replace '%ROMDIR%', $romDir
    return $cmd
}
