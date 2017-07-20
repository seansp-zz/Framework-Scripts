﻿#
#  Copies VHDs that have booted as expected to the test location where they will be prepped
#  for Azure automation
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$false)] [string] $sourceSA="smokeworkingstorageacct",
    [Parameter(Mandatory=$false)] [string] $sourceRG="smoke_working_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceContainer="vhds_under_test"
)

. "C:\Framework-Scripts\common_functions.ps1"

#
#  Session stuff
#
$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$cred = make_cred

login_azure $sourceRG $sourceSA

Write-Host "Generalizing the running machines..."  -ForegroundColor green
$runningVMs = Get-AzureRmVm -ResourceGroupName $sourceRG

foreach ($vm in $runningVMs) {
    $vm_name=$vm.Name

    $session = create_psrp_session $vm_name $sourceRG $cred $o
    if ($? -eq $true -and $session -ne $null) {
        Write-Host "    PSRP Connection established; deprovisioning and shutting down" -ForegroundColor Green
        invoke-command -session $session -ScriptBlock {sudo waagent --deprovision -force; sudo shutdown}
    } else {
        Write-Host "    UNABLE TO PSRP TO MACHINE!  COULD NOT DEPROVISION" -ForegroundColor Red
    }

    if ($session -ne $null) {
        Remove-PSSession $session
    }
}