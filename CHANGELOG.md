# Changelog

## Unreleased

### M8 — Install log + shortcuts
- `Write-InstallLog`: append-only JSON log at `$InstallRoot\install-log.json`. Schema v1 with `Version`, `Created`, `Actions[]`. Atomic write via `.tmp` + rename. Auto-injects `Timestamp` (ISO-8601 UTC). Throws on missing `Kind`.
- `New-EmulationStationShortcut`: creates `.lnk` shortcuts via `WScript.Shell` COM. Throws if target exe is missing (no dangling shortcuts). Idempotent — overwrites existing.
- `Install-EmulationStation` gains:
  - `-EmulationStationExe` parameter (default `%ProgramFiles(x86)%\EmulationStation\emulationstation.exe`).
  - `-NoShortcuts` switch (default off; opt-out for CI/headless).
  - `-NoInstallLog` switch (default off; opt-out for ephemeral tests).
  - Log calls sprinkled through the pipeline: `Started`, `WinGetInstall`, `DirectoryCreated`, `ConfigRendered`, `ShortcutCreated`, `Finished`. Each action carries kind-specific fields.
  - Shortcuts: Start Menu (`$env:APPDATA\Microsoft\Windows\Start Menu\Programs\EmulationStation.lnk`) + Desktop (`$env:USERPROFILE\Desktop\EmulationStation.lnk`). Skipped (with logged warning) if EmulationStation.exe isn't at the expected path — no dangling shortcuts.
  - Summary hashtable now includes `LogPath` (or `$null` when `-NoInstallLog`).
- 7 new unit tests for the helpers (4 log + 3 shortcut), plus 3 new orchestrator-wiring tests, plus an extension to the integration test asserting `install-log.json` exists with the expected actions after a real install.
- No defects from `reference/analysis.md` closed — those all fell by M7. M8 sets up M9's uninstaller (replay the log in reverse).
- Test totals: 98 unit, 105 default suite, 7 NotRun (Network + StateChange opt-ins).

### M7 — Console-specific Standalone emulators
- 5 new Standalone-launcher systems added to `manifest/systems.psd1`:
  - `psx` — `Stenzek.DuckStation` (replaces upstream ePSXe 2.0.5 from 2016).
  - `ps2` — `PCSX2Team.PCSX2` (PCSX2-Qt; replaces upstream PCSX2 1.6.0 from 2020).
  - `ps3` — `RPCS3.RPCS3`.
  - `gc` — `DolphinEmulator.Dolphin`.
  - `wii` — `DolphinEmulator.Dolphin` (shared package + executable with `gc`).
- Each declares the right `PackageId`, `ExecutableName`, and `CommandTemplate` (batch-mode flags so the emulator exits cleanly back to ES after a session). `%EXE%` substitution happens at config-render time via `Resolve-EmulatorPath`; `%ROM%` is preserved for ES's runtime substitution.
- No new downloads — Standalone systems are pure winget installs. Users supply their own ROMs and (for PSX/PS2/PS3) BIOS files.
- `tests/Unit/Manifest.Smoke.Tests.ps1` updated: total system count now 16 (11 Libretro + 5 Standalone), with a new assertion that Standalone systems have all four required launcher fields.
- `tests/Integration/Standalone.Network.Tests.ps1` (new, `Network` tag): best-effort path resolution against any of the 5 packages already installed on the host. Skips cleanly when none are installed (the expected case during M7 implementation on this box).
- Closes upstream defects #16 (final — hardcoded `C:\tools\Dolphin-Beta\` paths) and #17 (final — outdated PCSX2 1.6.0 and ePSXe 2.0.5 dropped entirely).
- **24 of 24 upstream defects from `reference/analysis.md` now addressed.** Remaining work is forward-looking (install log, uninstaller, docs, ship).
- Test totals: 88 unit, 95 default suite, 7 NotRun (Network + StateChange opt-ins).

### M6 — All RetroArch systems (11 total)
- `manifest/systems.psd1` expanded with 10 new libretro-driven systems: SNES, GB, GBC, GBA, Mega Drive / Genesis, Master System, N64, Atari 2600, Arcade (MAME 2010), C64.
- Shared cores recognized: `gambatte_libretro.dll` for GB+GBC, `genesis_plus_gx_libretro.dll` for Mega Drive+Master System. One download entry, two systems consume it.
- 3 new bundled homebrew ROMs (HTTPS, hash-pinned) from the OpenEmu/OpenEmu-Update GitHub repo: `snes-nwarp` (N-Warp Daisakusen, SNES), `gba-uranus` (Uranus Zero EV, GBA), `genesis-rickdangerous` (Rick Dangerous, Genesis). Together with the existing `nes-assimilate`, that's 4 bundled ROMs spanning 4 systems.
- `Update-DownloadHashes` run on this box pinned 12 of 13 entries. The remaining placeholder (`vice-x64-core`) is due to a transient libretro buildbot SSL failure that has been intermittent throughout M5+M6 work. Maintainer re-runs when reachable; orchestrator handles the placeholder gracefully if a user installs `c64` before then.
- 5 new manifest smoke tests in `tests/Unit/Manifest.Smoke.Tests.ps1`: system count, artifact cross-references, shape invariants, libretro core naming convention, shared-core intentionality (the gambatte / genesis_plus_gx pair).
- 1 new orchestrator test: `Install-EmulationStation -Systems @('nes','snes')` runs multi-system, with `Resolve-EmulatorPath` for RetroArch only invoked once due to the path-cache.
- Fixed a latent mock-target bug in `Install-EmulationStation.Tests.ps1`: the tests were mocking `Get-EmulationStationManifest` but the orchestrator calls `Resolve-Manifest` directly. The single-system manifest from M5 had hidden the misalignment; M6's expanded manifest exposed it. Now mocking the actual callee.
- Closes upstream defects #18 (final — the 700-line per-system copy-paste install logic is now a single generic loop driven by the manifest) and #23 (full — per-system opt-in via `-Systems`).
- Test totals: 86 unit, 93 default suite, 4 NotRun without `-IncludeNetwork`, 6 NotRun without `-IncludeStateChange`.

### M5 — NES end-to-end install
- `Install-EmulationStation`: full orchestration — preflight, manifest, winget packages, verified downloads, artifact placement (LibretroCore → cores dir, Rom → roms/<system>/, Theme → themes/, EmulatorAsset deferred), `Write-EsSystems` + `Write-EsSettings` rendering. Per-system and per-artifact failures aggregate into the returned summary rather than aborting.
- `Expand-VerifiedArchive`: `.zip` via .NET `ZipFile.ExtractToDirectory` (no shell dependency); `.7z` via `7z.exe` on PATH with a clear error if missing.
- `Update-DownloadHashes`: maintainer cmdlet that downloads each artifact and rewrites `downloads.psd1` with computed SHA-256. Warn-and-continue per entry; never writes a broken hash back.
- `Get-RemoteFileHash`: private helper for the maintainer flow. Uses `-ErrorAction Stop` so network failures propagate rather than silently emitting an empty hash.
- `tests/Invoke-Tests.ps1` gains `-IncludeStateChange` for opt-in to host-mutating tests.
- Real SHA-256 pinned for `nes-assimilate` (homebrew NES ROM from nesworld.com). `fceumm-core` retains placeholder hash because `buildbot.libretro.com` had SSL-handshake failures during M5 implementation — maintainer re-runs `Update-DownloadHashes` when libretro is reachable. The orchestrator handles the placeholder gracefully: download fails verification → recorded in `Failures`, install continues for the rest of the artifacts.
- 13 new unit tests (3 Expand-VerifiedArchive + 2 Update-DownloadHashes + 8 Install-EmulationStation). Integration test in `tests/Integration/Install-NES.Tests.ps1` tagged `Network`+`StateChange` (opt-in).
- Test totals: 80 unit, 87 default suite, 90 with `-IncludeNetwork`.
- Closes upstream defects #4 partial (hash pinning mechanism + maintainer flow; full pin lands when libretro reachable), #12 partial (aggregated failures, no `exit -1`), #13 (`Expand-Archive` shadowing + hardcoded 7z path), #19 partial (orchestrator unit tests + integration scaffold).

### M4 — Templated config generation
- `Render-Template`: simple `{{TOKEN}}` substitution helper. XML-escapes by default; `-NoXmlEscape` for INI/plain. Unknown tokens left literal so un-substituted placeholders are visible.
- `Write-EsSystems`: renders `es_systems.cfg` directly from `EmulatorSystem[]`. One `<system>` block per system. Libretro command = `"<retroarch.exe>" -L "<core.dll>" %ROM%`; Standalone command = manifest's `CommandTemplate` with `%EXE%` substituted. `%ROM%`/`%ROM_RAW%` preserved for ES runtime substitution. Output validated as well-formed XML before write.
- `Write-EsSettings`: renders `es_settings.cfg` with one `{{USERPROFILE}}` substitution (forward-slashed paths for the slideshow keys). Format is XML-ish but multi-rooted (matches upstream + what ES expects), so no XmlDocument validation.
- Templates at `src/templates/`:
  - `es_systems.cfg.system-block.template` — one system's XML block.
  - `es_settings.cfg.template` — verbatim port of upstream's es_settings (40 settings).
  - `dolphin.ini.template` — verbatim port of upstream's 200-line Dolphin config, with `$env:userprofile` replaced by `{{USERPROFILE}}`.
- 14 new unit tests (5 Render-Template + 6 Write-EsSystems + 3 Write-EsSettings).
- Closes upstream defects #10 (GUI-driven config bootstrap), #15 (60s sleep loops), #20 (es_systems.cfg heredoc), #21 (dolphin.ini heredoc).

### M3 — System data model
- Schema v1 for `manifest/systems.psd1` and `manifest/downloads.psd1` with strict validation: regex constraints on names, enum values for kinds, polymorphic `Launcher` (Libretro vs Standalone), cross-manifest artifact resolution.
- `Resolve-Manifest` rewritten — takes `-ManifestRoot` (directory), reads both PSD1s, returns typed `EmulatorSystem[]` and `DownloadSpec[]`. Throws with file:path-style messages on the first violation.
- New types: `LauncherKind`, `DownloadKind`, `EmulatorSystem`, `DownloadSpec`.
- `manifest/packages.psd1` removed; pinning folded into per-system `Packages = @(@{Id; Version})` shape (also accepts bare strings for unpinned).
- 15 new unit tests covering every validation rule + 2 for `Get-EmulationStationManifest` against the shipped manifest. Total grows from 50 to 60+ green.
- Closes upstream defects #18 (copy-paste install logic — schema enables generic loop in M6), #20 (es_systems.cfg heredoc — manifest now source of truth), #23 partial (per-system opt-in is now natural).

### M2 — winget package installer
- `Invoke-WinGet`: single chokepoint that shells out to winget.exe via `Start-Process` with redirected stdout/stderr; throws on non-zero exit with stderr context. Optional `-ParseJson` (for verbs that support it).
- `Install-WinGetPackage`: idempotent — query first via `Find-WinGetInstalledPackage`, install/upgrade only if needed. Returns typed status. Supports `-UserScope`, `-Version`, `ShouldProcess`.
- `Find-WinGetInstalledPackage`: parses tabular `winget list` output (strips ANSI, splits on CR/LF including standalone CR spinners, locates by header column positions). winget v1.28 list verb does NOT support `--output json`, so tabular parsing is the only reliable path.
- `Resolve-EmulatorPath`: queries registry uninstall keys (HKLM, HKLM\WOW6432Node, HKCU) for the package's DisplayName and returns its InstallLocation. Works for EXE/MSI installs (Dolphin, RPCS3, Git, etc.); MSIX/Store apps do not register InstallLocation and will throw — documented gap.
- 13 unit tests (mocked) covering parameter validation, idempotency, install, upgrade, scope, path resolution, registry traversal.
- 3 integration tests tagged `Network` (read-only on this machine, no state mutation).
- Closes upstream defects #6 (Chocolatey iex), #7 (third-party Scoop bucket), #8 partial (admin-free via `-UserScope`), #9 (hardcoded paths), #11 (force-killing processes), #14 (non-idempotent installs).

### M1 — Verified downloader
- `Get-VerifiedDownload`: HTTPS-only, mandatory SHA-256, atomic write via `.partial`, idempotent on re-run, retry-with-backoff for transient errors, hash-mismatch never retries, size cap default 5 GB.
- 12 unit tests (mocked `Invoke-WebRequest`) covering parameter validation, happy path, idempotency, hash mismatch, retry success / exhaustion, oversize.
- 1 integration test tagged `Network` (off by default; opt in via `Invoke-Tests.ps1 -IncludeNetwork`).
- Closes upstream defects #1 (TrustAllCertsPolicy), #2 (-SkipCertificateCheck), #3 (no checksums), #5 (http URLs).

### M0 — Foundations
- Module scaffold with public/private split.
- Preflight checks: PowerShell, Windows, winget, disk, network.
- Manifest schema (v1, empty until M3 / M6 / M7).
- Pester unit + integration test harness.
- Documentation: PLAN, ARCHITECTURE, CONTEXT, ADRs 0001–0004, M0 plan.

### To do
- Update the `<your name>` placeholder in [LICENSE](LICENSE).
