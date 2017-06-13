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

echo "********************************************************************"  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
echo "*              BORG, Phase II -- Assimilation by Azure             *"  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
echo "********************************************************************"  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM

try {
    echo "Importing the context...."  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
    Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'

    echo "Selecting the Azure subscription..."  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
    Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4"

    echo "Setting the Azure Storage Account"  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
    # New-AzureRmStorageAccount -ResourceGroupName $rg -Name $nm -Location westus -SkuName "Standard_LRS" -Kind "Storage"
    Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $nm
}
Catch
{
    echo "Caught exception attempting to log into Azure.  Aborting..." | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
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

$fileName = "D:\working_images\" + $requestedVM + ".vhd"
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
    echo "Caught exception attempting to get the storage container.  Aborting..." | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
    exit 1
}

$newRGName=$vhdFileName+"-SmokeRG"
$existingRG=Get-AzureRmResourceGroup -Name $newRGName

$groupExists=$false
if ($? -eq $true) {
    $groupExists=$true
}

try {
    

    if ($groupExists -eq $false)
    {
        echo "Creating a resource group for machine $vhdFileName"  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
        New-AzureRmResourceGroup -Name $newRGName -Location westus
    }
    else
    {
        echo "Using existing resource group for machine $vhdFileName"  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
    }

    echo "Making sure the VM is stopped..."  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
    stop-vm $vhdFileName

    echo "Uploading the $vhdFileName VHD blob to the cloud"  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
    $localFilePath=$sourceVHd.FullName
    Add-AzureRmVhd –ResourceGroupName $rg -Destination "$blobuploadURI" -LocalFilePath $localFilePath -OverWrite -NumberOfUploaderThreads 10

    if ($groupExists -eq $false)
    {
        echo "Creating a new VM config..."   | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
        $vm=New-AzureRmVMConfig -vmName $vhdFileName -vmSize 'Standard_D2'

        echo "Assigning resource group $rg network and subnet config to new machine" | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
        $VMVNETObject = Get-AzureRmVirtualNetwork -Name  azuresmokeresourcegroup-vnet -ResourceGroupName $rg
        $VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name default -VirtualNetwork $VMVNETObject

        echo "Creating the public IP address"  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
        $pip = New-AzureRmPublicIpAddress -ResourceGroupName $newRGName -Location $location `
                -Name $vhdFileName -AllocationMethod Dynamic -IdleTimeoutInMinutes 4

        echo "Creating the network interface"  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
        $VNIC = New-AzureRmNetworkInterface -Name $vhdFileName -ResourceGroupName $newRGName -Location westus -SubnetId $VMSubnetObject.Id -publicipaddressid $pip.Id

        echo "Adding the network interface"  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
        Add-AzureRmVMNetworkInterface -VM $vm -Id $VNIC.Id
    }

    echo "Assigning the OS disk to URI $blobuploadURIRaw"  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
    Set-AzureRmVMOSDisk -VM $vm -Name $vhdFileName -VhdUri $blobuploadURIRaw -CreateOption "Attach" -linux
}
Catch
{
    echo "Caught exception attempting to create the Azure VM.  Aborting..." | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
    exit 1
}

try {
    echo "Starting the VM"  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
    $NEWVM = New-AzureRmVM -ResourceGroupName $newRGName -Location westus -VM $vm
    if ($NEWVM -eq $null) {
        echo "FAILED TO CREATE VM!!" 
        exit 1
    }
}
Catch
{
    echo "Caught exception attempting to start the new VM.  Aborting..." | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
    exit 1
}

#
#  Give the VM time to get to user level and start OMI
#
echo "Giving it a minute to wake up"  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
sleep 60

echo "Checking OS versions..."  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$pw=convertto-securestring -AsPlainText -force -string 'P@$$w0rd!'
$cred=new-object -typename system.management.automation.pscredential -argumentlist "mstest",$pw

$expected_ver=Get-Content C:\temp\expected_version

$failed=0

try {
    $ip=Get-AzureRmPublicIpAddress -ResourceGroupName $newRGName
    $ipAddress=$ip.IpAddress
    echo "Creating PowerShell Remoting session to machine at IP $ipAddress"  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
    $session=new-PSSession -computername $ipAddress -credential $cred -authentication Basic -UseSSL -Port 443 -SessionOption $o

    if ($session -eq $null) {
        echo "FAILED to contact Azure guest VM"  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
        exit 1
    }

    $installed_vers=invoke-command -session $session -ScriptBlock {/bin/uname -r}
    remove-pssession $session
    echo "vhdFileName installed version retrieved as $installed_vers"   | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
}
Catch
{
    echo "Caught exception attempting to verify Azure installed kernel version.  Aborting..."
    exit 1
}

try {
    echo "Stopping the Azure VM"  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
    Stop-AzureRmVm -force -ResourceGroupName $vhdFileName -name $vhdFileName

    echo "Removing resource group."  | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
    Remove-AzureRmResourceGroup -Name $vhdFileName -Force
}
Catch
{
    echo "Caught exception attempting to clean up Azure.  Aborting..." | Out-File -Append -FilePath C:\temp\progress_logs\$requestedVM
    exit 1
}

#
#  Now, check for success
#
if ($expected_ver.CompareTo($installed_vers) -ne 0) {
    $failed = 1
}


exit $failed
