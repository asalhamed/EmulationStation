# M5 — NES end-to-end install

**Goal:** wire M1 + M2 + M3 + M4 into a single `Install-EmulationStation -Systems nes` call that, on a clean Windows 11 box, leaves you with RetroArch installed via winget, the fceumm core in the right place, one homebrew NES ROM, and an `es_systems.cfg` that EmulationStation can read. Launching ES and choosing the bundled ROM boots the NES game in RetroArch.

This is the most state-changing milestone we've shipped — running it will install RetroArch on your machine and write files to `%USERPROFILE%\.emulationstation\`. The integration test path makes the same change. Both are reversible (M9 uninstaller closes the loop), and re-runs are idempotent (M1/M2 already make every step skip if already done).

## What we're building

### `Install-EmulationStation` (was stub since M0)

```powershell
Install-EmulationStation
    -Systems <string[]>                       # default: all in manifest
    [-InstallRoot <string>]                   # default: %USERPROFILE%\.emulationstation
    [-ManifestRoot <string>]                  # default: ./manifest/
    [-CacheRoot <string>]                     # default: $InstallRoot\.cache
    [-SkipPreflight]                          # testing escape hatch
    [-SkipHomebrew]                           # don't drop bundled ROMs
    [-WhatIf] [-Confirm]
```

Algorithm:
```
1. Preflight unless -SkipPreflight: Assert-Prerequisite. Any Fail -> abort.
2. Resolve manifest: Get-EmulationStationManifest -ManifestRoot $ManifestRoot
3. Filter systems: if -Systems was given, keep only those by Name. Unknown names -> warn and skip (but proceed with the rest).
4. Create install root + cache root if missing.
5. For each filtered system:
     a. For each Package on the system: Install-WinGetPackage (idempotent).
     b. Resolve every PackageId to an executable path via Resolve-EmulatorPath. Build $launcherPaths hashtable.
     c. For each Artifact on the system:
          - Look up the DownloadSpec in the manifest by ID.
          - Get-VerifiedDownload -Uri ... -Sha256 ... -Destination $CacheRoot\$ArtifactId
          - Place it:
              LibretroCore  -> extract .zip into $retroarchInstallDir\cores\
              Rom           -> extract (if archive) into $InstallRoot\roms\$systemName\
                              -> or copy verbatim if not archived (e.g., .gba, .smc, .nes, .gen)
              Theme         -> extract into $InstallRoot\themes\
              EmulatorAsset -> defer (M7 specific)
6. Render configs (from M4):
     - Write-EsSystems with the full set of installed systems and the resolved launcher paths.
     - Write-EsSettings.
     - Copy templates/dolphin.ini.template -> $InstallRoot\dolphin.ini with USERPROFILE substituted (deferred to M7 if no Dolphin system installed; for NES, skip).
7. Return an InstallSummary: { Started; Finished; SystemsInstalled[]; Failures[]; InstallRoot }.
```

Aggregate failures per working principle #7 — if one system errors out, log it in `.Failures` and continue with the rest.

### `Expand-VerifiedArchive` (new private helper)

```powershell
Expand-VerifiedArchive
    -Path <string>          # the archive (.zip, .7z)
    -Destination <string>   # directory
    [-Force]                # overwrite
```

For `.zip`: use `[System.IO.Compression.ZipFile]::ExtractToDirectory()` from .NET — no shell dependency.
For `.7z`: shell out to `7z.exe`. Requires `7zip.7zip` installed via winget; M5 declares it as a prereq for systems that need it. **For NES specifically, the core is a `.dll.zip` — no 7-Zip needed.**

### `Update-DownloadHashes` (maintainer cmdlet)

```powershell
Update-DownloadHashes
    -ManifestRoot <string>
    [-OutputPath <string>]      # default: writes back over downloads.psd1
    [-Force]                    # overwrite existing pinned hashes too
```

Iterates `Downloads`, calls `Get-VerifiedDownload` with a `$('0' * 64)` placeholder hash → that fails with "SHA-256 mismatch", but we use a separate code path that just downloads + hashes without rejecting on mismatch (a tiny internal `Get-RemoteFileHash` helper that returns the computed hash, NOT a verified path). Then emits a new `downloads.psd1` with real hashes filled in.

**This is run by maintainers (us), not end users.** Output gets reviewed and committed.

For M5 we need real hashes on two entries: `fceumm-core` and `nes-assimilate`. We'll run `Update-DownloadHashes` once, eyeball the diff, commit.

## Test plan

### Unit tests (mocked, fast)

`tests/Unit/Install-EmulationStation.Tests.ps1` — 8 tests:
1. Calls preflight unless -SkipPreflight.
2. Filters to requested systems.
3. Unknown system name → warning, not throw.
4. For each system: Install-WinGetPackage called for each Package.
5. For each system: Get-VerifiedDownload called for each Artifact.
6. Calls Write-EsSystems with the right LauncherPaths.
7. Aggregates failures: one system erroring doesn't stop others.
8. Returns InstallSummary with the right fields.

`tests/Unit/Expand-VerifiedArchive.Tests.ps1` — 3 tests:
1. Extracts a .zip to the destination.
2. Throws on missing input file.
3. Throws on unsupported extension (without forcing).

`tests/Unit/Update-DownloadHashes.Tests.ps1` — 2 tests:
1. Mocked download → writes computed hash to output.
2. -Force overwrites existing pinned hash.

### Integration test (tagged `Network + StateChange`, opt-in)

`tests/Integration/Install-NES.Tests.ps1`:
1. Runs `Install-EmulationStation -Systems nes -InstallRoot $tempDir` end-to-end.
2. Asserts the resulting layout: `$tempDir\roms\nes\` has the homebrew ROM; the RetroArch core is present (somewhere — actual path depends on winget); `es_systems.cfg` parses as XML with `<name>nes</name>`.
3. Does NOT launch ES or play the ROM — manual verification.

This test:
- Will install `Libretro.RetroArch` via winget if not already installed (idempotent if it is).
- Will modify `%USERPROFILE%\.emulationstation\` (or wherever you point -InstallRoot).
- Is gated behind `-IncludeNetwork` AND a new `-IncludeStateChange` flag on Invoke-Tests.ps1.

### Manual demo (the moment of truth)

```powershell
Import-Module .\src\EmulationStationSetup.psd1 -Force
$summary = Install-EmulationStation -Systems nes
$summary | Format-List
# Then launch ES from Start Menu and pick the homebrew NES ROM.
```

## Files M5 adds or changes

```
src/public/
  Install-EmulationStation.ps1            REWRITE — full implementation

src/private/
  Expand-VerifiedArchive.ps1              NEW
  Update-DownloadHashes.ps1               NEW (maintainer)

manifest/
  downloads.psd1                          CHANGE — real SHA-256 for fceumm + nes-assimilate

tests/Unit/
  Install-EmulationStation.Tests.ps1      NEW (8 tests)
  Expand-VerifiedArchive.Tests.ps1        NEW (3 tests)
  Update-DownloadHashes.Tests.ps1         NEW (2 tests)

tests/Integration/
  Install-NES.Tests.ps1                   NEW (tagged Network + StateChange)

tests/Invoke-Tests.ps1                    CHANGE — add -IncludeStateChange switch
```

## Defects from `reference/analysis.md` this milestone closes

- #4 "latest cores" without pinning — addressed via `Update-DownloadHashes` maintainer flow. Real hashes pinned in manifest.
- #12 (partial) `exit -1` on every missing file — we aggregate failures instead.
- #13 `Expand-Archive` shadowing built-in + hardcoded 7z path — renamed to `Expand-VerifiedArchive`, uses .NET for .zip.
- #17 PCSX2 1.6.0 / ePSXe 2.0.5 — not relevant for NES, but the data-driven manifest gives M7 a clean path to slot in DuckStation/PCSX2-Qt.
- #19 (partial) no behavior tests — integration test exercises the full pipeline.
- #22 Bundled homebrew ROMs — still bundled (per user choice) but the URLs are hash-pinned now.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| `Libretro.RetroArch` not in winget on this box | Preflight check before install attempt; document the alternate manual path |
| `--scope user` not supported on Libretro.RetroArch's manifest | Try `-UserScope`, fall back to default scope with a warning |
| RetroArch install path differs from upstream's `.emulationstation\systems\retroarch\` | Use Resolve-EmulatorPath result; templates already accept arbitrary path via `{{COMMAND}}` |
| Hash drift between `Update-DownloadHashes` run and end-user run | Buildbot nightly URLs are unstable. Use libretro **stable** URLs where possible; nightly only as a fallback with a documented re-hash cadence |
| Integration test mutates real machine state | Tagged `StateChange`; off by default; doc that running it installs RetroArch (uninstall via `winget uninstall Libretro.RetroArch` or M9) |
| `nesworld.com` HTTP-only or down | Use HTTPS variant where available; fall back to a GitHub-hosted homebrew mirror; verify hash regardless |
| Test isolation: integration test pollutes user's real `%USERPROFILE%\.emulationstation\` | Test always uses `-InstallRoot $tempDir`; never the real user profile |

## Exit criteria

1. Real SHA-256 values pinned in `manifest/downloads.psd1` for `fceumm-core` and `nes-assimilate`.
2. 13 new unit tests pass alongside existing 74. Total 87 unit green, 4+ NotRun (Network/StateChange).
3. With `-IncludeNetwork -IncludeStateChange` on a clean test directory: `Install-EmulationStation -Systems nes -InstallRoot $tempDir` produces:
   - `$tempDir\es_systems.cfg` (XML-valid, contains `<name>nes</name>`)
   - `$tempDir\es_settings.cfg`
   - `$tempDir\roms\nes\<homebrew>.nes` or contents thereof
   - A discoverable retroarch.exe (via Resolve-EmulatorPath)
   - The fceumm core in a cores directory the retroarch.exe will find
4. Manual demo: launch EmulationStation, see the NES system, pick a ROM, it boots.

## Order of implementation

1. `Expand-VerifiedArchive.ps1` + 3 unit tests. Smallest piece first, no dependencies on M5's other code.
2. `Update-DownloadHashes.ps1` + 2 unit tests. Maintainer cmdlet, used in step 4.
3. Run `Update-DownloadHashes` against current `manifest/downloads.psd1` to learn real hashes for fceumm-core and nes-assimilate. Update manifest.
4. `Install-EmulationStation.ps1` rewrite — full orchestration. 8 unit tests.
5. Add `-IncludeStateChange` to `tests/Invoke-Tests.ps1`.
6. Integration test in `tests/Integration/Install-NES.Tests.ps1`.
7. Run unit suite, full suite, then manual demo on your machine.
8. Commit.

## What M5 does NOT include

- The 12 other RetroArch systems. That's M6 (data-driven loop over the manifest).
- DuckStation / PCSX2 / Dolphin / RPCS3 / etc. That's M7.
- The recalbox-backport theme. M6 or M10.
- Install log + uninstaller. M8 / M9.
- Desktop shortcuts. M8.
- Cleanup of the install on test teardown. Out of scope; user runs `winget uninstall ...` or M9.
