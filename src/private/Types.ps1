enum PreflightStatus {
    Pass
    Fail
    Warn
}

enum LauncherKind {
    Libretro
    Standalone
}

enum DownloadKind {
    LibretroCore
    Rom
    Theme
    EmulatorAsset
    Emulator         # An emulator binary (e.g., RPCS3 .7z) — extracted to <InstallRoot>\emulators\<system>\
    SystemFile       # Libretro system files (e.g., C-BIOS for MSX) — extracted to <retroarch>\system\
    Firmware         # Emulator firmware blob (e.g., PS3 PUP) — installed via emulator CLI, not placed on disk by us
}

class EmulatorSystem {
    [string]    $Name
    [string]    $FullName
    [string]    $Platform
    [string]    $Theme
    [string[]]  $RomExtensions
    [string]    $Notes
    [hashtable] $Launcher
    [object[]]  $Packages
    [hashtable] $Artifacts
}

class DownloadSpec {
    [string]       $Id
    [string]       $Url           # mutually exclusive with LocalPath
    [string]       $LocalPath     # relative to module root; bypasses network. Hash still verified.
    [string]       $Sha256
    [DownloadKind] $Kind
    [string]       $System
    [bool]         $KeepArchive    # if true, ROM-kind download is copied (not extracted) under its URL basename
}


class PreflightCheck {
    [string] $Name
    [PreflightStatus] $Status
    [string] $Detail
    [string] $Remediation

    PreflightCheck() { }

    PreflightCheck([string] $name, [PreflightStatus] $status, [string] $detail) {
        $this.Name = $name
        $this.Status = $status
        $this.Detail = $detail
    }

    PreflightCheck([string] $name, [PreflightStatus] $status, [string] $detail, [string] $remediation) {
        $this.Name = $name
        $this.Status = $status
        $this.Detail = $detail
        $this.Remediation = $remediation
    }
}

class InstallReport {
    [datetime] $When
    [PreflightCheck[]] $Checks
    [bool] $OverallPass
}
