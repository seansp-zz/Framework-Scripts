param (
    [Parameter(Mandatory=$true)] [string] $name
)
$rg="azuresmokeresourcegroup"
$nm="azuresmokestorageaccount"  
$destContainerName = "safe-templates"

Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'
Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4"
Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $nm

## Global
$rgName = "azuresmokeresourcegroup"
$location = "westus"

## Storage
$storageName = "azuresmokestorageaccount"
$storageType = "Standard_D2"

## Network
$nicname = $name + "-Smoke-1NIC"
$subnet1Name = "SmokeSubnet-1"
$vnetName = "SmokeVNet"
$vnetAddressPrefix = "10.0.0.0/16"
$vnetSubnetAddressPrefix = "10.0.0.0/24"

## Compute
$vmName = $name + "-Smoke-1"
$vmSize = "Standard_A2"
$osDiskName = $vmName + "-osDisk"
$blobURIRaw="https://azuresmokestorageaccount.blob.core.windows.net/clean-vhds/" + $name + "-Smoke-1.vhd"
Get-AzureStorageBlob -Container $destContainerName -Prefix $name | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $destContainerName}
$destUri = $blobURIRaw.Replace("clean-vhds","safe-templates")

## Setup local VM object
# $cred = Get-Credential
az vm create -n $vmName -g $rgName -l $location --os-type linux --image $blobURIRaw --storage-container-name "safe-templates" --use-unmanaged-disk --nsg SmokeNSG `
    --subnet SmokeSubnet-1 --vnet-name SmokeVNet --storage-account azuresmokestorageaccount --os-disk-name $vmName
