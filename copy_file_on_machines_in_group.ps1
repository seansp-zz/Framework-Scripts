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

write-host "Creating VMs for $vmNameArray "

#
#  Session stuff
#
$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$cred = make_cred

login_azure $DestRG $DestSA
$error = $false
$suffix = $suffix.Replace(".vhd","")
Write-Host "New suffix is $suffix"

foreach ($baseName in $vmNameArray) {
    
    $vm_name = $baseName + $suffix
    $password="$TEST_USER_ACCOUNT_PASS"
    write-host "VM Name is $vm_name"

    $scriptCommand= { param($script) copy-item $script /root/runonce.d } 

    $runCommand = "echo $password | sudo -S bash -c `'cp /root/Framework-Scripts/$scriptName /root/runonce.d`'"

    $commandBLock=[scriptblock]::Create($runCommand)

    [System.Management.Automation.Runspaces.PSSession]$session = create_psrp_session $vm_name $destRG $destSA $cred $o
    if ($? -eq $true -and $session -ne $null) {
        invoke-command -session $session -ScriptBlock $commandBLock -ArgumentList $runCommand
        Exit-PSSession

    } else {
        Write-Host "    FAILED to establish PSRP connection to machine $vm_name." -ForegroundColor Red
    }
}