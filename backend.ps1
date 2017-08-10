##### Install PowerShell 5 using https://github.com/DarwinJS/ChocoPackages/blob/master/PowerShell/v5.1/tools/ChocolateyInstall.ps1#L107-L173
##### For 2008 R2, run the .ps1 from: https://download.microsoft.com/download/6/F/5/6F5FF66C-6775-42B0-86C4-47D41F2DA187/Win7AndW2K8R2-KB3191566-x64.zip

class Instance {
    [Backend] $Backend
    [String] $Name
    [String] $LogPath = "C:\temp\transcripts\launch_single_azure_vm_{0}.log"
    [String] $DefaultUsername
    [String] $DefaultPassword

    Instance ($Backend, $Name) {
        $transcriptPath = $this.LogPath -f @($Name)
        Start-Transcript -Path $transcriptPath -Force  -Append
        $this.Backend = $Backend
        $this.Name = $Name
        Write-Host ("Initialized instance wrapper" + $this.Name) -ForegroundColor Blue
    }

    [void] Cleanup () {
        $this.Backend.CleanupInstance($this.Name)
    }

    [void] CreateFromSpecialized () {
        $this.Backend.CreateInstanceFromSpecialized($this.Name)
    }

    [void] CreateFromURN () {
        $this.Backend.CreateInstanceFromURN($this.Name)
    }

    [void] CreateFromGeneralized () {
        $this.Backend.CreateInstanceFromGeneralized($this.Name)
    }

    [void] StopInstance () {
        $this.Backend.StopInstance($this.Name)
    }

    [void] RemoveInstance () {
        $this.Backend.removeInstance($this.Name)
    }

    [String] GetPublicIP () {
        return $this.Backend.GetPublicIP($this.Name)
    }

    [object] GetVM () {
        return $this.Backend.GetVM($this.Name)
    }

    [String] SetupAzureRG() 
    {
        return $this.Backend.SetupAzureRG()
    }

    [string] WaitForAzureRG( ) {
        return $this.Backend.WaitForAzureRG( )
    }
}

class AzureInstance : Instance {
    AzureInstance ($Backend, $Name) : base ($Backend, $Name) {}
}

class HypervInstance : Instance {
    HypervInstance ($Params) : base ($Params) {}
}


class Backend {
    [String] $Name="BaseBackend"

    Backend ($Params) {
        Write-Host ("Initialized backend " + $this.Name) -ForegroundColor Blue
    }

    [Instance] GetInstanceWrapper ($InstanceName) {
        Write-Host ("Initializing instance on backend " + $this.Name) -ForegroundColor Green
        return $null
    }

    [void] CreateInstanceFromSpecialized ($InstanceName) {
    }

    [void] CreateInstanceFromURN ($InstanceName) {
    }

    [void] CreateInstanceFromGeneralized ($InstanceName) {
    }

    [void] CleanupInstance ($InstanceName) {
        Write-Host ("Cleaning instance and associated resources on backend " + $this.Name) `
            -ForegroundColor Red
    }

    [void] RebootInstance ($InstanceName) {
        Write-Host ("Rebooting instance on backend " + $this.Name) -ForegroundColor Green
    }

    [String] GetPublicIP ($InstanceName) {
        Write-Host ("Getting instance public IP a on backend " + $this.Name) -ForegroundColor Green
        return $null
    }

    [object] GetVM($instanceName) {
       Write-Host ("Getting instance VM on backend " + $this.Name) -ForegroundColor Green
       return $null       
    }

    [void] StopInstance($instanceName) {
       Write-Host ("StopInstance VM on backend " + $this.Name) -ForegroundColor Green
    }

    [void] RemoveInstance($instanceName) {
       Write-Host ("RemoveInstance VM on backend " + $this.Name) -ForegroundColor Green
    }

    [Object] GetPSSession ($InstanceName) {
        Write-Host ("Getting new Powershell Session on backend " + $this.Name) -ForegroundColor Green
        return $null
    }

    [string] SetupAzureRG( ) {
        Write-Host ("Setting up Azure Resource Groups " + $this.Name) -ForegroundColor Green
        return $null
    }

    [string] WaitForAzureRG( ) {
        Write-Host ("Waiting for Azure resource group setup " + $this.Name) -ForegroundColor Green
        return $null
    }
}

class AzureBackend : Backend {
    [String] $Name = "AzureBackend"
    [String] $SecretsPath = "C:\Framework-Scripts\secrets.ps1"
    [String] $CommonFunctionsPath = "C:\Framework-Scripts\common_functions.ps1"
    [String] $ProfilePath = "C:\Azure\ProfileContext.ctx"
    [String] $ResourceGroupName = "smoke_working_resource_group"
    [String] $StorageAccountName = "smokeworkingstorageacct"
    [String] $ContainerName = "vhds-under-test"
    [String] $Location = "westus"
    [String] $VMFlavor = "Standard_D2_V2"
    [String] $NetworkName = "SmokeVNet"
    [String] $SubnetName = "SmokeSubnet"
    [String] $NetworkSecGroupName = "SmokeNSG"
    [String] $addressPrefix = "172.19.0.0/16"
    [String] $subnetPrefix = "172.19.0.0/24"
    [String] $blobURN = "Unset"
    [String] $suffix = "-Smoke-1"

    AzureBackend ($Params) : base ($Params) {
        if (Test-Path $this.CommonFunctionsPath) {
            . $this.CommonFunctionsPath
        } else {
            throw "??? Common Functions file file does not exist."
        }

        if (Test-Path $this.SecretsPath) {
            . $this.SecretsPath
        } else {
            throw "Secrets file does not exist."
        }
    }

    [Instance] GetInstanceWrapper ($InstanceName) {
        if (Test-Path $this.CommonFunctionsPath) {
            . $this.CommonFunctionsPath
        } else {
            throw "??? Common Functions file file does not exist."
        }

        if (Test-Path $this.SecretsPath) {
            . $this.SecretsPath
        } else {
            throw "Secrets file does not exist."
        }

        $this.suffix = $this.suffix -replace "_","-"
        login_azure $this.ResourceGroupName $this.StorageAccountName $this.Location

        $instance = [AzureInstance]::new($this, $InstanceName)
        return $instance
    }

    [string] SetupAzureRG( ) {
        #
        #  Avoid potential race conditions
        Write-Host "Getting the NSG"
        $sg = $this.getNSG()

        Write-Host "Getting the network"
        $VMVNETObject = $this.getNetwork($sg)

        Write-Host "Getting the subnet"
        $VMSubnetObject = $this.getSubnet($sg, $VMVNETObject)

        return "Success"
    }

    [string] WaitForAzureRG( ) {
        $azureIsReady = $false
        while ($azureIsReady -eq $false) {
            $sg = Get-AzureRmNetworkSecurityGroup -Name $this.NetworkSecGroupName -ResourceGroupName $this.ResourceGroupName
            if (!$sg) {
                sleep(10)
            } else {
                $VMVNETObject = Get-AzureRmVirtualNetwork -Name $this.NetworkName -ResourceGroupName $this.ResourceGroupName
                if (!$VMVNETObject) {
                    sleep(10)
                } else {
                    $VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name $this.SubnetName -VirtualNetwork $VMVNETObject
                    if (!$VMSubnetObject) {
                        sleep(10)
                    } else {
                        $azureIsReady = $true
                    }
                }
            }
        }

        return "Success"
    }

    [void] StopInstance ($InstanceName) {
        $regionSuffix = ("-" + $this.Location) -replace " ","-"
        $imageName = $InstanceName + "-" + $this.VMFlavor + $regionSuffix.ToLower()
        $imageName = $imageName -replace "_","-"
        $imageName = $imageName + $this.suffix

        Stop-AzureRmVM -Name $imageName -ResourceGroupName $this.ResourceGroupName -Force
    }

    [void] RemoveInstance ($InstanceName) {
        $regionSuffix = ("-" + $this.Location) -replace " ","-"
        $imageName = $InstanceName + "-" + $this.VMFlavor + $regionSuffix.ToLower()
        $imageName = $imageName -replace "_","-"
        $imageName = $imageName + $this.suffix

        Remove-AzureRmVM -Name $imageName -ResourceGroupName $this.ResourceGroupName -Force
    }

    [void] CleanupInstance ($InstanceName) {
        $this.RemoveInstance($InstanceName)

        $regionSuffix = ("-" + $this.Location) -replace " ","-"
        $imageName = $InstanceName + "-" + $this.VMFlavor + $regionSuffix.ToLower()
        $imageName = $imageName -replace "_","-"
        $imageName = $imageName + $this.suffix

        $VNIC = Get-AzureRmNetworkInterface -Name $imageName -ResourceGroupName $this.ResourceGroupName 
        if ($VNIC) {
            Remove-AzureRmNetworkInterface -Name $imageName -ResourceGroupName $this.ResourceGroupName -Force
        }

        $pip = Get-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName -Name $imageName 
        if ($pip) {
            Remove-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName -Name $imageName -Force
        }        
    }

    # Microsoft.Azure.Commands.Network.Models.PSNetworkSecurityGroup
    [object] getNSG()
    {
        $sg = Get-AzureRmNetworkSecurityGroup -Name $this.NetworkSecGroupName -ResourceGroupName $this.ResourceGroupName
        if (!$sg) {
            write-host "Network security group does not exist for this region.  Creating now..." -ForegroundColor Yellow
            $rule1 = New-AzureRmNetworkSecurityRuleConfig -Name "ssl-rule" -Description "Allow SSL over HTTP" `
                                                            -Access "Allow" -Protocol "Tcp" -Direction "Inbound" -Priority "100" `
                                                            -SourceAddressPrefix "Internet" -SourcePortRange "*" `
                                                            -DestinationAddressPrefix "*" -DestinationPortRange "443"
            $rule2 = New-AzureRmNetworkSecurityRuleConfig -Name "ssh-rule" -Description "Allow SSH" `
                                                            -Access "Allow" -Protocol "Tcp" -Direction "Inbound" -Priority "101" `
                                                            -SourceAddressPrefix "Internet" -SourcePortRange "*" -DestinationAddressPrefix "*" `
                                                            -DestinationPortRange "22"

            New-AzureRmNetworkSecurityGroup -Name $this.NetworkSecGroupName -ResourceGroupName $this.ResourceGroupName -Location $this.Location -SecurityRules $rule1,$rule2

            $sg = Get-AzureRmNetworkSecurityGroup -Name $this.NetworkSecGroupName -ResourceGroupName $this.ResourceGroupName
            Write-Host "Done."
        }

        return $sg
    }

    # Microsoft.Azure.Commands.Network.Models.PSVirtualNetwork
    [object] getNetwork($sg)
    {
        $VMVNETObject = Get-AzureRmVirtualNetwork -Name $this.NetworkName -ResourceGroupName $this.ResourceGroupName
        if (!$VMVNETObject) {
            write-host "Network does not exist for this region.  Creating now..." -ForegroundColor Yellow
            $VMSubnetObject = New-AzureRmVirtualNetworkSubnetConfig -Name $this.SubnetName  -AddressPrefix $this.subnetPrefix -NetworkSecurityGroup $sg
            New-AzureRmVirtualNetwork   -Name $this.NetworkName -ResourceGroupName $this.ResourceGroupName -Location $this.Location -AddressPrefix $this.addressPrefix -Subnet $VMSubnetObject
            $VMVNETObject = Get-AzureRmVirtualNetwork -Name $this.NetworkName -ResourceGroupName $this.ResourceGroupName
        }

        return $VMVNETObject
    }

    # Microsoft.Azure.Commands.Network.Models.PSSubnet
    [object] getSubnet($sg,$VMVNETObject)
    {
        $VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name $this.SubnetName -VirtualNetwork $VMVNETObject 
        if (!$VMSubnetObject) {
            write-host "Subnet does not exist for this region.  Creating now..." -ForegroundColor Yellow
            Add-AzureRmVirtualNetworkSubnetConfig -Name $this.SubnetName -VirtualNetwork $VMVNETObject -AddressPrefix $this.subnetPrefix -NetworkSecurityGroup $sg
            Set-AzureRmVirtualNetwork -VirtualNetwork $VMVNETObject 
            $VMVNETObject = Get-AzureRmVirtualNetwork -Name $this.NetworkName -ResourceGroupName $this.ResourceGroupName
            $VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name $this.SubnetName -VirtualNetwork $VMVNETObject 
        }

        return $VMSubnetObject
    }

    # Microsoft.Azure.Commands.Network.Models.PSPublicIpAddress
    [object] getPIP($pipName)
    {
        $pip = Get-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName -Name $pipName 
        if (!$pip) {
            write-host "Public IP does not exist for this region.  Creating now..." -ForegroundColor Yellow
            $vm = New-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName -Location $this.Location `
                -Name $pipName -AllocationMethod Dynamic -IdleTimeoutInMinutes 4
            $pip = Get-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName -Name $pipName
        }

        return $pip
    }

    # Microsoft.Azure.Commands.Network.Models.PSNetworkInterface
    [object] getNIC([string] $nicName,
                    [object] $VMSubnetObject, 
                    [object] $pip)
    {
        $VNIC = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $this.ResourceGroupName 
        if (!$VNIC) {
            Write-Host "Creating new network interface" -ForegroundColor Yellow
            $vm = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $this.ResourceGroupName `
                -Location $this.Location -SubnetId $VMSubnetObject.Id -publicipaddressid $pip.Id
            $VNIC = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $this.ResourceGroupName
        }

        return $VNIC
    }

    [void] CreateInstanceFromSpecialized ($InstanceName) {        
        Write-Host "Creating a new VM config..." -ForegroundColor Yellow

        $regionSuffix = ("-" + $this.Location) -replace " ","-"
        
        $sg = $this.getNSG()

        $VMVNETObject = $this.getNetwork($sg)

        $VMSubnetObject = $this.getSubnet($sg, $VMVNETObject)

        $imageName = $InstanceName + "-" + $this.VMFlavor + $regionSuffix.ToLower()
        $imageName = $imageName -replace "_","-"
        $imageName = $imageName + $this.suffix

        $vm = New-AzureRmVMConfig -VMName $imageName -VMSize $this.VMFlavor
        Write-Host "Assigning network " $this.NetworkName " and subnet config " $this.SubnetName " with NSG " $this.NetworkSecGroupName " to new machine" -ForegroundColor Yellow            

        Write-Host "Assigning the public IP address" -ForegroundColor Yellow
        $ipName = $imageName
        $pip = $this.getPIP($ipName)

        Write-Host "Assigning the network interface" -ForegroundColor Yellow
        $nicName = $imageName
        $VNIC = $this.getNIC($nicName, $VMSubnetObject, $pip)

        Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $this.ResourceGroupName 
        $VNIC.NetworkSecurityGroup = $sg
        
        Set-AzureRmNetworkInterface -NetworkInterface $VNIC

        Write-Host "Adding the network interface" -ForegroundColor Yellow
        Add-AzureRmVMNetworkInterface -VM $vm -Id $VNIC.Id
        
        #
        #  Code specific to a specialized blob
        $blobURIRaw = ("https://{0}.blob.core.windows.net/{1}/{2}.vhd" -f `
                       @($this.StorageAccountName, $this.ContainerName, $InstanceName))

        $vm = Set-AzureRmVMOSDisk -VM $vm -Name $imageName -VhdUri $blobURIRaw -CreateOption Attach -Linux
        try {
            Write-Host "Starting the VM" -ForegroundColor Yellow
            $NEWVM = New-AzureRmVM -ResourceGroupName $this.ResourceGroupName -Location $this.Location -VM $vm
            if (!$NEWVM) {
                Write-Host "Failed to create VM" -ForegroundColor Red
            } else {
                Write-Host "VM $imageName started successfully..." -ForegroundColor Green
            }
        } catch {
            Write-Host "Caught exception attempting to start the new VM.  Aborting..."
            Stop-Transcript
            return
        }
    }

    [void] CreateInstanceFromURN ($InstanceName) {        
        Write-Host "Creating a new VM config..." -ForegroundColor Yellow

        $regionSuffix = ("-" + $this.Location) -replace " ","-"
        
        $sg = $this.getNSG()

        $VMVNETObject = $this.getNetwork($sg)

        $VMSubnetObject = $this.getSubnet($sg, $VMVNETObject)

        $imageName = $InstanceName + "-" + $this.VMFlavor + $regionSuffix.ToLower()
        $imageName = $imageName -replace "_","-"
        $imageName = $imageName + $this.suffix        

        $vm = New-AzureRmVMConfig -VMName $imageName -VMSize $this.VMFlavor
        Write-Host "Assigning network " $this.NetworkName " and subnet config " $this.SubnetName " with NSG " $this.NetworkSecGroupName " to new machine" -ForegroundColor Yellow            

        Write-Host "Assigning the public IP address" -ForegroundColor Yellow
        $ipName = $imageName
        $pip = $this.getPIP($ipName)

        Write-Host "Assigning the network interface" -ForegroundColor Yellow
        $nicName = $imageName
        $VNIC = $this.getNIC($nicName, $VMSubnetObject, $pip)
        $VNIC.NetworkSecurityGroup = $sg
        
        Set-AzureRmNetworkInterface -NetworkInterface $VNIC

        Write-Host "Adding the network interface" -ForegroundColor Yellow
        Add-AzureRmVMNetworkInterface -VM $vm -Id $VNIC.Id

        Write-Host "Parsing the blob string " $this.blobURN
        $blobParts = $this.blobURN.split(":")
        $blobSA = $this.StorageAccountName
        $blobContainer = $this.ContainerName
        $osDiskVhdUri = "https://$blobSA.blob.core.windows.net/$blobContainer/"+$imageName+".vhd"

        $trying = $true
        $tries = 0
        while ($trying -eq $true) {
            $trying = $false
            try {
                Write-Host "Starting the VM" -ForegroundColor Yellow
                $cred = make_cred_initial
                $vm = Set-AzureRmVMOperatingSystem -VM $vm -Linux -ComputerName $imageName -Credential $cred
                $vm = Set-AzureRmVMSourceImage -VM $vm -PublisherName $blobParts[0] -Offer $blobParts[1] `
                    -Skus $blobParts[2] -Version $blobParts[3]
                $vm = Set-AzureRmVMOSDisk -VM $vm -VhdUri $osDiskVhdUri -name $imageName -CreateOption fromImage -Caching ReadWrite

                $NEWVM = New-AzureRmVM -ResourceGroupName $this.ResourceGroupName -Location $this.Location -VM $vm
                if (!$NEWVM) {
                    Write-Host "Failed to create VM" -ForegroundColor Red
                    sleep(30)
                    $trying = $true
                    $tries = $tries + 1
                    if ($tries -gt 5) {
                        break
                    }
                } else {
                    Write-Host "VM $imageName started successfully..." -ForegroundColor Green
                }
            } catch {
                Write-Host "Caught exception attempting to start the new VM.  Aborting..."
            }
        }
    }

    [void] CreateInstanceFromGeneralized ($InstanceName) {        
        Write-Host "Creating a new VM config..." -ForegroundColor Yellow

        $regionSuffix = ("-" + $this.Location) -replace " ","-"
        
        $sg = $this.getNSG()

        $VMVNETObject = $this.getNetwork($sg)

        $VMSubnetObject = $this.getSubnet($sg, $VMVNETObject)

        $imageName = $InstanceName + "-" + $this.VMFlavor + $regionSuffix.ToLower()
        $imageName = $imageName -replace "_","-"
        $imageName = $imageName + $this.suffix

        $vm = New-AzureRmVMConfig -VMName $imageName -VMSize $this.VMFlavor
        Write-Host "Assigning network " $this.NetworkName " and subnet config " $this.SubnetName " with NSG " $this.NetworkSecGroupName " to new machine" -ForegroundColor Yellow            

        Write-Host "Assigning the public IP address" -ForegroundColor Yellow
        $ipName = $imageName
        $pip = $this.getPIP($ipName)

        Write-Host "Assigning the network interface" -ForegroundColor Yellow
        $nicName = $imageName
        $VNIC = $this.getNIC($nicName, $VMSubnetObject, $pip)

        Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $this.ResourceGroupName 
        $VNIC.NetworkSecurityGroup = $sg
        
        Set-AzureRmNetworkInterface -NetworkInterface $VNIC

        #
        #  Set up the OS disk
        Write-Host "Setting up the OS disk.  Image name is $imageName"       
        $blobURIRaw = ("https://{0}.blob.core.windows.net/{1}/{2}.vhd" -f `
                       @($this.StorageAccountName, $this.ContainerName, $InstanceName))

        $imageConfig = New-AzureRmImageConfig -Location $this.Location
        $imageConfig = Set-AzureRmImageOsDisk -Image $imageConfig -OsType Windows -OsState Generalized -BlobUri $blobURIRaw
        $image = New-AzureRmImage -ImageName $imageName -ResourceGroupName $this.ResourceGroupName -Image $imageConfig

        $cred = make_cred_initial
        $vm = Set-AzureRmVMSourceImage -VM $vm -Id $image.Id
        $vm = Set-AzureRmVMOSDisk -VM $vm -DiskSizeInGB 20 -name $imageName -CreateOption fromImage -Caching ReadWrite
        $vm = Set-AzureRmVMOperatingSystem -VM $vm -Windows -ComputerName $imageName `
                    -Credential $cred -ProvisionVMAgent -EnableAutoUpdate

        Write-Host "Adding the network interface" -ForegroundColor Yellow
        Add-AzureRmVMNetworkInterface -VM $vm -Id $VNIC.Id
        
        
        try {
            Write-Host "Starting the VM" -ForegroundColor Yellow
            
            $NEWVM = New-AzureRmVM -ResourceGroupName $this.ResourceGroupName -Location $this.Location -VM $vm
            if (!$NEWVM) {
                Write-Host "Failed to create VM" -ForegroundColor Red
            } else {
                Write-Host "VM $imageName started successfully..." -ForegroundColor Green
            }
        } catch {
            Write-Host "Caught exception attempting to start the VM $imageName.  Aborting..." -ForegroundColor Red
        }
    }

    [String] GetPublicIP ($InstanceName) {
        ([Backend]$this).GetPublicIP($InstanceName)
        $regionSuffix = ("-" + $this.Location) -replace " ","-"
        $imageName = $InstanceName + "-" + $this.VMFlavor + $regionSuffix.ToLower()
        $imageName = $imageName -replace "_","-"
        $imageName = $imageName + $this.suffix

        $ip = Get-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName `
            -Name ($imageName)
        if ($ip) {
            return $ip.IPAddress
        } else {
            return $null
        }
    }

    [Object] GetPSSession ($InstanceName) {
        return ([Backend]$this).GetPSSession()
    }

    [Object] GetVM($instanceName) {
        $regionSuffix = ("-" + $this.Location) -replace " ","-"
        $imageName = $InstanceName + "-" + $this.VMFlavor + $regionSuffix.ToLower()
        $imageName = $imageName -replace "_","-"
        $imageName = $imageName + $this.suffix

        write-host "GetVM looking for $imageName"

        return Get-AzureRmVM -ResourceGroupName $this.ResourceGroupName -Name $imageName
    }
}

class HypervBackend : Backend {
    [String] $Name="HypervBackend"

    HypervBackend ($Params) : base ($Params) {}
}


class BackendFactory {
    [Backend] GetBackend([String] $Type, $Params) {
        return (New-Object -TypeName $Type -ArgumentList $Params)
    }
}
