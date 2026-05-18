# M4 — Templated config generation

**Goal:** generate `es_systems.cfg`, `es_settings.cfg`, and `dolphin.ini` *directly from the manifest*, with zero GUI launches and zero sleep loops. After M4, configuration is deterministic: same manifest input → same config output, every time.

## What we're building

Three private cmdlets + three template assets:

| Cmdlet | Purpose |
|---|---|
| `Write-EsSystems` | Renders `es_systems.cfg` from `EmulatorSystem[]`. One `<system>` block per system. |
| `Write-EsSettings` | Renders `es_settings.cfg` (mostly static — one user-path substitution). |
| `Render-Template` | Private helper: simple `{{TOKEN}}` → value substitution. |

Plus templates at `src/templates/`:
- `es_systems.cfg.system-block.template` — one system's XML block with `{{TOKEN}}` placeholders.
- `es_settings.cfg.template` — full settings XML with one user-profile placeholder.
- `dolphin.ini` — verbatim copy of upstream's Dolphin config. Not a template; copied as-is.

## Function contracts

### `Render-Template`
```powershell
Render-Template
    -Template <string>                     # template body
    -Substitutions <hashtable>             # @{ TOKEN = 'value' }
```
Returns: string with every `{{TOKEN}}` replaced. Unknown tokens are left as `{{NAME}}` literally (caller can spot un-substituted tokens). Substitution values are **XML-escaped** before being inserted (escapes `&`, `<`, `>` in element content). Caller can opt out via a `-NoXmlEscape` switch for non-XML output.

### `Write-EsSystems`
```powershell
Write-EsSystems
    -Systems <EmulatorSystem[]>            # validated, typed
    -InstallRoot <string>                  # %USERPROFILE%\.emulationstation
    -OutputPath <string>                   # where to write es_systems.cfg
    -LauncherPaths <hashtable>             # @{ 'Libretro.RetroArch' = 'C:\...\retroarch.exe'; ... }
```
For each system:
- Compute ROM dir (`$InstallRoot\roms\$Name`).
- Compute extension list (each ROM extension is emitted lowercase + uppercase, space-separated, matching upstream).
- Compute `<command>` per launcher kind (see below).
- Render the per-system template with the system's fields + computed values.

Joins all blocks into `<systemList>...</systemList>`. Parses the result as `[xml]` before writing — malformed = throw, no half-output.

**Command for Libretro:** `"<retroarch.exe>" -L "<core>" %ROM%` (the `%ROM%` is ES's runtime token, kept verbatim).

**Command for Standalone:** the system's `Launcher.CommandTemplate`, with `%EXE%` substituted by the resolved executable path. `%ROM%` (and `%ROM_RAW%`) are preserved.

### `Write-EsSettings`
```powershell
Write-EsSettings
    -UserProfile <string>                  # %USERPROFILE%
    -OutputPath <string>                   # where to write es_settings.cfg
```
Renders the static template, substituting `{{USERPROFILE}}` (forward-slashed) for the slideshow paths. Validates XML before writing.

## What we're NOT doing (M0/M1/M2 boundaries respected)
- **No `Start-Process`** to launch ES or RetroArch to "generate a default config." We write the config files directly.
- **No `Start-Sleep`** waiting for files to appear.
- **No `Stop-Process -Force`** to force-quit the GUI mid-render.
- **No registry writes** — we'll write configs to user-profile paths, which is per-user and unprivileged.

## Templates — content sketches

### `es_systems.cfg.system-block.template`
```xml
    <system>
        <name>{{NAME}}</name>
        <fullname>{{FULLNAME}}</fullname>
        <path>{{PATH}}</path>
        <extension>{{EXTENSION}}</extension>
        <command>{{COMMAND}}</command>
        <platform>{{PLATFORM}}</platform>
        <theme>{{THEME}}</theme>
    </system>
```

### `es_settings.cfg.template`
Verbatim port of upstream's es_settings, with `$env:userprofile` replaced by `{{USERPROFILE}}` (slash-normalized). All keys (BackgroundJoystickInput, ThemeSet, etc.) preserved. ThemeSet pinned to `'recalbox-backport'` (we'll ship that theme in M6/M10).

### `dolphin.ini`
Verbatim copy of the 200-line heredoc from upstream's prepare.ps1. We don't generate it; we ship a file. Upstream's content goes into `templates/dolphin.ini` once, byte-stable thereafter.

## Test plan

`tests/Unit/Render-Template.Tests.ps1` — 4 tests:
1. Single substitution works.
2. Multiple substitutions in one template.
3. Unknown token left literally.
4. `-NoXmlEscape` skips encoding.
5. `&`, `<`, `>` in values get escaped to `&amp;`, `&lt;`, `&gt;`.

`tests/Unit/Write-EsSystems.Tests.ps1` — 6 tests:
1. Renders a Libretro NES system → valid XML; `<command>` contains `retroarch.exe -L ... fceumm_libretro.dll %ROM%`.
2. Renders a Standalone PSX system → `<command>` has `%EXE%` substituted with the provided path; `%ROM%` preserved.
3. Multiple systems → multiple `<system>` blocks in one `<systemList>`.
4. Extensions emitted lowercase + uppercase (matches upstream's `.nes .NES`).
5. Missing LauncherPath for a referenced package → throws.
6. Output parses as well-formed XML.

`tests/Unit/Write-EsSettings.Tests.ps1` — 3 tests:
1. Writes a file that parses as XML.
2. `{{USERPROFILE}}` substituted with slash-normalized path.
3. ThemeSet value is `recalbox-backport`.

Total: 13 new unit tests.

## Files M4 adds or changes

```
src/private/
  Render-Template.ps1            NEW
  Write-EsSystems.ps1            NEW
  Write-EsSettings.ps1           NEW

src/templates/
  es_systems.cfg.system-block.template   NEW
  es_settings.cfg.template               NEW
  dolphin.ini                            NEW (verbatim)

tests/Unit/
  Render-Template.Tests.ps1      NEW
  Write-EsSystems.Tests.ps1      NEW
  Write-EsSettings.Tests.ps1     NEW
```

`src/EmulationStationSetup.psm1` already sets `$script:TemplateRoot = Join-Path $PSScriptRoot 'templates'` — we just populate it.

## Defects from `reference/analysis.md` this milestone closes

- #10 GUI-driven config bootstrap (launch ES, sleep 60s, force-kill). We render directly.
- #11 Force-killing our own subprocesses for config. Eliminated — no processes to kill.
- #15 60s sleep loops for config-file appearance. None.
- #20 `es_systems.cfg` baked into the script as a 250-line heredoc. Now generated from the typed manifest.
- #21 Dolphin config as 200-line heredoc. Now a checked-in file.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| XML special chars in user-supplied fields (FullName etc.) | `Render-Template` XML-escapes substitution values by default; only opt-out via `-NoXmlEscape` |
| Path with `&` in install root | Same — escape in element content |
| ROM extensions case-doubling produces malformed list (e.g., `.NeS`) | We constrain RomExtensions to lowercase in the schema (M3); `.NES` is generated by `.ToUpper()` of a known-good value |
| Template file missing at install time | Load-time check during Write-EsSystems; throws with clear path |
| Manifest has zero systems | `Write-EsSystems` produces an empty `<systemList></systemList>` — parses fine, ES handles it |
| Dolphin.ini content drifts from what upstream's emulators expect | Ship our own ini; if user's Dolphin install regenerates its own, that overrides ours (acceptable) |

## Exit criteria

1. Templates checked in at `src/templates/`.
2. 13 new unit tests pass alongside existing 60. Total 73 unit, 4 NotRun (Network).
3. Manual demo: given the NES manifest + a fake LauncherPath dict, `Write-EsSystems` produces a valid `es_systems.cfg` that parses as XML and matches the expected `<command>` shape.

## Order of implementation

1. `Render-Template.ps1` + 5 unit tests.
2. `templates/es_systems.cfg.system-block.template`.
3. `Write-EsSystems.ps1` + 6 unit tests.
4. `templates/es_settings.cfg.template` (verbatim from upstream).
5. `Write-EsSettings.ps1` + 3 unit tests.
6. `templates/dolphin.ini` (verbatim from upstream).
7. Run full suite both ways. Manual demo. Commit.

## What M4 does NOT include

- Wiring into `Install-EmulationStation`. That's M5.
- Resolving real launcher paths via winget. That's M5 (combines M2's resolver + M4's renderer).
- Theme installation (recalbox-backport). M6 / M10.
- Custom per-user overrides of the rendered config. Out of scope for v0.1.
