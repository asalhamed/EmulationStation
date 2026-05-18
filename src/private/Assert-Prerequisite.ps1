function Assert-Prerequisite {
    [CmdletBinding()]
    [OutputType([PreflightCheck[]])]
    param(
        [string[]] $Skip = @()
    )

    $checks = [System.Collections.Generic.List[PreflightCheck]]::new()

    if ('PowerShell' -notin $Skip) {
        $required = [version]'7.4'
        $current  = $PSVersionTable.PSVersion
        if ($current -ge $required) {
            $checks.Add([PreflightCheck]::new('PowerShell', 'Pass', "PS $current"))
        }
        else {
            $checks.Add([PreflightCheck]::new(
                'PowerShell', 'Fail',
                "PS $current (need >= $required)",
                'Run: winget install Microsoft.PowerShell'
            ))
        }
    }

    if ('Windows' -notin $Skip) {
        $minBuild = 17763
        $build    = [Environment]::OSVersion.Version.Build
        if ($build -ge $minBuild) {
            $checks.Add([PreflightCheck]::new('Windows', 'Pass', "Build $build"))
        }
        else {
            $checks.Add([PreflightCheck]::new(
                'Windows', 'Fail',
                "Build $build (need >= $minBuild for winget)",
                'Update Windows via Settings > Windows Update.'
            ))
        }
    }

    if ('WinGet' -notin $Skip) {
        $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $wingetCmd) {
            $checks.Add([PreflightCheck]::new(
                'WinGet', 'Fail',
                'winget not found on PATH',
                'Install App Installer from the Microsoft Store.'
            ))
        }
        else {
            try {
                $rawVersion    = (& winget --version 2>$null).Trim().TrimStart('v')
                $wingetVersion = [version]($rawVersion -replace '-.+$')
                $minWinGet     = [version]'1.6'
                if ($wingetVersion -ge $minWinGet) {
                    $checks.Add([PreflightCheck]::new('WinGet', 'Pass', "v$rawVersion"))
                }
                else {
                    $checks.Add([PreflightCheck]::new(
                        'WinGet', 'Fail',
                        "v$rawVersion (need >= $minWinGet)",
                        'Update App Installer from the Microsoft Store.'
                    ))
                }
            }
            catch {
                $checks.Add([PreflightCheck]::new(
                    'WinGet', 'Warn',
                    "Could not parse 'winget --version' output: $_",
                    ''
                ))
            }
        }
    }

    if ('Disk' -notin $Skip) {
        $drive     = $env:SystemDrive.TrimEnd(':')
        $freeBytes = (Get-PSDrive -Name $drive -ErrorAction SilentlyContinue).Free
        $freeGB    = if ($freeBytes) { [math]::Round($freeBytes / 1GB, 1) } else { 0 }
        $minGB     = 10
        if ($freeGB -ge $minGB) {
            $checks.Add([PreflightCheck]::new('Disk', 'Pass', "$freeGB GB free on $env:SystemDrive"))
        }
        else {
            $checks.Add([PreflightCheck]::new(
                'Disk', 'Fail',
                "$freeGB GB free on $env:SystemDrive (need >= $minGB)",
                'Free up space on the system drive before installing.'
            ))
        }
    }

    if ('Network' -notin $Skip) {
        $reachable = try {
            $null = Invoke-WebRequest -Uri 'https://github.com' -Method Head -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
            $true
        }
        catch {
            $false
        }
        if ($reachable) {
            $checks.Add([PreflightCheck]::new('Network', 'Pass', 'github.com reachable over HTTPS'))
        }
        else {
            $checks.Add([PreflightCheck]::new(
                'Network', 'Warn',
                'github.com HEAD request did not succeed within 5s',
                'Check firewall / proxy settings if installs fail later.'
            ))
        }
    }

    , $checks.ToArray()
}
