param (
    [Parameter(Mandatory=$true)] [string] $vmName="Unset",

    [Parameter(Mandatory=$true)] [string] $publisher="Unset",
    [Parameter(Mandatory=$true)] [string] $offer="Unset",
    [Parameter(Mandatory=$true)] [string] $sku="Unset",
    [Parameter(Mandatory=$true)] [string] $version="Unset",

    [Parameter(Mandatory=$false)] [string] $testCycle="BVT",

    [Parameter(Mandatory=$false)] [string] $resourceGroup="jpl_intake_rg",

    [Parameter(Mandatory=$false)] [string] $cleanContainer="original-images",
    [Parameter(Mandatory=$false)] [string] $bvtContainer="ready-for-bvt",

    [Parameter(Mandatory=$false)] [string] $destSA="smokebvtstorageaccount",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_bvts_resource_group"
)
    

$vmName = "JPL-Test-1"
$resourceGroup="jpl_intake_rg"
$storageAccount="jplintakestorageacct"
$cleanContainer="original-images"
$bvtContainer="ready-for-bvt"

<#
$vnetName="JPL-VNet-1"
$subnetName="JPL-Subnet-1"

$vm=New-AzureRmVMConfig -VMName $vmName -VMSize 'Standard_D2' 
$VMVNETObject = Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroup
$VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name $subnetName  -VirtualNetwork $VMVNETObject

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

echo "Adding the network interface"  
Add-AzureRmVMNetworkInterface -VM $vm -Id $VNIC.Id

$pw = convertto-securestring -AsPlainText -force -string 'P@ssW0rd-'
$cred = new-object -typename system.management.automation.pscredential -argumentlist "mstest",$pw

Set-AzureRmVMOperatingSystem -VM $vm -Linux -ComputerName $vmName -Credential $cred

Set-AzureRmVMSourceImage -VM $vm -PublisherName "RedHat" -Offer "RHEL" -Skus "7.4.BETA-LVM" -Version "7.4.2017063023"

New-AzureRmVM -ResourceGroupName $resourceGroup -Location westus -vm $vm
#>

$currentDir="/tmp"
$username="mstest"
$password="P@ssW0rd-"
$port=22
$ip=(Get-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup -Name $vmName-pip).IpAddress

#
#  Send make_drone to the new machine
echo "y" | C:\azure-linux-automation\tools\pscp C:\Framework-Scripts\make_drone.sh mstest@$ip`:/tmp
echo $password | C:\azure-linux-automation\tools\pscp C:\Framework-Scripts\make_drone.sh mstest@$ip`:/tmp

$chmodCommand="chmod 755 /tmp/make_drone.sh"
$runDroneCommand="/tmp/make_drone.sh"
$linuxChmodCommand="`"echo $password | sudo -S bash -c `'$chmodCommand`'`""
$linuxDroneCommand="`"echo $password | sudo -S bash -c `'$runDroneCommand`'`""

$runLinuxSetupJob = Start-Job -ScriptBlock `
			{ `
				$username = $args[1]; $password = $args[2]; $ip = $args[3]; $port = $args[4]; $jcommand = $args[5]; `
				cd $args[0]; `
				#Write-Host ".\tools\plink.exe -t -C -v -pw $password -P $port $username@$ip $jcommand";`
				C:\azure-linux-automation\tools\plink.exe -C -v -pw $password -P $port $username@$ip $jcommand;`
			} `
			-ArgumentList $currentDir, $username, $password, $ip, $port, $linuxChmodCommand
$setupJobId = $runLinuxSetupJob.Id
$jobState = get-job $setupJobId
While($jobState -eq "Running") {
    write-host "Sleeping..."
    sleep 1
    $jobState = get-job $setupJobId
}

receive-job $setupJobId

$runLinuxDroneJob = Start-Job -ScriptBlock `
			{ `
				$username = $args[1]; $password = $args[2]; $ip = $args[3]; $port = $args[4]; $jcommand = $args[5]; `
				cd $args[0]; `
				#Write-Host ".\tools\plink.exe -t -C -v -pw $password -P $port $username@$ip $jcommand";`
				C:\azure-linux-automation\tools\plink.exe -C -v -pw $password -P $port $username@$ip $jcommand;`
			} `
			-ArgumentList $currentDir, $username, $password, $ip, $port, $linuxDroneCommand

$jobState = get-job $runLinuxDroneJob.Id
While($jobState -eq "Running") {
    write-host "Sleeping..."
    sleep 1
    $jobState = get-job $runLinuxDroneJob.Id
}

receive-job $runLinuxDroneJob.Id