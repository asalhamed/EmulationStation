# Changelog

## Unreleased

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
