param (
    [Parameter(Mandatory=$false)] [string[]] $requestedNames,
    [Parameter(Mandatory=$false)] [string] $makeDronesFromAll="False",
    [Parameter(Mandatory=$false)] [string] $overwriteVHDs="False",

    [Parameter(Mandatory=$false)] [string] $sourceSA="smokesourcestorageacct",
    [Parameter(Mandatory=$false)] [string] $sourceRG="smoke_source_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceContainer="clean-vhds",

    [Parameter(Mandatory=$false)] [string] $destSA="smokesourcestorageacct",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_source_resource_group",
    [Parameter(Mandatory=$false)] [string] $destContainer="safe-templates",

    [Parameter(Mandatory=$false)] [string] $location="westus",
    [Parameter(Mandatory=$false)] [string] $vmFlavor="Standard_d2_v2",

    [Parameter(Mandatory=$false)] [string] $NSG="SmokeNSG",
    [Parameter(Mandatory=$false)] [string] $network="SmokeVNet",
    [Parameter(Mandatory=$false)] [string] $subnet="SmokeSubnet-1",

    [Parameter(Mandatory=$false)] [string] $currentSuffix="-Smoke-1.vhd",
    [Parameter(Mandatory=$false)] [string] $newSuffix="-RunOnce-Primed.vhd"
)

Start-Transcript -Path C:\temp\transcripts\create_drone_from_container.transcript -Force

. "C:\Framework-Scripts\common_functions.ps1"
. "C:\Framework-Scripts\secrets.ps1"

[System.Collections.ArrayList]$vmNames_array
$vmNameArray = {$vmNames_array}.Invoke()
$vmNameArray.Clear()
if ($requestedNames -like "*,*") {
    $vmNameArray = $requestedNames.Split(',')
} else {
    $vmNameArray += $requestedNames
}

if ($makeDronesFromAll -ne $true) {

    $regionSuffix = ("-" + $location) -replace " ","-"
Write-Host "Appending flavor $vmFlavor and region suffix $regionSuffix to VM Names"
    $nameCount = 0
    foreach ($vmName in $vmNameArray) {
        $vmName = $vmName + $vmFlavor + $regionSuffix
        $vmNameArray[$nameCount] = $vmName
        $nameCount = $nameCount + 1
    }
}

[System.Collections.ArrayList]$copyblobs_array
$copyblobs = {$copyblobs_array}.Invoke()
$copyblobs.clear()

#
Write-Host "Names array: " $vmNameArray
$numNames = $vmNameArray.Count

$vmName = $vmNameArray[0]
if ($makeDronesFromAll -ne $true -and ($vmNameArray.Count -eq 1  -and $vmNameArray[0] -eq "Unset")) {
    Write-Host "Must specify either a list of VMs in RequestedNames, or use MakeDronesFromAll.  Unable to process this request."
    Stop-Transcript
    exit 1
}
    
$LogDir = "c:\temp\job_logs"

get-job | Stop-Job
get-job | Remove-Job

login_azure $destRG $destSA $location

if ($makeDronesFromAll -eq $true) {
    Write-Host "Looking at all images in container $sourceContainer"
    $copyblob_new=get-AzureStorageBlob -Container $sourceContainer -Blob "*$currentSuffix"
    foreach ($blob in $copyblob_new) {
        Write-Host "Adding blob $blob.Name to the list"
        copyblobs += $blob
    }
} else {
    foreach ($vmName in $vmNameArray) {
        Write-Host "Looking for image $vmName in container $sourceContainer"
        $singleBlob=get-AzureStorageBlob -Container $sourceContainer -Blob "$vmName$suffix" -ErrorAction SilentlyContinue
        if ($? -eq $true) {
            Write-Host "Adding blob for $vmName to the list..."
            $copyblobs += $vmName
        } else {
            Write-Host "Blob for machine $vmName was not found.  This machine cannot be processed."
        }
    }
}

if ($copyblobs.Count -eq 0) {
    Write-Host "No blobs matched source extension $currentSuffix.  No VHDs to process."
    Stop-Transcript
    exit 1
}

write-host "Copying blobs..."
C:\Framework-Scripts\copy_single_image_container_to_container.ps1 -sourceSA $sourceSA -sourceRG $sourceRG -sourceContainer $sourceContainer `
                                       -destSA $destSA -destRG $destRG -destContainer $destContainer `
                                       -sourceExtension $currentSuffix -destExtension $newSuffix -location $location `
                                       -overwriteVHDs $overwriteVHDs -makeDronesFromAll $makeDronesFromAll -vmNames $vmNameArray


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
            write-host "Checkpoint 1" -ForegroundColor Cyan
    Start-Transcript C:\temp\transcripts\$vmName-scriptblock.log -Force
    write-host "Checkpoint 2" -ForegroundColor Cyan
    . "C:\Framework-Scripts\common_functions.ps1"
    . "C:\Framework-Scripts\secrets.ps1"

    write-host "Checkpoint 3" -ForegroundColor Cyan
    
    login_azure $destRG $destSA $location

    Write-Host "Deallocating machine $vmName, if it is up"
    $runningMachines = Get-AzureRmVm -ResourceGroupName $destRG -status | Where-Object -Property Name -Like "$vmName*"
    deallocate_machines_in_group $runningMachines $destRG $destSA $location

    $newVMName = $vmName + $newSuffix
    $newVMName = $newVMName | % { $_ -replace ".vhd", "" }
    $blobURIRaw="https://$sourceSA.blob.core.windows.net/$sourceContainer/" + $vmName + $currentSuffix

    Write-Host "Attempting to create virtual machine $newVMName.  This may take some time." -ForegroundColor Green
    C:\Framework-Scripts\launch_single_azure_vm.ps1 -vmName $newVMName -resourceGroup $destRG -storageAccount $destSA -containerName $destContainer `
                                                    -network $network -subnet $subnet -NSG $NSG #  -addAdminUser $TEST_USER_ACCOUNT_NAME `
                                                    # -adminUser $TEST_USER_ACCOUNT_NAME -adminPW $TEST_USER_ACCOUNT_PAS2
    if ($? -ne $true) {
        Write-Host "Error creating VM $newVMName.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    #
    #  Just because it's up doesn't mean it's accepting connections yet.  Wait 2 minutes, then try to connect.  I tried 1 minute,
    #  but kept getting timeouts on the Ubuntu machines.

    $currentDir="C:\Framework-Scripts"
    $username="$TEST_USER_ACCOUNT_NAME"
    $password="$TEST_USER_ACCOUNT_PAS2" # Could just be "$TEST_USER_ACCOUNT_PASS1_K6"
    $port=22
    $pipName = $newVMName
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
    Write-Host "Copying make_drone to target $ip.." -ForegroundColor Green

    #
    #  Now transfer the files
    $ipTemp = $ip + ":/tmp"
    while ($true) {
        $sslReply=@(echo "y" | C:\azure-linux-automation\tools\pscp -pw $password -l $username C:\Framework-Scripts\README.md $ipTemp)
        echo "SSL Rreply is $sslReply"
        if ($sslReply -match "README" ) {
            Write-Host "Got a key request"
            break
        } else {
            Write-Host "No match"
            sleep(10)
        }
    }
    $sslReply=@(echo "y" | C:\azure-linux-automation\tools\pscp -pw $password -l $username C:\Framework-Scripts\README.md $ipTemp)

    C:\azure-linux-automation\tools\dos2unix.exe -n C:\Framework-Scripts\make_drone.sh c:\temp\nix_files\make_drone.sh
    C:\azure-linux-automation\tools\dos2unix.exe -n C:\Framework-Scripts\secrets.sh c:\temp\nix_files\secrets.sh
    C:\azure-linux-automation\tools\dos2unix.exe -n C:\Framework-Scripts\secrets.ps1 c:\temp\nix_files\secrets.ps1

    try_pscp  C:\temp\nix_files\make_drone.sh $ipTemp
    if ($? -ne $true) {
        Write-Host "Error copying make_drone.sh to $newVMName.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    try_pscp C:\temp\nix_files\secrets.sh $ipTemp
    if ($? -ne $true) {
        Write-Host "Error copying secrets.sh to $newVMName.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    try_pscp C:\temp\nix_files\secrets.ps1 $ipTemp
    if ($? -ne $true) {
        Write-Host "Error copying secrets.ps1 to $newVMName.  This VM must be manually examined!!" -ForegroundColor red
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
    try_plink $ip $linuxChmodCommand
    if ($? -ne $true) {
        Write-Host "Error running chmod command.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    #
    #  Now run make_drone
    Write-Host "And now running..."
    try_plink $ip $linuxDroneCommand
    if ($? -ne $true) {
        Write-Host "Error running make_drone command.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    Stop-Transcript
}

$scriptBlock = [scriptblock]::Create($scriptBlockString)

$dronejobs_array=@()
$droneJobs = {$dronejobs_array}.Invoke()
$droneJobs.clear()

write-host "Setting up the drone jobs..."

get-job | Stop-Job
get-job | Remove-Job

Set-AzureRmCurrentStorageAccount –ResourceGroupName $destRG –StorageAccountName $destSA
foreach ($vmName in $vmNameArray) { 
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
$notDone = $true
while ($notDone -eq $true) {
    write-host "Status at "@(date)"is:" -ForegroundColor Green
    $notDone = $false
    foreach ($vmName in $vmNameArray) {
        $jobName=$vmName + "-drone-job"
        $job = get-job $jobName
        $jobState = $job.State
        write-host "    Job $jobName is in state $jobState" -ForegroundColor Yellow
        if ($jobState -eq "Running") {
            $notDone = $true
        }
    }
    sleep 10
}

Write-Host "All jobs have completed.  Checking results (this will take a moment...)"

#
#  Get the results of that
$status = c:\Framework-Scripts\run_command_on_machines_in_group.ps1 -requestedNames $requestedNames -destSA $destSA -destRG $destRG -suffix $newSuffix -command "/bin/uname -a"
$status

if ($status -contains "FAILED to establish PSRP connection") {
    Write-Host "Errors found in this job, so adding the job output to the log..."
    
    $jobs = get-job
    foreach ($job in $jobs) {
        Write-Host ""
        Write-Host "------------------------------------------------------------------------------------------------------"
        Write-Host "                             JOB LOG FOR JOB $job.Name"   
        Write-Host "------------------------------------------------------------------------------------------------------"
        Write-Host ""
        $job | receive-job
    }
}

get-job | stop-job
get-job | remove-job

Stop-Transcript

if ($sessionFailed -eq $true) {    
    exit 1
} else {
    exit 0
}