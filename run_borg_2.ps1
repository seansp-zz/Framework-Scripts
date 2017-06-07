#
#  THIS IS A WINDOWS POWERSHELL SCRIPT!!  IT ONLY WORKS ON WINDOWS!!
#
# Variables for common values
$resourceGroup = "azureSmokeResourceGroup"
$rg=$resourceGroup
$nm="azuresmokestoragesccount"
$location = "westus"
$vmName = "azureSmokeVM-1"
$cn="azuresmokestoragecontainer"


write-host "********************************************************************" -ForegroundColor green
write-host "*              BORG, Phase II -- Assimilation by Azure             *" -ForegroundColor green
write-host "********************************************************************" -ForegroundColor green

write-host "Importing the context...." -ForegroundColor green
Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'

write-host "Selecting the Azure subscription..." -ForegroundColor green
Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4"

write-host "Setting the Azure Storage Account" -ForegroundColor green
# New-AzureRmStorageAccount -ResourceGroupName $rg -Name $nm -Location westus -SkuName "Standard_LRS" -Kind "Storage"
Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $nm

#
#  Clear anything in the storage container
#
# Get-AzureStorageBlob -Container $cn -blob * | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $cn}

#
#  Copy the files to the cloud
#
$failed=0
Get-ChildItem 'D:\azure_images' |
foreach-Object {
    # $sourceVHd=get-item -Path D:\azure_images\RHEL71-Smoke-1.vhd

    # $vhdFile=$sourceVHd
    # $vhdFileName=$vhdFile.Name.Split('.')[0]

    $vhdFile=$_
    $vhdFileName=$vhdFile.Name.Split('.')[0]

    #
    #  Copy the blob to the storage container
    $c = Get-AzureStorageContainer -Name $cn
    $sas = $c | New-AzureStorageContainerSASToken -Permission rwdl
    $blobuploadURIRaw = $c.CloudBlobContainer.Uri.ToString() + "/" + $vhdFile.Name.ToString() 
    $blobuploadURI = $blobuploadURIRaw + $sas

    $newRGName=$vhdFileName+"-SmokeRG"
    New-AzureRmResourceGroup -Name $newRGName -Location westus

    stop-vm $vhdFileName

    write-host "Uploading the $vhdFileName VHD blob to the cloud" -ForegroundColor magenta
    $localFilePath=$_.FullName
    Add-AzureRmVhd –ResourceGroupName $rg -Destination "$blobuploadURI" -LocalFilePath $localFilePath -OverWrite

    $vm=New-AzureRmVMConfig -vmName $vhdFileName -vmSize 'Standard_D2'

    $VMVNETObject = Get-AzureRmVirtualNetwork -Name  azuresmokeresourcegroup-vnet -ResourceGroupName $rg

    $VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name default -VirtualNetwork $VMVNETObject

    $pip = New-AzureRmPublicIpAddress -ResourceGroupName $newRGName -Location $location `
          -Name $vhdFileName -AllocationMethod Dynamic -IdleTimeoutInMinutes 4

    $VNIC = New-AzureRmNetworkInterface -Name $vhdFileName -ResourceGroupName $newRGName -Location westus -SubnetId $VMSubnetObject.Id -publicipaddressid $pip.Id

    Add-AzureRmVMNetworkInterface -VM $vm -Id $VNIC.Id

    Set-AzureRmVMOSDisk -VM $vm -Name $vhdFileName -VhdUri $blobuploadURIRaw -CreateOption "Attach" -linux

    $NEWVM = New-AzureRmVM -ResourceGroupName $newRGName -Location westus -VM $vm

    #
    #  Give the VM time to get to user level and start OMI
    #
    sleep 60

    write-host "Checking OS versions..." -ForegroundColor green
    $o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
    $pw=convertto-securestring -AsPlainText -force -string 'P@$$w0rd!'
    $cred=new-object -typename system.management.automation.pscredential -argumentlist "mstest",$pw

    $expected_ver=Get-Content C:\temp\expected_version

    $failed=0

    $ip=Get-AzureRmPublicIpAddress -ResourceGroupName $newRGName
    $session=new-PSSession -computername $ip.IpAddress -credential $cred -authentication Basic -UseSSL -Port 443 -SessionOption $o
    $installed_vers=invoke-command -session $session -ScriptBlock {/bin/uname -r}
    remove-pssession $session
    write-host "vhdFileName installed version retrieved as $installed_vers"  -ForegroundColor green

    Stop-AzureRmVm -force -ResourceGroupName $vhdFileName -name $vhdFileName

    write-host "Removing resource group." -ForegroundColor green
    Remove-AzureRmResourceGroup -Name $vhdFileName -Force

    #
    #  Now, check for success
    #
    if ($expected_ver.CompareTo($installed_vers) -ne 0) {
        $failed = 1
    }
}


exit $failed
