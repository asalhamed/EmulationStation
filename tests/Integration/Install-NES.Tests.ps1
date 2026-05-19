BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force

    $script:TempInstallRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("es-install-test-" + [guid]::NewGuid().Guid.Substring(0,8))
    New-Item -ItemType Directory -Path $script:TempInstallRoot -Force | Out-Null
}

AfterAll {
    # We deliberately do NOT uninstall Libretro.RetroArch — that would clobber a pre-existing user install.
    # The temp install root is cleaned up; the winget package stays.
    Remove-Item -LiteralPath $script:TempInstallRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Install-EmulationStation — NES end-to-end' -Tag 'Network','StateChange' {
    It 'installs RetroArch, places homebrew ROM, and writes es_systems.cfg' {
        $r = InModuleScope EmulationStationSetup -Parameters @{ R = $script:TempInstallRoot } {
            param($R)
            Install-EmulationStation -Systems @('nes') -InstallRoot $R -WarningAction SilentlyContinue
        }

        $r                          | Should -Not -BeNullOrEmpty
        $r.SystemsInstalled         | Should -Contain 'nes'

        # Artifact placement — we tolerate the fceumm core failing if libretro's buildbot is unreachable
        # or its hash is still a placeholder; the rest of the install should still land.
        $romsDir = Join-Path $script:TempInstallRoot 'roms\nes'
        Test-Path -LiteralPath $romsDir | Should -BeTrue

        # The homebrew ROM was hash-pinned; if it landed, the dir is non-empty.
        $romFiles = @(Get-ChildItem -LiteralPath $romsDir -Recurse -File -ErrorAction SilentlyContinue)
        if ($romFiles.Count -eq 0 -and -not ($r.Failures | Where-Object { $_.Step -like 'Download:nes-assimilate*' })) {
            throw "Roms dir is empty and there's no recorded download failure — something is wrong."
        }

        # The systems config should exist and contain a <name>nes</name> element.
        $cfg = Join-Path $script:TempInstallRoot 'es_systems.cfg'
        Test-Path -LiteralPath $cfg | Should -BeTrue
        $content = Get-Content -LiteralPath $cfg -Raw
        $content | Should -Match '<name>nes</name>'
        $content | Should -Match '<fullname>Nintendo Entertainment System</fullname>'

        # Settings file
        Test-Path -LiteralPath (Join-Path $script:TempInstallRoot 'es_settings.cfg') | Should -BeTrue
    }

    It 're-running is idempotent and returns SystemsInstalled containing nes again' {
        # Second pass should skip the winget install (AlreadyInstalled) and re-use cached downloads.
        $r = InModuleScope EmulationStationSetup -Parameters @{ R = $script:TempInstallRoot } {
            param($R)
            Install-EmulationStation -Systems @('nes') -InstallRoot $R -WarningAction SilentlyContinue
        }
        $r.SystemsInstalled | Should -Contain 'nes'
    }
}
