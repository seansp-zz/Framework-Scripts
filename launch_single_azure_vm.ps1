param (
    [Parameter(Mandatory=$true)] [string] $vmName,
    [Parameter(Mandatory=$true)] [string] $resourceGroup="smoke_working_resource_group",
    [Parameter(Mandatory=$true)] [string] $storageAccount="smokework",
    [Parameter(Mandatory=$true)] [string] $containerName="vhds-under-test",

    [Parameter(Mandatory=$true)] [string] $network="SmokeVNet",
    [Parameter(Mandatory=$true)] [string] $subnet="SmokeSubnet-1",
    [Parameter(Mandatory=$true)] [string] $NSG="SmokeNSG",

    [Parameter(Mandatory=$false)] [string] $addAdminUser="",
    [Parameter(Mandatory=$false)] [string] $adminUser="",
    [Parameter(Mandatory=$false)] [string] $adminPW="",
    [Parameter(Mandatory=$false)] [string] $Location="westus",
    [Parameter(Mandatory=$false)] [string] $VMFlavor="Standard_D2",

    [Parameter(Mandatory=$false)] [string] $addressPrefix = "10.0.0.0/16",
    [Parameter(Mandatory=$false)] [string] $subnetPrefix = "10.0.0.0/24",
    [Parameter(Mandatory=$false)] [string] $blobURN,

    [Parameter(Mandatory=$false)] [string] $suffix = ".vhd",

    [Parameter(Mandatory=$false)] [switch] $imageIsGeneralized = $false
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$scriptPath\backend.ps1"

$backendFactory = [BackendFactory]::new()
$azureBackend = $backendFactory.GetBackend("AzureBackend", @(1))

$azureBackend.ResourceGroupName = $resourceGroup
$azureBackend.StorageAccountName = $storageAccount
$azureBackend.ContainerName = $containerName
$azureBackend.Location = $location
$azureBackend.VMFlavor = $VMFlavor
$azureBackend.NetworkName = $network
$azureBackend.SubnetName = $subnet
$azureBackend.NetworkSecGroupName = $NSG

$azureBackend.addressPrefix = $vnetAddressPrefix
$azureBackend.subnetPrefix = $vnetSubnetAddressPrefix
$azureBackend.blobURN = $blobURN
$azureBackend.suffix = $suffix

$azureInstance = $azureBackend.GetInstanceWrapper($vmName)
$azureInstance.Cleanup()

if ($false -eq $imageIsGeneralized) {}
    $azureInstance.CreateFromSpecialized()
} else {
    $azureInstance.CreateFromGeneralized()
}