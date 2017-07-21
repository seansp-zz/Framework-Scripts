#
#  Copies VHDs that have booted as expected to the test location where they will be prepped
#  for Azure automation
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$false)] [string] $sourceSA="smokeworkingstorageacct",
    [Parameter(Mandatory=$false)] [string] $sourceRG="smoke_working_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceContainer="vhds-under-test",

    [Parameter(Mandatory=$false)] [string] $destSA="smokebvtstorageaccount",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_bvts_resource_group",

    [Parameter(Mandatory=$false)] [string] $location="westus",

    [Parameter(Mandatory=$false)] [string] $templateFile="bvt_template.xml",
    [Parameter(Mandatory=$false)] [string] $removeTag="-BORG",
    [Parameter(Mandatory=$false)] [string] $OverwriteVHDs="False",

    [Parameter(Mandatory=$true)] [string] $distro="Smoke-BVT",
    [Parameter(Mandatory=$true)] [string] $testCycle="BVT"
)

#
#  This is a required location
$destContainer="vhds"

$copyblobs_array=@()
$copyblobs = {$copyblobs_array}.Invoke()

if ($OverwriteVHDs -ne "False") {
    $overwriteVHDs = $true
} else {
    $overwriteVHDs = $false
}

write-host "Overwrite flag is $overwriteVHDs"

Write-Host "Importing the context...." -ForegroundColor Green
Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx' 

Write-Host "Selecting the Azure subscription..." -ForegroundColor Green
Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4" 
Set-AzureRmCurrentStorageAccount –ResourceGroupName $destRG –StorageAccountName $destSA 

Write-Host "Stopping all running machines..."  -ForegroundColor green
Get-AzureRmVm -ResourceGroupName $sourceRG -status |  where-object -Property PowerState -eq -value "VM running" | Stop-AzureRmVM -Force

Write-Host "Copying the test VMs packages to BVT resource group"
$destKey=Get-AzureRmStorageAccountKey -ResourceGroupName $destRG -Name $destSA
$destContext=New-AzureStorageContext -StorageAccountName $destSA -StorageAccountKey $destKey[0].Value

$sourceKey=Get-AzureRmStorageAccountKey -ResourceGroupName $sourceRG -Name $sourceSA
$sourceContext=New-AzureStorageContext -StorageAccountName $sourceSA -StorageAccountKey $sourceKey[0].Value

$blobFilter = '*.vhd'
if ($removeTag -ne "") {
    $blobFilter = '*' + $removeTag
}
Write-Host "Blob filter is $blobFilter"

Set-AzureRmCurrentStorageAccount –ResourceGroupName $destRG –StorageAccountName $destSA 
$existingBlobs=get-AzureStorageBlob -Container $destContainer 

Set-AzureRmCurrentStorageAccount –ResourceGroupName $sourceRG –StorageAccountName $sourceSA 
$blobs=get-AzureStorageBlob -Container $sourceContainer -Blob $blobFilter

Set-AzureRmCurrentStorageAccount –ResourceGroupName $destRG –StorageAccountName $destSA

foreach ($oneblob in $blobs) {
    $sourceName=$oneblob.Name

    $targetName = $sourceName
    if ($removeTag -ne "") {
        $targetName = $sourceName | % { $_ -replace $removeTag, ".vhd" }
    }
    $targetName = $targetName | % { $_ -replace ".vhd", "-Booted-and-Verified.vhd" }
    
    $blobIsInDest = $false
    if ($existingBlobs.Name -contains $targetName) {
        $blobIsInDest = $true
    }

    $start_copy = $true
    if (($blobIsInDest -eq $true) -and ($overwriteVHDs -eq $true)) {
        Write-Host "There is an existing blob in the destination and the overwrite flag has been set.  The existing blob will be deleted."
        Remove-AzureStorageBlob -Blob $targetName -Container $destContainer -Force
    } elseif ($blobIsInDest -eq $false) {
        Write-Host "This is a new blob."
    } else {
        Write-Host "There was an existing blob named $targetName, and the overwrite flag was not set.  Blob will not be copied."
        $start_copy = $false
    }    
    
    if ($start_copy -eq $true) {
        Write-Host "Initiating job to copy VHD $targetName from LKG to BVT directory..." -ForegroundColor Yellow
        $blob = Start-AzureStorageBlobCopy -SrcBlob $sourceName -DestContainer $destContainer -SrcContainer $sourceContainer -DestBlob $targetName -Context $sourceContext -DestContext $destContext
        if ($? -eq $true) {
            $copyblobs.Add($targetName)
        } else {
            Write-Host "Job to copy VHD $targetName failed to start.  Cannot continue"
            exit 1
        }
    }
}

if ($copyblobs.Count -gt 0) {
    sleep 5
    Write-Host "All jobs have been launched.  Initial check is:" -ForegroundColor Yellow

    Set-AzureRmCurrentStorageAccount –ResourceGroupName $destRG –StorageAccountName $destSA  
    $stillCopying = $true
    while ($stillCopying -eq $true) {
        $stillCopying = $false
        $reset_copyblobs = $true

        Write-Host ""
        Write-Host "Checking copy status..."
        while ($reset_copyblobs -eq $true) {
            $reset_copyblobs = $false
            foreach ($blob in $copyblobs) {
                $status = Get-AzureStorageBlobCopyState -Blob $blob -Container $destContainer -ErrorAction SilentlyContinue
                if ($? -eq $false) {
                    Write-Host "        Could not get copy state for job $blob.  Job may not have started." -ForegroundColor Yellow
                    $copyblobs.Remove($blob)
                    $reset_copyblobs = $true
                    break
                } elseif ($status.Status -eq "Pending") {
                    $bytesCopied = $status.BytesCopied
                    $bytesTotal = $status.TotalBytes
                    $pctComplete = ($bytesCopied / $bytesTotal) * 100
                    Write-Host "        Job $blob has copied $bytesCopied of $bytesTotal bytes ($pctComplete %)." -ForegroundColor green
                    $stillCopying = $true
                } else {
                    $exitStatus = $status.Status
                    if ($exitStatus -eq "Completed") {
                        Write-Host "   **** Job $blob has failed with state $exitStatus." -ForegroundColor Red
                    } else {
                        Write-Host "   **** Job $blob has completed successfully." -ForegroundColor Green
                    }
                    $copyblobs.Remove($blob)
                    $reset_copyblobs = $true
                    break
                }
            }
        }

        if ($stillCopying -eq $true) {
            Write-Host ""
            sleep(10)
        } else {
            Write-Host ""
            Write-Host "All copy jobs have completed.  Rock on." -ForegroundColor green
        }
    }
}

$uri_front="https://"
$uri_middle=".blob.core.windows.net/vhds/"

# Set-AzureRmCurrentStorageAccount –ResourceGroupName $destRG –StorageAccountName $destSA 
# $blobs=get-AzureStorageBlob -Container $destContainer
cd C:\azure-linux-automation
$launched_machines = 0

Set-AzureRmCurrentStorageAccount –ResourceGroupName $sourceRG –StorageAccountName $sourceSA 
$blobs=get-AzureStorageBlob -Container $sourceContainer -Blob $blobFilter

foreach ($oneblob in $blobs) {
    $sourceName=$oneblob.Name
    $configFileName="bvt_exec_" + $sourceName + ".xml"
    $jobName=$sourceName + "_BVT_Runner"

    $targetName = $sourceName
    if ($removeTag -ne "") {
        $targetName = $sourceName | % { $_ -replace $removeTag, ".vhd" }
    }
    $targetName = $targetName | % { $_ -replace ".vhd", "-Booted-and-Verified.vhd" }

    $uri=$uri_front + $destSA + $uri_middle + $targetName
    (Get-Content .\$templateFile).Replace("SMOKE_MACHINE_NAME_HERE",$targetName) | out-file $configFileName

    #
    # Launch the automation
    Start-Job -Name $jobName -ScriptBlock { C:\Framework-Scripts\run_single_bvt.ps1 -sourceName $args[0] -configFileName $args[1] -distro $args[2] -testCycle $args[3]  } -ArgumentList @($sourceName),@($configFileName),@($distro),@($testCycle)
    if ($? -ne $true) {
        Write-Host "Error launching job for source $targetName.  BVT will not be run." -ForegroundColor Red
    } else {
        $launched_machines++
        $launchTime=date
        Write-Host "Machine $targetName launched as BVT $launched_machines at $launchTime" -ForegroundColor Green
    }
}

#
#  Wait for completion...
$sleep_count=0
while ($completed_machines -lt $launched_machines) {

    $completed_machines = 0
    $failed_machines = 0
    $running_machines = 0
    $other_machines = 0

    foreach ($oneblob in $blobs) {
        $sourceName=$oneblob.Name
        $jobName=$sourceName + "_BVT_Runner"

        $logFileName = $sourceName + "_transcript.log"

        $jobStatus=get-job -Name $jobName -ErrorAction SilentlyContinue
        if ($? -eq $true) {
            $jobState = $jobStatus.State
        }

        $logThisOne=$false
        if ($sleep_count % 6 -eq 0) {
            $updateTime=date
            write-host "Update as of $updateTime"
            $logThisOne=$true
        }
        if ($jobState -eq "Complete")
        {
            $completed_machines++
            $failed_machines++
            Write-Host "----> BVT job $jobName exited with FAILED state!" -ForegroundColor red
        }
        elseif ($jobState -eq "Completed")
        {
            $completed_machines++
            Write-Host "***** BVT job $jobName completed successfully." -ForegroundColor green
        }
        elseif ($jobState -eq "Running")
        {
            $running_machines++
            if ($logThisOne -eq $true) {
                $logtext=(Get-Content -Path C:\temp\transcripts\$logFileName | Select-Object -last 3)
                Write-Host $logtext
            }
        }
        else
        {
            $other_machines++
            Write-Host "***** BVT job $jobName is in state $jobState." -ForegroundColor Yellow
        }
    }

    $sleep_count++
    if ($completed_machines -lt $launched_machines) {
        sleep(10)
    } else {
        Write-Host "ALL BVTs have completed.  Checking results..."

        if ($failed_machines -gt 0) {
            Write-Host "There were $failed_machines failures out of $launched_machines attempts.  BVTs have failed." -ForegroundColor Red
            exit 1
        } elseif ($completed_machines -eq $launched_machines) {
            Write-Host "All BVTs have passed! " -ForegroundColor Green
            exit 0
        } else {
            write-host "$launched_machines BVT jobs were launched.  Of those: completed = $completed_machines, Running = $running_machines, Failed = $failed_machines, and unknown = $other_machines" -ForegroundColor Red
            exit 1
        }
    }
}
