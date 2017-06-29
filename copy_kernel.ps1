#!powershell
#
#  Copy the latest kernel build from the secure share to the local directory,
#  then install it, set the default kernel, switch out this script for the
#  secondary boot replacement, and reboot the machine.
param (
    [Parameter(Mandatory=$false)] [string] $pkg_mount_point="",
    [Parameter(Mandatory=$false)] [string] $pkg_mount_source="",
    [Parameter(Mandatory=$false)] [string] $pkg_storageaccount="",
    [Parameter(Mandatory=$false)] [string] $pkg_container="",
    [Parameter(Mandatory=$false)] [string] $pkg_location=""
)

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

        $m | out-file -Append /opt/microsoft/borg_progress.log
    } else {
        $m | out-file -Append /opt/microsoft/borg_progress.log
    }
}

function callVersionIn($m) {
    $output_path="c:\temp\expected_version"
    
    $m | out-file -Force $output_path
    return
}


function phoneVersionHome($m) {
    if ($global:isHyperV -eq $true) {
        invoke-command -session $s -ScriptBlock ${function:callVersionIn} -ArgumentList $m
    } else {
        $output_path="/opt/microsoft/installed_kernel_version.log"

        $m | out-file -Append $output_path
    }
}

if (Get-Item -ErrorAction SilentlyContinue -Path /opt/microsoft/borg_progress.log ) {
    Remove-Item /opt/microsoft/borg_progress.log
}

Stop-Transcript | out-null
Start-Transcript -path /root/borg_install_log -append

$hostName=hostname  
$hostName | Out-File -FilePath /opt/microsoft/borg_progress.log
phoneHome "******************************************************************" 
phoneHome "*        BORG DRONE $hostName starting conversion..." 
phoneHome "******************************************************************"

if ($ENV:PATH -ne "") {
    $ENV:PATH=$ENV:PATH + ":/sbin:/bin:/usr/sbin:/usr/bin:/opt/omi/bin:/usr/local:/usr/sbin:/bin"
} else {
    $ENV:PATH="/sbin:/bin:/usr/sbin:/usr/bin:/opt/omi/bin:/usr/local:/usr/sbin:/bin"
}
phoneHome "Search path is $ENV:PATH"
/bin/chmod 777 /opt/microsoft/borg_progress.log

#
#  Now see if we can mount the drop folder
#
phoneHome "Checking for platform..."
$global:isHyperV=$true
$lookup=nslookup cdmbuildsna01.redmond.corp.microsoft.com
if ($? -eq $false) {
    $global:isHyperV = $false
    phoneHome "It looks like we're in Azure"
} else {
    phoneHome "It looks like we're in Hyper-V"
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
    if ($pkg_mount_dir -eq "") {
        $pkg_mount_point="/mnt/ostcnix"
        $pkg_mount_dir="$pkg_mount_point" + "/latest"
    } else {
        $pkg_mount_point="/mnt/ostcnix"
        $pkg_mount_dir=$pkg_mount_point
    }

    if ((Test-Path $pkg_mount_dir) -eq 0) {
        New-Item -ItemType Directory -Path $pkg_mount_dir
    }

    if ((Test-Path "$pkg_mount_point") -eq 0) {
        if ($pkg_mount_source -eq "") {
            $pkg_mount_source = "cdmbuildsna01.redmond.corp.microsoft.com:/OSTCNix/OSTCNix/Build_Drops/kernel_drops"
        }

        mount $pkg_mount_source $pkg_mount_point
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

    phoneHome "Copying the kernel from Azure blob storage"
    $fileListURIBase = "https://" + $pkg_storageaccount + ".blob.core.windows.net/" + $pkg_container
    $fileListURI = $fileListURIBase + "/file_list"
    Invoke-WebRequest -Uri $fileListURI -OutFile file_list

    $files=Get-Content file_list
    
    foreach ($file in $files) {
        $fileName=$fileListURIBase + "/" + $pkg_container + "/" + $file
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
    #  rpm-based system
    #
    $kernelDevelName=("kernel-devel-"+(($kernelName -split "-")[1]+"-")+($kernelName -split "-")[2])+".rpm"
    phoneHome "Kernel Devel Package name is $kerneldevelName" 
    $kernelPackageName=$kernelName+".rpm"

    phoneHome "Making sure the firewall is configured" 
    & "/bin/firewall-cmd --zone=public --add-port=443/tcp --permanent"
    & "/bin/systemctl stop firewalld"
    & "/bin/systemctl start firewalld"

    #
    #  Install the new kernel
    #
    phoneHome "Installing the rpm kernel devel package $kernelDevelName"
    & "/bin/rpm -ivh $kernelDevelName"
    phoneHome "Installing the rpm kernel package $kernelPackageName"
    & "/bin/rpm -ivh $kernelPackageName"

    #
    #  Now set the boot order to the first selection, so the new kernel comes up
    #
    phoneHome "Setting the reboot for selection 0"
    & "/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg"
    & "/sbin/grub2-set-default 0"
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
    & "/usr/bin/apt-get -y update"

    phoneHome "Installing the DEB kernel devel package" 
    & "/usr/bin/dpkg -i $kernDevName"

    phoneHome "Installing the DEB kernel package" 
    & "/usr/bin/dpkg -i $debKernName"

    #
    #  Now set the boot order to the first selection, so the new kernel comes up
    #
    phoneHome "Setting the reboot for selection 0"
    & "/usr/sbin/grub-mkconfig -o /boot/grub/grub.cfg"
    & "/usr/sbin/grub-set-default 0"
}

#
#  Copy the post-reboot script to RunOnce
#
copy-Item -Path "/root/Framework-Scripts/report_kernel_version.ps1" -Destination "/root/runonce.d"

phoneHome "Rebooting now..."

if ($global:isHyperV -eq $true) {
    remove-pssession $s
}

Stop-Transcript

shutdown -r
