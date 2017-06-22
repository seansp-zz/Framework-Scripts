
param (
    [Parameter(Mandatory=$true)] [string] $resourceGroup="azuresmokeresourcegroup",
    [Parameter(Mandatory=$true)] [string] $storageAccount="azuresmokestorageaccount",
    [Parameter(Mandatory=$true)] [string] $n,
    [Parameter(Mandatory=$true)] [string] $j
)

Write-Host "Cleaning boot diag blobs from storage account $storageAccount, resource group $resourceGroup"

$nm="azuresmokestoragesccount"

Write-Host "Importing the context...." | out-file $logFileName
Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx' | out-file -append $logFileName

Write-Host "Selecting the Azure subscription..." | out-file -append $logFileName
Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4" | out-file -Append $logFileName
Set-AzureRmCurrentStorageAccount –ResourceGroupName $g –StorageAccountName $nm | out-file -Append $logFileName

$containers=get-azurestoragecontainer
foreach ($container in $containers) {
    if ($container.Name -like "bootdiag*") { 
        Remove-AzureStorageContainer -Force -Name $container.Name  
    }
 }       