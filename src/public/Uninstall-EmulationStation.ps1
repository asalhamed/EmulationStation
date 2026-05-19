function Uninstall-EmulationStation {
    <#
    .SYNOPSIS
    Reverses an Install-EmulationStation run by walking install-log.json in reverse.

    .DESCRIPTION
    Reads $InstallRoot\install-log.json (written by M8) and undoes each Action that is undoable:
        - ShortcutCreated -> Remove the .lnk
        - ConfigRendered  -> Remove the .cfg
        - FileWritten     -> Remove the file
        - DirectoryCreated -> Remove the dir IF EMPTY (user-dropped ROMs are preserved)
        - WinGetInstall   -> Skip by default; opt-in via -RemoveWinGetPackages. Only removes
                             packages we marked Status='Installed' (skips 'AlreadyInstalled'
                             and 'Upgraded' to preserve pre-existing user state).

    Each Remove-Item is wrapped in Test-Path so a partial pre-removal by the user is a no-op,
    not an error. Failures are aggregated into the returned summary.

    .PARAMETER InstallRoot
    Directory containing install-log.json. Default: %USERPROFILE%\.emulationstation

    .PARAMETER RemoveWinGetPackages
    Also winget-uninstall the emulator packages we installed (RetroArch, Dolphin, etc.).
    Default OFF — leaving them is safer because removing affects other things the user might
    use the emulators for.

    .PARAMETER RemoveInstallRoot
    After uninstall, also remove the install-log.json and the InstallRoot directory itself
    if it's empty (or contains only the .cache directory).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('hashtable')]
    param(
        [string] $InstallRoot = (Join-Path $env:USERPROFILE '.emulationstation'),
        [switch] $RemoveWinGetPackages,
        [switch] $RemoveInstallRoot
    )

    $started  = Get-Date
    $reversed = [System.Collections.Generic.List[hashtable]]::new()
    $skipped  = [System.Collections.Generic.List[hashtable]]::new()
    $failed   = [System.Collections.Generic.List[hashtable]]::new()

    $logPath = Join-Path $InstallRoot 'install-log.json'
    if (-not (Test-Path -LiteralPath $logPath)) {
        throw "No install log found at $logPath; nothing to uninstall."
    }

    $doc = Get-Content -LiteralPath $logPath -Raw | ConvertFrom-Json
    $allActions = @($doc.Actions)

    # Walk in reverse so we undo the latest actions first.
    for ($i = $allActions.Count - 1; $i -ge 0; $i--) {
        $action = $allActions[$i]
        $kind   = $action.Kind

        try {
            switch ($kind) {
                'Started' {
                    $skipped.Add(@{ Action = $action; Reason = 'meta marker' }) | Out-Null
                    break
                }
                'Finished' {
                    $skipped.Add(@{ Action = $action; Reason = 'meta marker' }) | Out-Null
                    break
                }
                'ShortcutCreated' {
                    if (Test-Path -LiteralPath $action.Path) {
                        if ($PSCmdlet.ShouldProcess($action.Path, 'Remove shortcut')) {
                            Remove-Item -LiteralPath $action.Path -Force
                            $reversed.Add(@{ Action = $action; Result = 'Removed' }) | Out-Null
                        }
                    } else {
                        $skipped.Add(@{ Action = $action; Reason = 'already missing' }) | Out-Null
                    }
                    break
                }
                'ConfigRendered' {
                    if (Test-Path -LiteralPath $action.Path) {
                        if ($PSCmdlet.ShouldProcess($action.Path, 'Remove config file')) {
                            Remove-Item -LiteralPath $action.Path -Force
                            $reversed.Add(@{ Action = $action; Result = 'Removed' }) | Out-Null
                        }
                    } else {
                        $skipped.Add(@{ Action = $action; Reason = 'already missing' }) | Out-Null
                    }
                    break
                }
                'FileWritten' {
                    if (Test-Path -LiteralPath $action.Path) {
                        if ($PSCmdlet.ShouldProcess($action.Path, 'Remove file')) {
                            Remove-Item -LiteralPath $action.Path -Force
                            $reversed.Add(@{ Action = $action; Result = 'Removed' }) | Out-Null
                        }
                    } else {
                        $skipped.Add(@{ Action = $action; Reason = 'already missing' }) | Out-Null
                    }
                    break
                }
                'DirectoryCreated' {
                    if (Test-Path -LiteralPath $action.Path) {
                        $contents = @(Get-ChildItem -LiteralPath $action.Path -Force -ErrorAction SilentlyContinue)
                        if ($contents.Count -eq 0) {
                            if ($PSCmdlet.ShouldProcess($action.Path, 'Remove empty directory')) {
                                Remove-Item -LiteralPath $action.Path -Force
                                $reversed.Add(@{ Action = $action; Result = 'Removed' }) | Out-Null
                            }
                        } else {
                            $skipped.Add(@{ Action = $action; Reason = "directory not empty ($($contents.Count) items)" }) | Out-Null
                        }
                    } else {
                        $skipped.Add(@{ Action = $action; Reason = 'already missing' }) | Out-Null
                    }
                    break
                }
                'WinGetInstall' {
                    if ($action.Status -ne 'Installed') {
                        $skipped.Add(@{ Action = $action; Reason = "Status was '$($action.Status)'; we did not cause this install" }) | Out-Null
                    } elseif (-not $RemoveWinGetPackages) {
                        $skipped.Add(@{ Action = $action; Reason = 'opt-in via -RemoveWinGetPackages' }) | Out-Null
                    } else {
                        if ($PSCmdlet.ShouldProcess($action.Id, 'winget uninstall')) {
                            $r = Uninstall-WinGetPackage -Id $action.Id
                            $reversed.Add(@{ Action = $action; Result = $r.Status }) | Out-Null
                        }
                    }
                    break
                }
                default {
                    $skipped.Add(@{ Action = $action; Reason = "unknown Kind '$kind'" }) | Out-Null
                }
            }
        } catch {
            $failed.Add(@{ Action = $action; Message = $_.Exception.Message }) | Out-Null
        }
    }

    # Optionally remove the install log + cache dir + InstallRoot itself if empty.
    if ($RemoveInstallRoot) {
        $tmpLog = "$logPath.tmp"
        foreach ($p in @($logPath, $tmpLog)) {
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
        }
        $cacheDir = Join-Path $InstallRoot '.cache'
        if (Test-Path -LiteralPath $cacheDir) {
            Remove-Item -LiteralPath $cacheDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $InstallRoot) {
            $remaining = @(Get-ChildItem -LiteralPath $InstallRoot -Force -ErrorAction SilentlyContinue)
            if ($remaining.Count -eq 0) {
                Remove-Item -LiteralPath $InstallRoot -Force -ErrorAction SilentlyContinue
            }
        }
    }

    @{
        Started     = $started
        Finished    = Get-Date
        InstallRoot = $InstallRoot
        Reversed    = $reversed.ToArray()
        Skipped     = $skipped.ToArray()
        Failed      = $failed.ToArray()
    }
}
