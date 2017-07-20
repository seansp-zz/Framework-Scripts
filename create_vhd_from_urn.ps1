param (
    [Parameter(Mandatory=$true)] [string] $vmName="Unset",
    [Parameter(Mandatory=$true)] [string] $blobURN="Unset",

    [Parameter(Mandatory=$false)] [string] $destRG="jpl_intake_rg",
    [Parameter(Mandatory=$false)] [string] $destSA="jplintakestorageacct",
    [Parameter(Mandatory=$false)] [string] $destContainer="ready-for-bvt",

    [Parameter(Mandatory=$false)] [string] $cleanContainer="original-images"
)

. "C:\Framework-Scripts\common_functions.ps1"
    
$vnetName="JPL-VNet-1"
$subnetName="JPL-Subnet-1"

login_azure $resourceGroup $SA

# Global
$location = "westus"

## Storage
$storageType = "Standard_D2"

## Network
$nicname = $name + "-NIC"
$subnet1Name = "JPS-Subnet-1"
$vnetName = "JPL-VNet-1"
$vnetAddressPrefix = "10.0.0.0/16"
$vnetSubnetAddressPrefix = "10.0.0.0/24"

## Compute

$vmSize = "Standard_A2"

Write-Host "Clearing any old images..." -ForegroundColor Green
Get-AzureStorageBlob -Container $destContainer -Prefix $vmName | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $destContainer}

Write-Host "Attempting to create virtual machine $vmName.  This may take some time." -ForegroundColor Green
az vm create -n $vmName -g $resourceGroup -l $location --image $blobURN --storage-container-name $destContainer --use-unmanaged-disk --nsg $NSG `
   --subnet $subnet1Name --vnet-name $vnetName  --storage-account $SA --os-disk-name $vmName --admin-password 'P@ssW0rd-1_K6' --admin-username "mstest" `
   --authentication-type "password"