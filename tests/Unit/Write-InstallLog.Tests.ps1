BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force

    $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wil-test-" + [guid]::NewGuid().Guid.Substring(0,8))
    New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
}

AfterAll {
    Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Write-InstallLog' {
    It 'creates a new log with the v1 skeleton when the file does not exist' {
        $log = Join-Path $script:TempRoot 'new.json'
        InModuleScope EmulationStationSetup -Parameters @{ L = $log } {
            param($L)
            Write-InstallLog -LogPath $L -Action @{ Kind = 'Started' }
        }
        Test-Path -LiteralPath $log | Should -BeTrue
        $doc = Get-Content -LiteralPath $log -Raw | ConvertFrom-Json
        $doc.Version       | Should -Be 1
        $doc.Created       | Should -Not -BeNullOrEmpty
        @($doc.Actions).Count | Should -Be 1
        $doc.Actions[0].Kind  | Should -Be 'Started'
    }

    It 'appends a second action to an existing log preserving order' {
        $log = Join-Path $script:TempRoot 'append.json'
        InModuleScope EmulationStationSetup -Parameters @{ L = $log } {
            param($L)
            Write-InstallLog -LogPath $L -Action @{ Kind = 'A' }
            Write-InstallLog -LogPath $L -Action @{ Kind = 'B' }
            Write-InstallLog -LogPath $L -Action @{ Kind = 'C' }
        }
        $doc = Get-Content -LiteralPath $log -Raw | ConvertFrom-Json
        @($doc.Actions).Count   | Should -Be 3
        $doc.Actions[0].Kind   | Should -Be 'A'
        $doc.Actions[1].Kind   | Should -Be 'B'
        $doc.Actions[2].Kind   | Should -Be 'C'
    }

    It 'injects Timestamp when the action does not provide one' {
        $log = Join-Path $script:TempRoot 'ts.json'
        InModuleScope EmulationStationSetup -Parameters @{ L = $log } {
            param($L)
            Write-InstallLog -LogPath $L -Action @{ Kind = 'X' }
        }
        $doc = Get-Content -LiteralPath $log -Raw | ConvertFrom-Json
        $doc.Actions[0].Timestamp | Should -Not -BeNullOrEmpty
        # Should be parseable as a real datetime
        { [datetime]::Parse($doc.Actions[0].Timestamp) } | Should -Not -Throw
    }

    It 'throws when the action lacks a Kind' {
        $log = Join-Path $script:TempRoot 'no-kind.json'
        InModuleScope EmulationStationSetup -Parameters @{ L = $log } {
            param($L)
            { Write-InstallLog -LogPath $L -Action @{ Path = 'X' } } |
                Should -Throw -ExpectedMessage "*Kind*"
        }
    }
}
