BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force
}

Describe 'Types' {
    It 'PreflightCheck constructs with three args' {
        InModuleScope EmulationStationSetup {
            $c = [PreflightCheck]::new('Test', 'Pass', 'detail')
            $c.Name   | Should -Be 'Test'
            $c.Status | Should -Be 'Pass'
            $c.Detail | Should -Be 'detail'
        }
    }

    It 'PreflightCheck constructs with four args (with Remediation)' {
        InModuleScope EmulationStationSetup {
            $c = [PreflightCheck]::new('Test', 'Fail', 'detail', 'fix it')
            $c.Remediation | Should -Be 'fix it'
        }
    }

    It 'PreflightStatus enum accepts Pass, Fail, Warn' {
        InModuleScope EmulationStationSetup {
            { [PreflightStatus]::Pass } | Should -Not -Throw
            { [PreflightStatus]::Fail } | Should -Not -Throw
            { [PreflightStatus]::Warn } | Should -Not -Throw
        }
    }

    It 'InstallReport instantiates' {
        InModuleScope EmulationStationSetup {
            $r = [InstallReport]::new()
            $r.OverallPass | Should -Be $false
        }
    }
}
