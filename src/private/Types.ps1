enum PreflightStatus {
    Pass
    Fail
    Warn
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
