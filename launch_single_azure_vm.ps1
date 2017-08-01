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

Start-Transcript -path C:\temp\transcripts\launch_single_azure_vm_$vmName.log -Force

. "C:\Framework-Scripts\common_functions.ps1"

login_azure $resourceGroup $storageAccount

echo "Making sure the VM is stopped..."  
$runningVMs = Get-AzureRmVm -ResourceGroupName $resourceGroup -status | Where-Object -Property Name -Like "$vmName*" | where-object -Property PowerState -eq -value "VM running"
remove_machines_from_group $runningVMs $resourceGroup

echo "Deleting any existing VM"
$runningVMs = Get-AzureRmVm -ResourceGroupName $resourceGroup -status | Where-Object -Property Name -Like "$vmName*" | Remove-AzureRmVM -Force
deallocate_machines_in_group $runningVMs $resourceGroup

echo "Creating a new VM config..."   
$vm=New-AzureRmVMConfig -vmName $vmName -vmSize 'Standard_D2' 

echo "Assigning resource group $resourceGroup network and subnet config to new machine" 
$VMVNETObject = Get-AzureRmVirtualNetwork -Name $network -ResourceGroupName $resourceGroup
$VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name $subnet -VirtualNetwork $VMVNETObject

echo "Assigning the public IP address"  
$ipName= $vmName + "PublicIP"
$pip = Get-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup -Name $ipName -ErrorAction SilentlyContinue
if ($? -eq $false) {
    Write-Host "Creating new IP address..."
    New-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup -Location westus -Name $ipName -AllocationMethod Dynamic -IdleTimeoutInMinutes 4
    $pip = Get-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup -Name $ipName
}

echo "Assigning the network interface"  
$nicName=$vmName + "VMNic"
$VNIC = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
if ($? -eq $false) {
    Write-Host "Creating new network interface"
    New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $resourceGroup -Location westus -SubnetId $VMSubnetObject.Id -publicipaddressid $pip.Id
    $VNIC = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $resourceGroup
}

$sg = Get-AzureRmNetworkSecurityGroup -Name SmokeNSG -ResourceGroupName $resourceGroup
$VNIC.NetworkSecurityGroup = $sg
Set-AzureRmNetworkInterface -NetworkInterface $VNIC

$pw = convertto-securestring -AsPlainText -force -string "$TEST_USER_ACCOUNT_PAS2" 
$cred = new-object -typename system.management.automation.pscredential -argumentlist "$TEST_USER_ACCOUNT_NAME",$pw

echo "Adding the network interface"  
Add-AzureRmVMNetworkInterface -VM $vm -Id $VNIC.Id

$blobURIRaw="https://$storageAccount.blob.core.windows.net/$containerName/" + $vmName + ".vhd"

$vm = Set-AzureRmVMOSDisk -VM $vm -Name $vmName -VhdUri $blobURIRaw -CreateOption attach -Linux

$vm = Set-AzureRmVMBootDiagnostics -VM $vm -Disable
 
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

