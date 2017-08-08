#
#  Copies user VHDs it finds for VMs in the reference resource group into the 'clean-vhds' 
#  storage container.  The target blobs will have the name of the VM, as a .vhd
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#
param (
    [Parameter(Mandatory=$false)] [string] $sourceSA="smokevhds",
    [Parameter(Mandatory=$false)] [string] $sourceRG="smoke_source_resource_group",
    [Parameter(Mandatory=$false)] [string] $sourceContainer="vhds",
    [Parameter(Mandatory=$false)] [string] $sourceExtension=".vhd",

    [Parameter(Mandatory=$false)] [String] $VMFlavor = "Standard_D2"
    [Parameter(Mandatory=$false)] [String] $addressPrefix = "172.19.0.0/16"
    [Parameter(Mandatory=$false)] [String] $subnetPrefix = "172.19.0.0/24"
    [Parameter(Mandatory=$false)] [string] $location="westus",

    #
    #  Normally you don't need to change these...
    [Parameter(Mandatory=$false)] [string] $destSA="smokesourcestorageacct",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_source_resource_group",
    [Parameter(Mandatory=$false)] [string] $destContainer="clean-vhds",
    [Parameter(Mandatory=$false)] [string] $destExtension="-Smoke-1.vhd",

    # 
    #  Optional -- if not given, all VMs are copied
    [Parameter(Mandatory=$false)] [string[]] $vmNames=""
)
Start-Transcript C:\temp\transcripts\create_vhd_from_azure_vm.log -Force

$regionSuffix = ("-" + $location) -replace " ","-"
$sourceSA = $sourceSA + $regionSuffix
$destSA = $destSA + $regionSuffix

Write-Host "Launching jobs to copy machine image from $sourceRG/$sourceSA/$sourceContainer to $destRG/$destSA/$destContainer..." -ForegroundColor Yellow
C:\Framework-Scripts\copy_single_image_container_to_container.ps1 -sourceSA $sourceSA -sourceRG $sourceRG -sourceContainer $sourceContainer -destSA $destSA `
                                                                  -destRG $destRG -sourceExtension ".vhd" -destExtension $destExtension -destContainer $destContainer `
                                                                  -location $location -makeDronesFromAll "False" -overwriteVHDs "True" -vmNamesIn $vmNames

Write-Host "Machines are ready for assimilation..."

Stop-Transcript
