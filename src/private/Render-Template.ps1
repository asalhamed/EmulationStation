function Render-Template {
    <#
    .SYNOPSIS
    Substitutes {{TOKEN}} placeholders in a template string with values from a hashtable.

    .DESCRIPTION
    Simple text-replace renderer. Each key in -Substitutions is matched against literal
    '{{KEY}}' (case-sensitive) in the template body. Unknown tokens are left literal — this is
    intentional so callers can spot un-substituted placeholders visually.

    Values are XML-escaped by default (& -> &amp;, < -> &lt;, > -> &gt;). Use -NoXmlEscape
    when rendering non-XML output (e.g., INI files).

    .PARAMETER Template
    Template body as a single string. Use $(Get-Content -Raw) to load a file.

    .PARAMETER Substitutions
    Hashtable of token name -> value. Token names should not include the {{}} delimiters.

    .PARAMETER NoXmlEscape
    Skip XML escaping; substitute values literally.
    #>
    [CmdletBinding()]
    [OutputType('string')]
    param(
        [Parameter(Mandatory)]
        [string] $Template,

        [Parameter(Mandatory)]
        [hashtable] $Substitutions,

        [switch] $NoXmlEscape
    )

    $result = $Template
    foreach ($key in $Substitutions.Keys) {
        $value = [string]$Substitutions[$key]
        if (-not $NoXmlEscape) {
            $value = $value -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
        }
        $result = $result.Replace("{{$key}}", $value)
    }
    $result
}
