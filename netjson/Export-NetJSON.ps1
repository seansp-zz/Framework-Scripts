#!/usr/bin/powershell
#
#  Consume the XML describing the LIS testset and output NetJSON describing the network configuration defined.
#
#  Author:  Derek Sean Spratt, Software Engineer, Microsoft
$ConfigForLISTest="C:/Users/Seansp/vscode/azure-linux-automation/Azure_ICA_all.xml"

$global:unhandledKinds = @()

#TODO: I am using $global:name because I got frustrated getting my name passed into this function.
#      This needs to be corrected, but is functional at present. /HACK
Function MakeHostedServiceHash( $source )
{
  $hash = @{
    'Name' = $global:name;
  }

  $machines = @{}
  $virtualNetworks = @{}
  $tags = @{}

  foreach( $child in $source.ChildNodes )
  {
    switch ($child.Name) {
      "isDeployed" {
        Write-Host "Deployment will be omitted." -ForegroundColor Gray
      }
      "VirtualMachine" {
        Write-Host "There is a virtual machine here." -ForegroundColor Yellow

      }
      "VnetDomainDBFilePath"
      {
        Write-Host "VnetDomainDBFilePath"
      }
      "VnetName" {
        Write-Host "Virtual Network!!"
      }
      "DnsServerIP" {
        Write-Host "DNS preconfigured."
      }
      "Subnet1Range" {
        Write-Host "Subnet1Range"
      }
      "VnetDomainRevFilePath" {
        Write-Host "VnetDomainRevFilePath"
      }
      "Tag" {
        Write-Host "Tag"
      }
      "Subnet2Range" { Write-Host "Subnet2Range" }
      "Subnet2Range" { Write-Host "Subnet2Range" }
      "ARMVnetName" { Write-Host "ARMVnetName" }
      "ARMVnetDomainDBFilePath" { Write-Host "ARMVnetDomainDBFilePath" }
      "ARMVnetDomainRevFilePath" { Write-Host "ARMVnetDomainRevFilePath" }
      "ARMSubnet1Range" { Write-Host "ARMSubnet1Range" }
      "ARMSubnet2Range" { Write-Host "ARMSubnet2Range" }
      "ARMDnsServerIP" { Write-Host "ARMDnsServerIP" }
      "Subnet2Range" { Write-Host "Subnet2Range" }
      "ARMVnetName" { Write-Host "ARMVnetName" }
      "ARMVnetDomainDBFilePath" { Write-Host "ARMVnetDomainDBFilePath" }
      "ARMVnetDomainRevFilePath" { Write-Host "ARMVnetDomainRevFilePath" }
      "ARMSubnet1Range" { Write-Host "ARMSubnet1Range" }
      "ARMSubnet2Range" { Write-Host "ARMSubnet2Range" }
      "ARMDnsServerIP" { Write-Host "ARMDnsServerIP" }
      "Subnet2Range" { Write-Host "Subnet2Range" }
      "ARMVnetName" { Write-Host "ARMVnetName" }
      "ARMVnetDomainDBFilePath" { Write-Host "ARMVnetDomainDBFilePath" }
      "ARMVnetDomainRevFilePath" { Write-Host "ARMVnetDomainRevFilePath" }
      "ARMSubnet1Range" { Write-Host "ARMSubnet1Range" }
      "ARMSubnet2Range" { Write-Host "ARMSubnet2Range" }
      "ARMDnsServerIP" { Write-Host "ARMDnsServerIP" }
      "Subnet2Range" { Write-Host "Subnet2Range" }
      "ARMVnetName" { Write-Host "ARMVnetName" }
      "ARMVnetDomainDBFilePath" { Write-Host "ARMVnetDomainDBFilePath" }
      "ARMVnetDomainRevFilePath" { Write-Host "ARMVnetDomainRevFilePath" }
      "ARMSubnet1Range" { Write-Host "ARMSubnet1Range" }
      "ARMSubnet2Range" { Write-Host "ARMSubnet2Range" }
      "ARMDnsServerIP" { Write-Host "ARMDnsServerIP" }
      Default {
        Write-Host "Unhandled: $($child.Name)"
        $name = $child.Name
        $text = """$name"" { Write-Host ""$name"" } "
        $global:unhandledKinds += $text;
      }
    }
  }
  $hash
}



Write-Output "Consuming XML from : $ConfigForLISTest"
$xmlConfig = [xml](Get-Content $ConfigForLISTest)
$user = $xmlConfig.config.Azure.Deployment.Data.UserName
$password = $xmlConfig.config.Azure.Deployment.Data.Password
$sshKey = $xmlConfig.config.Azure.Deployment.Data.sshKey
$sshPublickey = $xmlConfig.config.Azure.Deployment.Data.sshPublicKey

Write-HOst "This is my boom-stick" -Foreground Cyan
$setup_count = 0
$data_store_for_deployments = @{}
foreach( $setupKinds in $xmlConfig.config.Azure.Deployment.ChildNodes )
{
    if( 0 -eq $setup_count )
    {
      $data_store_for_deployments = $setupKinds
    }
    else {
      $hosted_service_count = 0
      foreach( $service in $setupKinds.ChildNodes )
      {
        if( "HostedService" -eq $service.Name )
        {
          $hosted_service_count += 1
          #TODO: Can have multiple hostedservices.  I see this with PublicEndpoint where the distinguishing item is an
          #      extra <TAG>DTAP</TAG>  ... This variation likely exists with other setuptypes too.
          $global:name = "$($setupKinds.Name)"
          if( $hosted_service_count -gt 1 )
          {
            $global:name = "$($global:name)-$hosted_service_count"
          }
          $json = MakeHostedServiceHash( $service ) | ConvertTo-Json
          Write-Host $json
        }
      }
    }
    $setup_count += 1
}

Write-Host $global:unhandledKinds

