$global:completed=0
$global:elapsed=0
$global:interval=500
$global:boot_timeout_minutes=15
$global:boot_timeout_intervals=$interval*($boot_timeout_minutes*60*(1000/$interval))
$global:found_centos=0
$global:found_ubuntu=0
$global:failed=0
$global:ubunResults=""
$global:centResults=""

$timer=New-Object System.Timers.Timer

$action={
    $global:elapsed=$global:elapsed+$global:interval

    # write-host "Checking elapsed = $global:elapsed against interval limit of $global:boot_timeout_intervals"    
    if ($elapsed -ge $global:boot_timeout_intervals) {
        write-host "Timer has timed out."
        $global:completed=1
    }

    if (($global:found_centos -eq 0) -and (Test-Path -path "c:\temp\centos-boot") -eq 1) {
        write-host "***** Centos boot has completed"
        $global:centResults=Get-Content c:\temp\centos-boot
        $global:centResults=$global:centResults -split " "

        if ($global:centResults[0] -ne "Success") {
            Write-Host "CentOS machine rebooted, but wrong version detected.  Expected $global:centResults[2] but got $global:centResults[1]"
        } else {
            Write-Host "CentOS machine rebooted successfully to kernel version $global:centResults[1]"
        }

                $global:found_centos=1
    }

    if (($global:found_ubuntu -eq 0) -and (Test-Path -path "c:\temp\ubuntu-boot") -eq 1) {
        write-host "***** Ubuntu boot has completed"
        $global:ubunResults=Get-Content c:\temp\ubuntu-boot
        $global:ubunResults=$global:ubunResults -split " "

       if ($global:ubunResults[0] -ne "Success") {
            Write-Host "Ubuntu machine rebooted, but wrong version detected.  Expected $global:ubunResults[2] but got $global:ubunResults[1]"
        } else {
            Write-Host "Ubuntu machine rebooted successfully to kernel version $global:ubunResults[1]"
        }

        $global:found_ubuntu=1
    }
 
    if (($global:found_centos -eq 1) -and ($global:found_ubuntu -eq 1)) {
        write-host "Both machines have booted.  Stopping the timer"
        $global:completed=1
    }

    if ($global:completed -eq 1) {
        write-host "Completed = $global:completed.  Stopping timer"             
    }
}

Write-Host "    "
Write-Host "**********************************************"
Write-Host "*                                            *"
Write-Host "*          Microsoft Linux Kernel            *"
Write-Host "*     Basic Operational Readiness Test       *"
Write-Host "* Host Infrastructure Validation Environment *"
Write-Host "*                                            *"
Write-Host "**********************************************"
Write-Host "    "

Write-Host "Welcome to the BORG HIVE"
Write-Host "    "
Write-Host "Initializing the Customizable Base of Execution"
Write-Host "    "
#
#  Clean up the sentinel files
#
Write-Host "Cleaning up sentinel files..."
remove-item -ErrorAction "silentlycontinue" c:\temp\centos
remove-item -ErrorAction "silentlycontinue" c:\temp\centos-boot
remove-item -ErrorAction "silentlycontinue" c:\temp\centos-prep_for_azure
remove-item -ErrorAction "silentlycontinue" c:\temp\ubuntu
remove-item -ErrorAction "silentlycontinue" c:\temp\ubuntu-boot
remove-item -ErrorAction "silentlycontinue" c:\temp\ubuntu-prep_for_azure

# 
Write-Host "Restoring VM Snapshots"
get-vm "CentOS 7.1 MSLK Test 1"  | Get-VMSnapshot -name "New Kernel at Startup" | Restore-VMSnapshot -Confirm:$false
get-vm "Ubuntu 1604 MSLK Test 1"  | Get-VMSnapshot -name "New Kernel at Startup" | Restore-VMSnapshot -Confirm:$false

Write-Host "   "
Write-Host "BORG CUBE is initialized.  Starting the Dedicated Remote Nodes of Execution"
Write-Host "    "

# 
Write-Host "Starting the CentOS DRONE"
start-vm -name "CentOS 7.1 MSLK Test 1"
Write-Host "Starting the Ubuntu DRONE"
start-vm -name "Ubuntu 1604 MSLK Test 1"

#
#  Wait for the two machines to report back
#
write-host "Initiating temporal evaluation loop"
Register-ObjectEvent -InputObject $timer -EventName elapsed –SourceIdentifier bootTimer -Action $action

write-host "Starting the timer"
$timer.Interval = 500
$timer.Enabled = $true
$timer.start()

while ($global:completed -eq 0) {
    if (($global:elapsed % 30000) -eq 0) {
        Write-Host "Waiting for remote machines to boot..."
        if (((test-path "c:\temp\centos") -eq 1) -and ($global:found_centos -eq 0)) {
            write-host "---"
            write-host "Last 3 lines from Centos:"
            get-content "c:\temp\centos" | Select-Object -Last 3 | write-host
            write-host "---"
        } else {
            if ($global:found_centos -eq 0) {
                Write-Host "CentOS machine has not checked in yet"
            }
        }

        if (((test-path "c:\temp\ubuntu") -eq 1) -and $global:found_ubuntu -eq 0) {
            write-host "---"
            write-host "Last 3 lines from Ubuntu:"
            get-content "c:\temp\ubuntu" | Select-Object -Last 3 | write-host
            write-host "---"
        } else {
            if ($global:found_ubuntu -eq 0) {
                Write-Host "Ubuntu machine has not checked in yet"
            }
        }
        [Console]::Out.Flush() 
    }
    start-sleep -s 1
}

write-host "Unregistering the timer"
$timer.stop()
unregister-event bootTimer

write-host "Checking results"

if (($global:found_centos -eq 1) -and ($global:found_ubuntu -eq 1)) {
    Write-Host "Both machines have come back up.  Checking versions."
    
    $blobal:failed=0
    if ($global:centResults[0] -ne "Success") {
        Write-Host "CentOS machine rebooted, but wrong version detected.  Expected $global:centResults[2] but got $global:centResults[1]"
        $global:failed=1
    } else {
        Write-Host "CentOS machine rebooted successfully to kernel version $global:centResults[1]"
    }

    if ($global:ubunResults[0] -ne "Success") {
        Write-Host "Ubuntu machine rebooted, but wrong version detected.  Expected $global:ubunResults[2] but got $global:ubunResults[1]"
        $global:failed=1
    } else {
        Write-Host "Ubuntu machine rebooted successfully to kernel version $global:ubunResults[1]"
    }

    if ($global:failed -eq 0) {
        write-host "BORG has been passed successfully!"
    } else {
        write-host "BORG TESTS HAVE FAILED!!"
    }
} else {
        write-host "BORG TEST FAILURE!!"

        if (($global:found_centos -eq 0) -and ($global:found_ubuntu -eq 0)) {
            write-host "Timeout waiting for both machines!  Build log for Ubuntu:"
            type c:\temp\ubuntu
        } else {
            if ($global:found_centos -eq 0) {
                write-host "CentOS machine did not report in.  This is the log:"
                type c:\temp\centos
            }

            if ($global:found_ubuntu -eq 0) {
                write-host "Ubuntu machine did not report in.  This is the log:"
                type c:\temp\ubuntu
            }
        }
    }

Write-Host "Log files:"
Write-Host ""
Write-Host "CentOS install log:"
get-content \temp\centos | write-host

Write-Host ""
Write-Host "CentOS boot results log:"
get-content \temp\centos-boot | write-host

Write-Host ""
Write-Host "CentOS Azure Prep log:"
get-content \temp\centos-prep_for_azure | write-host

Write-Host ""
Write-Host "Ubuntu install log:"
get-content \temp\ubuntu | write-host

Write-Host ""
Write-Host "Ubuntu boot results log:"
get-content \temp\ubuntu-boot | write-host

Write-Host ""
Write-Host "Ubuntu Azure Prep log:"
get-content \temp\ubuntu-prep_for_azure | write-host

Write-Host "Thanks for Playing"

if ($global:failed -eq 0) {
    exit 0
} else {
    exit 1
}
