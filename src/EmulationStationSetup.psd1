@{
    RootModule           = 'EmulationStationSetup.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'c8f3e8a1-2b4d-4e6f-9a1b-3c5d7e9f1a2b'
    Author               = 'asalh'
    CompanyName          = 'Personal'
    Copyright            = '(c) 2026'
    Description          = 'Installs and configures EmulationStation with ~15 emulated systems on Windows 10/11.'

    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')

    FunctionsToExport    = @(
        'Get-EmulationStationManifest'
        'Install-EmulationStation'
        'Test-EmulationStationInstall'
        'Uninstall-EmulationStation'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('EmulationStation', 'Emulator', 'Retro', 'Windows')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = ''
            ReleaseNotes = 'See CHANGELOG.md'
        }
    }
}
