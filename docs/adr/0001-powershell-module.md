# ADR-0001: Build as a PowerShell 7+ module

**Status:** Accepted (2026-05-17)

## Context
We need to install + configure EmulationStation and ~15 emulators on Windows 10/11. The upstream is a single ~700-line PowerShell script. We considered four alternatives.

## Options considered

1. **PowerShell 7+ module** — what we picked.
2. **WinGet manifest + small PS post-install** — winget handles the binaries, small script does config. Cleaner for the package side, but ties us to the manifests that exist in `winget-pkgs`, and there's no manifest for several things we need (jrassa EmulationStation build, recalbox-backport theme).
3. **GUI installer (Inno Setup / NSIS)** — proper Windows installer with Add/Remove Programs uninstaller. Heavier toolchain, much less transparent to inspect before running, harder to iterate, no native testability.
4. **Python + admin-elevation shim** — cross-platform if we ever want Linux. Adds a Python runtime dependency on every target machine, and Python is non-idiomatic for Windows admin work. We're explicitly Windows-only (see ADR scope).

## Decision
Build as a PowerShell 7+ module (`EmulationStationSetup`) with `public/` exported cmdlets, `private/` helpers, and Pester tests under `tests/`.

## Why
- **Audience fit.** Friends running this read PowerShell; some will modify it. A module is the most inspectable, debuggable artifact for them.
- **Native admin tooling.** PS is the canonical Windows administration language. Elevation, registry, shortcuts, file ACLs all work out of the box.
- **Calls winget cleanly.** No need to bootstrap a package manager (see [ADR-0003](0003-winget-over-choco-scoop.md)).
- **Testable.** Pester 5 is the de facto standard; we can write unit tests with mocked `winget` calls and integration tests on a Windows runner.
- **Idempotent re-runs.** A module structure forces us to think in terms of cmdlets with explicit pre/post-conditions, instead of top-to-bottom procedural script.
- **Transparent.** A friend can `Get-Command -Module EmulationStationSetup`, `Get-Help Install-EmulationStation`, and read the source before running anything elevated.

## Consequences
- **PowerShell 5.1 unsupported.** We require 7.4+. Most Windows 10/11 boxes don't have PS 7 pre-installed; the README must spell out the one-time `winget install Microsoft.PowerShell` step. This is a real friction point — the upstream supports PS 5 by adding the TLS-bypass policy ([ADR-0002](0002-no-tls-bypass.md) explains why we won't follow them there).
- We commit to learning / leaning on PowerShell module conventions (manifest, advanced functions, comment-based help, `ShouldProcess`). This is a small upfront cost.
- Module discoverability beyond friends is limited unless we publish to PSGallery. Out of scope for v0.1 per the audience decision.
