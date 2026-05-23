# One-shot helper to fetch C-BIOS MSX BIOS files for fmsx via the openMSX release bundle.
# openMSX ships C-BIOS files in share/systemroms/; we extract just those.
# SourceForge URL for the cbios standalone zip kept failing SSL from this network.
# Not part of the regular test suite — manual fix-up script.

$url    = 'https://github.com/openMSX/openMSX/releases/download/RELEASE_21_0/openmsx-21.0-windows-vc-x64-bin.zip'
$tmpZip = Join-Path ([System.IO.Path]::GetTempPath()) ("openmsx-" + [guid]::NewGuid().Guid.Substring(0,8) + '.zip')
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("openmsx-extract-" + [guid]::NewGuid().Guid.Substring(0,8))
$sysDir = 'C:\RetroArch-Win64\system'

Write-Host "1. Downloading openMSX 21.0 binary bundle (13 MB) for its bundled C-BIOS files ..."
Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
$size = (Get-Item $tmpZip).Length
$hash = (Get-FileHash $tmpZip -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host ("   downloaded {0:N0} bytes, sha256 {1}" -f $size, $hash)

Write-Host "2. Extracting ..."
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($tmpZip, $tmpDir)

Write-Host "3. Locating C-BIOS files in the bundle ..."
$cbiosFiles = Get-ChildItem -LiteralPath $tmpDir -Recurse -Filter 'cbios_*.rom'
if (-not $cbiosFiles) {
    # openMSX may not name them cbios_*; try BIOS-like names in systemroms/
    $cbiosFiles = Get-ChildItem -LiteralPath $tmpDir -Recurse -File | Where-Object {
        $_.DirectoryName -match 'systemroms|machines' -and $_.Extension -eq '.rom'
    }
}
if (-not $cbiosFiles) {
    Write-Host "   No C-BIOS files found. Tree contents:"
    Get-ChildItem -LiteralPath $tmpDir -Recurse -File | Where-Object Extension -in @('.rom', '.xml') |
        Select-Object FullName | Format-Table -AutoSize
    throw "No C-BIOS files in openMSX bundle — bundle layout may have changed."
}
Write-Host ("   Found {0} ROM file(s):" -f $cbiosFiles.Count)
$cbiosFiles | Select-Object @{n='Name';e={$_.Name}}, @{n='KB';e={[math]::Round($_.Length/1KB,1)}} | Format-Table -AutoSize

Write-Host "4. Ensuring RetroArch system dir exists ..."
if (-not (Test-Path $sysDir)) { New-Item -ItemType Directory -Path $sysDir -Force | Out-Null }

# fmsx_libretro looks for these specific filenames in RetroArch's system dir.
# openMSX-bundled C-BIOS uses '+' (e.g. cbios_main_msx2+.rom) and a shared cbios_sub.rom
# rather than the per-version cbios_sub_msx2.rom / cbios_sub_msx2p.rom that the standalone
# cbios-0.30.zip ships. We map both naming conventions.
$renames = @{
    # standalone cbios-0.30.zip naming
    'cbios_main_msx1.rom'  = @('MSX.ROM')
    'cbios_main_msx2.rom'  = @('MSX2.ROM')
    'cbios_sub_msx2.rom'   = @('MSX2EXT.ROM')
    'cbios_main_msx2p.rom' = @('MSX2P.ROM')
    'cbios_sub_msx2p.rom'  = @('MSX2PEXT.ROM')
    'cbios_logo_msx1.rom'  = @('CBIOS_LOGO_MSX1.ROM')
    'cbios_logo_msx2.rom'  = @('CBIOS_LOGO_MSX2.ROM')
    'cbios_logo_msx2p.rom' = @('CBIOS_LOGO_MSX2P.ROM')
    'cbios_music.rom'      = @('CBIOS_MUSIC.ROM')

    # openMSX-bundled naming
    'cbios_main_msx2+.rom' = @('MSX2P.ROM')
    'cbios_sub.rom'        = @('MSX2EXT.ROM', 'MSX2PEXT.ROM')   # shared between MSX2 + MSX2+
    'cbios_logo_msx2+.rom' = @('CBIOS_LOGO_MSX2P.ROM')
}

Write-Host "5. Copying + renaming into ${sysDir}:"
$copied = 0
foreach ($f in $cbiosFiles) {
    if ($renames.ContainsKey($f.Name)) {
        foreach ($destName in $renames[$f.Name]) {
            $dest = Join-Path $sysDir $destName
            Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
            Write-Host ("   {0,-30} -> {1}" -f $f.Name, $destName)
            $copied++
        }
    }
}
Write-Host ""
Write-Host "Copied $copied file(s)."

Write-Host ""
Write-Host "6. Result in $sysDir :"
Get-ChildItem -LiteralPath $sysDir | Select-Object Name, @{n='KB';e={[math]::Round($_.Length/1KB,1)}} | Format-Table -AutoSize

Write-Host ""
Write-Host "7. Cleanup temp:"
Remove-Item -LiteralPath $tmpZip -Force
Remove-Item -LiteralPath $tmpDir -Recurse -Force
Write-Host "Done. Castle Excellent (cart .rom) should now boot in MSX via ES-DE."
