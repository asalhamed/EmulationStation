BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force
}

Describe 'Uninstall-WinGetPackage' {
    It 'returns NotInstalled when the package isn''t present' {
        InModuleScope EmulationStationSetup {
            Mock Find-WinGetInstalledPackage { $null }
            Mock Invoke-WinGet { throw 'should not be called' }
            $r = Uninstall-WinGetPackage -Id 'Foo.Bar'
            $r.Status | Should -Be 'NotInstalled'
            $r.Id     | Should -Be 'Foo.Bar'
            Should -Invoke Invoke-WinGet -Times 0
        }
    }

    It 'calls winget uninstall with the right args when installed' {
        InModuleScope EmulationStationSetup {
            Mock Find-WinGetInstalledPackage { @{ Id = 'Foo.Bar'; DisplayName = 'Foo Bar'; Version = '1.0' } }
            $script:capturedArgs = $null
            Mock Invoke-WinGet {
                $script:capturedArgs = $Arguments
                'uninstall ok'
            } -ParameterFilter { $Verb -eq 'uninstall' }

            $r = Uninstall-WinGetPackage -Id 'Foo.Bar'
            $r.Status | Should -Be 'Uninstalled'
            Should -Invoke Invoke-WinGet -ParameterFilter { $Verb -eq 'uninstall' } -Times 1
            $script:capturedArgs | Should -Contain '--id'
            $script:capturedArgs | Should -Contain 'Foo.Bar'
            $script:capturedArgs | Should -Contain '--exact'
            $script:capturedArgs | Should -Contain '--silent'
        }
    }

    It 'rejects an Id with shell metacharacters' {
        InModuleScope EmulationStationSetup {
            { Uninstall-WinGetPackage -Id 'evil; rm -rf /' } | Should -Throw
        }
    }
}
