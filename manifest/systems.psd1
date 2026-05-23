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
        @{
            Name          = 'snes'
            FullName      = 'Super Nintendo Entertainment System'
            RomExtensions = @('.smc', '.sfc', '.fig', '.swc')
            Notes         = 'N-Warp Daisakusen V1.1 (homebrew) used as the bundled ROM.'
            Launcher      = @{
                Kind         = 'Libretro'
                LibretroCore = 'snes9x_libretro.dll'
            }
            Packages      = @('Libretro.RetroArch')
            Artifacts     = @{
                Core     = 'snes9x-core'
                Homebrew = 'snes-nwarp'
            }
        }
        @{
            Name          = 'gb'
            FullName      = 'Nintendo Game Boy'
            RomExtensions = @('.gb')
            Launcher      = @{
                Kind         = 'Libretro'
                LibretroCore = 'gambatte_libretro.dll'
            }
            Packages      = @('Libretro.RetroArch')
            Artifacts     = @{ Core = 'gambatte-core' }
        }
        @{
            Name          = 'gbc'
            FullName      = 'Nintendo Game Boy Color'
            RomExtensions = @('.gbc', '.cgb')
            Launcher      = @{
                Kind         = 'Libretro'
                LibretroCore = 'gambatte_libretro.dll'
            }
            Packages      = @('Libretro.RetroArch')
            Artifacts     = @{ Core = 'gambatte-core' }
        }
        @{
            Name          = 'gba'
            FullName      = 'Nintendo Game Boy Advance'
            RomExtensions = @('.gba', '.agb')
            Notes         = 'Uranus Zero EV (homebrew) used as the bundled ROM.'
            Launcher      = @{
                Kind         = 'Libretro'
                LibretroCore = 'mgba_libretro.dll'
            }
            Packages      = @('Libretro.RetroArch')
            Artifacts     = @{
                Core     = 'mgba-core'
                Homebrew = 'gba-uranus'
            }
        }
        @{
            Name          = 'megadrive'
            FullName      = 'Sega Mega Drive / Genesis'
            RomExtensions = @('.gen', '.md', '.smd', '.bin')
            Notes         = 'Rick Dangerous (homebrew port) used as the bundled ROM.'
            Launcher      = @{
                Kind         = 'Libretro'
                LibretroCore = 'genesis_plus_gx_libretro.dll'
            }
            Packages      = @('Libretro.RetroArch')
            Artifacts     = @{
                Core     = 'genesis-plus-gx-core'
                Homebrew = 'genesis-rickdangerous'
            }
        }
        @{
            Name          = 'mastersystem'
            FullName      = 'Sega Master System'
            RomExtensions = @('.sms')
            Launcher      = @{
                Kind         = 'Libretro'
                LibretroCore = 'genesis_plus_gx_libretro.dll'
            }
            Packages      = @('Libretro.RetroArch')
            Artifacts     = @{ Core = 'genesis-plus-gx-core' }
        }
        @{
            Name          = 'n64'
            FullName      = 'Nintendo 64'
            RomExtensions = @('.n64', '.z64', '.v64')
            Launcher      = @{
                Kind         = 'Libretro'
                LibretroCore = 'parallel_n64_libretro.dll'
            }
            Packages      = @('Libretro.RetroArch')
            Artifacts     = @{ Core = 'parallel-n64-core' }
        }
        @{
            Name          = 'atari2600'
            FullName      = 'Atari 2600'
            RomExtensions = @('.a26', '.bin')
            Launcher      = @{
                Kind         = 'Libretro'
                LibretroCore = 'stella_libretro.dll'
            }
            Packages      = @('Libretro.RetroArch')
            Artifacts     = @{ Core = 'stella-core' }
        }
        @{
            Name          = 'arcade'
            FullName      = 'Arcade (MAME 2010)'
            RomExtensions = @('.zip')
            Launcher      = @{
                Kind         = 'Libretro'
                LibretroCore = 'mame2010_libretro.dll'
            }
            Packages      = @('Libretro.RetroArch')
            Artifacts     = @{ Core = 'mame2010-core' }
        }
        @{
            Name          = 'c64'
            FullName      = 'Commodore 64'
            RomExtensions = @('.d64', '.t64', '.tap', '.prg', '.crt')
            Launcher      = @{
                Kind         = 'Libretro'
                LibretroCore = 'vice_x64_libretro.dll'
            }
            Packages      = @('Libretro.RetroArch')
            Artifacts     = @{ Core = 'vice-x64-core' }
        }

        # ---- Standalone emulators (M7) ----
        @{
            Name          = 'psx'
            FullName      = 'Sony PlayStation'
            RomExtensions = @('.cue', '.iso', '.bin', '.chd', '.pbp', '.img')
            Notes         = 'DuckStation replaces upstream ePSXe 2.0.5.'
            Launcher      = @{
                Kind            = 'Standalone'
                PackageId       = 'Stenzek.DuckStation'
                ExecutableName  = 'duckstation-qt-x64-ReleaseLTCG.exe'
                CommandTemplate = '"%EXE%" -batch -- "%ROM%"'
            }
            Packages      = @('Stenzek.DuckStation')
            Artifacts     = @{}
        }
        @{
            Name          = 'ps2'
            FullName      = 'Sony PlayStation 2'
            RomExtensions = @('.iso', '.chd', '.bin', '.gz')
            Notes         = 'PCSX2-Qt (current branch) replaces upstream PCSX2 1.6.0 (2020).'
            Launcher      = @{
                Kind            = 'Standalone'
                PackageId       = 'PCSX2Team.PCSX2'
                ExecutableName  = 'pcsx2-qt.exe'
                CommandTemplate = '"%EXE%" -batch -fullscreen -- "%ROM%"'
            }
            Packages      = @('PCSX2Team.PCSX2')
            Artifacts     = @{}
        }
        # PS3 (RPCS3) and GC/Wii (Dolphin) entries removed 2026-05-23 — winget upstream broken:
        #   - RPCS3.RPCS3 is not in the public winget repo (no matches at all)
        #   - DolphinEmulator.Dolphin manifest points at dl-mirror.dolphin-emu.org/5.0/dolphin-x64-5.0.exe
        #     which returns HTTP 403 (mirror dropped the 2016 release).
        # Restore both when winget manifests are fixed upstream. The schema and orchestrator support
        # them unchanged — just paste the entries back.
    )
}
