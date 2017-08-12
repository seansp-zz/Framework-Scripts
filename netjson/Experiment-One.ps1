
Function ConvertFromXml( $Object )
{

  if (($null -ne $Object ) -and ($null -ne $Object.DocumentElement)) {

    $PSObject = New-Object PSObject
    $PSObject | Add-Member -NotePropertyName "Name" -NotePropertyValue $Object.DocumentElement.Name
    foreach( $child in $Object.DocumentElement.ChildNodes )
    {
        $inner = $child.InnerXml

        if( $inner.StartsWith( "<" ) -and $inner.EndsWith( ">") )
        {
            # Recurse (TODO: DEPTH) to form the type.
            $childObject = ConvertFromInnerXml $child
            $array = @()
            try {
                $array = $PSObject | Get-Member -Name $child.Name
            }
            finally
            {
                $array = $array + $childObject
            }
            $PSObject | Add-Member -NotePropertyName $child.Name -NotePropertyValue $array -Force
        }
        else {
           $PSObject | Add-Member -NotePropertyName $child.Name -NotePropertyValue $child.InnerXml
        }
    }
    $PSObject
  }
}

Function ConvertFromInnerXml( $Object )
{

  if ($null -ne $Object) {

    $PSObject = New-Object PSObject
    foreach( $child in $Object.ChildNodes )
    {
        $inner = $child.InnerXml

        if( $inner.StartsWith( "<" ) -and $inner.EndsWith( ">") )
        {
            # Recurse (TODO: DEPTH) to form the type.
            $childObject = ConvertFromInnerXml $child
            $array = @()
            try {
                $array = $PSObject | Get-Member -Name $child.Name
            }
            finally
            {
                $array += $childObject[1]
            }
            $PSObject | Add-Member -NotePropertyName $child.Name -NotePropertyValue $array -Force
        }
        else {
           $PSObject | Add-Member -NotePropertyName $child.Name -NotePropertyValue $child.InnerXml
        }
    }
    $PSObject
  }
}


$xml = [xml] (Get-Content "sample.xml")
Write-Host $xml -ForegroundColor Green
$SomeCrazyType = ConvertFromXml ( $xml )
$foo = $SomeCrazyType | ConvertTo-Json -Depth 3

Write-Host $foo -ForegroundColor Yellow
