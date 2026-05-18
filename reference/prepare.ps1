function DownloadFiles {
    param ([String]$jsonDownloadOption)

    Write-Host "Starting downloading of $jsonDownloadOption"

    Get-Content "$scriptDir\download_list.json" | ConvertFrom-Json | Select-Object -expand $jsonDownloadOption | ForEach-Object {

        $url = $_.url
        $file = $_.file
        $output = "$requirementsFolder\$file"

        $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        if(![System.IO.File]::Exists($output)){

            Write-Host "INFO: Downloading $file"
            if($PSVersionTable.PSEdition -eq "Core"){
                Invoke-WebRequest $url -Out $output -SkipCertificateCheck -UserAgent $userAgent
            } else {

                add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
                [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

                Invoke-WebRequest $url -Out $output -UserAgent $userAgent

            }
            Write-Host "INFO: Finished Downloading $file successfully to: $output"
            Write-Host "INFO: Size of the downloaded file is $((Get-Item $output).Length / 1MB) MB"

        } else {

            Write-Host $file "INFO: Already exists...Skipping download."

        }

    }

}

function GithubReleaseFiles {

    Get-Content "$scriptDir\download_list.json" | ConvertFrom-Json | Select-Object -expand releases | ForEach-Object {

        $repo = $_.repo
        $file = $_.file
        $releases = "https://api.github.com/repos/$repo/releases"
        $tag = (Invoke-WebRequest $releases -usebasicparsing| ConvertFrom-Json)[0].tag_name

        $url = "https://github.com/$repo/releases/download/$tag/$file"
        $output = "$requirementsFolder\$file"

        if(![System.IO.File]::Exists($output)) {

            Write-Host "INFO: Downloading $file"
            Invoke-WebRequest $url -Out $output
            Write-Host "INFO: Finished Downloading $file successfully to: $output"
            Write-Host "INFO: Size of the downloaded file is $((Get-Item $output).Length / 1MB) MB"

        } else {

            Write-Host $file "INFO: Already exists...Skipping download."
        }

    }

}

function Expand-Archive([string]$Path, [string]$Destination, [bool]$VerboseLogging = $false) {
    $7z_Application = "C:\Program Files\7-Zip\7z.exe"
    $7z_Arguments = @(
        'x',                         # eXtract files with full paths
        '-y',                        # assume Yes on all queries
        "-o$Destination",            # set Output directory
        $Path                        # <archive_name>
    )

    Write-Output "Extracting file: $Path to destination: $Destination"

    if ($VerboseLogging) {
        & $7z_Application $7z_Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "7-Zip exited with code $LASTEXITCODE"
        }
    } else {
        & $7z_Application $7z_Arguments | Out-Null
    }
}

# Get script path
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path $scriptPath
Write-Host "INFO: Script directory is: $scriptDir"

Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

choco install git -y | Out-Null

# Install and setup scoop
if($env:path -match "scoop"){
    Write-Host "INFO: Scoop appears to be installed, skipping installation"
} else {
    Write-Host "INFO: Scoop not detected, installing scoop"
    iwr -useb get.scoop.sh -outfile 'installScoop.ps1'
    .\installScoop.ps1 -RunAsAdmin
}

Write-Host "INFO: Running Scoop Bucket Workaround"
# https://github.com/ScoopInstaller/Scoop/issues/4917#issuecomment-1125400640
scoop bucket rm main
scoop bucket add main

Write-Host "INFO: Adding scoop bucket"
scoop update
scoop bucket add emulators https://github.com/borger/scoop-emulators.git
scoop bucket add games
Write-Host "INFO: Installing Azahar (3DS)"
scoop install azahar
Write-Host "INFO: Installing PPSSPP"
scoop install ppsspp-dev
Write-Host "INFO: Installing Ryujinx (Switch)"
scoop install ryujinx
Write-Host "INFO: Installing xemu (Xbox)"
scoop install xemu
scoop install rpcs3

$azaharInstallDir = "$env:userprofile\scoop\apps\azahar\current"
$ppssppInstallDir = "$env:userprofile\scoop\apps\ppsspp-dev\current"
$ryujinxInstallDir = "$env:userprofile\scoop\apps\ryujinx\current"
$xemuInstallDir = "$env:userprofile\scoop\apps\xemu\current"
$rpcs3InstallDir = "$env:userprofile\scoop\apps\rpcs3\current"

choco install 7zip --no-progress -y | Out-Null
choco install dolphin --pre --no-progress -y | Out-Null
choco install cemu --no-progress -y | Out-Null

# Acquire files
$requirementsFolder = "$PSScriptRoot\requirements"
New-Item -ItemType Directory -Force -Path $requirementsFolder
DownloadFiles("downloads")
DownloadFiles("other_downloads")
GithubReleaseFiles

# Install Emulation Station
Write-Host "INFO: Starting Emulation station to generate config"
Start-Process "$requirementsFolder\emulationstation_win32_latest.exe" -ArgumentList "/S" -Wait

# Generate Emulation Station config file
& "${env:ProgramFiles(x86)}\EmulationStation\emulationstation.exe"
$timeout = 60 # 60 seconds timeout
$elapsed = 0
while (!(Test-Path "$env:userprofile\.emulationstation\es_systems.cfg") -and $elapsed -lt $timeout) {
    Write-Host "INFO: Checking for config file... ($elapsed/$timeout)"
    Start-Sleep 10
    $elapsed += 10
}

if (Test-Path "$env:userprofile\.emulationstation\es_systems.cfg") {
    Write-Host "INFO: Config file generated"
} else {
    Write-Host "WARNING: Config file not generated within timeout. Creating directory anyway."
    New-Item -ItemType Directory -Force -Path "$env:userprofile\.emulationstation\" | Out-Null
}
Stop-Process -Name "emulationstation" -ErrorAction SilentlyContinue

# NOTE: This is a partial snapshot for analysis purposes only.
# Full original at: https://github.com/Francommit/win10_emulation_station/blob/master/prepare.ps1
# Snapshot captured: 2026-05-17
# See SNAPSHOT.md for the analysis index and key observations.
