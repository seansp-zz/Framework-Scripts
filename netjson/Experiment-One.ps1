
Function ConvertFrom-ArbritraryXml( $Object )
{
  $originalObject = $null
  if ($null -ne $Object ) 
  {

    if( ($null -ne $Object.DocumentElement))
    {
      # Get to the document element.  We will use this for recursion.
       $originalObject = $Object
       $Object = $Object.DocumentElement
    } 
  
    $PSObject = New-Object PSObject
    $documentName = $Object.LocalName
    Write-Host "DocumentName = $documentName"
    foreach( $child in $Object.ChildNodes )
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
            $childObject = ConvertFrom-ArbritraryXml $child
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
    Write-Host "GLITCH!!!!Storing result into $documentName."
    if( $null -ne $originalObject )
    {
      $returnValue = New-Object PSObject
      $returnValue | Add-Member -NotePropertyName $documentName -NotePropertyValue $PSObject
      $returnValue
    }
    else {
      $PSObject    
    }
  }
}

