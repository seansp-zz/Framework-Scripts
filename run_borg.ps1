$global:completed=0
$global:elapsed=0
$global:interval=500
$global:boot_timeout_minutes=20
$global:boot_timeout_intervals=$interval*($boot_timeout_minutes*60*(1000/$interval))
$global:num_expected=0
$global:num_remaining=0
$global:failed=0
$global:booted_version="Unknown"

Import-Module C:\Framework-Scripts\clone_RvVm.ps1

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
    Write-Host "Checking boot results for machine $machine.MachineName"

    $resultsFile="c:\temp\boot_results\" + $machineName + "_boot"
    $progressFile="c:\temp\progress_logs\" + $machineName + "_progress.log"

    if ((test-path $resultsFile) -eq 0) {
        return
    }

    $results=get-content $resultsFile
    $resultsSplit = $results.split(' ')

    if ($resultsSplit[0] -ne "Success") {
        Write-Host "Machine $machineName rebooted, but wrong version detected.  Expected $resultsSplit[2] but got $resultsSplit[1]" -ForegroundColor red
        $global:failed=$true
    } else {
        Write-Host "CentOS machine rebooted successfully to kernel version " -ForegroundColor green
        $global:booted_version=$ResultsSplit[1]
    }

    Move-Item $resultsFile -Destination "c:\temp\completed_boots\"
    Move-Item $progressFile -Destination "c:\temp\completed_boots\"

    $machine.status = "Complete"
    $global:num_remaining--
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
            $logFile="c:\temp\progress_logs\" + $monitoredMachine.MachineName + "_progress.log"
            if ((test-path $logFile) -eq 1) {
                write-host "--- Last 3 lines of results from $logFile" -ForegroundColor magenta
                get-content "c:\temp\centos" | Select-Object -Last 3 | write-host  -ForegroundColor cyan
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
Write-Host "**********************************************" -ForegroundColor green
Write-Host "    " -ForegroundColor green

Write-Host "Welcome to the BORG HIVE" -ForegroundColor yellow
Write-Host "    "
Write-Host "Initializing the Customizable Universal Base of Execution" -ForegroundColor yellow
Write-Host "    "
#
#  Clean up the sentinel files
#
Write-Host "Cleaning up sentinel files..." -ForegroundColor green
remove-item -ErrorAction "silentlycontinue" C:\temp\completed_boots\*
remove-item -ErrorAction "silentlycontinue" C:\temp\boot_results\*
remove-item -ErrorAction "silentlycontinue" C:\temp\progress_logs\*

Write-Host "   "
Write-Host "BORG CUBE is initialized.  Starting the Dedicated Remote Nodes of Execution" -ForegroundColor yellow
Write-Host "    "

Write-Host "Checking to see which VMs we need to bring up..."

Get-ChildItem 'D:\azure_images' |
foreach-Object {
    
    $vhdFile=$_.Name
    $status="initializing"

    $global:num_remaining++

    $vhdFileName=$vhdFile.Split('.')[0]
    
    $machine = new-monitor -name $vhdFileName -status $status
    $global:monitoredMachines.Add($machine)
    
    $machine.status = "Allocating"
    $vhdPath="D:\azure_images\"+$vhdFile
    stop-vm -Name $vhdFileName -Force
    remove-vm -Name $vhdFileName -Force
     
    new-vm -Name $vhdFileName -MemoryStartupBytes 7168mb -Generation 1 -SwitchName "Microsoft Hyper-V Network Adapter - Virtual Switch" -VHDPath $vhdPath
    Start-VM -Name $vhdFileName
    $machine.Status = "Booting"
}

#
#  Wait for the machines to report back
#
write-host "Initiating temporal evaluation loop" -ForegroundColor yellow
Register-ObjectEvent -InputObject $timer -EventName elapsed –SourceIdentifier bootTimer -Action $action

write-host "Starting the timer" -ForegroundColor green
$timer.Interval = 500
$timer.Enabled = $true
$timer.start()

while ($global:completed -eq 0) {
    start-sleep -s 1
}

write-host "Unregistering the timer" -ForegroundColor green
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

        Write-Host "Not all test machines reported in.  Machines states are:"
        foreach ($machine in $global:montiroedMachines) {
            echo "Machine $machine.MachnineName is in state $machine.state"
        }
    }

if ($global:failed -eq 0) {    
    Write-Host "Exiting with success.  Thanks for Playing" -ForegroundColor green
    exit 0
} else {
    Write-Host "Exiting with failure.  Thanks for Playing" -ForegroundColor red
    exit 1
}
