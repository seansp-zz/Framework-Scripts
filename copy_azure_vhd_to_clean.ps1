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

    #
    #  Normally you don't need to change these...
    [Parameter(Mandatory=$false)] [string] $destSA="smokesourcestorageacct",
    [Parameter(Mandatory=$false)] [string] $destRG="smoke_source_resource_group",
    [Parameter(Mandatory=$false)] [string] $destContainer="clean-vhds",
    [Parameter(Mandatory=$false)] [string] $destExtension="-Smoke-1.vhd",

    [Parameter(Mandatory=$false)] [string] $location="westus",

    [Parameter(Mandatory=$false)] [string[]] $vmNames=""
)

Write-Host "Launching jobs to copy machines..." -ForegroundColor Yellow
C:\Framework-Scripts\copy_single_image_container_to_container.ps1 -sourceSA $sourceSA -sourceRG $sourceRG -sourceContainer $sourceContainer -destSA $destSA `
                                                                  -destRG $destRG -sourceExtension ".vhd" -destExtension $destExtension -destContainer $destContainer `
                                                                  -location $location -makeDronesFromAll -overwriteVHDs -vmNamesIn $vmNames

