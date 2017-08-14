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

    [Parameter(Mandatory=$false)] [string] $destSA="smokework",
    [Parameter(Mandatory=$false)] [string] $destRB="smoke_working_resource_group",
    [Parameter(Mandatory=$false)] [string] $destContainer="vhds-under-test",

    [Parameter(Mandatory=$false)] [string[]] $Flavors="",
    [Parameter(Mandatory=$false)] [string[]] $requestedNames = "",
    
    [Parameter(Mandatory=$false)] [string] $currentSuffix="-booted-and-verified.vhd",
    [Parameter(Mandatory=$false)] [string] $newSuffix="-variant.vhd",

    [Parameter(Mandatory=$false)] [string] $network="smokeVNet",
    [Parameter(Mandatory=$false)] [string] $subnet="SmokeSubnet-1",
    [Parameter(Mandatory=$false)] [string] $NSG="SmokeNSG",
    [Parameter(Mandatory=$false)] [string] $location="westus",

    [Parameter(Mandatory=$false)] [string] $srcSuffix="-Smoke-1",
    [Parameter(Mandatory=$false)] [string] $destSuffix="-Variant.vhd"
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
if ($makeDronesFromAll -ne $true -and ($vmNameArray.Count -eq 1  -and $vmName -eq "")) {
    Write-Host "Must specify either a list of VMs in RequestedNames, or use MakeDronesFromAll.  Unable to process this request."
    Stop-Transcript
    exit 1
}

if ($flavorsArray.Count -eq 1 -and $flavorsArray[0] -eq "" ) {
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
    param ($vmName,
    $sourceRG,
    $sourceSA,
    $sourceContainer,
    $destRG,
    $destSA,
    $destContainer,
    $location,
    $currentSuffix,
    $newSuffix,
    $NSG,
    $network,
    $subnet,
    $vmFlavor
    )
    Start-Transcript C:\temp\transcripts\$vmName-$vmFlacor-Variant.log -Force

    . "C:\Framework-Scripts\common_functions.ps1"
    . "C:\Framework-Scripts\secrets.ps1"

    write-host "Checkpoint 3" -ForegroundColor Cyan

    login_azure $destRG $destSA $location

    if ($startMachines -eq $true) {}
    Write-Host "Deallocating machine $vmName, if it is up"
    $runningMachines = Get-AzureRmVm -ResourceGroupName $destRG -status | Where-Object -Property Name -Like "$vmName*"
    deallocate_machines_in_group $runningMachines $destRG $destSA $location

    $regionSuffix = $VMFlavor + ("-" + $location) -replace " ","-"
    $regionSuffix = $regionSuffix -replace "_","-"

    $newVMName = $vmName
    # $newVMName = $newVMName | % { $_ -replace ".vhd", "" }

    Write-Host "Attempting to create virtual machine $newVMName.  This may take some time." -ForegroundColor Green
    C:\Framework-Scripts\launch_single_azure_vm.ps1 -vmName $newVMName -resourceGroup $destRG -storageAccount $destSA -containerName $destContainer `
                                                -network $network -subnet $subnet -NSG $NSG -Location $location -VMFlavor $vmFlavor -suffix $newSuffix 
    if ($? -ne $true) {
        Write-Host "Error creating VM $newVMName.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    #
    #  Just because it's up doesn't mean it's accepting connections yet.  Wait 2 minutes, then try to connect.  I tried 1 minute,
    #  but kept getting timeouts on the Ubuntu machines.
    $regionSuffix = ("-" + $location) -replace " ","-"
    $imageName = $newVMName + "-" + $vmFlavor + $regionSuffix.ToLower()
    $imageName = $imageName -replace "_","-"
    $imageName = $imageName + $newSuffix
    $imageName = $imageName -replace ".vhd", ""

    $pipName = $imageName
    $ip=(Get-AzureRmPublicIpAddress -ResourceGroupName $destRG -Name $pipName).IpAddress
    if ($? -ne $true) {
        Write-Host "Error getting IP address for VM $newVMName.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }
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

        Start-Job -Name $vmJobName -ScriptBlock $scriptBlock -ArgumentList $blobName, $sourceRG, $sourceSA, $sourceContainer,`
                                                                           $destRG, $destSA, $destContainer, $location,`
                                                                           $currentSuffix, $newSuffix, $NSG, $network, `
                                                                           $subnet, $oneFlavor
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
            # $jobFailed = $true
            $vmsFinished = $vmsFinished + 1
            $Failed = $true
        } elseif ($jobState -eq "Blocked") {
            write-host "**********************  HOST MACHINE $vmJobName IS BLOCKED WAITING INPUT.  COMMAND WILL NEVER COMPLETE!!" -ForegroundColor Red
            # $jobBlocked = $true
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