# Reference snapshot — Francommit/win10_emulation_station

Captured 2026-05-17 from <https://github.com/Francommit/win10_emulation_station/tree/master>.

## What's here

- `prepare.ps1` — partial snapshot of the main installer for analysis (header + first ~180 lines). The full original is ~700 lines; see GitHub for the rest. This is a reference, not something to execute.
- `download_list.json` — trimmed snapshot of the download manifest (representative entries from every section). Full file has ~30 extra NES games.
- `analysis.md` — the issues we identified that the rewrite must address.

## Why we keep this

So when we redesign each subsystem we can point to the *exact* upstream behavior we're replacing or improving, rather than working from memory.
