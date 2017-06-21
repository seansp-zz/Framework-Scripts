Write-Host "Copying Linux kernel build artifacts to the cloud..."
Write-Host "Importing the context...." -ForegroundColor green
Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'

Write-Host "Selecting the Azure subscription..." -ForegroundColor green
Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4"
Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $nm

$key=Get-AzureRmStorageAccountKey -ResourceGroupName $rg -Name $nm
$context=New-AzureStorageContext -StorageAccountName $destAccountName -StorageAccountKey $key[0].Value

#
#  Copy the latest packages up to Azure
#
$packages=get-childitem -path z:
Remove-Item -Path C:\temp\file_list
foreach ($package in $packages) {
    $package.name | out-file -Append C:\temp\file_list
}

Get-ChildItem z:\ | Set-AzureStorageBlobContent -Container "latest-packages" -force
Get-ChildItem C:\temp\file_list | Set-AzureStorageBlobContent -Container "latest-packages" -force

#
#  Clear the working container
#
Get-AzureStorageBlob -Container $destContainerName -blob * | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $destContainerName}

#
#  Copy the kernel packages to Azure.
#
dir z: > c:\temp\file_list
Get-ChildItem z:\ | Set-AzureStorageBlobContent -Container "latest-packages" -force

Write-Host "Copy complete."
