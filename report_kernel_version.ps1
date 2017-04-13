#!/usr/bin/powershell
#

function callItIn($c, $m) {
    $output_path="c:\temp\$c"
    
    $m | out-file -Append $output_path
    return
}

function phoneHome($m) {
    $username="serviceb"
    $password="Pine#Tar*9"
    $cred= New-Object System.Management.Automation.PSCredential -ArgumentList @($username,(ConvertTo-SecureString -String $password -AsPlainText -Force))

    #
    #  What OS are we on?
    #
    $linuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData
    $c = $linuxInfo.ID
    $c=$c -replace '"',""
    $c=$c+"-boot"

    invoke-command -Credential $cred -ComputerName MSLK-BOOT-TEST-HOST.redmond.corp.microsoft.com -Authentication Basic -ScriptBlock ${function:callItIn} -ArgumentList $c,$m
}

$kernel_name=uname -r
$expected=Get-Content /tmp/expected_version
if ($kenel_name -ne $expected) {
    phoneHome "Failed $kernel_name $expected"
} else {
    phoneHome "Success $kernel_name"
}
