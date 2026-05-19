# M6 — All RetroArch systems

**Goal:** populate the manifest with the full set of libretro-based systems we want to ship in v0.1. The orchestrator from M5 already iterates N systems generically — M6 is mostly a manifest edit, plus a few hygiene tests and one or two small orchestrator robustness fixes flushed out by stressing the bigger manifest.

## What we're adding

Eleven libretro systems total (NES already shipped in M3/M5). New systems for M6:

| Name | FullName | Core | RomExtensions |
|---|---|---|---|
| `snes` | Super Nintendo | `snes9x_libretro.dll` | .smc .sfc .fig |
| `gb` | Game Boy | `gambatte_libretro.dll` | .gb |
| `gbc` | Game Boy Color | `gambatte_libretro.dll` | .gbc |
| `gba` | Game Boy Advance | `mgba_libretro.dll` | .gba |
| `megadrive` | Sega Mega Drive / Genesis | `genesis_plus_gx_libretro.dll` | .md .gen .smd .bin |
| `mastersystem` | Sega Master System | `genesis_plus_gx_libretro.dll` | .sms |
| `n64` | Nintendo 64 | `parallel_n64_libretro.dll` | .n64 .z64 .v64 |
| `atari2600` | Atari 2600 | `stella_libretro.dll` | .a26 .bin |
| `arcade` | Arcade (MAME 2010) | `mame2010_libretro.dll` | .zip |
| `c64` | Commodore 64 | `vice_x64_libretro.dll` | .d64 .t64 .tap .prg |

Plus the existing `nes` (fceumm).

Each system entry has the same shape as the NES entry from M3:
- Libretro launcher with the core DLL name.
- `Packages = @('Libretro.RetroArch')` (shared install — winget call is idempotent, so 11 systems means 1 actual install).
- `Artifacts.Core = '<system>-core'` referencing a download entry.
- Optional `Artifacts.Homebrew` for the systems where we ship a ROM.

## Downloads added

- 10 new LibretroCore entries (or 8 — `gambatte_libretro.dll` and `genesis_plus_gx_libretro.dll` are shared between two systems each; we can either duplicate the manifest entry or share by reference).
- 3 homebrew ROMs from the OpenEmu/OpenEmu-Update GitHub repo (HTTPS, stable):
  - SNES: `N-Warp Daisakusen V1.1.smc`
  - GBA: `uranus0ev_fix.gba`
  - Genesis: `rickdangerous.gen`

Hashes for everything go in as `'0' * 64` placeholders. **Maintainer runs `Update-DownloadHashes` and commits the resulting real hashes** — same flow as M5. The libretro buildbot SSL issue we hit in M5 may still be present; the maintainer pinning step is gated on it being reachable.

## Decision: shared cores

Two cores are shared between two systems each:
- `gambatte_libretro.dll` → `gb`, `gbc`
- `genesis_plus_gx_libretro.dll` → `megadrive`, `mastersystem`

Schema-wise, both options work:

**Option A — one download per system:** `gb-core` and `gbc-core` both reference identical URLs but different keys. Simpler to reason about per-system but the download happens twice.

**Option B — shared download:** both `gb` and `gbc` reference a single `gambatte-core` download entry. Single download, two systems use the same DLL.

Going with **Option B** — the artifact reference is cleaner, the cache only stores one copy, and the orchestrator already handles "core already in cores dir" idempotently (Expand-VerifiedArchive with -Force just overwrites with identical bytes).

## Tests added

`tests/Unit/Manifest.Smoke.Tests.ps1` (new):
1. Shipped manifest has exactly 11 systems.
2. Every system's Artifacts references resolve to existing Downloads.
3. Every system has at least one Package and one RomExtension.
4. Libretro launchers' LibretroCore values are unique-ish (verifies we haven't typo'd two systems to the same core except where intentional — gambatte and gpgx).

`tests/Unit/Install-EmulationStation.Tests.ps1` (extend):
- Add: installs multiple systems in one call (mocked) — asserts every system landed in `SystemsInstalled`.

No new orchestrator code expected. If multi-system runs surface a real bug (e.g., RetroArch path being re-resolved 11 times), we fix it inline.

## Files M6 adds or changes

```
docs/plans/M6-retroarch-systems.md           NEW (this file)
manifest/systems.psd1                        EXPAND — 10 new system entries
manifest/downloads.psd1                      EXPAND — 8 cores + 3 homebrew ROMs
tests/Unit/Manifest.Smoke.Tests.ps1          NEW
tests/Unit/Install-EmulationStation.Tests.ps1   EXTEND (one new It block)
CHANGELOG.md                                 UPDATE
```

## Defects from `reference/analysis.md` this milestone closes

- #18 (final) — the ~700-line copy-paste install logic upstream uses for each system is now genuinely a single generic loop driven by the manifest. M3 set the schema; M5 implemented the loop; M6 proves it works with 11 systems.
- #23 (full) — per-system opt-in is fully wired: `Install-EmulationStation -Systems snes,gba` works.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Libretro buildbot still unreachable when maintainer runs `Update-DownloadHashes` | Manifest ships structurally complete with placeholders; maintainer re-runs later. Document in CHANGELOG. |
| Some core URL has changed format (e.g., file renamed in nightly) | Each entry is independent; one bad URL doesn't block others. Per-entry warn-and-continue in `Update-DownloadHashes`. |
| MAME 2010 core requires specific ROM naming and BIOS files | Out of scope. We ship the core; user supplies ROMs. The ROM dir is created so they can drop files in. |
| `genesis_plus_gx_libretro.dll` also runs Game Gear / SG-1000, not just MD + SMS | We're not declaring `gg` / `sg-1000` systems in M6. They can be added later as a manifest edit, no schema or code change. |
| Multi-system run in M5's orchestrator might over-resolve RetroArch path | `launcherPaths` hashtable already caches by `PackageId`; ContainsKey check skips on subsequent systems. Verified by re-reading M5's orchestrator before writing M6 tests. |
| 11 systems → 11 ROM dirs created even when only some have ROMs | Empty dirs are fine; ES handles them gracefully. |

## Exit criteria

1. `manifest/systems.psd1` has 11 systems (NES + 10 new).
2. `manifest/downloads.psd1` has 9 core download entries (8 unique + 1 fceumm) + 3 homebrew entries (NES + SNES + GBA + Genesis — actually 4 with NES, but NES already exists).
   Cleaner restatement: every Artifact reference in systems.psd1 resolves to a key in downloads.psd1. Schema validates strictly.
3. `Get-EmulationStationManifest` returns 11 EmulatorSystem objects with `Platform`, `Theme`, `RomExtensions` populated and Libretro launchers pointing at valid `.dll` names.
4. Manifest smoke tests pass (4 new tests).
5. Multi-system Install-EmulationStation unit test passes (1 new test).
6. Total test count: 80 unit + 5 new = 85 unit; everything green.

## Order of implementation

1. Add the 8 unique cores to `downloads.psd1` (with placeholder hashes).
2. Add the 3 homebrew ROMs to `downloads.psd1` (with placeholder hashes — we'll let `Update-DownloadHashes` pin the GitHub-hosted ones, which should be reachable).
3. Add 10 system entries to `systems.psd1`, referencing the right cores and (where applicable) homebrew downloads.
4. Run the existing test suite — schema validation should pass.
5. Add `tests/Unit/Manifest.Smoke.Tests.ps1` (4 tests).
6. Extend `tests/Unit/Install-EmulationStation.Tests.ps1` with the multi-system test.
7. Run `Update-DownloadHashes` on the user's box. GitHub-hosted homebrew should pin; libretro cores depend on buildbot reachability. Commit whatever pins successfully.
8. Re-run full unit suite. Commit M6.

## What M6 does NOT include

- Standalone-launcher systems (PSX, PS2, Wii, etc.). M7.
- Theme installation. M10.
- Per-system advanced configuration (gamepad bindings, scanlines, etc.). Out of scope.
- BIOS files (some cores require them — N64 doesn't, MAME varies, but PCE-CD/Saturn would). M7 handles where applicable; for M6's cores, BIOS isn't required.
