BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force
}

Describe 'Get-EmulationStationManifest' {
    It 'reads and validates the shipped manifest' {
        $m = Get-EmulationStationManifest
        $m | Should -Not -BeNullOrEmpty
        $m.Systems   | Should -Not -BeNullOrEmpty
        $m.Downloads | Should -Not -BeNullOrEmpty
    }

    It 'returns typed EmulatorSystem objects' {
        $m = Get-EmulationStationManifest
        foreach ($s in $m.Systems) {
            $s.GetType().Name | Should -Be 'EmulatorSystem'
            $s.Name           | Should -Match '^[a-z][a-z0-9_-]*$'
            $s.Platform       | Should -Not -BeNullOrEmpty
        }
    }
}
