param (
    [Parameter(Mandatory=$false)] [string[]] $requestedNames,
    [Parameter(Mandatory=$false)] [switch] $makeDronesFromAll,
    [Parameter(Mandatory=$false)] [switch] $overwriteVNDs,

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

. "C:\Framework-Scripts\common_functions.ps1"

if ($makeDronesFromAll -eq $false -and $requestedNames.Count -eq 0) {
    Write-Host "Must specify either a list of VMs in RequestedNames, or use MakeDronesFromAll.  Unable to process this request."
    exit 1
}
    
$LogDir = "c:\temp\job_logs"
$randomFileName = $vmName + "_copyImages.log"

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
        $singleBlob=get-AzureStorageBlob -Container $sourceContainer -name $theName
        $blobs += $singleBlob
    }
}

if ($blobs.Count -eq 0) {
    Write-Host "No blobs matched source extension $currentSuffix.  No VHDs to process."
    exit 1
}

foreach ($oneblob in $blobs) {
    $sourceName=$oneblob.Name
    write-host  "Adding sourceName $sourceName"
    $vmName=$sourceName | % { $_ -replace "$currentSuffix", "" }

    $vmNames.Add($vmName)
}

write-host "Copying blobs..."
C:\Framework-Scripts\copy_single_image_container_to_container.ps1 -sourceSA $sourceSA -sourceRG $sourceRG -sourceContainer $sourceContainer `
                                        -destSA $destSA -destRG $destRG -destContainer $destContainer `
                                        -sourceExtension $currentSuffix -destExtension $newSuffix -location $location `
                                        -overwriteVHDs:$overwriteVHDs -makeDronesFromAll:$makeDronesFromAll -vmNames $vmNames > $LogDir\$randomFileName


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

    Write-Host "Importing the context...." -ForegroundColor Green
    Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'

    Write-Host "Selecting the Azure subscription..." -ForegroundColor Green
    Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4"
    Set-AzureRmCurrentStorageAccount –ResourceGroupName $destRG –StorageAccountName $destSA

    write-host "Stopping VM $vmName, if running"
    Get-AzureRmVm -ResourceGroupName $destRG -status | Where-Object -Property Name -Like "$vmName*" | where-object -Property PowerState -eq -value "VM Running" | Stop-AzureRmVM -Force

    Write-Host "Deallocating machine $vmName, if it is up"
    az vm delete -n $vmName -g $destRG --yes

    $osDiskName = $vmName + "-osDisk"
    $blobURIRaw="https://$sourceSA.blob.core.windows.net/$sourceContainer/" + $vmName + $currentSuffix
    Write-Host "Clearing any old images..." -ForegroundColor Green
    Get-AzureStorageBlob -Container $destContainer -Prefix $vmName | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $destContainer}

    Write-Host "Attempting to create virtual machine $vmName.  This may take some time." -ForegroundColor Green
    C:\Framework-Scripts\launch_single_azure_vm.ps1 -vmName $vmName -resourceGroup $destRG -storageAccount $destSA -containerName $destContainer

    # az vm create -n $vmName -g $destRG -l $location --image $blobURIRaw --storage-container-name $destContainer --use-unmanaged-disk --nsg $NSG `
    #     --subnet $subnet --vnet-name $network --os-type Linux --storage-account $destSA --os-disk-name $vmName --admin-password 'P@ssW0rd-1_K6' `
    #     --admin-username "mstest" --authentication-type "password" 
    if ($? -ne $true) {
        Write-Host "Error creating VM $vmName.  This VM must be manually examined!!" -ForegroundColor red
        exit 1
    }

    exit 1

    $currentDir="C:\Framework-Scripts"
    $username="mstest"
    $password="P@ssW0rd-1_K6"
    $port=22
    $pipName = $vmName + "PublicIP"
    $ip=(Get-AzureRmPublicIpAddress -ResourceGroupName $destRG -Name $pipName).IpAddress
    if ($? -ne $true) {
        Write-Host "Error getting IP address for VM $vmName.  This VM must be manually examined!!" -ForegroundColor red
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
        Write-Host "Error copying make_drone.sh to $vmName.  This VM must be manually examined!!" -ForegroundColor red
        exit 1
    }

    $chmodCommand="chmod 755 /tmp/make_drone.sh"
    $runDroneCommand="/tmp/make_drone.sh"
    $linuxChmodCommand="`"echo $password | sudo -S bash -c `'$chmodCommand`'`""
    $linuxDroneCommand="`"echo $password | sudo -S bash -c `'$runDroneCommand`'`""
    $randomFileName = $vmName + "chmod_.log"
    write-host "Logging to file $randomFileName"
    $LogDir = "c:\temp\job_logs"

    Write-Host "Using plink to chmod the script"
    #
    #  chmod the thing
    C:\azure-linux-automation\tools\plink.exe -C -v -pw $password -P $port $username@$ip $linuxChmodCommand
    if ($? -ne $true) {
        Write-Host "Error doing the chmod on make_drone.sh for $vmName.  This VM must be manually examined!!" -ForegroundColor red
        exit 1
    }


    #
    #  Now run make_drone
    Write-Host "And now running..."
    C:\azure-linux-automation\tools\plink.exe -C -v -pw $password -P $port $username@$ip $linuxDroneCommand
    if ($? -ne $true) {
        Write-Host "Error executing make_drone.sh on $vmName.  This VM must be manually examined!!" -ForegroundColor red
        exit 1
    }
}

$scriptBlock = [scriptblock]::Create($scriptBlockString)

$dronejobs_array=@()
$droneJobs = {$dronejobs_array}.Invoke()
$droneJobs.clear()

Set-AzureRmCurrentStorageAccount –ResourceGroupName $destRG –StorageAccountName $destSA
foreach ($vmName in $vmNames) { 
    $randomFileName = $vmName + "_make_drone.log"
    $jobName=$vmName + "-drone-job"
    $makeDroneJob = Start-Job -Name $jobName -ScriptBlock $scriptBlock -ArgumentList $vmName,$sourceRG,$sourceSA,$sourceContainer,$destRG,$destSA,`
                                                                      $destContainer,$location,$currentSuffix,$newSuffix,$NSG,`
                                                                      $network,$subnet > $LogDir\$randomFileName
    if ($? -ne $true) {
        Write-Host "Error starting make_drone job ($jobName) for $vmName.  This VM must be manually examined!!" -ForegroundColor red
        exit 1
    }

    Write-Host "Just launched job $jobName"
}

write-host "Checking make_drone jobs..."
$allComplete = $false
while ($allComplete -eq $false) {
    $allComplete = $true
    foreach ($vmName in $vmNames) {
        $jobName=$vmName + "-drone-job"
        $job = get-job $jobName
        $jobState = $job.State
        write-host "    Job $jobName state is $jobState" -ForegroundColor Yellow
        if ($jobState -eq "Running") {
            $allComplete = $false
        }
        Write-Host "Job $jobName state is $jobState"
    }
    sleep 10
}

Write-Host "All jobs have completed.  Checking results..."
#
#  Get the results of that
foreach ($vmName in $vmNames) { 
    $randomFileName = $vmName + "_make_drone.log"
    $jobName=$vmName + "-drone-job"

    $out = receive-job $jobName 
    $out2 = Get-Content $LogDir\$randomFileName

    Write-host "-------------------------------"
    Write-Host $out
    Write-host "-------"
    Write-Host $out2
    
}