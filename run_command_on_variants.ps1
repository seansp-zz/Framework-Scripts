#
#  Create a set of macines based on variants.  Variants are different machine types (standard_d2_v2), so a set of variant
#  machines all share the same base VHD image, but are (potentially) using different hardware configurations.#
#  Copies VHDs that have booted as expected to the test location where they will be prepped
#  for Azure automation
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$false)] [string] $sourceSA="smokework",
    [Parameter(Mandatory=$false)] [string] $sourceRG="smoke_working_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceContainer="vhds-under-test",

    [Parameter(Mandatory=$false)] [string[]] $Flavors="Unset",
    [Parameter(Mandatory=$false)] [string[]] $requestedNames = "Unset",
    [Parameter(Mandatory=$false)] [string] $makeDronesFromAll="False"
    
    [Parameter(Mandatory=$false)] [string] $suffix="-booted-and-verified.vhd",

    [Parameter(Mandatory=$false)] [string] $command="unset",
    [Parameter(Mandatory=$false)] [string] $asRoot="False",
    [Parameter(Mandatory=$true) ] [string] $StartMachines="True",

    [Parameter(Mandatory=$false)] [string] $network="smokeVNet",
    [Parameter(Mandatory=$false)] [string] $subnet="SmokeSubnet-1",
    [Parameter(Mandatory=$false)] [string] $NSG="SmokeNSG",
    [Parameter(Mandatory=$false)] [string] $location="westus"
)

System.Collections.ArrayList]$vmNames_array
$vmNameArray = {$vmNames_array}.Invoke()
$vmNameArray.Clear()
if ($requestedNames -like "*,*") {
    $vmNameArray = $requestedNames.Split(',')
} else {
    $vmNameArray += $requestedNames
}

System.Collections.ArrayList]$all_vmNames_array
$all_vmNameArray = {$vmNames_array}.Invoke()
$all_vmNameArray.Clear()

System.Collections.ArrayList]$flavors_array
$flavorsArray = {$flavors_array}.Invoke()
$flavorsArray.Clear()
if ($Flavors -like "*,*") {
    $flavorsArray = $Flavors.Split(',')
} else {
    $flavorsArray += $Flavors
}

$vmName = $vmNameArray[0]
if ($makeDronesFromAll -ne $true -and ($vmNameArray.Count -eq 1  -and $vmNameArray[0] -eq "Unset")) {
    Write-Host "Must specify either a list of VMs in RequestedNames, or use MakeDronesFromAll.  Unable to process this request."
    Stop-Transcript
    exit 1
}

if ($flavorsArray.Count -eq 1 -and $flavorsArray[0] -eq "Unset" )
Write-Host "Must specify at least one VM Flavor to build..  Unable to process this request."
Stop-Transcript
exit 1
}

. "C:\Framework-Scripts\common_functions.ps1"
. "C:\Framework-Scripts\secrets.ps1"

login_azure $sourceRG $sourceSA $location

$blobs = Get-AzureStorageBlob -Container $sourceContainer

# Write-Host "Executing command on all running machines in resource group $sourceRG..."  -ForegroundColor green

$failed = $false

$comandScript = {
    param (
        $blobName,
        $startMachines,
        $sourceRG,
        $sourceSA,
        $sourceContainer,
        $network,
        $subnet,
        $NSG,
        $location,
        $flavor)

    Start-Transcript C:\temp\transcripts\run_command_on_container_$blobName.log -Force
    . C:\Framework-Scripts\common_functions.ps1
    . C:\Framework-Scripts\secrets.ps1

    login_azure $sourceRG $sourceSA $location
     
    $runningVMs = Get-AzureRmVm -ResourceGroupName $sourceRG
    if ($runningVMs.Name -contains $blobName) {
        write-host "VM $blobName is running"
    } else {
        Write-Host "VM $blobName is not running."

        if ($StartMachines -ne $false) {
            Write-Host "Starting VM for VHD $blobName..."
            .\launch_single_azure_vm.ps1 -vmName $blobName -resourceGroup $sourceRG -storageAccount $sourceSA `
                                         -containerName $sourceContainer -network $network -subnet $subnet -NSG $NSG `
                                         -Location $location -VMFlavor $flavor
        } else {
            Write-Host "StartMachine was not set.  VM $blobName will not be started or used."
            $failed = $true
        }
    }

    Stop-Transcript

    if ($failed -eq $true) {
        exit 1
    }

    exit 0
}

$scriptBlock = [scriptblock]::Create($comandScript)

[System.Collections.ArrayList]$copyblobs_array
$copyblobs = {$copyblobs_array}.Invoke()
$copyblobs.clear()

foreach ($blob in $blobs) {
    $blobName = ($blob.Name).replace(".vhd","")
    $copyblobs += $blobName

    foreach ($oneFlavor in $Flavors) {
        $vmJobName = "start_" + $oneFlavor + $blobName

        Start-Job -Name $vmJobName -ScriptBlock $scriptBlock -ArgumentList $blobName, $startMachines, $sourceRG, $sourceSA, $sourceContainer, `
                                                                           $network, $subnet, $NSG, $location, $oneFlavor
    }
}

$allDone = $false
while ($allDone -eq $false) {
    $allDone = $true
    $numNeeded = $vmNameArray.Count
    $vmsFinished = 0

    foreach ($blob in $blobs) {
        $blobName = ($blob.Name).replace(".vhd","")

        $vmJobName = "start_" + $blobName
        $job = Get-Job -Name $vmJobName
        $jobState = $job.State

        # write-host "    Job $job_name is in state $jobState" -ForegroundColor Yellow
        if ($jobState -eq "Running") {
            $allDone = $false
        } elseif ($jobState -eq "Failed") {
            write-host "**********************  JOB ON HOST MACHINE $vmJobName HAS FAILED TO START." -ForegroundColor Red
            $jobFailed = $true
            $vmsFinished = $vmsFinished + 1
            $Failed = $true
        } elseif ($jobState -eq "Blocked") {
            write-host "**********************  HOST MACHINE $vmJobName IS BLOCKED WAITING INPUT.  COMMAND WILL NEVER COMPLETE!!" -ForegroundColor Red
            $jobBlocked = $true
            $vmsFinished = $vmsFinished + 1
            $Failed = $true
        } else {
            $vmsFinished = $vmsFinished + 1
        }
    }

    if ($allDone -eq $false) {
        Start-Sleep -Seconds 10
    } elseif ($vmsFinished -eq $numNeeded) {
        break
    }
}

if ($Failed -eq $true) {
    Write-Host "Remote command execution failed because we could not !" -ForegroundColor Red
    exit 1
} 

C:\Framework-Scripts\run_command_on_machines_in_group.ps1 -requestedNames $copyBlobs -destSA $sourceSA -destRG $sourceRG -suffix $suffix -command $command -asRoot $asRoot
