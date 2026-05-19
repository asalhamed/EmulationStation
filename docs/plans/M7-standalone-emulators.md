# M7 — Console-specific (Standalone) emulators

**Goal:** add five Standalone-launcher systems via winget — PSX, PS2, PS3, GameCube, Wii. The schema (M3) and orchestrator (M5) already support `Standalone` launchers and were tested with a mocked DuckStation back in M5. M7 wires the real emulators into the manifest, drops ePSXe and the ancient PCSX2 1.6.0 that upstream still ships, and proves the Standalone path works against real winget packages.

## What we're adding

| Name | FullName | winget package | Executable | ROM exts |
|---|---|---|---|---|
| `psx` | Sony PlayStation | `Stenzek.DuckStation` | `duckstation-qt-x64-ReleaseLTCG.exe` | .cue .iso .bin .chd .pbp .img |
| `ps2` | Sony PlayStation 2 | `PCSX2Team.PCSX2` | `pcsx2-qt.exe` | .iso .chd .bin .gz |
| `ps3` | Sony PlayStation 3 | `RPCS3.RPCS3` | `rpcs3.exe` | .iso .pkg .bin |
| `gc` | Nintendo GameCube | `DolphinEmulator.Dolphin` | `Dolphin.exe` | .iso .gcm .gcz |
| `wii` | Nintendo Wii | `DolphinEmulator.Dolphin` | `Dolphin.exe` | .iso .wad .wbfs |

Note `gc` and `wii` share the same winget package and executable, parallel to how M6's `gb`/`gbc` and `megadrive`/`mastersystem` share libretro cores.

## Command templates

| System | CommandTemplate | Why |
|---|---|---|
| psx | `"%EXE%" -batch -- "%ROM%"` | DuckStation's `-batch` exits cleanly after ROM ends. `--` ends option parsing. |
| ps2 | `"%EXE%" -batch -fullscreen -- "%ROM%"` | PCSX2 Qt's standard batch+fullscreen invocation. |
| ps3 | `"%EXE%" "%ROM%"` | RPCS3 takes a path positionally; no batch flag in supported builds. |
| gc  | `"%EXE%" -b -e "%ROM%"` | Dolphin's `-b -e` = batch + execute + exit. |
| wii | `"%EXE%" -b -e "%ROM%"` | Same Dolphin invocation. |

`%EXE%` is substituted by `Write-EsSystems` with the resolved path from `Resolve-EmulatorPath`. `%ROM%` is preserved verbatim for ES's runtime substitution.

## Downloads

**None added.** M7 systems are winget-only — no cores to fetch, no bundled homebrew. Users supply their own ROMs (legal or otherwise — out of scope).

## Tests

Two small additions:

1. `tests/Unit/Manifest.Smoke.Tests.ps1` — bump expected system count from 11 to 16 (NES, 10 libretro from M6, 5 standalone from M7). Add an assertion that we have exactly 5 Standalone systems and they all declare ExecutableName + CommandTemplate.

2. `tests/Integration/Standalone.Network.Tests.ps1` (new, tagged `Network`) — best-effort: for each Standalone system, check if its winget package is already installed on the machine and, if so, that `Resolve-EmulatorPath` returns a real `.exe` path. Systems not installed are skipped, not failed. This is a low-cost smoke check for real-world resolution; the actual install is gated behind `-IncludeStateChange` in the M5-style integration test that already exists.

No changes to `Install-EmulationStation` or any of the renderers expected. The orchestrator's M5 Standalone branch and `Write-EsSystems`'s Standalone branch (M4) cover this end-to-end.

## Defects from `reference/analysis.md` this milestone closes

- #16 (final) — hardcoded `C:\tools\Dolphin-Beta\Dolphin.exe`-style paths are now resolved at install time via `Resolve-EmulatorPath` against winget's registry entries.
- #17 (final) — PCSX2 1.6.0 (2020) and ePSXe 2.0.5 (2016) are dropped. Replaced by:
  - PCSX2-Qt (current Qt branch via `PCSX2Team.PCSX2`)
  - DuckStation (modern, maintained PSX emulator) replacing ePSXe entirely.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| DuckStation's executable name (`duckstation-qt-x64-ReleaseLTCG.exe`) varies per release | Resolve-EmulatorPath throws with a clear "Executable 'X' not found under 'Y'" — we update the manifest. Document that this is a "real-world hash drift" we accept. |
| PCSX2-Qt may install under `pcsx2-qtx64-avx2.exe` vs `pcsx2-qt.exe` | Same — manifest edit if upstream renames. |
| RPCS3 typically takes a *directory* path for unpacked games, not a single .iso | Out of scope. Users who need RPCS3 directory-launch can post-edit es_systems.cfg. The manifest still scaffolds the basics. |
| Dolphin's `-b -e` may have changed across major versions | The flag has been stable across Dolphin 5.x and the current dev branch. |
| Standalone systems registered as MSIX may not have InstallLocation in registry | We hit this gap in M2 (Microsoft.PowerShell). None of these emulators ship as MSIX; all are MSI/EXE installers. |
| Users may have a different (non-winget) install of DuckStation/etc. | `Resolve-EmulatorPath` reads the registry uninstall keys, which most installers populate regardless of how the user installed. If it's not registered, we throw — and the manifest provides a clear surface for adding fallbacks later. |

## Exit criteria

1. `manifest/systems.psd1` has 16 entries (11 from M6 + 5 from M7).
2. `Get-EmulationStationManifest` returns 16 systems; all five new ones have `Launcher.Kind = 'Standalone'` with all four required fields (Kind, PackageId, ExecutableName, CommandTemplate).
3. `Manifest.Smoke.Tests.ps1` updated and green: system count = 16, Standalone count = 5, shape invariants hold.
4. Best-effort integration test runs without failures (it skips systems whose packages aren't installed).
5. Total tests: 86 unit + 0 new (one updated) = 86, plus 1 new integration test tagged `Network`.

## Order of implementation

1. Add 5 Standalone system entries to `systems.psd1`.
2. Update `Manifest.Smoke.Tests.ps1`: bump system count, add Standalone-shape assertions.
3. Run unit suite; fix any schema violations.
4. Add `tests/Integration/Standalone.Network.Tests.ps1` — best-effort path resolution against installed emulators.
5. Run with `-IncludeNetwork`. Skips are fine.
6. Commit.

## What M7 does NOT include

- BIOS files (PS1/PS2/PS3 require them — user supplies their own, legally obtained).
- Per-emulator advanced configuration (per-game settings, gamepad bindings, save states paths). Users tune in each emulator's GUI.
- Actually installing PS3 emulator on the test box (it's a multi-GB install and the project's policy is `-IncludeStateChange` opt-in).
- Replacing the integration coverage with a "this actually launches a game" test. Manual demo only.
