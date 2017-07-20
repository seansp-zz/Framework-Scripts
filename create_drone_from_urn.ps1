﻿param (
    [Parameter(Mandatory=$true)] [string] $vmName="Unset",

    [Parameter(Mandatory=$true)] [string] $blobURN="Unset",

    [Parameter(Mandatory=$false)] [string] $testCycle="BVT",

    [Parameter(Mandatory=$false)] [string] $resourceGroup="jpl_intake_rg",
    [Parameter(Mandatory=$false)] [string] $SA="jplintakestorageacct",

    [Parameter(Mandatory=$false)] [string] $cleanContainer="original-images",
    [Parameter(Mandatory=$false)] [string] $bvtContainer="ready-for-bvt",

    [Parameter(Mandatory=$false)] [string] $NSG="JPL-NSG-1",
    [Parameter(Mandatory=$false)] [string] $location="westus"
)
    
$vnetName="JPL-VNet-1"
$subnetName="JPL-Subnet-1"

Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'
Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4"
Set-AzureRmCurrentStorageAccount –ResourceGroupName $resourceGroup –StorageAccountName $SA

# Global
$location = "westus"

## Storage
$storageType = "Standard_D2"

## Network
$nicname = $name + "-NIC"
$subnet1Name = "JPS-Subnet-1"
$vnetName = "JPL-VNet-1"
$vnetAddressPrefix = "10.0.0.0/16"
$vnetSubnetAddressPrefix = "10.0.0.0/24"

## Compute

$vmSize = "Standard_A2"

$osDiskName = $vmName + "-osDisk"
$blobURIRaw="https://jplintakestorageacct.blob.core.windows.net/$bvtContainer/" + $vnName + "-JPL-1.vhd"
Write-Host "Clearing any old images..." -ForegroundColor Green
Get-AzureStorageBlob -Container $bvtContainer -Prefix $vmName | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $bvtContainer}
$destUri = $blobURIRaw.Replace($bvtContainer,$cleanContainer)

Write-Host "Attempting to create virtual machine $vmName.  This may take some time." -ForegroundColor Green
## Setup local VM object
# $cred = Get-Credential
az vm create -n $vmName -g $resourceGroup -l $location --image $blobURN --storage-container-name $bvtContainer --use-unmanaged-disk --nsg $NSG `
   --subnet $subnet1Name --vnet-name $vnetName  --storage-account $SA --os-disk-name $vmName --admin-password 'P@ssW0rd-1_K6' --admin-username "mstest" `
   --authentication-type "password"

$currentDir="C:\Framework-Scripts"
$username="mstest"
$password="P@ssW0rd-1_K6"
$port=22
$pipName = $vmName + "PublicIP"
$ip=(Get-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup -Name $pipName).IpAddress

#
#  Send make_drone to the new machine
#
#  The first one gets the machine added to known_hosts
echo "y" | C:\azure-linux-automation\tools\pscp C:\Framework-Scripts\make_drone.sh mstest@$ip`:/tmp

#
#  Now transfer the file
C:\azure-linux-automation\tools\dos2unix.exe .\make_drone.sh
echo $password | C:\azure-linux-automation\tools\pscp C:\Framework-Scripts\make_drone.sh mstest@$ip`:/tmp

C:\azure-linux-automation\tools\dos2unix.exe .\rpm_install_azure_test_prereq.sh
echo $password | C:\azure-linux-automation\tools\pscp C:\Framework-Scripts\rpm_install_azure_test_prereq.sh mstest@$ip`:/tmp

C:\azure-linux-automation\tools\dos2unix.exe .\deb_install_azure_test_prereq.sh
echo $password | C:\azure-linux-automation\tools\pscp C:\Framework-Scripts\deb_install_azure_test_prereq.sh mstest@$ip`:/tmp

$chmodCommand="chmod 755 /tmp/make_drone.sh"
$runDroneCommand="/tmp/make_drone.sh"
$linuxChmodCommand="`"echo $password | sudo -S bash -c `'$chmodCommand`'`""
$linuxDroneCommand="`"echo $password | sudo -S bash -c `'$runDroneCommand`'`""
$randomFileName = $vmName + "_chmod.log"
write-host "Logging to file $randomFileName"
$LogDir = "c:\temp\job_logs"

#
#  chmod the thing
$runLinuxSetupJob = Start-Job -ScriptBlock `
			{ `
				$username = $args[1]; $password = $args[2]; $ip = $args[3]; $port = $args[4]; $jcommand = $args[5]; `
				cd $args[0]; `
				#Write-Host ".\tools\plink.exe -t -C -v -pw $password -P $port $username@$ip $jcommand";`
				C:\azure-linux-automation\tools\plink.exe -C -v -pw $password -P $port $username@$ip $jcommand;`
			} `
			-ArgumentList $currentDir, $username, $password, $ip, $port, $linuxChmodCommand

$setupJobId = $runLinuxSetupJob.Id
write-host "Job $setupJobId launched to chmod make_drone"
sleep 1
$jobState = get-job $setupJobId
While($jobState -eq "Running") {
    write-host "Sleeping..."
    sleep 1
    $jobState = get-job $setupJobId
}

Write-Host "Job $setupJobId state at completion was $jobState"

#
#  This should be empty
$chmod_out = receive-job $setupJobId 2> $LogDir\$randomFileName
$chmod_out2 = Get-Content $LogDir\$randomFileName
Write-Host $chmod_out
Write-Host $chmod_out2

#
#  Now run make_drone
$runLinuxDroneJob = Start-Job -ScriptBlock `
			{ `
				$username = $args[1]; $password = $args[2]; $ip = $args[3]; $port = $args[4]; $jcommand = $args[5]; `
				cd $args[0]; `
				#Write-Host ".\tools\plink.exe -t -C -v -pw $password -P $port $username@$ip $jcommand";`
				C:\azure-linux-automation\tools\plink.exe -C -v -pw $password -P $port $username@$ip $jcommand;`
			} `
			-ArgumentList $currentDir, $username, $password, $ip, $port, $linuxDroneCommand

$droneJobId = $runLinuxDroneJob.Id
write-host "Job $droneJobId launched to turn the machine into a drone..."
sleep 1
$jobState = get-job $droneJobId
While($jobState -eq "Running") {
    write-host "Sleeping..."
    sleep 1
    $jobState = get-job $droneJobId
}

Write-Host "Job $droneJobId state at completion was $jobState"

#
#  Get the results of that
$randomFileName = $vmName + "_make_drone.log"
$out = receive-job $droneJobId 2> $LogDir\$randomFileName
$out2 = Get-Content $LogDir\$randomFileName
Write-Host $out
Write-Host $out2