BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force
}

Describe 'Shipped manifest — smoke checks' {
    BeforeAll {
        $script:Manifest = Get-EmulationStationManifest
    }

    It 'has exactly 15 systems (12 libretro + 3 Standalone)' {
        # 11 libretro from M3+M6 (nes, snes, gb, gbc, gba, megadrive, mastersystem, n64,
        # atari2600, arcade, c64) + 1 MSX (fmsx) + 2 winget Standalone (psx, ps2) +
        # 1 Manifest-source Standalone (ps3 via direct download).
        # GC + Wii (Dolphin) still excluded — winget manifest URL returns HTTP 403.
        $script:Manifest.Systems.Count | Should -Be 15
    }

    It 'has exactly 3 Standalone systems with all required Launcher fields' {
        $standalones = @($script:Manifest.Systems | Where-Object { $_.Launcher.Kind -eq 'Standalone' })
        $standalones.Count | Should -Be 3
        foreach ($s in $standalones) {
            $s.Launcher.PackageId       | Should -Not -BeNullOrEmpty -Because "system '$($s.Name)' missing PackageId"
            $s.Launcher.ExecutableName  | Should -Not -BeNullOrEmpty -Because "system '$($s.Name)' missing ExecutableName"
            $s.Launcher.CommandTemplate | Should -Not -BeNullOrEmpty -Because "system '$($s.Name)' missing CommandTemplate"
        }
    }

    It 'has exactly 12 Libretro systems' {
        $libretros = @($script:Manifest.Systems | Where-Object { $_.Launcher.Kind -eq 'Libretro' })
        $libretros.Count | Should -Be 12
    }

    It 'every system Artifact reference resolves to an entry in Downloads' {
        $downloadIds = $script:Manifest.Downloads | ForEach-Object Id
        foreach ($sys in $script:Manifest.Systems) {
            foreach ($key in $sys.Artifacts.Keys) {
                $ref = $sys.Artifacts[$key]
                $downloadIds | Should -Contain $ref -Because "system '$($sys.Name)' references missing download '$ref'"
            }
        }
    }

    It 'every system declares at least one RomExtension; WinGet-sourced systems also have Packages' {
        foreach ($sys in $script:Manifest.Systems) {
            $sys.RomExtensions.Count | Should -BeGreaterThan 0 -Because "system '$($sys.Name)' has no RomExtensions"
            # Manifest-sourced Standalone systems (e.g., PS3) skip winget entirely.
            $source = if ($sys.Launcher.Source) { $sys.Launcher.Source } else { 'WinGet' }
            if ($source -eq 'WinGet') {
                $sys.Packages.Count | Should -BeGreaterThan 0 -Because "WinGet-sourced system '$($sys.Name)' has no Packages"
            }
        }
    }

    It 'Libretro launchers all point at a .dll core name' {
        foreach ($sys in $script:Manifest.Systems) {
            if ($sys.Launcher.Kind -eq 'Libretro') {
                $sys.Launcher.LibretroCore | Should -Match '_libretro\.dll$' -Because "system '$($sys.Name)' has unusual core name"
            }
        }
    }

    It 'shared cores are intentional (gambatte for gb+gbc, genesis_plus_gx for megadrive+mastersystem)' {
        $byCore = @{}
        foreach ($sys in $script:Manifest.Systems) {
            if ($sys.Launcher.Kind -ne 'Libretro') { continue }
            $core = $sys.Launcher.LibretroCore
            if (-not $byCore.ContainsKey($core)) { $byCore[$core] = @() }
            $byCore[$core] += $sys.Name
        }

        $sharedCores = $byCore.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }

        # Expected: gambatte (gb, gbc), genesis_plus_gx (megadrive, mastersystem) — exactly 2 shared cores.
        $sharedCores.Count | Should -Be 2

        # Each shared core's system list should match what we documented.
        $shared = @{}
        foreach ($entry in $sharedCores) { $shared[$entry.Key] = ($entry.Value | Sort-Object) }
        $shared['gambatte_libretro.dll']         | Should -Be @('gb', 'gbc')
        $shared['genesis_plus_gx_libretro.dll']  | Should -Be @('mastersystem', 'megadrive')
    }
}
