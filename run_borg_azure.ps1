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
$rg="azureSmokeResourceGroup"
$nm="azuresmokestoragesccount"  

class MonitoredMachine {
    [string] $name="unknown"
    [string] $status="Unitialized"
    [string] $ipAddress="Unitialized"
    $session
}

$timer=New-Object System.Timers.Timer

[System.Collections.ArrayList]$global:monitoredMachines = @()

function copy_azure_machines {

    Write-Host "Importing the context...." -ForegroundColor green
    Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'

    Write-Host "Selecting the Azure subscription..." -ForegroundColor green
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

    Write-Host "Getting the list of machines and disks..."  -ForegroundColor green
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
                Write-Host "Removing previous resource group for machine $vmName"  -ForegroundColor green
                Remove-AzureRmResourceGroup -Name $newRGName -Force
            }
            Write-Host "Creating new resource group for VM $vmName" -ForegroundColor green
            New-AzureRmResourceGroup -Name $newRGName -Location westus

            Write-Host "Making sure the VM is stopped..."  -ForegroundColor green
            stop-vm $vmName -TurnOff -Force

            Write-Host "Creating a new VM config..."   -ForegroundColor green
            $vm=New-AzureRmVMConfig -vmName $vmName -vmSize 'Standard_D2'

            Write-Host "Assigning resource group $rg network and subnet config to new machine" -ForegroundColor green
            $VMVNETObject = Get-AzureRmVirtualNetwork -Name SmokeVNet -ResourceGroupName $rg
            $VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name SmokeSubnet-1 -VirtualNetwork $VMVNETObject

            Write-Host "Creating the public IP address"  -ForegroundColor green
            $pip = New-AzureRmPublicIpAddress -ResourceGroupName $newRGName -Location $location `
                    -Name $vmName -AllocationMethod Dynamic -IdleTimeoutInMinutes 4

            Write-Host "Creating the network interface"  -ForegroundColor green
            $VNIC = New-AzureRmNetworkInterface -Name $vmName -ResourceGroupName $newRGName -Location westus -SubnetId $VMSubnetObject.Id -publicipaddressid $pip.Id

            Write-Host "Adding the network interface"  -ForegroundColor green
            Add-AzureRmVMNetworkInterface -VM $vm -Id $VNIC.Id

            Write-Host "Getting the source disk URI" -ForegroundColor green
            $c = Get-AzureStorageContainer -Name $destContainerName
            $blobName=$vmName + ".vhd"
            $blobURIRaw = $c.CloudBlobContainer.Uri.ToString() + "/" + $blobName

            Write-Host "Setting the OS disk to interface $blobURIRaw" -ForegroundColor green
            Set-AzureRmVMOSDisk -VM $vm -Name $vmName -VhdUri $blobURIRaw -CreateOption "Attach" -linux
        }
        Catch
        {
            Write-Host "Caught exception attempting to create the Azure VM.  Aborting..." -ForegroundColor Red
            return 1
        }

        try {
            Write-Host "Starting the VM"  -ForegroundColor green
            $global:num_remaining++
            $NEWVM = New-AzureRmVM -ResourceGroupName $newRGName -Location westus -VM $vm
            if ($NEWVM -eq $null) {
                Write-Host "FAILED TO CREATE VM!!" 
                $global:num_remaining--
            } else {
                Write-Host "VM number $global:num_remaining started successfully..." -ForegroundColor Green

                $machine = new-Object MonitoredMachine
                $machine.name = $vmName
                $machine.status = "Booting" # $status
                $global:monitoredMachines.Add($machine)
            }
        }
        Catch
        {
            Write-Host "Caught exception attempting to start the new VM.  Aborting..." -ForegroundColor red
            return 1
        }
    }
}

$action={
    function checkMachine ([MonitoredMachine]$machine) {
        $machineName=$machine.name
        $machineStatus=$machine.status
        $machineIP=$machine.ipAddress

        if ($machineStatus -eq "Completed" -or $global:num_remaining -eq 0) {
            Write-Host "Machine $machineName is in state $machineStatus"
            return 0
        }

        Write-Host "Checking boot results for machine $machineName" -ForegroundColor green

        if ($machineStatus -ne "Booting") {
            Write-Host "??? Machine was not in state Booting.  Cannot process" -ForegroundColor red
            return 1
        }

        $expected_ver=Get-Content C:\temp\expected_version

        $failed=0
        $newRGName=$machineName + "-SmokeRG"

        #
        #  Attempt to create the PowerShell PSRP session
        #
        $machineIsUp = $false
        foreach ($localMachine in $global:monitoredMachines) {
            [MonitoredMachine]$monitoredMachine=$localMachine

            if ($localMachine.Name -eq $machineName) {
                $ip=Get-AzureRmPublicIpAddress -ResourceGroupName $newRGName
                $ipAddress=$ip.IpAddress
                $localMachine.ipAddress = $ipAddress

                Write-Host "Creating PowerShell Remoting session to machine at IP $ipAddress"  -ForegroundColor green
                $o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
                $pw=convertto-securestring -AsPlainText -force -string 'P@$$w0rd!'
                $cred=new-object -typename system.management.automation.pscredential -argumentlist "mstest",$pw
                $localMachine.session=new-PSSession -computername $ipAddress -credential $cred -authentication Basic -UseSSL -Port 443 -SessionOption $o
                if ($?) {
                    $machineIsUp = $true
                } else {
                    return 0
                }
                break
            }
        }

        
        try {            
            $installed_vers=invoke-command -session $localMachine.session -ScriptBlock {/bin/uname -r}
            Write-Host "$machineName installed version retrieved as $installed_vers" -ForegroundColor Cyan
        }
        Catch
        {
            Write-Host "Caught exception attempting to verify Azure installed kernel version.  Aborting..." -ForegroundColor red
        }

        <#
        try {
            Write-Host "Stopping the Azure VM"  -ForegroundColor green
            Stop-AzureRmVm -force -ResourceGroupName $newRGName -name $machineName

            Write-Host "Removing resource group."  -ForegroundColor green
            Remove-AzureRmResourceGroup -Name $newRGName -Force
        }
        Catch
        {
            Write-Host "Caught exception attempting to clean up Azure.  Aborting..." -ForegroundColor red
        }
        #>

        #
        #  Now, check for success
        #
        if ($expected_ver.CompareTo($installed_vers) -ne 0) {
            Write-Host "Machine is up, but the kernel version is $installed_vers when we expected $expected_ver.  Waiting to see if it reboots." -ForegroundColor Red
            Write-Host "(let's see if there is anything running with the name Kernel on the remote machine)"
            invoke-command -session $localMachine.session -ScriptBlock {ps -efa | grep -i linux}

        } else {
            Write-Host "Machine came back up as expected.  kernel version is $installed_vers" -ForegroundColor green
            $localMachine.Status = "Completed"
            $global:num_remaining--
        }
    }

    # Write-Host "Checking elapsed = $global:elapsed against interval limit of $global:boot_timeout_intervals" -ForegroundColor Yellow
    if ($elapsed -ge $global:boot_timeout_intervals) {
        Write-Host "Timer has timed out." -ForegroundColor red
        $global:completed=1
    }

    #
    #  Check for Hyper-V completion
    #
    foreach ($localMachine in $global:monitoredMachines) {
        [MonitoredMachine]$monitoredMachine=$localMachine
        $monitoredMachineName=$monitoredMachine.name
        $monitoredMachineStatus=$monitoredMachine.status

        write-host "Looking at machine $monitoredMachineName, current status $monitoredMachineStatus"

        if ($monitoredMachineStatus -ne "Completed") {
            Write-Host "Checking machine $monitoredMachineName..." -ForegroundColor yellow
            checkMachine $monitoredMachine
        }
    }

    if ($global:num_remaining -eq 0) {
        Write-Host "***** All machines have reported in."  -ForegroundColor magenta
        if ($global:failed -eq $true) {
            Write-Host "One or more machines have failed to boot.  This job has failed." -ForegroundColor Red
        }
        Write-Host "Stopping the timer" -ForegroundColor green
        $global:completed=1
    }

    if (($global:elapsed % 100) -eq 0) {
        Write-Host "Waiting for remote machines to complete all testing.  There are $global:num_remaining machines left.." -ForegroundColor green

        foreach ($localMachine in $global:monitoredMachines) {
            [MonitoredMachine]$monitoredMachine=$localMachine

            if ($monitoredMachineStatus -ne "Completed") {
                Write-Host "--- Machine $monitoredMachineName has not completed yet" -ForegroundColor yellow
            }
                        
            if ($machine.session -ne $null) {
                Write-Host "Last three lines of the log file..." -ForegroundColor Magenta                
                $ipAddress=$monitoredMachine.ipAddress
                $last_lines=invoke-command -session $machine.session -ScriptBlock {get-content /tmp/borg_progress.log | Select-Object -Last 3 | Write-Host  -ForegroundColor Green }
                write-host$last_lines
            }
        }
    }
    Write-Host "Leaving timer.  Completed flag is $global:completed"

    [Console]::Out.Flush() 
}

unregister-event AzureBootTimer -ErrorAction SilentlyContinue

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


#
#  Wait for the machines to report back
#                    
write-host "$global:num_left machines have been launched.  Waiting for completion..."

Write-Host "                          Initiating temporal evaluation loop (Starting the timer)" -ForegroundColor yellow
unregister-event AzureBootTimer
Register-ObjectEvent -InputObject $timer -EventName elapsed –SourceIdentifier AzureBootTimer -Action $action

copy_azure_machines
launch_azure_vms

$timer.Interval = 500
$timer.Enabled = $true
$timer.start()

Write-Host "Finished starting the VMs.  Completed is $global:completed"
while ($global:completed -eq 0) {
    start-sleep -s 1
}

Write-Host "                         Exiting Temporal Evaluation Loop (Unregistering the timer)" -ForegroundColor yellow
$timer.stop()
unregister-event AzureBootTimer

Write-Host "Checking results" -ForegroundColor green

if ($global:num_remaining -eq 0) {
    Write-Host "All machines have come back up.  Checking results." -ForegroundColor green
    
    if ($global:failed -eq $true) {
        Write-Host "Failures were detected in reboot and/or reporting of kernel version.  See log above for details." -ForegroundColor red
        Write-Host "             BORG TESTS HAVE FAILED!!" -ForegroundColor red
    } else {
        Write-Host "All machines rebooted successfully to kernel version $global:booted_version" -ForegroundColor green
        Write-Host "             BORG has been passed successfully!" -ForegroundColor yellow
    }
} else {
        Write-Host "Not all machines booted in the allocated time!" -ForegroundColor red
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
