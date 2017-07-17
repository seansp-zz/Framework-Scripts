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

#
#  Session stuff
#
$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$pw = convertto-securestring -AsPlainText -force -string 'P@ssW0rd-'
$cred = new-object -typename system.management.automation.pscredential -argumentlist "mstest",$pw

Write-Host "Importing the context...." -ForegroundColor Green
Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'

Write-Host "Selecting the Azure subscription..." -ForegroundColor Green
Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4"
Set-AzureRmCurrentStorageAccount –ResourceGroupName $sourceRG –StorageAccountName $sourceSA

Write-Host "Generalizing the running machines..."  -ForegroundColor green
$runningVMs = Get-AzureRmVm -ResourceGroupName $sourceRG

foreach ($vm in $runningVMs) {
    $pipName=$vm.Name + "-pip"

    $ipAddress = Get-AzureRmPublicIpAddress -ResourceGroupName $sourceRG -Name $pipName

    Write-Host "Deprovisioning machine with public IP provisioned as $pipName" -ForegroundColor Green
    $session=new-PSSession -computername $ipAddress.IpAddress -credential $cred -authentication Basic -UseSSL -Port 443 -SessionOption $o

    if ($? -eq $true) {
        Write-Host "    PSRP Connection established; deprovisioning and shutting down" -ForegroundColor Green
        invoke-command -session $session -ScriptBlock {sudo waagent --deprovision -force; sudo shutdown}
    } else {
        Write-Host "    UNABLE TO PSRP TO MACHINE!  COULD NOT DEPROVISION" -ForegroundColor Red
    }

    Remove-PSSession $session
}