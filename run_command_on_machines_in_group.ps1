param (
    [Parameter(Mandatory=$false)] [string[]] $requestedNames,
    
    [Parameter(Mandatory=$false)] [string] $destSA="smokesourcestorageacct",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_source_resource_group",

    [Parameter(Mandatory=$false)] [string] $suffix="-Runonce-Primed.vhd",

    [Parameter(Mandatory=$false)] [string] $command="unset",
    [Parameter(Mandatory=$false)] [string] $asRoot="false"
)
    
    
. c:\Framework-Scripts\common_functions.ps1
. c:\Framework-Scripts\secrets.ps1

[System.Collections.ArrayList]$vmNames_array
$vmNameArray = {$vmNames_array}.Invoke()
$vmNameArray.Clear()
$vmNameArray = $requestedNames.Split(',')

#
#  Session stuff
#
$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$cred = make_cred

login_azure $DestRG $DestSA
$error = $false
$suffix = $suffix.Replace(".vhd","")

$password="$TEST_USER_ACCOUNT_PASS"

$scriptCommand= { param($cmd) $cmd } 

if ($asRoot -ne $false) {
    $runCommand = "echo $password | sudo -S bash -c `'$command`'"
} else {
    $runCommand = $command
}

$commandBLock=[scriptblock]::Create($runCommand)

foreach ($baseName in $vmNameArray) {
    $vm_name = $baseName + $suffix

    write-host "Executing remote command on machine $vm_name"

    [System.Management.Automation.Runspaces.PSSession]$session = create_psrp_session $vm_name $destRG $destSA $cred $o
    if ($? -eq $true -and $session -ne $null) {
        invoke-command -session $session -ScriptBlock $commandBLock -ArgumentList $command
        Exit-PSSession

    } else {
        Write-Host "    FAILED to establish PSRP connection to machine $vm_name." -ForegroundColor Red
    }
}
