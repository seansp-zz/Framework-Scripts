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

    invoke-command -Credential $cred -ComputerName 10.123.175.125 -Authentication Basic -ScriptBlock ${function:callItIn} -ArgumentList $c,$m
}

$kernel_name=uname -r
phoneHome $kernel_name
