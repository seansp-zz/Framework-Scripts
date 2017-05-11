#!/usr/bin/powershell
#
#  Prepare a machine for Azure
#
(Get-Content /etc/sysconfig/network) -replace 'HOSTNAME=.*','HOSTNAME=localhost.localdomain' -replace 'NETWORKING=no','NETWORKING=yes' | Set-Content /etc/sysconfig/net

cd /etc/sysconfig/network-scripts

(Get-Content /etc/sysconfig/network-scripts/ifcfg-eth0) -replace 'DEVICE=.*','DEVICE=eth0' `
							-replace 'ONBOOT=.*','ONBOOT=yes' `
							-replace 'BOOTPROTO=.*','BOOTPROTO=dhcp' `
							-replace 'TYPE=.*','TYPE=Ethernet' `
							-replace 'USERCTL=.*','USERCTL=no' `
							-replace 'PEERDNS=.*','PEERDNS=yes' `
							-replace 'IPV6INIT=.*','IPV6INIT=no' `
							-replace 'NM_CONTROLLED=.*','NM_CONTROLLED=no' `
		| Set-Content /etc/sysconfig/network-scripts/ifcfg-eth0


ln -s /dev/null /etc/udev/rules.d/75-persistent-net-generator.rules

#
#  Modify GRUB for Azure
#
#  Get the existing command line
$grubLine=(sls  'GRUB_CMDLINE_LINUX' /etc/default/grub | select -exp line)

#
#  Take out all the bad stuff
$grubLine=$grubLine -replace 'rhgb','' -replace 'quiet','' -replace 'crashkernel=auto','' -replace 'rootdelay=.*','' -replace 'console=.*','' -replace 'earlyprintk=.*','' -replace 'net.iframes=.*',''

#
#  Now add in the new stuff
$grubLine=$grubLine -replace '"$',' rootdelay=300 console=ttyS0 earlyprintk=ttyS0 net.ifnames=0"'

#
#  And finally write it back to the file
(Get-Content /etc/default/grub) -replace 'GRUB_CMDLINE_LINUX=.*',$grubLine | Set-Content /etc/default/grub

grub2-mkconfig -o /boot/grub2/grub.cfg

yum install -y python-pyasn1 WALinuxAgent
systemctl enable waagent

(Get-Content /etc/waagent.conf) -replace 'ResourceDisk.Format=.*','ResourceDisk.Format=y' `
				-replace 'ResourceDisk.Filesystem=.*','ResourceDisk.Filesystem=ext4' `
				-replace 'ResourceDisk.MountPoint=.*','ResourceDisk.MountPoint=/mnt/resource' `
				-replace 'ResourceDisk.EnableSwap=.*','ResourceDisk.EnableSwap=y' `
				-replace 'ResourceDisk.SwapSizeMB=.*','ResourceDisk.SwapSizeMB=2048' `
		| Set-Content /etc/waagent.conf



waagent -force -deprovision
exit

