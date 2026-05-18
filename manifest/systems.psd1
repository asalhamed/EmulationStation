@{
    SchemaVersion = 1
    Systems = @(
        @{
            Name          = 'nes'
            FullName      = 'Nintendo Entertainment System'
            RomExtensions = @('.nes', '.fds', '.unif', '.unf')
            Notes         = 'Homebrew compilation by Wave 5 (NES) used as the bundled ROM.'
            Launcher      = @{
                Kind         = 'Libretro'
                LibretroCore = 'fceumm_libretro.dll'
            }
            Packages      = @('Libretro.RetroArch')
            Artifacts     = @{
                Core     = 'fceumm-core'
                Homebrew = 'nes-assimilate'
            }
        }
    )
}
