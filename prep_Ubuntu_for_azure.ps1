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

echo "Getting rid of updatedns"
remove-item -force /etc/rc.d/rc.local
remove-item -force -recurse /root/dns

echo "Fixing sources"
(Get-Content /etc/apt/sources.list) -replace "[a-z][a-z].archive.ubuntu.com","azure.archive.ubuntu.com" | out-file -encoding ASCII -path /etc/apt/sources.list
apt-get update
apt-get dist-upgrade

#
#  Modify GRUB for Azure
#
#  Get the existing command line
#
echo "Fixing GRUB"
$grubLine='GRUB_CMDLINE_LINUX_DEFAULT="console=tty1 console=ttyS0,115200n8 earlyprintk=ttyS0,115200 rootdelay=300"'

#
#  And finally write it back to the file
#
(Get-Content /etc/default/grub) -replace 'GRUB_CMDLINE_LINUX_DEFAULT=.*',$grubLine | Set-Content -encoding ASCII /etc/default/grub

echo "Setting up new GRUB"
update-grub

echo "Fixing OMI"
get-content /etc/opt/omi/conf/omiserver.conf | /opt/omi/bin/omiconfigeditor httpsport -a 443 | set-content -encoding ASCII /etc/opt/omi/conf/omiserver.conf

echo "Allowing OMI port through the firewall"
ufw allow 443

echo "Installing Python and WAAgent"
apt-get update
apt-get install walinuxagent

setConfig "/etc/waagent.conf" "ResourceDisk.Format" "y" 
setConfig "/etc/waagent.conf" "ResourceDisk.Filesystem" "ext4" 
setConfig "/etc/waagent.conf" "ResourceDisk.MountPoint" "/mnt/resource" 
setConfig "/etc/waagent.conf" "ResourceDisk.EnableSwap" "y" 
setConfig "/etc/waagent.conf" "ResourceDisk.SwapSizeMB" "2048" 

echo "Deprovisioning..."
# waagent -force -deprovision
# exit

