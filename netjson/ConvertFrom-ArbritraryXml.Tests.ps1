$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

. .\Experiment-One.ps1

Describe "ConvertFrom-JSON -- Simple Case" {
    It "Generates simple JSON baseline for validation" {
        $PSObject = New-Object PSObject
        $PSObject | Add-Member -NotePropertyName "Name" -NotePropertyValue "Top"
#        InnerXml:"<Property Name="Name" Type="System.String">Top</Property>"
#       TODO: Hmm.
        $result_simple_case = $PSObject | ConvertTo-Json
        $xml_simple_case = $PSObject | ConvertTo-Xml
        $true | Should Be $true
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
    It "Simple Nested XML" {
        $simple="
<TOP>
  <Child/>
</TOP>
"
        $xml = [xml] $simple
        # Write-Host $xml -ForegroundColor Green
        $SomeCrazyType = ConvertFromXml ( $xml )
        # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
        # Write-Host $foo -ForegroundColor Yellow

        $testValue = $SomeCrazyType | ConvertTo-Json

        $testValue | Should Be @'
{
    "Name":  "TOP",
    "Child":  ""
}
'@
    }
    It "Two nested children -- XML" {
        $simple="
<TOP>
  <Child>
    <Name>Alan</Name>
  </Child>
  <Child>
    <Name>Beth</Name>
  </Child>
</TOP>
"
        $xml = [xml] $simple
        # Write-Host $xml -ForegroundColor Green
        $SomeCrazyType = ConvertFromXml ( $xml )
        # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
        # Write-Host $foo -ForegroundColor Yellow
        $testValue = $SomeCrazyType | ConvertTo-Json
        $testValue | Should Be @'
{
    "Name":  "TOP",
    "Alan":  {
                 "Name":  "Alan"
             },
    "Beth":  {
                 "Name":  "Beth"
             }
}
'@
    }
}
