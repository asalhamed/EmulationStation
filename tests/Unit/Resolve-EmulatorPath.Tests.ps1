BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force

    # Create a temp directory structure to stand in for an InstallLocation that real Test-Path checks can pass.
    $script:fakeInstallRoot = Join-Path ([System.IO.Path]::GetTempPath()) "evrp-test-$([guid]::NewGuid().Guid.Substring(0,8))"
    New-Item -ItemType Directory -Path $script:fakeInstallRoot -Force | Out-Null
    $script:fakeExePath = Join-Path $script:fakeInstallRoot 'foo.exe'
    Set-Content -LiteralPath $script:fakeExePath -Value 'binary'
}

AfterAll {
    Remove-Item -LiteralPath $script:fakeInstallRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-EmulatorPath — not installed' {
    It 'throws when winget reports the package is not installed' {
        InModuleScope EmulationStationSetup {
            Mock Find-WinGetInstalledPackage { $null }
            { Resolve-EmulatorPath -PackageId 'Foo.Bar' } |
                Should -Throw -ExpectedMessage '*not installed*'
        }
    }
}

Describe 'Resolve-EmulatorPath — happy paths' {
    It 'returns InstallLocation when DisplayName matches a registry entry' {
        InModuleScope EmulationStationSetup -Parameters @{ Loc = $script:fakeInstallRoot } {
            param($Loc)
            Mock Find-WinGetInstalledPackage {
                @{ Id = 'Foo.Bar'; DisplayName = 'Foo Bar'; Version = '1.0' }
            }
            Mock Test-Path { $true } -ParameterFilter { $Path -like 'HKLM:*' -or $LiteralPath -like 'HKLM:*' }
            Mock Test-Path { $false } -ParameterFilter { $Path -like 'HKCU:*' -or $LiteralPath -like 'HKCU:*' }
            Mock Test-Path { $true }    # default for our InstallLocation test
            Mock Get-ChildItem {
                @([PSCustomObject]@{ PSPath = 'HKLM:\...\foo' })
            } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
            Mock Get-ChildItem { @() } -ParameterFilter { $LiteralPath -like 'HKCU:*' }
            Mock Get-ItemProperty {
                [PSCustomObject]@{ DisplayName = 'Foo Bar'; InstallLocation = $Loc }
            }

            $result = Resolve-EmulatorPath -PackageId 'Foo.Bar'
            $result | Should -Be $Loc
        }
    }

    It 'returns full exe path when -ExecutableName is provided and exists' {
        InModuleScope EmulationStationSetup -Parameters @{ Loc = $script:fakeInstallRoot } {
            param($Loc)
            Mock Find-WinGetInstalledPackage {
                @{ Id = 'Foo.Bar'; DisplayName = 'Foo Bar'; Version = '1.0' }
            }
            Mock Test-Path { $true } -ParameterFilter { $Path -like 'HKLM:*' -or $LiteralPath -like 'HKLM:*' }
            Mock Test-Path { $false } -ParameterFilter { $Path -like 'HKCU:*' -or $LiteralPath -like 'HKCU:*' }
            Mock Test-Path { $true }
            Mock Get-ChildItem {
                @([PSCustomObject]@{ PSPath = 'HKLM:\...\foo' })
            } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
            Mock Get-ChildItem { @() } -ParameterFilter { $LiteralPath -like 'HKCU:*' }
            Mock Get-ItemProperty {
                [PSCustomObject]@{ DisplayName = 'Foo Bar'; InstallLocation = $Loc }
            }

            $result = Resolve-EmulatorPath -PackageId 'Foo.Bar' -ExecutableName 'foo.exe'
            $result | Should -Be (Join-Path $Loc 'foo.exe')
        }
    }
}

Describe 'Resolve-EmulatorPath — failures' {
    It 'throws when ExecutableName is missing under InstallLocation' {
        InModuleScope EmulationStationSetup -Parameters @{ Loc = $script:fakeInstallRoot } {
            param($Loc)
            Mock Find-WinGetInstalledPackage {
                @{ Id = 'Foo.Bar'; DisplayName = 'Foo Bar'; Version = '1.0' }
            }
            Mock Test-Path { $true } -ParameterFilter { $Path -like 'HKLM:*' -or $LiteralPath -like 'HKLM:*' }
            Mock Test-Path { $false } -ParameterFilter { $Path -like 'HKCU:*' -or $LiteralPath -like 'HKCU:*' }
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq $Loc }
            Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*\does-not-exist.exe' }
            Mock Get-ChildItem {
                @([PSCustomObject]@{ PSPath = 'HKLM:\...\foo' })
            } -ParameterFilter { $LiteralPath -like 'HKLM:*' }
            Mock Get-ChildItem { @() } -ParameterFilter { $LiteralPath -like 'HKCU:*' }
            Mock Get-ItemProperty {
                [PSCustomObject]@{ DisplayName = 'Foo Bar'; InstallLocation = $Loc }
            }

            { Resolve-EmulatorPath -PackageId 'Foo.Bar' -ExecutableName 'does-not-exist.exe' } |
                Should -Throw -ExpectedMessage "*not found under*"
        }
    }

    It 'throws when no registry entry matches' {
        InModuleScope EmulationStationSetup {
            Mock Find-WinGetInstalledPackage {
                @{ Id = 'Foo.Bar'; DisplayName = 'Foo Bar'; Version = '1.0' }
            }
            Mock Test-Path { $true } -ParameterFilter { $Path -like 'HK*:*' -or $LiteralPath -like 'HK*:*' }
            Mock Get-ChildItem { @() }
            Mock Get-ItemProperty { $null }

            { Resolve-EmulatorPath -PackageId 'Foo.Bar' } |
                Should -Throw -ExpectedMessage '*not found in registry*'
        }
    }
}
