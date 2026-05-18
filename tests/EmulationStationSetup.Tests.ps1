BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\src\EmulationStationSetup.psd1'
}

Describe 'Module' {
    It 'imports without error' {
        { Import-Module $script:ModuleManifest -Force } | Should -Not -Throw
    }

    It 'exports exactly the expected public cmdlets' {
        Import-Module $script:ModuleManifest -Force
        $expected = @(
            'Get-EmulationStationManifest'
            'Install-EmulationStation'
            'Test-EmulationStationInstall'
            'Uninstall-EmulationStation'
        ) | Sort-Object
        $actual = (Get-Module EmulationStationSetup).ExportedFunctions.Keys | Sort-Object
        $actual | Should -BeExactly $expected
    }

    It 'has a valid module manifest' {
        Test-ModuleManifest -Path $script:ModuleManifest | Should -Not -BeNullOrEmpty
    }
}
