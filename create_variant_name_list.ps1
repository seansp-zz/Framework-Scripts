#
#  Create a set of macines based on variants.  Variants are different machine types (standard_d2_v2), so a set of variant
#  machines all share the same base VHD image, but are (potentially) using different hardware configurations.#
#  Copies VHDs that have booted as expected to the test location where they will be prepped
#  for Azure automation
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$false)] [string[]] $Flavors="",
    [Parameter(Mandatory=$false)] [string[]] $requestedNames = "",
    [Parameter(Mandatory=$false)] [string[]] $location = ""
)

[System.Collections.ArrayList]$vmNames_array
$vmNameArray = {$vmNames_array}.Invoke()
$vmNameArray.Clear()
if ($requestedNames -like "*,*") {
    $vmNameArray = $requestedNames.Split(',')
} else {
    $vmNameArray += $requestedNames
}

[System.Collections.ArrayList]$all_vmNames_array
$all_vmNameArray = {$vmNames_array}.Invoke()
$all_vmNameArray.Clear()

[System.Collections.ArrayList]$flavors_array
$flavorsArray = {$flavors_array}.Invoke()
$flavorsArray.Clear()
if ($Flavors -like "*,*") {
    $flavorsArray = $Flavors.Split(',')
} else {
    $flavorsArray += $Flavors
}

$vmName = $vmNameArray[0]
if ($makeDronesFromAll -ne $true -and ($vmNameArray.Count -eq 1  -and $vmName -eq "")) {
    Write-Host "Must specify either a list of VMs in RequestedNames, or use MakeDronesFromAll.  Unable to process this request."
    exit 1
}

if ($flavorsArray.Count -eq 1 -and $flavorsArray[0] -eq "" ) {
Write-Host "Must specify at least one VM Flavor to build..  Unable to process this request."
exit 1
}

. "C:\Framework-Scripts\common_functions.ps1"
. "C:\Framework-Scripts\secrets.ps1"

foreach ($vmName in $vmNameArray) {
    foreach ($oneFlavor in $flavorsArray) {
        $oneName = $oneFlavor + $blobName

        write-verbose "Launching job to start machine $blobName in flavor $oneFlavor"
        Start-Job -Name $vmJobName -ScriptBlock $scriptBlock -ArgumentList $blobName, $sourceRG, $sourceSA, $sourceContainer,`
                                                                           $destRG, $destSA, $destContainer, $location,`
                                                                           $currentSuffix, $newSuffix, $NSG, $network, `
                                                                           $subnet, $oneFlavor
    }
}

Start-Sleep -Seconds 10

$allDone = $false
while ($allDone -eq $false) {
    $allDone = $true
    $numNeeded = $vmNameArray.Count
    $vmsFinished = 0

    foreach ($vmName in $vmNameArray) {
        
        $blobName = $vmName
        
        $blobName = $blobName.replace(".vhd","")

        foreach ($oneFlavor in $flavorsArray) {
            $vmJobName = "start_" + $oneFlavor + $blobName
            $job = Get-Job -Name $vmJobName
            $jobState = $job.State
            
            if ($jobState -eq "Running") {
                write-host "    Job $vmJobName is in state $jobState" -ForegroundColor Yellow
                $allDone = $false
                $logFile = "C:\temp\transcripts\" + $vmName + "-" + $oneFlavor + "-Variant.log"
                $logLines = Get-Content -Path $logFile -Tail 5
                if ($? -eq $true) {
                    Write-Host "         Last 5 lines from log file $logFile :" -ForegroundColor Cyan
                    foreach ($line in $logLines) {
                        write-host "        "$line -ForegroundColor Gray
                    }
                }
            } elseif ($jobState -eq "Failed") {
                write-host "    Job $vmJobName is in state $jobState" -ForegroundColor red
                write-host "**********************  JOB ON HOST MACHINE $vmJobName HAS FAILED TO START." -ForegroundColor Red
                # $jobFailed = $true
                $vmsFinished = $vmsFinished + 1
                $Failed = $true
            } elseif ($jobState -eq "Blocked") {
                write-host "    Job $vmJobName is in state $jobState" -ForegroundColor magenta
                write-host "**********************  HOST MACHINE $vmJobName IS BLOCKED WAITING INPUT.  COMMAND WILL NEVER COMPLETE!!" -ForegroundColor Red
                # $jobBlocked = $true
                $vmsFinished = $vmsFinished + 1
                $Failed = $true
            } else {
                $vmsFinished = $vmsFinished + 1
            }
        }
    }

    if ($allDone -eq $false) {
        Start-Sleep -Seconds 10
    } elseif ($vmsFinished -eq $numNeeded) {
        break
    }
}

if ($Failed -eq $true) {
    Write-Host "Remote command execution failed because we could not !" -ForegroundColor Red
    exit 1
} 