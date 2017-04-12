#!/usr/bin/powershell
#
#  Copy the latest kernel build from the secure share to the local directory,
#  then install it, set the default kernel, switch out this script for the
#  secondary boot replacement, and reboot the machine.
#
#  Start by cleaning out any existing downloads
#
echo "Starting copy file scipt" 
cd /tmp
$kernFolder="./latest_kernel"
If (Test-Path $kernFolder) {
    Remove-Item -Recurse -Force $kernFolder
}
new-item $kernFolder -type directory

#
#  Now see if we can mount the drop folder
#
if ((Test-Path "/mnt/ostcnix") -eq 0) {
    mount /mnt/ostcnix
}

if ((Test-Path "/mnt/ostcnix/latest") -eq 0) {
    echo "Latest directory was not on mount point!  No kernel to install!" 
    $LASTEXITCODE = 1
    exit $LASTERRORCODE
}

#
#  Copy the files
#
echo "Copying the kernel from the drop share" 
cd /tmp/latest_kernel
copy-Item -Path "/mnt/ostcnix/latest/*" -Destination "./"

#
#  What OS are we on?
#
$linuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData
$linuxOs = $linuxInfo.ID
echo "Operating system is "$linuxOs

#
#  Figure out the kernel name
#
$rpmName=(get-childitem kernel-[0-9]*.rpm).name
$kernelName=($rpmName -split ".rpm")[0]
echo "Kernel name is $kernelName" 

$kernelDevelName="kernel-devel-"+(($kernelName -split "-")[1]+"-")+($kernelName -split "-")[2]
echo "Kernel Devel Package name is $kerneldevelName" 

$kernelHeadersName="kernel-headers-"+(($kernelName -split "-")[1]+"-")+($kernelName -split "-")[2]
echo "Kernel Headers Package name is $kernelHeadersName" 

#
#  Install the new kernel
#
if ($linuxOs -eq "centos") {
    echo "Installing the RPM kernel devel package" 
    rpm -ivh $kernelDevelName".rpm"
    echo "Installing the RPM kernel package" 
    rpm -ivh $kernelName".rpm"
    # echo "Installing the RPM kernel headers package" 
    # rpm -ivh $kernelHeadersName".rpm"
} else {
    echo "Installing the RPM kernel devel package" 
    rpm -ivh $kernelDevelName".rpm"
    echo "Installing the RPM kernel package" 
    rpm -ivh $kernelName".rpm"
    # echo "Installing the RPM kernel headers package" 
    # rpm -ivh $kernelHeadersName".rpm"
}

#
#  Now set the boot order to the first selection, so the new kernel comes up
#
echo "Setting the reboot for selection 0"
grub2-reboot 0

echo "Rebooting now..."
reboot
