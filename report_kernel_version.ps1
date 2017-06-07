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
# $linuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData
# $c = $linuxInfo.ID
# $c = $c + $linuxInfo.VERSION_ID
# $c=$c -replace '"',""
# $c=$c -replace '\.',""
# $c="progress_logs/" + $c
$c=hostname

$linuxOs = $linuxInfo.ID
phoneHome "Preparing VMs for Azure insertion..."

$kernel_name=uname -r
$expected=Get-Content /root/expected_version

if (($kernel_name.CompareTo($expected)) -ne 0) {
    phoneHome "Azure insertion cancelled because OS version did not match expected..."
}

$c=$c -replace "progress_logs","boot_results"

if (($kernel_name.CompareTo($expected)) -ne 0) {
    phoneHome "Failed $kernel_name $expected"

    remove-pssession $s

    exit 1
} else {
    echo "Passed.  Let's go to Azure!!"

    phoneHome "Success $kernel_name"

    remove-pssession $s

    exit 0
}

