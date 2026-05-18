BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force

    $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("es-systems-test-" + [guid]::NewGuid().Guid.Substring(0,8))
    New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
}

AfterAll {
    Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Write-EsSystems' {
    It 'renders a Libretro system with the expected command' {
        $out = Join-Path $script:TempRoot 'es_systems.cfg'
        InModuleScope EmulationStationSetup -Parameters @{ Out = $out } {
            param($Out)
            $sys = [EmulatorSystem]::new()
            $sys.Name          = 'nes'
            $sys.FullName      = 'Nintendo Entertainment System'
            $sys.Platform      = 'nes'
            $sys.Theme         = 'nes'
            $sys.RomExtensions = @('.nes', '.fds')
            $sys.Launcher      = @{ Kind = 'Libretro'; LibretroCore = 'fceumm_libretro.dll' }
            $sys.Packages      = @(@{ Id = 'Libretro.RetroArch' })
            $sys.Artifacts     = @{}

            Write-EsSystems -Systems @($sys) -InstallRoot 'C:\fake-install' -OutputPath $Out `
                -LauncherPaths @{ 'Libretro.RetroArch' = 'C:\fake-install\systems\retroarch\retroarch.exe' }

            Test-Path -LiteralPath $Out | Should -BeTrue
            $content = Get-Content -LiteralPath $Out -Raw
            $content | Should -Match '<name>nes</name>'
            $content | Should -Match 'retroarch\.exe.*-L.*fceumm_libretro\.dll.*%ROM%'
        }
    }

    It 'renders a Standalone system with %EXE% substituted' {
        $out = Join-Path $script:TempRoot 'es_systems_psx.cfg'
        InModuleScope EmulationStationSetup -Parameters @{ Out = $out } {
            param($Out)
            $sys = [EmulatorSystem]::new()
            $sys.Name          = 'psx'
            $sys.FullName      = 'PlayStation'
            $sys.Platform      = 'psx'
            $sys.Theme         = 'psx'
            $sys.RomExtensions = @('.cue', '.iso')
            $sys.Launcher      = @{
                Kind            = 'Standalone'
                PackageId       = 'Stenzek.DuckStation'
                ExecutableName  = 'duckstation-qt-x64-ReleaseLTCG.exe'
                CommandTemplate = '"%EXE%" -batch -- "%ROM%"'
            }
            $sys.Packages      = @(@{ Id = 'Stenzek.DuckStation' })
            $sys.Artifacts     = @{}

            Write-EsSystems -Systems @($sys) -InstallRoot 'C:\fake-install' -OutputPath $Out `
                -LauncherPaths @{ 'Stenzek.DuckStation' = 'C:\Program Files\DuckStation' }

            $content = Get-Content -LiteralPath $Out -Raw
            $content | Should -Match 'duckstation-qt-x64-ReleaseLTCG\.exe'
            $content | Should -Match '%ROM%'
            $content | Should -Not -Match '%EXE%'
        }
    }

    It 'emits extensions in both lower and uppercase' {
        $out = Join-Path $script:TempRoot 'es_systems_ext.cfg'
        InModuleScope EmulationStationSetup -Parameters @{ Out = $out } {
            param($Out)
            $sys = [EmulatorSystem]::new()
            $sys.Name          = 'nes'
            $sys.FullName      = 'NES'
            $sys.Platform      = 'nes'
            $sys.Theme         = 'nes'
            $sys.RomExtensions = @('.nes', '.fds')
            $sys.Launcher      = @{ Kind = 'Libretro'; LibretroCore = 'x.dll' }
            $sys.Packages      = @()
            $sys.Artifacts     = @{}

            Write-EsSystems -Systems @($sys) -InstallRoot 'C:\x' -OutputPath $Out `
                -LauncherPaths @{ 'Libretro.RetroArch' = 'C:\x\ra.exe' }

            $content = Get-Content -LiteralPath $Out -Raw
            $content | Should -Match '\.nes \.NES \.fds \.FDS'
        }
    }

    It 'throws when Libretro path is missing from LauncherPaths' {
        $out = Join-Path $script:TempRoot 'es_systems_err.cfg'
        InModuleScope EmulationStationSetup -Parameters @{ Out = $out } {
            param($Out)
            $sys = [EmulatorSystem]::new()
            $sys.Name = 'nes'; $sys.FullName = 'X'; $sys.Platform = 'nes'; $sys.Theme = 'nes'
            $sys.RomExtensions = @('.nes')
            $sys.Launcher = @{ Kind = 'Libretro'; LibretroCore = 'x.dll' }
            $sys.Packages = @(); $sys.Artifacts = @{}

            { Write-EsSystems -Systems @($sys) -InstallRoot 'C:\x' -OutputPath $Out -LauncherPaths @{} } |
                Should -Throw -ExpectedMessage '*Libretro.RetroArch*'
        }
    }

    It 'renders multiple systems in one systemList' {
        $out = Join-Path $script:TempRoot 'es_systems_multi.cfg'
        InModuleScope EmulationStationSetup -Parameters @{ Out = $out } {
            param($Out)
            $nes = [EmulatorSystem]::new()
            $nes.Name = 'nes'; $nes.FullName = 'NES'; $nes.Platform = 'nes'; $nes.Theme = 'nes'
            $nes.RomExtensions = @('.nes')
            $nes.Launcher = @{ Kind = 'Libretro'; LibretroCore = 'x.dll' }
            $nes.Packages = @(); $nes.Artifacts = @{}

            $snes = [EmulatorSystem]::new()
            $snes.Name = 'snes'; $snes.FullName = 'SNES'; $snes.Platform = 'snes'; $snes.Theme = 'snes'
            $snes.RomExtensions = @('.smc')
            $snes.Launcher = @{ Kind = 'Libretro'; LibretroCore = 'snes9x_libretro.dll' }
            $snes.Packages = @(); $snes.Artifacts = @{}

            Write-EsSystems -Systems @($nes, $snes) -InstallRoot 'C:\x' -OutputPath $Out `
                -LauncherPaths @{ 'Libretro.RetroArch' = 'C:\x\ra.exe' }

            $content = Get-Content -LiteralPath $Out -Raw
            ([regex]'<system>').Matches($content).Count | Should -Be 2
        }
    }

    It 'produces well-formed XML' {
        $out = Join-Path $script:TempRoot 'es_systems_xml.cfg'
        InModuleScope EmulationStationSetup -Parameters @{ Out = $out } {
            param($Out)
            $sys = [EmulatorSystem]::new()
            $sys.Name = 'nes'; $sys.FullName = 'NES & Friends'; $sys.Platform = 'nes'; $sys.Theme = 'nes'
            $sys.RomExtensions = @('.nes')
            $sys.Launcher = @{ Kind = 'Libretro'; LibretroCore = 'x.dll' }
            $sys.Packages = @(); $sys.Artifacts = @{}

            Write-EsSystems -Systems @($sys) -InstallRoot 'C:\x' -OutputPath $Out `
                -LauncherPaths @{ 'Libretro.RetroArch' = 'C:\x\ra.exe' }

            $content = Get-Content -LiteralPath $Out -Raw
            { [xml]$content } | Should -Not -Throw
            $content | Should -Match 'NES &amp; Friends'
        }
    }
}
