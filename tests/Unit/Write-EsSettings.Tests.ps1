BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force

    $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("es-settings-test-" + [guid]::NewGuid().Guid.Substring(0,8))
    New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
}

AfterAll {
    Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Write-EsSettings' {
    It 'produces a non-empty file with the expected root elements' {
        # es_settings.cfg is XML-ish but multi-rooted; not valid as a single XmlDocument.
        # We assert structure by content, not by [xml] parsing.
        $out = Join-Path $script:TempRoot 'es_settings.cfg'
        InModuleScope EmulationStationSetup -Parameters @{ Out = $out } {
            param($Out)
            Write-EsSettings -UserProfile 'C:\Users\test' -OutputPath $Out
            Test-Path -LiteralPath $Out | Should -BeTrue
            $content = Get-Content -LiteralPath $Out -Raw
            $content | Should -Match "<\?xml version='1\.0'\?>"
            $content | Should -Match '<bool '
            $content | Should -Match '<string '
        }
    }

    It 'substitutes USERPROFILE with forward slashes' {
        $out = Join-Path $script:TempRoot 'es_settings2.cfg'
        InModuleScope EmulationStationSetup -Parameters @{ Out = $out } {
            param($Out)
            Write-EsSettings -UserProfile 'C:\Users\test' -OutputPath $Out
            $content = Get-Content -LiteralPath $Out -Raw
            $content | Should -Match 'C:/Users/test/\.emulationstation/slideshow'
            $content | Should -Not -Match '\{\{USERPROFILE\}\}'
        }
    }

    It 'sets ThemeSet to recalbox-backport' {
        $out = Join-Path $script:TempRoot 'es_settings3.cfg'
        InModuleScope EmulationStationSetup -Parameters @{ Out = $out } {
            param($Out)
            Write-EsSettings -UserProfile 'C:\Users\test' -OutputPath $Out
            $content = Get-Content -LiteralPath $Out -Raw
            $content | Should -Match "ThemeSet'\s+value='recalbox-backport'"
        }
    }
}
