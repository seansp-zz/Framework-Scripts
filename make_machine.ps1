$rg="azuresmokeresourcegroup"
$nm="azuresmokestorageaccount"  
$destContainerName = "safe-templates"
$name="Ubuntu1604"

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
$destUri = $blobURIRaw.Replace("clean-vhds","safe-templates")
$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$pw=convertto-securestring -AsPlainText -force -string 'P@$$w0rd!'
$cred=new-object -typename system.management.automation.pscredential -argumentlist "mstest",$pw

$vnet = Get-AzureRmVirtualNetwork -Name SmokeVNet -ResourceGroupName $rg
$subnetconfig = Get-AzureRmVirtualNetworkSubnetConfig -Name $subnet1Name -VirtualNetwork $vnet

$pip = New-AzureRmPublicIpAddress -Name $nicname -ResourceGroupName $rgName -Location $location -AllocationMethod Dynamic
$nic = New-AzureRmNetworkInterface -Name $nicname -ResourceGroupName $rgName -Location $location -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id

$existingBlob=Get-AzureStorageBlob -Container "safe-templates" -Prefix $nicname
if ($? -eq $true) {
    Remove-AzureStorageBlob -Blob $existingBlob -Container $destContainer
}

## Setup local VM object
# $cred = Get-Credential
$vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize
$vm = Set-AzureRmVMOperatingSystem -VM $vm -Linux -ComputerName $vmName -Credential $cred
$vm = Set-AzureRmVMOSDisk -vm $vm -name $vmName -SourceImageUri $blobURIRaw -VhdUri $destUri -CreateOption FromImage -Linux
$vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $nic.Id

$NEWVM = New-AzureRmVM -ResourceGroupName $rgName -Location westus -VM $vm -verbose