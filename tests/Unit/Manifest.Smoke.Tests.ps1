BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force
}

Describe 'Shipped manifest — smoke checks' {
    BeforeAll {
        $script:Manifest = Get-EmulationStationManifest
    }

    It 'has exactly 11 systems (NES + 10 added in M6)' {
        $script:Manifest.Systems.Count | Should -Be 11
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

    It 'every system declares at least one Package and one RomExtension' {
        foreach ($sys in $script:Manifest.Systems) {
            $sys.Packages.Count      | Should -BeGreaterThan 0 -Because "system '$($sys.Name)' has no Packages"
            $sys.RomExtensions.Count | Should -BeGreaterThan 0 -Because "system '$($sys.Name)' has no RomExtensions"
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
