# EmulationStation Setup

A PowerShell 7+ module that installs and configures [EmulationStation](https://emulationstation.org/) with ~15 emulated systems on Windows 10/11.

This is a security/reliability-focused rewrite of [Francommit/win10_emulation_station](https://github.com/Francommit/win10_emulation_station). See [PLAN.md](PLAN.md) for scope and milestones, [ARCHITECTURE.md](ARCHITECTURE.md) for the design, and [docs/adr/](docs/adr/) for individual architecture decisions.

## Status

Active development. **Not ready to use yet.** See [PLAN.md](PLAN.md) for the milestone roadmap.

## Requirements

- Windows 10 build 1809 (October 2018) or later, or Windows 11
- PowerShell 7.4+: `winget install Microsoft.PowerShell`
- `winget` 1.6+: included with App Installer from the Microsoft Store
- Pester 5+ (dev only): `Install-Module Pester -Scope CurrentUser -MinimumVersion 5.0`

## Try the preflight

```powershell
Import-Module .\src\EmulationStationSetup.psd1
Test-EmulationStationInstall -PreflightOnly
```

## Run the tests

```powershell
.\tests\Invoke-Tests.ps1            # all suites
.\tests\Invoke-Tests.ps1 -Scope Unit
```

## Layout

```
src/                  Module code (public cmdlets + private helpers + templates)
manifest/             Data-driven declarations (systems, packages, downloads)
tests/                Pester unit + integration tests
docs/                 ADRs and per-milestone plans
reference/            Snapshot of the upstream project + defect analysis
```

## License

MIT — see [LICENSE](LICENSE).
