param (
    [switch]$getAll=$false,
    [switch]$replaceVHD=$false,
    [string[]] $requestedVMs=""
)

$rg="azuresmokeresourcegroup"
$nm="azuresmokestoragesccount"

write-host "Importing the context...." -ForegroundColor green
Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'

write-host "Selecting the Azure subscription..." -ForegroundColor green
Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4"
Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $nm

Write-Host "Getting the list of machines and disks..."
$smoke_machines=Get-AzureRmVm -ResourceGroupName $rg
$smoke_disks=Get-AzureRmDisk -ResourceGroupName $rg
$neededVms_array=@()
$neededVms = {$neededVms_array}.Invoke()

write-host "Clearing the old VHD download directory" -ForegroundColor green
if ($getAll -eq $true -and $replaceVHD -eq $true) {
    Write-Host "GetAll and replaceVHD were both specified.  Clearning the download directory..." -ForegroundColor green
    remove-item "D:\azure_images\*" -recurse -force
} elseif ($requestedVMs.Length -eq 0) {
    foreach ($machine in $smoke_machines) {
        $machineName=$machine.Name+".vhd"
        if ((Test-Path D:\azure_images\$machineName) -eq $true -and $replaceVHD -eq $true) {
            Write-Host "Machine $machineName is being deleted from the disk and will be downloaded again..." -ForegroundColor green
            remove-item "D:\azure_images\$machineName" -recurse -force
            $neededVms.Add($machineName)
        } elseIf (Test-Path D:\azure_images\$machineName) {
            Write-Host "Machine $machineName was already on the disk and the replaceVHD flag was not given.  Machine will not be updated." -ForegroundColor red            
        } else {
            Write-Host "Machine $machineName does not yet exist on the disk.  Machine will be downloaded..." -ForegroundColor green
            $neededVms.Add($machineName)
        }
    }
} else {
    foreach ($machine in $requestedVMs) {
        Write-Host "Downloading per user-defined list"
        $machineName=$machine+".vhd"
        write-host "Looking for machine $machienName"
        if ((Test-Path D:/azure_images/$machineName) -eq $true -and $replaceVHD -eq $true) {
            Write-Host "Machine $machine is being deleted from the disk and will be downloaded again..." -ForegroundColor green
            remove-item "D:/azure_images/$machineName" -recurse -force
            $neededVms.Add($machine)
        } elseIf (Test-Path D:\azure_images\$machineName) {
            Write-Host "Machine $machine was already on the disk and the replaceVHD flag was not given.  Machine will not be updated." -ForegroundColor red            
        } else {
            Write-Host "Machine $machine does not yet exist on the disk.  Machine will be downloaded..." -ForegroundColor green
            $neededVms.Add($machine)
        }
    }
}
        
if ($getAll -eq $true) {
    Write-Host "Downloading all machines.  This may take some time..." -ForegroundColor green
    foreach ($machine in $smoke_machines) {
        $vhd_name=$machine.Name + ".vhd"
        $machine_name = "D:/azure_images/" + $machine.Name + ".vhd"
        $neededVMs.Add($machine.Name)

        function downloadMachine {
            param (
               [Parameter(Mandatory=$true)] [string] $g,
               [Parameter(Mandatory=$true)] [string] $u,
               [Parameter(Mandatory=$true)] [string] $n
            )
            Save-AzureRmVhd -ResourceGroupName $g -SourceUri $u -LocalFilePath $n -OverWrite
        }

        $jobName = $machine.Name + "_SaveVhd"
        $uri=$machine.StorageProfile.OsDisk.Vhd.Uri
        Write-Host "Starting job $jobName to download machine $vhd_name from uri $uri to directory $machine_name" -ForegroundColor green

        start-job -name $jobName -ScriptBlock {C:\Framework-Scripts\download_single_vm.ps1 -g $args[0] -u $args[1] -n $args[2] } -ArgumentList $rg,$uri,$machine_name
    }
} else {
    foreach ($neededMachine in $neededVms) {
       
        foreach ($machine in $smoke_machines) {
            if ($machine.Name -eq $neededMachine) {
                break;
            }
        }
        $vhd_name=$machine.Name + ".vhd"
        $machine_name = "D:/azure_images/" + $machine.Name + ".vhd"

        $jobName = $machine.Name + "_SaveVhd"
        $uri=$machine.StorageProfile.OsDisk.Vhd.Uri
        Write-Host "Starting job $jobName to download machine $vhd_name from uri $uri to directory $machine_name" -ForegroundColor green
        start-job -name $jobName -ScriptBlock {C:\Framework-Scripts\download_single_vm.ps1 -g $args[0] -u $args[1] -n $args[2] } -ArgumentList $rg,$uri,$machine_name
    }
}

$sleepCount = 0
$stop_checking = $false

while ($stop_checking -eq $false) {
    foreach ($machine in $neededVms) {
        $waitIntervals = 0
    
        $jobName = $machine + "_SaveVhd"

        if (($sleepCount % 6) -eq 0) {
            Write-Host "Checking download progress of machine $machine, job $jobName"  -ForegroundColor green
        }

        $jobState=Get-Job -Name $jobName
        $failed=$true

        if ($jobState.State -eq "Running") {
            if (($sleepCount % 6) -eq 0) {
                Write-Host "Download still in progress..." -ForegroundColor green
                $failed=$false
            }
        } elseif ($jobState.State -eq "Completed") {
            Write-Host "Download has completed" -ForegroundColor green
            $stop_checking = $true
            $failed=$false
        } elseif ($jobState.State -eq "Failed") {
            Write-Host "Download has FAILED" -ForegroundColor red
            $stop_checking = $true
        } elseif ($jobState.State -eq "Stopped") {
            Write-Host "Download has Stopped"  -ForegroundColor red   
            $stop_checking = $true
        } elseif ($jobState.State -eq "Blocked") {
            Write-Host "Download has Blocked" -ForegroundColor red
            $stop_checking = $true
         } elseif ($jobState.State -eq "Suspended") {
            Write-Host "Download has Suspended" -ForegroundColor red
        } elseif ($jobState.State -eq "Disconnected") {
            Write-Host "Download has Disconnected" -ForegroundColor red
            $stop_checking = $true
        } elseif ($jobState.State -eq "Suspending") {
            Write-Host "Download is being suspended" -ForegroundColor red
        } elseif ($jobState.State -eq "Stopping") {
            Write-Host "Download is being Stopped" -ForegroundColor red
        }

        if ($stop_checking -eq $true)
        {
            if ($failed) {
                Write-Host "DOWNLOAD FAILED!!" -Foregroundcolor Red
            } else {
                Write-Host "Machine $machine has been downloaded successfully." -ForegroundColor green
            }
            $neededVms.Remove($machine)

            if ($neededVms.Length -le 0) {
                Write-Host "All downloads have completed or failed.  Terminating loop." -ForegroundColor Green
                break;
            }
            else
            {
                $stop_checking = $false
            }
        }
    }
    $SleepCount++
    Start-Sleep 10
}