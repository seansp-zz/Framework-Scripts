#!/usr/bin/powershell
#
#  Copy the latest kernel build from the secure share to the local directory,
#  then install it, set the default kernel, switch out this script for the
#  secondary boot replacement, and reboot the machine.
function callItIn($c, $m) {
    $output_path="c:\temp\progress_logs\$c"
    
    $m | out-file -Append $output_path
    return
}

$global:isHyperV = $false

function phoneHome($m) {
    if ($global:isHyperV -eq $true) {
        invoke-command -session $s -ScriptBlock ${function:callItIn} -ArgumentList $c,$m

        if ($? -eq $false)
        {
            #
            #  Error on ps.  Try reconnecting.
            #
            Exit-PSSession $s
            $o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
            $pw=convertto-securestring -AsPlainText -force -string 'P@$$w0rd!'
            $cred=new-object -typename system.management.automation.pscredential -argumentlist "mstest",$pw
            $s=new-PSSession -computername lis-f1637.redmond.corp.microsoft.com -credential $cred -authentication Basic -SessionOption $o
        }
    } else {
        $output_path="/opt/microsoft/borg_progress.log"

        $m | out-file -Append $output_path
    }
}

function callVersionIn($m) {
    $output_path="c:\temp\expected_version"
    
    $m | out-file -Force $output_path
    return
}


function phoneVersionHome($m) {
    invoke-command -session $s -ScriptBlock ${function:callVersionIn} -ArgumentList $m
}

if (Get-Item -Path /root/borg_progress.log) {
    Remove-Item /root/borg_progress.log
    $hostName=hostname
    echo "******************************************************************" | Out-File -FilePath /root/borg_progress.log
    echo "*        BORG DRONE $hostName starting conversion..." | Out-File -append -FilePath /root/borg_progress.log
    echo "******************************************************************" | Out-File -Append -FilePath /root/borg_progress.log
    chmod 777 /root/borg_progress.log
}


#
#  Now see if we can mount the drop folder
#
echo "Checking for platform..."
$global:isHyperV=$true
$lookup=nslookup cdmbuildsna01.redmond.corp.microsoft.com
if ($? -eq $false) {
    $global:isHyperV = $false
    echo "It looks like we're in Azure"
} else {
    echo "It looks like we're in Hyper-V"
}

#
#  Start by cleaning out any existing downloads
#
$o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$pw=convertto-securestring -AsPlainText -force -string 'P@$$w0rd!'
$cred=new-object -typename system.management.automation.pscredential -argumentlist "mstest",$pw
if ($global:isHyperV -eq $true) {
    $s=new-PSSession -computername lis-f1637.redmond.corp.microsoft.com -credential $cred -authentication Basic -SessionOption $o
}

#
#  What OS are we on?
#
$linuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData
# $c = $linuxInfo.ID
# $c = $c + $linuxInfo.VERSION_ID
# $c=$c -replace '"',""
# $c=$c -replace '\.',""
# $c="progress_logs/$c"
$c=hostname

phoneHome "Starting copy file scipt" 
cd /root
$kernFolder="/root/latest_kernel"
If (Test-Path $kernFolder) {
    Remove-Item -Recurse -Force $kernFolder
}
new-item $kernFolder -type directory

if ($global:isHyperV -eq $true) {
    if ((Test-Path "/mnt/ostcnix") -eq 0) {
        New-Item -ItemType Directory -Path /mnt/ostcnix
    }

    if ((Test-Path "/mnt/ostcnix/latest") -eq 0) {
        mount cdmbuildsna01.redmond.corp.microsoft.com:/OSTCNix/OSTCNix/Build_Drops/kernel_drops /mnt/ostcnix
    }

    if ((Test-Path "/mnt/ostcnix/latest") -eq 0) {
        phoneHome "Latest directory was not on mount point!  No kernel to install!" 
        $LASTEXITCODE = 1
        exit $LASTERRORCODE
    }

    #
    #  Copy the files
    #
    phoneHome "Copying the kernel from the drop share" 
    cd /root/latest_kernel
    copy-Item -Path "/mnt/ostcnix/latest/*" -Destination $kernFolder
} else {
#
#  If we can't mount the drop folder, maybe we can get the files from Azure
#
    cd $kernFolder

    phoneHome "Copying the kernel from Azure blob storage"
    wget -m https://azuresmokestorageaccount.blob.core.windows.net/latest-packages/file_list -O file_list

    $files=Get-Content file_list
    
    foreach ($file in $files) {
        $fileName="https://azuresmokestorageaccount.blob.core.windows.net/latest-packages/" + $file
        wget -m $fileName -O $file
    }
}

#
#  What OS are we on?
#
$linuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData
$linuxOs = $linuxInfo.ID
phoneHome "Operating system is $linuxOs"
$linuxVers = $linuxInfo.VERSION_ID
phoneHome "Operating system version is $linuxVersion"

#
#  Remove the old sentinel file
#
Remove-Item -Force "/root/expected_version"

#
#  Figure out the kernel name
#
$rpmName=(get-childitem kernel-[0-9]*.rpm).name
$kernelName=($rpmName -split ".rpm")[0]
phoneHome "Kernel name is $kernelName" 

#
#  Figure out the kernel version
#
$kernelVersion=($kernelName -split "-")[1]

#
#  For some reason, the file is -, but the kernel is _
#
$kernelVersion=($kernelVersion -replace "_","-")
phoneHome "Expected Kernel version is $kernelVersion" 
$kernelVersion | Out-File -Path "/root/expected_version"
phoneVersionHome $kernelVersion

#
#  Do the right thing for the platform
#
cd $kernFolder
If (Test-Path /bin/rpm) {
    #
    #  RPM-based system
    #
    $kernelDevelName=("kernel-devel-"+(($kernelName -split "-")[1]+"-")+($kernelName -split "-")[2])+".rpm"
    phoneHome "Kernel Devel Package name is $kerneldevelName" 
    $kernelPackageName=$kernelName+".rpm"

    phoneHome "Making sure the firewall is configured" 
    firewall-cmd --zone=public --add-port=443/tcp --permanent
    systemctl stop firewalld
    systemctl start firewalld

    #
    #  Install the new kernel
    #
    phoneHome "Installing the RPM kernel devel package $kernelDevelName"
    rpm -ivh $kernelDevelName
    phoneHome "Installing the RPM kernel package $kernelPackageName"
    rpm -ivh $kernelPackageName

    #
    #  Now set the boot order to the first selection, so the new kernel comes up
    #
    phoneHome "Setting the reboot for selection 0"
    grub2-mkconfig -o /boot/grub2/grub.cfg
    grub2-set-default 0
} else {
    #
    #  Figure out the kernel name
    #
    $debKernName=(get-childitem linux-image-*.deb)[0].Name
    phoneHome "Kernel Package name is $DebKernName" 

    #
    #  Debian
    #
    $kernDevName=(get-childitem linux-image-*.deb)[1].Name
    phoneHome "Kernel Devel Package name is $kernDevName" 

    #
    #  Make sure it's up to date
    #
    phoneHome "Getting the system current" 
    apt-get -y update

    phoneHome "Installing the DEB kernel devel package" 
    dpkg -i $kernDevName

    phoneHome "Installing the DEB kernel package" 
    dpkg -i $debKernName

    #
    #  Now set the boot order to the first selection, so the new kernel comes up
    #
    phoneHome "Setting the reboot for selection 0"
    grub-mkconfig -o /boot/grub/grub.cfg
    grub-set-default 0
}

#
#  Copy the post-reboot script to RunOnce
#
copy-Item -Path "/root/Framework-Scripts/report_kernel_version.ps1" -Destination "/root/runonce.d"

phoneHome "Rebooting now..."

remove-pssession $s

shutdown -r
