# Architecture

## Repository layout

```
EmulationStation/
├── src/
│   ├── EmulationStationSetup.psd1        Module manifest
│   ├── EmulationStationSetup.psm1        Loader (dot-sources public/private)
│   ├── public/                           Exported cmdlets
│   │   ├── Install-EmulationStation.ps1
│   │   ├── Uninstall-EmulationStation.ps1
│   │   ├── Test-EmulationStationInstall.ps1
│   │   └── Get-EmulationStationManifest.ps1
│   ├── private/                          Internal helpers (not exported)
│   │   ├── Get-VerifiedDownload.ps1
│   │   ├── Install-WinGetPackage.ps1
│   │   ├── Resolve-EmulatorPath.ps1
│   │   ├── Resolve-Manifest.ps1
│   │   ├── Write-EsSystems.ps1
│   │   ├── Write-EsSettings.ps1
│   │   ├── New-Shortcut.ps1
│   │   ├── Add-InstallLogEntry.ps1
│   │   ├── Read-InstallLog.ps1
│   │   ├── Assert-Prerequisite.ps1
│   │   └── Expand-VerifiedArchive.ps1
│   └── templates/
│       ├── es_systems.cfg.template
│       ├── es_settings.cfg.template
│       └── dolphin.ini
├── manifest/
│   ├── systems.psd1                       What each emulated system needs
│   ├── packages.psd1                      winget IDs to install (pinned)
│   └── downloads.psd1                     url + sha256 + dest per artifact
├── tests/
│   ├── Unit/                              Mocked, fast; runs on any host
│   └── Integration/                       Hits filesystem; Windows only
├── docs/
│   ├── adr/                               Architecture decision records
│   ├── plans/                             Per-milestone deep plans
│   ├── TROUBLESHOOTING.md
│   └── SECURITY.md
├── reference/                             Upstream snapshot for analysis
├── PLAN.md
├── ARCHITECTURE.md (this file)
├── CONTEXT.md                             Domain glossary
├── CHANGELOG.md
└── README.md
```

## Public cmdlet contracts

### `Install-EmulationStation`
```
Install-EmulationStation
  [-Systems <string[]>]               # default: all in manifest
  [-InstallRoot <path>]               # default: $env:USERPROFILE\.emulationstation
  [-ManifestPath <path>]              # default: $PSScriptRoot\..\manifest
  [-SkipHomebrew]                     # default: $false; if set, no ROMs placed
  [-WhatIf] [-Confirm]                # PowerShell standard
```
Returns: `InstallSummary` object — `{ Started, Finished, SystemsInstalled[], Failures[], InstallLogPath }`.

### `Uninstall-EmulationStation`
```
Uninstall-EmulationStation
  [-InstallLog <path>]                # default: $InstallRoot\install.log.jsonl
  [-KeepRoms]                         # default: $true
  [-RemoveWinGetPackages]             # default: $false
  [-WhatIf] [-Confirm]
```
Returns: `UninstallSummary` — `{ Removed[], Kept[], Errors[] }`.

### `Test-EmulationStationInstall`
```
Test-EmulationStationInstall
  [-InstallRoot <path>]
  [-PreflightOnly]                    # check prerequisites only, no install needed
```
Returns: `InstallReport` — `{ Checks[]: { Name, Status, Detail } }` with `Status` in `Pass|Fail|Skip`.

### `Get-EmulationStationManifest`
Reads + validates the manifest, returns the typed system collection. Useful for introspection / docs generation.

## Data flow

```
                 manifest/*.psd1
                       │
                       ▼
               Resolve-Manifest  ────────►  Typed System[] objects
                       │
                       ▼
              Assert-Prerequisite  (PS, OS, winget, disk, admin)
                       │
                       ▼
              For each requested System:
                ├── Install-WinGetPackage     (idempotent)
                ├── Get-VerifiedDownload      (HTTPS + SHA-256)
                ├── Expand-VerifiedArchive    (.NET ZipFile / 7z)
                ├── Place files per system rules
                └── Add-InstallLogEntry       (record action)
                       │
                       ▼
              Write-EsSystems     (render template from System[])
              Write-EsSettings    (render template)
              Copy templates/dolphin.ini verbatim
              New-Shortcut x 3    (each recorded in log)
                       │
                       ▼
              Test-EmulationStationInstall   (post-install audit)
```

## Trust boundaries
- **Module code** (this repo): trusted.
- **Manifests** (this repo, hash-pinned): trusted.
- **Downloaded binaries**: untrusted until SHA-256 matches manifest.
- **User input** (`-Systems`, `-InstallRoot`, etc.): validated against manifest / safe-path rules; no input is interpolated into commands.

## Failure model
- Prerequisites: hard fail before any side effect.
- Per-system install: failures aggregated in `InstallSummary.Failures`; other systems continue.
- Hash mismatch: abort that artifact, do not retry, do not "fall through" to the file.
- winget error: surface stderr verbatim; mark system failed.
- Partial install: install log records what *did* land, so uninstall can clean up.

## Out-of-scope (deferred)
- Code-signing the module.
- Cross-platform abstractions.
- GUI front-end.
- Scraper integration (the `sselph/scraper` is unmaintained; we'll document manual use only).
