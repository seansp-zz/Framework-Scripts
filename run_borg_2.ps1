#
#  THIS IS A WINDOWS POWERSHELL SCRIPT!!  IT ONLY WORKS ON WINDOWS!!
#
# Variables for common values
$resourceGroup = "azureSmokeResourceGroup"
$rg=$resourceGroup
$nm="azuresmokestoragesccount"
$location = "westus"
$vmName = "azureSmokeVM-1"

echo "********************************************************************"
echo "*              BORG, Phase II -- Assimilation by Azure             *"
echo "********************************************************************"

# Login-AzureRmAccount -Credential $cred
$tempRg1CentOS="azureTempResourceGroup-4"
$tempRg1Ubuntu="azureTempResourceGroup-4A"
$tempRg2CentOS="azureTempResourceGroupSecond-4"
$tempRg2Ubuntu="azureTempResourceGroupSecond-4A"
$cn="azuresmokecontainer"

$centdiskname="osdev64-cent7"
$centdiskUri="https://$nm.blob.core.windows.net/$cn/osdev64-cent7.vhd"
$CentOSimageName="CentMSKernelTestImage"

$ubundiskname="ubun16x64dev"
$ubundiskUri="https://$nm.blob.core.windows.net/$cn/ubun16x64dev.vhd"
$UbuntuimageName="UbuntuMSKernelTestImage"

echo "Importing the context...."
Import-AzureRmContext -Path 'D:\Boot-Ready Images\ProfileContext.ctx'

echo "Selecting the Azure subscription..."
Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4"

echo "Removing old resource groups."
echo "First, $tempRg1CentOS"
Remove-AzureRmResourceGroup -Name $tempRg1CentOS -Force
Remove-AzureRmResourceGroup -Name $tempRg1Ubuntu -Force
echo "Then, $tempRg2CentOS"
Remove-AzureRmResourceGroup -Name $tempRg2CentOS -Force
Remove-AzureRmResourceGroup -Name $tempRg2Ubuntu -Force
echo "Whew!  That was painful.  Note to self -- make sure we have to do all of those"

echo "Setting the Azure Storage Account"
# New-AzureRmStorageAccount -ResourceGroupName $rg -Name $nm -Location westus -SkuName "Standard_LRS" -Kind "Storage"
Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $nm

# $azureCentOSSourceImage="https://azuresmokestoragesccount.blob.core.windows.net/azuresmokecontainer/osdev64-cent7.vhd"
$azureCentOSTargetImage="/osdev64-cent7.vhd"
$azureCentOSDiskImage='D:\Exported Images\CentOS 7.1 MSLK Test 1\Virtual Hard Disks\osdev64-cent7.vhd'
$hvCentOSVMName="CentOS 7.1 MSLK Test 1"
$CentOSvmName="CentOSSmoke1"
$CentOScomputerName="Cent71-mslk-test-1"

$azureUbuntuTargetImage="/ubun16x64dev.vhd"
$azureUbuntuDiskImage='D:\Exported Images\Ubuntu 1604 MSLK Test 1\Virtual Hard Disks\ubun16x64dev.vhd'
$hvUbuntuVMName="Ubuntu 1604 MSLK Test 1"
$UbuntuvmName="UbuntuSmoke1"
$UbuntucomputerName="Ubuntu-1604-mslk-test-1"

#
#  Create the checkpoint and snapshot
#
echo "Clearing the old VHD checkpoint directory"
remove-item "D:\Exported Images\*" -exclude ubuntu-1604-MSLK-Test-1 -recurse -force

echo "Stopping the running VMs"
Stop-VM -Name $hvCentOSVMName
Stop-VM -Name $hvUbuntuVMName

echo "Creating checkpoints..."

echo "First CentOS..."
Checkpoint-vm -Name $hvCentOSVMName -Snapshotname "Ready for Azure"
echo "CentOS Checkpoint created.  Exporting VM"
Export-VMSnapshot -name "Ready for Azure" -VMName $hvCentOSVMName -path 'D:\Exported Images\'

echo "Then Ubuntu..."
Checkpoint-vm -Name $hvUbuntuVMName -Snapshotname "Ready for Azure"
echo "Ubuntu Checkpoint created.  Exporting VM"
Export-VMSnapshot -name "Ready for Azure" -VMName $hvUbuntuVMName -path 'D:\Exported Images\'

#
#  Copy the blob to the storage container
$c = Get-AzureStorageContainer -Name $cn
$sas = $c | New-AzureStorageContainerSASToken -Permission rwdl
$CentOSblob = $c.CloudBlobContainer.Uri.ToString() + $azureCentOSTargetImage 
$CentOSuploadURI = $CentOSblob + $sas
echo "Uploading the CentOS VHD blob to the cloud"
Add-AzureRmVhd -Destination $CentOSuploadURI -LocalFilePath $azureCentOSDiskImage -NumberOfUploaderThreads 32
 
$Ubuntublob = $c.CloudBlobContainer.Uri.ToString() + $azureUbuntuTargetImage 
$UbuntuuploadURI = $Ubuntublob + $sas
echo "Uploading the Ubuntu VHD blob to the cloud"
Add-AzureRmVhd -Destination $UbuntuuploadURI -LocalFilePath $azureUbuntuDiskImage -NumberOfUploaderThreads 32

#
#  Go from generalized to specialized state for CentOS
#
echo "Setting the image on disk"
$CentOSimageConfig = New-AzureRmImageConfig -Location westus
Set-AzureRmImageOsDisk -Image $CentOSimageConfig -OsType "Linux" -OsState "Generalized" –BlobUri $CentOSblob

echo "Creating resource group $tempRg1CentOS"
New-AzureRmResourceGroup -Name $tempRg1CentOS -Location westus

echo "Creating the image"
New-AzureRmImage -ResourceGroupName $tempRg1CentOS -ImageName $CentOSimageName -Image $CentOSimageConfig

#
#  Go from generalized to specialized state for Ubuntu
#
echo "Setting the image on disk"
$UbuntuimageConfig = New-AzureRmImageConfig -Location westus
Set-AzureRmImageOsDisk -Image $UbuntuimageConfig -OsType "Linux" -OsState "Generalized" –BlobUri $Ubuntublob

echo "Creating resource group $tempRg1Ubuntu"
New-AzureRmResourceGroup -Name $tempRg1Ubuntu -Location westus

echo "Creating the image"
New-AzureRmImage -ResourceGroupName $tempRg1Ubuntu -ImageName $UbuntuimageName -Image $UbuntuimageConfig

#
#  Create the image from the VM
#
echo "Logging in to Azure for Azure CLI..."
az login --service-principal -u 58cfc776-5d1b-4872-bcdb-08ce60b9a66c --tenant 72f988bf-86f1-41af-91ab-2d7cd011db47 --password 'P@{P@$$w0rd!}w0rd!'

echo "Thank you.  Creating CentOS Azure VM..."
az vm create -g $tempRg1CentOS -n $CentOSvmName --image $CentOSimageName --generate-ssh-keys
az vm create -g $tempRg1Ubuntu -n $UbuntuvmName --image $UbuntuimageName --generate-ssh-keys

#
#  Try starting it up
#
$CentOSimage = Get-AzureRMImage -ImageName $CentOSimageName -ResourceGroupName $tempRg1CentOS

echo "Creating another resrouce group for the test.  This is $tempRg2CentOS"
New-AzureRmResourceGroup -Name $tempRg2CentOS -Location $location

echo "Configuring the system..."
echo "User and password..."
# Definer user name and blank password
$securePassword = ConvertTo-SecureString 'P@$$w0rd!' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ("azureuser", $securePassword)

# Create a subnet configuration
echo "Subnet..."
$subnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name smokeSubnet -AddressPrefix 10.0.0.0/24

# Create a virtual network
echo "Creating a virtual network"
$vnet = New-AzureRmVirtualNetwork -ResourceGroupName $tempRg2CentOS -Location $location `
  -Name SMOKEvNET -AddressPrefix 10.0.0.0/16 -Subnet $subnetConfig

# Create a public IP address and specify a DNS name
echo "Assigning a public IP address and giving DNS"
$pip = New-AzureRmPublicIpAddress -ResourceGroupName $tempRg2CentOS -Location $location `
  -Name "smokepip" -AllocationMethod Dynamic -IdleTimeoutInMinutes 4

# Create an inbound network security group rule for port 22
echo "Enabling port 22 for SSH"
$nsgRuleSSH = New-AzureRmNetworkSecurityRuleConfig -Name smokeNetworkSecurityGroupRuleSSH  -Protocol Tcp `
  -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * `
  -DestinationPortRange 22 -Access Allow

# Create an inbound network security group rule for port 443
echo "Enabling port 443 for OMI"
$nsgRuleOMI = New-AzureRmNetworkSecurityRuleConfig -Name smokeNetworkSecurityGroupRuleOMI  -Protocol Tcp `
  -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * `
  -DestinationPortRange 443 -Access Allow

# Create a network security group
echo "Creating a network security group"
$nsg = New-AzureRmNetworkSecurityGroup -ResourceGroupName $tempRg2CentOS -Location $location `
  -Name smokeNetworkSecurityGroup -SecurityRules $nsgRuleSSH,$nsgRuleOMI

# Create a virtual network card and associate with public IP address and NSG
echo "Creating a NIC"
$nic = New-AzureRmNetworkInterface -Name smokeNic -ResourceGroupName $tempRg2CentOS -Location $location `
  -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id


$vmSize = "Standard_DS1_v2"

echo "Creating the full VM configuration..."
$CentOSvm = New-AzureRmVMConfig -VMName $CentOSvmName -VMSize $vmSize

echo "Setting the VM source image..."
$CentOSvm = Set-AzureRmVMSourceImage -VM $CentOSvm -Id $CentOSimage.Id

echo "Setting the VM OS Source Disk...."
$CentOSvm = Set-AzureRmVMOSDisk -VM $CentOSvm  -StorageAccountType PremiumLRS -DiskSizeInGB 128 -CreateOption FromImage -Caching ReadWrite

echo "Setting the OS to Linux..."
$CentOSvm = Set-AzureRmVMOperatingSystem -VM $CentOSvm -Linux -Credential $cred -ComputerName $CentOScomputerName

echo "Adding the network interface..."
$CentOSvm = Add-AzureRmVMNetworkInterface -VM $CentOSvm -Id $nic.Id

echo "And launching the VM..."
New-AzureRmVM -VM $CentOSvm -ResourceGroupName $tempRg2CentOS -Location $location

#==================================================================
#
#  Try starting it up
#
$Ubuntuimage = Get-AzureRMImage -ImageName $UbuntuimageName -ResourceGroupName $tempRg1Ubuntu

echo "Creating another resrouce group for the test.  This is $tempRg2Ubuntu"
New-AzureRmResourceGroup -Name $tempRg2Ubuntu -Location $location

echo "Configuring the system..."
echo "User and password..."
# Definer user name and blank password
$securePassword = ConvertTo-SecureString 'P@$$w0rd!' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ("azureuser", $securePassword)

# Create a subnet configuration
echo "Subnet..."
$subnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name smokeSubnet -AddressPrefix 10.0.0.0/24

# Create a virtual network
echo "Creating a virtual network"
$vnet = New-AzureRmVirtualNetwork -ResourceGroupName $tempRg2Ubuntu -Location $location `
  -Name SMOKEvNET -AddressPrefix 10.0.0.0/16 -Subnet $subnetConfig

# Create a public IP address and specify a DNS name
echo "Assigning a public IP address and giving DNS"
$pip = New-AzureRmPublicIpAddress -ResourceGroupName $tempRg2Ubuntu -Location $location `
  -Name "smokepip" -AllocationMethod Dynamic -IdleTimeoutInMinutes 4

# Create an inbound network security group rule for port 22
echo "Enabling port 22 for SSH"
$nsgRuleSSH = New-AzureRmNetworkSecurityRuleConfig -Name smokeNetworkSecurityGroupRuleSSH  -Protocol Tcp `
  -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * `
  -DestinationPortRange 22 -Access Allow

# Create an inbound network security group rule for port 443
echo "Enabling port 443 for OMI"
$nsgRuleOMI = New-AzureRmNetworkSecurityRuleConfig -Name smokeNetworkSecurityGroupRuleOMI  -Protocol Tcp `
  -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * `
  -DestinationPortRange 443 -Access Allow

# Create a network security group
echo "Creating a network security group"
$nsg = New-AzureRmNetworkSecurityGroup -ResourceGroupName $tempRg2Ubuntu -Location $location `
  -Name smokeNetworkSecurityGroup -SecurityRules $nsgRuleSSH,$nsgRuleOMI

# Create a virtual network card and associate with public IP address and NSG
echo "Creating a NIC"
$nic = New-AzureRmNetworkInterface -Name smokeNic -ResourceGroupName $tempRg2Ubuntu -Location $location `
  -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id


$vmSize = "Standard_DS1_v2"

echo "Creating the full VM configuration..."
$Ubuntuvm = New-AzureRmVMConfig -VMName $UbuntuvmName -VMSize $vmSize

echo "Setting the VM source image..."
$Ubuntuvm = Set-AzureRmVMSourceImage -VM $Ubuntuvm -Id $Ubuntuimage.Id

echo "Setting the VM OS Source Disk...."
$Ubuntuvm = Set-AzureRmVMOSDisk -VM $Ubuntuvm  -StorageAccountType PremiumLRS -DiskSizeInGB 128 -CreateOption FromImage -Caching ReadWrite

echo "Setting the OS to Linux..."
$Ubuntuvm = Set-AzureRmVMOperatingSystem -VM $Ubuntuvm -Linux -Credential $cred -ComputerName $UbuntucomputerName

echo "Adding the network interface..."
$Ubuntuvm = Add-AzureRmVMNetworkInterface -VM $Ubuntuvm -Id $nic.Id

echo "And launching the VM..."
New-AzureRmVM -VM $Ubuntuvm -ResourceGroupName $tempRg2Ubuntu -Location $location

#================================================

#
#  Machine should now be up.  Get the version
#
$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$pw=convertto-securestring -AsPlainText -force -string 'P@$$w0rd!'
$cred=new-object -typename system.management.automation.pscredential -argumentlist "azureuser",$pw

$CentOSip=Get-AzureRmPublicIpAddress -ResourceGroupName $tempRg2CentOS
$CentOSs=new-PSSession -computername $CentOSip.IpAddress -credential $cred -authentication Basic -UseSSL -Port 443 -SessionOption $o
$CentOS_installed_vers=invoke-command -session $CentOSs -ScriptBlock {/bin/uname -r}
remove-pssession $CentOSs

$Ubuntuip=Get-AzureRmPublicIpAddress -ResourceGroupName $tempRg2Ubuntu 
$Ubuntus=new-PSSession -computername $Ubuntuip.IpAddress -credential $cred -authentication Basic -UseSSL -Port 443 -SessionOption $o
$Ubuntu_installed_vers=invoke-command -session $Ubuntus -ScriptBlock {/bin/uname -r}
remove-pssession $Ubuntus

$expected_boot=Get-Content C:\temp\centos-boot
$expected_ver=$expected_boot.split(" ")[1]

echo "Stopping the VMs"
Stop-AzureRmVm -force -ResourceGroupName $tempRg1CentOS -name $CentOSvmName
Stop-AzureRmVm -force -ResourceGroupName $tempRg1Ubuntu -name $UbuntuvmName
Stop-AzureRmVm -force -ResourceGroupName $tempRg2CentOS -name $CentOSvmName
Stop-AzureRmVm -force -ResourceGroupName $tempRg2Ubuntu -name $UbuntuvmName

#
#  Removing the resource groups takes a long time, and I'd like to know how it went...
#
if (($expected_ver.CompareTo($CentOS_installed_vers) -eq 0) -and ($expected_ver.CompareTo($Ubuntu_installed_vers) -eq 0)) {
    echo "Success!"
} else {
    echo "Failure"
}

#
#  Clean up
#
echo "Removing resource groups."
echo "First, $tempRg1CentOS"
Remove-AzureRmResourceGroup -Name $tempRg1CentOS -Force
Remove-AzureRmResourceGroup -Name $tempRg1Ubuntu -Force
echo "Then, $tempRg2CentOS"
Remove-AzureRmResourceGroup -Name $tempRg2CentOS -Force
Remove-AzureRmResourceGroup -Name $tempRg2Ubuntu -Force

#
#  Now, check for success
#
if (($expected_ver.CompareTo($CentOS_installed_vers) -eq 0) -and ($expected_ver.CompareTo($Ubuntu_installed_vers) -eq 0)) {
    exit 0
} else {
    exit 1
}
