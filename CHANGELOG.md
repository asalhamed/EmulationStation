# Changelog

## Unreleased

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
