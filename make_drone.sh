#!/bin/bash
#
#  Script to take a VM template and make it our own
#
#  Author:  John W. Fawcett, Principal Software Development Engineer, Microsoft
#

#
#  Load our secrets.sh
#
source /tmp/secrets.sh

#
#  Find out what kind of system we're on
#
set -e

if [ -f /usr/bin/dpkg ]
  then
    echo "This is a dpkg machine"
    export is_rpm=0
else
    echo "This is an RPM-based machine"
    export is_rpm=1
fi

#
#  Do the setup for that system
#
if [ $is_rpm == 0 ]
  then
    echo "DEB-based system"
    echo "Precursors."

apt-get -y update
apt-get -y install wget
apt-get -y install iperf
apt-get -y install bind9
apt-get install build-essential software-properties-common -y
apt-get -y install python python-pyasn1 python-argparse python-crypto python-paramiko
export DEBIAN_FRONTEND=noninteractive
apt-get -y install mysql-server
apt-get -y install mysql-client
    
    #
    #  Add the test user
    #

    user_exists=`grep $TEST_USER_ACCOUNT_NAME /etc/passwd`
    if [ -z "${user_exists}" ]; then
        useradd -d /home/mstest -s /bin/bash -G sudo -m $TEST_USER_ACCOUNT_NAME -p $TEST_USER_ACCOUNT_PASS
        passwd mstest << PASSWD_END
$TEST_USER_ACCOUNT_PASS
$TEST_USER_ACCOUNT_PASS
PASSWD_END
    fi

cp /etc/apt/sources.list /etc/apt/sources.list.orig
cat << NEW_SOURCES > /etc/apt/sources.list.orig
deb  http://deb.debian.org/debian stretch main
deb-src  http://deb.debian.org/debian stretch main

deb  http://deb.debian.org/debian stretch-updates main
deb-src  http://deb.debian.org/debian stretch-updates main

deb http://security.debian.org/ stretch/updates main
deb-src http://security.debian.org/ stretch/updates main
NEW_SOURCES
    #
    #  Make sure things are consistent
    dpkg --configure -a
    apt --fix-broken -y install
    apt-get -y update
    apt-get install -y curl
    apt-get install -y dnsutils
    apt-get install -y apt-transport-https

    wget http://ftp.us.debian.org/debian/pool/main/o/openssl1.0/libssl1.0.2_1.0.2l-2_amd64.deb
    dpkg -i ./libssl1.0.2_1.0.2l-2_amd64.deb

    #
    #  Set up the repos to look at and update
    dpkg -l linux-{image,headers}-* | awk '/^ii/{print $2}' | egrep '[0-9]+\.[0-9]+\.[0-9]+' | grep -v $(uname -r | cut -d- -f-2) | xargs sudo apt-get -y purge
    curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
    curl https://packages.microsoft.com/config/ubuntu/14.04/prod.list | tee /etc/apt/sources.list.d/microsoft.list
    apt-get -y update

    #
    #  Install PowerShell.  Right now, we have to manually install a downlevel version, but we install the current one
    #  first so all the dependancies are satisfied.
    # apt-get install -y powershell
    #
    #  This package is in a torn state
    wget http://launchpadlibrarian.net/201330288/libicu52_52.1-8_amd64.deb
    dpkg -i libicu52_52.1-8_amd64.deb

    #
    #  Install and remove PS
    apt-get install -y powershell

    #
    #  Download and install the beta 2 version
    export download_1404="https://github.com/PowerSahell/PowerShell/releases/download/v6.0.0-beta.2/powershell_6.0.0-beta.2-1ubuntu1.14.04.1_amd64.deb"
    export download_1604="https://github.com/PowerShell/PowerShell/releases/download/v6.0.0-beta.2/powershell_6.0.0-beta.2-1ubuntu1.16.04.1_amd64.deb"
    wget $download_1604

    export pkg_name=`echo $download_1604 | sed -e s/.*powershell/powershell/`
    dpkg -r powershell
    wget http://archive.ubuntu.com/ubuntu/pool/main/i/icu/libicu55_55.1-7_amd64.deb
    dpkg -i libicu55_55.1-7_amd64.deb
    dpkg -i $pkg_name

    #
    #  Install OMI and PSRP
    apt-get install -y omi
    apt-get install -y omi-psrp-server

    #
    #  Install git and clone our repo
    cd
    apt-get install -y git

    framework_scripts_path="/root/Framework-Scripts"
    if ! [ -d $framework_scripts_path ]; then
        git clone https://github.com/FawcettJohnW/Framework-Scripts.git $framework_scripts_path
    fi
    cp /tmp/secrets.sh $framework_scripts_path/secrets.sh
    cp /tmp/secrets.ps1 $framework_scripts_path/secrets.ps1

    #
    #  Need NFS
    apt-get install -y nfs-common

    #
    #  Enable the HTTPS port and restart OMI
    sed -e s/"httpsport=0"/"httpsport=0,443"/ < /etc/opt/omi/conf/omiserver.conf > /tmp/x
    /bin//cp /tmp/x /etc/opt/omi/conf/omiserver.conf
    /opt/omi/bin/omiserver -s
    /opt/omi/bin/omiserver -d

    #
    #  Allow basic auth and restart sshd
    sed -e s/"PasswordAuthentication no"/"PasswordAuthentication yes"/ < /etc/ssh/sshd_config > /tmp/x
    /bin/cp /tmp/x /etc/ssh/sshd_conf
    service ssh restart
   
    #
    #  Set up runonce and copy in the right script
    if ! [ -d "runonce.d" ]; then
        mkdir runonce.d runonce.d/ran
    fi
## Unhooking the runonce.d so that we can place other things there in the future.
## to use, simply connect in and copy as shown below.
#    cp Framework-Scripts/update_and_copy.ps1 runonce.d/
    
    #
    #  Tell cron to run the runonce at reboot
#    echo "@reboot root /root/Framework-Scripts/runonce.ps1" >> /etc/crontab
    apt-get install -y ufw
    ufw allow 443
    ufw allow 5986
else
    echo "RPM-based system"
    echo "User name is $REDHAT_SUBSCRIPTION_ID"
    echo "PW is $REDHAT_SUBSCRIPTION_PW"
subscription-manager register --username $REDHAT_SUBSCRIPTION_ID --password $REDHAT_SUBSCRIPTION_PW --auto-attach

    echo "Precursors"
yum -y install wget
rpm -Uvh http://linux.mirrors.es.net/fedora-epel/7/x86_64/i/iperf-2.0.8-1.el7.x86_64.rpm
yum -y localinstall https://dev.mysql.com/get/mysql57-community-release-el7-9.noarch.rpm
yum -y install mysql-community-server
yum -y groupinstall "Development Tools"
yum -y install bind bind-utils
yum -y install python python-pyasn1
yum -y install python-argparse
yum -y install python-crypto
yum -y install python-paramiko

    #
    #  Make sure we have the tools we need
    yum install -y yum-utils
    yum install -y bind-utils

    #
    #  Clean up disk space
    package-cleanup --oldkernels --count=2

    #
    #  Add the test user
    useradd -d /home/$TEST_USER_ACCOUNT_NAME -s /bin/bash -G wheel -m $TEST_USER_ACCOUNT_NAME -p $TEST_USER_ACCOUNT_PASS 
    passwd $TEST_USER_ACCOUNT_NAME << PASSWD_END
$TEST_USER_ACCOUNT_PASS
$TEST_USER_ACCOUNT_PASS
PASSWD_END

    #
    #  Set up our repo and update
    curl https://packages.microsoft.com/config/rhel/7/prod.repo | sudo tee /etc/yum.repos.d/microsoft.repo
    yum update -y

    #
    #  See above about PowerSHell
    # yum install -y powershell
    yum install -y powershell
    yum erase -y powershell
    export download_normal="https://github.com/PowerShell/PowerShell/releases/download/v6.0.0-beta.2/powershell-6.0.0_beta.2-1.el7.x86_64.rpm"
    export doenload_suse="https://github.com/PowerShell/PowerShell/releases/download/v6.0.0-beta.2/powershell-6.0.0_beta.2-1.suse.42.1.x86_64.rpm"
    wget $download_normal
    rpm -i $download_normal

    #
    #  OMI and PSRP
    yum install -y omi
    yum install -y omi-psrp-server

    #
    #  Git and sync
    yum install -y git
    cd
    framework_scripts_path="/root/Framework-Scripts"
    if ! [ -d $framework_scripts_path ]; then
        git clone https://github.com/FawcettJohnW/Framework-Scripts.git $framework_scripts_path
    fi
    cp /tmp/secrets.sh $framework_scripts_path/secrets.sh
    cp /tmp/secrets.ps1 $framework_scripts_path/secrets.ps1

    #
    #  Need NFS
    yum install -y nfs-utils

    #
    #  Set up HTTPS and restart OMI
    sed -e s/"httpsport=0"/"httpsport=0,443"/ < /etc/opt/omi/conf/omiserver.conf > /tmp/x
    /bin/cp /tmp/x /etc/opt/omi/conf/omiserver.conf
    /opt/omi/bin/omiserver -s
    /opt/omi/bin/omiserver -d

    #
    #  Allow basic auth and restart sshd
    sed -e s/"PasswordAuthentication no"/"PasswordAuthentication yes"/ < /etc/ssh/sshd_config > /tmp/x
    /bin/cp /tmp/x /etc/ssh/sshd_conf
    systemctl stop sshd
    systemctl start sshd
    
    #
    #  Set up runonce
    mkdir runonce.d runonce.d/ran

## Unhooking the runonce.d so that we can place other things there in the future.
## to use, simply connect in and copy as shown below.
    #
    #    cp Framework-Scripts/update_and_copy.ps1 runonce.d/
    #
    #
    #  Tell cron to run the runonce at reboot
    echo "@reboot root /root/Framework-Scripts/runonce.ps1" >> /etc/crontab

    #
    #  Make sure 443 is allowed through the firewall
    firewall-cmd --zone=public --add-port=443/tcp --permanent
    systemctl stop firewalld
    systemctl start firewalld
    /opt/omi/bin/omiserver -d
fi

if [ -f /etc/motd ] 
  then
    mv /etc/motd /etc/motd_before_ms_kernel
fi

cat << "MOTD_EOF" > /etc/motd
*************************************************************************************

    WARNING   WARNING   WARNING   WARNING   WARNING   WARNING   WARNING   WARNING
    
      THIS IS AN EXPERIMENTAL COMPUTER.  IT IS NOT INTENDED FOR PRODUCTION USE


                 Microsoft Authorized Employees and Partners ONLY!

                   Please wave your badge in front of the screen

     If you are authorized to use this machine, we welcome you and invite your
   feedback through the established channels.  If you're not authorized, please
   don't tell anybody about this.  It really annoys the bosses when things like
   that happen.


   Welcome to the Twilight Zone.                                      Let's Rock.
*************************************************************************************
MOTD_EOF
