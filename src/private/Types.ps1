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
    [string]       $Url
    [string]       $Sha256
    [DownloadKind] $Kind
    [string]       $System
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
