#
#  Copies user VHDs it finds for VMs in the reference resource group into the 'clean-vhds' 
#  storage container.  The target blobs will have the name of the VM, as a .vhd
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$false)] [string] $sourceSA="smokesourcestorageacct",
    [Parameter(Mandatory=$false)] [string] $sourceRG="smoke_source_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceContainer="clean-vhds"
)

Write-Host "Importing the context...." -ForegroundColor Green
Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'

Write-Host "Selecting the Azure subscription..." -ForegroundColor Green
Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4"

Set-AzureRmCurrentStorageAccount –ResourceGroupName $sourceRG –StorageAccountName $sourceSA
$blobs=get-AzureStorageBlob -Container $sourceContainer -Blob "*-Smoke-1*.vhd"

foreach ($oneblob in $blobs) {
    $sourceName=$oneblob.Name

    $sourceName = $sourceName.Replace("-Smoke-1.vhd","")
 
    C:\Framework-Scripts\make_template_from_clean.ps1 $sourceName
}

write-host "All done!"
exit 0