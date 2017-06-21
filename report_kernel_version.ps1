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

$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$pw=convertto-securestring -AsPlainText -force -string 'P@$$w0rd!'
$cred=new-object -typename system.management.automation.pscredential -argumentlist "mstest",$pw
$s=new-PSSession -computername lis-f1637.redmond.corp.microsoft.com -credential $cred -authentication Basic -SessionOption $o

#
#  What OS are we on?
#
# $linuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData
# $c = $linuxInfo.ID
# $c = $c + $linuxInfo.VERSION_ID
# $c=$c -replace '"',""
# $c=$c -replace '\.',""
$ourHost=hostname

$c="progress_logs/" + $ourHost

$linuxOs = $linuxInfo.ID
phoneHome "Preparing VMs for Azure insertion..."

$kernel_name=uname -r
$expected=Get-Content /root/expected_version

if (($kernel_name.CompareTo($expected)) -ne 0) {
    phoneHome "Azure insertion cancelled because OS version did not match expected..."
    phoneHome "Installed version is $kernel_name"
    phoneHome "Expected version is $expected"
}

if (($kernel_name.CompareTo($expected)) -ne 0) {

    $c="boot_results/" + $ourHost
    phoneHome "Failed $kernel_name $expected"

    remove-pssession $s

    exit 1
} else {
    phoneHome "Passed.  Let's go to Azure!!"

    $c="boot_results/" + $ourHost
    phoneHome "Success $kernel_name"

    remove-pssession $s

    exit 0
}

