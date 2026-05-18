@{
    SchemaVersion = 1
    Downloads = @{
        'fceumm-core' = @{
            Url    = 'https://buildbot.libretro.com/nightly/windows/x86_64/latest/fceumm_libretro.dll.zip'
            # Placeholder hash; replaced with the real SHA-256 in M5 when we wire this through Get-VerifiedDownload.
            Sha256 = '0000000000000000000000000000000000000000000000000000000000000000'
            Kind   = 'LibretroCore'
        }
        'nes-assimilate' = @{
            Url    = 'https://www.nesworld.com/homebrew/assimilate_full.zip'
            Sha256 = '0000000000000000000000000000000000000000000000000000000000000000'
            Kind   = 'Rom'
            System = 'nes'
        }
    }
}
