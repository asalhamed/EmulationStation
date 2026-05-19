BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force

    $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("udh-test-" + [guid]::NewGuid().Guid.Substring(0,8))
    New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null

    $script:DownloadsPath = Join-Path $script:TempRoot 'downloads.psd1'
}

AfterAll {
    Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Update-DownloadHashes' {
    It 'replaces placeholder hash with computed hash and writes new manifest' {
        $initial = @"
@{
    SchemaVersion = 1
    Downloads = @{
        'foo-core' = @{
            Url    = 'https://example.com/foo.zip'
            Sha256 = '$('0' * 64)'
            Kind   = 'LibretroCore'
        }
    }
}
"@
        Set-Content -LiteralPath $script:DownloadsPath -Value $initial

        InModuleScope EmulationStationSetup -Parameters @{ R = $script:TempRoot } {
            param($R)
            Mock Get-RemoteFileHash { 'deadbeef' * 8 } -ParameterFilter { $Uri -eq 'https://example.com/foo.zip' }
            Update-DownloadHashes -ManifestRoot $R
        }

        $written = Get-Content -LiteralPath $script:DownloadsPath -Raw
        $written | Should -Match "Sha256\s+=\s+'$('deadbeef' * 8)'"
        $written | Should -Not -Match "Sha256\s+=\s+'$('0' * 64)'"
    }

    It '-Force refreshes a hash that is already non-placeholder' {
        $initial = @"
@{
    SchemaVersion = 1
    Downloads = @{
        'foo-core' = @{
            Url    = 'https://example.com/foo.zip'
            Sha256 = '$('a' * 64)'
            Kind   = 'LibretroCore'
        }
    }
}
"@
        Set-Content -LiteralPath $script:DownloadsPath -Value $initial

        InModuleScope EmulationStationSetup -Parameters @{ R = $script:TempRoot } {
            param($R)
            Mock Get-RemoteFileHash { 'cafebabe' * 8 } -ParameterFilter { $Uri -eq 'https://example.com/foo.zip' }
            Update-DownloadHashes -ManifestRoot $R -Force
        }

        $written = Get-Content -LiteralPath $script:DownloadsPath -Raw
        $written | Should -Match "Sha256\s+=\s+'$('cafebabe' * 8)'"
    }
}
