# ADR-0002: No TLS bypass, ever. HTTPS-only. PS 5 unsupported.

**Status:** Accepted (2026-05-17)

## Context
Upstream `prepare.ps1` includes this for PowerShell 5.1:
```powershell
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(...) { return true; }
}
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
```
And on PowerShell 7 it uses `Invoke-WebRequest … -SkipCertificateCheck`. Both globally disable TLS certificate validation for the entire process.

The download_list.json also contains plain `http://` URLs for `epsxe.com` and `nesworld.com`.

This is done because (a) PS 5.1 ships without modern TLS roots and breaks on some sites; (b) some emulator-host certs have been flaky historically. The "fix" creates a real MITM hole: any attacker on the network path can substitute the binary you download.

## Decision
1. **Never call `-SkipCertificateCheck`.** Never install a custom `CertificatePolicy`.
2. **HTTPS-only.** Manifests reject `http://` URLs at parse time. The two `http://` upstream URLs get replaced with HTTPS equivalents (or the file is removed from the manifest).
3. **PowerShell 5.1 unsupported.** Preflight requires PS 7.4+. This eliminates the root cause for the original bypass.
4. **Every download has a SHA-256.** Even with TLS, we don't trust the byte stream — we verify it matches the hash we pinned.

## Why
- TLS bypass is a single line that silently weakens every download. There is no "narrow" version of it.
- The user friction of "install PowerShell 7" (one `winget` line) is dramatically lower than the cost of explaining to a friend why their emulator install vector is MITM-able.
- SHA-256 on top of TLS gives us defense-in-depth: even if a CA mis-issues, even if an upstream host is compromised, the hash mismatch catches it.

## Consequences
- Some upstream URLs may not work over HTTPS. For each `http://` entry in `reference/download_list.json`, we either:
  - Find the HTTPS equivalent at the same host.
  - Find an alternate trustworthy mirror (archive.org, GitHub release).
  - Drop the artifact from the manifest and document the loss.
- We can't run on PS 5.1. README must lead with the PS 7 install step.
- Hash-pinning means a maintenance burden: when upstream artifacts move, hashes need re-pinning. We accept this — it's the same maintenance cost as any reproducible build.

## What this does not buy us
- A compromised manifest in *our* repo would silently install whatever the attacker pinned. We mitigate by signing commits and reviewing manifest PRs carefully, but if our repo is owned, the user is owned. This is true of any installer.
