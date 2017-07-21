function login_azure([string] $rg, [string] $sa) {

    Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx' > $null
    Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4" > $null

    if ($rg -ne "" -and $sa -ne "") {
        Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $sa > $null
    }
}

function make_cred () {
    $pw = convertto-securestring -AsPlainText -force -string 'P@ssW0rd-'
    $cred = new-object -typename system.management.automation.pscredential -argumentlist "mstest",$pw

    return $cred
}

function create_psrp_session([string] $vmName, [string] $rg, [string] $SA,
                             [System.Management.Automation.PSCredential] $cred,
                             [System.Management.Automation.Remoting.PSSessionOption] $o)
 {
    
    Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $SA > $null

    $pipName=$vmName + "-pip"

    $ipAddress = Get-AzureRmPublicIpAddress -ResourceGroupName $rg -Name $pipName

    if ($ipAddress.IpAddress -eq "Not Assigned") {
        Write-Error "Machine $vmName does not have an assigned IP address.  Cannot create PSRP session to the machine."
        return $null
    }

    new-PSSession -computername $ipAddress.IpAddress -credential $cred -authentication Basic -UseSSL -Port 443 -SessionOption $o
}
