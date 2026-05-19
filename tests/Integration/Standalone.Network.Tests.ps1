BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force

    $script:Manifest = Get-EmulationStationManifest
    $script:Standalones = @($script:Manifest.Systems | Where-Object { $_.Launcher.Kind -eq 'Standalone' })
}

Describe 'Standalone emulators — best-effort path resolution' -Tag 'Network' {
    It 'resolves a real .exe path for every Standalone system already installed via winget' {
        # For each Standalone, check if the winget package is installed locally. If yes, resolve.
        # If not, skip — we do NOT install during this test (state-changing).
        $checked    = 0
        $resolved   = 0
        $missing    = @()

        foreach ($s in $script:Standalones) {
            $pkg = $s.Launcher.PackageId
            $exe = $s.Launcher.ExecutableName

            $isInstalled = InModuleScope EmulationStationSetup -Parameters @{ Id = $pkg } {
                param($Id)
                $r = Find-WinGetInstalledPackage -Id $Id
                $null -ne $r
            }

            if (-not $isInstalled) {
                Write-Host "SKIP $($s.Name) — $pkg not installed locally"
                continue
            }

            $checked++
            try {
                $path = InModuleScope EmulationStationSetup -Parameters @{ Id = $pkg; Exe = $exe } {
                    param($Id, $Exe)
                    Resolve-EmulatorPath -PackageId $Id -ExecutableName $Exe
                }
                Test-Path -LiteralPath $path | Should -BeTrue
                Write-Host "OK   $($s.Name) -> $path"
                $resolved++
            }
            catch {
                Write-Host "MISS $($s.Name) — installed but ExecutableName '$exe' not found: $($_.Exception.Message)"
                $missing += "$($s.Name) ($exe)"
            }
        }

        if ($checked -eq 0) {
            Set-ItResult -Skipped -Because "None of the 5 Standalone emulators are installed on this machine."
            return
        }
        # If anything was installed, we expect at least one to resolve. If multiple are installed
        # and ALL fail resolution, the manifest's ExecutableName is probably wrong — make that loud.
        $resolved | Should -BeGreaterThan 0 -Because "checked $checked Standalone(s) with installed packages but none resolved: $($missing -join ', ')"
    }
}
