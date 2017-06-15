$global:completed=0
$global:elapsed=0
$global:interval=500
$global:boot_timeout_minutes=20
$global:boot_timeout_intervals=$interval*($boot_timeout_minutes*60*(1000/$interval))
$global:num_expected=0
$global:num_remaining=0
$global:failed=0
$global:booted_version="Unknown"

$timer=New-Object System.Timers.Timer

function new-monitor()
{
    param ([string]$name="Unknown", 
           [string]$status="Unitialized")

    $monitoredMachine = New-Object PSObject

    $monitoredMachine | Add-Member MachineName $name
    $monitoredMachine | Add-Member Status $status

    return $monitoredMachine
}

$monitoredMachines_Array=@()
$global:monitoredMachines = {$monitoredMachines_Array}.Invoke()

function checkMachine($machine) {
    if ($machine.Status -ne "Booting") {
        return
    }

    Write-Host "Checking boot results for machine $machine" -ForegroundColor green

    $machineName=$machine.MachineName
    $resultsFile="c:\temp\boot_results\" + $machineName
    $progressFile="c:\temp\progress_logs\" + $machineName
    $res_dest="c:\temp\completed_boots\" + $machineName + "_boot"
    $prog_dest="c:\temp\completed_boots\" + $machineName + "_progress"

    if ((test-path $resultsFile) -eq 0) {
        return
    }

    $results=get-content $resultsFile
    $resultsSplit = $results.split(' ')
    $resultsWord=$resultsSplit[0]
    $resustsgot=$resultsSplit[1]

    if ($resultsSplit[0] -ne "Success") {
        $resultExpected = $resultsSplit[2]
        Write-Host "Machine $machineName rebooted, but wrong version detected.  Expected resultExpected but got $resustsgot" -ForegroundColor red
        $global:failed=$true
    } else {
        Write-Host "Machine rebooted successfully to kernel version " -ForegroundColor green
        $global:booted_version=$resustsgot
    }

    Move-Item $resultsFile -Destination $res_dest
    Move-Item $progressFile -Destination $prog_dest

    $machine.Status = "Azure"

    if ($global:failed -eq $false) {
        Write-Host "Chainging to Azure valication job..." -ForegroundColor green
        start-job -Name $machineName -ScriptBlock {C:\Framework-Scripts\run_borg_2.ps1 $args[0] } -ArgumentList @($machineName)
    } else {
        Write-Host "This, or another, machine has failed to boot.  Machines will not progress to Azure" -ForegroundColor red
        exit 1
    }
}

$action={
    $global:elapsed=$global:elapsed+$global:interval

    # write-host "Checking elapsed = $global:elapsed against interval limit of $global:boot_timeout_intervals"    
    if ($elapsed -ge $global:boot_timeout_intervals) {
        write-host "Timer has timed out." -ForegroundColor red
        $global:completed=1
    }

    #
    #  Check for Hyper-V completion
    foreach ($monitoredMachine in $global:monitoredMachines) {
        $monitoredMachineName=$monitoredMachine.MachineName
        $monitoredMachineStatus=$monitoredMachine.Status
        $bootFile="c:\temp\boot_results\" + $monitoredMachineName
        if ($monitoredMachineStatus -eq "Booting" -and (test-path $bootFile) -eq 1) {
            checkmachine($monitoredMachine)
        }
    }

    
    #
    #  Check for Azure completion
    #
    foreach ($monitoredMachine in $global:montiroedMachines) {
        # Write-Host "Checking state of Azure job $monitoredMachine.MachineName" -ForegroundColor green
        $monitoredMachineName=$monitoredMachine.MachineName
        $monitoredMachineStatus=$monitoredMachine.Status
        if ($monitoredMachineStatus -eq "Azure") {
            $jobStatus=get-job -Name $monitoredMachineName
            if ($jobStatus -eq $true) {
                $jobState = $jobStatus.State
                Write-Host "Current state is $jobState"

                if (($jobState -ne "Completed") -and 
                    ($jobState -ne "Failed")) {
                    sleep 10
                } elseif ($jobState -eq "Failed") {
                    Write-Host "Azure job $monitoredMachineName exited with FAILED state!" -ForegroundColor red
                    $global:failed = 1
                    $monitoredMachine.status = "Completed"
                    $global:num_remaining--
                } else {
                    Write-Host "Azure job $monitoredMachineName booted successfully." -ForegroundColor green
                    $monitoredMachine.status = "Completed"
                    $global:num_remaining--
                }
            }
        }
    }

    if ($global:num_remaining -eq 0) {
        write-host "***** All machines have reported in."  -ForegroundColor magenta
        if ($global:failed) {
            Write-Host "One or more machines have failed to boot.  This job has failed." -ForegroundColor Red
        }
        write-host "Stopping the timer" -ForegroundColor green
        $global:completed=1
        exit 1
    }
 
    if (($global:elapsed % 10000) -eq 0) {
        Write-Host "Waiting for remote machines to complete all testing.  There are $global:num_remaining machines left.." -ForegroundColor green

        foreach ($monitoredMachine in $global:monitoredMachines) {
            
            $monitoredMachineName=$monitoredMachine.MachineName
            $logFile="c:\temp\progress_logs\" + $monitoredMachineName
            $monitoredMachineStatus=$monitoredMachine.Status
            if ($monitoredMachineStatus -eq "Booting" -or $monitoredMachineStatus -eq "Azure") {
                if ((test-path $logFile) -eq 1) {
                    write-host "--- Last 3 lines of results from $logFile" -ForegroundColor magenta
                    get-content $logFile | Select-Object -Last 3 | write-host  -ForegroundColor cyan
                    write-host "---" -ForegroundColor magenta
                } else {
                    Write-Host "--- Machine $monitoredMachineName has not checked in yet"
                }
            }
        }

        [Console]::Out.Flush() 
    }
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
Write-Host "Cleaning up sentinel files..." -ForegroundColor green
remove-item -ErrorAction "silentlycontinue" C:\temp\completed_boots\*
remove-item -ErrorAction "silentlycontinue" C:\temp\boot_results\*
remove-item -ErrorAction "silentlycontinue" C:\temp\progress_logs\*

Write-Host "   "
Write-Host "                                BORG CUBE is initialized"                   -ForegroundColor Yellow
Write-Host "              Starting the Dedicated Remote Nodes of Execution (DRONES)" -ForegroundColor yellow
Write-Host "    "

Write-Host "Checking to see which VMs we need to bring up..." -ForegroundColor green
Write-Host "Errors may appear here depending on the state of the system.  They're almost all OK.  If things go bad, we'll let you know." -ForegroundColor Green
Write-Host "For now, though, please feel free to ignore the following errors..." -fore Green
Write-Host " "
Get-ChildItem 'D:\azure_images\*.vhd' |
foreach-Object {
    
    $vhdFile=$_.Name
    $status="Copying"

    $global:num_remaining++

    $vhdFileName=$vhdFile.Split('.')[0]
    
    $machine = new-monitor -name $vhdFileName -status $status
    $global:monitoredMachines.Add($machine)
    
    Write-Host "Stopping and cleaning any existing instances of machine $vhdFileName.  Any errors here may be ignored." -ForegroundColor green
    stop-vm -Name $vhdFileName -Force
    remove-vm -Name $vhdFileName -Force

    $machine.status = "Allocating"
    # Copy-Item $sourceFile $destFile -Force
    $destFile="d:\working_images\" + $vhdFile
    Remove-Item -Path $destFile -Force
    
    Write-Host "Copying VHD $vhdFileName to working directory..." -ForegroundColor green
    $jobName=$vhdFileName + "_copy_job"

    $existingJob = get-job  $jobName
    if ($? -eq $true) {
        stop-job $jobName
        remove-job $jobName
    }

    Start-Job -Name $jobName -ScriptBlock { robocopy /njh /ndl /nc /ns /np /nfl D:\azure_images\ D:\working_images\ $args[0] } -ArgumentList @($vhdFile)
}
Write-Host " "
Write-Host "Start paying attention to errors again..." -ForegroundColor green
Write-Host " "

while ($true) {
    Write-Host "Waiting for copying to complete..." -ForegroundColor green
    $copy_complete=$true
    Get-ChildItem 'D:\azure_images\*.vhd' |
    foreach-Object {
        $vhdFile=$_.Name
        $vhdFileName=$vhdFile.Split('.')[0]

        $jobName=$vhdFileName + "_copy_job"

        $jobStatus=get-job -Name $jobName
        $jobState = $jobStatus.State
        
        if (($jobState -ne "Completed") -and 
            ($jobState -ne "Failed")) {
            Write-Host "      Current state of job $jobName is $jobState" -ForegroundColor yellow
            $copy_complete = $false
        }
        elseif ($jobState -eq "Failed")
        {
            $global:failed = 1
            Write-Host "----> Copy job $jobName exited with FAILED state!" -ForegroundColor red
        }
        else
        {
            Write-Host "      Copy job $jobName completed successfully." -ForegroundColor green
        }    
    }

    if ($copy_complete -eq $false) {
        sleep 30
    } else {
        break
    }
}

if ($global:failed -eq 1) {
    write-host "Copy failed.  Cannot continue..."
    exit 1
}

Write-Host "All machines template images have been copied.  Starting the VMs in Hyper-V" -ForegroundColor green

Get-ChildItem 'D:\working_images\*.vhd' |
foreach-Object {   
    $vhdFile=$_.Name

    $vhdFileName=$vhdFile.Split('.')[0]
    
    foreach ($machine in $global:monitoredMachines) {
        $monitoredMachineName=$machine.MachineName
        if ($monitoredMachineName -eq $vhdFileName) {
             $machine.Status = "Booting"
             break
        }
    }
    
    $vhdPath="D:\working_images\"+$vhdFile   

    Write-Host "BORG DRONE $vhdFileName is starting" -ForegroundColor green

    new-vm -Name $vhdFileName -MemoryStartupBytes 7168mb -Generation 1 -SwitchName "Microsoft Hyper-V Network Adapter - Virtual Switch" -VHDPath $vhdPath
    if ($? -eq $false) {
        Write-Host "Unable to create Hyper-V VM.  The BORG cannot continue." -ForegroundColor Red
        exit 1
    }

    Start-VM -Name $vhdFileName
    if ($? -eq $false) {
        Write-Host "Unable to start Hyper-V VM.  The BORG cannot continue." -ForegroundColor Red
        exit 1
    }
}

#
#  Wait for the machines to report back
#                       
write-host "                          Initiating temporal evaluation loop (Starting the timer)" -ForegroundColor yellow
Register-ObjectEvent -InputObject $timer -EventName elapsed –SourceIdentifier bootTimer -Action $action
$timer.Interval = 500
$timer.Enabled = $true
$timer.start()

while ($global:completed -eq 0) {
    start-sleep -s 1
}

write-host "                         Exiting Temporal Evaluation Loop (Unregistering the timer)" -ForegroundColor green
$timer.stop()
unregister-event bootTimer

write-host "Checking results" -ForegroundColor green

if ($global:num_remaining -eq 0) {
    Write-Host "All machines have come back up.  Checking results." -ForegroundColor green
    
    if ($global:failed -eq $true) {
        Write-Host "Failures were detected in reboot and/or reporting of kernel version.  See log above for details." -ForegroundColor red
        write-host "                            BORG TESTS HAVE FAILED!!" -ForegroundColor red
    } else {
        Write-Host "All machines rebooted successfully to kernel version $global:booted_version" -ForegroundColor green
        write-host "                      BORG has been passed successfully!" -ForegroundColor green
    }
} else {
        write-host "Not all machines booted in the allocated time!" -ForegroundColor red
        Write-Host " Machines states are:" -ForegroundColor red
        foreach ($machine in $global:montiroedMachines) {
            echo "Machine $machine.MachnineName is in state $machine.state" -ForegroundColor red
        }
    }

foreach ($monitoredMachine in $global:montiroedMachines) {
        $monitoredMachineName=$monitoredMachine.Name
        $monitoredMachineState=$monitoredMachine.State

        Write-Host "Checking state of Azure job $monitoredMachineName" -ForegroundColor green

        $jobStatus=get-job -Name $monitoredMachineName
        $jobState = $jobStatus.State

        Write-Host "Current state is $jobState"

        if (($jobState -ne "Completed") -and 
            ($jobState -ne "Failed")) {
            sleep 10
        }
        elseif ($jobState -eq "Failed")
        {
            $global:failed = 1
            Write-Host "Azure job $monitoredMachine.MachineName exited with FAILED state!" -ForegroundColor red
            $monitoredMachine.status = "Completed"
        }
        else
        {
            Write-Host "Azure job $monitoredMachine.MachineName booted successfully." -ForegroundColor green
            $monitoredMachine.status = "Completed"
        }
    }

if ($global:failed -eq 0) {    
    Write-Host "                       BORG is   Exiting with success.  Thanks for Playing" -ForegroundColor green
    exit 0
} else {
    Write-Host "                        BORG is Exiting with failure.  Thanks for Playing" -ForegroundColor red
    exit 1
}
