#!/usr/bin/powershell
#

$pw=convertto-securestring -AsPlainText -force -string 'Pa$$w0rd!'
$cred=new-object -typename system.management.automation.pscredential -argumentlist "psRemote",$pw
$s=new-PSSession -computername mslk-boot-test-host.redmond.corp.microsoft.com -credential $cred -authentication Basic

function callItIn($c, $m) {
    $output_path="c:\temp\$c"
    
    $m | out-file -Append $output_path
    return
}

function phoneHome($m) {

    #
    #  What OS are we on?
    #
    $linuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData
    $c = $linuxInfo.ID
    $c=$c -replace '"',""
    $c=$c+"-boot"

    invoke-command -session $s -ScriptBlock ${function:callItIn} -ArgumentList $c,$m
}

$kernel_name=uname -r
$expected=Get-Content /root/expected_version
if ($kenel_name -ne $expected) {
    phoneHome "Failed $kernel_name $expected"
} else {
    phoneHome "Success $kernel_name"
}

remove-pssession $s
