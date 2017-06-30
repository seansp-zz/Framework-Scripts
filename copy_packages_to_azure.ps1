param (
    [Parameter(Mandatory=$false)] [string] $nm="azuresmokestorageaccount",
    [Parameter(Mandatory=$false)] [string] $rg="azuresmokeresourcegroup",
    [Parameter(Mandatory=$false)] [string] $destAccountName="azuresmokestorageaccount",
    [Parameter(Mandatory=$false)] [string] $destContainer="latest-packages",
    [Parameter(Mandatory=$false)] [string] $location="westus"
)

Write-Host "Copying Linux kernel build artifacts to the cloud..."
Write-Host "Importing the context...." -ForegroundColor green
Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'

Write-Host "Selecting the Azure subscription..." -ForegroundColor green
Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4"
Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $nm

$failure_point = "No failure"
$key=Get-AzureRmStorageAccountKey -ResourceGroupName $rg -Name $nm
if ($? -eq $false) {
    $failure_point="GetKey"
    goto ErrOut:
}

$context=New-AzureStorageContext -StorageAccountName $destAccountName -StorageAccountKey $key[0].Value
if ($? -eq $false) {
    $failure_point="NewContext"
    goto ErrOut:
}

#
#  Copy the latest packages up to Azure
#
$packages=get-childitem -path z:
Remove-Item -Path C:\temp\file_list -Force

foreach ($package in $packages) {
    $package.name | out-file -Append C:\temp\file_list
}

#
#  Clear the working container
#
Get-AzureStorageBlob -Container $destContainer -blob * | ForEach-Object {Remove-AzureStorageBlob -Blob $_.Name -Container $destContainer}
if ($? -eq $false) {
    $failure_point="ClearingContainers"
    goto ErrOut:
}

#
#  Copy the kernel packages to Azure.
#
Get-ChildItem z:\ | Set-AzureStorageBlobContent -Container $destContainer -force
if ($? -eq $false) {
    $failure_point="CopyPackages"
    goto ErrOut:
}

Write-Host "Copy complete."
exit 0

:ErrOut
#
#  Not really sure what happened.  Better let a human have a look...
#
write-host "Copying packages to Azure has failed in operation $failure_point."
exit 1