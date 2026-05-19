BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force

    $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("nes-shortcut-test-" + [guid]::NewGuid().Guid.Substring(0,8))
    New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null

    # Fake "EmulationStation.exe" we can point a shortcut at.
    $script:FakeExe = Join-Path $script:TempRoot 'fake-emulationstation.exe'
    Set-Content -LiteralPath $script:FakeExe -Value 'fake binary'
}

AfterAll {
    Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'New-EmulationStationShortcut' {
    It 'creates a .lnk file at the requested path' {
        $lnk = Join-Path $script:TempRoot 'es.lnk'
        InModuleScope EmulationStationSetup -Parameters @{ Exe = $script:FakeExe; L = $lnk } {
            param($Exe, $L)
            New-EmulationStationShortcut -TargetExe $Exe -ShortcutPath $L
        }
        Test-Path -LiteralPath $lnk | Should -BeTrue
        (Get-Item -LiteralPath $lnk).Length | Should -BeGreaterThan 0
    }

    It 'sets TargetPath on the .lnk to the input exe' {
        $lnk = Join-Path $script:TempRoot 'es-target.lnk'
        InModuleScope EmulationStationSetup -Parameters @{ Exe = $script:FakeExe; L = $lnk } {
            param($Exe, $L)
            New-EmulationStationShortcut -TargetExe $Exe -ShortcutPath $L
        }

        $wsh = New-Object -ComObject WScript.Shell
        try {
            $shortcut = $wsh.CreateShortcut($lnk)
            $shortcut.TargetPath | Should -Be $script:FakeExe
        }
        finally {
            if ($shortcut) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) | Out-Null }
            if ($wsh)      { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh)      | Out-Null }
        }
    }

    It 'throws when TargetExe does not exist' {
        $lnk = Join-Path $script:TempRoot 'missing.lnk'
        InModuleScope EmulationStationSetup -Parameters @{ L = $lnk } {
            param($L)
            { New-EmulationStationShortcut -TargetExe 'C:\does-not-exist.exe' -ShortcutPath $L } |
                Should -Throw -ExpectedMessage '*not found*'
        }
    }
}
