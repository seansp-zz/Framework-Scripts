#
#  Copies VHDs that have booted as expected to the test location where they will be prepped
#  for Azure automation
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$false)] [string] $sourceSA="smokeworkingstorageacct",
    [Parameter(Mandatory=$false)] [string] $sourceRG="smoke_working_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceContainer="vhds_under_test",

    [Parameter(Mandatory=$false)] [string[]] $requestedNames,
    [Parameter(Mandatory=$false)] [string[]] $generalizeAll,

    [Parameter(Mandatory=$false)] [string] $suffix="-Runonce-Primed.vhd"
)

. "C:\Framework-Scripts\common_functions.ps1"
. "C:\Framework-Scripts\secrets.ps1"

[System.Collections.ArrayList]$vmNames_array
$vmNameArray = {$vmNames_array}.Invoke()
$vmNameArray.Clear()
$vmNameArray = $requestedNames.Split(',')

$vmName = $vmNameArray[0]
if ($generalizeAll -eq $false -and ($vmNameArray.Count -eq 1  -and $vmNameArray[0] -eq "Unset")) {
    Write-Host "Must specify either a list of VMs in RequestedNames, or use MakeDronesFromAll.  Unable to process this request."
    Stop-Transcript
    exit 1
} elseif ($generalizeAll -eq $true) {
    $requestedNames = ""
    $runningVMs = Get-AzureRmVm -ResourceGroupName $sourceRG
    foreach ($vm in $runningVMs) {
        $vm_name=$vm.Name
        $requestedNames = $requestedNames + $vm_name + ","
    }
    $requestedNames = $requestedNames -replace ".$"
}

Write-Host "Replacing cloud-init..."
C:\Framework-Scripts\run_command_on_machines_in_group.ps1 -requestedNames $requestedNames -destSA $sourceSA -destRG $sourceRG `
                                                          -suffix $suffix -command "echo $TEST_USER_ACCOUNT_PASS | sudo -S bash -c `"/bin/mv /usr/bin/cloud-init.DO_NOT_RUN_THIS_POS /usr/bin/cloud-init`""

Write-Host "Deprovisioning..."
C:\Framework-Scripts\run_command_on_machines_in_group.ps1 -requestedNames $requestedNames -destSA $sourceSA -destRG $sourceRG `
                                                          -suffix $suffix -command "echo $TEST_USER_ACCOUNT_PASS | sudo -S bash -c `"/sbin/waagent -deprovision -force`""
 if ($? -eq $false) {
    Write-Host "FAILED to deprovision machines" -ForegroundColor Red
    exit 1
}

Write-Host "And stopping..."
C:\Framework-Scripts\run_command_on_machines_in_group.ps1 -requestedNames $requestedNames -destSA $sourceSA -destRG $sourceRG `
                                                          -suffix $suffix -command "echo $TEST_USER_ACCOUNT_PASS | sudo -S bash -c shutdown"
if ($? -eq $false) {
    Write-Host "FAILED to stop machines" -ForegroundColor Red
    exit 1
}