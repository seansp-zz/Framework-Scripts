
param (
    [Parameter(Mandatory=$false)] [string] $resourceGroup="smoke_working_resource_group",
    [Parameter(Mandatory=$false)] [string] $storageAccount="smokeworkingstorageacct"
)

. ./secrets.ps1 

Write-Host "Cleaning boot diag blobs from storage account $storageAccount, resource group $resourceGroup"

Write-Host "Importing the context...." 
Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'

Write-Host "Selecting the Azure subscription..." 
Select-AzureRmSubscription -SubscriptionId "$AZURE_SUBSCRIPTION_ID" 
Set-AzureRmCurrentStorageAccount –ResourceGroupName $resourceGroup –StorageAccountName $storageAccount 

$containers=get-azurestoragecontainer
foreach ($container in $containers) {
    if ($container.Name -like "bootdiag*") { 
        Remove-AzureStorageContainer -Force -Name $container.Name  
    }
 }       