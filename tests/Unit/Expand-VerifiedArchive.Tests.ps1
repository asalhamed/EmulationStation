BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force

    $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("eva-test-" + [guid]::NewGuid().Guid.Substring(0,8))
    New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null

    # Create a known .zip with a known file inside
    $stageDir = Join-Path $script:TempRoot 'stage'
    New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $stageDir 'hello.txt') -Value 'hello world'
    $script:KnownZip = Join-Path $script:TempRoot 'sample.zip'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($stageDir, $script:KnownZip)
}

AfterAll {
    Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Expand-VerifiedArchive' {
    It 'extracts a .zip to the destination' {
        $dest = Join-Path $script:TempRoot 'out-zip'
        InModuleScope EmulationStationSetup -Parameters @{ Z = $script:KnownZip; D = $dest } {
            param($Z, $D)
            Expand-VerifiedArchive -Path $Z -Destination $D
            Test-Path -LiteralPath (Join-Path $D 'hello.txt') | Should -BeTrue
            (Get-Content -LiteralPath (Join-Path $D 'hello.txt') -Raw).Trim() | Should -Be 'hello world'
        }
    }

    It 'throws when the input file is missing' {
        InModuleScope EmulationStationSetup {
            { Expand-VerifiedArchive -Path 'C:\does-not-exist.zip' -Destination 'C:\out' } |
                Should -Throw -ExpectedMessage '*not found*'
        }
    }

    It 'throws on unsupported archive extension' {
        $bogus = Join-Path $script:TempRoot 'bogus.tar.gz'
        Set-Content -LiteralPath $bogus -Value 'not really'
        InModuleScope EmulationStationSetup -Parameters @{ B = $bogus } {
            param($B)
            { Expand-VerifiedArchive -Path $B -Destination 'C:\out' } |
                Should -Throw -ExpectedMessage '*Unsupported archive extension*'
        }
    }
}
