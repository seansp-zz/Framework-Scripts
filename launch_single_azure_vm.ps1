param (
    [Parameter(Mandatory=$true)] [string] $vmName="Unknown",
    [Parameter(Mandatory=$true)] [string] $resourceGroup="smoke_working_resource_group",
    [Parameter(Mandatory=$true)] [string] $storageAccount="smokeworkingstorageacct",
    [Parameter(Mandatory=$true)] [string] $containerName="vhds-under-test",

    [Parameter(Mandatory=$true)] [string] $network="SmokeVNet",
    [Parameter(Mandatory=$true)] [string] $subnet="SmokeSubnet-1",
    [Parameter(Mandatory=$true)] [string] $NSG="SmokeNSG",

    [Parameter(Mandatory=$false)] [string] $addAdminUser="",
    [Parameter(Mandatory=$false)] [string] $adminUser="",
    [Parameter(Mandatory=$false)] [string] $adminPW=""
)

. "C:\Framework-Scripts\secrets.ps1"
if( [string]::IsNullOrWhiteSpace( $adminUser ) )
{
    $adminUser = "$TEST_USER_ACCOUNT_NAME"
}
if( [string]::IsNullOrWhiteSpace( $adminPW ) )
{
    $adminPW = "$TEST_USER_ACCOUNT_PASS"
}

Start-Transcript C:\temp\transcripts\launch_single_azure_vm.log -Force

. "C:\Framework-Scripts\common_functions.ps1"

login_azure $resourceGroup $storageAccount

echo "Making sure the VM is stopped..."  
Get-AzureRmVm -ResourceGroupName $resourceGroup -status | Where-Object -Property Name -Like "$vmName*" | where-object -Property PowerState -eq -value "VM running" | Stop-AzureRmVM -Force

echo "Deleting any existing VM"
Get-AzureRmVm -ResourceGroupName $resourceGroup -status | Where-Object -Property Name -Like "$vmName*" | Remove-AzureRmVM -Force

echo "Creating a new VM config..."   
$vm=New-AzureRmVMConfig -vmName $vmName -vmSize 'Standard_D2' 

echo "Assigning resource group $resourceGroup network and subnet config to new machine" 
$VMVNETObject = Get-AzureRmVirtualNetwork -Name $network -ResourceGroupName $resourceGroup
$VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name $subnet -VirtualNetwork $VMVNETObject

echo "Assigning the public IP address"  
$pip = Get-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup -Name $vmName-pip -ErrorAction SilentlyContinue
if ($? -eq $false) {
    Write-Host "Creating new IP address..."
    New-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup -Location westus -Name $vmName-pip -AllocationMethod Dynamic -IdleTimeoutInMinutes 4
    $pip = Get-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup -Name $vmName-pip
}

echo "Assigning the network interface"  
$VNIC = Get-AzureRmNetworkInterface -Name $vmName-nic -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
if ($? -eq $false) {
    Write-Host "Creating new network interface"
    New-AzureRmNetworkInterface -Name $vmName-nic -ResourceGroupName $resourceGroup -Location westus -SubnetId $VMSubnetObject.Id -publicipaddressid $pip.Id
    $VNIC = Get-AzureRmNetworkInterface -Name $vmName-nic -ResourceGroupName $resourceGroup
}

$sg = Get-AzureRmNetworkSecurityGroup -Name SmokeNSG -ResourceGroupName $resourceGroup
$VNIC.NetworkSecurityGroup = $sg
Set-AzureRmNetworkInterface -NetworkInterface $VNIC

echo "Adding the network interface"  
Add-AzureRmVMNetworkInterface -VM $vm -Id $VNIC.Id

$vm = Set-AzureRmVMOSDisk -VM $vm -Name $vmName -VhdUri $blobURIRaw -CreateOption attach -Linux
 
try {
    echo "Starting the VM"  
    $NEWVM = New-AzureRmVM -ResourceGroupName $resourceGroup -Location $location -VM $vm
    if ($NEWVM -eq $null) {
        echo "FAILED TO CREATE VM!!" 
    } else {
        echo "VM $vmName started successfully..."  
    } 
}
Catch
{
    echo "Caught exception attempting to start the new VM.  Aborting..." 
    Stop-Transcript
    return
}

Stop-Transcript

