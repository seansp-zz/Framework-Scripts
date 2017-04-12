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
    echo "Found script $_.Name"
    $movePath=Join-Path -Path $_.Directory -ChildPath "ran"
    echo "Move path is "$movePath

    $fileName=$_.Name
    echo "File name is "$fileName

    $fullName="$($movePath)/$($_.Name)"
    echo "Full name is "$fullName

    echo "Moving the script so we don't execute again next time"
    logger -t runonce -p local3.info "$fileName"
    Move-Item $_ $movePath -force

    echo "Running the script..."
    iex $fullName
}
