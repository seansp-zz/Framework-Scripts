function login_azure($rg,$sa) {
    Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'
    Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4"

    if ($rg -ne "" -and $sa -ne "") {
        Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $sa
    }
}

function make_cred () {
    $pw = convertto-securestring -AsPlainText -force -string 'P@ssW0rd-'
    $cred = new-object -typename system.management.automation.pscredential -argumentlist "mstest",$pw

    return $cred
}

function create_psrp_session ($vmName, $rg, $cred, $opts) {
    $pipName=$vmName + "-PIP"

    $ipAddress = Get-AzureRmPublicIpAddress -ResourceGroupName $rg -Name $pipName

    if ($ipAddress.IpAddress -eq "Not Assigned") {
        Write-Error "Machine $vmName does not have an assigned IP address.  Cannot create PSRP session to the machine."
        return $null
    }

    $session=new-PSSession -computername $ipAddress.IpAddress -credential $cred -authentication Basic -UseSSL -Port 443 -SessionOption $opts

    return $session
}
