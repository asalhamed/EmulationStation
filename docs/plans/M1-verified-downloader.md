# M1 — Verified downloader

**Goal:** ship `Get-VerifiedDownload`, the one and only mechanism by which this module pulls bytes from the network. Every later milestone (cores, ROMs, themes, ES build) uses it. The function is the load-bearing security boundary of the whole installer: if it's correct, hash mismatches and TLS failures cannot become silent installs of the wrong bytes.

## What we're building

A single private cmdlet `Get-VerifiedDownload` with these guarantees, in priority order:

1. **HTTPS only.** Reject `http://` at parameter binding. No code path can disable TLS validation.
2. **SHA-256 mandatory.** Caller passes the expected hash; mismatch = abort, with the partial file cleaned up.
3. **Atomic.** Bytes land at `${Destination}.partial`, are hashed in place, then renamed to `$Destination` only on success. Crash-during-download leaves no half-file masquerading as a good one.
4. **Idempotent.** If `$Destination` already exists and its hash matches, return immediately with no network call.
5. **Retry with backoff.** Network blips retry up to `$RetryCount` times with exponential backoff. Hash mismatch does NOT retry (the manifest is wrong, retrying won't fix it).
6. **Size capped.** `$MaxSizeMB` rejects downloads larger than expected before they finish (defends against a compromised host serving an unbounded stream).
7. **No bypasses.** No `-SkipCertificateCheck`, no custom `CertificatePolicy`, no `iex`.

## Function signature

```powershell
function Get-VerifiedDownload {
    [CmdletBinding()]
    [OutputType('System.IO.FileInfo')]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({
            if ($_ -notmatch '^https://') {
                throw "Uri must be https://. Got: $_"
            }
            $true
        })]
        [string] $Uri,

        [Parameter(Mandatory)]
        [string] $Destination,

        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-fA-F]{64}$')]
        [string] $ExpectedSha256,

        [int] $MaxSizeMB     = 5000,    # 5 GB cap; RetroArch is ~300 MB, biggest single artifact
        [int] $RetryCount    = 3,
        [int] $TimeoutSec    = 300,     # per attempt
        [int] $InitialBackoffSec = 2    # doubled per retry
    )
    # ...
}
```

Returns a `[System.IO.FileInfo]` of the verified file at `$Destination`.

## Algorithm

```
1. Validate inputs (PS does HTTPS + hex via Validate* attributes).
2. Normalize expected hash to uppercase.
3. If $Destination exists:
     a. Compute its SHA-256.
     b. If matches expected → return [FileInfo]$Destination.
     c. If mismatches → write warning, delete it.
4. Ensure destination directory exists.
5. partial = "$Destination.partial"
6. For attempt in 1..$RetryCount:
     a. Try:
          - Invoke-WebRequest -Uri $Uri -OutFile $partial
                          -TimeoutSec $TimeoutSec
                          -MaximumRedirection 5
                          -UserAgent <ours>
                          -ErrorAction Stop
          - If (Get-Item $partial).Length / 1MB > $MaxSizeMB:
                delete partial, throw "Exceeds size cap".
          - actual = (Get-FileHash $partial -Algorithm SHA256).Hash.ToUpper()
          - If actual -eq expected:
                Move-Item $partial $Destination -Force
                return [FileInfo]$Destination
          - Else:
                delete partial
                throw "SHA-256 mismatch: expected $expected, got $actual"
     b. Catch [hash-mismatch]:
          rethrow — don't retry, manifest is wrong.
     c. Catch [other network/IO]:
          delete partial if present.
          if attempt -lt $RetryCount:
              sleep ($InitialBackoffSec * [math]::Pow(2, $attempt - 1))
              continue
          else:
              rethrow as terminating error.
```

The hash-mismatch-doesn't-retry rule is important. A mismatch means the manifest is wrong or the host is serving tampered bytes — neither situation improves by trying again.

## What it deliberately does NOT do

- **No streaming hash during download.** We hash after the file lands. Streaming would catch oversize earlier but complicates retry logic and the size cap already handles it.
- **No partial resumption (HTTP `Range`).** Each retry starts from byte 0. The artifacts we download (cores ~5 MB, RetroArch ~300 MB) don't justify the complexity.
- **No content-type validation.** We hash the bytes; we don't care what the server claims.
- **No mirror fallback.** One URL per artifact. If a host goes down, the manifest needs updating.

## User-Agent

```
EmulationStationSetup/0.1 (PowerShell; +https://github.com/asalh/EmulationStation)
```

Documented, scannable in logs, identifies us as automation. If any upstream blocks us, we re-evaluate per-download.

## Test plan

`tests/Unit/Get-VerifiedDownload.Tests.ps1` — Pester unit tests with `Invoke-WebRequest` mocked:

| # | Test | What it asserts |
|---|---|---|
| 1 | Rejects http:// URL | `ValidateScript` throws at binding |
| 2 | Rejects non-hex SHA-256 | `ValidatePattern` throws at binding |
| 3 | Rejects 63-char SHA-256 | length validation via pattern |
| 4 | Happy path: writes file, returns FileInfo | Mock IWR drops bytes, hash matches |
| 5 | Idempotent: existing file with matching hash | Mock IWR is never called |
| 6 | Existing file with wrong hash → re-downloads | Old file gone, new file present, IWR called once |
| 7 | Server returns wrong bytes → throws, partial gone | Hash mismatch path |
| 8 | Network error on attempt 1, success on 2 | Retry succeeds, IWR called twice |
| 9 | All retries exhausted → throws | IWR called `RetryCount` times |
| 10 | Oversize file → throws, partial gone | size cap path |
| 11 | Hash-mismatch does NOT retry | IWR called exactly once even with retries available |
| 12 | Destination directory missing → created | New-Item -Force path |

`tests/Integration/Get-VerifiedDownload.Network.Tests.ps1` (tagged `Network` — opt-in):

| # | Test | What it asserts |
|---|---|---|
| 1 | Real HTTPS download with pre-pinned hash succeeds | End-to-end against a stable, small public file |

For the integration test we'll use a small known artifact — likely the [libretro-info](https://github.com/libretro/libretro-core-info) README or a tiny libretro core info file, both stable and ~KB-sized.

## Mocking strategy

Pester 5 `Mock` for `Invoke-WebRequest` inside `InModuleScope`:

```powershell
Mock Invoke-WebRequest -ModuleName EmulationStationSetup {
    param($Uri, $OutFile, ...)
    Set-Content -Path $OutFile -Value 'fake-bytes-with-known-hash'
}
```

Hash-of-known-content: we pre-compute SHA-256 of a known string, plant it in the test, mock IWR to write that string. Real cryptographic primitive (`Get-FileHash`) runs unmocked.

## Files M1 will add or change

```
src/private/
  Get-VerifiedDownload.ps1       NEW

tests/Unit/
  Get-VerifiedDownload.Tests.ps1 NEW

tests/Integration/
  Get-VerifiedDownload.Network.Tests.ps1   NEW (tagged Network, off by default)

tests/Invoke-Tests.ps1           CHANGE — add -ExcludeTag default to skip Network
```

No public cmdlet changes. Manifests untouched. M0's preflight not modified.

## Test runner change

We'll exclude `Network`-tagged tests by default and add a `-IncludeNetwork` switch:

```powershell
param(
    [ValidateSet('All', 'Unit', 'Integration', 'Smoke')]
    [string] $Scope = 'All',
    [switch] $IncludeNetwork
)
# ...
if (-not $IncludeNetwork) {
    $config.Filter.ExcludeTag = 'Network'
}
```

Local dev runs `.\tests\Invoke-Tests.ps1` (fast, offline). CI / pre-release runs `.\tests\Invoke-Tests.ps1 -IncludeNetwork`.

## Defects from `reference/analysis.md` this milestone closes

- #1 `TrustAllCertsPolicy` — eliminated by using PS 7 + standard cert validation (M0) and never calling `-SkipCertificateCheck` here.
- #2 `-SkipCertificateCheck` on Core branch — same as above.
- #3 No checksum verification on downloads — solved.
- #5 Plain `http://` URLs — rejected at parameter binding.
- #9 (partial) Hardcoded paths — `Destination` is caller-provided; we don't bake in any paths.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Mock of IWR doesn't simulate real streaming behavior | Integration test (off by default) hits a real URL |
| Move-Item on Windows isn't atomic across volumes | Document: caller must pass a Destination on the same volume as the partial; we make partial sibling to Destination so this is automatic |
| Get-FileHash for huge files is slow | Acceptable — runs once per artifact, after download |
| User-Agent gets a download blocked by a fussy server | Document; per-download UA override is out of scope for M1, add when we hit it |
| Pester mock can leak between tests | Use `BeforeEach { Mock ... }` not `BeforeAll`; reset state explicitly |

## Exit criteria

All four must hold before we mark M1 done and commit:

1. `src/private/Get-VerifiedDownload.ps1` exists and is dot-sourced by the module loader.
2. `tests/Invoke-Tests.ps1` runs green (M0 tests + 12 new M1 unit tests).
3. `tests/Invoke-Tests.ps1 -IncludeNetwork` runs green (adds 1 integration test that pulls a real ~KB file).
4. Manual demo: `Import-Module ...; Get-VerifiedDownload -Uri https://...stable-file... -Destination $env:TEMP\foo -ExpectedSha256 <real hash>` succeeds, re-run is instant (idempotent).

## Order of implementation

1. Write `Get-VerifiedDownload.ps1` (skeleton: param block + idempotent-check branch).
2. Add file → run smoke tests to confirm module still loads.
3. Build unit tests 1–3 (parameter validation). They should pass without any body code beyond the param block.
4. Body: happy path → unit tests 4, 12.
5. Body: idempotent check → unit tests 5, 6.
6. Body: retry loop → unit tests 7, 8, 9, 11.
7. Body: oversize guard → unit test 10.
8. Test runner: `-IncludeNetwork` switch.
9. Write integration test (1).
10. Run full suite both with and without `-IncludeNetwork`. Manual demo.
11. Commit.

## What M1 does NOT include

- Calling `Get-VerifiedDownload` from `Install-EmulationStation`. That's M5 wiring.
- Populating `manifest/downloads.psd1`. That's M3 (schema) / M6 (entries).
- Downloading and verifying an actual emulator. That's M5.
