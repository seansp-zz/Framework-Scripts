param (
    [Parameter(Mandatory=$true)] [string] $script
)

$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$pw=convertto-securestring -AsPlainText -force -string 'P@$$w0rd!'
$cred=new-object -typename system.management.automation.pscredential -argumentlist "MSTest",$pw

$s=New-PSSession -ComputerName 169.254.241.55 -Authentication Basic -Credential $cred  -Port 443 -UseSSL -SessionOption $o

[string]$scripttext="{ ./run_as_admin.ps1 " + $script + '; $cmd_status=$?' + " }"
[ScriptBlock]$scriptblock = [ScriptBlock]::Create($scripttext)

invoke-command -session $s -ScriptBlock $scriptblock

$remote_status = invoke-command -Session $s -ScriptBlock { $cmd_status }

exit $remote_status