BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force

    # A known payload, hashed once for the whole suite.
    $script:KnownContent = 'verified-download-test-payload-do-not-change'
    $env:EVD_TEST_CONTENT = $script:KnownContent

    $tmp = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmp, $script:KnownContent)
    $script:KnownHash = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash
    Remove-Item -LiteralPath $tmp

    function script:New-TempPath {
        Join-Path ([System.IO.Path]::GetTempPath()) "evd-test-$([guid]::NewGuid().Guid.Substring(0,8))"
    }
}

AfterAll {
    Remove-Item Env:\EVD_TEST_CONTENT -ErrorAction SilentlyContinue
}

Describe 'Get-VerifiedDownload — parameter validation' {
    It 'rejects http:// URL at binding' {
        InModuleScope EmulationStationSetup -Parameters @{ Hash = $script:KnownHash } {
            param($Hash)
            { Get-VerifiedDownload -Uri 'http://example.com/x' -Destination 'C:\nope' -ExpectedSha256 $Hash } |
                Should -Throw -ExpectedMessage '*https*'
        }
    }

    It 'rejects non-hex SHA-256' {
        InModuleScope EmulationStationSetup {
            { Get-VerifiedDownload -Uri 'https://example.com/x' -Destination 'C:\nope' -ExpectedSha256 'not-a-hash' } |
                Should -Throw
        }
    }

    It 'rejects 63-character SHA-256 (one short)' {
        InModuleScope EmulationStationSetup {
            $short = 'a' * 63
            { Get-VerifiedDownload -Uri 'https://example.com/x' -Destination 'C:\nope' -ExpectedSha256 $short } |
                Should -Throw
        }
    }
}

Describe 'Get-VerifiedDownload — happy path' {
    It 'writes file, verifies hash, returns FileInfo' {
        $dest = script:New-TempPath
        try {
            InModuleScope EmulationStationSetup -Parameters @{ Dest = $dest; Hash = $script:KnownHash } {
                param($Dest, $Hash)
                Mock Invoke-WebRequest {
                    [System.IO.File]::WriteAllText($OutFile, $env:EVD_TEST_CONTENT)
                }
                $result = Get-VerifiedDownload -Uri 'https://example.com/x' -Destination $Dest -ExpectedSha256 $Hash
                $result.FullName | Should -Be $Dest
                Test-Path -LiteralPath $Dest | Should -BeTrue
                Should -Invoke Invoke-WebRequest -Times 1
            }
        }
        finally {
            Remove-Item -LiteralPath $dest -ErrorAction SilentlyContinue
        }
    }

    It 'creates the destination directory if it does not exist' {
        $newDir = script:New-TempPath
        $dest   = Join-Path $newDir 'nested\file.bin'
        try {
            InModuleScope EmulationStationSetup -Parameters @{ Dest = $dest; Hash = $script:KnownHash } {
                param($Dest, $Hash)
                Mock Invoke-WebRequest {
                    [System.IO.File]::WriteAllText($OutFile, $env:EVD_TEST_CONTENT)
                }
                $null = Get-VerifiedDownload -Uri 'https://example.com/x' -Destination $Dest -ExpectedSha256 $Hash
                Test-Path -LiteralPath $Dest | Should -BeTrue
            }
        }
        finally {
            Remove-Item -LiteralPath $newDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Get-VerifiedDownload — idempotency' {
    It 'returns existing file without re-downloading when hash matches' {
        $dest = script:New-TempPath
        [System.IO.File]::WriteAllText($dest, $script:KnownContent)
        try {
            InModuleScope EmulationStationSetup -Parameters @{ Dest = $dest; Hash = $script:KnownHash } {
                param($Dest, $Hash)
                Mock Invoke-WebRequest { throw 'should not have been called' }
                $result = Get-VerifiedDownload -Uri 'https://example.com/x' -Destination $Dest -ExpectedSha256 $Hash
                $result.FullName | Should -Be $Dest
                Should -Invoke Invoke-WebRequest -Times 0
            }
        }
        finally {
            Remove-Item -LiteralPath $dest -ErrorAction SilentlyContinue
        }
    }

    It 'replaces existing file when hash does not match' {
        $dest = script:New-TempPath
        [System.IO.File]::WriteAllText($dest, 'wrong-content')
        try {
            InModuleScope EmulationStationSetup -Parameters @{ Dest = $dest; Hash = $script:KnownHash } {
                param($Dest, $Hash)
                Mock Invoke-WebRequest {
                    [System.IO.File]::WriteAllText($OutFile, $env:EVD_TEST_CONTENT)
                }
                $null = Get-VerifiedDownload -Uri 'https://example.com/x' -Destination $Dest -ExpectedSha256 $Hash
                Should -Invoke Invoke-WebRequest -Times 1
                (Get-FileHash -LiteralPath $Dest -Algorithm SHA256).Hash | Should -Be $Hash
            }
        }
        finally {
            Remove-Item -LiteralPath $dest -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Get-VerifiedDownload — hash mismatch' {
    It 'throws and removes partial when downloaded bytes have wrong hash' {
        $dest = script:New-TempPath
        try {
            InModuleScope EmulationStationSetup -Parameters @{ Dest = $dest; Hash = $script:KnownHash } {
                param($Dest, $Hash)
                Mock Invoke-WebRequest {
                    [System.IO.File]::WriteAllText($OutFile, 'something-different')
                }
                { Get-VerifiedDownload -Uri 'https://example.com/x' -Destination $Dest -ExpectedSha256 $Hash } |
                    Should -Throw -ExpectedMessage '*SHA-256 mismatch*'

                Test-Path -LiteralPath $Dest             | Should -BeFalse
                Test-Path -LiteralPath "$Dest.partial"   | Should -BeFalse
            }
        }
        finally {
            Remove-Item -LiteralPath $dest -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath "$dest.partial" -ErrorAction SilentlyContinue
        }
    }

    It 'does NOT retry on hash mismatch (calls IWR exactly once)' {
        $dest = script:New-TempPath
        try {
            InModuleScope EmulationStationSetup -Parameters @{ Dest = $dest; Hash = $script:KnownHash } {
                param($Dest, $Hash)
                Mock Invoke-WebRequest {
                    [System.IO.File]::WriteAllText($OutFile, 'wrong')
                }
                Mock Start-Sleep { }
                { Get-VerifiedDownload -Uri 'https://example.com/x' -Destination $Dest -ExpectedSha256 $Hash -RetryCount 5 } |
                    Should -Throw -ExpectedMessage '*SHA-256 mismatch*'
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly
                Should -Invoke Start-Sleep -Times 0
            }
        }
        finally {
            Remove-Item -LiteralPath $dest -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath "$dest.partial" -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Get-VerifiedDownload — retry behavior' {
    It 'retries on network error and succeeds on a later attempt' {
        $dest = script:New-TempPath
        try {
            InModuleScope EmulationStationSetup -Parameters @{ Dest = $dest; Hash = $script:KnownHash } {
                param($Dest, $Hash)
                $script:attempt = 0
                Mock Invoke-WebRequest {
                    $script:attempt++
                    if ($script:attempt -lt 2) {
                        throw [System.Net.Http.HttpRequestException]::new('simulated transient')
                    }
                    [System.IO.File]::WriteAllText($OutFile, $env:EVD_TEST_CONTENT)
                }
                Mock Start-Sleep { }
                $result = Get-VerifiedDownload -Uri 'https://example.com/x' -Destination $Dest -ExpectedSha256 $Hash -RetryCount 3
                $result.FullName | Should -Be $Dest
                Should -Invoke Invoke-WebRequest -Times 2
            }
        }
        finally {
            Remove-Item -LiteralPath $dest -ErrorAction SilentlyContinue
        }
    }

    It 'throws after all retries exhausted' {
        $dest = script:New-TempPath
        try {
            InModuleScope EmulationStationSetup -Parameters @{ Dest = $dest; Hash = $script:KnownHash } {
                param($Dest, $Hash)
                Mock Invoke-WebRequest {
                    throw [System.Net.Http.HttpRequestException]::new('always fails')
                }
                Mock Start-Sleep { }
                { Get-VerifiedDownload -Uri 'https://example.com/x' -Destination $Dest -ExpectedSha256 $Hash -RetryCount 3 } |
                    Should -Throw -ExpectedMessage '*after 3 attempts*'
                Should -Invoke Invoke-WebRequest -Times 3 -Exactly
            }
        }
        finally {
            Remove-Item -LiteralPath $dest -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath "$dest.partial" -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Get-VerifiedDownload — size cap' {
    It 'rejects oversize download and removes partial' {
        $dest = script:New-TempPath
        try {
            InModuleScope EmulationStationSetup -Parameters @{ Dest = $dest; Hash = $script:KnownHash } {
                param($Dest, $Hash)
                Mock Invoke-WebRequest {
                    # Write 2 MB of bytes — exceeds a 1 MB cap below
                    $bytes = [byte[]]::new(2MB)
                    [System.IO.File]::WriteAllBytes($OutFile, $bytes)
                }
                Mock Start-Sleep { }
                { Get-VerifiedDownload -Uri 'https://example.com/x' -Destination $Dest -ExpectedSha256 $Hash -MaxSizeMB 1 } |
                    Should -Throw -ExpectedMessage '*exceeds cap of 1 MB*'

                Test-Path -LiteralPath $Dest           | Should -BeFalse
                Test-Path -LiteralPath "$Dest.partial" | Should -BeFalse
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly
            }
        }
        finally {
            Remove-Item -LiteralPath $dest -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath "$dest.partial" -ErrorAction SilentlyContinue
        }
    }
}
