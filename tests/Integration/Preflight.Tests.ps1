BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force
}

Describe 'Preflight on this machine' -Tag 'Integration' {
    BeforeAll {
        $script:report = Test-EmulationStationInstall -PreflightOnly
    }

    It 'returns an InstallReport' {
        $script:report.GetType().Name | Should -Be 'InstallReport'
    }

    It 'returns between 1 and 5 checks' {
        $script:report.Checks.Count | Should -BeGreaterOrEqual 1
        $script:report.Checks.Count | Should -BeLessOrEqual 5
    }

    It 'OverallPass is a boolean' {
        $script:report.OverallPass | Should -BeOfType [bool]
    }

    It 'every check has Name, Status, Detail' {
        foreach ($c in $script:report.Checks) {
            $c.Name   | Should -Not -BeNullOrEmpty
            $c.Status | Should -BeIn @('Pass', 'Fail', 'Warn')
        }
    }
}
