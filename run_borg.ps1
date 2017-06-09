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
    Write-Host "Checking boot results for machine $machine.MachineName" -ForegroundColor green

    $resultsFile="c:\temp\boot_results\" + $machineName
    $progressFile="c:\temp\progress_logs\" + $machineName

    if ((test-path $resultsFile) -eq 0) {
        return
    }

    $results=get-content $resultsFile
    $resultsSplit = $results.split(' ')

    if ($resultsSplit[0] -ne "Success") {
        Write-Host "Machine $machineName rebooted, but wrong version detected.  Expected $resultsSplit[2] but got $resultsSplit[1]" -ForegroundColor red
        $global:failed=$true
    } else {
        Write-Host "Machine rebooted successfully to kernel version " -ForegroundColor green
        $global:booted_version=$ResultsSplit[1]
    }

    Move-Item $resultsFile -Destination "c:\temp\completed_boots\{$machineName}_boot"
    Move-Item $progressFile -Destination "c:\temp\completed_boots\{$machineName}_progress"

    $machine.status = "Azure"
    $global:num_remaining--

    if ($global:failed -eq $false) {
        Write-Host "Chainging to Azure valication job..." -ForegroundColor green
        start-job -Name $machineName -ScriptBlock {C:\Framework-Scripts\run_borg_2.ps1 $machine.MachineName}
    } else {
        Write-Host "This, or another, machine has failed to boot.  Machines will not progress to Azure" -ForegroundColor red
    }
}

$action={
    $global:elapsed=$global:elapsed+$global:interval

    # write-host "Checking elapsed = $global:elapsed against interval limit of $global:boot_timeout_intervals"    
    if ($elapsed -ge $global:boot_timeout_intervals) {
        write-host "Timer has timed out." -ForegroundColor red
        $global:completed=1
    }

    foreach ($monitoredMachine in $global:montiroedMachines) {
        if ($monitoredMachine.Status -ne "Complete") {
            checkMachine($monitoredMachine.MachineName)
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
        Write-Host "Waiting for remote machines to boot.  There are $global:num_remaining machines left.." -ForegroundColor green

        foreach ($monitoredMachine in $global:monitoredMachines) {
            $logFile="c:\temp\progress_logs\" + $monitoredMachine.MachineName
            if ((test-path $logFile) -eq 1) {
                write-host "--- Last 3 lines of results from $logFile" -ForegroundColor magenta
                get-content $logFile | Select-Object -Last 3 | write-host  -ForegroundColor cyan
                write-host "---" -ForegroundColor magenta
            } else {
                $machineName = $monitoredMachine.MachineName
                Write-Host "--- Machine $machineName has not checked in yet"
            }
        }

        [Console]::Out.Flush() 
    }
}

Write-Host "    " -ForegroundColor green
Write-Host "**********************************************" -ForegroundColor green
Write-Host "*                                            *" -ForegroundColor green
Write-Host "*            Microsoft Linux Kernel          *" -ForegroundColor green
Write-Host "*     Basic Operational Readiness Gateway    *" -ForegroundColor green
Write-Host "* Host Infrastructure Validation Environment *" -ForegroundColor green
Write-Host "*                                            *" -ForegroundColor green
Write-Host "*           Welcome to the BORG HIVE         *" -ForegroundColor green
Write-Host "**********************************************" -ForegroundColor green
Write-Host "    "
Write-Host "Initializing the CUBE (Customizable Universal Base of Execution)" -ForegroundColor yellow
Write-Host "    "
#
#  Clean up the sentinel files
#
Write-Host "Cleaning up sentinel files..." -ForegroundColor green
remove-item -ErrorAction "silentlycontinue" C:\temp\completed_boots\*
remove-item -ErrorAction "silentlycontinue" C:\temp\boot_results\*
remove-item -ErrorAction "silentlycontinue" C:\temp\progress_logs\*

Write-Host "   "
Write-Host "BORG CUBE is initialized.  Starting the DRONES (Dedicated Remote Node of Execution)" -ForegroundColor yellow
Write-Host "    "

Write-Host "Checking to see which VMs we need to bring up..."

Get-ChildItem 'D:\azure_images\*.vhd' |
foreach-Object {
    
    $vhdFile=$_.Name
    $status="initializing"

    $global:num_remaining++

    $vhdFileName=$vhdFile.Split('.')[0]
    
    $machine = new-monitor -name $vhdFileName -status $status
    $global:monitoredMachines.Add($machine)
    
    Write-Host "Stopping and cleaning any existing VMs.  Any errors here may be ignored." -ForegroundColor green
    stop-vm -Name $vhdFileName -Force
    remove-vm -Name $vhdFileName -Force

    Write-Host "Start paying attention to errors again..." -ForegroundColor green
    Write-Host "Copying VHD $vhdFileName to working directory..." -ForegroundColor green
    $machine.status = "Allocating"
    $sourceFile="D:\azure_images\"+$vhdFile
    $destFile="D:\working_images\"+$vhdFile
    Copy-Item $sourceFile $destFile -Force

    if ($? -eq $false) {
        Write-Host "Copy failed.  The BORG cannot continue." -ForegroundColor Red
        exit 1
    }

    Write-Host "Copy complete.  Starting the VM on Hyper-V" -ForegroundColor green
    $vhdPath="D:\working_images\"+$vhdFile   
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

    $machine.Status = "Booting"
    Write-Host "BORG DRONE $vhdFileName has started" -ForegroundColor green
}

#
#  Wait for the machines to report back
#
write-host "Initiating temporal evaluation loop (Starting the timer)" -ForegroundColor yellow
Register-ObjectEvent -InputObject $timer -EventName elapsed –SourceIdentifier bootTimer -Action $action
$timer.Interval = 500
$timer.Enabled = $true
$timer.start()

while ($global:completed -eq 0) {
    start-sleep -s 1
}

write-host "Exiting Temporal Evaluation Loop (Unregistering the timer)" -ForegroundColor green
$timer.stop()
unregister-event bootTimer

write-host "Checking results" -ForegroundColor green

if ($global:num_remaining -eq 0) {
    Write-Host "All machines have come back up.  Checking results." -ForegroundColor green
    
    if ($global:failed -eq $true) {
        Write-Host "Failures were detected in reboot and/or reporting of kernel version.  See log above for details." -ForegroundColor red
        write-host "BORG TESTS HAVE FAILED!!" -ForegroundColor red
    } else {
        Write-Host "All machines rebooted successfully to kernel version $global:booted_version" -ForegroundColor green
        write-host "BORG has been passed successfully!" -ForegroundColor green
    }
} else {
        write-host "BORG TEST FAILURE!!  Not all machines booted in the allocated time!" -ForegroundColor red

        Write-Host "Not all test machines reported in.  Machines states are:" -ForegroundColor red
        foreach ($machine in $global:montiroedMachines) {
            echo "Machine $machine.MachnineName is in state $machine.state" -ForegroundColor red
        }
    }

foreach ($monitoredMachine in $global:montiroedMachines) {
        Write-Host "Checking state of Azure job $monitoredMachine.MachineName" -ForegroundColor green
        $jobStatus=get-job -Name $monitoredMachine.MachineName

        Write-Host "Current state is $jobStatus.State"

        if (($jobStatus.State -ne "Completed") -and 
            ($jobStatus.State -ne "Failed")) {
            sleep 10
        }
        elseif ($jobStatus.State -eq "Failed")
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
    Write-Host "Exiting with success.  Thanks for Playing" -ForegroundColor green
    exit 0
} else {
    Write-Host "Exiting with failure.  Thanks for Playing" -ForegroundColor red
    exit 1
}
