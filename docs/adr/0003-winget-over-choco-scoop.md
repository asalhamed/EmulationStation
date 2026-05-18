# ADR-0003: `winget` is the only package manager we bootstrap

**Status:** Accepted (2026-05-17)

## Context
Upstream `prepare.ps1` bootstraps **two** package managers:
1. Chocolatey, via the canonical `iex $((New-Object Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))` line.
2. Scoop, via `iwr -useb get.scoop.sh -outfile … ; .\installScoop.ps1 -RunAsAdmin`.

It then adds a third-party Scoop bucket (`github.com/borger/scoop-emulators`) for emulators not in the main bucket.

This is the single most dangerous line in the upstream installer: an arbitrary URL's contents executed with admin rights, with no signature/hash check. Compromise of `chocolatey.org` or the install script — or any MITM during the fetch — is full RCE.

Meanwhile, `winget` has been built into Windows since Windows 10 1809 (2018), is signed by Microsoft, and now supports almost every emulator upstream needs.

## Decision
- **`winget` is the only package manager we use.** No Chocolatey, no Scoop, no third-party buckets.
- Pre-flight asserts winget ≥ 1.6 (for stable JSON output).
- Every package we install is pinned by `Id` + version in `manifest/packages.psd1`.
- We do not `iex` anything downloaded.

## Why
- **Already on the box.** No bootstrap of a package manager = zero `iex $(downloaded)` lines in our installer.
- **Signed by Microsoft.** The `winget` binary itself is part of App Installer, signed and updated through the Microsoft Store. Trust chain is the OS vendor.
- **Per-user packages.** Several emulators are available as per-user installs, no admin needed.
- **JSON output.** `winget list --output json` (and `winget search`) means we can programmatically resolve install paths instead of hardcoding `C:\tools\Dolphin-Beta\`.
- **Coverage.** As of 2026, the emulators we care about are all in `winget-pkgs`: `Dolphin.Dolphin`, `PCSX2.PCSX2`, `RPCS3.RPCS3`, `PPSSPP.PPSSPP`, `Ryujinx.Ryujinx`, `xemu.xemu`, `Vita3K.Vita3K`, `Cemu.Cemu`, `Stenzek.DuckStation`, `Libretro.RetroArch`.

## Consequences
- A handful of components are not in winget (the jrassa EmulationStation build, recalbox-backport theme, libretro cores). These come through our verified downloader ([ADR-0002](0002-no-tls-bypass.md)) — SHA-256 pinned URLs, not a package manager.
- We drop `Azahar` for 3DS if winget coverage isn't there at install time — but as of 2026 it ships in winget as `Azahar-Emu.Azahar`. Preflight will check.
- Users with existing Chocolatey or Scoop installs are unaffected — we don't touch them.
- We lose the ability to "auto-update" a package later via Chocolatey's mechanisms. We considered this a feature: updates are user-driven (`git pull && re-run`), not silent.

## What if winget isn't available?
Preflight aborts with a clear error and a one-liner: `winget` is included in App Installer from the Microsoft Store; if it's missing, install App Installer. We do not attempt to install winget for them.
