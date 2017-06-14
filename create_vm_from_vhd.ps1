param (
    [Parameter(Mandatory=$true)]
    [string] $vhdFile="",
    [Parameter(Mandatory=$true)]
    [string] $vhdFileName=""
)


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

write-host "Creating the VM.  This usually takes a few minutes.  It will be running when we're done."

az login --service-principal -u 58cfc776-5d1b-4872-bcdb-08ce60b9a66c --tenant 72f988bf-86f1-41af-91ab-2d7cd011db47 --password 'P@{P@$$w0rd!}w0rd!'
az vm create -g $rg -n $vhdFileName --image $blobuploadURIRaw --generate-ssh-keys --os-type Linux --use-unmanaged-disk --nics $VNIC.Id --size 'Standard_DS2_V2' `
             --location westus --public-ip-address-allocation dynamic --public-ip-address-dns-name $vhdFileName --storage-account $nm  `
             --ssh-dest-key-path '/home/jfawcett/.ssh/authorized_keys' --ssh-key-value $sshPublicKey