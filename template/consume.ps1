

#From AzureWinUtils (with a lot removed)
function LogMsg([string]$msg, [string]$color="green")
{
    # #Masking the password.
    # $pass2 = $password.Replace('"','')
    # $msg = $msg.Replace($pass2,"$($pass2[0])***$($pass2[($pass2.Length) - 1])")
    foreach ( $line in $msg )
    {
        $now = [Datetime]::Now.ToUniversalTime().ToString("MM/dd/yyyy HH:mm:ss : ")
        $tag="INFO : "
        write-host -f $color "$tag $now $line"
    }
}

# Import-Module ..\ConvertFrom-ArbritraryXml.psm1
# $xmlAsText = Get-Content -Path .\Make_Drone.xml
# $ob = ConvertFrom-ArbritraryXml( [xml] $xmlAsText )
# $json = $ob | ConvertTo-Json -Depth 10

$jsonAsText =  Get-Content -Path .\deploy_drone.json | Out-String
$json = ConvertFrom-Json $jsonAsText 

LogMsg "Building Topology $($json.Topology.Name)" "cyan"

#TODO: Security Groups could be multiple.
#LogMsg "Checking to see if security group exists already."
LogMsg "Using ResourceGroup :: $($json.Topology.ResourceGroup)"
$rg = Get-AzureRmResourceGroup `
  -Name $json.Topology.ResourceGroup `
  -ErrorAction Ignore
  if( $null -ne $rg )
  {
    #TODO: Purge option.
    LogMsg "Found existing resource group. Deleting." "yellow"
    Remove-AzureRmResourceGroup -Name $json.Topology.ResourceGroup -Force 
    LogMsg "Complete."
  }
  LogMsg "Creating resource group." 
  $rg = New-AzureRmResourceGroup `
    -Name $json.Topology.ResourceGroup `
    -Location $json.Topology.Location
    #TODO: ErrorAction
  LogMsg "Completed creating ResourceGroup:$($json.Topology.ResourceGroup)."

LogMsg "Creating security groups" "magenta"  #TODO: More than one.
$sg = Get-AzureRmNetworkSecurityGroup `
 -Name $json.Topology.NetworkSecurityGroup.Name `
 -ResourceGroupName $json.Topology.ResourceGroup `
 -ErrorAction Ignore
 if( $null -ne $sg )
 {
   LogMsg "This should never happen.", "red"
 }
 else {
   $rules = @()
   foreach( $def in $json.Topology.NetworkSecurityGroup.Rule )
   {
     LogMsg "Creating rule: $($def.Name) -- $($def.Description)"
     $rule = New-AzureRmNetworkSecurityRuleConfig `
     -Name $def.Name -Description $def.Description `
     -Access $def.Access -Protocol $def.Protocol -Direction $def.Direction `
     -Priority $def.Priority -SourceAddressPrefix $def.SourceAddressPrefix `
     -SourcePortRange $def.SourcePortRange  `
     -DestinationAddressPrefix $def.DestinationAddressPrefix `
     -DestinationPortRange $def.DestinationPortRange
     $rules += $rule
   }
   New-AzureRmNetworkSecurityGroup -Name $json.Topology.NetworkSecurityGroup.Name `
    -ResourceGroupName $json.Topology.ResourceGroup `
    -Location $json.Topology.Location `
    -SecurityRules $rules
   $sg = Get-AzureRmNetworkSecurityGroup `
   -Name $json.Topology.NetworkSecurityGroup.Name `
   -ResourceGroupName $json.Topology.ResourceGroup `
   -ErrorAction Ignore

   LogMsg "Now building the Network -- $($json.Topology.Network.Name)"
   $vnet = Get-AzureRmVirtualNetwork -Name $json.Topology.Network.Name -ResourceGroupName $json.Topology.ResourceGroup
   if ($null -eq $vnet) {
       write-host "Network does not exist for this region.  Creating now..." -ForegroundColor Yellow
       $vsubnet = New-AzureRmVirtualNetworkSubnetConfig -Name $json.Topology.Network.Subnet.Name `
        -AddressPrefix $json.Topology.Network.Subnet.AddressPrefix -NetworkSecurityGroup $sg
       New-AzureRmVirtualNetwork  -Name $json.Topology.Network.Name `
        -ResourceGroupName $json.Topology.ResourceGroup -Location $json.Topology.Location `
        -AddressPrefix $json.Topology.Network.AddressPrefix -Subnet $vsubnet
        $vnet = Get-AzureRmVirtualNetwork -Name $json.Topology.Network.Name `
          -ResourceGroupName $json.Topology.ResourceGroup
   }
 }

 LogMsg "Now building the computers." "magenta"

foreach( $def in $json.Topology.VirtualMachine )
{
  LogMsg $def.Name "green"
  $vm = New-AzureRmVMConfig -VMName $def.Name -VMSize $def.VMSize
  #TODO: Public IP
  #TODO: NIC
  #TODO: Set OSDisk
  #TODO: Boot Diagnostics.
  #TODO: Launch

}

