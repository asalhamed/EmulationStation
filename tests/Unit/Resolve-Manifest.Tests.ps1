BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force

    $script:Root = Join-Path ([System.IO.Path]::GetTempPath()) ("es-manifest-test-" + [guid]::NewGuid().Guid.Substring(0,8))
    New-Item -ItemType Directory -Path $script:Root -Force | Out-Null

    function script:Write-Manifests([hashtable] $Systems, [hashtable] $Downloads) {
        $sysSchemaVer = if ($Systems.SchemaVersion) { $Systems.SchemaVersion } else { 1 }
        $dlSchemaVer  = if ($Downloads.SchemaVersion) { $Downloads.SchemaVersion } else { 1 }
        $sysPsd1 = @"
@{
    SchemaVersion = $sysSchemaVer
    Systems = @(
$($Systems.Body)
    )
}
"@
        $dlPsd1 = @"
@{
    SchemaVersion = $dlSchemaVer
    Downloads = @{
$($Downloads.Body)
    }
}
"@
        Set-Content -LiteralPath (Join-Path $script:Root 'systems.psd1')   -Value $sysPsd1
        Set-Content -LiteralPath (Join-Path $script:Root 'downloads.psd1') -Value $dlPsd1
    }

    $script:ValidDownloadBody = @"
        'fceumm-core' = @{
            Url    = 'https://buildbot.libretro.com/x/fceumm.zip'
            Sha256 = '$('a' * 64)'
            Kind   = 'LibretroCore'
        }
"@
    $script:ValidSystemBody = @"
        @{
            Name          = 'nes'
            FullName      = 'Nintendo Entertainment System'
            RomExtensions = @('.nes')
            Launcher      = @{ Kind = 'Libretro'; LibretroCore = 'fceumm_libretro.dll' }
            Packages      = @('Libretro.RetroArch')
            Artifacts     = @{ Core = 'fceumm-core' }
        }
"@
}

AfterAll {
    Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-Manifest - happy path' {
    It 'parses a valid manifest and returns typed objects' {
        script:Write-Manifests @{ Body = $script:ValidSystemBody } @{ Body = $script:ValidDownloadBody }
        InModuleScope EmulationStationSetup -Parameters @{ R = $script:Root } {
            param($R)
            $m = Resolve-Manifest -ManifestRoot $R
            $m.Systems.Count               | Should -Be 1
            $m.Downloads.Count             | Should -Be 1
            $m.Systems[0].GetType().Name   | Should -Be 'EmulatorSystem'
            $m.Downloads[0].GetType().Name | Should -Be 'DownloadSpec'
        }
    }

    It 'defaults Platform = Name when unset' {
        script:Write-Manifests @{ Body = $script:ValidSystemBody } @{ Body = $script:ValidDownloadBody }
        InModuleScope EmulationStationSetup -Parameters @{ R = $script:Root } {
            param($R)
            (Resolve-Manifest -ManifestRoot $R).Systems[0].Platform | Should -Be 'nes'
        }
    }
}

Describe 'Resolve-Manifest - schema version errors' {
    It 'throws when SchemaVersion is missing on systems.psd1' {
        $bad = "@{ Systems = @() }"
        Set-Content -LiteralPath (Join-Path $script:Root 'systems.psd1') -Value $bad
        Set-Content -LiteralPath (Join-Path $script:Root 'downloads.psd1') -Value "@{ SchemaVersion = 1; Downloads = @{} }"
        InModuleScope EmulationStationSetup -Parameters @{ R = $script:Root } {
            param($R)
            { Resolve-Manifest -ManifestRoot $R } | Should -Throw -ExpectedMessage '*SchemaVersion*'
        }
    }

    It 'throws when SchemaVersion is 999 (unsupported)' {
        Set-Content -LiteralPath (Join-Path $script:Root 'systems.psd1') -Value "@{ SchemaVersion = 999; Systems = @() }"
        Set-Content -LiteralPath (Join-Path $script:Root 'downloads.psd1') -Value "@{ SchemaVersion = 1; Downloads = @{} }"
        InModuleScope EmulationStationSetup -Parameters @{ R = $script:Root } {
            param($R)
            { Resolve-Manifest -ManifestRoot $R } | Should -Throw -ExpectedMessage '*999*'
        }
    }

    It 'throws when manifest file does not exist' {
        InModuleScope EmulationStationSetup {
            $missing = Join-Path ([System.IO.Path]::GetTempPath()) ('does-not-exist-' + [guid]::NewGuid())
            { Resolve-Manifest -ManifestRoot $missing } | Should -Throw -ExpectedMessage '*not found*'
        }
    }
}

Describe 'Resolve-Manifest - system validation errors' {
    It 'throws when system Name is missing' {
        $body = @"
        @{
            FullName = 'X'
            RomExtensions = @('.x')
            Launcher = @{ Kind = 'Libretro'; LibretroCore = 'x.dll' }
            Artifacts = @{}
        }
"@
        script:Write-Manifests @{ Body = $body } @{ Body = '' }
        InModuleScope EmulationStationSetup -Parameters @{ R = $script:Root } {
            param($R)
            { Resolve-Manifest -ManifestRoot $R } | Should -Throw -ExpectedMessage '*Name is required*'
        }
    }

    It 'throws when system Name has uppercase' {
        $body = @"
        @{
            Name = 'NES'
            FullName = 'X'
            RomExtensions = @('.x')
            Launcher = @{ Kind = 'Libretro'; LibretroCore = 'x.dll' }
            Artifacts = @{}
        }
"@
        script:Write-Manifests @{ Body = $body } @{ Body = '' }
        InModuleScope EmulationStationSetup -Parameters @{ R = $script:Root } {
            param($R)
            { Resolve-Manifest -ManifestRoot $R } | Should -Throw -ExpectedMessage '*NES*'
        }
    }

    It 'throws on duplicate system Names' {
        $body = @"
        @{
            Name = 'nes'; FullName = 'X1'; RomExtensions = @('.x')
            Launcher = @{ Kind = 'Libretro'; LibretroCore = 'x.dll' }
            Artifacts = @{}
        }
        @{
            Name = 'nes'; FullName = 'X2'; RomExtensions = @('.x')
            Launcher = @{ Kind = 'Libretro'; LibretroCore = 'x.dll' }
            Artifacts = @{}
        }
"@
        script:Write-Manifests @{ Body = $body } @{ Body = '' }
        InModuleScope EmulationStationSetup -Parameters @{ R = $script:Root } {
            param($R)
            { Resolve-Manifest -ManifestRoot $R } | Should -Throw -ExpectedMessage '*duplicate*'
        }
    }

    It 'throws when RomExtension has no leading dot' {
        $body = @"
        @{
            Name = 'nes'; FullName = 'X'; RomExtensions = @('nes')
            Launcher = @{ Kind = 'Libretro'; LibretroCore = 'x.dll' }
            Artifacts = @{}
        }
"@
        script:Write-Manifests @{ Body = $body } @{ Body = '' }
        InModuleScope EmulationStationSetup -Parameters @{ R = $script:Root } {
            param($R)
            { Resolve-Manifest -ManifestRoot $R } | Should -Throw -ExpectedMessage '*leading dot*'
        }
    }

    It 'throws on unknown Launcher.Kind' {
        $body = @"
        @{
            Name = 'nes'; FullName = 'X'; RomExtensions = @('.x')
            Launcher = @{ Kind = 'Bogus' }
            Artifacts = @{}
        }
"@
        script:Write-Manifests @{ Body = $body } @{ Body = '' }
        InModuleScope EmulationStationSetup -Parameters @{ R = $script:Root } {
            param($R)
            { Resolve-Manifest -ManifestRoot $R } | Should -Throw -ExpectedMessage '*Libretro*Standalone*'
        }
    }

    It 'throws on Libretro launcher missing LibretroCore' {
        $body = @"
        @{
            Name = 'nes'; FullName = 'X'; RomExtensions = @('.x')
            Launcher = @{ Kind = 'Libretro' }
            Artifacts = @{}
        }
"@
        script:Write-Manifests @{ Body = $body } @{ Body = '' }
        InModuleScope EmulationStationSetup -Parameters @{ R = $script:Root } {
            param($R)
            { Resolve-Manifest -ManifestRoot $R } | Should -Throw -ExpectedMessage '*LibretroCore is required*'
        }
    }

    It 'throws on Standalone launcher missing PackageId' {
        $body = @"
        @{
            Name = 'psx'; FullName = 'PSX'; RomExtensions = @('.cue')
            Launcher = @{ Kind = 'Standalone'; ExecutableName = 'x.exe'; CommandTemplate = '%EXE% %ROM%' }
            Artifacts = @{}
        }
"@
        script:Write-Manifests @{ Body = $body } @{ Body = '' }
        InModuleScope EmulationStationSetup -Parameters @{ R = $script:Root } {
            param($R)
            { Resolve-Manifest -ManifestRoot $R } | Should -Throw -ExpectedMessage '*PackageId is required*'
        }
    }

    It 'throws when Artifact references a missing download' {
        $body = @"
        @{
            Name = 'nes'; FullName = 'X'; RomExtensions = @('.x')
            Launcher = @{ Kind = 'Libretro'; LibretroCore = 'x.dll' }
            Artifacts = @{ Core = 'does-not-exist' }
        }
"@
        script:Write-Manifests @{ Body = $body } @{ Body = $script:ValidDownloadBody }
        InModuleScope EmulationStationSetup -Parameters @{ R = $script:Root } {
            param($R)
            { Resolve-Manifest -ManifestRoot $R } | Should -Throw -ExpectedMessage "*'does-not-exist'*"
        }
    }
}

Describe 'Resolve-Manifest - download validation errors' {
    It 'throws on http URL in downloads' {
        $bad = @"
        'foo' = @{
            Url    = 'http://example.com/x'
            Sha256 = '$('a' * 64)'
            Kind   = 'LibretroCore'
        }
"@
        script:Write-Manifests @{ Body = $script:ValidSystemBody } @{ Body = $bad }
        InModuleScope EmulationStationSetup -Parameters @{ R = $script:Root } {
            param($R)
            { Resolve-Manifest -ManifestRoot $R } | Should -Throw -ExpectedMessage '*https*'
        }
    }

    It 'throws on non-hex Sha256 in downloads' {
        $bad = @"
        'foo' = @{
            Url    = 'https://example.com/x'
            Sha256 = 'not-a-hash'
            Kind   = 'LibretroCore'
        }
"@
        script:Write-Manifests @{ Body = $script:ValidSystemBody } @{ Body = $bad }
        InModuleScope EmulationStationSetup -Parameters @{ R = $script:Root } {
            param($R)
            { Resolve-Manifest -ManifestRoot $R } | Should -Throw -ExpectedMessage '*Sha256*hex*'
        }
    }

    It 'throws on Rom-kind download missing System' {
        $bad = @"
        'foo' = @{
            Url    = 'https://example.com/x'
            Sha256 = '$('a' * 64)'
            Kind   = 'Rom'
        }
"@
        script:Write-Manifests @{ Body = $script:ValidSystemBody } @{ Body = $bad }
        InModuleScope EmulationStationSetup -Parameters @{ R = $script:Root } {
            param($R)
            { Resolve-Manifest -ManifestRoot $R } | Should -Throw -ExpectedMessage '*System is required*'
        }
    }
}
