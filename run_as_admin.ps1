param (
    [Parameter(Mandatory=$true)] [string] $scriptName
)

$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$pw=convertto-securestring -AsPlainText -force -string 'P@$$w0rd!'
$cred=new-object -typename system.management.automation.pscredential -argumentlist "\MSTest",$pw
 
$process = Start-Process -Wait -Credential $cred -FilePath powershell.exe -ArgumentList $scriptName -Verbose -NoNewWindow
Wait-Process -Id $process.Id