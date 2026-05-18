BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force
}

Describe 'winget integration — read-only checks on this machine' -Tag 'Network' {
    It 'Invoke-WinGet runs against the real binary without error' {
        InModuleScope EmulationStationSetup {
            $result = Invoke-WinGet -Verb list -Arguments @('--id', 'Microsoft.PowerShell', '--exact') -TimeoutSec 60
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [string]
        }
    }

    It 'Install-WinGetPackage reports AlreadyInstalled for Microsoft.PowerShell' {
        InModuleScope EmulationStationSetup {
            $r = Install-WinGetPackage -Id 'Microsoft.PowerShell'
            $r.Status      | Should -Be 'AlreadyInstalled'
            $r.Id          | Should -Be 'Microsoft.PowerShell'
            $r.DisplayName | Should -Not -BeNullOrEmpty
            $r.Version     | Should -Not -BeNullOrEmpty
        }
    }

    It 'Resolve-EmulatorPath returns a real path for an installed EXE/MSI package' {
        # MSIX/Store apps (Microsoft.PowerShell, Microsoft.WindowsTerminal) don't register an
        # InstallLocation under the standard uninstall keys. EXE/MSI installs (Git, VS Code,
        # most emulators we care about) do. We try a few common candidates and skip if none
        # are present on this machine.
        InModuleScope EmulationStationSetup {
            $candidates = @('Git.Git', 'Microsoft.VisualStudioCode', '7zip.7zip', 'Notepad++.Notepad++')
            $resolved = $null
            foreach ($id in $candidates) {
                try {
                    $resolved = Resolve-EmulatorPath -PackageId $id
                    break
                }
                catch {
                    continue
                }
            }
            if (-not $resolved) {
                Set-ItResult -Skipped -Because "none of $($candidates -join ', ') are installed with a discoverable InstallLocation on this machine"
                return
            }
            Test-Path -LiteralPath $resolved | Should -BeTrue
        }
    }
}
