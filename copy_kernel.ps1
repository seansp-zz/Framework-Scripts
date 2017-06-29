#!/usr/bin/powershell
#
#  Copy the latest kernel build from the secure share to the local directory,
#  then install it, set the default kernel, switch out this script for the
#  secondary boot replacement, and reboot the machine.
param (
    [Parameter(Mandatory=$false)] [string] $pkg_mount_point="Undefined",
    [Parameter(Mandatory=$false)] [string] $pkg_mount_source="Undefined",
    [Parameter(Mandatory=$false)] [string] $pkg_storageaccount="Undefined",
    [Parameter(Mandatory=$false)] [string] $pkg_container="Undefined",
    [Parameter(Mandatory=$false)] [string] $pkg_location="Undefined"
)

$global:isHyperV = $false
$global:o = New-PSSessionOption -SkipCACheck -SkipRevocationCheck -SkipCNCheck
$global:pw=convertto-securestring -AsPlainText -force -string 'P@$$w0rd!'
$global:cred=new-object -typename system.management.automation.pscredential -argumentlist "mstest",$global:pw
$global:session=$null

get-pssession | remove-pssession
$agents = pidof omiagent
foreach ($agent in $agents) {
    @(kill -9 $agent)
}
apt autoremove -y

function callItIn($c, $m) {
    $output_path="c:\temp\progress_logs\$c"

    $m | out-file -Append $output_path
    return
}

function phoneHome($m) {
echo $m
    if ($global:isHyperV -eq $true) {

        if ($global:session -eq $null) {
            echo "*** Restarting the PowerShell session!" | out-file -Append /opt/microsoft/borg_progress.log
            get-pssession | remove-pssession
            $global:session=new-PSSession -computername lis-f1637.redmond.corp.microsoft.com -credential $global:cred -authentication Basic -SessionOption $global:o
        }

        invoke-command -session $global:session -ScriptBlock ${function:callItIn} -ArgumentList $c,$m

        $m | out-file -Append /opt/microsoft/borg_progress.log
    } else {
        $m | out-file -Append /opt/microsoft/borg_progress.log
    }
}

function callVersionIn($f,$m) {
    $output_path=$f

    $m | out-file -Force $output_path
    return
}


function phoneVersionHome($m) {

    $outFile = "c:\temp\expected_version_deb"
    if (Test-Path /bin/rpm) {
        $outFile = "c:\temp\expected_version_centos"
    } 

    if ($global:isHyperV -eq $true) {
        if ($global:session -eq $null) {
             echo "*** Restarting (2) the PowerShell session!" | out-file -Append /opt/microsoft/borg_progress.log
             get-pssession | remove-pssession
            $global:session=new-PSSession -computername lis-f1637.redmond.corp.microsoft.com -credential $global:cred -authentication Basic -SessionOption $global:o
        }

        invoke-command -session $global:session -ScriptBlock ${function:callVersionIn} -ArgumentList $outFile,$m
    } else {
        $output_path="/root/expected_version"

        $m | out-file -Append $output_path
    }
}

if (Get-Item -ErrorAction SilentlyContinue -Path /opt/microsoft/borg_progress.log ) {
    Remove-Item /opt/microsoft/borg_progress.log
}

Stop-Transcript | out-null
Start-Transcript -path /root/borg_install_log -append

#
#  What OS are we on?
#
$linuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData
$c=hostname

$c | Out-File -FilePath /opt/microsoft/borg_progress.log
#
#  Start by cleaning out any existing downloads
#
$global:isHyperV=$true
$lookup=nslookup cdmbuildsna01.redmond.corp.microsoft.com
if ($? -eq $false) {
    $global:isHyperV = $false
    phoneHome "It looks like we're in Azure"
} else {
    phoneHome "It looks like we're in Hyper-V"
}

phoneHome "******************************************************************"
phoneHome "*        BORG DRONE $hostName starting conversion..."
phoneHome "******************************************************************"

if ($ENV:PATH -ne "") {
    $ENV:PATH=$ENV:PATH + ":/sbin:/bin:/usr/sbin:/usr/bin:/opt/omi/bin:/usr/local:/usr/sbin:/bin"
} else {
    $ENV:PATH="/sbin:/bin:/usr/sbin:/usr/bin:/opt/omi/bin:/usr/local:/usr/sbin:/bin"
}

echo "Search path is $ENV:PATH"
$foo=@(which chmod)
echo "Found it at $foo"
$bar=@(chmod 777 /opt/microsoft/borg_progress.log)
echo $bar
$zed=@(ls -laF /opt/microsoft/borg_progress.log)
echo $zed

phoneHome "Starting copy file scipt"
cd /root
$kernFolder="/root/latest_kernel"
If (Test-Path $kernFolder) {
    Remove-Item -Recurse -Force $kernFolder
}
new-item $kernFolder -type directory

if ($global:isHyperV -eq $true) {

    if ($pkg_mount_point -eq "Undefined") {
        $pkg_mount_point="/mnt/ostcnix"
        $pkg_mount_dir= $pkg_mount_point + "/latest"
    } else {
        $pkg_mount_dir=$pkg_mount_point
    }

    if ($pkg_mount_source -eq "Undefined") {
        $pkg_mount_source = "cdmbuildsna01.redmond.corp.microsoft.com:/OSTCNix/OSTCNix/Build_Drops/kernel_drops"
    }

    echo "Package mount point is $pkg_mount_point and Package mount dir is $pkg_mount_dir"
    echo "Package source is $pkg_mount_source"

    if ((Test-Path $pkg_mount_point) -eq $false) {
        echo "Creating the mount point"
        New-Item -ItemType Directory -Path $pkg_mount_point
    }

    echo "Checking for the mount directory..."
    if ((Test-Path $pkg_mount_dir) -eq $false) {
        echo "Target directory was not there.  Mounting"
        $mntRes = @(mount $pkg_mount_source $pkg_mount_point)
    }

    if ((Test-Path $pkg_mount_dir) -eq 0) {
        phoneHome "Latest directory $pkg_mount_dir was not on mount point $pkg_mount_point!  No kernel to install!"
        phoneHome "Mount was from $pkg_mount_source"
        $LASTEXITCODE = 1
        exit $LASTERRORCODE
    }

    #
    #  Copy the files
    #
    phoneHome "Copying the kernel from the drop share"
    cd /root/latest_kernel

    copy-Item -Path $pkg_mount_dir/* -Destination ./
} else {
    #
    #  If we can't mount the drop folder, maybe we can get the files from Azure
    #
    cd $kernFolder

    if ($pkg_storageaccount -eq "Undefined") {
        $pkg_storageaccount = "azuresmokestorageaccount"
    }

    if ($pkg_container -eq "Undefined") {
        $pkg_container = "latest-packages"
    }

    phoneHome "Copying the kernel from Azure blob storage"
    $fileListURIBase = "https://" + $pkg_storageaccount + ".blob.core.windows.net/" + $pkg_container
    $fileListURI = $fileListURIBase + "/file_list"
echo "Downloading file list from URI $fileListURI"
    Invoke-WebRequest -Uri $fileListURI -OutFile file_list

    $files=Get-Content file_list

    foreach ($file in $files) {
        $fileListURIBase = "https://" + $pkg_storageaccount + ".blob.core.windows.net/" + $pkg_container
        $fileName=$fileListURIBase + "/" + $file
        Invoke-WebRequest -Uri $fileName -OutFile $file
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
if (Test-Path /bin/rpm) {
    $kernel_name_cent=Get-ChildItem -Path /root/latest_kernel/kernel-[0-9].* -Exclude "*.src*"
    $kernelNameCent = $kernel_name_cent.Name.split("-")[1]
    phoneHome "CentOS Kernel name is $kernelNameCent"

    #
    #  Figure out the kernel version
    #
    $kernelVersionCent=$kernelNameCent

    #
    #  For some reason, the file is -, but the kernel is _
    #
    $kernelVersionCent=($kernelVersionCent -replace "_","-")
    phoneHome "Expected Kernel version is $kernelVersionCent"
    $kernelVersionCent | Out-File -Path "/root/expected_version"
    phoneVersionHome $kernelVersionCent
} else {
    $kernel_name_deb=Get-ChildItem -Path /root/latest_kernel/linux-image-[0-9].* -Exclude "*-dbg_*"
    $kernelNameDeb = $kernel_name_deb.Name.split("image-")[1]
    phoneHome "Debian Kernel name is $kernelNameDeb"

    #
    #  Figure out the kernel version
    #
    $kernelVersionDeb=($kernelNameDeb -split "_")[0]

    #
    #  For some reason, the file is -, but the kernel is _
    #
    $kernelVersionDeb=($kernelVersionDeb -replace "_","-")
    phoneHome "Expected Kernel version is $kernelVersionDeb"
    $kernelVersionDeb | Out-File -Path "/root/expected_version"
    phoneVersionHome $kernelVersionDeb
}

#
#  Do the right thing for the platform
#
cd $kernFolder
if (Test-Path /bin/rpm) {
    #
    #  rpm-based system
    #
    $kerneldevelName = Get-Childitem -Path /root/latest_kernel/kernel-devel-[0-9].*.rpm
    phoneHome "Kernel Devel Package name is $kerneldevelName"

    $kernelPackageName = Get-ChildItem -Path /root/latest_kernel/kernel-[0-9].*.rpm

    phoneHome "Making sure the firewall is configured"
    $foo=@(firewall-cmd --zone=public --add-port=443/tcp --permanent)
    $foo=@(systemctl stop firewalld)
    $foo=@(systemctl start firewalld)

    #
    #  Install the new kernel
    #
    phoneHome "Installing the rpm kernel devel package $kernelDevelName"
    @(rpm -ivh $kernelDevelName)

    phoneHome "Installing the rpm kernel package $kernelPackageName"
    @(rpm -ivh $kernelPackageName)

    #
    #  Now set the boot order to the first selection, so the new kernel comes up
    #
    phoneHome "Setting the reboot for selection 0"
    $foo = @(/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg)
    $foo = @(/sbin/grub2-set-default 0)
} else {
    #
    #  Figure out the kernel name
    #
    $debKernName=(get-childitem linux-image-*.deb -exclude "-dgb_")[0].Name
    phoneHome "Kernel Package name is $DebKernName"

    #
    #  Debian
    #
    $kernDevName=(get-childitem linux-image-*.deb -Exclude ".src.")[1].Name
    phoneHome "Kernel Devel Package name is $kernDevName"

    #
    #  Make sure it's up to date
    #
    Remove-Item -Path /var/lib/dpkg/lock
    
    @(apt-get install -f)
    @(apt autoremove)
    phoneHome "Getting the system current"
    while ($true) {
        phoneHome "Tyring apt-get now..."
        @(apt-get -y update)
        if ($? -ne $true) {
           phoneHome "Retyring getting the system current"
           sleep 1
        } else {
            phoneHome "Command was successful?"
            break
        }
    }

    phoneHome "Installing the DEB kernel devel package"
    while ($true) {
        phoneHome "Tyring dpkg(1) now..."
        @(dpkg -i $kernDevName)
        if ($? -ne $true) {
            phoneHome "Retyring installing the DEB devel package"
           sleep 1
        } else {
            phoneHome "Command was successful?"
            break
        }
    }

    phoneHome "Installing the DEB kernel package"
    while ($true) {
        phoneHome "Tyring dpkg(2) now..."
        @(dpkg -i $debKernName)
        if ($? -ne $true) {
            phoneHome "Retyring installing the DEB Kernel package"
           sleep 1
        } else {
            phoneHome "Command was successful?"
            break
        }
    }
    #
    #  Now set the boot order to the first selection, so the new kernel comes up
    #
    phoneHome "Setting the reboot for selection 0"
    @(grub-mkconfig -o /boot/grub/grub.cfg)
    @(grub-set-default 0)
}

#
#  Copy the post-reboot script to RunOnce
#
copy-Item -Path "/root/Framework-Scripts/report_kernel_version.ps1" -Destination "/root/runonce.d"

phoneHome "Rebooting now..."

if ($global:isHyperV -eq $true) {
    remove-pssession $global:session
}

Stop-Transcript

shutdown -r
