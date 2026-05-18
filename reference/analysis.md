# Upstream analysis — what we have to fix

Captured from the 2026-05-17 snapshot of `prepare.ps1` and `download_list.json`. Each item below is a concrete defect in the upstream installer that informs a requirement in the new design.

## Security defects

1. **Custom `TrustAllCertsPolicy`** in `prepare.ps1` (PS 5.1 branch) disables TLS certificate validation globally for the process. Replacement: never disable cert validation; require PS 7+ which has correct cert handling, or fail loudly.
2. **`Invoke-WebRequest … -SkipCertificateCheck`** in the PS Core branch — same problem on PS 7.
3. **No checksum or signature verification** on any of the ~30 downloads. Replacement: SHA-256 manifest entries, verified before use; refuse to proceed on mismatch.
4. **Recommended one-liner pulls a versioned zip** (`1.3.9`) but the in-script behavior pulls latest cores/buildbot artifacts. Replacement: pin every artifact by URL + hash; "latest" is opt-in only.
5. **Plain `http://` URLs** for `epsxe.com` and `nesworld.com`. Replacement: HTTPS only, or refuse.
6. **`Set-ExecutionPolicy Bypass -Scope Process -Force`** and `iex`-from-the-web for Chocolatey bootstrap. Replacement: don't bootstrap Chocolatey; use winget which is built into Windows 10/11.
7. **Mixed-trust sources** — a third-party Scoop bucket (`github.com/borger/scoop-emulators`), `dl.coolatoms.org`, `nesworld.com`. Replacement: drop third-party buckets; use winget manifests and official emulator release pages only.
8. **Admin elevation + global package manager state mutation** — installs Chocolatey + Scoop machine-wide. Replacement: per-user install in `%LOCALAPPDATA%`; admin only when strictly necessary (e.g., VC++ runtime).

## Reliability defects

9. **Hardcoded paths**: `C:\Program Files\7-Zip\7z.exe`, `C:\tools\Dolphin-Beta\Dolphin.exe`, `C:\tools\cemu\Cemu.exe`. Replacement: resolve binaries at runtime by querying winget/scoop, fail fast with a clear error.
10. **GUI-driven config bootstrap**: launches `emulationstation.exe`, sleeps 60s, then `Stop-Process` to get a default config. If the GUI doesn't drop the file in time the script *fabricates a stub*. Replacement: write the canonical config directly; never launch a GUI to extract state.
11. **`Stop-Process -Name retroarch -Force`** as part of normal flow. Replacement: never force-kill our own subprocesses; run them with explicit lifecycle.
12. **`exit -1`** on every missing file. Replacement: aggregate failures, report all of them, allow partial success with `--skip-missing`.
13. **`function Expand-Archive` shadows the built-in** and depends on a hardcoded `7z.exe` path that the script itself doesn't install until later. Replacement: use `.NET ZipFile` for `.zip`, the `7z` module for `.7z`/`.exe` installers only when needed.
14. **Non-idempotent installs**: scoop bucket workaround (`scoop bucket rm main; scoop bucket add main`) runs every time; bucket adds error if they already exist. Replacement: check-then-add, treat "already present" as success.
15. **Latency-based race conditions**: 60s sleeps for config files. Replacement: synchronous file generation, not GUI-and-wait.
16. **No uninstaller / no manifest of what was placed where**. Replacement: install log enumerating every file, every shortcut, every registry write, with a matching `uninstall.ps1`.
17. **Pinned to broken/old versions**: PCSX2 1.6.0 (5+ years old, broken installer on modern Win10/11), ePSXe 2.0.5 (last released 2016). Replacement: PCSX2-Qt nightly, DuckStation for PSX (modern, actively maintained, BIOS-optional).

## Maintainability defects

18. **One ~700-line script** with copy-pasted "if Test-Path then Expand-Archive else exit" blocks for every system. Replacement: data-driven — every system declared in one JSON/PSD1, generic install function consumes it.
19. **No tests, no CI verification of behavior** — the existing GH Actions badge runs the script but doesn't verify end state. Replacement: Pester tests on Windows runner that assert filesystem layout post-install.
20. **`es_systems.cfg` baked into the script as a heredoc** with `$variable` interpolation. Replacement: template file with explicit substitution, easier to diff and review.
21. **Dolphin config baked as 200-line heredoc**. Replacement: ship as a real `.ini` file copied verbatim.

## Functional gaps

22. **Bundled "homebrew" ROMs** from multiple third-party hosts. Replacement: ship empty `roms/` directories + a separate optional `homebrew-pack.ps1`. Keeps the core installer small and the trust surface tight.
23. **No way to opt out of individual systems** — it's all-or-nothing. Replacement: `--systems nes,snes,gba` flag.
24. **No `--dry-run`**. Replacement: required, prints planned actions without executing.
