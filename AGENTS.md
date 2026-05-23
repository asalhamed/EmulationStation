# AGENTS.md

Notes for AI assistants (Claude, Copilot, etc.) working on this repo.

## What this is

A PowerShell 7+ module that installs and configures EmulationStation with 13 emulated systems on Windows 10/11 — including the **ES-DE frontend** itself, wired with `--home <InstallRoot>` so it reads our generated `custom_systems/es_systems.xml`. **v0.1.0 shipped** (then patched post-release to handle real-install findings). Built as a security/reliability-focused rewrite of [Francommit/win10_emulation_station](https://github.com/Francommit/win10_emulation_station), closing 24 documented defects in the upstream.

## Where to start reading

In this order:

1. **[README.md](README.md)** — user-facing overview, quickstart, supported systems, known limitations.
2. **[PLAN.md](PLAN.md)** — the milestone roadmap, working principles, and the "Outcomes" section at the bottom listing what shipped.
3. **[ARCHITECTURE.md](ARCHITECTURE.md)** — module structure, data flow, install pipeline.
4. **[CONTEXT.md](CONTEXT.md)** — domain vocabulary (system, launcher, artifact, manifest, install root, etc.).
5. **[docs/adr/](docs/adr/)** — the four load-bearing decisions: PowerShell module, no TLS bypass, winget over Choco/Scoop, data-driven manifest.
6. **[docs/plans/](docs/plans/)** — per-milestone deep plans (M0–M10). Useful as worked examples for how this project does plan-first work.
7. **[CHANGELOG.md](CHANGELOG.md)** — what landed in each milestone, with commit pointers.
8. **[reference/analysis.md](reference/analysis.md)** — the 24-defect catalogue of upstream issues this project addresses.

## Working principles (from PLAN.md)

1. Idempotent everywhere — re-runs are safe.
2. Verified bytes — every download SHA-256 pinned in `manifest/downloads.psd1`.
3. No GUI bootstrap — configs rendered from templates, not extracted via "launch and sleep".
4. winget-only for packages — no Chocolatey, no Scoop, no third-party buckets.
5. HTTPS only — no `TrustAllCertsPolicy`, no `-SkipCertificateCheck`.
6. Data > code — new systems = new manifest entry, not new code paths.
7. Aggregate failures — report every miss at the end; don't bail on the first.
8. One Pester test per public cmdlet before a milestone is "done".
9. No `iex $(downloaded-string)` — read first, hash-verify, then run.
10. Every artifact placement is logged — so uninstall is a replay, not guesswork.

## Module layout

```
src/EmulationStationSetup.{psd1,psm1}   manifest + loader
src/public/                              4 exported cmdlets
src/private/                             helpers — one cmdlet per file
src/templates/                           es_systems block, es_settings, dolphin.ini
manifest/                                systems.psd1 + downloads.psd1 (the data)
tests/Unit/                              Pester unit tests
tests/Integration/                       tagged 'Network' or 'StateChange'
tests/Invoke-Tests.ps1                   the test runner
```

## Adding or changing things

- **New system** → edit `manifest/systems.psd1`. Add a `Core` reference and the corresponding entry in `manifest/downloads.psd1`. Then run `Update-DownloadHashes` (private cmdlet, maintainer flow) to pin its SHA-256. No code changes needed — the orchestrator handles N systems generically.
- **New cmdlet** → file under `src/public/` or `src/private/`. The loader (`EmulationStationSetup.psm1`) dot-sources everything in `public/` and `private/` automatically. Write Pester tests in the corresponding `tests/Unit/` location.
- **Architectural decision** → write an ADR in `docs/adr/` before changing the schema or the orchestration shape.
- **New milestone (post-v0.1)** → follow the M0–M10 cadence: write a `docs/plans/Mn-*.md` deep plan, get review, then implement.

## Test conventions

Three opt-in tiers via `tests/Invoke-Tests.ps1`:

| Flag | What runs additionally |
|---|---|
| (default) | Unit tests (108), smoke (3), and offline integration (4) |
| `-IncludeNetwork` | + 2 real-network tests (GitHub, winget queries, libretro) |
| `-IncludeStateChange` | + 2 host-mutating tests (actually installs RetroArch) |

When mocking module-private functions, mock the actual callee — for example, `Install-EmulationStation` calls `Resolve-Manifest` directly, not `Get-EmulationStationManifest`. This caught us in M6.

For COM-dependent tests (shortcuts), it's fine to actually create `.lnk` files in `$env:TEMP` and verify them via WSH round-trip rather than trying to mock `New-Object -ComObject`.

## Things to avoid

- `$varName:` in strings — PowerShell parses this as a scope qualifier and errors. Use `${varName}:` or `$($varName):` instead.
- `-match` / `-notmatch` when you need case-sensitive matching. Use `-cmatch` / `-cnotmatch`. The schema validator caught this with system names.
- Piping a hashtable to `Should -BeOfType [hashtable]` in Pester — enumerates the hashtable's entries, doesn't check the type. Use `($r -is [hashtable]) | Should -BeTrue` instead.
- Calling `Resolve-Manifest` with `-Path` (single file) — the signature changed in M3 to `-ManifestRoot` (directory). Update any old call sites.

## Git conventions

Local-only commit identity (`git config --local`): Ahmed AlHamed / asalhamed@gmail.com. Do NOT touch the global config. Commit messages follow the form `Mn: <short summary>` for milestone commits; bug-fix commits should say what defect they closed. All commits use HEREDOC-style messages for proper formatting and end with the Co-Authored-By trailer when an AI assistant did the work.

## Network reality

`buildbot.libretro.com` has intermittent SSL handshake failures from some networks. This is why `Update-DownloadHashes` is per-entry warn-and-continue: a transient failure on one core doesn't corrupt the rest. `vice-x64-core` in v0.1.0 ships with a placeholder hash for this reason — maintainer re-runs to fix when libretro is reachable.
