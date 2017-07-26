#
#  Copies VHDs that have booted as expected to the test location where they will be prepped
#  for Azure automation
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$false)] [string] $sourceSA="smokeworkingstorageacct",
    [Parameter(Mandatory=$false)] [string] $sourceRG="smoke_working_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceContainer="vhds_under_test"
)

. "C:\Framework-Scripts\common_functions.ps1"
. "C:\Framework-Scripts\secrets.ps1"

#
#  Session stuff
#
$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$cred = make_cred

login_azure $sourceRG $sourceSA
$error = $false

Write-Host "Locating the running machines..."  -ForegroundColor green
$runningVMs = Get-AzureRmVm -ResourceGroupName $sourceRG
foreach ($vm in $runningVMs) {
    $vm_name=$vm.Name

    $password="$TEST_USER_ACCOUNT_PASS"

    [System.Management.Automation.Runspaces.PSSession]$session = create_psrp_session $vm_name $sourceRG $sourceSA $cred $o
    if ($? -eq $true -and $session -ne $null) {
        Write-Host "    PSRP Connection to machine $vm_name established; deprovisioning and shutting down" -ForegroundColor Green
        $deprovisionString = "echo $password | sudo -S bash -c `"/sbin/waagent -deprovision -force`""
        $deprovisionBlock=[scriptblock]::Create($deprovisionString)
        invoke-command -session $session -ScriptBlock $deprovisionBlock

        $stopBlockString = "echo $password | sudo -S bash -c shutdown"
        $stopBlock=[scriptblock]::Create($stopBlockString)
        invoke-command -session $session -ScriptBlock $stopBlock

        Write-Host "Now deallocating the machine..."
        az vm deallocate --resource-group $sourceRG --name $vm_name

        Write-Host "And finally generalizing the machine..."
        az vm generalize --resource-group $sourceRG --name $vm_name
    } else {
        Write-Host "    UNABLE TO PSRP TO MACHINE!  COULD NOT DEPROVISION" -ForegroundColor Red
        $error = $true
    }

    if ($session -ne $null) {
        Remove-PSSession $session
    }

    if ($error -eq $true) {
        exit 1
    } else {
        exit 0
    }
}