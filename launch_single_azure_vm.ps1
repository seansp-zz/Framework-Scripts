param (
    [Parameter(Mandatory=$true)] [string] $vmName
)

$rg="smoke_working_resource_group"
$nm="smokeworkingstorageacct"  
$destContainerName = "vhds-under-test"

Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'
Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4"
Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $nm

# try {
    echo "Making sure the VM is stopped..."  
    Stop-AzureRmVM -Name $vmName -ResourceGroupName $rg -Force -ErrorAction SilentlyContinue

    echo "Deleting any existing VM"
    Remove-AzureRmVM -Name $vmName -ResourceGroupName $rg -Force -ErrorAction SilentlyContinue

    echo "Creating a new VM config..."   
    $vm=New-AzureRmVMConfig -vmName $vmName -vmSize 'Standard_D2'

    echo "Assigning resource group $rg network and subnet config to new machine" 
    $VMVNETObject = Get-AzureRmVirtualNetwork -Name SmokeVNet -ResourceGroupName $rg
    $VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name SmokeSubnet-1 -VirtualNetwork $VMVNETObject

    echo "Assigning the public IP address"  
    $pip = Get-AzureRmPublicIpAddress -ResourceGroupName $rg -Name $vmName -ErrorAction SilentlyContinue
    if ($? -eq $false) {
        Write-Host "Creating new IP address..."
        New-AzureRmPublicIpAddress -ResourceGroupName $rg -Location westus -Name $vmName -AllocationMethod Dynamic -IdleTimeoutInMinutes 4
        $pip = Get-AzureRmPublicIpAddress -ResourceGroupName $rg -Name $vmName
    }

    echo "Assigning the network interface"  
    $VNIC = Get-AzureRmNetworkInterface -Name $vmName -ResourceGroupName $rg -ErrorAction SilentlyContinue
    if ($? -eq $false) {
        Write-Host "Creating new network interface"
        New-AzureRmNetworkInterface -Name $vmName -ResourceGroupName $rg -Location westus -SubnetId $VMSubnetObject.Id -publicipaddressid $pip.Id
        $VNIC = Get-AzureRmNetworkInterface -Name $vmName -ResourceGroupName $rg
    }

    echo "Adding the network interface"  
    Add-AzureRmVMNetworkInterface -VM $vm -Id $VNIC.Id

    echo "Getting the source disk URI" 
    $c = Get-AzureStorageContainer -Name $destContainerName
    $blobName=$vmName + ".vhd"
    $blobURIRaw = $c.CloudBlobContainer.Uri.ToString() + "/" + $blobName

    echo "Setting the OS disk to interface $blobURIRaw" 
    Set-AzureRmVMOSDisk -VM $vm -Name $vmName -VhdUri $blobURIRaw -CreateOption "Attach" -linux
<# }
Catch
{
    echo "Caught exception attempting to create the Azure VM.  Aborting..." 
    return 1
} #>

try {
    echo "Starting the VM"  
    $NEWVM = New-AzureRmVM -ResourceGroupName $rg -Location westus -VM $vm
    if ($NEWVM -eq $null) {
        echo "FAILED TO CREATE VM!!" 
    } else {
        echo "VM $vmName started successfully..."             
    }
}
Catch
{
    echo "Caught exception attempting to start the new VM.  Aborting..." 
    return 1
}