# M3 — System data model

**Goal:** lock down the schema for `manifest/systems.psd1` and `manifest/downloads.psd1`, harden `Resolve-Manifest` so it rejects malformed declarations with clear errors, and return typed objects that M4–M7 can iterate over without re-parsing.

After M3, "add a new system" is a manifest edit, not a code change. M3 itself ships **one example** (NES) end-to-end through the data model; full population lands in M6 / M7.

## What we're building

### Schema for `manifest/systems.psd1`

```powershell
@{
    SchemaVersion = 1
    Systems = @(
        @{
            Name          = 'nes'                           # required, ^[a-z][a-z0-9_-]*$
            FullName      = 'Nintendo Entertainment System' # required
            Platform      = 'nes'                           # optional, defaults to Name
            Theme         = 'nes'                           # optional, defaults to Name
            RomExtensions = @('.nes', '.fds', '.unif', '.unf')  # required, each starts with '.'
            Notes         = 'Homebrew compilation by Wave 5'    # optional
            Launcher      = @{
                Kind         = 'Libretro'                   # required: 'Libretro' | 'Standalone'
                LibretroCore = 'fceumm_libretro.dll'        # required when Kind = 'Libretro'
            }
            Packages      = @('Libretro.RetroArch')         # required (may be empty array)
            Artifacts     = @{                              # required (may be empty hashtable)
                Core    = 'fceumm-core'                     # values reference keys in downloads.psd1
                Homebrew = 'nes-assimilate'
            }
        }
        @{
            Name          = 'psx'
            FullName      = 'PlayStation'
            RomExtensions = @('.cue', '.iso', '.bin', '.chd', '.pbp')
            Launcher      = @{
                Kind            = 'Standalone'
                PackageId       = 'Stenzek.DuckStation'     # required when Kind = 'Standalone'
                ExecutableName  = 'duckstation-qt-x64-ReleaseLTCG.exe'
                CommandTemplate = '"%EXE%" -batch -- "%ROM%"'
            }
            Packages      = @('Stenzek.DuckStation')
            Artifacts     = @{ Homebrew = 'psx-marilyn' }
        }
    )
}
```

### Schema for `manifest/downloads.psd1`

```powershell
@{
    SchemaVersion = 1
    Downloads = @{
        'fceumm-core' = @{
            Url    = 'https://buildbot.libretro.com/nightly/windows/x86_64/latest/fceumm_libretro.dll.zip'
            Sha256 = '...'                  # 64-hex; required
            Kind   = 'LibretroCore'         # 'LibretroCore' | 'Rom' | 'Theme' | 'EmulatorAsset'
        }
        'nes-assimilate' = @{
            Url    = 'https://www.nesworld.com/homebrew/assimilate_full.zip'
            Sha256 = '...'
            Kind   = 'Rom'
            System = 'nes'                  # required when Kind = 'Rom'; tells M5+ where to drop it
        }
    }
}
```

### Validation rules

For **each system** in `Systems`:
- `Name`: required, string, matches `^[a-z][a-z0-9_-]*$`. Uniqueness enforced across the array.
- `FullName`: required, non-empty string.
- `Platform`: optional string; defaults to `Name`.
- `Theme`: optional string; defaults to `Name`.
- `RomExtensions`: required, non-empty array, each entry matches `^\.[a-z0-9]+$` (lowercase, leading dot).
- `Notes`: optional string.
- `Launcher`: required, hashtable.
  - `Kind`: required, must be `'Libretro'` or `'Standalone'`.
  - If `Libretro`: `LibretroCore` required, string ending `.dll`.
  - If `Standalone`: `PackageId`, `ExecutableName`, `CommandTemplate` all required strings.
- `Packages`: required array (may be empty). Each element matches winget ID regex `^[A-Za-z0-9._-]+$`.
- `Artifacts`: required hashtable (may be empty). Each value must be a string key that exists in `downloads.psd1` (cross-manifest validation).

For **each download** in `Downloads`:
- Key (the artifact reference name): matches `^[a-z][a-z0-9-]*$`.
- `Url`: required, must start with `https://`.
- `Sha256`: required, 64 hex chars.
- `Kind`: required, one of `LibretroCore`, `Rom`, `Theme`, `EmulatorAsset`.
- If `Kind = 'Rom'`: `System` required, must match a system Name.

### Resolve-Manifest contract change

Before M3: reads PSD1, returns hashtable, only validates SchemaVersion.

After M3: reads PSD1, validates the full schema, returns typed objects. Throws on the first violation with a path like `systems.psd1: Systems[3].Launcher.LibretroCore is required when Kind='Libretro'`.

```powershell
Resolve-Manifest -ManifestRoot <path>          # NEW: takes a directory; reads systems + downloads
# Returns: PSCustomObject with .Systems and .Downloads, both validated.
```

The old single-file signature `Resolve-Manifest -Path` becomes a private helper.

## Types (additions to `src/private/Types.ps1`)

```powershell
enum LauncherKind { Libretro; Standalone }
enum DownloadKind { LibretroCore; Rom; Theme; EmulatorAsset }

class EmulatorSystem {
    [string]   $Name
    [string]   $FullName
    [string]   $Platform
    [string]   $Theme
    [string[]] $RomExtensions
    [string]   $Notes
    [hashtable] $Launcher                  # keep as hashtable; polymorphic shape
    [string[]] $Packages
    [hashtable] $Artifacts                 # keys → download IDs
}

class DownloadSpec {
    [string]       $Id                     # the key from downloads.psd1
    [string]       $Url
    [string]       $Sha256
    [DownloadKind] $Kind
    [string]       $System                 # only meaningful for Roms
}
```

We keep `Launcher` and `Artifacts` as hashtables rather than classes — they're small, polymorphic, and treating them as data is simpler than a sealed type hierarchy for two cases.

## Test plan

12 tests in `tests/Unit/Resolve-Manifest.Tests.ps1` (replaces the 4 we have). Plus 2 in a new `tests/Unit/Get-EmulationStationManifest.Tests.ps1`.

### `Resolve-Manifest` tests

| # | Test | Asserts |
|---|---|---|
| 1 | Valid systems + downloads parse OK | returns PSCustomObject with Systems[].EmulatorSystem and Downloads[].DownloadSpec |
| 2 | SchemaVersion missing on systems.psd1 | throws |
| 3 | SchemaVersion 999 (unsupported) | throws with version |
| 4 | systems.psd1 not found | throws |
| 5 | System missing Name | throws with field path |
| 6 | System Name with uppercase | throws with regex hint |
| 7 | Duplicate system Name | throws |
| 8 | RomExtension without leading dot | throws |
| 9 | Launcher.Kind = 'Bogus' | throws with allowed values |
| 10 | Libretro launcher missing LibretroCore | throws |
| 11 | Standalone launcher missing PackageId | throws |
| 12 | System Artifact references missing download | throws with both keys in message |
| 13 | Download with http:// URL | throws |
| 14 | Download with bad SHA-256 (non-hex) | throws |
| 15 | Rom-kind download missing System | throws |

That's 15. Slightly above the 12 target but each is mechanical.

### `Get-EmulationStationManifest` tests

| # | Test | Asserts |
|---|---|---|
| 1 | Returns Systems and Downloads from the real manifest | both arrays present, types correct |
| 2 | Defaults Platform = Name when unset | EmulatorSystem.Platform == Name |

## Files M3 adds or changes

```
docs/plans/M3-system-data-model.md                NEW (this file)

manifest/systems.psd1                             CHANGE — one NES example entry
manifest/downloads.psd1                           CHANGE — one core + one homebrew entry
manifest/packages.psd1                            DELETE — folding pinning into systems entries

src/private/Types.ps1                             CHANGE — add LauncherKind, DownloadKind, EmulatorSystem, DownloadSpec
src/private/Resolve-Manifest.ps1                  REWRITE — full schema validation, takes -ManifestRoot, returns typed
src/public/Get-EmulationStationManifest.ps1       CHANGE — uses the new Resolve-Manifest signature

tests/Unit/Resolve-Manifest.Tests.ps1             EXPAND — 15 tests covering every validation rule
tests/Unit/Get-EmulationStationManifest.Tests.ps1 NEW (2 tests)
```

`Get-EmulationStationManifest` is already a public cmdlet. After M3 its `ManifestRoot` parameter takes a *directory* path; the previous behavior of reading three separate files via internal `Resolve-Manifest -Path` is encapsulated.

## Trade-offs we're locking in

- **Polymorphic `Launcher`** stays a hashtable, not a class hierarchy. Keeps PSD1 readable, accepts that the schema's polymorphism is documented elsewhere (here).
- **No separate `packages.psd1`** — version pins (when needed) live on the system entry, e.g. `Packages = @(@{ Id='Libretro.RetroArch'; Version='1.17.0' })`. M3 supports both string-only (`'Libretro.RetroArch'`) and pinned-hashtable shapes; that polymorphism is tested in #11-ish (folded into existing).
- **Cross-manifest validation** is eager: bad reference = manifest doesn't load. Slow-fail rejected; we want bad data to surface at the start, not mid-install.
- **Names lowercase** — matches ES's convention and avoids case-collision headaches across the filesystem on case-insensitive Windows.

## Defects from `reference/analysis.md` this milestone closes

- #18 ~700-line copy-paste install logic — schema enables the generic install loop landing in M6.
- #19 (partial) no tests — schema gets fully covered.
- #20 `es_systems.cfg` baked into a heredoc — manifest now is the source of truth; the heredoc gets replaced by a template render in M4.
- #23 No way to opt out of individual systems — the manifest is queryable; `Install-EmulationStation -Systems nes,snes` (M5) becomes natural.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Schema lock-in too early — we'll need fields we haven't thought of | `SchemaVersion = 1`; bump to 2 with migration if needed. Acceptable cost. |
| Polymorphic Launcher hashtable is harder to refactor later | Hide it behind the `Resolve-Manifest` boundary; consumers only read it after validation passes. |
| Duplicate-Name detection across array entries is O(n²) without care | Use a `HashSet<string>` during parse. n is < 30, doesn't actually matter. |
| Schema rules differ subtly from upstream's es_systems.cfg expectations | Manual spot-check M4-rendered output against upstream's es_systems.cfg syntax for two example systems (NES + PSX) before declaring M3 done. |

## Exit criteria

1. `manifest/systems.psd1` has one valid NES entry.
2. `manifest/downloads.psd1` has matching entries that the NES system references.
3. `manifest/packages.psd1` is removed.
4. `Resolve-Manifest` returns typed `EmulatorSystem[]` and `DownloadSpec[]`.
5. 15 new unit tests + 2 Get-EmulationStationManifest tests green; existing 49 still green; integration tests still green with `-IncludeNetwork`.
6. `Get-EmulationStationManifest | Select-Object -ExpandProperty Systems` on your box returns the NES record with all defaults populated.

## Order of implementation

1. Add `LauncherKind`, `DownloadKind`, `EmulatorSystem`, `DownloadSpec` types in `Types.ps1`. Smoke-test module still loads.
2. Rewrite `Resolve-Manifest.ps1` taking `-ManifestRoot`, doing full validation.
3. Update `Get-EmulationStationManifest.ps1` to use the new signature.
4. Populate `manifest/systems.psd1` with one NES entry. Remove `manifest/packages.psd1`.
5. Populate `manifest/downloads.psd1` with the NES core + homebrew entries (SHA-256 left as placeholders for now — those land in M5 when we actually download).
6. Replace existing `Resolve-Manifest.Tests.ps1` with the 15-case suite.
7. Add `Get-EmulationStationManifest.Tests.ps1`.
8. Run unit suite — fix until green.
9. Manual check: `Get-EmulationStationManifest` prints the typed NES record.
10. Commit.

## What M3 does NOT include

- **Populating the rest of the systems.** That's M6 (RetroArch systems) and M7 (console-specific).
- **Real SHA-256 values for the downloads.** Those land alongside the actual downloads in M5/M6 (M3 uses placeholder zeros so the schema passes; M5's real download will replace).
- **Wiring the manifest into `Install-EmulationStation`.** That's M5.
- **Generating `es_systems.cfg`.** That's M4.
