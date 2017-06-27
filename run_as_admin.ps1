param (
    [Parameter(Mandatory=$true)] [string] $scriptName
)

$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$pw=convertto-securestring -AsPlainText -force -string 'N0rthW00d5!'
$cred=new-object -typename system.management.automation.pscredential -argumentlist "redmond\jfawcett",$pw
 
$process = Start-Process -Wait -Credential $cred -FilePath powershell.exe -ArgumentList $scriptName -Verbose -NoNewWindow
Wait-Process -Id $process.Id