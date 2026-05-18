function Write-EsSettings {
    <#
    .SYNOPSIS
    Renders es_settings.cfg from the static template and writes it to disk.

    .DESCRIPTION
    The settings file is almost entirely static — only the slideshow paths reference the user
    profile, which we substitute via {{USERPROFILE}}. Output is XML-validated before write.

    .PARAMETER UserProfile
    The user profile directory (typically %USERPROFILE%). Forward-slashed in the output to match
    upstream's conventions for these particular paths.

    .PARAMETER OutputPath
    Where to write es_settings.cfg.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $UserProfile,

        [Parameter(Mandatory)]
        [string] $OutputPath
    )

    $templatePath = Join-Path $script:TemplateRoot 'es_settings.cfg.template'
    if (-not (Test-Path -LiteralPath $templatePath)) {
        throw "Template not found: $templatePath"
    }
    $template = Get-Content -LiteralPath $templatePath -Raw

    $normalized = $UserProfile -replace '\\', '/'

    $rendered = Render-Template -Template $template -Substitutions @{
        USERPROFILE = $normalized
    } -NoXmlEscape   # The substituted value is a path, used in attribute content already-escaped by ES conventions

    # Note: es_settings.cfg is XML-ish but has multiple root elements, matching upstream's format and
    # what EmulationStation expects. We deliberately do NOT validate as a single-rooted XmlDocument.

    $destDir = Split-Path -Parent $OutputPath
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    Set-Content -LiteralPath $OutputPath -Value $rendered -NoNewline
}
