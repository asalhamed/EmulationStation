# EmulationStation Setup — Project Plan

## Goal
Replace the upstream `Francommit/win10_emulation_station` installer with a PowerShell 7+ module that achieves feature parity for ~15 emulated systems on Windows 10/11, while resolving every defect catalogued in `reference/analysis.md`.

## Scope (locked 2026-05-17)

| Decision | Choice |
|---|---|
| Audience | Shareable to friends / small group — reasonable docs, idempotent re-runs, uninstaller; not full public-OSS overhead |
| Stack | PowerShell 7+ module, Pester for tests, `winget` for packages |
| Systems v1 | Full upstream parity (~15): RetroArch-driven (NES, SNES, Genesis, GBA, GBC, GB, Atari 2600/7800, MAME, FBA, MSX, C64, Amiga, NGP) + console-specific (PSX, PS2, PS3, PSP, Switch, 3DS, Wii, GC, Xbox, Vita, Wii U) |
| Homebrew ROMs | Bundled like upstream, but every artifact pinned with SHA-256 |
| Distribution | A `git pull && Import-Module` from the user's machine; no signed releases yet |

## Non-goals
- Cross-platform (Windows-only).
- GUI installer.
- Code-signing certificate (cost; defer until/unless we go public).
- BIOS distribution (user's responsibility; we won't ship copyrighted BIOS).
- Replacing upstream — this is a fork-in-spirit, not a PR.

## Architecture decisions (full reasoning in `docs/adr/`)
- **[ADR-0001]** Build as a PowerShell 7+ module, not a single script or GUI installer.
- **[ADR-0002]** No TLS bypass, ever. HTTPS only. PS 5 unsupported.
- **[ADR-0003]** `winget` is the only package manager we bootstrap. No Chocolatey, no Scoop, no third-party buckets.
- **[ADR-0004]** Data-driven — every system declared once in `manifest/systems.psd1`; install code is generic.

## Milestones

Each milestone has a clear *exit criterion*: a Pester test or visible artifact that proves it's done. We do not start the next milestone until the previous one's exit criterion passes, and we confirm with the user before moving on.

### M0 — Foundations
**Build:** module scaffold (`src/EmulationStationSetup.{psd1,psm1}`), public/private split, Pester test harness, manifest schema (`manifest/*.psd1`) with `Resolve-Manifest` validator, preflight (`Assert-Prerequisite`: PS ≥ 7.4, Windows 10 1809+, `winget` present, ≥10 GB free, admin only when strictly required).
**Exit:** `Invoke-Pester` runs green; `Test-EmulationStationInstall -PreflightOnly` returns a typed report.

### M1 — Verified downloader
**Build:** `Get-VerifiedDownload` — HTTPS-only, mandatory SHA-256, retry with exponential backoff, atomic write (`.partial` → rename), idempotent (skip if existing hash matches), redirect handling, max-size guard, proxy-aware.
**Exit:** Pester tests cover happy path, bad-hash rejection, partial-download recovery, redirect-following, idempotent re-run, oversize abort.

### M2 — winget package installer
**Build:** `Install-WinGetPackage` — idempotent (query `winget list` first), pin version, capture log, return resolved install path. `Resolve-EmulatorPath` reads `winget list` JSON to find where things landed (no hardcoded `C:\tools\...`).
**Exit:** Tests via mocked `winget` JSON outputs; integration test installs `7zip.7zip` and resolves its path.

### M3 — System data model
**Build:** `manifest/systems.psd1` declares each of the 15 systems with: `Name`, `FullName`, `RomExtensions[]`, `WingetPackage`, `LauncherTemplate`, `ThemeName`, optional `LibretroCore`. `Resolve-Manifest` validates and returns typed objects.
**Exit:** Pester tests on schema violations (missing field, bad regex, duplicate name) and on happy-path parse of the real manifest.

### M4 — Templated config generation
**Build:** `templates/es_systems.cfg.template` with `{{TOKEN}}` placeholders. `Write-EsSystems` renders from system model — no GUI launch, no sleep loop, no `Stop-Process`. Same for `es_settings.cfg`. `dolphin.ini` shipped as a verbatim file (not a heredoc).
**Exit:** Snapshot tests — rendered output for a known system set matches a checked-in expected file. XML parses without warnings.

### M5 — Single-system end-to-end install (NES)
**Build:** Wire M1 + M2 + M3 + M4 into `Install-EmulationStation -Systems nes`. Installs RetroArch via winget, downloads `fceumm_libretro.dll.zip` verified, extracts to `cores/`, drops one homebrew NES ROM into `roms/nes/`, writes a single-system `es_systems.cfg`.
**Exit:** On a clean Windows VM, `Install-EmulationStation -Systems nes` finishes without error; the NES game launches in RetroArch from the EmulationStation UI.

### M6 — All RetroArch systems
**Build:** Loop M5 over every system whose manifest entry has a `LibretroCore` field. ~12 systems. Aggregate failures — don't `exit -1` on the first missing artifact.
**Exit:** `Install-EmulationStation -Systems @retroarch` succeeds; all 12 systems show up in ES; ROM launches in each.

### M7 — Console-specific emulators
**Build:** Per-emulator handlers for: DuckStation (replaces ePSXe — modern, BIOS-optional, actively maintained), PCSX2-Qt (replaces PCSX2 1.6.0), RPCS3, PPSSPP, Ryujinx, Azahar (3DS), Dolphin (GC + Wii), xemu (Xbox), Vita3K, Cemu (Wii U). All via winget where available; otherwise download + verify.
**Exit:** Each emulator installed at a discoverable path, ES launches each from the menu, one homebrew ROM playable per system.

### M8 — Install log + shortcuts
**Build:** `Add-InstallLogEntry` writes one JSON line per filesystem/shortcut/registry action to `$InstallRoot\install.log.jsonl`. `New-Shortcut` typed wrapper. Three Desktop shortcuts (ROMs folder, Cores folder, Windowed ES) recorded in the log.
**Exit:** After full install, `install.log.jsonl` enumerates every artifact placed by the installer. Test asserts every recorded path exists.

### M9 — Uninstaller
**Build:** `Uninstall-EmulationStation` reads `install.log.jsonl` and removes in reverse order. `-KeepRoms` (default `$true`) preserves user-added content. `-RemoveWinGetPackages` (default `$false`) so we don't yank things the user might want for other purposes.
**Exit:** Install → uninstall leaves filesystem in pre-install state minus the ROMs folder. Test verifies.

### M10 — Verification, docs, ship v0.1
**Build:** `Test-EmulationStationInstall` runs the full layout audit. `README.md` with one-paragraph safety summary and the install command. `TROUBLESHOOTING.md` covering known upstream issues. `CHANGELOG.md`. Tag `v0.1`.
**Exit:** Friend can clone the repo, run one command in admin PS 7, and get a working EmulationStation install on a clean Windows 11 box.

## Working principles
These are non-negotiable — every PR / milestone must respect them:

1. **Idempotent everywhere.** Re-runs must converge to the same state.
2. **No TLS bypass.** No `-SkipCertificateCheck`, no `TrustAllCertsPolicy`.
3. **Every download has a SHA-256.** Mismatch = abort; no soft fallback.
4. **Per-user install where possible.** Admin only for VC++ runtime / system-wide dependencies winget itself requires.
5. **No GUI-driven config bootstrap.** Write configs directly from templates.
6. **Data > code.** New systems = new manifest entry, not new code paths.
7. **Aggregate failures.** Report every miss at the end; don't bail on the first.
8. **One Pester test per public cmdlet.** Before the milestone is "done."
9. **No `iex $(downloaded-string)`.** Read first, hash-verify, then run.
10. **Every artifact placement is logged.** So uninstall is a replay, not guesswork.

## How we'll work together
- I plan each milestone in detail (a `docs/plans/Mn-*.md`) before writing code.
- You review the plan, push back, approve.
- I implement, with Pester tests landing alongside the code.
- We mark the milestone done together; I update this file's checklist.
