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
        Start-Transcript -Path $transcriptPath -Force -ErrorAction SilentlyContinue -Append
        $this.Backend = $Backend
        $this.Name = $Name
        Write-Host ("Initialized instance wrapper" + $this.Name) -ForegroundColor Blue
    }

    [void] Cleanup () {
        $this.Backend.CleanupInstance($this.Name)
    }

    [void] Create () {
        $this.Backend.CreateInstance($this.Name)
    }

    [String] GetPublicIP () {
        return $this.Backend.GetPublicIP($this.Name)
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

    [void] CreateInstance ($InstanceName) {
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

    [Object] GetPSSession ($InstanceName) {
        Write-Host ("Getting new Powershell Session on backend " + $this.Name) -ForegroundColor Green
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
    [String] $VMFlavor = "Standard_D2"
    [String] $NetworkName = "SmokeVNet"
    [String] $SubnetName = "SmokeSubnet"
    [String] $NetworkSecGroupName = "SmokeNSG"
    [String] $addressPrefix = "172.19.0.0/16"
    [String] $subnetPrefix = "172.19.0.0/24"

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

        login_azure $this.ResourceGroupName $this.StorageAccountName $this.Location

        $instance = [AzureInstance]::new($this, $InstanceName)
        return $instance
    }

    [void] CleanupInstance ($InstanceName) {
        ([Backend]$this).CleanupInstance($InstanceName)
        $vm = Get-AzureRmVm -ResourceGroupName $this.ResourceGroupName -Status | `
            Where-Object -Property Name -eq $InstanceName
        if (!$vm) {
            Write-Host ("VM $InstanceName does not exist") -ForegroundColor Yellow
            return
        }
        Get-AzureRmVm -ResourceGroupName $this.ResourceGroupName -Status | `
            Where-Object -Property Name -eq $InstanceName | `
            Remove-AzureRmVM -Force
    }

    [void] CreateInstance ($InstanceName) {        
        ([Backend]$this).CreateInstance($InstanceName)
        Write-Host "Creating a new VM config..." -ForegroundColor Yellow

        $regionSuffix = ("-" + $this.Location) -replace " ","-"
        $this.NetworkName = $this.NetworkName + $regionSuffix
        $this.SubnetName =  $this.SubnetName + $regionSuffix
        $this.NetworkSecGroupName = $this.NetworkSecGroupName + $regionSuffix
        
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

        $VMVNETObject = Get-AzureRmVirtualNetwork -Name $this.NetworkName -ResourceGroupName $this.ResourceGroupName
        if (!$VMVNETObject) {
            write-host "Network does not exist for this region.  Creating now..." -ForegroundColor Yellow
            $VMSubnetObject = New-AzureRmVirtualNetworkSubnetConfig -Name $this.SubnetName  -AddressPrefix $this.subnetPrefix -NetworkSecurityGroup $sg
            New-AzureRmVirtualNetwork   -Name $this.NetworkName -ResourceGroupName $this.ResourceGroupName -Location $this.Location -AddressPrefix $this.addressPrefix -Subnet $VMSubnetObject
            $VMVNETObject = Get-AzureRmVirtualNetwork -Name $this.NetworkName -ResourceGroupName $this.ResourceGroupName
        }

        $VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name $this.SubnetName -VirtualNetwork $VMVNETObject
        if (!$VMSubnetObject) {
            write-host "Subnet does not exist for this region.  Creating now..." -ForegroundColor Yellow
            Add-AzureRmVirtualNetworkSubnetConfig -Name $this.SubnetName -VirtualNetwork $VMVNETObject -AddressPrefix $this.subnetPrefix -NetworkSecurityGroup $sg
            Set-AzureRmVirtualNetwork -VirtualNetwork $VMVNETObject 
            $VMVNETObject = Get-AzureRmVirtualNetwork -Name $this.NetworkName -ResourceGroupName $this.ResourceGroupName
            $VMSubnetObject = Get-AzureRmVirtualNetworkSubnetConfig -Name $this.SubnetName -VirtualNetwork $VMVNETObject 
        }

        $vm = New-AzureRmVMConfig -VMName $InstanceName -VMSize $this.VMFlavor
        Write-Host "Assigning network " $this.NetworkName " and subnet config " $this.SubnetName " with NSG " $this.NetworkSecGroupName " to new machine" -ForegroundColor Yellow            

        Write-Host "Assigning the public IP address" -ForegroundColor Yellow
        $ipName = $InstanceName + "PublicIP" + $regionSuffix
        $pip = Get-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName -Name $ipName `
            -ErrorAction SilentlyContinue
        if (!$pip) {
            write-host "Public IP does not exist for this region.  Creating now..." -ForegroundColor Yellow
            $vm = New-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName -Location $this.Location `
                -Name $ipName -AllocationMethod Dynamic -IdleTimeoutInMinutes 4
            $pip = Get-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName -Name $ipName
        }

        Write-Host "Assigning the network interface" -ForegroundColor Yellow
        $nicName = $InstanceName + "VMNic" + $regionSuffix
        $VNIC = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $this.ResourceGroupName -ErrorAction SilentlyContinue
        if (!$VNIC) {
            Write-Host "Creating new network interface" -ForegroundColor Yellow
            $vm = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $this.ResourceGroupName `
                -Location $this.Location -SubnetId $VMSubnetObject.Id -publicipaddressid $pip.Id
            $VNIC = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $this.ResourceGroupName
        }
        $VNIC.NetworkSecurityGroup = $sg
        
        Set-AzureRmNetworkInterface -NetworkInterface $VNIC

        Write-Host "Adding the network interface" -ForegroundColor Yellow
        Add-AzureRmVMNetworkInterface -VM $vm -Id $VNIC.Id
        
        $blobURIRaw = ("https://{0}.blob.core.windows.net/{1}/{2}.vhd" -f `
                       @($this.StorageAccountName, $this.ContainerName, $InstanceName))

        $vm = Set-AzureRmVMOSDisk -VM $vm -Name $InstanceName -VhdUri $blobURIRaw -CreateOption Attach -Linux
        try {
            Write-Host "Starting the VM" -ForegroundColor Yellow
            $NEWVM = New-AzureRmVM -ResourceGroupName $this.ResourceGroupName -Location $this.Location -VM $vm
            if (!$NEWVM) {
                Write-Host "Failed to create VM" -ForegroundColor Red
            } else {
                Write-Host "VM $InstanceName started successfully..." -ForegroundColor Green
            }
        } catch {
            Write-Host "Caught exception attempting to start the new VM.  Aborting..."
            Stop-Transcript
            return
        }
    }

    [String] GetPublicIP ($InstanceName) {
        ([Backend]$this).GetPublicIP($InstanceName)
        $ip = Get-AzureRmPublicIpAddress -ResourceGroupName $this.ResourceGroupName `
            -Name ($InstanceName + "-pip")
        if ($ip) {
            return $ip.IPAddress
        } else {
            return $null
        }
    }

    [Object] GetPSSession ($InstanceName) {
        return ([Backend]$this).GetPSSession()
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
