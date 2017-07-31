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
Start-Transcript C:\temp\transcripts\create_vhd_from_urn_$vmName.log

. "C:\Framework-Scripts\common_functions.ps1"
. "C:\Framework-Scripts\secrets.ps1"

Write-Host "Working with RG $destRG and SA $destSA"
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

#
#  Yes, these are done sequentially, not in parallel.  I will figure that out later :)
#
$i = 0
while ($i -lt $vmNameArray.Length) {
    $vmName = $vmNameArray[$i]
    $blobURN = $blobURNArray[$i]
    $i++
    Write-Host "Preparing machine $vmName for service as a drone..."

    Write-Host "Stopping any running VMs" -ForegroundColor Green
    Get-AzureRmVm -ResourceGroupName $destRG -status | Where-Object -Property Name -Like "$vmName*" | where-object -Property PowerState -eq -value "VM running" | Stop-AzureRmVM -Force

    echo "Deleting any existing VM"
    Get-AzureRmVm -ResourceGroupName $destRG -status | Where-Object -Property Name -Like "$vmName*" | Remove-AzureRmVM -Force

    Write-Host "Clearing any old images in $destContainer with prefix $vmName..." -ForegroundColor Green
    Get-AzureStorageBlob -Container $destContainer -Prefix $vmName | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $destContainer}

    Write-Host "Attempting to create virtual machine $vmName.  This may take some time." -ForegroundColor Green
    Write-Host "User is $TEST_USER_ACCOUNT_NAME"
    Write-Host "Password is $TEST_USER_ACCOUNT_PAS2"
    $diskName=$vmName + $suffix
    write-host "Creating machine $vmName"
    $pw = convertto-securestring -AsPlainText -force -string "$TEST_USER_ACCOUNT_PASS" 
    [System.Management.Automation.PSCredential]$cred = new-object -typename system.management.automation.pscredential -argumentlist "$TEST_USER_ACCOUNT_NAME",$pw

    az vm create -n $vmName -g $destRG -l $location --image $blobURN --storage-container-name $destContainer --use-unmanaged-disk --nsg $NSG `
       --subnet $subnetName --vnet-name $vnetName  --storage-account $destSA --os-disk-name $diskName --admin-password 'P@ssW0rd-1_K6' `
       --admin-username mstest --authentication-type password

    if ($? -eq $false) {
        Write-Error "Failed to create VM.  Details follow..."
        Stop-Transcript
        exit 1
    }

    #
    #  Disable Cloud-Init so it doesn't try to deprovision the machine (known bug in Azure)
    write-host "Attempting to contact the machine..."
    $pipName = $vmName + "PublicIP"
    $ip=(Get-AzureRmPublicIpAddress -ResourceGroupName $destRG -Name $pipName).IpAddress
    $password='P@ssW0rd-1_K6'
    $port=22
    $username="$TEST_USER_ACCOUNT_NAME"

    $disableCommand1="systemctl enable cloud-config.service"
    $disableCommand2="systemctl enable cloud-final.service"
    $disableCommand3="systemctl enable cloud-init-local.service"
    $disableCommand4="systemctl enable cloud-init.service"

    $runDisableCommand1="`"echo $password | sudo -S bash -c `'$disableCommand1`'`""
    $runDisableCommand2="`"echo $password | sudo -S bash -c `'$disableCommand2`'`""
    $runDisableCommand3="`"echo $password | sudo -S bash -c `'$disableCommand3`'`""
    $runDisableCommand4="`"echo $password | sudo -S bash -c `'$disableCommand4`'`""

    #
    #  Eat the prompt and get the host into .known_hosts
    while ($true) {
        $sslReply=@(echo "y" | C:\azure-linux-automation\tools\pscp C:\Framework-Scripts\README.md "$username@$ip"`:/tmp)
        echo "SSL Rreply is $sslReply"
        if ($sslReply -match "password:" ) {
            Write-Host "Got a key request"
            break
        } else {
            Write-Host "No match"
            sleep(10)
        }
    }
    $sslReply=@(echo "y" | C:\azure-linux-automation\tools\pscp C:\Framework-Scripts\README.md $username@$ip`:/tmp)

    #
    C:\azure-linux-automation\tools\plink.exe -C -v -pw $password -P $port "$username@$ip" $runDisableCommand1

    #
    C:\azure-linux-automation\tools\plink.exe -C -v -pw $password -P $port "$username@$ip" $runDisableCommand2

    C:\azure-linux-automation\tools\plink.exe -C -v -pw $password -P $port "$username@$ip" $runDisableCommand3

    C:\azure-linux-automation\tools\plink.exe -C -v -pw $password -P $port "$username@$ip" $runDisableCommand4
    
    Write-Host "VM Created successfully.  Stopping it now..."
    Stop-AzureRmVM -ResourceGroupName $destRG -Name $vmName -Force

    # Write-Host "Deleting the VM so we can harvest the VHD..."
    # Remove-AzureRmVM -ResourceGroupName $destRG -Name $diskName -Force

    Write-Host "Machine $vmName is ready for assimilation..."
}
Stop-Transcript