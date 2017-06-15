##############################################################
#
#  Microsoft Linux Kernel Build and Validation Pipeline
#
#  Script Name:  create_vm_from_vhd
#
#  Script Summary:  This script will create a VHD in Azure
#         assigned to the azuresmokeresourcegroup so it can be
#         discovered by the download monitoring job.
#
##############################################################
param (
    [Parameter(Mandatory=$true)]
    [string] $blobName=""
)

$vhdFileName = $blobName
$vhdFile = $vhdFileName + ".vhd"

$resourceGroup = "azureSmokeResourceGroup"
$rg=$resourceGroup
$nm="azuresmokestoragesccount"
$location = "westus"
$vmName = "azureSmokeVM-1"
$cn="vhds"

write-host "Importing the context and setting the account..."
Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'
Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4"
Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $nm

Write-Host "Getting the container and setting up the user"
$c = Get-AzureStorageContainer -Name $cn
$sas = $c | New-AzureStorageContainerSASToken -Permission rwdl
$blobuploadURIRaw = $c.CloudBlobContainer.Uri.ToString() + "/" + $vhdFile 

$securePassword = ConvertTo-SecureString 'P@$$w0rd!' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ("mstest", $securePassword)
$cred2 = New-Object System.Management.Automation.PSCredential ("jfawcett", $securePassword)

write-host "Creating the public IP address..."
$pip = New-AzureRmPublicIpAddress -ResourceGroupName $rg -Location $location -Name $vhdFileName -AllocationMethod Dynamic -IdleTimeoutInMinutes 4
write-host "Getting the existing virtual network, subnet, and NSG"
$VMVNETObject = Get-AzureRmVirtualNetwork -Name SmokeVNet -ResourceGroupName $rg
$VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name SmokeSubnet-1 -VirtualNetwork $VMVNETObject
$nsgObject = Get-AzureRmNetworkSecurityGroup -ResourceGroupName $rg -name SmokeNSG
write-host "Creating the NIC"
$VNIC = New-AzureRmNetworkInterface -Name $vhdFileName -ResourceGroupName $rg -Location westus -SubnetId $VMSubnetObject.Id -publicipaddressid $pip.Id -NetworkSecurityGroupId $nsgObject.Id

$sshPublicKey="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC4JIoy6xOt+zkw73tNOs7+6pDJi02fkQndTdjcEkG0LwOr1su9s3evV+O59/ZcumP9uo5zZLKPA1IHT0LuZlaEzq6s978bw1c6v5E/AefM00hwsiAwsQD+RWe0F70F4ayqlsMVfb6MBbykyu1JtoXkAeiYHhsw4sVw9PZfzowAgXhTjWaGOo/vmG4YcwghUM/SrSuNH+jcoUz+T2T8RwfB+zvIMwWjsA0S18ZU7ZUjIEED/ansbcJ5umL7kxftKe3Njes3GvQDIUThBDuJs5IDp+CqwwwjHqgWFBgE3EITwqGeZheuRX+mQ3YuR2G52dqUhySUiLwnr4RtHBo5p59j"

write-host "Creating the VM.  This usually takes a few minutes.  It will be running when we're done."

az login --service-principal -u 58cfc776-5d1b-4872-bcdb-08ce60b9a66c --tenant 72f988bf-86f1-41af-91ab-2d7cd011db47 --password 'P@{P@$$w0rd!}w0rd!'
az vm create -g $rg -n $vhdFileName --image $blobuploadURIRaw --generate-ssh-keys --os-type Linux --use-unmanaged-disk --nics $VNIC.Id --size 'Standard_DS2_V2' `
             --location westus --public-ip-address-allocation dynamic --public-ip-address-dns-name $vhdFileName --storage-account $nm  `
             --ssh-dest-key-path '/home/jfawcett/.ssh/authorized_keys' --ssh-key-value $sshPublicKey