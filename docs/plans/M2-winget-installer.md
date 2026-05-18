# M2 — winget package installer

**Goal:** ship idempotent winget-based package installation with runtime path resolution. Closes the upstream defects around (a) bootstrapping Chocolatey + Scoop with `iex $(downloaded)`, and (b) hardcoded `C:\tools\Dolphin-Beta\...` paths.

## What we're building

Three private cmdlets, structured for testability:

| Cmdlet | Responsibility |
|---|---|
| `Invoke-WinGet` | The *only* place the module shells out to `winget.exe`. Parses JSON output, surfaces stderr on failure. Mockable in tests. |
| `Install-WinGetPackage` | Idempotent install: query first, install/upgrade only when needed. |
| `Resolve-EmulatorPath` | Given a winget package ID, find where its executable lives by querying registry uninstall keys. Replaces hardcoded `C:\tools\...` paths. |

## Function contracts

### `Invoke-WinGet`
```powershell
Invoke-WinGet
    -Verb <list|install|upgrade|search|show>
    -Arguments <string[]>                    # extra winget args after the verb
    [-TimeoutSec <int>]                      # default 600
    [-ParseJson]                             # if set, JSON-parse stdout
```
Returns: parsed object (when `-ParseJson`) or raw string. Throws on non-zero exit with stderr in the message.

### `Install-WinGetPackage`
```powershell
Install-WinGetPackage
    -Id <string>                             # e.g., 'Dolphin.Dolphin'
    [-Version <string>]                      # pin; otherwise install latest
    [-UserScope]                             # --scope user; default is machine
    [-TimeoutSec <int>]                      # default 600
```
Returns:
```powershell
@{
    Status      = 'Installed' | 'AlreadyInstalled' | 'Upgraded'
    Id          = 'Dolphin.Dolphin'
    DisplayName = 'Dolphin Emulator'
    Version     = '5.0-21342'
}
```

### `Resolve-EmulatorPath`
```powershell
Resolve-EmulatorPath
    -PackageId <string>                      # winget package ID
    [-ExecutableName <string>]               # filter to specific .exe in the install dir
```
Returns: install directory (default) or full path to the executable.

## Algorithms

### `Install-WinGetPackage`
```
1. Validate $Id matches [A-Za-z0-9._-]+ (no shell metachars).
2. existing = Invoke-WinGet -Verb list -Arguments @('--id', $Id, '--exact') -ParseJson
3. If $existing has a match:
     installedVersion = $existing.Version
     If -not $Version OR $installedVersion -eq $Version:
         return @{ Status = 'AlreadyInstalled'; ... }
     Else:
         Invoke-WinGet -Verb upgrade -Arguments @(...with --version $Version, --silent, ...)
         return @{ Status = 'Upgraded'; Version = $Version }
4. Else (no existing match):
     args = @('--id', $Id, '--exact', '--silent',
              '--accept-package-agreements', '--accept-source-agreements')
     if $Version:   args += @('--version', $Version)
     if $UserScope: args += @('--scope', 'user')
     Invoke-WinGet -Verb install -Arguments $args
     after = Invoke-WinGet -Verb list -Arguments @('--id', $Id, '--exact') -ParseJson
     return @{ Status = 'Installed'; ... from $after }
```

### `Resolve-EmulatorPath`
```
1. Get the package's DisplayName from `winget show` or `winget list` JSON.
2. Search registry uninstall keys (HKLM, HKLM\WOW6432Node, HKCU) for entries
   where DisplayName matches.
3. Read the InstallLocation property.
4. If $ExecutableName specified:
     full = Join-Path $InstallLocation $ExecutableName
     If Test-Path $full: return $full else throw.
5. Else return $InstallLocation.
```

## Testing strategy

`Invoke-WinGet` itself is the chokepoint — we **mock it** in the unit tests for the other two cmdlets. We do not mock `winget.exe` directly.

### Unit tests for `Install-WinGetPackage` (mocked `Invoke-WinGet`)

| # | Test | Asserts |
|---|---|---|
| 1 | Install when not present | `Invoke-WinGet install` called once, returns Status='Installed' |
| 2 | Idempotent: already installed, matching version | only one `list` call, no install/upgrade, Status='AlreadyInstalled' |
| 3 | Already installed but different version → upgrade | `upgrade` called, Status='Upgraded' |
| 4 | UserScope adds `--scope user` to install args | argument list contains 'user' |
| 5 | Invalid Id (empty or special chars) | parameter validation throws |
| 6 | Invoke-WinGet throws (non-zero exit) | error surfaces, no partial state |

### Unit tests for `Resolve-EmulatorPath`

For these we mock `Get-ItemProperty` to simulate registry returns.

| # | Test | Asserts |
|---|---|---|
| 1 | Found via HKLM | returns InstallLocation |
| 2 | Found via HKCU when absent from HKLM | returns InstallLocation |
| 3 | DisplayName mismatch in all hives | throws "not found" |
| 4 | ExecutableName matches a file under InstallLocation | returns full path |
| 5 | ExecutableName missing under InstallLocation | throws |

### Unit tests for `Invoke-WinGet`

Mocking a native exe is harder; we mock `Start-Process` (which we'll use to launch winget) or use Pester's `Mock` on `Invoke-WinGet`'s internal call. Approach: use `Mock & { … }` to intercept the native call. **Tests cover:**

| # | Test | Asserts |
|---|---|---|
| 1 | Verb + args composed correctly | invocation receives expected args |
| 2 | Non-zero exit throws with stderr | error message includes the captured stderr |
| 3 | `-ParseJson` parses valid JSON | returns the object |
| 4 | `-ParseJson` on invalid JSON | throws clearly |

### Integration test (tagged `Network`, opt-in)

One test that does NOT mutate machine state:
- `Install-WinGetPackage -Id Microsoft.PowerShell` → expect `Status = 'AlreadyInstalled'` (user has PS 7.6.1 already).
- `Resolve-EmulatorPath -PackageId Microsoft.PowerShell -ExecutableName pwsh.exe` → expect a path that exists.

We deliberately avoid installing anything in the integration test to keep it side-effect-free. Manual demo will install something real.

## Manual demo (for exit-criteria check)

Once tests pass:
```powershell
Import-Module .\src\EmulationStationSetup.psd1 -Force
InModuleScope EmulationStationSetup {
    $r = Install-WinGetPackage -Id '7zip.7zip'         # likely AlreadyInstalled on this box
    $r | Format-Table
    Resolve-EmulatorPath -PackageId '7zip.7zip' -ExecutableName '7z.exe'
}
```
Expected: prints a hashtable with Status, then prints a real path to `7z.exe`.

## Files M2 adds or changes

```
src/private/
  Invoke-WinGet.ps1                                  NEW
  Install-WinGetPackage.ps1                          NEW
  Resolve-EmulatorPath.ps1                           NEW

tests/Unit/
  Invoke-WinGet.Tests.ps1                            NEW
  Install-WinGetPackage.Tests.ps1                    NEW
  Resolve-EmulatorPath.Tests.ps1                     NEW

tests/Integration/
  WinGet.Network.Tests.ps1                           NEW (tagged Network)
```

No public-cmdlet changes. Manifests untouched.

## Defects from `reference/analysis.md` this milestone closes

- #6 `Set-ExecutionPolicy Bypass` + `iex` of Chocolatey installer — *not used*, we replace it with `Invoke-WinGet`.
- #7 Mixed-trust sources (third-party Scoop bucket, dl.coolatoms.org for some bits) — no Scoop, no third-party buckets in this path.
- #8 (partial) Admin elevation + machine-wide package state — when `-UserScope`, no admin required.
- #9 Hardcoded binary paths — replaced with `Resolve-EmulatorPath`.
- #11 Force-killing processes (winget's `--silent` is the supported way) — eliminated.
- #14 Non-idempotent installs — check-then-install pattern.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| winget JSON output format varies across versions | Pin parse on `--output json` only; preflight required ≥1.6 (M0); fall back to a tolerant parser |
| Some packages don't register `InstallLocation` (MSIX, store apps) | Document; `Resolve-EmulatorPath` throws with a clear "no install location for X" message |
| Mocking a native `winget` call in Pester | Centralize through `Invoke-WinGet`; tests mock that wrapper, not the binary |
| Registry queries slow without filter | `Get-ItemProperty -Name DisplayName` then filter; not enumerated as a hashtable |
| `winget install` can prompt despite `--silent` if dependencies need confirmation | Always pass `--accept-package-agreements --accept-source-agreements`; document the rare case |
| Integration test depends on user having Microsoft.PowerShell | Acceptable — preflight already requires PS 7.4+; if winget doesn't know about it, test skips |

## Exit criteria

1. Three new private cmdlets dot-sourced into the module; smoke test still green.
2. Unit test count rises: M0 (21) + M1 (12) + M2 (15) = 48 passing, plus 2 NotRun (Network).
3. `-IncludeNetwork` runs green: 50/50 including 2 integration tests (preflight + winget).
4. Manual demo prints a Status and a real 7-Zip path on your machine.

## Order of implementation

1. `Invoke-WinGet.ps1` — minimum viable wrapper, with `-ParseJson`.
2. Smoke + 4 unit tests for `Invoke-WinGet`. Confirm module still loads, run suite.
3. `Install-WinGetPackage.ps1` body 1: install-when-not-present path only.
4. 1 unit test for that path.
5. Add idempotency branch + 1 test.
6. Add upgrade branch + 1 test.
7. Add `-UserScope` handling + 1 test.
8. Add parameter validation + 1 test.
9. `Resolve-EmulatorPath.ps1` + 5 unit tests.
10. Integration test against `Microsoft.PowerShell`.
11. Run full suite both ways. Manual demo. Commit.

## What M2 does NOT include

- Wiring `Install-WinGetPackage` into `Install-EmulationStation`. That's M5.
- Choosing which winget package IDs we'll use for which emulators. That's M3 (the manifest) and M7 (console-specific).
- Handling MSIX-only packages without an InstallLocation. Out of scope until we hit one in M7.
- Uninstall via winget. M9 will offer `-RemoveWinGetPackages` as an opt-in.
