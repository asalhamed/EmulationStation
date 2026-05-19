# M8 — Install log + shortcuts

**Goal:** make the install reversible (M9 needs a record to undo from) and launchable (a Start Menu / Desktop shortcut so the user can actually run EmulationStation). After M8, every action `Install-EmulationStation` takes is recorded in a structured log, and the user has a clickable way to launch ES.

## What we're building

### 1. Install log

A structured JSON file at `$InstallRoot\install-log.json` that records every observable action. Format:

```json
{
  "Version": 1,
  "Created": "2026-05-18T14:23:01Z",
  "Actions": [
    { "Timestamp": "2026-05-18T14:23:02Z", "Kind": "WinGetInstall", "Id": "Libretro.RetroArch", "Status": "Installed", "Version": "1.17.0" },
    { "Timestamp": "2026-05-18T14:23:10Z", "Kind": "DirectoryCreated", "Path": "C:\\Users\\you\\.emulationstation\\roms\\nes" },
    { "Timestamp": "2026-05-18T14:23:12Z", "Kind": "FileWritten", "Path": "C:\\Users\\you\\.emulationstation\\roms\\nes\\assimilate.nes", "Sha256": "529f..." },
    { "Timestamp": "2026-05-18T14:23:15Z", "Kind": "ConfigRendered", "Path": "C:\\Users\\you\\.emulationstation\\es_systems.cfg" },
    { "Timestamp": "2026-05-18T14:23:16Z", "Kind": "ShortcutCreated", "Path": "C:\\Users\\you\\AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs\\EmulationStation.lnk", "Target": "C:\\Program Files (x86)\\EmulationStation\\emulationstation.exe" }
  ]
}
```

**Append-only semantics:** every `Install-EmulationStation` run reads the existing log, appends new actions, writes the whole file back. We don't truncate or rewrite history.

**Action kinds (v1):**
- `WinGetInstall` — winget package installed/upgraded. `Id`, `Status`, `Version`.
- `WinGetSkipped` — package was already at target version. `Id`, `Version`.
- `DirectoryCreated` — `Path`.
- `FileWritten` — a file we *placed* (extracted, downloaded into final location, or rendered). `Path`, optional `Sha256`.
- `ConfigRendered` — `Path` (es_systems.cfg, es_settings.cfg, dolphin.ini).
- `ShortcutCreated` — `Path` (the .lnk), `Target` (what it launches).
- `Run` — internal marker: `Started` and `Finished` actions wrap each invocation with timing + outcome.

M9 (uninstaller) walks the actions in reverse and undoes each Kind it knows how to.

### 2. Shortcuts

Create `.lnk` shortcuts via the `WScript.Shell` COM object:

- **Start Menu:** `$env:APPDATA\Microsoft\Windows\Start Menu\Programs\EmulationStation.lnk` (user-scope, no admin needed)
- **Desktop:** `$env:USERPROFILE\Desktop\EmulationStation.lnk`

Both point at the `EmulationStation.exe` path passed to `Install-EmulationStation`. If the exe doesn't exist, we record a warning in `Failures` and skip — we don't create dangling shortcuts.

### 3. Orchestrator wiring

`Install-EmulationStation` gains:

```powershell
[string] $EmulationStationExe        # default: %ProgramFiles(x86)%\EmulationStation\emulationstation.exe
[switch] $NoShortcuts                # default off; opt-out for headless / CI
[switch] $NoInstallLog               # default off; opt-out for ephemeral tests
```

Steps wired:
- Before any action: `Start-InstallLog` opens (or creates) the log, records a `Started` action.
- After each major step: append the appropriate action.
- At end: `Stop-InstallLog` records a `Finished` action with the summary.
- Just before returning: if `-NoShortcuts` not set, create shortcuts (recording `ShortcutCreated`).

The summary returned by `Install-EmulationStation` gets an extra field: `LogPath`.

## Function contracts

### `Write-InstallLog`
```powershell
Write-InstallLog
    -LogPath <string>
    -Action <hashtable>           # { Kind = 'X'; ... }
```
Appends `$Action` (with `Timestamp` auto-injected if absent) to the `Actions` array. Creates the file with a `Version=1` skeleton if missing. Atomic write via `.tmp` + rename.

### `New-EmulationStationShortcut`
```powershell
New-EmulationStationShortcut
    -TargetExe <string>
    -ShortcutPath <string>
    [-WorkingDirectory <string>]
    [-Description <string>]
```
Throws if `TargetExe` doesn't exist (caller decides whether to swallow). Idempotent — overwrites existing shortcut at the same path.

## Test plan

`tests/Unit/Write-InstallLog.Tests.ps1` — 4 tests:
1. Creates the file on first call with the v1 skeleton.
2. Appends an action to an existing log.
3. Injects Timestamp automatically when not provided.
4. Multiple calls accumulate actions in order.

`tests/Unit/New-EmulationStationShortcut.Tests.ps1` — 3 tests:
1. Creates a .lnk file at the expected path.
2. The .lnk's TargetPath equals the input TargetExe.
3. Throws when TargetExe doesn't exist on disk.

`tests/Unit/Install-EmulationStation.Tests.ps1` — extend with 2 tests:
1. Install run produces an install-log.json with `Started` and `Finished` actions.
2. `-NoShortcuts` skips shortcut creation; the absence of `ShortcutCreated` actions is visible in the log.

Integration test: extend `tests/Integration/Install-NES.Tests.ps1` to also assert that:
- `install-log.json` exists in `$InstallRoot`
- It parses as JSON with `Version = 1`
- It contains at least one `Started` and one `Finished` action

Total: 9 new unit tests + 3 new integration assertions.

## Files M8 adds or changes

```
src/private/
  Write-InstallLog.ps1                  NEW
  New-EmulationStationShortcut.ps1      NEW
src/public/
  Install-EmulationStation.ps1          CHANGE — wire log + shortcuts
tests/Unit/
  Write-InstallLog.Tests.ps1            NEW
  New-EmulationStationShortcut.Tests.ps1   NEW
  Install-EmulationStation.Tests.ps1    EXTEND (2 new It blocks)
tests/Integration/
  Install-NES.Tests.ps1                 EXTEND (log assertions)
```

## Defects from `reference/analysis.md` this milestone closes

None remaining from the 24-item list — they all closed by M7. M8 is forward-looking: enables M9's uninstaller (which closes a brand-new concern: clean removal, not present in upstream's `prepare.ps1` at all).

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| WScript.Shell COM not available on locked-down boxes | Try/catch around the creation; log the failure into `Failures`, don't break the install |
| Atomic log write fails mid-rename | We write to `.tmp` + Move-Item; ENotEmpty / sharing violation gets surfaced as a regular IO error and continues. Worst case: log temporarily missing one action; the install isn't blocked |
| Install log grows unboundedly across many runs | Acceptable for v0.1 — runs are infrequent and each adds a handful of KB. M10 can add `-RotateLog` if it becomes a real issue |
| Shortcut points at a path that gets removed later | M9 uninstaller cleans up shortcuts as part of reverse-replay. Until then, user manually deletes if needed |
| User has EmulationStation at a non-default path | Default is `%ProgramFiles(x86)%\EmulationStation\emulationstation.exe`; if missing, `-EmulationStationExe` overrides. Shortcut step is skipped on missing exe (logged in `Failures`, not fatal) |
| Append-only JSON is read-modify-write — race on concurrent installs | Out of scope; we don't expect concurrent invocations. Document |

## Exit criteria

1. Two new private cmdlets (`Write-InstallLog`, `New-EmulationStationShortcut`).
2. 9 new unit tests pass alongside existing 88. Total 97 unit, integration suite still green.
3. After `Install-EmulationStation -Systems nes -InstallRoot $tmp`, `$tmp\install-log.json` exists, parses, contains the expected actions.
4. If `EmulationStation.exe` exists at the configured path, Start Menu + Desktop shortcuts created and clickable.

## Order of implementation

1. `Write-InstallLog.ps1` + 4 unit tests.
2. `New-EmulationStationShortcut.ps1` + 3 unit tests.
3. Wire both into `Install-EmulationStation.ps1` (new parameters, append actions, `LogPath` in summary).
4. Add 2 unit tests to `Install-EmulationStation.Tests.ps1` (mock helpers to assert wiring).
5. Extend integration test in `Install-NES.Tests.ps1` for log assertions.
6. Run full suite both ways. Commit.

## What M8 does NOT include

- Actually installing EmulationStation itself (the frontend EXE). User-supplied for v0.1; M10 will integrate as a `EmulatorAsset` download with an installer-run action.
- Bidirectional log → state diff (`Resolve-InstallState`). M9 walks the log in reverse without needing this.
- Log rotation or compaction. M10 if needed.
- A `Get-InstallHistory` public cmdlet. M9 or M10 can expose if useful.
