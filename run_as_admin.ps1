param (
    [Parameter(Mandatory=$true)] [string] $launcher,
    [Parameter(Mandatory=$true)] [string] $script
)

$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$pw=convertto-securestring -AsPlainText -force -string 'P@$$w0rd!'
$cred=new-object -typename system.management.automation.pscredential -argumentlist "MSTest",$pw

$s=New-PSSession -ComputerName 169.254.241.55 -Authentication Basic -Credential $cred  -Port 443 -UseSSL -SessionOption $o

$scriptBlockString = 
{ 
   param($pg,$sp) 
   $code = Start-Process -FilePath powershell.exe -ArgumentList $launcher $sp -NoNewWindow -Wait
   $code.ExitCode
}

$scriptBlock = [scriptblock]::Create($scriptBlockString)

$result = Invoke-Command -Session $s -ScriptBlock $scriptBlock -ArgumentList $script

if($result -ne 0) {
    exit 1
} else {
    exit 0
}

# invoke-command -session $s -FilePath $script
# $remote_status = invoke-command -Session $s -ScriptBlock { $? } -ErrorAction SilentlyContinue

# if ($? -eq $false -or $remote_status -ne 0) {
    # exit 1
# } else {
    # exit 0
# }