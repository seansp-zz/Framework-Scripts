param (
    [Parameter(Mandatory=$false)] [string[]] $Incoming_vmNames,
    [Parameter(Mandatory=$false)] [string[]] $Incoming_blobURNs,

    [Parameter(Mandatory=$false)] [string] $destRG="jpl_intake_rg",
    [Parameter(Mandatory=$false)] [string] $destSA="jplintakestorageacct",
    [Parameter(Mandatory=$false)] [string] $destContainer="ready-for-bvt",
    [Parameter(Mandatory=$false)] [string] $location="westus",

    [Parameter(Mandatory=$false)] [string] $useNewResourceGroup = "True",

    [Parameter(Mandatory=$false)] [string] $vnetName = "SmokeVNet",
    [Parameter(Mandatory=$false)] [string] $subnetName = "SmokeSubnet-1",
    [Parameter(Mandatory=$false)] [string] $NSG = "SmokeNSG",

    [Parameter(Mandatory=$false)] [string] $suffix = "-Smoke-1",
    [Parameter(Mandatory=$false)] [string] $VMFlavor="standard_d2_v2"
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
get-job | Stop-Job
get-job | remove-job

Start-Transcript C:\temp\transcripts\create_vhd_from_urn.log -Force

$vmNames_array=@()
$vmNameArray = {$vmNames_array}.Invoke()
$vmNameArray.Clear()
if ($Incoming_vmNames -like "*,*") {
    $vmNameArray = $Incoming_vmNames.Split(',')
} else {
    $vmNameArray += $Incoming_vmNames
}

$blobURN_Array=@()
$blobURNArray = {$blobURN_Array}.Invoke()
$blobURNArray.Clear()

if ($Incoming_vmNames -like "*,*") {
    $blobURNArray = $Incoming_blobURNs.Split(',')
} else {
    $blobURNArray += $Incoming_blobURNs
}

Write-Host "Names array: " $vmNameArray -ForegroundColor Yellow
$numNames = $vmNameArray.Count
Write-Host "blobs array: " $blobURNArray -ForegroundColor Yellow
$numBlobs = $blobURNArray.Count

$firstBlob = $blobURNArray[0]

if ($vmNameArray.Count -ne $blobURNArray.Count) {
    Write-Host "Please provide the same number of names and URNs. You have $numNames names and $numBlobs blobs" -ForegroundColor Red
    exit 1
} else {
    $numLeft = $vmNameArray.Count
    Write-Host "There are $numLeft machines to process..."  -ForegroundColor Gray
}
$vmName = $vmNameArray[0]

. "C:\Framework-Scripts\common_functions.ps1"
. "C:\Framework-Scripts\secrets.ps1"

$location=($location.ToLower()).Replace(" ","")

$saLength = $destSA.Length
if ($saLength -gt 24) {
    #
    #  Truncate the name
    $destSA = $destSA.Substring(0, 24)
    $saLength = $destSA.Length
}


#  Log in without changing to the RG or SA.  This is intentional
login_azure

Write-Host "Looking for storage account $destSA in resource group $destRG.  Length of name is $saLength"
#
$existingGroup = Get-AzureRmResourceGroup -Name $destRG
if ($? -eq $true -and $existingGroup -ne $null) {
    write-host "Resource group already existed.  Deleting resource group." -ForegroundColor Yellow
    Remove-AzureRmResourceGroup -Name $destRG -Force

    write-host "Creating new resource group $destRG"
    New-AzureRmResourceGroup -Location $location -Name $destRG -Force
}

#
#
#  Change the name of the SA to include the region, then Now see if the SA exists
$existingAccount = Get-AzureRmStorageAccount -ResourceGroupName $destRG -Name $destSA
if ($? -eq $false) {
    Write-Host "Storage account $destSA did not exist.  Creating it and populating with the right containers..." -ForegroundColor Yellow
    New-AzureRmStorageAccount -ResourceGroupName $destRG -Name $destSA -Location $location -SkuName Standard_LRS -Kind Storage

    write-host "Selecting it as the current SA" -ForegroundColor Yellow
    Set-AzureRmCurrentStorageAccount –ResourceGroupName $destRG –StorageAccountName $destSA

    Write-Host "creating the containers" -ForegroundColor Yellow
    New-AzureStorageContainer -Name "ready-for-bvt" -Permission Blob
    New-AzureStorageContainer -Name "drones" -Permission Blob
    Write-Host "Complete." -ForegroundColor Green
}
Set-AzureRmCurrentStorageAccount –ResourceGroupName $destRG –StorageAccountName $destSA

$gotContainer = Get-AzureStorageBlob -Container "ready-for-bvt" -Prefix $vmName
if ($? -eq $false) {
    Write-Host "creating the BVT ready container" -ForegroundColor Yellow
    New-AzureStorageContainer -Name "ready-for-bvt" -Permission Blob
}

$gotContainer = Get-AzureStorageBlob -Container "drones" -Prefix $vmName
if ($? -eq $false) {
    New-AzureStorageContainer -Name "drones" -Permission Blob
    Write-Host "Complete." -ForegroundColor Green
}

. C:\Framework-Scripts\backend.ps1
# . "$scriptPath\backend.ps1"

 ## Storage
$vnetAddressPrefix = "10.0.0.0/16"
$vnetSubnetAddressPrefix = "10.0.0.0/24"

$backendFactory = [BackendFactory]::new()
$azureBackend = $backendFactory.GetBackend("AzureBackend", @(1))

$azureBackend.ResourceGroupName = $destRG
$azureBackend.StorageAccountName = $destSA
$azureBackend.ContainerName = $destContainer
$azureBackend.Location = $location
$azureBackend.VMFlavor = $VMFlavor
$azureBackend.NetworkName = $vnetName
$azureBackend.SubnetName = $subnetName
$azureBackend.NetworkSecGroupName = $NSG
$azureBackend.addressPrefix = $vnetAddressPrefix
$azureBackend.subnetPrefix = $vnetSubnetAddressPrefix
$azureBackend.blobURN = $blobURN
$azureBackend.suffix = $suffix

$azureInstance = $azureBackend.GetInstanceWrapper("AzureSetup")
$azureInstance.Cleanup()
$ret = $azureInstance.SetupAzureRG()

#
#  If the account does not exist, create it.

$scriptBlockString = 
{
    param ( [string] $vmName,
            [string] $VMFlavor,
            [string] $blobURN,
            [string] $destRG,
            [string] $destSA,
            [string] $destContainer,
            [string] $location,
            [string] $suffix,
            [string] $NSG,
            [string] $vnetName,
            [string] $subnetName
            )    
    Start-Transcript C:\temp\transcripts\create_vhd_from_urn_$vmName.log -Force

    . C:\Framework-Scripts\common_functions.ps1
    . C:\Framework-Scripts\secrets.ps1

    $NSG = $NSG
    $subnetName =  $subnetName
    $vnetName  = $vnetName
    $pipName = $vmName 
    $nicName = $vmName

    login_azure $destRG $destSA $location

   

    Write-Host "Deleting any existing VM" -ForegroundColor Green
    $runningVMs = Get-AzureRmVm -ResourceGroupName $destRG -status | Where-Object -Property Name -Like "$vmName*" | Remove-AzureRmVM -Force -ErrorAction Continue
    if ($runningVMs -ne $null) {
        deallocate_machines_in_group $runningVMs $destRG $destSA $location
    }
    
    Write-Host "Clearing any old images in $destContainer with prefix $vmName..." -ForegroundColor Green
    Get-AzureStorageBlob -Container $destContainer -Prefix $vmName | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $destContainer} -ErrorAction Continue    

    . C:\Framework-Scripts\backend.ps1
    # . "$scriptPath\backend.ps1"
    $backendFactory = [BackendFactory]::new()
    $azureBackend = $backendFactory.GetBackend("AzureBackend", @(1))

    $azureBackend.ResourceGroupName = $destRG
    $azureBackend.StorageAccountName = $destSA
    $azureBackend.ContainerName = $destContainer
    $azureBackend.Location = $location
    $azureBackend.VMFlavor = $VMFlavor
    $azureBackend.NetworkName = $vnetName
    $azureBackend.SubnetName = $subnetName
    $azureBackend.NetworkSecGroupName = $NSG
    $azureBackend.addressPrefix = $vnetAddressPrefix
    $azureBackend.subnetPrefix = $vnetSubnetAddressPrefix
    $azureBackend.blobURN = $blobURN
    $azureBackend.suffix = $suffix

    $azureInstance = $azureBackend.GetInstanceWrapper($vmName)
    $azureInstance.Cleanup()

    $azureInstance.CreateFromURN()

    $VM = $azureInstance.GetVM()
    # $VM = Get-AzureRmVM -ResourceGroupName $destRG -Name $vmName
    Set-AzureRmVMBootDiagnostics -VM $VM -Disable -ResourceGroupName $destRG  -StorageAccountName $destSA

    #
    #  Disable Cloud-Init so it doesn't try to deprovision the machine (known bug in Azure)
    write-host "Attempting to contact the machine..." -ForegroundColor Green
    
    $ip=$azureInstance.GetPublicIP()
    $password=$TEST_USER_ACCOUNT_PAS2
    $port=22
    $username="$TEST_USER_ACCOUNT_NAME"

    #
    # Disable cloud-init
    $disableCommand0="mv /usr/bin/cloud-init /usr/bin/cloud-init.DO_NOT_RUN_THIS_POS"
    $runDisableCommand0="`"echo `'$password`' | sudo -S bash -c `'$disableCommand0`'`""

    #
    #  Eat the prompt and get the host into .known_hosts
    $remoteAddress = $ip
    $remoteTmp=$remoteAddress + ":/tmp"
    Write-Host "Attempting to contact remote macnhine using $remoteAddress" -ForegroundColor Green
    $timeOut = 0
    while ($true) {
        $sslReply=@(echo "y" | C:\azure-linux-automation\tools\pscp -pw $password -l $username C:\Framework-Scripts\README.md $remoteTmp)
        echo "SSL Rreply is $sslReply"
        if ($sslReply -match "README" ) {
            Write-Host "Got a key request" -ForegroundColor Green
            break
        } else {
            Write-Host "No match" -ForegroundColor Yellow
            sleep(10)
            $timeOut = $timeOut + 1
            if ($timeOut -ge 60) {
                Write-Host "Failed to contact machine at IP $remoteAddress for 600 seconds.  Timeout."
                Stop-Transcript
                return 1
            }
        }
    }
    $sslReply=@(echo "y" |C:\azure-linux-automation\tools\pscp -pw $password -l $username  C:\Framework-Scripts\README.md $remoteAddress``:/tmp)

    Write-Host "Setting SELinux into permissive mode" -ForegroundColor Green
    try_plink $ip $runDisableCommand0

    Write-Host "VM Created successfully.  Stopping it now..." -ForegroundColor Green
    $azureInstance.StopInstance()

    Write-Host "Deleting the VM so we can harvest the VHD..." -ForegroundColor Green
    $azureInstance.RemoveInstance()

    Write-Host "Machine $vmName is ready for assimilation..." -ForegroundColor Green

    Stop-Transcript
}

$scriptBlock = [scriptblock]::Create($scriptBlockString)

$i = 0
foreach ($vmName in $vmNameArray) {
    $blobURN = $blobURNArray[$i]
    $i++
    Write-Host "Preparing machine $vmName for (URN $blobURN) service as a drone..." -ForegroundColor Green

    $jobName=$vmName + "-intake-job"
    $makeDroneJob = Start-Job -Name $jobName -ScriptBlock $scriptBlock -ArgumentList $vmName,$VMFlavor,$blobURN,$destRG,$destSA,`
                                                                      $destContainer,$location,$suffix,$NSG,`
                                                                      $vnetName,$subnetName
    if ($? -ne $true) {
        Write-Host "Error starting intake_machine job ($jobName) for $vmName.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    Write-Host "Just launched job $jobName" -ForegroundColor Green
}

sleep(10)

$notDone = $true
while ($notDone -eq $true) {
    write-host "Status at "@(date)"is:" -ForegroundColor Green
    $notDone = $false
    foreach ($vmName in $vmNameArray) {
        $jobName=$vmName + "-intake-job"
        $job = get-job $jobName
        $jobState = $job.State
        if ($jobState -eq "Running") {
            $notDone = $true
            $useColor = "Yellow"
        } elseif ($jobState -eq "Completed") {
            $useColor="green"
        } elseif ($jobState -eq "Failed") {
            $useColor = "Red"
        } elseif ($jobState -eq "Blocked") {
            $useColor = "Magenta"
        }
        write-host "    Job $jobName is in state $jobState" -ForegroundColor $useColor
        $logFileName = "C:\temp\transcripts\create_vhd_from_urn_$vmName.log"
        $logLines = Get-Content -Path $logFileName -Tail 5 -ErrorAction SilentlyContinue
        if ($? -eq $true) {
            Write-Host "         Last 5 lines from the log file:" -ForegroundColor Cyan
            foreach ($line in $logLines) { 
                write-host "        "$line -ForegroundColor Gray 
            }
        }
    }
    sleep 10
}

Stop-Transcript
#
#  Exit with error if we failed to create the VM.  THe setup may have failed, but we can't tell that right ow
exit 0