BeforeAll {
    $script:ModuleManifest = Join-Path $PSScriptRoot '..\..\src\EmulationStationSetup.psd1'
    Import-Module $script:ModuleManifest -Force
}

Describe 'Render-Template' {
    It 'substitutes a single token' {
        InModuleScope EmulationStationSetup {
            $r = Render-Template -Template 'hello {{NAME}}' -Substitutions @{ NAME = 'world' }
            $r | Should -Be 'hello world'
        }
    }

    It 'substitutes multiple tokens' {
        InModuleScope EmulationStationSetup {
            $r = Render-Template -Template '{{A}}-{{B}}-{{A}}' -Substitutions @{ A = 'x'; B = 'y' }
            $r | Should -Be 'x-y-x'
        }
    }

    It 'leaves unknown tokens literal' {
        InModuleScope EmulationStationSetup {
            $r = Render-Template -Template 'a {{KNOWN}} b {{UNKNOWN}} c' -Substitutions @{ KNOWN = 'v' }
            $r | Should -Be 'a v b {{UNKNOWN}} c'
        }
    }

    It 'XML-escapes substitution values by default' {
        InModuleScope EmulationStationSetup {
            $r = Render-Template -Template '<x>{{V}}</x>' -Substitutions @{ V = 'A & B < C' }
            $r | Should -Be '<x>A &amp; B &lt; C</x>'
        }
    }

    It '-NoXmlEscape skips escaping' {
        InModuleScope EmulationStationSetup {
            $r = Render-Template -Template '{{V}}' -Substitutions @{ V = 'A & B' } -NoXmlEscape
            $r | Should -Be 'A & B'
        }
    }
}
