BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force
}

Describe 'Assert-Prerequisite' {
    Context 'shape' {
        It 'returns 5 checks when nothing is skipped' {
            InModuleScope EmulationStationSetup {
                $r = Assert-Prerequisite
                $r.Count | Should -Be 5
            }
        }

        It 'returns 4 checks when one is skipped by name' {
            InModuleScope EmulationStationSetup {
                $r = Assert-Prerequisite -Skip @('Network')
                $r.Count | Should -Be 4
                $r.Name | Should -Not -Contain 'Network'
            }
        }

        It 'returns PreflightCheck objects with Pass/Fail/Warn statuses' {
            InModuleScope EmulationStationSetup {
                $r = Assert-Prerequisite
                foreach ($c in $r) {
                    $c.GetType().Name | Should -Be 'PreflightCheck'
                    $c.Status | Should -BeIn @('Pass', 'Fail', 'Warn')
                }
            }
        }
    }

    Context 'PowerShell version check' {
        It 'passes on PS >= 7.4 (this runtime)' {
            InModuleScope EmulationStationSetup {
                $r = (Assert-Prerequisite) | Where-Object Name -EQ 'PowerShell'
                if ($PSVersionTable.PSVersion -ge [version]'7.4') {
                    $r.Status | Should -Be 'Pass'
                }
                else {
                    $r.Status | Should -Be 'Fail'
                }
            }
        }
    }

    Context 'Skip parameter' {
        It 'is case-insensitive (PowerShell default for -notin)' {
            InModuleScope EmulationStationSetup {
                $r = Assert-Prerequisite -Skip @('network')
                $r.Name | Should -Not -Contain 'Network'
            }
        }

        It 'ignores unknown names without erroring' {
            InModuleScope EmulationStationSetup {
                { Assert-Prerequisite -Skip @('NotAThing') } | Should -Not -Throw
                (Assert-Prerequisite -Skip @('NotAThing')).Count | Should -Be 5
            }
        }
    }
}
