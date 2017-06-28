param (
    [Parameter(Mandatory=$false)] [switch] $skipCopy
)

$global:completed=0
$global:elapsed=0
$global:interval=500
$global:boot_timeout_minutes=45
$global:boot_timeout_intervals=$interval*($boot_timeout_minutes*60*(1000/$interval))
$global:num_expected=0
$global:num_remaining=0
$global:failed=0
$global:booted_version="Unknown"

class MonitoredMachine {
    [string] $name="unknown"
    [string] $status="Unitialized"
}

$timer=New-Object System.Timers.Timer

[System.Collections.ArrayList]$global:monitoredMachines = @()

$action={
    function checkMachine ([MonitoredMachine]$machine) {

        $machineName=$machine.name
        $machineStatus=$machine.status

        Write-Host "Checking boot results for machine $machineName" -ForegroundColor green

        if ($machineStatus -ne "Booting") {
            Write-Host "??? Machine was not in state Booting.  Cannot process"
            return
        }

        $resultsFile="c:\temp\boot_results\" + $machineName
        $progressFile="c:\temp\progress_logs\" + $machineName
        

        if ((test-path $resultsFile) -eq $false) {
            Write-Host "Unable to locate results file $resultsFile.  Cannot process"
            return
        }

        $results=get-content $resultsFile
        $resultsSplit = $results.split(' ')
        $resultsWord=$resultsSplit[0]
        $resustsgot=$resultsSplit[1]

        if ($resultsSplit[0] -ne "Success") {
            $resultExpected = $resultsSplit[2]
            Write-Host "Machine $machineName rebooted, but wrong version detected.  Expected $resultExpected but got $resustsgot" -ForegroundColor red
            $global:failed=$true
        } else {
            Write-Host "Machine rebooted successfully to kernel version $resultExpected" -ForegroundColor green
            $global:booted_version=$resustsgot
        }

        $machine.status = "Completed"
        $global:num_remaining--
    }

    $global:elapsed=$global:elapsed+$global:interval

    # write-host "Checking elapsed = $global:elapsed against interval limit of $global:boot_timeout_intervals"    
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

        $bootFile="c:\temp\boot_results\" + $monitoredMachineName

        if (($monitoredMachineStatus -eq "Booting") -and ((test-path $bootFile) -eq $true)) {
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
        return
    }
 
    if (($global:elapsed % 10000) -eq 0) {
        Write-Host ""
        Write-Host "Waiting for remote machines to complete all testing.  There are $global:num_remaining machines left.." -ForegroundColor green

        foreach ($localMachine in $global:monitoredMachines) {
        [MonitoredMachine]$monitoredMachine=$localMachine
            
            $monitoredMachineName=$monitoredMachine.name
            $logFile="c:\temp\progress_logs\" + $monitoredMachineName
            $monitoredMachineStatus=$monitoredMachine.status

            if ($monitoredMachineStatus -eq "Booting") {
                if ((test-path $logFile) -eq $true) {
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
Write-Host "For now, though, please feel free to ignore the following errors..." -ForegroundColor Green
Write-Host " "
Write-Host "*************************************************************************************************************************************"
Write-Host "                      Stopping and cleaning any existing machines.  Any errors here may be ignored." -ForegroundColor green

get-job | Stop-Job
get-job | remove-job

Get-ChildItem 'D:\azure_images\*.vhd' |
foreach-Object {
    
    $vhdFile=$_.Name
    $status="Copying"

    $global:num_remaining++

    $vhdFileName=$vhdFile.Split('.')[0]
    
    $machine = new-Object MonitoredMachine
    $machine.name = $vhdFileName
    $machine.status = "Booting" # $status
    $global:monitoredMachines.Add($machine)
   
    Write-Host "Stopping and cleaning any existing instances of machine $vhdFileName." -ForegroundColor green
    stop-vm -Name $vhdFileName -Force -ErrorAction SilentlyContinue
    remove-vm -Name $vhdFileName -Force -ErrorAction SilentlyContinue

    $machine.status = "Allocating"
    # Copy-Item $sourceFile $destFile -Force
    $destFile="d:\working_images\" + $vhdFile

    if ($skipCopy -eq $false) {
    Remove-Item -Path $destFile -Force
    
        Write-Host "Starting job to copy VHD $vhdFileName to working directory..." -ForegroundColor green
        $jobName=$vhdFileName + "_copy_job"

        $existingJob = get-job $jobName -ErrorAction SilentlyContinue
        if ($? -eq $true) {
            stop-job $jobName -ErrorAction SilentlyContinue
            remove-job $jobName -ErrorAction SilentlyContinue
        }

        Start-Job -Name $jobName -ScriptBlock { robocopy /njh /ndl /nc /ns /np /nfl D:\azure_images\ D:\working_images\ $args[0] } -ArgumentList @($vhdFile)
    } else {
        Write-Host "Skipping copy per command line option"
    }
}

Write-Host "*************************************************************************************************************************************"
Write-Host " "
Write-Host "                                        Start paying attention to errors again..." -ForegroundColor green
Write-Host " "

if ($skipCopy -eq $false) {
    while ($true) {
        Write-Host "Waiting for copying to complete..." -ForegroundColor green
        $copy_complete=$true
        Get-ChildItem 'D:\azure_images\*.vhd' |
        foreach-Object {
            $vhdFile=$_.Name
            $vhdFileName=$vhdFile.Split('.')[0]

            $jobName=$vhdFileName + "_copy_job"

            $jobStatus=get-job -Name $jobName -ErrorAction SilentlyContinue
            if ($? -eq $true) {
                $jobState = $jobStatus.State
            } else {
                $jobStatus = "Completed"
            }
        
            if (($jobState -ne "Completed") -and 
                ($jobState -ne "Failed")) {
                Write-Host "      Current state of job $jobName is $jobState" -ForegroundColor yellow
                $copy_complete = $false
            }
            elseif ($jobState -eq "Failed")
            {
                $global:failed = 1
                Write-Host "----> Copy job $jobName exited with FAILED state!" -ForegroundColor red
                Receive-Job -Name $jobName
            }
            else
            {
                Write-Host "      Copy job $jobName completed successfully." -ForegroundColor green
                remove-job $jobName -ErrorAction SilentlyContinue
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
}

Write-Host "All machines template images have been copied.  Starting the VMs in Hyper-V" -ForegroundColor green

Get-ChildItem 'D:\working_images\*.vhd' |
foreach-Object {   
    $vhdFile=$_.Name

    $vhdFileName=$vhdFile.Split('.')[0]
    
    foreach ($localMachine in $global:monitoredMachines) {
        [MonitoredMachine]$monitoredMachine=$localMachine
        $monitoredMachineName=$machine.name
        if ($monitoredMachineName -eq $vhdFileName) {             
             break
        }
    }
    
    $vhdPath="D:\working_images\"+$vhdFile   

    Write-Host "BORG DRONE $vhdFileName is starting" -ForegroundColor green

    new-vm -Name $vhdFileName -MemoryStartupBytes 7168mb -Generation 1 -SwitchName "External" -VHDPath $vhdPath
    $monitoredMachine.status = "Booting"

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
unregister-event bootTimer
Register-ObjectEvent -InputObject $timer -EventName elapsed –SourceIdentifier bootTimer -Action $action
$timer.Interval = 1000
$timer.Enabled = $true
$timer.start()

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
        $global:failed = $true
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
