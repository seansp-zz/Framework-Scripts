#!/usr/bin/powershell
#
#  Prepare a machine for Azure
#
#  Function setConfig grabbed from an answer on StackOverflow.
#      http://stackoverflow.com/questions/15662799/powershell-function-to-replace-or-add-lines-in-text-files
#
function setConfig( $file, $key, $value ) {
    $content = Get-Content $file
    if ( $content -match "^$key\s*=" ) {
        $content -replace "^$key\s*=.*", "$key=$value" |
        Set-Content -encoding UTF8 $file     
    } else {
        Add-Content -encoding UTF8 $file "$key=$value"
    }
}

function callItIn($c, $m) {
    $output_path="c:\temp\$c"

    $m | out-file -Append $output_path
    return
}

function phoneHome($m) {

    invoke-command -session $s -ScriptBlock ${function:callItIn} -ArgumentList $c,$m
}

$linuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData
$c = $linuxInfo.ID
$c=$c -replace '"',""
$c=$c+"-prep_for_azure"

phonehome "Getting rid of updatedns"
remove-item -force /etc/rc.d/rc.local
remove-item -force -recurse /root/dns

phonehome "Fixing sources"
(Get-Content /etc/apt/sources.list) -replace "[a-z][a-z].archive.ubuntu.com","azure.archive.ubuntu.com" | out-file -encoding ASCII -path /etc/apt/sources.list
apt-get -y update
apt-get -y dist-upgrade

#
#  Modify GRUB for Azure
#
#  Get the existing command line
#
phonehome "Fixing GRUB"
$grubLine='GRUB_CMDLINE_LINUX_DEFAULT="console=tty1 console=ttyS0,115200n8 earlyprintk=ttyS0,115200 rootdelay=300"'

#
#  And finally write it back to the file
#
(Get-Content /etc/default/grub) -replace 'GRUB_CMDLINE_LINUX_DEFAULT=.*',$grubLine | Set-Content -encoding ASCII /etc/default/grub

phonehome "Setting up new GRUB"
update-grub

phonehome "Fixing OMI"
get-content /etc/opt/omi/conf/omiserver.conf | /opt/omi/bin/omiconfigeditor httpsport -a 443 | set-content -encoding ASCII /etc/opt/omi/conf/omiserver.conf

phonehome "Allowing OMI port through the firewall"
ufw allow 443

phonehome "Installing Python and WAAgent"
apt-get -y update
apt-get -y install walinuxagent

setConfig "/etc/waagent.conf" "ResourceDisk.Format" "y" 
setConfig "/etc/waagent.conf" "ResourceDisk.Filesystem" "ext4" 
setConfig "/etc/waagent.conf" "ResourceDisk.MountPoint" "/mnt/resource" 
setConfig "/etc/waagent.conf" "ResourceDisk.EnableSwap" "y" 
setConfig "/etc/waagent.conf" "ResourceDisk.SwapSizeMB" "2048" 

phonehome "Deprovisioning..."
waagent -force -deprovision
shutdown now

