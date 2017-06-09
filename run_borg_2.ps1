param (
    [Parameter(Mandatory=$true)]
    [string] $requestedVM=""
)

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

try {
    write-host "Importing the context...." -ForegroundColor green
    Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'

    write-host "Selecting the Azure subscription..." -ForegroundColor green
    Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4"

    write-host "Setting the Azure Storage Account" -ForegroundColor green
    # New-AzureRmStorageAccount -ResourceGroupName $rg -Name $nm -Location westus -SkuName "Standard_LRS" -Kind "Storage"
    Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $nm
}
Catch
{
    Write-Error "Caught exception attempting to log into Azure.  Aborting..."
    exit 1
}

#
#  Clear anything in the storage container
#
# Get-AzureStorageBlob -Container $cn -blob * | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $cn}

#
#  Copy the files to the cloud
#
$failed=0

$fileName = "D:\azure_images\" + $requestedVM + ".vhd"
$sourceVHd=get-item -Path $filename

$vhdFile=$sourceVHd
$vhdFileName=$vhdFile.Name.Split('.')[0]

try {
    #
    #  Copy the blob to the storage container
    $c = Get-AzureStorageContainer -Name $cn
    $sas = $c | New-AzureStorageContainerSASToken -Permission rwdl
    $blobuploadURIRaw = $c.CloudBlobContainer.Uri.ToString() + "/" + $vhdFile.Name.ToString() 
    $blobuploadURI = $blobuploadURIRaw + $sas
}
Catch
{
    Write-Error "Caught exception attempting to get the storage container.  Aborting..."
    exit 1
}

try {
    write-host "Creating a resource group for machine $vhdFileName" -ForegroundColor magenta
    $newRGName=$vhdFileName+"-SmokeRG"
    New-AzureRmResourceGroup -Name $newRGName -Location westus

    Write-Host "Making sure the VM is stopped..." -ForegroundColor magenta
    stop-vm $vhdFileName

    write-host "Uploading the $vhdFileName VHD blob to the cloud" -ForegroundColor magenta
    $localFilePath=$sourceVHd.FullName
    Add-AzureRmVhd –ResourceGroupName $rg -Destination "$blobuploadURI" -LocalFilePath $localFilePath -OverWrite

    Write-Host "Creating a new VM config..."  -ForegroundColor magenta
    $vm=New-AzureRmVMConfig -vmName $vhdFileName -vmSize 'Standard_D2'

    Write-Host "Assigning resource group $rg network and subnet config to new machine"
    $VMVNETObject = Get-AzureRmVirtualNetwork -Name  azuresmokeresourcegroup-vnet -ResourceGroupName $rg
    $VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name default -VirtualNetwork $VMVNETObject

    write-host "Creating the public IP address" -ForegroundColor magenta
    $pip = New-AzureRmPublicIpAddress -ResourceGroupName $newRGName -Location $location `
            -Name $vhdFileName -AllocationMethod Dynamic -IdleTimeoutInMinutes 4

    write-host "Creating the network interface" -ForegroundColor magenta
    $VNIC = New-AzureRmNetworkInterface -Name $vhdFileName -ResourceGroupName $newRGName -Location westus -SubnetId $VMSubnetObject.Id -publicipaddressid $pip.Id

    write-host "Adding the network interface" -ForegroundColor magenta
    Add-AzureRmVMNetworkInterface -VM $vm -Id $VNIC.Id

    write-host "Assigning the OS disk to URI $blobuploadURIRaw" -ForegroundColor magenta
    Set-AzureRmVMOSDisk -VM $vm -Name $vhdFileName -VhdUri $blobuploadURIRaw -CreateOption "Attach" -linux
}
Catch
{
    Write-Error "Caught exception attempting to create the Azure VM.  Aborting..."
    exit 1
}

try {
    write-host "Starting the VM" -ForegroundColor magenta
    $NEWVM = New-AzureRmVM -ResourceGroupName $newRGName -Location westus -VM $vm
    if ($NEWVM -eq $null) {
        write-host "FAILED TO CREATE VM!!" -ForegroundColor red
        exit 1
    }
}
Catch
{
    Write-Error "Caught exception attempting to start the new VM.  Aborting..."
    exit 1
}

#
#  Give the VM time to get to user level and start OMI
#
write-host "Giving it a minute to wake up" -ForegroundColor magenta
sleep 60

write-host "Checking OS versions..." -ForegroundColor cyan
$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$pw=convertto-securestring -AsPlainText -force -string 'P@$$w0rd!'
$cred=new-object -typename system.management.automation.pscredential -argumentlist "mstest",$pw

$expected_ver=Get-Content C:\temp\expected_version

$failed=0

try {
    $ip=Get-AzureRmPublicIpAddress -ResourceGroupName $newRGName
    $ipAddress=$ip.IpAddress
    write-host "Creating PowerShell Remoting session to machine at IP $ipAddress" -ForegroundColor cyan
    $session=new-PSSession -computername $ipAddress -credential $cred -authentication Basic -UseSSL -Port 443 -SessionOption $o

    if ($session -eq $null) {
        write-host "FAILED to contact Azure guest VM" -ForegroundColor red
        exit 1
    }

    $installed_vers=invoke-command -session $session -ScriptBlock {/bin/uname -r}
    remove-pssession $session
    write-host "vhdFileName installed version retrieved as $installed_vers"  -ForegroundColor green
}
Catch
{
    Write-Error "Caught exception attempting to verify Azure installed kernel version.  Aborting..."
    exit 1
}

try {
    Write-Host "Stopping the Azure VM" -ForegroundColor cyan
    Stop-AzureRmVm -force -ResourceGroupName $vhdFileName -name $vhdFileName

    write-host "Removing resource group." -ForegroundColor cyan
    Remove-AzureRmResourceGroup -Name $vhdFileName -Force
}
Catch
{
    Write-Error "Caught exception attempting to clean up Azure.  Aborting..."
    exit 1
}

#
#  Now, check for success
#
if ($expected_ver.CompareTo($installed_vers) -ne 0) {
    $failed = 1
}


exit $failed
