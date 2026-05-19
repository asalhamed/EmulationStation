# M9 — Uninstaller (reverse-replay the install log)

**Goal:** close the loop. Anything `Install-EmulationStation` put on the box, `Uninstall-EmulationStation` can take back off, reading the M8 install log and reversing each undoable action. Things we didn't create — pre-existing winget packages, user-supplied ROMs — are never touched.

This is the milestone that lets a user say "I tried this; I want my machine back" and get a clean result.

## What we're building

### `Uninstall-EmulationStation`

```powershell
Uninstall-EmulationStation
    [-InstallRoot <string>]                  # default %USERPROFILE%\.emulationstation
    [-RemoveWinGetPackages]                  # default OFF: don't winget-uninstall RetroArch/etc.
    [-RemoveInstallRoot]                     # default OFF: don't delete the InstallRoot dir itself
    [-WhatIf] [-Confirm]
```

Returns a `RemovalSummary` hashtable:

```powershell
@{
    Started        = <datetime>
    Finished       = <datetime>
    InstallRoot    = '<path>'
    Reversed       = @(<action>, ...)   # what we successfully undid
    Skipped        = @(<action>, ...)   # what we deliberately didn't undo + reason
    Failed         = @(@{ Action; Message }, ...)
}
```

### `Uninstall-WinGetPackage` (private helper)

Thin wrapper around `winget uninstall --id <X> --exact --silent`. Idempotent: if the package isn't installed, returns `Status='NotInstalled'` without erroring.

```powershell
Uninstall-WinGetPackage
    -Id <string>
    [-TimeoutSec <int>]                      # default 300
```

Returns `@{ Status = 'Uninstalled' | 'NotInstalled'; Id }`.

### Touch-up to `Invoke-WinGet`

Add `'uninstall'` to the `ValidateSet` on `-Verb`. One-line change.

## Algorithm

```
1. Find install-log.json at $InstallRoot\install-log.json.
   - If missing: throw "No install log found at <path>; nothing to uninstall."
2. Parse JSON. Reverse the Actions array.
3. For each action (reverse order):
     Switch on Kind:
       'Started', 'Finished' → no-op
       'ShortcutCreated' → Remove-Item the Path (silently if missing)
       'ConfigRendered'  → Remove-Item the Path
       'FileWritten'     → Remove-Item the Path
       'DirectoryCreated' →
            If empty: Remove-Item -Recurse
            If non-empty: skip with reason 'directory not empty (contains user content)'
       'WinGetInstall'   →
            If $action.Status -ne 'Installed': skip with reason '<status>' (preserves user pre-existing installs)
            ElseIf -not $RemoveWinGetPackages: skip with reason 'opt-in via -RemoveWinGetPackages'
            Else: Uninstall-WinGetPackage -Id $action.Id; record result
4. If -RemoveInstallRoot and the dir is now empty (or contains only install-log.json):
     Remove the install-log.json, then Remove-Item the dir.
5. Return RemovalSummary.
```

### Why we skip `AlreadyInstalled` and `Upgraded` packages

- `AlreadyInstalled` means the user had it before us. Removing it would surprise them.
- `Upgraded` means we changed the version but it was already there. Removing entirely also surprises.

Only `Installed` (a brand-new install we caused) is reversible without ambiguity. Documented.

### Why empty-directory check before removal

The install log records `DirectoryCreated` for every dir we made. But ES users drop their own ROMs into `roms\<system>\` after install. We must not nuke those. Only directories that are truly empty at uninstall time get removed.

## Test plan

`tests/Unit/Uninstall-EmulationStation.Tests.ps1` — 7 tests:
1. Throws when install-log.json is missing.
2. Reverses ShortcutCreated by deleting the .lnk.
3. Reverses ConfigRendered by deleting the .cfg.
4. Reverses DirectoryCreated only when dir is empty; preserves with a Skipped entry otherwise.
5. Skips WinGetInstall by default (without `-RemoveWinGetPackages`).
6. With `-RemoveWinGetPackages`, calls Uninstall-WinGetPackage for `Status='Installed'` actions only; skips `AlreadyInstalled` and `Upgraded`.
7. Returns RemovalSummary with Reversed/Skipped/Failed populated.

`tests/Unit/Uninstall-WinGetPackage.Tests.ps1` — 3 tests:
1. Calls winget uninstall once with the right args.
2. Returns Status='Uninstalled' on success.
3. Returns Status='NotInstalled' when the package isn't installed (`winget` non-zero exit with the expected error code).

`tests/Integration/Install-NES.Tests.ps1` — extend with 1 test:
- Install → assert layout — Uninstall → assert layout cleaned up. (No `-RemoveWinGetPackages`; winget package stays.)

Total: 10 new unit tests + 1 integration extension.

## Files M9 adds or changes

```
src/private/
  Invoke-WinGet.ps1                       CHANGE (1 line: add 'uninstall' to ValidateSet)
  Uninstall-WinGetPackage.ps1             NEW
src/public/
  Uninstall-EmulationStation.ps1          REWRITE (was stub since M0)
tests/Unit/
  Uninstall-WinGetPackage.Tests.ps1       NEW (3 tests)
  Uninstall-EmulationStation.Tests.ps1    NEW (7 tests)
tests/Integration/
  Install-NES.Tests.ps1                   EXTEND (install-then-uninstall round-trip)
```

## Defects from `reference/analysis.md` this milestone closes

None — they all fell by M7. M9 closes a brand-new concern that didn't appear in the upstream analysis because **upstream doesn't have an uninstaller at all**. The reverse-replay design only works because M8 set up the install log. This is the milestone where being able to leave a user's machine cleaner than we found it becomes a guarantee, not a hope.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Install log corrupted or partially written | M8's atomic write makes this rare. If parsing fails, we throw with a clear message; user can manually clean up. |
| User deleted some files between install and uninstall | Every Remove-Item wrapped in Test-Path check; missing items are no-ops with a Skipped entry. |
| User dropped ROMs into roms/<system>/ — we'd erase them | Empty-dir check before Remove-Item. Non-empty dirs are preserved. |
| `winget uninstall` requires admin for machine-scope installs | Surface the error. The user re-runs elevated. Don't try to escalate ourselves. |
| `-RemoveWinGetPackages` removes a package the user uses for something else | This is an opt-in flag. Default off. Documented. |
| Some shortcuts pointing at our InstallRoot exist outside the log (manually created by user) | We don't touch those — we only delete .lnk paths recorded in the log. |
| Uninstall halfway through fails — partial state | Each action wrapped in try/catch; failures go into `Failed[]`, processing continues. Final summary lists everything. |

## Exit criteria

1. `Uninstall-EmulationStation` ships and is callable.
2. 10 new unit tests + 1 integration extension pass alongside existing 98 unit. Total 108 unit, 115 default suite, 7 NotRun.
3. Install → Uninstall on a temp `-InstallRoot` produces a clean dir (no .cfg, no shortcuts, empty subdirs removed). `-RemoveInstallRoot` also removes the root dir.
4. Re-running Uninstall after a successful Uninstall throws cleanly ("no install log found").

## Order of implementation

1. `Invoke-WinGet.ps1`: add `'uninstall'` to the ValidateSet.
2. `Uninstall-WinGetPackage.ps1` + 3 unit tests.
3. `Uninstall-EmulationStation.ps1` (replace M0 stub) + 7 unit tests.
4. Extend integration test in `Install-NES.Tests.ps1` with install-then-uninstall.
5. Run full suite both ways. Commit.

## What M9 does NOT include

- Removing user-created files in roms/ — empty-dir-check protects them.
- Rolling back a partially-failed install (a separate concern; v1 is "reverse what we successfully did").
- A "diff what's still here from the log" / drift-detector. M10 if useful.
- Restoring the previous package version on `Upgraded` packages. winget doesn't make this easy; out of scope.
