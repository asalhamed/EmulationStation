# M10 — Verification, docs, ship v0.1

**Goal:** clean lap. Verify the whole thing works end-to-end on this box (where reachable), refresh the README so a first-time reader can understand and use the module, update the top-level docs to reflect what landed vs. what was planned, and tag `v0.1.0`.

No new functionality — only polish, docs, and a release marker.

## What we're doing

### 1. README polish

Rewrite `README.md` so a user landing on the repo can:
- Understand what this is and how it differs from upstream Francommit in 30 seconds.
- See the supported systems table.
- Run the four canonical commands (install, install-subset, uninstall, run-tests).
- Know where to look for architecture, design decisions, manifest authoring, the change log.

Target length ~150 lines. Link out to the deep docs rather than duplicating them.

### 2. PLAN.md "Outcomes" section

Append a final section to `PLAN.md` summarising actual outcomes vs. plan:
- Milestones shipped (10 of 10) with commit SHAs.
- Defects closed (24 of 24 from the upstream analysis).
- Test totals (108 unit, 115 default, 117 with network, 2 still gated behind StateChange).
- What didn't land in v0.1 (EmulationStation frontend installer; non-zero placeholder hashes deferred to maintainer pin step; theme installation; advanced per-emulator config).

### 3. Final verification

On this machine:
- `tests\Invoke-Tests.ps1` (default, offline): must be 115/115 green.
- `tests\Invoke-Tests.ps1 -IncludeNetwork`: real downloads + winget queries; should be 117/117 (a few may legitimately skip if libretro buildbot is unhappy).
- Manual demo: `Get-EmulationStationManifest` lists 16 systems with sane fields.

We do **not** run `-IncludeStateChange` in M10 — that mutates the host. It's documented as opt-in for maintainers running pre-release validation on a clean VM.

### 4. Tag v0.1.0

```
git tag -a v0.1.0 -m "v0.1.0 — Windows EmulationStation installer rewrite"
```

No push step. The user pushes when they want to share.

## Files M10 adds or changes

```
docs/plans/M10-verification-ship.md       NEW (this file)
README.md                                 REWRITE (~150 lines, user-facing)
PLAN.md                                   APPEND (Outcomes section)
CHANGELOG.md                              UPDATE (M10 entry + reorder Unreleased -> v0.1.0)
```

No test changes; no source changes; no manifest changes.

## Defects closed by M10

None — those were already at 24/24 after M7. M10 is shipping work.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| README drifts from reality (we changed code but README still says something else) | Cross-check every command in the README against actual cmdlet signatures via Get-Help |
| Final test run hits a transient network failure | Re-run, document if persistent. We've already accepted some libretro flakiness. |
| Tag is wrong (e.g., points at a commit that lost a fix) | Tag is annotated and re-creatable; if wrong we just tag again before pushing |

## Exit criteria

1. README polished and reads well.
2. PLAN.md has an Outcomes section.
3. CHANGELOG header for v0.1.0 with full milestone list.
4. `Invoke-Tests.ps1` (default) green.
5. `Invoke-Tests.ps1 -IncludeNetwork` runs with at most known-transient skips.
6. `git tag v0.1.0` exists.

## What M10 does NOT include

- Pushing to a remote.
- Publishing to PowerShell Gallery.
- Cutting v0.1.1 / v0.2.0 follow-ups for known limitations (EmulationStation frontend installation, theme, etc.).
