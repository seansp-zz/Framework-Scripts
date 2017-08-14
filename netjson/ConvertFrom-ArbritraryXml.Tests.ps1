$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

. .\Experiment-One.ps1

Describe "ConvertFrom-ArbritraryXml" {
    It "Verify Simple XML" {
        $simple="
<TOP>
</TOP>
"
        $xml = [xml] $simple
        # Write-Host $xml -ForegroundColor Green
        $SomeCrazyType = ConvertFromXml ( $xml )
        # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
        # Write-Host $foo -ForegroundColor Yellow

        $SomeCrazyType | ConvertTo-Json | Should Be @'
{
    "Name":  "TOP"
}
'@
    }
    It "Verify Simple XML" {
        $simple="
<TOP>
</TOP>
"
        $xml = [xml] $simple
        # Write-Host $xml -ForegroundColor Green
        $SomeCrazyType = ConvertFromXml ( $xml )
        # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
        # Write-Host $foo -ForegroundColor Yellow

        $SomeCrazyType | ConvertTo-Json | Should Be @'
{
    "Name":  "TOP"
}
'@
    }
    It "Verify Simple XML" {
        $simple="
<TOP>
</TOP>
"
        $xml = [xml] $simple
        # Write-Host $xml -ForegroundColor Green
        $SomeCrazyType = ConvertFromXml ( $xml )
        # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
        # Write-Host $foo -ForegroundColor Yellow

        $SomeCrazyType | ConvertTo-Json | Should Be @'
{
    "Name":  "TOP"
}
'@
    }
    It "Verify Simple XML" {
        $simple="
<TOP>
</TOP>
"
        $xml = [xml] $simple
        # Write-Host $xml -ForegroundColor Green
        $SomeCrazyType = ConvertFromXml ( $xml )
        # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
        # Write-Host $foo -ForegroundColor Yellow

        $SomeCrazyType | ConvertTo-Json | Should Be @'
{
    "Name":  "TOP"
}
'@
    }
    It "Verify Simple XML" {
        $simple="
<TOP>
</TOP>
"
        $xml = [xml] $simple
        # Write-Host $xml -ForegroundColor Green
        $SomeCrazyType = ConvertFromXml ( $xml )
        # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
        # Write-Host $foo -ForegroundColor Yellow

        $SomeCrazyType | ConvertTo-Json | Should Be @'
{
    "Name":  "TOP"
}
'@
    }
    It "Verify Simple XML" {
        $simple="
<TOP>
</TOP>
"
        $xml = [xml] $simple
        # Write-Host $xml -ForegroundColor Green
        $SomeCrazyType = ConvertFromXml ( $xml )
        # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
        # Write-Host $foo -ForegroundColor Yellow

        $SomeCrazyType | ConvertTo-Json | Should Be @'
{
    "Name":  "TOP"
}
'@
    }
    It "Verify Simple XML" {
        $simple="
<TOP>
</TOP>
"
        $xml = [xml] $simple
        # Write-Host $xml -ForegroundColor Green
        $SomeCrazyType = ConvertFromXml ( $xml )
        # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
        # Write-Host $foo -ForegroundColor Yellow

        $SomeCrazyType | ConvertTo-Json | Should Be @'
{
    "Name":  "TOP"
}
'@
    }
    It "Verify Simple XML" {
        $simple="
<TOP>
</TOP>
"
        $xml = [xml] $simple
        # Write-Host $xml -ForegroundColor Green
        $SomeCrazyType = ConvertFromXml ( $xml )
        # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
        # Write-Host $foo -ForegroundColor Yellow

        $SomeCrazyType | ConvertTo-Json | Should Be @'
{
    "Name":  "TOP"
}
'@
    }
    It "Verify Simple XML" {
        $simple="
<TOP>
</TOP>
"
        $xml = [xml] $simple
        # Write-Host $xml -ForegroundColor Green
        $SomeCrazyType = ConvertFromXml ( $xml )
        # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
        # Write-Host $foo -ForegroundColor Yellow

        $SomeCrazyType | ConvertTo-Json | Should Be @'
{
    "Name":  "TOP"
}
'@
    }
    It "Verify Simple XML" {
        $simple="
<TOP>
</TOP>
"
        $xml = [xml] $simple
        # Write-Host $xml -ForegroundColor Green
        $SomeCrazyType = ConvertFromXml ( $xml )
        # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
        # Write-Host $foo -ForegroundColor Yellow

        $SomeCrazyType | ConvertTo-Json | Should Be @'
{
    "Name":  "TOP"
}
'@
    }
    It "Verify Simple XML" {
        $simple="
<TOP>
</TOP>
"
        $xml = [xml] $simple
        # Write-Host $xml -ForegroundColor Green
        $SomeCrazyType = ConvertFromXml ( $xml )
        # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
        # Write-Host $foo -ForegroundColor Yellow

        $SomeCrazyType | ConvertTo-Json | Should Be @'
{
    "Name":  "TOP"
}
'@
    }
    It "Verify Simple XML" {
        $simple="
<TOP>
</TOP>
"
        $xml = [xml] $simple
        # Write-Host $xml -ForegroundColor Green
        $SomeCrazyType = ConvertFromXml ( $xml )
        # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
        # Write-Host $foo -ForegroundColor Yellow

        $SomeCrazyType | ConvertTo-Json | Should Be @'
{
    "Name":  "TOP"
}
'@
    }

}
