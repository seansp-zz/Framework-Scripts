param (
    [Parameter(Mandatory=$true)] [string] $scriptName
)

# $o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
# $pw=convertto-securestring -AsPlainText -force -string 'P@$$w0rd!'
# $cred=new-object -typename system.management.automation.pscredential -argumentlist "lis-f1637\MSTest",$pw
 
# $process = Start-Process -Wait -Credential $cred -FilePath powershell.exe -ArgumentList $scriptName -Verbose -NoNewWindow
$process = Start-Process -Wait -FilePath powershell.exe -ArgumentList $scriptName -Verbose -NoNewWindow
Wait-Process -Id $process.Id