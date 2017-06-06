#
#  THIS IS A WINDOWS POWERSHELL SCRIPT!!  IT ONLY WORKS ON WINDOWS!!
#
# Variables for common values
$resourceGroup = "azureSmokeResourceGroup"
$rg=$resourceGroup
$nm="azuresmokestoragesccount"
$location = "westus"
$vmName = "azureSmokeVM-1"

write-host "********************************************************************" -ForegroundColor green
write-host "*              BORG, Phase II -- Assimilation by Azure             *" -ForegroundColor green
write-host "********************************************************************" -ForegroundColor green

# Login-AzureRmAccount -Credential $cred
$tempRg1CentOS="azureTempResourceGroup-1"
$tempRg1Ubuntu="azureTempResourceGroup-1A"
$tempRg2CentOS="azureTempResourceGroupSecond-1"
$tempRg2Ubuntu="azureTempResourceGroupSecond-1A"
$cn="azuresmokestoragecontainer"

$centdiskname="osdev64-cent7"
$centdiskUri="https://$nm.blob.core.windows.net/$cn/osdev64-cent7.vhd"
$CentOSimageName="CentMSKernelTestImage"

$ubundiskname="ubun16x64dev"
$ubundiskUri="https://$nm.blob.core.windows.net/$cn/ubun16x64dev.vhd"
$UbuntuimageName="UbuntuMSKernelTestImage"

write-host "Clearing the old VHD checkpoint directory" -ForegroundColor green
remove-item "D:\Exported Images\*" -exclude ubuntu-1604-MSLK-Test-1 -recurse -force

write-host "Importing the context...." -ForegroundColor green
Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'

write-host "Selecting the Azure subscription..." -ForegroundColor green
Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4"

write-host "Removing old resource groups.  These should all fail" -ForegroundColor green
write-host "First, $tempRg1CentOS" -ForegroundColor magenta
Remove-AzureRmResourceGroup -Name $tempRg1CentOS -Force
Remove-AzureRmResourceGroup -Name $tempRg1Ubuntu -Force
write-host "Then, $tempRg2CentOS" -ForegroundColor cyan
Remove-AzureRmResourceGroup -Name $tempRg2CentOS -Force
Remove-AzureRmResourceGroup -Name $tempRg2Ubuntu -Force

write-host "Setting the Azure Storage Account" -ForegroundColor green
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
write-host "Creating VM snapshots..." -ForegroundColor green

write-host "First CentOS..." -ForegroundColor green
Export-VMSnapshot -name "Ready for Azure" -VMName $hvCentOSVMName -path 'D:\Exported Images\'

write-host "Then Ubuntu..." -ForegroundColor green
Export-VMSnapshot -name "Ready for Azure" -VMName $hvUbuntuVMName -path 'D:\Exported Images\'

#
#  Clear anything in the storage container
#
Get-AzureStorageBlob -Container $cn -blob * | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $cn}

#
#  Copy the blob to the storage container
$c = Get-AzureStorageContainer -Name $cn
$sas = $c | New-AzureStorageContainerSASToken -Permission rwdl
$CentOSblob = $c.CloudBlobContainer.Uri.ToString() + $azureCentOSTargetImage 
$CentOSuploadURI = $CentOSblob + $s
write-host "Uploading the CentOS VHD blob to the cloud" -ForegroundColor magenta
Add-AzureRmVhd –ResourceGroupName $rg -Destination $CentOSuploadURI -LocalFilePath $azureCentOSDiskImage -OverWrite
 
$Ubuntublob = $c.CloudBlobContainer.Uri.ToString() + $azureUbuntuTargetImage 
$UbuntuuploadURI = $Ubuntublob + $sas
write-host "Uploading the Ubuntu VHD blob to the cloud" -ForegroundColor cyan
Add-AzureRmVhd –ResourceGroupName $rg -Destination $UbuntuuploadURI -LocalFilePath $azureUbuntuDiskImage -OverWrite

#
#  Go from generalized to specialized state for CentOS
#
write-host "Setting the image on disk" -ForegroundColor magenta
$CentOSimageConfig = New-AzureRmImageConfig -Location westus
Set-AzureRmImageOsDisk -Image $CentOSimageConfig -OsType "Linux" -OsState "Generalized" –BlobUri $CentOSblob

write-host "Creating resource group $tempRg1CentOS" -ForegroundColor magenta
New-AzureRmResourceGroup -Name $tempRg1CentOS -Location westus

write-host "Creating the image" -ForegroundColor magenta
New-AzureRmImage -ResourceGroupName $tempRg1CentOS -ImageName $CentOSimageName -Image $CentOSimageConfig

#
#  Go from generalized to specialized state for Ubuntu
#
write-host "Setting the image on disk" -ForegroundColor cyan
$UbuntuimageConfig = New-AzureRmImageConfig -Location westus
Set-AzureRmImageOsDisk -Image $UbuntuimageConfig -OsType "Linux" -OsState "Generalized" –BlobUri $Ubuntublob

write-host "Creating resource group $tempRg1Ubuntu" -ForegroundColor cyan
New-AzureRmResourceGroup -Name $tempRg1Ubuntu -Location westus

write-host "Creating the image" -ForegroundColor cyan
New-AzureRmImage -ResourceGroupName $tempRg1Ubuntu -ImageName $UbuntuimageName -Image $UbuntuimageConfig

#
#  Create the image from the VM
#
write-host "Logging in to Azure for Azure CLI..." -ForegroundColor green
az login --service-principal -u 58cfc776-5d1b-4872-bcdb-08ce60b9a66c --tenant 72f988bf-86f1-41af-91ab-2d7cd011db47 --password 'P@{P@$$w0rd!}w0rd!'

write-host "Thank you.  Creating CentOS Azure VM..." -ForegroundColor magenta
az vm create -g $tempRg1CentOS -n $CentOSvmName --image $CentOSimageName --generate-ssh-keys

write-host "Creating Ubuntu Azure VM..." -ForegroundColor cyan
az vm create -g $tempRg1Ubuntu -n $UbuntuvmName --image $UbuntuimageName --generate-ssh-keys

#
#  Try starting it up
#
$CentOSimage = Get-AzureRMImage -ImageName $CentOSimageName -ResourceGroupName $tempRg1CentOS

write-host "Creating another resrouce group for the test.  This is $tempRg2CentOS" -ForegroundColor magenta
New-AzureRmResourceGroup -Name $tempRg2CentOS -Location $location

write-host "Configuring the system..." -ForegroundColor magenta
write-host "User and password..." -ForegroundColor magenta
# Definer user name and blank password
$securePassword = ConvertTo-SecureString 'P@$$w0rd!' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ("azureuser", $securePassword)

# Create a subnet configuration
write-host "Subnet..." -ForegroundColor magenta
$subnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name smokeSubnet -AddressPrefix 10.0.0.0/24

# Create a virtual network
write-host "Creating a virtual network" -ForegroundColor magenta
$vnet = New-AzureRmVirtualNetwork -ResourceGroupName $tempRg2CentOS -Location $location `
  -Name SMOKEvNET -AddressPrefix 10.0.0.0/16 -Subnet $subnetConfig

# Create a public IP address and specify a DNS name
write-host "Assigning a public IP address and giving DNS" -ForegroundColor magenta
$pip = New-AzureRmPublicIpAddress -ResourceGroupName $tempRg2CentOS -Location $location `
  -Name "smokepip" -AllocationMethod Dynamic -IdleTimeoutInMinutes 4

# Create an inbound network security group rule for port 22
write-host "Enabling port 22 for SSH" -ForegroundColor magenta
$nsgRuleSSH = New-AzureRmNetworkSecurityRuleConfig -Name smokeNetworkSecurityGroupRuleSSH  -Protocol Tcp `
  -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * `
  -DestinationPortRange 22 -Access Allow

# Create an inbound network security group rule for port 443
write-host "Enabling port 443 for OMI" -ForegroundColor magenta
$nsgRuleOMI = New-AzureRmNetworkSecurityRuleConfig -Name smokeNetworkSecurityGroupRuleOMI  -Protocol Tcp `
  -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * `
  -DestinationPortRange 443 -Access Allow

# Create a network security group
write-host "Creating a network security group" -ForegroundColor magenta
$nsg = New-AzureRmNetworkSecurityGroup -ResourceGroupName $tempRg2CentOS -Location $location `
  -Name smokeNetworkSecurityGroup -SecurityRules $nsgRuleSSH,$nsgRuleOMI

# Create a virtual network card and associate with public IP address and NSG
write-host "Creating a NIC" -ForegroundColor magenta
$nic = New-AzureRmNetworkInterface -Name smokeNic -ResourceGroupName $tempRg2CentOS -Location $location `
  -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id


$vmSize = "Standard_DS1_v2"

write-host "Creating the full VM configuration..." -ForegroundColor magenta
$CentOSvm = New-AzureRmVMConfig -VMName $CentOSvmName -VMSize $vmSize

write-host "Setting the VM source image..." -ForegroundColor magenta
$CentOSvm = Set-AzureRmVMSourceImage -VM $CentOSvm -Id $CentOSimage.Id

write-host "Setting the VM OS Source Disk...." -ForegroundColor magenta
$CentOSvm = Set-AzureRmVMOSDisk -VM $CentOSvm  -StorageAccountType PremiumLRS -DiskSizeInGB 128 -CreateOption FromImage -Caching ReadWrite

write-host "Setting the OS to Linux..." -ForegroundColor magenta
$CentOSvm = Set-AzureRmVMOperatingSystem -VM $CentOSvm -Linux -Credential $cred -ComputerName $CentOScomputerName

write-host "Adding the network interface..." -ForegroundColor magenta
$CentOSvm = Add-AzureRmVMNetworkInterface -VM $CentOSvm -Id $nic.Id

write-host "And launching the VM..." -ForegroundColor magenta
New-AzureRmVM -VM $CentOSvm -ResourceGroupName $tempRg2CentOS -Location $location

#==================================================================
#
#  Try starting it up
#
$Ubuntuimage = Get-AzureRMImage -ImageName $UbuntuimageName -ResourceGroupName $tempRg1Ubuntu

write-host "Creating another resrouce group for the test.  This is $tempRg2Ubuntu" -ForegroundColor cyan
New-AzureRmResourceGroup -Name $tempRg2Ubuntu -Location $location

write-host "Configuring the system..." -ForegroundColor cyan
write-host "User and password..." -ForegroundColor cyan
# Definer user name and blank password
$securePassword = ConvertTo-SecureString 'P@$$w0rd!' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ("azureuser", $securePassword)

# Create a subnet configuration
write-host "Subnet..." -ForegroundColor cyan
$subnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name smokeSubnet -AddressPrefix 10.0.0.0/24

# Create a virtual network
write-host "Creating a virtual network" -ForegroundColor cyan
$vnet = New-AzureRmVirtualNetwork -ResourceGroupName $tempRg2Ubuntu -Location $location `
  -Name SMOKEvNET -AddressPrefix 10.0.0.0/16 -Subnet $subnetConfig

# Create a public IP address and specify a DNS name
write-host "Assigning a public IP address and giving DNS" -ForegroundColor cyan
$pip = New-AzureRmPublicIpAddress -ResourceGroupName $tempRg2Ubuntu -Location $location `
  -Name "smokepip" -AllocationMethod Dynamic -IdleTimeoutInMinutes 4

# Create an inbound network security group rule for port 22
write-host "Enabling port 22 for SSH" -ForegroundColor cyan
$nsgRuleSSH = New-AzureRmNetworkSecurityRuleConfig -Name smokeNetworkSecurityGroupRuleSSH  -Protocol Tcp `
  -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * `
  -DestinationPortRange 22 -Access Allow

# Create an inbound network security group rule for port 443
write-host "Enabling port 443 for OMI" -ForegroundColor cyan
$nsgRuleOMI = New-AzureRmNetworkSecurityRuleConfig -Name smokeNetworkSecurityGroupRuleOMI  -Protocol Tcp `
  -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * `
  -DestinationPortRange 443 -Access Allow

# Create a network security group
write-host "Creating a network security group" -ForegroundColor cyan
$nsg = New-AzureRmNetworkSecurityGroup -ResourceGroupName $tempRg2Ubuntu -Location $location `
  -Name smokeNetworkSecurityGroup -SecurityRules $nsgRuleSSH,$nsgRuleOMI

# Create a virtual network card and associate with public IP address and NSG
write-host "Creating a NIC" -ForegroundColor cyan
$nic = New-AzureRmNetworkInterface -Name smokeNic -ResourceGroupName $tempRg2Ubuntu -Location $location `
  -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id


$vmSize = "Standard_DS1_v2"

write-host "Creating the full VM configuration..." -ForegroundColor cyan
$Ubuntuvm = New-AzureRmVMConfig -VMName $UbuntuvmName -VMSize $vmSize

write-host "Setting the VM source image..." -ForegroundColor cyan
$Ubuntuvm = Set-AzureRmVMSourceImage -VM $Ubuntuvm -Id $Ubuntuimage.Id

write-host "Setting the VM OS Source Disk...." -ForegroundColor cyan
$Ubuntuvm = Set-AzureRmVMOSDisk -VM $Ubuntuvm  -StorageAccountType PremiumLRS -DiskSizeInGB 128 -CreateOption FromImage -Caching ReadWrite

write-host "Setting the OS to Linux..." -ForegroundColor cyan
$Ubuntuvm = Set-AzureRmVMOperatingSystem -VM $Ubuntuvm -Linux -Credential $cred -ComputerName $UbuntucomputerName

write-host "Adding the network interface..." -ForegroundColor cyan
$Ubuntuvm = Add-AzureRmVMNetworkInterface -VM $Ubuntuvm -Id $nic.Id

write-host "And launching the VM..." -ForegroundColor cyan
New-AzureRmVM -VM $Ubuntuvm -ResourceGroupName $tempRg2Ubuntu -Location $location

#================================================
sleep 60
#
#  Machine should now be up.  Get the version
#
write-host "Checking OS versions..." -ForegroundColor green
$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$pw=convertto-securestring -AsPlainText -force -string 'P@$$w0rd!'
$cred=new-object -typename system.management.automation.pscredential -argumentlist "azureuser",$pw

$CentOSip=Get-AzureRmPublicIpAddress -ResourceGroupName $tempRg2CentOS
$CentOSs=new-PSSession -computername $CentOSip.IpAddress -credential $cred -authentication Basic -UseSSL -Port 443 -SessionOption $o
$CentOS_installed_vers=invoke-command -session $CentOSs -ScriptBlock {/bin/uname -r}
remove-pssession $CentOSs
write-host "CentOS installed version retrieved as $CentOS_installed_vers"  -ForegroundColor green

$Ubuntuip=Get-AzureRmPublicIpAddress -ResourceGroupName $tempRg2Ubuntu 
$Ubuntus=new-PSSession -computername $Ubuntuip.IpAddress -credential $cred -authentication Basic -UseSSL -Port 443 -SessionOption $o
$Ubuntu_installed_vers=invoke-command -session $Ubuntus -ScriptBlock {/bin/uname -r}
remove-pssession $Ubuntus
write-host "Ubuntu installed version retrieved as $Ubuntu_installed_vers"  -ForegroundColor green

$expected_boot=Get-Content C:\temp\centos-boot
$expected_ver=$expected_boot.split(" ")[1]

write-host "Stopping the VMs" -ForegroundColor green
Stop-AzureRmVm -force -ResourceGroupName $tempRg1CentOS -name $CentOSvmName
Stop-AzureRmVm -force -ResourceGroupName $tempRg1Ubuntu -name $UbuntuvmName
Stop-AzureRmVm -force -ResourceGroupName $tempRg2CentOS -name $CentOSvmName
Stop-AzureRmVm -force -ResourceGroupName $tempRg2Ubuntu -name $UbuntuvmName

#
#  Removing the resource groups takes a long time, and I'd like to know how it went...
#
if (($expected_ver.CompareTo($CentOS_installed_vers) -eq 0) -and ($expected_ver.CompareTo($Ubuntu_installed_vers) -eq 0)) {
    write-host "Success!" -ForegroundColor green
} else {
    write-host "Failure" -ForegroundColor red
}

#
#  Clean up
#
write-host "Removing resource groups." -ForegroundColor green
write-host "First, $tempRg1CentOS" -ForegroundColor green
Remove-AzureRmResourceGroup -Name $tempRg1CentOS -Force
Remove-AzureRmResourceGroup -Name $tempRg1Ubuntu -Force
write-host "Then, $tempRg2CentOS" -ForegroundColor green
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
