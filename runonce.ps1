#!/usr/bin/powershell
#
#  Reused from the StackOverflow article.  Solution by Dennis Williamson
#
#  Place this file in /root/Framework_Scripts/
#  Create directory /root//runonce.d
#  Add the line "@reboot root /root/Framework_Scripts/runonce.ps1" to /etc/crontab
#
#  When there's a script you want to run at the next boot, put it in /root/runonce.d.
#
function callItIn($c, $m) {
    $output_path="c:\temp\$c"
    
    $m | out-file -Append $output_path
    return
}

function phoneHome($m) {
    invoke-command -session $s -ScriptBlock ${function:callItIn} -ArgumentList $c,$m
}

#
#  Give the machine 30 seconds to settle down
#
sleep 30

$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$pw=convertto-securestring -AsPlainText -force -string 'P@$$w0rd!'
$cred=new-object -typename system.management.automation.pscredential -argumentlist "mstest",$pw
$s=new-PSSession -computername lis-f1637.redmond.corp.microsoft.com -credential $cred -authentication Basic -SessionOption $o

#
#  What OS are we on?
#
$linuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData
# $c = $linuxInfo.ID
# $c=$c -replace '"',""
$ourHost=hostname
$c=$ourHost + "_RunOnce"

phoneHome "RunOnce starting up on machine $c"

#
#  Check for the runonce directory
#
if ((Test-Path /root/runonce.d) -eq 0) {
    echo "No runonce directory found"
    $LASTEXITCODE = 1
    exit $LASTERRORCODE
}

#
#  If there are entries, execute them....
#

$scriptsArray=@()

Get-ChildItem /root/runonce.d -exclude ran |
foreach-Object {
    $script=$_.Name

    echo "Found script $script"
    phoneHome "RunOnce has located $script in execution folder"

    $fullName='/root/runonce.d/ran/'+$script

    Move-Item -force $_ $fullName

    $scriptsArray+=$fullName
    phoneHome "Script has been copied to staging folder"

}

foreach ($script in $scriptsArray) {
    phoneHome "RunOnce initiating execution of script $script from staging folder"

    iex $script
    phoneHome "RunOnce execution of script $script complete"
}

remove-pssession $s
