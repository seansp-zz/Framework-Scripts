param (
    [Parameter(Mandatory=$false)] [string[]] $Incoming_vmNames,
    [Parameter(Mandatory=$false)] [string[]] $Incoming_blobURNs,

    [Parameter(Mandatory=$false)] [string] $destRG="jpl_intake_rg",
    [Parameter(Mandatory=$false)] [string] $destSA="jplintakestorageacct",
    [Parameter(Mandatory=$false)] [string] $destContainer="ready-for-bvt",
    [Parameter(Mandatory=$false)] [string] $location="westus",

    [Parameter(Mandatory=$false)] [string] $vnetName = "SmokeVNet",
    [Parameter(Mandatory=$false)] [string] $subnetName = "SmokeSubnet-1",
    [Parameter(Mandatory=$false)] [string] $NSG = "SmokeNSG",

    [Parameter(Mandatory=$false)] [string] $suffix = "-Smoke-1"
)

$vmNames_array=@()
$vmNameArray = {$vmNamess_array}.Invoke()
$vmNameArray.Clear()
$vmNameArray = $Incoming_vmNames.Split(',')

$blobURNArray=@()
$blobURNArray = {$blobURNArray}.Invoke()
$blobURNArray = $Incoming_blobURNs.Split(',')

Write-Host "Names array: " $vmNameArray
$numNames = $vmNameArray.Length
Write-Host "blobs array: " $blobURNArray
$numBlobs = $blobURNArray.Length

if ($vmNameArray.Length -ne $blobURNArray.Length) {
    Write-Host "Please provide the same number of names and URNs. You have $numNames names and $numBlobs blobs"
    exit 1
} else {
    Write-Host "There are $vmNameArray.Length left..."
}
$vmName = $vmNameArray[0]

. "C:\Framework-Scripts\common_functions.ps1"
. "C:\Framework-Scripts\secrets.ps1"

Write-Host "Working with RG $destRG and SA $destSA"
login_azure $destRG $destSA

$scriptBlockString = 
{
    param ($vmName,
            $blobURN,
            $destRG,
            $destSA,
            $destContainer,
            $location,
            $suffix,
            $NSG,
            $vnetName,
            $subnetName
            )

    Start-Transcript C:\temp\transcripts\create_vhd_from_urn_$vmName.log -Force

    . "C:\Framework-Scripts\common_functions.ps1"
    . C:\Framework-Scripts\secrets.ps1

    login_azure $destRG $destSA

    # Global
    $location = "westus"

    ## Storage
    $storageType = "Standard_D2"

    ## Network
    $nicname = $vmName + "VMNic"

    $vnetAddressPrefix = "10.0.0.0/16"
    $vnetSubnetAddressPrefix = "10.0.0.0/24"

    ## Compute

    $vmSize = "Standard_A2"


    echo "Deleting any existing VM"
    $runningVMs = Get-AzureRmVm -ResourceGroupName $destRG -status | Where-Object -Property Name -Like "$vmName*" | Remove-AzureRmVM -Force -ErrorAction Continue
    deallocate_machines_in_group $runningVMs $destRG $destSA

    Write-Host "Clearing any old images in $destContainer with prefix $vmName..." -ForegroundColor Green
    Get-AzureStorageBlob -Container $destContainer -Prefix $vmName | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $destContainer} -ErrorAction Continue

    Write-Host "Attempting to create virtual machine $vmName.  This may take some time." -ForegroundColor Green
    Write-Host "User is $TEST_USER_ACCOUNT_NAME"
    Write-Host "Password is $TEST_USER_ACCOUNT_PAS2"
    $vmName = $vmName + $suffix
    $diskName=$vmName
    write-host "Creating machine $vmName"
    $pw = convertto-securestring -AsPlainText -force -string "$TEST_USER_ACCOUNT_PASS" 
    [System.Management.Automation.PSCredential]$cred = new-object -typename system.management.automation.pscredential -argumentlist "$TEST_USER_ACCOUNT_NAME",$pw

    az vm create -n $vmName -g $destRG -l $location --image $blobURN --storage-container-name $destContainer --use-unmanaged-disk --nsg $NSG `
       --subnet $subnetName --vnet-name $vnetName  --storage-account $destSA --os-disk-name $diskName --admin-password $TEST_USER_ACCOUNT_PAS2 `
       --admin-username mstest --authentication-type password
    if ($? -eq $false) {
        Write-Error "Failed to create VM.  Details follow..."
        Stop-Transcript
        exit 1
    }

    az vm boot-diagnostics enable --storage "http://$destSA.blob.core.windows.net/" -n $vmName -g $destRG

    $VM = Get-AzureRmVM -ResourceGroupName $destRG -Name $vmName
    Set-AzureRmVMBootDiagnostics -VM $VM -Disable -ResourceGroupName $destRG  -StorageAccountName $destSA

    #
    #  Disable Cloud-Init so it doesn't try to deprovision the machine (known bug in Azure)
    write-host "Attempting to contact the machine..."
    $pipName = $vmName + "PublicIP"
    $ip=(Get-AzureRmPublicIpAddress -ResourceGroupName $destRG -Name $pipName).IpAddress
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
    Write-Host "Attempting to contact remote macnhine using $remoteAddress"
    while ($true) {
        $sslReply=@(echo "y" | C:\azure-linux-automation\tools\pscp -pw $password -l $username C:\Framework-Scripts\README.md $remoteTmp)
        echo "SSL Rreply is $sslReply"
        if ($sslReply -match "README" ) {
            Write-Host "Got a key request"
            break
        } else {
            Write-Host "No match"
            sleep(10)
        }
    }
    $sslReply=@(echo "y" |C:\azure-linux-automation\tools\pscp -pw $password -l $username  C:\Framework-Scripts\README.md $remoteAddress``:/tmp)

    Write-Host "Setting SELinux into permissive mode"
    C:\azure-linux-automation\tools\plink.exe -C -v -pw $password -P $port -l $userName $ip $runDisableCommand0

    Write-Host "VM Created successfully.  Stopping it now..."
    Stop-AzureRmVM -ResourceGroupName $destRG -Name $vmName -Force

    # Write-Host "Deleting the VM so we can harvest the VHD..."
    Remove-AzureRmVM -ResourceGroupName $destRG -Name $diskName -Force

    Write-Host "Machine $vmName is ready for assimilation..."

    Stop-Transcript
}

$scriptBlock = [scriptblock]::Create($scriptBlockString)

$i = 0
foreach ($vmName in $vmNameArray) {
    $blobURN = $blobURNArray[$i]
    $i++
    Write-Host "Preparing machine $vmName for service as a drone..."

    $jobName=$vmName + "-intake-job"
    $makeDroneJob = Start-Job -Name $jobName -ScriptBlock $scriptBlock -ArgumentList $vmName,$blobURN,$destRG,$destSA,`
                                                                      $destContainer,$location,$Suffix,$NSG,`
                                                                      $vnetName,$subnetName
    if ($? -ne $true) {
        Write-Host "Error starting intake_machine job ($jobName) for $vmName.  This VM must be manually examined!!" -ForegroundColor red
        Stop-Transcript
        exit 1
    }

    Write-Host "Just launched job $jobName"
}

$notDone = $true
while ($notDone -eq $true) {
    write-host "Status at "@(date)"is:" -ForegroundColor Green
    $notDone = $false
    foreach ($vmName in $vmNameArray) {
        $jobName=$vmName + "-intake-job"
        $job = get-job $jobName
        $jobState = $job.State
        write-host "    Job $jobName is in state $jobState" -ForegroundColor Yellow
        if ($jobState -eq "Running") {
            $notDone = $true
        } else {
            get-job $jobName | Receive-Job
        }
    }
    sleep 10
}

#
#  Exit with error if we failed to create the VM.  THe setup may have failed, but we can't tell that right ow
exit 0