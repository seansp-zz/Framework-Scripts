param (
    [Parameter(Mandatory=$false)] [string[]] $vmNames,
    [Parameter(Mandatory=$false)] [string[]] $blobURNs,

    [Parameter(Mandatory=$false)] [string] $destRG="jpl_intake_rg",
    [Parameter(Mandatory=$false)] [string] $destSA="jplintakestorageacct",
    [Parameter(Mandatory=$false)] [string] $destContainer="ready-for-bvt",
    [Parameter(Mandatory=$false)] [string] $location="westus",

    [Parameter(Mandatory=$false)] [string] $vnetName = "SmokeVNet",
    [Parameter(Mandatory=$false)] [string] $subnetName = "SmokeSubnet-1",
    [Parameter(Mandatory=$false)] [string] $NSG = "SmokeNSG",

    [Parameter(Mandatory=$false)] [string] $suffix = "-Smoke-1"
)
$vmNameArray = $vmNames
$blobURNArray = $blobURNs

Write-Host "Names array: " $vmNameArray
$numNames = $vmNameArray.Length
Write-Host "blobs array: " $blobURNArray
$numBlobs = $blobURNs.Length

if ($vmNameArray.Length -ne $blobURNs.Length) {
    Write-Host "Please provide the same number of names and URNs. You have $numNames names and $numBlobs blobs"
    exit 1
} else {
    Write-Host "There are $vmNameArray.Length left..."
}
$vmName = $vmNames[0]
Start-Transcript C:\temp\transcripts\create_vhd_from_urn_$vmNames[0].log

. "C:\Framework-Scripts\common_functions.ps1"
. "C:\Framework-Scripts\secrets.ps1"

Write-Host "Working with RG $destRG and SA $destSA"
login_azure $destRG $destSA

# Global
$location = "westus"

## Storage
$storageType = "Standard_D2"

## Network
$nicname = $vmName + "-NIC"

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

    Write-Host "Clearing any old images..." -ForegroundColor Green
    Get-AzureStorageBlob -Container $destContainer -Prefix $vmName | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $destContainer}

    Write-Host "Attempting to create virtual machine $vmName.  This may take some time." -ForegroundColor Green
    Write-Host "User is $TEST_USER_ACCOUNT_NAME"
    Write-Host "Password is $TEST_USER_ACCOUNT_PAS2"
    $diskName=$vmName + $suffix
    write-host "Creating machine $vmName"
    az vm create -n $vmName -g $destRG -l $location --image $blobURN --storage-container-name $destContainer --use-unmanaged-disk --nsg $NSG `
       --subnet $subnetName --vnet-name $vnetName  --storage-account $destSA --os-disk-name $diskName --admin-password `'$TEST_USER_ACCOUNT_PAS2`' --admin-username $TEST_USER_ACCOUNT_NAME `
       --authentication-type "password"

    if ($? -eq $false) {
        Write-Error "Failed to create VM.  Details follow..."
        Stop-Transcript
        exit 1
    }
    Write-Host "VM Created successfully.  Stopping it now..."
    # Stop-AzureRmVM -ResourceGroupName $destRG -Name $diskName -Force

    # Write-Host "Deleting the VM so we can harvest the VHD..."
    # Remove-AzureRmVM -ResourceGroupName $destRG -Name $diskName -Force

    Write-Host "Machine $vmName is ready for assimilation..."
}
Stop-Transcript