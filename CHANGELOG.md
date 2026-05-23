# Changelog

## Unreleased

### Standalone MAME (current version) + 2 public-domain arcade ROMs
- **New `mame` system** — distinct from existing `arcade` (libretro mame2010 for vintage ROM sets). `mame` uses current MAME 0.287 via `Source = 'Manifest'`, downloads the official `mame0287b_x64.exe` from `github.com/mamedev/mame/releases` (101 MB SFX, extracts to ~368 MB), resolves `mame.exe` recursively. Command template: `"%EXE%" -rompath "%ROMDIR%" "%BASENAME%"`.
- **`.exe` arrivals now treated as 7z self-extracting archives** in `Expand-VerifiedArchive` and the orchestrator's `Emulator` case. 7z handles SFX archives natively; if the file isn't actually SFX, 7z fails with a clear error. Required for MAME's `.exe` distribution; helpful for future emulators that ship via SFX.
- **`%ROMDIR%` substitution** added to `Build-LauncherCommand` — Standalone `CommandTemplate` strings can now reference `%ROMDIR%` and we substitute it with `<InstallRoot>\roms\<system.Name>`. MAME needs this for `-rompath`. `%EXE%` substitution unchanged.
- **New manifest field `KeepArchive` on Download entries** — when true (default false), the ROM-kind file is **copied** (not extracted) under its URL basename. MAME reads ROM sets as `.zip` archives, so `gridlee.zip` must stay `gridlee.zip`, not get expanded into loose `.bin` files. `DownloadSpec` class gained the property; `Resolve-Manifest` reads it; `Place-Artifact` honors it.
- **Two public-domain MAME ROMs bundled** from mamedev.org/roms/:
  - **Gridlee** (Videa, 1983) — released to public domain by Atari Games
  - **Robby Roto** (Bally Midway, 1981) — released to public domain by Williams/Midway
- 16 systems total (was 15); 20 download entries (was 17). Manifest smoke counts updated: 16 systems / 12 Libretro / 4 Standalone.
- **End-to-end install on Windows 11 Pro**: 16/16 systems landed, MAME ROMs and binary all in place, 2 placeholder failures (cbios-msx + ps3-firmware) both network-conditional. Wall clock 2m 27s.

### "Fix all BYO" — system BIOS + auto-firmware + more bundled homebrew
- **Two new `DownloadKind` values**:
  - `SystemFile` — extracted to `<retroarch>\system\`, where libretro cores look for BIOS files. Place-Artifact handles `.zip`/`.7z` extraction + bare-file copy.
  - `Firmware` — passed to the emulator's CLI for installation rather than placed on disk by us. Currently used for RPCS3's `--installfw <pup>` flow.
- **MSX now uses bluemsx core + C-BIOS** (Apache-licensed open-source BIOS) — previous fmsx core required user-supplied Microsoft BIOS files we can't redistribute. bluemsx accepts C-BIOS natively. C-BIOS shipped via SourceForge mirror redirect.
- **Sony PS3 firmware auto-install** — `ps3-firmware` artifact downloads Sony's PUP from `dus01.ps3.update.playstation.net` (Sony hosts; we just reference their URL — never redistribute). After RPCS3 binary extracted, orchestrator invokes `rpcs3.exe --installfw <pup>` to install firmware silently.
- **Two more bundled homebrew ROMs**:
  - **Atari 2600**: Halo 2600 by Ed Fries (freeware, hosted by OpenEmu)
  - **Master System**: Bruce Lee (homebrew port, hosted by OpenEmu)
- **Artifact processing order** in `Install-EmulationStation` now sorts by Kind: `Emulator` first (sets `$launcherPaths` for Manifest-sourced systems), then `SystemFile`, then `Firmware` (needs the emulator binary resolved), then everything else. Previously hashtable iteration was undefined; this guarantees firmware install happens after rpcs3.exe is extracted.
- **Hash pinning status** (3 of 5 new entries pinned at commit time):
  - ✅ `atari2600-halo`, `bluemsx-core`, `sms-brucelee` pinned
  - ⚠️ `cbios-msx`, `ps3-firmware` — placeholders; SourceForge and Sony's update server were SSL-flaky from this network during pinning. Maintainer re-runs `Update-DownloadHashes -Force` when reachable. Orchestrator aggregates failures and continues — install completes for the rest of the manifest.
- 17 download entries total (was 15); 15 systems unchanged.
- Tests: 115 unit pass.
- End-to-end install on Windows 11 Pro: 15/15 systems landed, Atari 2600 + Master System ROMs in place, RPCS3 binary extracted. MSX core/BIOS and PS3 firmware pending network normalization for hash pin.

### MSX + PS3 added; new Launcher.Source = 'Manifest' for non-winget binaries
- **MSX** (Microsoft MSX) — standard libretro entry, `fmsx_libretro.dll`. System BIOS ROMs (MSX2.ROM etc.) are BYO, documented in `Notes`.
- **PS3** (Sony PlayStation 3) — re-added via new schema field `Launcher.Source = 'Manifest'`. Bypasses winget entirely; the emulator binary is downloaded as an Artifact (`Kind = 'Emulator'`) and extracted to `<InstallRoot>\emulators\<system>\`. RPCS3 build pinned to GitHub release `build-67464f97df8679d5d540256987551f34fe00d4cc` (`rpcs3-v0.0.40-19389-67464f97_win64_msvc.7z`, hash `49a71725…`); maintainer bumps URL + re-runs `Update-DownloadHashes` for newer builds.
- **New `DownloadKind = 'Emulator'`** for binaries that get extracted under `<InstallRoot>\emulators\<system>\`. `Place-Artifact` handles extraction + recursive `Get-ChildItem` to locate the `ExecutableName`. Path is registered in `$launcherPaths[<Launcher.PackageId>]` so `Build-LauncherCommand` finds it.
- **Schema validation** for `Launcher.Source`: must be `'WinGet'` (default) or `'Manifest'`. When `'Manifest'`, requires at least one `Artifacts` entry referencing a known download.
- **7-Zip auto-install + path fallback** — orchestrator scans downloads for `.7z` extensions; if any and 7z isn't on PATH, installs `7zip.7zip` via winget before the per-system loop. `Expand-VerifiedArchive` also falls back to `$env:ProgramFiles\7-Zip\7z.exe` / `${env:ProgramFiles(x86)}\7-Zip\7z.exe` for cases where PATH refresh doesn't propagate to the in-process command lookup (which we hit on the first MSX/PS3 run).
- **`Write-EsSystems` is now called with only successfully-installed systems** — previously a single system whose path resolution failed (e.g., PS3 if extraction errored) would throw inside `Build-LauncherCommand` and prevent any `es_systems.cfg` write at all. Now partial-success runs still produce a valid config with all the systems that did work.
- Manifest counts: 11 Libretro + 1 new (MSX) + 2 WinGet Standalone + 1 new Manifest Standalone = **15 systems**, **15 downloads**.
- Smoke tests updated: 15 systems, 12 Libretro, 3 Standalone. Per-system invariant tightened to "WinGet-sourced systems must declare Packages; Manifest-sourced systems may have empty Packages." 115 unit pass.
- End-to-end install verified on Windows 11 Pro: **0 failures**, 15 systems, RPCS3 v0.0.40 extracted to `…\.emulationstation\emulators\ps3\rpcs3.exe`. Wall clock 41 seconds on the cached re-run.

### ES-DE frontend included with full linkage
- **`Install-EmulationStation` now installs the ES-DE frontend by default.** New parameter `-SkipFrontend` opts out. Defaults: `-FrontendPackageId 'ES-DE.EmulationStation-DE'`, `-FrontendExecutableName 'ES-DE.exe'`.
- After the per-system loop and config renders, the orchestrator: (1) installs `ES-DE.EmulationStation-DE` via winget (idempotent), (2) resolves `ES-DE.exe` via `Resolve-EmulatorPath`, (3) auto-sets `$EmulationStationExe` for shortcut creation if the caller didn't override, (4) sets `$frontendArgs = "--home <InstallRoot>"`.
- **`es_systems.cfg` is mirrored to `<InstallRoot>\custom_systems\es_systems.xml`** — the location ES-DE reads when launched with `--home <InstallRoot>`. Same XML content (the `<systemList>` schema is compatible), just the filename and path differ. Logged as a separate `ConfigRendered` action with `Format=ESDE`.
- **`New-EmulationStationShortcut` gains `-Arguments`** so the Start Menu + Desktop shortcuts carry `--home "<InstallRoot>"`. This makes ES-DE read our existing `.emulationstation` tree (config, gamelists, themes) instead of the default `%USERPROFILE%\ES-DE\`. Tracked in the install log.
- **Shortcut probe** auto-switches to ES-DE's install path when the frontend is installed. The legacy classic-ES default at `${ProgramFiles(x86)}\EmulationStation\emulationstation.exe` is still honored if the caller passes `-EmulationStationExe`.
- 4 new unit tests: ES-DE installed by default; `-SkipFrontend` skips; `custom_systems\es_systems.xml` mirror appears; shortcuts carry `--home <InstallRoot>` arguments.
- End-to-end install verified on Windows 11 Pro: **0 failures**, 13 systems, ES-DE v3.4.1 installed, Start Menu + Desktop shortcuts created with `--home` arg. Wall clock 1m 11s (ES-DE is the heaviest single download).

### Fixes from first real end-to-end install
- **`Resolve-EmulatorPath`** — fall back to `UninstallString` (or `QuietUninstallString`) when the registry entry's `InstallLocation` is empty. NSIS installers (`Libretro.RetroArch` is the canonical case — installs to `C:\RetroArch-Win64\` but the install key doesn't populate `InstallLocation`) now resolve correctly. Quoted paths with trailing arguments (`"C:\...\uninstall.exe" /S`) handled. Adds 2 unit tests.
- **`Write-EsSystems`** — derive the cores directory from `Split-Path -Parent <retroarch.exe>` instead of `$InstallRoot\systems\retroarch\cores\`. Previously the rendered `<command>` pointed at a directory `Place-Artifact` never wrote to, so RetroArch would launch but fail to load the core at runtime. Regression test pins the contract: cores dir must be a sibling of `retroarch.exe`, never under `$InstallRoot`.
- **`manifest/systems.psd1`** — removed PS3 (RPCS3) and GC/Wii (Dolphin) entries. `RPCS3.RPCS3` is not in the public winget repo (no matches at all). `DolphinEmulator.Dolphin`'s installer URL points at `dl-mirror.dolphin-emu.org/5.0/dolphin-x64-5.0.exe` which returns HTTP 403 (2016 mirror dropped). Schema + orchestrator unchanged — paste entries back when winget is fixed upstream. System count: 16 → 13 (11 Libretro + 2 Standalone).
- **`manifest/downloads.psd1`** — all 13 hashes pinned to current libretro nightly (`vice-x64-core` was last placeholder).
- **Tests** — 111 unit pass (was 108): +2 `Resolve-EmulatorPath` (UninstallString fallback paths), +1 `Write-EsSystems` (core-path regression).

End-to-end install verified on Windows 11 Pro: 13 systems installed, 9 cores extracted to `C:\RetroArch-Win64\cores\`, 4 homebrew ROMs placed, `es_systems.cfg` written with correct paths. Re-run idempotent in 35 seconds (winget packages skip as AlreadyInstalled, ROM cache hits).

## v0.1.0 — 2026-05-19

First public cut. All 11 planned milestones (M0–M10) shipped; all 24 defects from `reference/analysis.md` addressed. 108 unit tests, 115 default suite, 117 with `-IncludeNetwork`. 16 systems supported (11 Libretro + 5 Standalone). Install + uninstall are both auditable round-trips.

### M10 — Verification, docs, ship v0.1
- README rewritten end-to-end: quickstart, supported systems, install pipeline summary, run-the-tests, maintainer flow, layout, known limitations.
- PLAN.md appended with an Outcomes section: milestone-by-milestone commit list, test totals, defect tally, deferred items.
- M10 deep plan committed at `docs/plans/M10-verification-ship.md`.
- v0.1.0 git tag annotated.

### M9 — Uninstaller (reverse-replay)
- `Uninstall-EmulationStation` replaces the M0 `NotImplementedException` stub. Walks `install-log.json` Actions[] in reverse, undoing what's undoable: `ShortcutCreated` → delete .lnk, `ConfigRendered` → delete .cfg, `FileWritten` → delete file, `DirectoryCreated` → remove if empty (preserving user-dropped ROMs), `WinGetInstall` → skip by default, opt-in via `-RemoveWinGetPackages`.
- `Uninstall-WinGetPackage` (private): idempotent — checks if installed first; returns `Status='NotInstalled'` without erroring when absent.
- `Invoke-WinGet` ValidateSet expanded to include `'uninstall'`.
- **Conservative defaults locked in:**
  - `-RemoveWinGetPackages` is OFF by default — RetroArch and the standalone emulators stay installed unless the user explicitly opts in.
  - Only packages we recorded as `Status='Installed'` are uninstalled when opted in. `AlreadyInstalled` and `Upgraded` are skipped because we didn't put them there or didn't put that version there.
  - Non-empty directories are preserved — only empty `DirectoryCreated` paths get removed. User ROMs are safe.
- Returns a `RemovalSummary` hashtable: `Started`, `Finished`, `InstallRoot`, `Reversed[]`, `Skipped[]` (with reasons), `Failed[]`.
- 7 new unit tests for `Uninstall-EmulationStation` covering: missing-log throw, ShortcutCreated reversal, ConfigRendered reversal, empty-vs-non-empty directory handling, default winget-skip, opt-in winget-uninstall with Status filtering, return shape.
- 3 new unit tests for `Uninstall-WinGetPackage`.
- Integration test in `Install-NES.Tests.ps1` extended with an install-then-uninstall round-trip assertion.
- No defects from `reference/analysis.md` to close — those all fell by M7. M9 closes a brand-new concern that upstream's installer doesn't address at all: clean reversibility.
- Test totals: 108 unit, 115 default suite, 8 NotRun (Network + StateChange opt-ins).

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
