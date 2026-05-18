#Requires -Version 7.4
[CmdletBinding()]
param(
    [ValidateSet('All', 'Unit', 'Integration', 'Smoke')]
    [string] $Scope = 'All'
)

$ErrorActionPreference = 'Stop'

$pester = Get-Module -ListAvailable -Name Pester | Where-Object Version -GE '5.0.0' | Select-Object -First 1
if (-not $pester) {
    throw "Pester 5+ is required. Run: Install-Module Pester -Scope CurrentUser -MinimumVersion 5.0"
}

Import-Module Pester -MinimumVersion 5.0

$paths = switch ($Scope) {
    'Unit'        { @((Join-Path $PSScriptRoot 'Unit')) }
    'Integration' { @((Join-Path $PSScriptRoot 'Integration')) }
    'Smoke'       { @((Join-Path $PSScriptRoot 'EmulationStationSetup.Tests.ps1')) }
    'All'         {
        @(
            (Join-Path $PSScriptRoot 'EmulationStationSetup.Tests.ps1')
            (Join-Path $PSScriptRoot 'Unit')
            (Join-Path $PSScriptRoot 'Integration')
        )
    }
}

$config = New-PesterConfiguration
$config.Run.Path = $paths
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'

Invoke-Pester -Configuration $config
