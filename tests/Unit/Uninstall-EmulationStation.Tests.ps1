BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force

    $script:Root = Join-Path ([System.IO.Path]::GetTempPath()) ("ues-test-" + [guid]::NewGuid().Guid.Substring(0,8))

    function script:Setup-Fixture {
        param([hashtable[]] $Actions)

        $tmp = Join-Path $script:Root ("install-$([guid]::NewGuid().Guid.Substring(0,8))")
        New-Item -Path $tmp -ItemType Directory -Force | Out-Null

        $doc = @{
            Version = 1
            Created = (Get-Date).ToUniversalTime().ToString('o')
            Actions = $Actions
        }
        $json = $doc | ConvertTo-Json -Depth 12
        Set-Content -LiteralPath (Join-Path $tmp 'install-log.json') -Value $json -NoNewline
        $tmp
    }
}

AfterAll {
    Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Uninstall-EmulationStation' {
    It 'throws when install-log.json is missing' {
        $tmp = Join-Path $script:Root "no-log-$([guid]::NewGuid().Guid.Substring(0,8))"
        New-Item -Path $tmp -ItemType Directory -Force | Out-Null
        InModuleScope EmulationStationSetup -Parameters @{ R = $tmp } {
            param($R)
            { Uninstall-EmulationStation -InstallRoot $R } |
                Should -Throw -ExpectedMessage '*No install log*'
        }
    }

    It 'reverses ShortcutCreated by deleting the .lnk' {
        $lnk = Join-Path $script:Root "fake-$([guid]::NewGuid().Guid.Substring(0,6)).lnk"
        Set-Content -LiteralPath $lnk -Value 'fake'
        $tmp = script:Setup-Fixture @( @{ Kind = 'ShortcutCreated'; Path = $lnk; Target = 'C:\nope.exe' } )
        InModuleScope EmulationStationSetup -Parameters @{ R = $tmp } {
            param($R)
            $r = Uninstall-EmulationStation -InstallRoot $R
            $r.Reversed.Count | Should -BeGreaterThan 0
        }
        Test-Path -LiteralPath $lnk | Should -BeFalse
    }

    It 'reverses ConfigRendered by deleting the .cfg file' {
        $cfg = Join-Path $script:Root "fake-$([guid]::NewGuid().Guid.Substring(0,6)).cfg"
        Set-Content -LiteralPath $cfg -Value '<systemList/>'
        $tmp = script:Setup-Fixture @( @{ Kind = 'ConfigRendered'; Path = $cfg } )
        InModuleScope EmulationStationSetup -Parameters @{ R = $tmp } {
            param($R)
            $null = Uninstall-EmulationStation -InstallRoot $R
        }
        Test-Path -LiteralPath $cfg | Should -BeFalse
    }

    It 'removes empty DirectoryCreated; preserves non-empty (user content)' {
        $emptyDir = Join-Path $script:Root "empty-$([guid]::NewGuid().Guid.Substring(0,6))"
        $fullDir  = Join-Path $script:Root "full-$([guid]::NewGuid().Guid.Substring(0,6))"
        New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null
        New-Item -Path $fullDir  -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $fullDir 'user-rom.nes') -Value 'mine'

        $tmp = script:Setup-Fixture @(
            @{ Kind = 'DirectoryCreated'; Path = $emptyDir }
            @{ Kind = 'DirectoryCreated'; Path = $fullDir  }
        )
        InModuleScope EmulationStationSetup -Parameters @{ R = $tmp } {
            param($R)
            $result = Uninstall-EmulationStation -InstallRoot $R
            ($result.Skipped | ForEach-Object Reason) -join ' ' | Should -Match 'not empty'
        }
        Test-Path -LiteralPath $emptyDir          | Should -BeFalse
        Test-Path -LiteralPath $fullDir           | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fullDir 'user-rom.nes') | Should -BeTrue
    }

    It 'skips WinGetInstall by default' {
        $tmp = script:Setup-Fixture @( @{ Kind = 'WinGetInstall'; Id = 'Foo.Bar'; Status = 'Installed'; Version = '1.0' } )
        InModuleScope EmulationStationSetup -Parameters @{ R = $tmp } {
            param($R)
            Mock Uninstall-WinGetPackage { throw 'should not be called' }
            $r = Uninstall-EmulationStation -InstallRoot $R
            Should -Invoke Uninstall-WinGetPackage -Times 0
            ($r.Skipped | ForEach-Object Reason) -join ' ' | Should -Match 'opt-in'
        }
    }

    It 'removes WinGetInstall with Status=Installed when -RemoveWinGetPackages set' {
        $tmp = script:Setup-Fixture @(
            @{ Kind = 'WinGetInstall'; Id = 'Foo.Installed';  Status = 'Installed';        Version = '1.0' }
            @{ Kind = 'WinGetInstall'; Id = 'Foo.PreExisting'; Status = 'AlreadyInstalled'; Version = '2.0' }
            @{ Kind = 'WinGetInstall'; Id = 'Foo.Upgraded';   Status = 'Upgraded';         Version = '3.0' }
        )
        InModuleScope EmulationStationSetup -Parameters @{ R = $tmp } {
            param($R)
            Mock Uninstall-WinGetPackage { @{ Status = 'Uninstalled'; Id = $Id } }
            $r = Uninstall-EmulationStation -InstallRoot $R -RemoveWinGetPackages

            # Only the Status='Installed' one should be uninstalled.
            Should -Invoke Uninstall-WinGetPackage -ParameterFilter { $Id -eq 'Foo.Installed' } -Times 1
            Should -Invoke Uninstall-WinGetPackage -ParameterFilter { $Id -eq 'Foo.PreExisting' } -Times 0
            Should -Invoke Uninstall-WinGetPackage -ParameterFilter { $Id -eq 'Foo.Upgraded' } -Times 0
        }
    }

    It 'returns a RemovalSummary with Reversed/Skipped/Failed populated' {
        $lnk = Join-Path $script:Root "summary-$([guid]::NewGuid().Guid.Substring(0,6)).lnk"
        Set-Content -LiteralPath $lnk -Value 'fake'
        $tmp = script:Setup-Fixture @(
            @{ Kind = 'Started' }
            @{ Kind = 'ShortcutCreated'; Path = $lnk; Target = 'C:\nope.exe' }
            @{ Kind = 'Finished' }
        )

        # Run InModuleScope and capture the return; assert from outside to avoid the
        # awkward Pester `-Parameters` hashtable-vs-string binding gotcha.
        $r = InModuleScope EmulationStationSetup -Parameters @{ Tmp = $tmp } {
            param([string] $Tmp)
            Uninstall-EmulationStation -InstallRoot $Tmp
        }
        ($r -is [hashtable]) | Should -BeTrue
        $r.Started      | Should -BeOfType [datetime]
        $r.Finished     | Should -BeOfType [datetime]
        $r.InstallRoot  | Should -Be $tmp
        $r.Reversed     | Should -Not -BeNullOrEmpty
        $r.Skipped      | Should -Not -BeNullOrEmpty   # Started + Finished are skipped as meta markers
        $r.Failed.Count | Should -Be 0
    }
}
