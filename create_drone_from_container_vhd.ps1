﻿param (
    [Parameter(Mandatory=$false)] [string[]] $requestedNames,
    [Parameter(Mandatory=$false)] [string] $makeDronesFromAll=$false,
    [Parameter(Mandatory=$false)] [string] $overwriteVHDs=$false,

    [Parameter(Mandatory=$false)] [string] $sourceSA="smokesourcestorageacct",
    [Parameter(Mandatory=$false)] [string] $sourceRG="smoke_source_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceContainer="clean-vhds",

    [Parameter(Mandatory=$false)] [string] $destSA="smokesourcestorageacct",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_source_resource_group",
    [Parameter(Mandatory=$false)] [string] $destContainer="safe-templates",

    [Parameter(Mandatory=$false)] [string] $location="westus",

    [Parameter(Mandatory=$false)] [string] $NSG="SmokeNSG",
    [Parameter(Mandatory=$false)] [string] $network="SmokeVNet",
    [Parameter(Mandatory=$false)] [string] $subnet="SmokeSubnet-1",

    [Parameter(Mandatory=$false)] [string] $currentSuffix="-Smoke-1.vhd",
    [Parameter(Mandatory=$false)] [string] $newSuffix="-RunOnce-Primed.vhd"
)

Start-Transcript -Path C:\temp\transcripts\create_drone_from_container.transcript -Force

. "C:\Framework-Scripts\common_functions.ps1"

if ($makeDronesFromAll -eq $false -and ($requestedNames.Count -eq 1  -and $requestedNames[0] -eq "Unset")) {
    Write-Host "Must specify either a list of VMs in RequestedNames, or use MakeDronesFromAll.  Unable to process this request."
    Stop-Transcript
    exit 1
}
    
$LogDir = "c:\temp\job_logs"

get-job | Stop-Job
get-job | Remove-Job

login_azure $destRG $destSA

$vmNames_array=@()
$vmNames = {$vmNamess_array}.Invoke()
$vmNames.Clear()

$blobs_array=@()
$blobs = {$blobs_array}.Invoke()

Set-AzureRmCurrentStorageAccount –ResourceGroupName $sourceRG –StorageAccountName $sourceSA
if ($makeDronesFromAll -eq $true) {
    Write-Host "Looking at all images in container $sourceContainer"
    $blobs=get-AzureStorageBlob -Container $sourceContainer -Blob "*$currentSuffix"
} else {
    foreach ($vmName in $requestedNames) {
        Write-Host "Looking at image $vmName in container $sourceContainer"
        $theName = $vmName + $currentSuffix
        $singleBlob=get-AzureStorageBlob -Container $sourceContainer -Blob $theName
        $blobs += $singleBlob
    }
}

if ($blobs.Count -eq 0) {
    Write-Host "No blobs matched source extension $currentSuffix.  No VHDs to process."
    Stop-Transcript
    exit 1
}

foreach ($oneblob in $blobs) {
    $sourceName=$oneblob.Name
    write-host  "Adding sourceName $sourceName"
    $vmName=$sourceName | % { $_ -replace "$currentSuffix", "" }
    write-host  "Adding VM name $vmName"
    $vmNames.Add($vmName)
}

write-host "Copying blobs..."
C:\Framework-Scripts\copy_single_image_container_to_container.ps1 -sourceSA $sourceSA -sourceRG $sourceRG -sourceContainer $sourceContainer `
                                        -destSA $destSA -destRG $destRG -destContainer $destContainer `
                                        -sourceExtension $currentSuffix -destExtension $newSuffix -location $location `
                                        -overwriteVHDs:$overwriteVHDs -makeDronesFromAll:$makeDronesFromAll -vmNames $vmNames


$scriptBlockString = 
{
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
            $subnet
            )

    Start-Transcript C:\temp\transcripts\scriptblock.log -Force

    . "C:\Framework-Scripts\common_functions.ps1"

    login_azure $destRG $destSA

    write-host "Stopping VM $vmName, if running"
    Get-AzureRmVm -ResourceGroupName $destRG -status | Where-Object -Property Name -Like "$vmName*" | where-object -Property PowerState -eq -value "VM running" | Stop-AzureRmVM -Force

    Write-Host "Deallocating machine $vmName, if it is up"
    Get-AzureRmVm -ResourceGroupName $destRG -status | Where-Object -Property Name -Like "$vmName*" | Remove-AzureRmVM -Force

    $newVMName = $vmName + $newSuffix
    $newVMName = $newVMName | % { $_ -replace ".vhd", "" }
    $blobURIRaw="https://$sourceSA.blob.core.windows.net/$sourceContainer/" + $vmName + $currentSuffix

    Write-Host "Attempting to create virtual machine $newVMName.  This may take some time." -ForegroundColor Green
    C:\Framework-Scripts\launch_single_azure_vm.ps1 -vmName $newVMName -resourceGroup $destRG -storageAccount $destSA -containerName $destContainer -network $network -subnet $subnet -addAdminUser mstest -adminUser mstest -adminPW "P@ssW0rd-1_K6"
    if ($? -ne $true) {
        Write-Host "Error creating VM $newVMName.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    #
    #  Just because it's up doesn't mean it's accepting connections yet.  Wait 1 minute, then try to connect
    sleep(60)

    $currentDir="C:\Framework-Scripts"
    $username="mstest"
    $password="P@ssW0rd-1_K6"
    $port=22
    $pipName = $newVMName + "-pip"
    $ip=(Get-AzureRmPublicIpAddress -ResourceGroupName $destRG -Name $pipName).IpAddress
    if ($? -ne $true) {
        Write-Host "Error getting IP address for VM $newVMName.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    #
    #  Send make_drone to the new machine
    #
    #  The first one gets the machine added to known_hosts
    Write-Host "Copying make_drone to the target.." -ForegroundColor Green
    echo "y" | C:\azure-linux-automation\tools\pscp C:\Framework-Scripts\make_drone.sh mstest@$ip`:/tmp

    #
    #  Now transfer the files
    C:\azure-linux-automation\tools\dos2unix.exe C:\Framework-Scripts\make_drone.sh
    echo $password | C:\azure-linux-automation\tools\pscp C:\Framework-Scripts\make_drone.sh mstest@$ip`:/tmp
    if ($? -ne $true) {
        Write-Host "Error copying make_drone.sh to $newVMName.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    $chmodCommand="chmod 755 /tmp/make_drone.sh"
    $runDroneCommand="/tmp/make_drone.sh"
    $linuxChmodCommand="`"echo $password | sudo -S bash -c `'$chmodCommand`'`""
    $linuxDroneCommand="`"echo $password | sudo -S bash -c `'$runDroneCommand`'`""

    Write-Host "Using plink to chmod the script"
    #
    #  chmod the thing
    C:\azure-linux-automation\tools\plink.exe -C -v -pw $password -P $port $username@$ip $linuxChmodCommand

    #
    #  Now run make_drone
    Write-Host "And now running..."
    C:\azure-linux-automation\tools\plink.exe -C -v -pw $password -P $port $username@$ip $linuxDroneCommand

    Stop-Transcript
}

$scriptBlock = [scriptblock]::Create($scriptBlockString)

$dronejobs_array=@()
$droneJobs = {$dronejobs_array}.Invoke()
$droneJobs.clear()

Set-AzureRmCurrentStorageAccount –ResourceGroupName $destRG –StorageAccountName $destSA
foreach ($vmName in $vmNames) { 
    $jobName=$vmName + "-drone-job"
    $makeDroneJob = Start-Job -Name $jobName -ScriptBlock $scriptBlock -ArgumentList $vmName,$sourceRG,$sourceSA,$sourceContainer,$destRG,$destSA,`
                                                                      $destContainer,$location,$currentSuffix,$newSuffix,$NSG,`
                                                                      $network,$subnet
    if ($? -ne $true) {
        Write-Host "Error starting make_drone job ($jobName) for $vmName.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    Write-Host "Just launched job $jobName"
}

write-host "Checking make_drone jobs..."
$allComplete = $false
while ($allComplete -eq $false) {
    write-host "Status at "@(date)"is:" -ForegroundColor Green
    $allComplete = $true
    foreach ($vmName in $vmNames) {
        $jobName=$vmName + "-drone-job"
        $job = get-job $jobName
        $jobState = $job.State
        write-host "    Job $jobName is in state $jobState" -ForegroundColor Yellow
        if ($jobState -eq "Running") {
            $allComplete = $false
        }
    }
    sleep 10
}

Write-Host "All jobs have completed.  Checking results..."
#
#  Get the results of that
$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$cred = make_cred
$sessionFailed = $false
foreach ($vmName in $vmNames) {
    $newVMName = $vmName + $newSuffix
    $newVMName = $newVMName | % { $_ -replace ".vhd", "" }

    [System.Management.Automation.Runspaces.PSSession]$session = create_psrp_session $newVMName $destRG $destSA $cred $o
    if ($session -ne $NULL) {
        invoke-command -session $session -ScriptBlock {/bin/uname -a}
        Remove-PSSession $session
    } else {
        Write-Host "FAILED to create PSRP session to $newVMName"
        $sessionFailed = $true
    }
}

Stop-Transcript

if ($sessionFailed -eq $true) {    
    exit 1
} else {
    exit 0
}