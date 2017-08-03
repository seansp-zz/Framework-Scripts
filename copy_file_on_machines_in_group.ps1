param (
    [Parameter(Mandatory=$false)] [string[]] $requestedNames,
    
    [Parameter(Mandatory=$false)] [string] $destSA="smokesourcestorageacct",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_source_resource_group",

    [Parameter(Mandatory=$false)] [string] $suffix="-Runonce-Primed.vhd",

    [Parameter(Mandatory=$false)] [string] $scriptName="unset"
)
    
    
. c:\Framework-Scripts\common_functions.ps1
. c:\Framework-Scripts\secrets.ps1

[System.Collections.ArrayList]$vmNames_array
$vmNameArray = {$vmNames_array}.Invoke()
$vmNameArray.Clear()
$vmNameArray = $requestedNames.Split(',')

write-host "Copying file $file to $vmNameArray "

#
#  Session stuff
#
$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$cred = make_cred

$password="$TEST_USER_ACCOUNT_PASS"

$scriptCommand= { param($cmd) $cmd } 

$command="cp -f /root/Framework-Scripts/" + $scriptName + " /root/runonce.d"
$runCommand = "echo $password | sudo -S bash -c `'$command`'"

$commandBLock=[scriptblock]::Create($runCommand)

foreach ($baseName in $vmNameArray) {
    $vm_name = $baseName + $suffix
    $vm_name = $vm_name | % { $_ -replace ".vhd", "" }

    write-host "Executing remote command on machine $vm_name"

    [System.Management.Automation.Runspaces.PSSession]$session = create_psrp_session $vm_name $destRG $destSA $cred $o
    if ($? -eq $true -and $session -ne $null) {
        invoke-command -session $session -ScriptBlock $commandBLock -ArgumentList $runCommand
        Exit-PSSession

    } else {
        Write-Host "    FAILED to establish PSRP connection to machine $vm_name." -ForegroundColor Red
    }
}
