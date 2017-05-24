#!/usr/bin/powershell
#

function callItIn($c, $m) {
    $output_path="c:\temp\$c"
    
    $m | out-file -Append $output_path
    return
}

function phoneHome($m) {

    invoke-command -session $s -ScriptBlock ${function:callItIn} -ArgumentList $c,$m
}

$pw=convertto-securestring -AsPlainText -force -string 'Pa$$w0rd!'
$cred=new-object -typename system.management.automation.pscredential -argumentlist "psRemote",$pw
$s=new-PSSession -computername mslk-smoke-host.redmond.corp.microsoft.com -credential $cred -authentication Basic

#
#  What OS are we on?
#
$linuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData
$c = $linuxInfo.ID
$c=$c -replace '"',""
$c=$c+"-boot"

$kernel_name=uname -r
$expected=Get-Content /root/expected_version

if (($kernel_name.CompareTo($expected)) -ne 0) {
    phoneHome "Failed $kernel_name $expected"
} else {
    echo "Passed"
    phoneHome "Success $kernel_name"
}

$c = $linuxInfo.ID
$c=$c -replace '"',""
$c=$c+"-prep_for_azure"
$linuxOs = $linuxInfo.ID
phoneHome "Preparing VMs for Azure insertion..."

if ($linuxOs -eq '"centos"') {
    /root/Framework-Scripts/prep_CentOS_for_azure.ps1
} else {
    /root/Framework-Scripts/prep_Ubuntu_for_azure.ps1
}

#
#  The following line will never be executed, because the prep_ scripts shut the machine down
#
remove-pssession $s
