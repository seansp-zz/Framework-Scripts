﻿#
#  Copies user VHDs it finds for VMs in the reference resource group into the 'clean-vhds' 
#  storage container.  The target blobs will have the name of the VM, as a .vhd
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$false)] [string] $sourceSA="smokesourcestorageacct",
    [Parameter(Mandatory=$false)] [string] $sourceRG="smoke_source_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceContainer="clean-vhds",
    [Parameter(Mandatory=$false)] [string] $sourceExtension="Smoke-1.vhd",


    [Parameter(Mandatory=$false)] [string] $destSA="smokesourcestorageacct",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_source_resource_group",
    [Parameter(Mandatory=$false)] [string] $destContainer="safe-templates",
    [Parameter(Mandatory=$false)] [string] $destExtension="Smoke-1.vhd",

    [Parameter(Mandatory=$false)] [string] $location="westus",

    [Parameter(Mandatory=$false)] [string[]] $vmNamesIn,
    
    [Parameter(Mandatory=$false)] [switch] $makeDronesFromAll,
    [Parameter(Mandatory=$false)] [switch] $clearDestContainer,
    [Parameter(Mandatory=$false)] [switch] $overwriteVHDs
)

. "C:\Framework-Scripts\common_functions.ps1"

$copyblobs_array=@()
$copyblobs = {$copyblobs_array}.Invoke()

$vmNames_array=@()
$vmNames = {$vmNames_array}.Invoke()
foreach($vmName in $vmNamesIn) {
    $vmNames.Add($vmName)
}

login_azure $destRG $destSA

Write-Host "Stopping all running machines..."  -ForegroundColor green
if ($makeDronesFromAll -eq $true) {
    foreach ($vmName in $vmNames) {
        Get-AzureRmVm -ResourceGroupName $sourceRG -status | Where-Object -Property Name -Like "$vmName*" | where-object -Property PowerState -eq -value "VM Running" | Stop-AzureRmVM -Force
        Get-AzureRmVm -ResourceGroupName $destRG -status | Where-Object -Property Name -Like "$vmName*" | where-object -Property PowerState -eq -value "VM Running" | Stop-AzureRmVM -Force
    } 
} else {
    Get-AzureRmVm -ResourceGroupName $sourceRG -status | where-object -Property PowerState -eq -value "VM Running" | Stop-AzureRmVM -Force
    Get-AzureRmVm -ResourceGroupName $destRG -status | where-object -Property PowerState -eq -value "VM Running" | Stop-AzureRmVM -Force
}

Write-Host "Launching jobs to copy individual machines..." -ForegroundColor Yellow

$destKey=Get-AzureRmStorageAccountKey -ResourceGroupName $destRG -Name $destSA
$destContext=New-AzureStorageContext -StorageAccountName $destSA -StorageAccountKey $destKey[0].Value

$sourceKey=Get-AzureRmStorageAccountKey -ResourceGroupName $sourceRG -Name $sourceSA
$sourceContext=New-AzureStorageContext -StorageAccountName $sourceSA -StorageAccountKey $sourceKey[0].Value

Set-AzureRmCurrentStorageAccount –ResourceGroupName $sourceRG –StorageAccountName $sourceSA
if ($makeDronesFromAll -eq $true) {
    $blobs=get-AzureStorageBlob -Container $sourceContainer -Blob "*$sourceExtension"
    $blobCount = $blobs.Count
    Write-Host "Making drones of all VHDs in container $sourceContainer.  There will be $blobCount VHDs:"-ForegroundColor Magenta
    $vmNames.Clear()
    foreach ($blob in $blobs) {
        $blobName = $blob.Name
        write-host "                       $blobName" -ForegroundColor Magenta
        $vmNames.Add($blobName)
    }
} else {
    foreach ($vmName in $vmNames) {
        $theName = $vmName + $sourceExtension
        $singleBlob=get-AzureStorageBlob -Container $sourceContainer -name $theName
        if ($? -eq $true) {
            $blobs += $singleBlob
        } else {
            Write-Host " ***** ??? Could not find source blob $theName in container $sourceContainer.  This request is skipped" -ForegroundColor Red
        }
    }
}

Set-AzureRmCurrentStorageAccount –ResourceGroupName $destRG –StorageAccountName $destSA
if ($clearDestContainer -eq $true) {
    Write-Host "Clearing destingation container of all jobs with extension $destExtension"
    get-AzureStorageBlob -Container $destContainer -Blob "*$destExtension" | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $destContainer }
}

foreach ($vmName in $vmNames) {
    $sourceName=$vmName
    $targetName = $sourceName | % { $_ -replace "$sourceExtension", "$destExtension" }

    Write-Host "Initiating job to copy VHD $targetName from cache to working directory..." -ForegroundColor Yellow
    if ($overwriteVHDs -eq $true) {
        $blob = Start-AzureStorageBlobCopy -SrcBlob $sourceName -DestContainer $destContainer -SrcContainer $sourceContainer -DestBlob $targetName -Context $sourceContext -DestContext $destContext -Force
    } else {
        $blob = Start-AzureStorageBlobCopy -SrcBlob $sourceName -DestContainer $destContainer -SrcContainer $sourceContainer -DestBlob $targetName -Context $sourceContext -DestContext $destContext
    }

    if ($? -eq $true) {
        $copyblobs.Add($targetName)
    } else {
        Write-Host "Job to copy VHD $targetName failed to start.  Cannot continue"
        exit 1
    }
}

sleep 5
Write-Host "All jobs have been launched.  Initial check is:" -ForegroundColor Yellow

$stillCopying = $true
while ($stillCopying -eq $true) {
    $stillCopying = $false

    write-host ""
    write-host "Checking blob copy status..." -ForegroundColor yellow

    foreach ($vmName in $vmNames) {
        $sourceName=$vmName
        $targetName = $sourceName | % { $_ -replace "$sourceExtension", "$destExtension" }

        $copyStatus = Get-AzureStorageBlobCopyState -Blob $targetName -Container $destContainer -ErrorAction SilentlyContinue
        $status = $copyStatus.Status
        if ($? -eq $false) {
            Write-Host "        Could not get copy state for job $targetName.  Job may not have started." -ForegroundColor Yellow
            break
        } elseif ($status -eq "Pending") {
            $bytesCopied = $copyStatus.BytesCopied
            $bytesTotal = $copyStatus.TotalBytes
            if ($bytesTotal -le 0) {
                Write-Host "        Job $targetName not started copying yet." -ForegroundColor green
            } else {
                $pctComplete = ($bytesCopied / $bytesTotal) * 100
                Write-Host "        Job $targetName has copied $bytesCopied of $bytesTotal bytes ($pctComplete %)." -ForegroundColor green
            }
            $stillCopying = $true
        } else {
            if ($status -eq "Success") {
                Write-Host "   **** Job $targetName has completed successfully." -ForegroundColor Green                    
            } else {
                Write-Host "   **** Job $targetName has failed with state $Status." -ForegroundColor Red
            }
        }
    }

    if ($stillCopying -eq $true) {
        sleep(10)
    } else {
        Write-Host "All copy jobs have completed.  Rock on." -ForegroundColor Green
    }
}

exit 0
