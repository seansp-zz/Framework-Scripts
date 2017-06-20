$global:completed=0
$global:elapsed=0
$global:interval=500
$global:boot_timeout_minutes=20
$global:boot_timeout_intervals=$interval*($boot_timeout_minutes*60*(1000/$interval))
$global:num_expected=0
$global:num_remaining=0
$global:failed=0
$global:booted_version="Unknown"

$location="westus"
$destAccountName="azuresmokestoragesccount"
$destContainerName="working-vhds"
$neededVms_array=@()
$neededVms = {$neededVms_array}.Invoke()
$copyblobs_array=@()
$copyblobs = {$copyblobs_array}.Invoke()
$destContainerName = "working-vhds"

class MonitoredMachine {
    [string] $name="unknown"
    [string] $status="Unitialized"
    [string] $ipAddress="Unitialized"
}

$timer=New-Object System.Timers.Timer

[System.Collections.ArrayList]$global:monitoredMachines = @()

function copy_azure_machines {
    $rg="azureSmokeResourceGroup"
    $nm="azuresmokestoragesccount"  
    

    write-host "Importing the context...." -ForegroundColor green
    Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'

    write-host "Selecting the Azure subscription..." -ForegroundColor green
    Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4"
    Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $nm

    $key=Get-AzureRmStorageAccountKey -ResourceGroupName $rg -Name $nm
    $context=New-AzureStorageContext -StorageAccountName $destAccountName -StorageAccountKey $key[0].Value

    #
    #  Copy the latest packages up to Azure
    #
    $packages=get-childitem -path z:
    Remove-Item -Path C:\temp\file_list
    foreach ($package in $packages) {
        $package.name | out-file -Append C:\temp\file_list
    }

    Get-ChildItem z:\ | Set-AzureStorageBlobContent -Container "latest-packages" -force
    Get-ChildItem C:\temp\file_list | Set-AzureStorageBlobContent -Container "latest-packages" -force

    #
    #  Clear the working container
    #
    Get-AzureStorageBlob -Container $destContainerName -blob * | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $destContainerName}

    #
    #  Copy the kernel packages to Azure.
    #
    dir z: > c:\temp\file_list
    Get-ChildItem z:\ | Set-AzureStorageBlobContent -Container "latest-packages" -force

    Write-Host "Getting the list of machines and disks..."
    $smoke_machines=Get-AzureRmVm -ResourceGroupName $rg
    $smoke_disks=Get-AzureRmDisk -ResourceGroupName $rg

    foreach ($machine in $smoke_machines) {
        $vhd_name = $machine.Name + ".vhd"
        $vmName = $machine.Name

        $neededVMs.Add($vmName)

        $uri=$machine.StorageProfile.OsDisk.Vhd.Uri
    
        $blob = Start-AzureStorageBlobCopy -AbsoluteUri $uri -destblob $vhd_name -DestContainer $destContainerName -DestContext $context -Force

        $copyblobs.Add($vhd_name)
    }

    $allDone = $true
    foreach ($blob in $copyblobs) {
        $status = Get-AzureStorageBlobCopyState -Blob $blob -Container $destContainerName -WaitForComplete

        $status
    }
}


function launch_azure_vms {
    foreach ($vmName in $neededVms) {
        $newRGName=$vmName + "-SmokeRG"
        $groupExists=$false
        $existingRG=Get-AzureRmResourceGroup -Name $newRGName -ErrorAction SilentlyContinue 
        
        if ($? -eq $true) {
            $groupExists=$true
        }

        try {
            if ($groupExists -eq $true)
            {
                echo "Removing previous resource group for machine $vmName" 
                Remove-AzureRmResourceGroup -Name $newRGName -Force
            }
            New-AzureRmResourceGroup -Name $newRGName -Location westus

            echo "Making sure the VM is stopped..." 
            stop-vm $vmName

            echo "Creating a new VM config..."  
            $vm=New-AzureRmVMConfig -vmName $vmName -vmSize 'Standard_D2'

            echo "Assigning resource group $rg network and subnet config to new machine"
            $VMVNETObject = Get-AzureRmVirtualNetwork -Name SmokeVNet -ResourceGroupName $rg
            $VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name SmokeSubnet-1 -VirtualNetwork $VMVNETObject

            echo "Creating the public IP address" 
            $pip = New-AzureRmPublicIpAddress -ResourceGroupName $newRGName -Location $location `
                    -Name $vmName -AllocationMethod Dynamic -IdleTimeoutInMinutes 4

            echo "Creating the network interface" 
            $VNIC = New-AzureRmNetworkInterface -Name $vmName -ResourceGroupName $newRGName -Location westus -SubnetId $VMSubnetObject.Id -publicipaddressid $pip.Id

            echo "Adding the network interface" 
            Add-AzureRmVMNetworkInterface -VM $vm -Id $VNIC.Id

            echo "Getting the source disk URI"
            $c = Get-AzureStorageContainer -Name $destContainerName
            $blobName=$vmName + ".vhd"
            $blobURIRaw = $c.CloudBlobContainer.Uri.ToString() + "/" + $blobName

            echo "Setting the OS disk to interface $blobURIRaw"
            Set-AzureRmVMOSDisk -VM $vm -Name $vmName -VhdUri $blobURIRaw -CreateOption "Attach" -linux
        }
        Catch
        {
            echo "Caught exception attempting to create the Azure VM.  Aborting..."
            exit 1
        }

        try {
            echo "Starting the VM" 
            $NEWVM = New-AzureRmVM -ResourceGroupName $newRGName -Location westus -VM $vm
            if ($NEWVM -eq $null) {
                echo "FAILED TO CREATE VM!!" 
                exit 1
            } else {
                $global:num_remaining++
            }
        }
        Catch
        {
            echo "Caught exception attempting to start the new VM.  Aborting..."
            exit 1
        }
    }

$action={
    function checkMachine ([MonitoredMachine]$machine) {
        $machineName=$machine.name
        $machineStatus=$machine.status
        $machineIP=$machine.ipAddress

        if ($machineStatus -eq "Completed") {
            return
        }

        $o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
        $pw=convertto-securestring -AsPlainText -force -string 'P@$$w0rd!'
        $cred=new-object -typename system.management.automation.pscredential -argumentlist "mstest",$pw

        Write-Host "Checking boot results for machine $machineName" -ForegroundColor green

        if ($machineStatus -ne "Booting") {
            Write-Host "??? Machine was not in state Booting.  Cannot process"
            return
        }

        $expected_ver=Get-Content C:\temp\expected_version

        $failed=0
        $newRGName=$machineName + "-SmokeRG"

        try {
            $ip=Get-AzureRmPublicIpAddress -ResourceGroupName $newRGName
            $ipAddress=$ip.IpAddress
            # echo "Creating PowerShell Remoting session to machine at IP $ipAddress" 
            $session=new-PSSession -computername $ipAddress -credential $cred -authentication Basic -UseSSL -Port 443 -SessionOption $o

            if ($session -eq $null) {
                # echo "FAILED to contact Azure guest VM" 
                goto :NOCONNECTION
            }

            $installed_vers=invoke-command -session $session -ScriptBlock {/bin/uname -r}
            remove-pssession $session
            echo "$machineName installed version retrieved as $installed_vers"
            $machine.Status = "Completed"
            $global:num_remaining--
        }
        Catch
        {
            echo "Caught exception attempting to verify Azure installed kernel version.  Aborting..."
            goto :NOCONNECTION
        }

        try {
            echo "Stopping the Azure VM" 
            Stop-AzureRmVm -force -ResourceGroupName $newRGName -name $machineName

            echo "Removing resource group." 
            Remove-AzureRmResourceGroup -Name $newRGName -Force
        }
        Catch
        {
            echo "Caught exception attempting to clean up Azure.  Aborting..."
            goto :NOCONNECTION
        }

        #
        #  Now, check for success
        #
        if ($expected_ver.CompareTo($installed_vers) -ne 0) {
            $global:failed = 1
            $machine.Status = "Completed"
            $global:num_remaining--
        }
     }
     
     :NOCONNECTION
    }

    write-host "Checking elapsed = $global:elapsed against interval limit of $global:boot_timeout_intervals"    
    if ($elapsed -ge $global:boot_timeout_intervals) {
        write-host "Timer has timed out." -ForegroundColor red
        $global:completed=1
    }

    #
    #  Check for Hyper-V completion
    #
    foreach ($localMachine in $global:monitoredMachines) {
        [MonitoredMachine]$monitoredMachine=$localMachine
        $monitoredMachineName=$monitoredMachine.name
        $monitoredMachineStatus=$monitoredMachine.status

        if ($monitoredMachineStatus -ne "Completed") {
            Write-Host "Checking machine..."
            checkMachine $monitoredMachine
        }
    }

    if ($global:num_remaining -eq 0) {
        write-host "***** All machines have reported in."  -ForegroundColor magenta
        if ($global:failed) {
            Write-Host "One or more machines have failed to boot.  This job has failed." -ForegroundColor Red
        }
        write-host "Stopping the timer" -ForegroundColor green
        $global:completed=1
    }

    if (($global:elapsed % 10000) -eq 0) {
        Write-Host "Waiting for remote machines to complete all testing.  There are $global:num_remaining machines left.." -ForegroundColor green

        foreach ($localMachine in $global:monitoredMachines) {
            [MonitoredMachine]$monitoredMachine=$localMachine

            if ($monitoredMachineStatus -ne "Completed") {
                Write-Host "--- Machine $monitoredMachineName has not completed yet"
            }
            $ipAddress=$monitoredMachine.ipAddress

            # echo "Creating PowerShell Remoting session to machine at IP $ipAddress" 
            $session=new-PSSession -computername $ipAddress -credential $cred -authentication Basic -UseSSL -Port 443 -SessionOption $o

            if ($session -eq $null) {
                # echo "FAILED to contact Azure guest VM" 
                goto :NOCONNECTION
            }

            $last_lines=invoke-command -session $session -ScriptBlock {get-content /tmp/borg_progress.log | Select-Object -Last 3 | write-host  -ForegroundColor cyan}
            remove-pssession $session                        
         }
    }

    [Console]::Out.Flush() 
}

Write-Host "    " -ForegroundColor green
Write-Host "                 **********************************************" -ForegroundColor yellow
Write-Host "                 *                                            *" -ForegroundColor yellow
Write-Host "                 *            Microsoft Linux Kernel          *" -ForegroundColor yellow
Write-Host "                 *     Basic Operational Readiness Gateway    *" -ForegroundColor yellow
Write-Host "                 * Host Infrastructure Validation Environment *" -ForegroundColor yellow
Write-Host "                 *                                            *" -ForegroundColor yellow
Write-Host "                 *           Welcome to the BORG HIVE         *" -ForegroundColor yellow
Write-Host "                 **********************************************" -ForegroundColor yellow
Write-Host "    "
Write-Host "          Initializing the CUBE (Customizable Universal Base of Execution)" -ForegroundColor yellow
Write-Host "    "

#
#  Clean up the sentinel files
#
Write-Host "   "
Write-Host "                                BORG CUBE is initialized"                   -ForegroundColor Yellow
Write-Host "              Starting the Dedicated Remote Nodes of Execution (DRONES)" -ForegroundColor yellow
Write-Host "    "

copy_azure_machines

#
#  Wait for the machines to report back
#                    
write-host "                          Initiating temporal evaluation loop (Starting the timer)" -ForegroundColor yellow
unregister-event bootTimer
Register-ObjectEvent -InputObject $timer -EventName elapsed –SourceIdentifier bootTimer -Action $action
$timer.Interval = 500
$timer.Enabled = $true
$timer.start()

launch_azure_vms

while ($global:completed -eq 0) {
    start-sleep -s 1
}

write-host "                         Exiting Temporal Evaluation Loop (Unregistering the timer)" -ForegroundColor yellow
$timer.stop()
unregister-event bootTimer

write-host "Checking results" -ForegroundColor green

if ($global:num_remaining -eq 0) {
    Write-Host "All machines have come back up.  Checking results." -ForegroundColor green
    
    if ($global:failed -eq $true) {
        Write-Host "Failures were detected in reboot and/or reporting of kernel version.  See log above for details." -ForegroundColor red
        write-host "             BORG TESTS HAVE FAILED!!" -ForegroundColor red
    } else {
        Write-Host "All machines rebooted successfully to kernel version $global:booted_version" -ForegroundColor green
        write-host "             BORG has been passed successfully!" -ForegroundColor yellow
    }
} else {
        write-host "Not all machines booted in the allocated time!" -ForegroundColor red
        Write-Host " Machines states are:" -ForegroundColor red
        foreach ($localMachine in $global:monitoredMachines) {
            [MonitoredMachine]$monitoredMachine=$localMachine
            $monitoredMachineName=$monitoredMachine.name
            $monitoredMachineState=$monitoredMachine.status
            Write-Host Machine "$monitoredMachineName is in state $monitoredMachineState" -ForegroundColor red
        }
    }

if ($global:failed -eq 0) {    
    Write-Host "     BORG is   Exiting with success.  Thanks for Playing" -ForegroundColor green
    exit 0
} else {
    Write-Host "     BORG is Exiting with failure.  Thanks for Playing" -ForegroundColor red
    exit 1
}
