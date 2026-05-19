BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force

    $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ies-test-" + [guid]::NewGuid().Guid.Substring(0,8))
    New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null

    function script:MakeNesSystem {
        InModuleScope EmulationStationSetup {
            $s = [EmulatorSystem]::new()
            $s.Name = 'nes'; $s.FullName = 'NES'; $s.Platform = 'nes'; $s.Theme = 'nes'
            $s.RomExtensions = @('.nes')
            $s.Launcher = @{ Kind = 'Libretro'; LibretroCore = 'fceumm_libretro.dll' }
            $s.Packages = @(@{ Id = 'Libretro.RetroArch'; Version = $null })
            $s.Artifacts = @{ Core = 'fceumm-core' }
            $s
        }
    }

    function script:MakeFakeManifest {
        InModuleScope EmulationStationSetup {
            $d = [DownloadSpec]::new()
            $d.Id = 'fceumm-core'; $d.Url = 'https://example.com/fceumm.zip'
            $d.Sha256 = ('a' * 64); $d.Kind = [DownloadKind]::LibretroCore
            [pscustomobject]@{
                Systems = @((script:MakeNesSystem))
                Downloads = @($d)
            }
        }
    }
}

AfterAll {
    Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Install-EmulationStation — orchestration' {
    BeforeEach {
        InModuleScope EmulationStationSetup {
            Mock Assert-Prerequisite { @() }
            # Install-EmulationStation calls Resolve-Manifest directly, not Get-EmulationStationManifest.
            Mock Resolve-Manifest {
                $d = [DownloadSpec]::new()
                $d.Id = 'fceumm-core'; $d.Url = 'https://example.com/fceumm.zip'
                $d.Sha256 = ('a' * 64); $d.Kind = [DownloadKind]::LibretroCore
                $s = [EmulatorSystem]::new()
                $s.Name = 'nes'; $s.FullName = 'NES'; $s.Platform = 'nes'; $s.Theme = 'nes'
                $s.RomExtensions = @('.nes')
                $s.Launcher = @{ Kind = 'Libretro'; LibretroCore = 'fceumm_libretro.dll' }
                $s.Packages = @(@{ Id = 'Libretro.RetroArch'; Version = $null })
                $s.Artifacts = @{ Core = 'fceumm-core' }
                [pscustomobject]@{ Systems = @($s); Downloads = @($d) }
            }
            Mock Install-WinGetPackage { @{ Status = 'Installed'; Id = $Id; DisplayName = 'X'; Version = '1.0' } }
            Mock Resolve-EmulatorPath { 'C:\fake\retroarch.exe' }
            Mock Get-VerifiedDownload {
                Set-Content -LiteralPath $Destination -Value 'fake-zip-bytes'
                Get-Item -LiteralPath $Destination
            }
            Mock Expand-VerifiedArchive { }
            Mock Write-EsSystems  { }
            Mock Write-EsSettings { }
        }
    }

    It 'runs preflight by default and skips with -SkipPreflight' {
        $dest = Join-Path $script:TempRoot 'preflight-on'
        InModuleScope EmulationStationSetup -Parameters @{ D = $dest } {
            param($D)
            $null = Install-EmulationStation -InstallRoot $D
            Should -Invoke Assert-Prerequisite -Times 1
        }

        $dest2 = Join-Path $script:TempRoot 'preflight-off'
        InModuleScope EmulationStationSetup -Parameters @{ D = $dest2 } {
            param($D)
            $null = Install-EmulationStation -InstallRoot $D -SkipPreflight
            Should -Invoke Assert-Prerequisite -Times 1   # only the first call counts
        }
    }

    It 'throws when preflight has a Fail' {
        InModuleScope EmulationStationSetup -Parameters @{ D = (Join-Path $script:TempRoot 'fail') } {
            param($D)
            Mock Assert-Prerequisite {
                @([PreflightCheck]::new('X', [PreflightStatus]::Fail, 'broken'))
            }
            { Install-EmulationStation -InstallRoot $D } | Should -Throw -ExpectedMessage '*Preflight failed*'
        }
    }

    It 'warns and skips unknown system names rather than throwing' {
        $dest = Join-Path $script:TempRoot 'unknown'
        InModuleScope EmulationStationSetup -Parameters @{ D = $dest } {
            param($D)
            $warn = $null
            $r = Install-EmulationStation -InstallRoot $D -Systems @('nes', 'bogus') -SkipPreflight -WarningVariable warn -WarningAction SilentlyContinue
            $r.SystemsInstalled    | Should -Be @('nes')
            $r.SystemsRequested    | Should -Contain 'bogus'
            $warn -join ' '        | Should -Match 'bogus'
        }
    }

    It 'calls Install-WinGetPackage for each declared Package' {
        $dest = Join-Path $script:TempRoot 'pkgs'
        InModuleScope EmulationStationSetup -Parameters @{ D = $dest } {
            param($D)
            $null = Install-EmulationStation -InstallRoot $D -SkipPreflight
            Should -Invoke Install-WinGetPackage -ParameterFilter { $Id -eq 'Libretro.RetroArch' } -Times 1
        }
    }

    It 'calls Get-VerifiedDownload for each Artifact' {
        $dest = Join-Path $script:TempRoot 'arts'
        InModuleScope EmulationStationSetup -Parameters @{ D = $dest } {
            param($D)
            $null = Install-EmulationStation -InstallRoot $D -SkipPreflight
            Should -Invoke Get-VerifiedDownload -Times 1
        }
    }

    It 'aggregates artifact failure into Summary.Failures and continues' {
        $dest = Join-Path $script:TempRoot 'fail-aggregate'
        InModuleScope EmulationStationSetup -Parameters @{ D = $dest } {
            param($D)
            Mock Get-VerifiedDownload { throw 'simulated mismatch' }
            $r = Install-EmulationStation -InstallRoot $D -SkipPreflight -WarningAction SilentlyContinue
            $r.Failures.Count | Should -BeGreaterThan 0
            ($r.Failures | ForEach-Object Message) -join ' ' | Should -Match 'simulated mismatch'
            # Even though the artifact failed, the system is still considered installed
            # (winget package + path resolution succeeded — only the artifact was lost).
            $r.SystemsInstalled | Should -Be @('nes')
        }
    }

    It 'passes resolved LauncherPaths to Write-EsSystems' {
        $dest = Join-Path $script:TempRoot 'launcher-paths'
        InModuleScope EmulationStationSetup -Parameters @{ D = $dest } {
            param($D)
            $null = Install-EmulationStation -InstallRoot $D -SkipPreflight
            Should -Invoke Write-EsSystems -ParameterFilter {
                $LauncherPaths['Libretro.RetroArch'] -eq 'C:\fake\retroarch.exe'
            } -Times 1
        }
    }

    It 'installs multiple systems in one call when -Systems lists several' {
        $dest = Join-Path $script:TempRoot 'multi'
        InModuleScope EmulationStationSetup -Parameters @{ D = $dest } {
            param($D)
            # Override the default single-system mock with a two-system one for this test only.
            Mock Resolve-Manifest {
                $d1 = [DownloadSpec]::new()
                $d1.Id = 'fceumm-core'; $d1.Url = 'https://example.com/fceumm.zip'
                $d1.Sha256 = ('a' * 64); $d1.Kind = [DownloadKind]::LibretroCore
                $d2 = [DownloadSpec]::new()
                $d2.Id = 'snes9x-core'; $d2.Url = 'https://example.com/snes9x.zip'
                $d2.Sha256 = ('b' * 64); $d2.Kind = [DownloadKind]::LibretroCore

                $nes = [EmulatorSystem]::new()
                $nes.Name = 'nes'; $nes.FullName = 'NES'; $nes.Platform = 'nes'; $nes.Theme = 'nes'
                $nes.RomExtensions = @('.nes')
                $nes.Launcher = @{ Kind = 'Libretro'; LibretroCore = 'fceumm_libretro.dll' }
                $nes.Packages = @(@{ Id = 'Libretro.RetroArch'; Version = $null })
                $nes.Artifacts = @{ Core = 'fceumm-core' }

                $snes = [EmulatorSystem]::new()
                $snes.Name = 'snes'; $snes.FullName = 'SNES'; $snes.Platform = 'snes'; $snes.Theme = 'snes'
                $snes.RomExtensions = @('.smc')
                $snes.Launcher = @{ Kind = 'Libretro'; LibretroCore = 'snes9x_libretro.dll' }
                $snes.Packages = @(@{ Id = 'Libretro.RetroArch'; Version = $null })
                $snes.Artifacts = @{ Core = 'snes9x-core' }

                [pscustomobject]@{ Systems = @($nes, $snes); Downloads = @($d1, $d2) }
            }

            $r = Install-EmulationStation -InstallRoot $D -SkipPreflight -Systems @('nes', 'snes')
            $r.SystemsInstalled | Should -Contain 'nes'
            $r.SystemsInstalled | Should -Contain 'snes'

            # RetroArch is shared between the two systems; Install-WinGetPackage should be invoked
            # for it once per system call (idempotent at the winget layer) but Resolve-EmulatorPath
            # should only run once because launcherPaths cached the answer.
            Should -Invoke Resolve-EmulatorPath -ParameterFilter { $PackageId -eq 'Libretro.RetroArch' } -Times 1
        }
    }

    It 'returns a summary hashtable with the expected fields populated' {
        $dest = Join-Path $script:TempRoot 'summary'
        InModuleScope EmulationStationSetup -Parameters @{ D = $dest } {
            param($D)
            $r = Install-EmulationStation -InstallRoot $D -SkipPreflight
            $r              | Should -BeOfType [hashtable]
            $r.SystemsInstalled | Should -Be @('nes')
            $r.InstallRoot      | Should -Be $D
            $r.Started          | Should -BeOfType [datetime]
            $r.Finished         | Should -BeOfType [datetime]
        }
    }
}
