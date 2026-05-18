# M0 — Foundations

**Goal:** establish the skeleton of the module — directory structure, Pester harness, manifest schema, preflight checks — with no install behavior yet. After M0, `Invoke-Pester` runs green and `Test-EmulationStationInstall -PreflightOnly` works on the user's Win 11 box.

## What we're building

A skeleton that compiles, tests, and can answer "is this machine ready to install?" — but does not yet install anything. Every later milestone slots into this skeleton.

## Files we'll create

```
EmulationStation/
├── .gitignore
├── .editorconfig
├── README.md                                stub (full version in M10)
├── CHANGELOG.md                             starts at "Unreleased"
├── src/
│   ├── EmulationStationSetup.psd1           module manifest
│   ├── EmulationStationSetup.psm1           loader: dot-sources public + private
│   ├── public/
│   │   ├── Install-EmulationStation.ps1     stub: throws NotImplementedException
│   │   ├── Uninstall-EmulationStation.ps1   stub
│   │   ├── Test-EmulationStationInstall.ps1 -PreflightOnly works; full audit stubbed
│   │   └── Get-EmulationStationManifest.ps1 works (just reads + returns)
│   └── private/
│       ├── Types.ps1                        classes: PreflightCheck, InstallReport
│       ├── Assert-Prerequisite.ps1          5 checks (PS, Win, winget, disk, network)
│       └── Resolve-Manifest.ps1             minimal validator; expands in M3
├── manifest/
│   ├── systems.psd1                         starts empty: @{ Systems = @() }
│   ├── packages.psd1                        starts empty
│   └── downloads.psd1                       starts empty
├── tests/
│   ├── Invoke-Tests.ps1                     runner script
│   ├── EmulationStationSetup.Tests.ps1      smoke: module imports + exports
│   ├── Unit/
│   │   ├── Assert-Prerequisite.Tests.ps1    mocked OS/winget/disk
│   │   ├── Resolve-Manifest.Tests.ps1       schema happy + sad paths
│   │   └── Types.Tests.ps1                  class instantiation
│   └── Integration/
│       └── Preflight.Tests.ps1              hits the real system (Windows-only)
└── docs/
    └── plans/
        └── M0-foundations.md (this file)
```

## Module manifest decisions (`EmulationStationSetup.psd1`)

| Key | Value | Why |
|---|---|---|
| `PowerShellVersion` | `'7.4'` | Per ADR-0001; eliminates PS 5 TLS bypass need |
| `CompatiblePSEditions` | `@('Core')` | Win PowerShell 5.1 is `Desktop`, we want Core only |
| `RequiredModules` | none for runtime | Pester is dev-only |
| `FunctionsToExport` | the 4 public cmdlets, by exact name | Strict; no wildcards (security best practice) |
| `CmdletsToExport` / `VariablesToExport` / `AliasesToExport` | `@()` | Explicit empty arrays, not `'*'` |
| `PrivateData.PSData.Tags` | `'EmulationStation', 'Emulator', 'Retro'` | For when/if we publish |
| `RootModule` | `'EmulationStationSetup.psm1'` | |
| `ModuleVersion` | `'0.1.0'` | SemVer; bump as we go |

## Module loader (`EmulationStationSetup.psm1`)

```powershell
# Dot-source types first (classes need to be defined before any function that uses them)
. $PSScriptRoot\private\Types.ps1

# Dot-source private then public
foreach ($file in Get-ChildItem $PSScriptRoot\private\*.ps1 -Exclude 'Types.ps1') {
    . $file.FullName
}
foreach ($file in Get-ChildItem $PSScriptRoot\public\*.ps1) {
    . $file.FullName
}

Export-ModuleMember -Function (Get-ChildItem $PSScriptRoot\public\*.ps1).BaseName
```

Pattern rationale: dot-sourcing keeps each function in its own file (easier diffs, easier tests). `Export-ModuleMember` based on the `public/` directory is intentional — adding a public cmdlet is one file, no manifest edit needed (we'll keep `FunctionsToExport` in sync as a belt-and-braces check that catches drift in CI).

## Types (`src/private/Types.ps1`)

PowerShell 7 classes. Kept private (not exported) — consumers see PSCustomObject shapes.

```powershell
enum PreflightStatus { Pass; Fail; Warn }

class PreflightCheck {
    [string] $Name
    [PreflightStatus] $Status
    [string] $Detail
    [string] $Remediation        # optional: how to fix if Fail
}

class InstallReport {
    [datetime] $When
    [PreflightCheck[]] $Checks
    [bool] $OverallPass
}
```

Note: classes in `.psm1`-loaded files have a known issue where they're not visible cross-module. We address this by putting types in a single file and dot-sourcing it *first* in the loader. For M0 we don't need cross-module reach, so this is fine.

## Preflight checks (`src/private/Assert-Prerequisite.ps1`)

Five checks, each independent, each returning a `[PreflightCheck]`:

| # | Name | How we check | Pass criterion |
|---|---|---|---|
| 1 | PowerShell version | `$PSVersionTable.PSVersion` | `>= [version]'7.4'` |
| 2 | Windows version | `[Environment]::OSVersion.Version` | Build `>= 17763` (Win 10 1809) |
| 3 | winget available | `Get-Command winget -ErrorAction SilentlyContinue` + parse `winget --version` | Present, `>= '1.6'` |
| 4 | Free disk | `Get-PSDrive C \| Select-Object Free` | `>= 10GB` |
| 5 | Network reach | `Test-Connection github.com -Count 1 -Quiet` | True |

Function signature:
```powershell
function Assert-Prerequisite {
    [CmdletBinding()]
    [OutputType([PreflightCheck[]])]
    param(
        [string[]] $Skip = @()    # opt out of specific checks by name (testing)
    )
    # … runs each check, returns array
}
```

Why array-of-results, not throw-on-fail: the public cmdlet wants to *report* all problems at once, not bail on the first. Our working principle #7.

## Public `Test-EmulationStationInstall -PreflightOnly`

```powershell
function Test-EmulationStationInstall {
    [CmdletBinding()]
    [OutputType([InstallReport])]
    param(
        [string] $InstallRoot = (Join-Path $env:USERPROFILE '.emulationstation'),
        [switch] $PreflightOnly
    )

    if ($PreflightOnly) {
        $checks = Assert-Prerequisite
        return [InstallReport]@{
            When        = Get-Date
            Checks      = $checks
            OverallPass = ($checks | Where-Object Status -eq 'Fail').Count -eq 0
        }
    }

    throw [System.NotImplementedException]::new(
        'Full audit lands in M10. Use -PreflightOnly for now.'
    )
}
```

## Manifest schema (M0 minimum)

`manifest/systems.psd1`:
```powershell
@{
    SchemaVersion = 1
    Systems       = @()    # entries land in M3 / M6 / M7
}
```

`Resolve-Manifest` for M0:
- Reads the PSD1.
- Asserts `SchemaVersion -eq 1`.
- Asserts `Systems` is an array.
- Returns the imported hashtable.

Full schema validation (required keys, regex validation, package existence) lands in M3.

## Pester strategy

**Pester version:** 5.x. Dev-only dependency. README will say `Install-Module Pester -Scope CurrentUser -MinimumVersion 5.0`.

**Unit tests** (`tests/Unit/`):
- Mock everything that touches the system (`Get-Command`, `Get-CimInstance`, `Test-Connection`, `Get-PSDrive`).
- Run on any host, including non-Windows (for portability of the test code).
- Fast — <1s for the whole unit suite.

**Integration tests** (`tests/Integration/`):
- Hit the real machine.
- Gated by `[if ($IsWindows)]`.
- For M0, just one: "preflight returns OverallPass=true on this developer machine."

**Runner** (`tests/Invoke-Tests.ps1`):
- Imports Pester, runs both directories, exits with Pester's exit code.
- Used by us locally; future-Claude calls it before declaring milestones done.

## Sample tests to write

### `Unit/Assert-Prerequisite.Tests.ps1`
```
Describe 'Assert-Prerequisite' {
    Context 'PowerShell version check' {
        It 'passes when PSVersion >= 7.4' { ... }
        It 'fails when PSVersion < 7.4' { ... }
    }
    Context 'Windows version check' {
        It 'passes on build 17763+' { ... }
        It 'fails on Win 10 1803 (build 17134)' { ... }
    }
    Context 'winget availability' {
        It 'fails when winget is not on PATH' {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'winget' }
            (Assert-Prerequisite | Where-Object Name -eq 'winget').Status | Should -Be 'Fail'
        }
    }
    Context '-Skip parameter' {
        It 'omits checks by name' {
            (Assert-Prerequisite -Skip @('Network')).Name | Should -Not -Contain 'Network'
        }
    }
}
```

### `EmulationStationSetup.Tests.ps1` (smoke)
```
Describe 'Module load' {
    It 'imports without error' {
        { Import-Module $PSScriptRoot\..\src\EmulationStationSetup.psd1 -Force } | Should -Not -Throw
    }
    It 'exports exactly the 4 public cmdlets' {
        (Get-Module EmulationStationSetup).ExportedFunctions.Keys |
            Should -BeExactly @(
                'Get-EmulationStationManifest',
                'Install-EmulationStation',
                'Test-EmulationStationInstall',
                'Uninstall-EmulationStation'
            )
    }
}
```

## Risks & how we'll handle them

| Risk | Mitigation |
|---|---|
| Classes in dot-sourced files have visibility quirks | Single `Types.ps1` loaded first; verified by smoke test |
| Pester 5 missing on the user's machine | Readme spells out one-line install; preflight could warn if missing in dev mode (not for end users) |
| `winget --version` output format drift | Parse defensively — find first version-like substring; covered by unit test with several real outputs |
| `Test-Connection github.com` blocked by corporate firewall | Mark Network as `Warn` not `Fail` if it's the only failing check; document |
| `Get-PSDrive C` doesn't exist (non-C system drive) | Use `$env:SystemDrive` instead; covered by unit test |

## Exit criteria

All of these must be true before we mark M0 done:

1. `Import-Module .\src\EmulationStationSetup.psd1` succeeds.
2. `Get-Command -Module EmulationStationSetup` lists exactly 4 public cmdlets.
3. `.\tests\Invoke-Tests.ps1` exits 0; Unit suite + Integration suite both green.
4. On the user's Win 11 box: `Test-EmulationStationInstall -PreflightOnly` returns an `InstallReport` with `OverallPass = $true`.
5. `Get-EmulationStationManifest` returns the (empty) typed manifest object.

## Order of operations (when implementing)

1. `.gitignore`, `README.md` stub, `CHANGELOG.md` — repo hygiene.
2. Module manifest + loader + Types — minimum bootable scaffold.
3. Manifest PSD1s (empty) + `Resolve-Manifest` — read path works.
4. `Assert-Prerequisite` + `Test-EmulationStationInstall -PreflightOnly` — preflight works.
5. Stub the other 3 public cmdlets.
6. Pester runner + smoke test.
7. Unit tests for `Assert-Prerequisite` and `Resolve-Manifest`.
8. Integration test (preflight on this box).
9. Run all tests, confirm green, run preflight on the user's box.

## What M0 does NOT include

These are deferred and named explicitly so we don't accidentally pull them in:

- Downloading anything. (M1)
- Installing winget packages. (M2)
- Real system manifest entries. (M3)
- Config templates. (M4)
- Actual install behavior. (M5+)
- Logging. (M8)
- Documentation beyond a stub README. (M10)
