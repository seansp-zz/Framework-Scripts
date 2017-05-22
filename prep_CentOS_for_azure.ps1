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

echo "setting network script"
setConfig "/etc/sysconfig/network" "NETWORKING" "yes" 
setConfig "/etc/sysconfig/network" "HOSTNAME" "localhost.localdomain" 

echo "Removing old ifcfg script"
remove-item -force /etc/sysconfig/network-scripts/ifcfg-eth0

echo "setting up new ifcfg script"
echo '
DEVICE=eth0
ONBOOT=yes
BOOTPROTO=dhcp
TYPE=Ethernet 
USERCTL=no
PEERDNS=yes
IPV6INIT=no
NM_CONTROLLED=no' | set-content -encoding UTF8 /etc/sysconfig/network-scripts/ifcfg-eth0

echo "Linking the rules"
ln -s /dev/null /etc/udev/rules.d/75-persistent-net-generator.rules

#
#  Modify GRUB for Azure
#
#  Get the existing command line
#
echo "Fixing GRUB"
$grubLine=(sls  'GRUB_CMDLINE_LINUX' /etc/default/grub | select -exp line)

#
#  Take out all the bad stuff
#
$grubLine=$grubLine -replace 'rhgb','' `
                    -replace 'quiet','' `
                    -replace 'crashkernel=auto','' `
                    -replace 'rootdelay=.*','' `
                    -replace 'console=.*','' `
                    -replace 'earlyprintk=.*','' `
                    -replace 'net.iframes=.*',''

#
#  Now add in the new stuff
#
$grubLine=$grubLine -replace '"$',' rootdelay=300 console=ttyS0 earlyprintk=ttyS0 net.ifnames=0"'

#
#  And finally write it back to the file
#
(Get-Content /etc/default/grub) -replace 'GRUB_CMDLINE_LINUX=.*',$grubLine | Set-Content -encoding UTF8 /etc/default/grub

echo "Setting up new GRUB"
grub2-mkconfig -o /boot/grub2/grub.cfg

echo "Installing Python and WAAgent"
curl -o /etc/yum.repos.d/openlogic.repo https://raw.githubusercontent.com/szarkos/AzureBuildCentOS/master/config/azure/OpenLogic.repo
curl -o /etc/pki/rpm-gpg/OpenLogic-GPG-KEY https://raw.githubusercontent.com/szarkos/AzureBuildCentOS/master/config/OpenLogic-GPG-KEY

yum install -y python-pyasn1 WALinuxAgent
systemctl enable waagent

setConfig "/etc/waagent.conf" "ResourceDisk.Format" "y" 
setConfig "/etc/waagent.conf" "ResourceDisk.Filesystem" "ext4" 
setConfig "/etc/waagent.conf" "ResourceDisk.MountPoint" "/mnt/resource" 
setConfig "/etc/waagent.conf" "ResourceDisk.EnableSwap" "y" 
setConfig "/etc/waagent.conf" "ResourceDisk.SwapSizeMB" "2048" 

echo "Deprovisioning..."
# waagent -force -deprovision
# exit

