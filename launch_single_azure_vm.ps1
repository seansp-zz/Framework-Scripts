param (
    [Parameter(Mandatory=$true)] [string] $vmName,
    [Parameter(Mandatory=$true)] [string] $resourceGroup="smoke_working_resource_group",
    [Parameter(Mandatory=$true)] [string] $storageAccount="smokeworkingstorageacct",
    [Parameter(Mandatory=$true)] [string] $containerName="vhds-under-test",

    [Parameter(Mandatory=$true)] [string] $network="SmokeVNet",
    [Parameter(Mandatory=$true)] [string] $subnet="SmokeSubnet-1",
    [Parameter(Mandatory=$true)] [string] $NSG="SmokeNSG",

    [Parameter(Mandatory=$true)] [string] $location="westus",

    [Parameter(Mandatory=$false)] [string] $addAdminUser="",
    [Parameter(Mandatory=$false)] [string] $adminUser="",
    [Parameter(Mandatory=$false)] [string] $adminPW="",
    [Parameter(Mandatory=$false)] [string] $Location="westus",
    [Parameter(Mandatory=$false)] [string] $VMFlavor="Standard_D2"
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$scriptPath\backend.ps1"

$backendFactory = [BackendFactory]::new()
$azureBackend = $backendFactory.GetBackend("AzureBackend", @(1))

$azureBackend.ResourceGroupName = $resourceGroup
$azureBackend.StorageAccountName = $storageAccount
$azureBackend.ContainerName = $containerName
$azureBackend.Location = $Location
$azureBackend.VMFlavor = $VMFlavor
$azureBackend.NetworkName = $network
$azureBackend.SubnetName = $subnet
$azureBackend.NetworkSecGroupName = $NSG

$azureInstance = $azureBackend.GetInstanceWrapper($vmName)
$azureInstance.Cleanup()
$azureInstance.Create()