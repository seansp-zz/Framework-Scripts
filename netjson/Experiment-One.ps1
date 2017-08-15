
Function ConvertFrom-ArbritraryXml( $Object )
{
  if (($null -ne $Object ) -and ($null -ne $Object.DocumentElement)) 
  {
    $PSObject = New-Object PSObject
    #document name is the enclosing XML object.
    $documentName = $Object.DocumentElement.Name
    foreach( $child in $Object.DocumentElement.ChildNodes )
    {
        $inner = $child.InnerXml
        Write-Host "Identified CHILD: $($child.Name)"
        if( $inner.StartsWith( "<" ) -and $inner.EndsWith( ">") )
        {
            Write-Host "Identified CHILD: $($child.Name)"
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
    Write-Host "Storing result into $documentName."
    $returnValue = New-Object PSObject
    $returnValue | Add-Member -NotePropertyName $documentName -NotePropertyValue $PSObject
    $returnValue
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

