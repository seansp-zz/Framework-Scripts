#
#  Copies VHDs that have booted as expected to the test location where they will be prepped
#  for Azure automation
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$true) ] [string] $Command="logout",

    [Parameter(Mandatory=$false)] [string] $sourceSA="smokeworkingstorageacct",
    [Parameter(Mandatory=$false)] [string] $sourceRG="smoke_working_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceContainer="vhds-under-test"
)

. "C:\Framework-Scripts\common_functions.ps1"
. ./secrets.ps1

#
#  Session stuff
#
$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$cred = make_cred

login_azure $sourceRG $sourceSA

$blobs = Get-AzureStorageBlob -Container $sourceContainer

Write-Host "Executing command on all running machines in resource group $sourceRG..."  -ForegroundColor green
$runningVMs = Get-AzureRmVm -ResourceGroupName $sourceRG
foreach ($blob in $blobs) {
    $blobName = $blob.Name


    $vm_name=$vm.Name

    if (vm.Name in $blobs.Name) {
        Write-Host "VM for VHD $vm.Name found and is running.  "
    } else {
        Write-Host "VM for VHD

    $password="$TEST_USER_ACCOUNT_PASS"

    $failed = $false
    [System.Management.Automation.Runspaces.PSSession]$session = create_psrp_session $vm_name $sourceRG $sourceSA $cred $o
    if ($? -eq $true -and $session -ne $null) {
        Write-Host "    PSRP Connection established; executing remote command" -ForegroundColor Green
        invoke-command -session $session -ScriptBlock {$Command}
        if ($? -eq $false) {
            $Failed = $true
        }
    } else {
        Write-Host "    UNABLE TO PSRP TO MACHINE!  COULD NOT DEPROVISION" -ForegroundColor Red
    }
    
    if ($session -ne $null) {
        Remove-PSSession $session
    }

    if ($Failed -eq $true) {
        Write-Host "Remote command execution failed!" -ForegroundColor Red
        exit 1
    } else {
        exit 0
    }
}