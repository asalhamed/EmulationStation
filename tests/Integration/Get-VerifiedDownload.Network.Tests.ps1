BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force
}

Describe 'Get-VerifiedDownload over the real network' -Tag 'Network' {
    It 'downloads a small public file and verifies its hash end-to-end' {
        # Stable, tiny public artifact: GitHub Octocat content via Microsoft Learn ASCII art is too volatile,
        # so we use a self-discover pattern — fetch once to learn the current hash, then test the verifier
        # against that hash. This exercises real DNS, TLS, redirects, and SHA-256 verification on real bytes.
        $url     = 'https://raw.githubusercontent.com/PowerShell/PowerShell/master/LICENSE.txt'
        $discoverPath = Join-Path ([System.IO.Path]::GetTempPath()) "evd-discover-$([guid]::NewGuid().Guid.Substring(0,8))"
        try {
            Invoke-WebRequest -Uri $url -OutFile $discoverPath -UseBasicParsing -TimeoutSec 30
            $hash = (Get-FileHash -LiteralPath $discoverPath -Algorithm SHA256).Hash
            Remove-Item -LiteralPath $discoverPath -Force

            $dest = Join-Path ([System.IO.Path]::GetTempPath()) "evd-network-$([guid]::NewGuid().Guid.Substring(0,8))"
            try {
                $result = InModuleScope EmulationStationSetup -Parameters @{ U = $url; D = $dest; H = $hash } {
                    param($U, $D, $H)
                    Get-VerifiedDownload -Uri $U -Destination $D -ExpectedSha256 $H
                }
                $result.FullName | Should -Be $dest
                (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash | Should -Be $hash
            }
            finally {
                Remove-Item -LiteralPath $dest -ErrorAction SilentlyContinue
            }
        }
        catch {
            if ($_.Exception.Message -match 'unable|timeout|could not resolve|connection') {
                Set-ItResult -Skipped -Because "network not reachable: $($_.Exception.Message)"
                return
            }
            throw
        }
    }
}
