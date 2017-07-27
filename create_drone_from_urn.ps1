param (
    [Parameter(Mandatory=$true)] [string[]] $vmNames,

    [Parameter(Mandatory=$true)] [string[]] $blobURNs,

    [Parameter(Mandatory=$false)] [string] $testCycle="BVT",

    [Parameter(Mandatory=$false)] [string] $resourceGroup="jpl_intake_rg",
    [Parameter(Mandatory=$false)] [string] $SA="jplintakestorageacct",

    [Parameter(Mandatory=$false)] [string] $cleanContainer="original-images",
    [Parameter(Mandatory=$false)] [string] $bvtContainer="ready-for-bvt",

    [Parameter(Mandatory=$false)] [string] $NSG="JPL-NSG-1",
    [Parameter(Mandatory=$false)] [string] $location="westus"
)
    

## Compute
. "C:\Framework-Scripts\secrets.ps1"

if ($vmNames.Count -ne $blobURNs.Count) {
    Write-Host "Please procvide the same number of names and URNs."
    exit 1
} else {
    Write-Host "There are $vmNames.Count() left..."
}

Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'
Select-AzureRmSubscription -SubscriptionId "$AZURE_SUBSCRIPTION_ID"
Set-AzureRmCurrentStorageAccount –ResourceGroupName $resourceGroup –StorageAccountName $SA

# Global
$location = "westus"

## Storage
$storageType = "Standard_D2"

## Network
$subnet1Name = "SmokeSubnet-1"
$vnetName = "SmokeVNet"
$vnetAddressPrefix = "10.0.0.0/16"
$vnetSubnetAddressPrefix = "10.0.0.0/24"

$vmSize = "Standard_D2"
#
#  Yes, these are done sequentially, not in parallel.  I will figure that out later :)
#
$i = 0
while ($i -lt $vmNames.Count) {
    $blobURN = $all_URNs[$i]
    $i++
    Write-Host "Preparing machine $vmName for service as a drone..."

    $nicname = $vmName + "-NIC"

    $blobURIRaw="https://jplintakestorageacct.blob.core.windows.net/$bvtContainer/" + $vmName + "-JPL-1.vhd"
    Write-Host "Clearing any old images..." -ForegroundColor Green
    Write-Host "Making sure the VM is stopped..."  
    Get-AzureRmVm -ResourceGroupName $resourceGroup -status | Where-Object -Property Name -Like "$vmName*" | where-object -Property PowerState -eq -value "VM running" | Stop-AzureRmVM -Force

    echo "Deleting any existing VM"
    Get-AzureRmVm -ResourceGroupName $resourceGroup -status | Where-Object -Property Name -Like "$vmName*" | Remove-AzureRmVM -Force

    Get-AzureStorageBlob -Container $bvtContainer -Prefix $vmName | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $bvtContainer}
    $destUri = $blobURIRaw.Replace($bvtContainer,$cleanContainer)

    Write-Host "Attempting to create virtual machine $vmName.  This may take some time." -ForegroundColor Green
    ## Setup local VM object
    # $cred = Get-Credential
    Write-Host "Creating machine $newVMName in RG $destRG and SA $destSA"

    # C:\Framework-Scripts\launch_single_azure_vm.ps1 -vmName $newVMName -resourceGroup $destRG -storageAccount $destSA -containerName $destContainer `
      #                                                  -network $network -subnet $subnet -NSG $NSG #  -addAdminUser $TEST_USER_ACCOUNT_NAME `
       #                                                 # -adminUser $TEST_USER_ACCOUNT_NAME -adminPW $TEST_USER_ACCOUNT_PAS2


       $nicName

    az vm create -n $vmName -g $resourceGroup -l $location --image $blobURN --storage-container-name $bvtContainer --use-unmanaged-disk --nsg $NSG `
       --subnet $subnet1Name --vnet-name $vnetName  --storage-account $SA --os-disk-name $vmName --admin-password $TEST_USER_ACCOUNT_PAS2 --admin-username $TEST_USER_ACCOUNT_NAME `
       --authentication-type "password" --vnet-name $vnetName
   

    #
    #  Just because it's up doesn't mean it's ready.  Wait a minute here...
    sleep(60)

    $currentDir="C:\Framework-Scripts"
    $username="$TEST_USER_ACCOUNT_NAME"
    $password="$TEST_USER_ACCOUNT_PAS2"
    $port=22
    $pipName = $vmName + "PublicIP"
    $ip=(Get-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup -Name $pipName).IpAddress

    #
    #  Send make_drone to the new machine
    #
    #  The first one gets the machine added to known_hosts
    echo "y" | C:\azure-linux-automation\tools\pscp C:\Framework-Scripts\make_drone.sh $username@$ip`:/tmp

    #
    #  Now transfer the file
    C:\azure-linux-automation\tools\dos2unix.exe -n C:\Framework-Scripts\make_drone.sh c:\temp\make_drone.sh
    C:\azure-linux-automation\tools\dos2unix.exe -n C:\Framework-Scripts\secrets.sh c:\temp\secrets.sh
    C:\azure-linux-automation\tools\dos2unix.exe -n C:\Framework-Scripts\secrets.ps1 c:\temp\secrets.ps1
    echo $password | C:\azure-linux-automation\tools\pscp  C:\temp\make_drone.sh $username@$ip`:/tmp
    echo $password | C:\azure-linux-automation\tools\pscp  C:\temp\secrets.sh $username@$ip`:/tmp
    echo $password | C:\azure-linux-automation\tools\pscp  C:\temp\secrets.ps1 $username@$ip`:/tmp


    C:\azure-linux-automation\tools\dos2unix.exe .\rpm_install_azure_test_prereq.sh c:\temp\rpm_install_azure_test_prereq.sh
    echo $password | C:\azure-linux-automation\tools\pscp C:\temp\rpm_install_azure_test_prereq.sh $username@$ip`:/tmp

    C:\azure-linux-automation\tools\dos2unix.exe .\deb_install_azure_test_prereq.sh c:\temp\deb_install_azure_test_prereq.sh
    echo $password | C:\azure-linux-automation\tools\pscp C:\temp\deb_install_azure_test_prereq.sh $username@$ip`:/tmp

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

    $setupJobID = $runLinuxSetupJob.Id
    write-host "Job $setupJobId launched to chmod make_drone"
    sleep 1
    $jobState = (get-job $setupJobID).State
    While($jobState -eq "Running") {
        sleep 10
        $jobState = (get-job $setupJobId).State
    }

    Write-Host "Job $setupJobId state at completion was $jobState"

    #
    #  This should be empty
    receive-job $setupJobID | Out-File $LogDir\$randomFileName
    $chmod_out2 = Get-Content $LogDir\$randomFileName
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
    $randomFileName = $vmName + "_make_drone.log"
    echo "make_drone for $vmName starting..." | Out-File $LogDir\$randomFileName -Force

    While($jobState -eq "Running") {
        sleep 10
        $jobState = (get-job $droneJobId).State
        receive-job $droneJobId | Out-File $LogDir\$randomFileName -Append
        Get-Content $LogDir\$randomFileName -Tail 3
    }

    Write-Host "Job $droneJobId state at completion was $jobState"

    #
    #  Get the results of that
    receive-job $droneJobId | Out-File $LogDir\$randomFileName -Append
    $out2 = Get-Content $LogDir\$randomFileName
    Write-Host $out2
}

exit 0