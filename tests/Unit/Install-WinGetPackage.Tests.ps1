BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force
}

Describe 'Install-WinGetPackage — parameter validation' {
    It 'rejects empty Id' {
        InModuleScope EmulationStationSetup {
            { Install-WinGetPackage -Id '' } | Should -Throw
        }
    }

    It 'rejects Id with shell metacharacters' {
        InModuleScope EmulationStationSetup {
            { Install-WinGetPackage -Id 'evil; rm -rf /' } | Should -Throw
        }
    }
}

Describe 'Install-WinGetPackage — already installed' {
    It 'returns AlreadyInstalled when no version is requested and package is present' {
        InModuleScope EmulationStationSetup {
            Mock Find-WinGetInstalledPackage {
                @{ Id = 'Foo.Bar'; DisplayName = 'Foo Bar'; Version = '1.2.3' }
            } -ParameterFilter { $Id -eq 'Foo.Bar' }
            Mock Invoke-WinGet { throw 'should not be called' }

            $r = Install-WinGetPackage -Id 'Foo.Bar'
            $r.Status      | Should -Be 'AlreadyInstalled'
            $r.Version     | Should -Be '1.2.3'
            $r.DisplayName | Should -Be 'Foo Bar'
            Should -Invoke Invoke-WinGet -Times 0
        }
    }

    It 'returns AlreadyInstalled when requested version matches installed' {
        InModuleScope EmulationStationSetup {
            Mock Find-WinGetInstalledPackage {
                @{ Id = 'Foo.Bar'; DisplayName = 'Foo Bar'; Version = '1.2.3' }
            }
            Mock Invoke-WinGet { throw 'should not be called' }

            $r = Install-WinGetPackage -Id 'Foo.Bar' -Version '1.2.3'
            $r.Status | Should -Be 'AlreadyInstalled'
            Should -Invoke Invoke-WinGet -Times 0
        }
    }
}

Describe 'Install-WinGetPackage — install when missing' {
    It 'calls winget install once and returns Installed' {
        InModuleScope EmulationStationSetup {
            $script:findCallCount = 0
            Mock Find-WinGetInstalledPackage {
                $script:findCallCount++
                if ($script:findCallCount -eq 1) { $null }
                else { @{ Id = 'Foo.Bar'; DisplayName = 'Foo Bar'; Version = '2.0.0' } }
            }
            Mock Invoke-WinGet { 'install ok' } -ParameterFilter { $Verb -eq 'install' }

            $r = Install-WinGetPackage -Id 'Foo.Bar'
            $r.Status      | Should -Be 'Installed'
            $r.Version     | Should -Be '2.0.0'
            Should -Invoke Invoke-WinGet -ParameterFilter { $Verb -eq 'install' } -Times 1
        }
    }

    It 'passes --scope user when -UserScope is set' {
        InModuleScope EmulationStationSetup {
            $script:capturedArgs = $null
            $script:findCallCount = 0
            Mock Find-WinGetInstalledPackage {
                $script:findCallCount++
                if ($script:findCallCount -eq 1) { $null }
                else { @{ Id = 'Foo.Bar'; DisplayName = 'Foo Bar'; Version = '2.0.0' } }
            }
            Mock Invoke-WinGet {
                $script:capturedArgs = $Arguments
                'install ok'
            } -ParameterFilter { $Verb -eq 'install' }

            $null = Install-WinGetPackage -Id 'Foo.Bar' -UserScope
            $script:capturedArgs | Should -Contain 'user'
            $script:capturedArgs | Should -Contain '--scope'
        }
    }

    It 'throws when post-install query finds nothing' {
        InModuleScope EmulationStationSetup {
            Mock Find-WinGetInstalledPackage { $null }   # always missing
            Mock Invoke-WinGet { 'install ok' } -ParameterFilter { $Verb -eq 'install' }

            { Install-WinGetPackage -Id 'Foo.Bar' } |
                Should -Throw -ExpectedMessage '*post-install query*'
        }
    }
}

Describe 'Install-WinGetPackage — upgrade' {
    It 'calls winget upgrade and returns Upgraded when versions differ' {
        InModuleScope EmulationStationSetup {
            Mock Find-WinGetInstalledPackage {
                @{ Id = 'Foo.Bar'; DisplayName = 'Foo Bar'; Version = '1.0.0' }
            }
            $script:upgradeCalled = $false
            Mock Invoke-WinGet { $script:upgradeCalled = $true; 'upgrade ok' } -ParameterFilter { $Verb -eq 'upgrade' }
            Mock Invoke-WinGet { throw 'should not be called' } -ParameterFilter { $Verb -eq 'install' }

            $r = Install-WinGetPackage -Id 'Foo.Bar' -Version '2.0.0'
            $r.Status  | Should -Be 'Upgraded'
            $r.Version | Should -Be '2.0.0'
            $script:upgradeCalled | Should -BeTrue
        }
    }
}
