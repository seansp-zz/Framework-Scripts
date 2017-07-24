#
#  Copies VHDs that have booted as expected to the test location where they will be prepped
#  for Azure automation
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$true) ] [string] $Command="logout",
    [Parameter(Mandatory=$true) ] [string] $StartMachines="False",

    [Parameter(Mandatory=$false)] [string] $sourceSA="smokeworkingstorageacct",
    [Parameter(Mandatory=$false)] [string] $sourceRG="smoke_working_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceContainer="vhds-under-test"
)

. "C:\Framework-Scripts\common_functions.ps1"
. "C:\Framework-Scripts\secrets.ps1"

#
#  Session stuff
#
$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$cred = make_cred

login_azure $sourceRG $sourceSA

$blobs = Get-AzureStorageBlob -Container $sourceContainer

Write-Host "Executing command on all running machines in resource group $sourceRG..."  -ForegroundColor green
$runningVMs = Get-AzureRmVm -ResourceGroupName $sourceRG
$failed = $false

foreach ($blob in $blobs) {
    $blobName = ($blob.Name).replace(".vhd","")

    foreach ($blob in $blobs) {
        $blobName = ($blob.Name).Replace(".vhd","")
        if ($runningVMs.Name -contains $blobName) {
            write-host "VM $blobName is running"
        } else {
            Write-Host "VM $blobName is not running."

            if ($StartMachines -ne $false) {
                Write-Host "Starting VM for VHD $blobName..."
                .\launch_single_azure_vm.ps1 -vmName RHEL72-BORG -resourceGroup $sourceRG -storageAccount $sourceSA -containerName $sourceContainer -network SmokeVNet -subnet SmokeSubnet-1
            } else {
                Write-Host "StartMachine was not set.  VM $blobName will not be started or used."
                continue
            }

            $password="$TEST_USER_ACCOUNT_PASS"

            [System.Management.Automation.Runspaces.PSSession]$session = create_psrp_session $vm_name $sourceRG $sourceSA $cred $o
            if ($? -eq $true -and $session -ne $null) {
                Write-Host "    PSRP Connection established; executing remote command" -ForegroundColor Green
                invoke-command -session $session -ScriptBlock {$Command}
                if ($? -eq $false) {
                    $Failed = $true
                }
            } else {
                Write-Host "    UNABLE TO PSRP TO MACHINE!  COULD NOT DEPROVISION" -ForegroundColor Red
                continue
            }
    
            if ($session -ne $null) {
                Remove-PSSession $session
            }
        }
    }
}

if ($Failed -eq $true) {
    Write-Host "Remote command execution failed!" -ForegroundColor Red
    exit 1
} else {
    exit 0
}
