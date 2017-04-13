#!/usr/bin/powershell
#
#  Reused from the StackOverflow article.  Solution by Dennis Williamson
#
#  Place this file in /usr/local/bin
#  Create directory /etc/local/runonce.d
#  Add the line "@reboot root /usr/local/bin/runonce.ps1" to /etc/crontab
#
#  When there's a script you want to run at the next boot, put it in /etc/local/runonce.d.
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

    invoke-command -Credential $cred -ComputerName MSLK-BOOT-TEST-HOST.redmond.corp.microsoft.com -Authentication Basic -ScriptBlock ${function:callItIn} -ArgumentList $c,$m
}

#
#  Check for the runonce directory
#
if ((Test-Path "/etc/local/runonce.d") -eq 0) {
    echo "No runonce directory found"
    $LASTEXITCODE = 1
    exit $LASTERRORCODE
}

#
#  If there are entries, execute them....
#
Get-ChildItem "/etc/local/runonce.d" -exclude "ran" |
foreach-Object {
    echo "Found script $_"
    phoneHome "RunOnce found script $_"

    $movePath=Join-Path -Path $_.Directory -ChildPath "ran"
    echo "Move path is "$movePath

    $fileName=$_.Name
    $fullName="$($movePath)/$($_.Name)"


    echo "Moving the script so we don't execute again next time"
    logger -t runonce -p local3.info "$fileName"
    Move-Item $_ $movePath -force

    echo "Running the script..."
    phoneHome "RunOnce initiating execution of script $fileName"
    iex $fullName
    phoneHome "RunOnce execution of script $fileName complete"
}
