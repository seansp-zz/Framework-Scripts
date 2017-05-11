#!/usr/bin/powershell
#
#  Reused from the StackOverflow article.  Solution by Dennis Williamson
#
#  Place this file in /usr/local/bin
#  Create directory /etc/local/runonce.d
#  Add the line "@reboot root /usr/local/bin/runonce.ps1" to /etc/crontab
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

$pw=convertto-securestring -AsPlainText -force -string 'Pa$$w0rd!'
$cred=new-object -typename system.management.automation.pscredential -argumentlist "psRemote",$pw
$s=new-PSSession -computername mslk-boot-test-host.redmond.corp.microsoft.com -credential $cred -authentication Basic

#
#  What OS are we on?
#
$linuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData
$c = $linuxInfo.ID
$c=$c -replace '"',""

phoneHome "RunOnce starting up on machine $c"

#
#  Check for the runonce directory
#
if ((Test-Path /root/runonce.d) -eq 0) {
    echo "No runonce directory found"
    $LASTEXITCODE = 1
    exit $LASTERRORCODE
}

/bin/ls -laF /root/runonce.d | /usr/bin/tee /tmp/FUO

#
#  If there are entries, execute them....
#

Get-ChildItem /root/runonce.d -exclude ran |
foreach-Object {
    $script=$_.Name

    echo "Found script $script"
    phoneHome "RunOnce found script $script"
    
    $fullName='/root/runonce.d/ran/'+$script

    Move-Item -force $_ $fullName

    echo "Running the script..."
    phoneHome "RunOnce initiating execution of script $fullName"

    iex $fullName
    phoneHome "RunOnce execution of script $fullName complete"
}

remove-pssession $s
