# EmulationStation Setup for Windows

A PowerShell 7 module that installs and configures [EmulationStation](https://emulationstation.org/) with **16 emulated systems** on Windows 10/11. Security- and reliability-focused rewrite of [Francommit/win10_emulation_station](https://github.com/Francommit/win10_emulation_station).

**Version:** v0.1.0 — first public cut. See [CHANGELOG.md](CHANGELOG.md) for the full change list.

## What's different from upstream

Upstream's single `prepare.ps1` is replaced by a structured module with hard guarantees:

- **HTTPS-only with SHA-256 verification.** No `TrustAllCertsPolicy`, no `-SkipCertificateCheck`, no plain `http://`. Every downloaded byte is hash-pinned in [manifest/downloads.psd1](manifest/downloads.psd1).
- **winget instead of Chocolatey+Scoop.** No third-party package-manager bootstraps, no `iex` over the network. winget is built in.
- **No GUI bootstrap.** Configs (`es_systems.cfg`, `es_settings.cfg`, `dolphin.ini`) are rendered directly from templates. No launching ES + sleeping 60s + force-killing.
- **Idempotent throughout.** Re-running is safe at every layer: downloader, winget install, archive extract, config render.
- **Aggregated failures.** One broken artifact doesn't abort the install — failures land in a summary, the rest proceeds.
- **Append-only install log + uninstaller.** Anything we put on the box, `Uninstall-EmulationStation` can take back off.
- **Data-driven manifest.** Adding or removing a system is a `.psd1` edit, not a code change.

All 24 defects catalogued in [reference/analysis.md](reference/analysis.md) are addressed. See [docs/adr/](docs/adr/) for the load-bearing design decisions.

## Supported systems (16)

| Kind | Systems |
|---|---|
| Libretro (RetroArch + cores) | nes, snes, gb, gbc, gba, megadrive, mastersystem, n64, atari2600, arcade (MAME 2010), c64 |
| Standalone | psx (DuckStation), ps2 (PCSX2-Qt), ps3 (RPCS3), gc + wii (Dolphin) |

Adding a system is a manifest edit — see [manifest/systems.psd1](manifest/systems.psd1) for examples.

## Requirements

- Windows 10 build 1809+ or Windows 11
- PowerShell 7.4+ — `winget install Microsoft.PowerShell`
- winget 1.6+ — included with App Installer from the Microsoft Store
- EmulationStation frontend — currently BYO (see [Known limitations](#known-limitations))
- Pester 5+ (dev only) — `Install-Module Pester -Scope CurrentUser -MinimumVersion 5.0`

## Quickstart

```powershell
# Import the module from a checkout
Import-Module .\src\EmulationStationSetup.psd1

# 1. Check prerequisites
Test-EmulationStationInstall -PreflightOnly

# 2. Inspect the manifest
Get-EmulationStationManifest | Select-Object -ExpandProperty Systems | Format-Table Name, FullName

# 3. Install one system
Install-EmulationStation -Systems nes

# 4. Install all 16 systems
Install-EmulationStation

# 5. Skip the bundled homebrew ROMs (BYO ROMs)
Install-EmulationStation -SkipHomebrew

# 6. Uninstall (clean reverse-replay; keeps winget packages by default)
Uninstall-EmulationStation

# 7. Full nuke including the winget-installed emulators
Uninstall-EmulationStation -RemoveWinGetPackages -RemoveInstallRoot
```

The install lands at `%USERPROFILE%\.emulationstation` by default; pass `-InstallRoot <path>` to redirect.

## What happens during install

1. **Preflight** — checks PowerShell version, Windows build, winget availability, disk space, network. Any `Fail` aborts.
2. **Manifest** — loads + validates `systems.psd1` and `downloads.psd1`. Schema violations abort with a precise error.
3. **Per system**: idempotent `winget install` of declared packages, registry-based path resolution, verified download of every artifact (SHA-256 mandatory), atomic placement.
4. **Configs** — renders `es_systems.cfg` and `es_settings.cfg` from templates with the resolved emulator paths substituted.
5. **Shortcuts** — Start Menu and Desktop `.lnk` pointing at your EmulationStation install. Skipped (with logged warning) if ES isn't at the configured path.
6. **Install log** — every action recorded in `install-log.json` for the uninstaller to replay later.

Every step appends to [`install-log.json`](docs/plans/M8-install-log-shortcuts.md). `Uninstall-EmulationStation` replays it in reverse.

## Run the tests

```powershell
# Default — fast, offline, deterministic
.\tests\Invoke-Tests.ps1

# Includes real-network integration tests (libretro buildbot, GitHub, winget queries)
.\tests\Invoke-Tests.ps1 -IncludeNetwork

# Maintainer-only — actually installs RetroArch on the host
.\tests\Invoke-Tests.ps1 -IncludeNetwork -IncludeStateChange
```

Default suite: 115 tests, fully offline. With `-IncludeNetwork`: +2 tests. With `-IncludeStateChange`: +2 more (mutates host state).

## Maintainer flow: pinning hashes

When a libretro core update lands or a new artifact gets added, run:

```powershell
Import-Module .\src\EmulationStationSetup.psd1 -Force
InModuleScope EmulationStationSetup {
    Update-DownloadHashes -ManifestRoot (Join-Path $PWD 'manifest')
}
```

This downloads every entry in `downloads.psd1`, computes SHA-256, and rewrites the manifest in place. Review the diff, commit. Failures (network blip, server down) per-entry skip with a warning — the broken entry keeps its previous hash, never an empty/corrupt value.

## Layout

```
src/
  EmulationStationSetup.psd1      module manifest
  EmulationStationSetup.psm1      loader
  public/                         exported cmdlets
    Install-EmulationStation.ps1
    Uninstall-EmulationStation.ps1
    Test-EmulationStationInstall.ps1
    Get-EmulationStationManifest.ps1
  private/                        helpers (one cmdlet per file)
  templates/                      es_systems block, es_settings, dolphin.ini

manifest/
  systems.psd1                    declarations for 16 systems
  downloads.psd1                  HTTPS URLs + pinned SHA-256

tests/
  Unit/                           Pester unit tests (108)
  Integration/                    Network + StateChange tagged
  Invoke-Tests.ps1                runner

docs/
  adr/                            architecture decision records
  plans/                          per-milestone deep plans

reference/                        upstream snapshot + defect analysis
```

## Known limitations

- **EmulationStation frontend is BYO.** This module installs the *emulators* (RetroArch, DuckStation, PCSX2-Qt, RPCS3, Dolphin) and writes the configs ES expects, but you currently install ES itself from [emulationstation.org](https://emulationstation.org/) separately. Shortcut creation skips gracefully if it isn't found.
- **`vice-x64-core` ships with a placeholder hash.** Buildbot SSL was intermittent during initial maintainer pinning; re-run `Update-DownloadHashes` when reachable and commit.
- **Themes not bundled.** ES displays a default look; the recalbox-backport theme upstream uses isn't pulled in.
- **MSIX-installed emulators won't path-resolve.** Resolve-EmulatorPath reads registry uninstall keys, which MSIX/Store apps don't populate. None of the emulators we declare are MSIX; this matters only if you swap in such a package later.

## Architecture and design

- [PLAN.md](PLAN.md) — milestone roadmap and working principles.
- [ARCHITECTURE.md](ARCHITECTURE.md) — module structure, data flow, install pipeline.
- [CONTEXT.md](CONTEXT.md) — domain vocabulary, install root layout, manifest semantics.
- [docs/adr/](docs/adr/) — individual decisions: PS module (vs script), no TLS bypass, winget over Chocolatey, data-driven manifest.
- [docs/plans/](docs/plans/) — per-milestone deep plans (M0–M10), useful as worked examples.

## License

MIT — see [LICENSE](LICENSE).
