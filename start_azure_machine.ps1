$vm=New-AzureRmVMConfig -vmName JWF -vmSize 'Standard_D2'

$VMVNETObject = Get-AzureRmVirtualNetwork -Name  azuresmokeresourcegroup-vnet -ResourceGroupName $rg

$VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name default -VirtualNetwork $VMVNETObject

$VNIC = New-AzureRmNetworkInterface -Name JWF -ResourceGroupName $rg -Location westus -SubnetId $VMSubnetObject.Id -PrivateIpAddress $VMIP

Add-AzureRmVMNetworkInterface -VM $vm -Id $VNIC.Id

Set-AzureRmVMOSDisk -VM $vm -Name JWF -VhdUri $uri -CreateOption "Attach" -linux

$NEWVM = New-AzureRmVM -ResourceGroupName $rg -Location westus -VM $vm