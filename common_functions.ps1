function login_azure([string] $rg, [string] $sa) {
    . "C:\Framework-Scripts\secrets.ps1"

    Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx' > $null
    Select-AzureRmSubscription -SubscriptionId "$AZURE_SUBSCRIPTION_ID" > $null

    if ($rg -ne "" -and $sa -ne "") {
        Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $sa > $null
    }
}

function make_cred () {
    . "C:\Framework-Scripts\secrets.ps1"

    $pw = convertto-securestring -AsPlainText -force -string "$TEST_USER_ACCOUNT_PASS" 
    $cred = new-object -typename system.management.automation.pscredential -argumentlist "$TEST_USER_ACCOUNT_NAME",$pw

    return $cred
}

function create_psrp_session([string] $vmName, [string] $rg, [string] $SA,
                             [System.Management.Automation.PSCredential] $cred,
                             [System.Management.Automation.Remoting.PSSessionOption] $o)
{
    
    Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $SA

    $pipName=$vmName + "PublicIP"

    $ipAddress = Get-AzureRmPublicIpAddress -ResourceGroupName $rg -Name $pipName

    if ($ipAddress.IpAddress -eq "Not Assigned") {
        Write-Error "Machine $vmName does not have an assigned IP address.  Cannot create PSRP session to the machine."
        return $null
    }

    new-PSSession -computername $ipAddress.IpAddress -credential $cred -authentication Basic -UseSSL -Port 443 -SessionOption $o
}

function stop_machines_in_group([Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine[]] $runningVMs,
                                    [string] $destRG,
                                    [string] $destSA)
{
    Write-Host "Removing from $destRG and $destSA"

    $scriptBlockString =
    {
        param ([Parameter(Mandatory=$false)] [string] $vm_name,
                [Parameter(Mandatory=$false)] [string] $destRG,
                [Parameter(Mandatory=$false)] [string] $destSA
        )
                
        . C:\Framework-Scripts\common_functions.ps1
        . C:\Framework-Scripts\secrets.ps1

        login_azure $destRG $destSA
        Write-Host "Stopping machine $vm_name in RG $destRG"
        Stop-AzureRmVM -Name $vm_name -ResourceGroupName $destRG -Force
    }

    $scriptBlock = [scriptblock]::Create($scriptBlockString)

    foreach ($singleVM in $runningVMs) {
        $vm_name = $singleVM.Name
        $vmJobName = $vm_name + "-Src"
        write-host "Starting job to stop VM $vm_name"
        Start-Job -Name $vmJobName -ScriptBlock $scriptBlock -ArgumentList $vm_name,$destRG,$destSA
    }

    $allDone = $false
    while ($allDone -eq $false) {
        $allDone = $true
        foreach ($singleVM in $runningVMs) {
            $vm_name = $singleVM.Name
            $vmJobName = $vm_name + "-Src"
            $job = Get-Job -Name $vmJobName
            $jobState = $job.State
            write-host "    Job $vmJobName is in state $jobState" -ForegroundColor Yellow
            if ($jobState -eq "Running") {
                $allDone = $false
            }
        }

        if ($allDone -eq $false) {
            sleep(10)
        }
    }
}

function deallocate_machines_in_group([Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine[]] $runningVMs,
                                    [string] $destRG,
                                    [string] $destSA)
{
    Write-Host "Deprovisioning from $destRG and $destSA"

    $scriptBlockString =
    {
        param ([Parameter(Mandatory=$false)] [string] $vm_name,
                [Parameter(Mandatory=$false)] [string] $destRG,
                [Parameter(Mandatory=$false)] [string] $destSA
        )
                
        . C:\Framework-Scripts\common_functions.ps1
        . C:\Framework-Scripts\secrets.ps1

        login_azure $destRG $destSA
        Write-Host "Deallocating machine $vm_name in RG $destRG"
        Remove-AzureRmVM -Name $vm_name -ResourceGroupName $destRG -Force
    }

    $scriptBlock = [scriptblock]::Create($scriptBlockString)
    foreach ($singleVM in $runningVMs) {
        $vm_name = $singleVM.Name
        $vmJobName = $vm_name + "-Deprov"
        write-host "Starting job to deprovision VM $vm_name"
        Start-Job -Name $vmJobName -ScriptBlock $scriptBlock -ArgumentList $vm_name,$destRG,$destSA
    }

    $allDone = $false
    while ($allDone -eq $false) {
        $allDone = $true
        foreach ($singleVM in $runningVMs) {
            $vm_name = $singleVM.Name
            $vmJobName = $vm_name + "-Deprov"
            $job = Get-Job -Name $vmJobName
            $jobState = $job.State
            write-host "    Job $vmJobName is in state $jobState" -ForegroundColor Yellow
            if ($jobState -eq "Running") {
                $allDone = $false
            }
        }

        if ($allDone -eq $false) {
            sleep(10)
        }
    }

    if ($allDone -eq $false) {
        sleep(10)
    }
}

function try_pscp([string] $file,
                  [string] $ipTemp)
{
    . C:\Framework-Scripts\secrets.ps1
    
    $try_again = $true
    while ($try_again -eq $true) {
        $try_again = $false
        try {
            $out = C:\azure-linux-automation\tools\pscp -pw $TEST_USER_ACCOUNT_PASS -l $TEST_USER_ACCOUNT_NAME $file $ipTemp
        }
        catch {
                Write-Host "pscp Exception caught -- trying again"
                $try_again = $true
        }

        if ($? -eq $false -and $out -contains "connection timed out")
        {
            Write-Host "Timeout on pscp of $file"
            $try_again = $true
        } elseif ($? -eq $false) {
            write-host "General error copying file..."
            return 1
        } else {
            Write-Host "Successful copy"
            return 0
        }
    }
}

function try_plink([string] $ip,
                  [string] $command)
{
    . C:\Framework-Scripts\secrets.ps1

    $port=22
    
    $try_again = $true
    while ($try_again -eq $true) {
        $try_again = $false
        try {
            $out = C:\azure-linux-automation\tools\plink.exe -C -v -pw $TEST_USER_ACCOUNT_PASS -P $port -l $TEST_USER_ACCOUNT_NAME $ip $command
        }
        catch {
                Write-Host "plink Exception caught -- trying again"
                $try_again = $true
        }

        if ($? -eq $false -and $out -contains "connection timed out")
        {
            Write-Host "Timeout on plink of $command"
            $try_again = $true
        } elseif ($? -eq $false) {
            write-host "General error executing command..."
            return 1
        } else {
            Write-Host "Successful command execution"
            return 0
        }
    }
}
