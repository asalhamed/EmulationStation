BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force

    $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('es-manifest-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
}

AfterAll {
    Remove-Item $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-Manifest' {
    It 'returns hashtable when manifest is valid' {
        $valid = Join-Path $script:TempRoot 'valid.psd1'
        Set-Content $valid -Value "@{ SchemaVersion = 1; Systems = @() }"
        InModuleScope EmulationStationSetup -Parameters @{ Path = $valid } {
            param($Path)
            (Resolve-Manifest -Path $Path).SchemaVersion | Should -Be 1
        }
    }

    It 'throws when SchemaVersion is missing' {
        $bad = Join-Path $script:TempRoot 'no-schema.psd1'
        Set-Content $bad -Value "@{ Systems = @() }"
        InModuleScope EmulationStationSetup -Parameters @{ Path = $bad } {
            param($Path)
            { Resolve-Manifest -Path $Path } | Should -Throw -ExpectedMessage '*SchemaVersion*'
        }
    }

    It 'throws when manifest does not exist' {
        $missing = Join-Path $script:TempRoot 'missing.psd1'
        InModuleScope EmulationStationSetup -Parameters @{ Path = $missing } {
            param($Path)
            { Resolve-Manifest -Path $Path } | Should -Throw -ExpectedMessage '*not found*'
        }
    }

    It 'throws when SchemaVersion is unsupported' {
        $future = Join-Path $script:TempRoot 'future.psd1'
        Set-Content $future -Value "@{ SchemaVersion = 999 }"
        InModuleScope EmulationStationSetup -Parameters @{ Path = $future } {
            param($Path)
            { Resolve-Manifest -Path $Path } | Should -Throw -ExpectedMessage '*999*'
        }
    }
}
