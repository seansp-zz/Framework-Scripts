$global:completed=0
$global:elapsed=0
$global:interval=500
$global:boot_timeout_minutes=10
$global:boot_timeout_intervals=$interval*($boot_timeout_minutes*60*(1000/$interval))
$global:found_centos=0
$global:found_ubuntu=0

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
        $global:found_centos=1
    }

    if (($global:found_ubuntu -eq 0) -and (Test-Path -path "c:\temp\ubuntu-boot") -eq 1) {
        write-host "***** Ubuntu boot has completed"
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

#
#  Clean up the sentinel files
#
remove-item -ErrorAction "silentlycontinue" c:\temp\centos
remove-item -ErrorAction "silentlycontinue" c:\temp\centos-boot
remove-item -ErrorAction "silentlycontinue" c:\temp\ubuntu
remove-item -ErrorAction "silentlycontinue" c:\temp\ubuntu-boot

# echo "Restoring VM Snapshots"
get-vm "CentOS 7.1 MSLK Test 1"  | Get-VMSnapshot -name "New Kernel at Startup" | Restore-VMSnapshot -Confirm:$false
get-vm "Ubuntu 1604 MSLK Test 1"  | Get-VMSnapshot -name "New Kernel at Startup" | Restore-VMSnapshot -Confirm:$false

# echo "Starting the VMs"
start-vm -name "CentOS 7.1 MSLK Test 1"
start-vm -name "Ubuntu 1604 MSLK Test 1"

#
#  Wait for the two machines to report back
#
write-host "Registering the timer"
Register-ObjectEvent -InputObject $timer -EventName elapsed –SourceIdentifier bootTimer -Action $action

write-host "Starting the timer"
$timer.Interval = 500
$timer.Enabled = $true
$timer.start()

while ($global:completed -eq 0) {
    if (($global:elapsed % 30000) -eq 0) {
        Write-Host "Waiting for remote machines to boot..."
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
    $centResults=Get-Content c:\temp\centos-boot
    $centResults -split " "
    $failed=0
    if ($centResults[0] -ne "Success") {
        Write-Host "CentOS machine rebooted, but wrong version detected.  Expected $centResults[2] but got $centResults[1]"
        $failed=1
    } else {
        Write-Host "CentOS machine rebooted successfully to kernel version $centResults[1]"
    }

    $ubunResults=Get-Content c:\temp\ubuntu-boot
    $ubunResults -split " "
    if ($ubunResults[0] -ne "Success") {
        Write-Host "Ubuntu machine rebooted, but wrong version detected.  Expected $ubunResults[2] but got $ubunResults[1]"
        $failed=1
    } else {
        Write-Host "Ubuntu machine rebooted successfully to kernel version $ubunResults[1]"
    }

    if ($failed -eq 0) {
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
