
Function ConvertFrom-ArbritraryXml( $Object )
{
  if (($null -ne $Object ) -and ($null -ne $Object.DocumentElement)) 
  {
    $PSObject = New-Object PSObject
    #document name is the enclosing XML object.
    Write-Host "WOOOOOOOOOOOO: $($Object.LocalName)"
    $documentName = $Object.DocumentElement.Name
    foreach( $child in $Object.DocumentElement.ChildNodes )
    {
      Write-Host ">>>>#########################"
      $temp = $PSObject | ConvertTo-Json 
      Write-Host $temp 
      Write-Host ">>>>#########################"
      



        $inner = $child.InnerXml
        if( $inner.StartsWith( "<" ) -and $inner.EndsWith( ">") )
        {
            Write-Host "Identified $($child.LocalName): $($child.Name)"
            # Recurse (TODO: DEPTH) to form the type.
            $childObject = ConvertFromInnerXml $child
            $array = @()
            try {
                Write-Host "I am a newly magical try."
                $array = $($PSObject.$($child.LocalName))
                if( ($null -ne $array ) -and !(($array -is [array])) )
                {
                  Write-Host "The fix is IN."
                  $array = @($array)
                }
            }
            catch
            {
                Write-Host "I am a catch."
            }
            Write-Host "I am a plus operator."
            $before = $array | ConvertTo-Json 
            Write-Host "BEFORE:"
            Write-Host $before
            Write-Host "Want to Add:" 
            $addition = $childObject | ConvertTo-Json 
            Write-Host $addition 




            $array += $childObject
            Write-Host "Boom."
            $tempTemp = $array | ConvertTo-Json -Depth 10 
            Write-Host "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
            Write-Host $tempTemp
            Write-Host "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
            

            $PSObject | Add-Member -NotePropertyName $child.LocalName -NotePropertyValue $array -Force
        }
        else {
          Write-Host "Almost-Boom."
           $PSObject | Add-Member -NotePropertyName $child.LocalName -NotePropertyValue $child.InnerXml
        }
        Write-Host "====#########################"
        $temp = $PSObject | ConvertTo-Json -Depth 10
        Write-Host $temp 
        Write-Host "====#########################"
    }
    Write-Host "++++#########################"
    $temp = $PSObject | ConvertTo-Json 
    Write-Host $temp 
    Write-Host "++++#########################"    
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
    $documentName = $Object.LocalName
    foreach( $child in $Object.ChildNodes )
    {
        $inner = $child.InnerXml
        Write-Host "NESTED::---->$($Object.LocalName):$($child.LocalName)"

        if( $inner.StartsWith( "<" ) -and $inner.EndsWith( ">") )
        {
            # Recurse (TODO: DEPTH) to form the type.
            $childObject = ConvertFromInnerXml $child
            $array = @()
            try {
                # $array = $PSObject | Get-Member -Name $child.Name
                Write-Host "INNER:I am a newly magical try."
                $array = $($PSObject.$($child.Name))
                if( ($null -ne $array ) -and !(($array -is [array])) )
                {
                  Write-Host "INNER:The fix is IN."
                  $array = @($array)
                }                
            }
            finally
            {
                $array += $childObject
            }
            $PSObject | Add-Member -NotePropertyName $child.Name -NotePropertyValue $array -Force
        }
        else {
           $PSObject | Add-Member -NotePropertyName $child.Name -NotePropertyValue $child.InnerXml
        }
    }
    $PSObject
    # Write-Host "INNER:Storing result into $documentName."
    # $returnValue = New-Object PSObject
    # $returnValue | Add-Member -NotePropertyName $documentName -NotePropertyValue $PSObject
    # $returnValue
  }
}

