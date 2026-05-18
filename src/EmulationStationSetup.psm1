#Requires -Version 7.4

# Module-scoped paths, used by functions to find sibling files at runtime.
$script:ModuleRoot   = $PSScriptRoot
$script:ProjectRoot  = Split-Path $PSScriptRoot -Parent
$script:ManifestRoot = Join-Path $script:ProjectRoot 'manifest'
$script:TemplateRoot = Join-Path $PSScriptRoot 'templates'

# Types first — classes must be in scope before any function that references them.
. (Join-Path $PSScriptRoot 'private\Types.ps1')

# Then private helpers (excluding Types.ps1 which we already loaded).
$privateFiles = Get-ChildItem -Path (Join-Path $PSScriptRoot 'private') -Filter '*.ps1' |
    Where-Object Name -NE 'Types.ps1'
foreach ($file in $privateFiles) {
    . $file.FullName
}

# Then public cmdlets.
$publicFiles = Get-ChildItem -Path (Join-Path $PSScriptRoot 'public') -Filter '*.ps1'
foreach ($file in $publicFiles) {
    . $file.FullName
}

Export-ModuleMember -Function $publicFiles.BaseName
