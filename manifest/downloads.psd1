@{
    SchemaVersion = 1
    Downloads = @{
        'atari2600-halo' = @{
            Url    = 'https://github.com/OpenEmu/OpenEmu-Update/raw/master/Homebrew/2600/Halo%202600/Halo2600_Final.a26'
            Sha256 = 'ba093e70ca756cfb05b44165b2e8cabaf3834ee6ccba37e0293032a7ab02434f'
            Kind   = 'Rom'
            System = 'atari2600'
        }
        'fceumm-core' = @{
            Url    = 'https://buildbot.libretro.com/nightly/windows/x86_64/latest/fceumm_libretro.dll.zip'
            Sha256 = '93b58f5a0778a1680d181d9de3937daa44d18ffef600d00133533eb83ef2d9d8'
            Kind   = 'LibretroCore'
        }
        'gambatte-core' = @{
            Url    = 'https://buildbot.libretro.com/nightly/windows/x86_64/latest/gambatte_libretro.dll.zip'
            Sha256 = 'ed4f9a18795a060970b849d48b3f537af8b1295dcd8e1b245825e04ae6582090'
            Kind   = 'LibretroCore'
        }
        'gba-uranus' = @{
            Url    = 'https://github.com/OpenEmu/OpenEmu-Update/raw/master/Homebrew/GBA/Uranus%20Zero%20EV/uranus0ev_fix.gba'
            Sha256 = 'f142874fcb6a0d679950bbd5586495f056dca8572e5edf2b5a3b53de4eb486b3'
            Kind   = 'Rom'
            System = 'gba'
        }
        'genesis-plus-gx-core' = @{
            Url    = 'https://buildbot.libretro.com/nightly/windows/x86_64/latest/genesis_plus_gx_libretro.dll.zip'
            Sha256 = '1b9a2fab1b468f1eb6fc119a9fd0110103b1f17ebbe0d41f50759675d939ea7d'
            Kind   = 'LibretroCore'
        }
        'genesis-rickdangerous' = @{
            Url    = 'https://github.com/OpenEmu/OpenEmu-Update/raw/master/Homebrew/SG/Rick%20Dangerous/rickdangerous.gen'
            Sha256 = '2ea8e70b2a7299147f2464a4690979a77f78d31e10fb5c45a0637e03b88d7df6'
            Kind   = 'Rom'
            System = 'megadrive'
        }
        'mame-binary' = @{
            Url    = 'https://github.com/mamedev/mame/releases/download/mame0287/mame0287b_x64.exe'
            Sha256 = '68cdaf6d48213c6f3d0f7fa7f2733db46f74e400ad66db2d8a8d777430a42fb9'
            Kind   = 'Emulator'
        }
        'mame-gridlee' = @{
            Url    = 'https://www.mamedev.org/roms/gridlee/gridlee.zip'
            Sha256 = 'df977ceba0ae1c8d0ecf489ae8423390ff5c7c76ce95f5ee6ba9bc892b18056e'
            Kind   = 'Rom'
            System = 'mame'
        }
        'mame-robby' = @{
            Url    = 'https://www.mamedev.org/roms/robby/robby.zip'
            Sha256 = 'd3f7ae3afeeedb7d2476ea05e326a6a6f6e851c969f07a1de36133fcb4d0a8d8'
            Kind   = 'Rom'
            System = 'mame'
        }
        'mame2010-core' = @{
            Url    = 'https://buildbot.libretro.com/nightly/windows/x86_64/latest/mame2010_libretro.dll.zip'
            Sha256 = '855288fe89668c1d4c63a92398586298c85422953d4b3e25851c2fc2fccfb367'
            Kind   = 'LibretroCore'
        }
        'mgba-core' = @{
            Url    = 'https://buildbot.libretro.com/nightly/windows/x86_64/latest/mgba_libretro.dll.zip'
            Sha256 = '4230eb1f439d1cced502af903f35070967b1373bbe6b6f5d818f0071a8fa9e05'
            Kind   = 'LibretroCore'
        }
        'nes-assimilate' = @{
            Url    = 'https://www.nesworld.com/homebrew/assimilate_full.zip'
            Sha256 = '529f8d74456c38a21a6146882465b341ccb082d25d6500a31f29ad3bd5294786'
            Kind   = 'Rom'
            System = 'nes'
        }
        'fmsx-core' = @{
            Url    = 'https://buildbot.libretro.com/nightly/windows/x86_64/latest/fmsx_libretro.dll.zip'
            Sha256 = '0000000000000000000000000000000000000000000000000000000000000000'
            Kind   = 'LibretroCore'
        }
        'msx-bios' = @{
            # Repo-bundled MSX BIOS pack: C-BIOS (Apache) + Microsoft MSX-DOS2/KANJI/FMPAC/PAINTER ROMs.
            # LocalPath bypasses the network — orchestrator copies from repo and hash-verifies.
            LocalPath = 'assets/msx-bios.zip'
            Sha256    = '0679bb9aff8d2462b9519aa45da8618bd151c3995ae494ddc9b43989b77611bf'
            Kind      = 'SystemFile'
        }
        'parallel-n64-core' = @{
            Url    = 'https://buildbot.libretro.com/nightly/windows/x86_64/latest/parallel_n64_libretro.dll.zip'
            Sha256 = '82d61c09c655770d8efe8228661986ad407024d023637c11f95d1fafd385c855'
            Kind   = 'LibretroCore'
        }
        'ps3-firmware' = @{
            Url    = 'https://dus01.ps3.update.playstation.net/update/ps3/image/us/2024_0207_8d3aab90a44a2bc8d0eb46e0bef2ac76/PS3UPDAT.PUP'
            Sha256 = '0000000000000000000000000000000000000000000000000000000000000000'
            Kind   = 'Firmware'
        }
        'rpcs3-binary' = @{
            Url    = 'https://github.com/RPCS3/rpcs3-binaries-win/releases/download/build-67464f97df8679d5d540256987551f34fe00d4cc/rpcs3-v0.0.40-19389-67464f97_win64_msvc.7z'
            Sha256 = '49a71725ca5eff3265f643ac36dbaa0d3beacf144252795b58318a1cd1f222bf'
            Kind   = 'Emulator'
        }
        'sms-brucelee' = @{
            Url    = 'https://github.com/OpenEmu/OpenEmu-Update/raw/master/Homebrew/SMS/Bruce%20Lee/BruceLee-SMS-1.00.sms'
            Sha256 = '95ce932b5f458f85e093bc094db225221da439b9369dca75c28fef099dbf2877'
            Kind   = 'Rom'
            System = 'mastersystem'
        }
        'snes-nwarp' = @{
            Url    = 'https://github.com/OpenEmu/OpenEmu-Update/raw/master/Homebrew/SNES/N-Warp%20Daisakusen/N-Warp%20Daisakusen%20V1.1.smc'
            Sha256 = 'ee928ab95b7075d7c50b4fb01af35a62da3920bdd19b7ffd08686dca9cd54c82'
            Kind   = 'Rom'
            System = 'snes'
        }
        'snes9x-core' = @{
            Url    = 'https://buildbot.libretro.com/nightly/windows/x86_64/latest/snes9x_libretro.dll.zip'
            Sha256 = 'ee5b3bad1d6fafe6070b526528d373894dc392d67d9b613ea58fd105da526fac'
            Kind   = 'LibretroCore'
        }
        'stella-core' = @{
            Url    = 'https://buildbot.libretro.com/nightly/windows/x86_64/latest/stella_libretro.dll.zip'
            Sha256 = 'd6b84268cd633db352fa89dfd5b7f36e096233f7c2fb6d2554a6c0b2863b06c1'
            Kind   = 'LibretroCore'
        }
        'vice-x64-core' = @{
            Url    = 'https://buildbot.libretro.com/nightly/windows/x86_64/latest/vice_x64_libretro.dll.zip'
            Sha256 = 'e68d1049028d221be439f3a3cf07028af059ee0223d58133dfcbbc4465a935e8'
            Kind   = 'LibretroCore'
        }
    }
}

