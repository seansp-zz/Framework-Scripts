param (
    [Parameter(Mandatory=$false)] [string[]] $requestedNames,
    
    [Parameter(Mandatory=$false)] [string] $destSA="smokesourcestorageacct",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_source_resource_group",

    [Parameter(Mandatory=$false)] [string] $suffix="-Runonce-Primed.vhd",

    [Parameter(Mandatory=$false)] [string] $command="unset",
    [Parameter(Mandatory=$false)] [string] $asRoot="false",

    [Parameter(Mandatory=$false)] [string] $location="westus"
)
    
    
. c:\Framework-Scripts\common_functions.ps1
. c:\Framework-Scripts\secrets.ps1

[System.Collections.ArrayList]$vmNames_array
$vmNameArray = {$vmNames_array}.Invoke()
$vmNameArray.Clear()
if ($requestedNames -like "*,*") {
    $vmNameArray = $requestedNames.Split(',')
} else {
    $vmNameArray += $requestedNames
}

$commandString = 
{
    param ( $DestRG,
            $DestSA,
            $location,
            $suffix,
            $command,
            $asRoot,
            $vm_name
            )

    . C:\Framework-Scripts\common_functions.ps1
    . C:\Framework-Scripts\secrets.ps1

    Start-Transcript C:\temp\transcripts\run_command_on_machines_in_group_$vm_name.log > $null

    login_azure $DestRG $DestSA $location
    #
    #  Session stuff
    #
    $o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
    $cred = make_cred

    $errorFound = $false
    $suffix = $suffix.Replace(".vhd","")

    $password="$TEST_USER_ACCOUNT_PASS"

    if ($asRoot -ne $false) {
        $runCommand = "echo $password | sudo -S bash -c `'$command`'"
    } else {
        $runCommand = $command
    }

    $commandBLock=[scriptblock]::Create($runCommand)

    # write-host "Executing remote command on machine $vm_name, resource gropu $destRG"

    [System.Management.Automation.Runspaces.PSSession]$session = create_psrp_session $vm_name $destRG $destSA $location $cred $o $false
    if ($? -eq $true -and $session -ne $null) {
        invoke-command -session $session -ScriptBlock $commandBLock -ArgumentList $command
        Exit-PSSession

    } else {
        Write-Host "    FAILED to establish PSRP connection to machine $vm_name."
    }

    Stop-Transcript > $null
}

$commandBLock = [scriptblock]::Create($commandString)

get-job | Stop-Job
get-job | Remove-Job

foreach ($baseName in $vmNameArray) {
    $vm_name = $baseName + $suffix
    $vm_name = $vm_name | % { $_ -replace ".vhd", "" }
    $job_name = "run_command_" + $vm_name 

    # write-host "Executing remote command on machine $vm_name, resource gropu $destRG"

    start-job -Name $job_name -ScriptBlock $commandBLock -ArgumentList $DestRG, $DestSA, $location, $suffix, $command, $asRoot, $vm_name > $null
}

$jobFailed = $false
$jobBlocked = $false

$allDone = $false
while ($allDone -eq $false) {
    $allDone = $true
    $numNeeded = $vmNameArray.Count
    $vmsFinished = 0

    foreach ($baseName in $vmNameArray) {
        $vm_name = $baseName + $suffix
        $vm_name = $vm_name | % { $_ -replace ".vhd", "" }
        $job_name = "run_command_" + $vm_name

        $job = Get-Job -Name $job_name
        $jobState = $job.State

        # write-host "    Job $job_name is in state $jobState" -ForegroundColor Yellow
        if ($jobState -eq "Running") {
            $allDone = $false
        } elseif ($jobState -eq "Failed") {
            write-host "**********************  JOB ON HOST MACHINE $vm_name HAS FAILED." -ForegroundColor Red
            $jobFailed = $true
            $vmsFinished = $vmsFinished + 1
        } elseif ($jobState -eq "Blocked") {
            write-host "**********************  HOST MACHINE $vm_name IS BLOCKED WAITING INPUT.  COMMAND WILL NEVER COMPLETE!!" -ForegroundColor Red
            $jobBlocked = $true
            $vmsFinished = $vmsFinished + 1
        } else {
            $vmsFinished = $vmsFinished + 1
        }
    }

    if ($allDone -eq $false) {
        sleep(10)
    } elseif ($vmsFinished -eq $numNeeded) {
        break
    }
}

foreach ($baseName in $vmNameArray) {
    $vm_name = $baseName + $suffix
    $vm_name = $vm_name | % { $_ -replace ".vhd", "" }
    $job_name = "run_command_" + $vm_name

    Get-Job $job_name | Receive-Job -OutVariable $jobText -ErrorAction SilentlyContinue
    Write-Host $vm_name : $jobText
}

if ($jobFailed -eq $true -or $jobBlocked -eq $true)
{
    exit 1
}

exit 0