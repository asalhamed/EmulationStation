# Project context & glossary

## What this project is
A PowerShell 7+ module that installs and configures [EmulationStation](https://emulationstation.org/) on Windows 10/11, with ~15 emulated game systems wired up end-to-end. It replaces the upstream [Francommit/win10_emulation_station](https://github.com/Francommit/win10_emulation_station) installer.

## Why a rewrite (not a PR)
Upstream is a single ~700-line PowerShell script with 24 catalogued defects (see `reference/analysis.md`), including security holes (disabled TLS validation, no download verification) and reliability holes (GUI-driven config bootstrap, hardcoded binary paths, copy-pasted per-system logic). Fixing these in place would mean rewriting most of the file anyway.

## Domain glossary

| Term | Meaning |
|---|---|
| **EmulationStation (ES)** | The frontend. Lists "systems" (NES, SNES, etc.), launches the configured emulator binary when the user picks a ROM. Reads `es_systems.cfg` to know which binaries to launch and `es_settings.cfg` for global options. Lives at `%USERPROFILE%\.emulationstation\`. |
| **System** | One emulated platform (e.g., `nes`, `snes`, `gba`). In our manifest, each system has a name, ROM extensions, a launcher template, and a theme name. |
| **Emulator** | The binary that actually runs the game (Dolphin, RPCS3, PPSSPP, etc.). Some systems share an emulator (RetroArch covers a dozen). |
| **RetroArch** | A multi-system emulator frontend that loads **libretro cores** (DLLs) for individual platforms. We use it for everything 6th-gen and earlier. |
| **Libretro core** | A DLL that implements a single platform inside RetroArch (`fceumm_libretro.dll` = NES, `snes9x_libretro.dll` = SNES, etc.). Distributed by the [libretro buildbot](https://buildbot.libretro.com/). |
| **Console-specific emulator** | An emulator we use *instead* of a libretro core because the standalone is materially better — Dolphin for GC/Wii, RPCS3 for PS3, etc. |
| **Theme** | XML/SVG assets that style the ES UI per system. We use `recalbox-backport`. |
| **ROM** | The game file the emulator loads. We only ever bundle public-domain / homebrew ROMs. BIOS files (e.g., PSX SCPH1001) are NOT bundled — the user supplies them. |
| **Scraper** | A separate tool that fetches box art + metadata for ROMs in the user's library. Upstream bundles `sselph/scraper`; we'll document but not auto-run it. |
| **Manifest** | Our PSD1 declaration of every system / package / download. Code reads the manifest; adding a system means editing the manifest, not the code. |
| **Install log** | An append-only JSONL file (`install.log.jsonl`) recording every filesystem and shortcut action the installer takes. The uninstaller replays it in reverse. |

## Versions of things we care about

| Component | Pin / minimum |
|---|---|
| PowerShell | 7.4+ |
| Windows | 10 build 1809+ (winget requirement), 11 supported |
| `winget` | 1.6+ (JSON output stable) |
| Pester | 5.x (test framework) |
| RetroArch | Latest stable (versioned by SHA in manifest) |
| EmulationStation | jrassa Windows build (community-maintained Windows port) |

## What we deliberately don't do
- Don't ship BIOS files (copyright).
- Don't bundle non-public-domain ROMs.
- Don't auto-update — installs are deterministic from the manifest. Updates = `git pull && re-run`.
- Don't try to manage the user's existing emulators if they had any pre-installed — we install our own, side-by-side.
- Don't enable a scraper by default. It hammers TheGamesDB and the upstream tool is unmaintained.
