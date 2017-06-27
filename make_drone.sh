#!/bin/bash
#
#  Script to take a VM template and make it our own
#
#  Find out what kind of system we're on
#
if [ -f /usr/bin/dpkg ]
  then
    echo "This is a dpkg machine"
    export is_rpm=0
else
    echo "This is an RPM-based machine"
    export is_rpm=1
fi

if [ $is_rpm == 0 ]
  then
    user
    echo "DEB-based system"
    useradd -d /home/mstest -s /bin/bash -G admin -m mstest -p 'P@$$w0rd!'

    dpkg -l linux-{image,headers}-* | awk '/^ii/{print $2}' | egrep '[0-9]+\.[0-9]+\.[0-9]+' | grep -v $(uname -r | cut -d- -f-2) | xargs sudo apt-get -y purge

    curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
    curl https://packages.microsoft.com/config/ubuntu/14.04/prod.list | sudo tee /etc/apt/sources.list.d/microsoft.list
    apt-get -y update

    # apt-get install -y powershell
    wget http://launchpadlibrarian.net/201330288/libicu52_52.1-8_amd64.deb
    dpkg -i libicu52_52.1-8_amd64.deb
    apt-get install powershell
    apt-get purge powershell
    export download_1404="https://github.com/PowerShell/PowerShell/releases/download/v6.0.0-beta.2/powershell_6.0.0-beta.2-1ubuntu1.14.04.1_amd64.deb"
    export download_1604="https://github.com/PowerShell/PowerShell/releases/download/v6.0.0-beta.2/powershell_6.0.0-beta.2-1ubuntu1.16.04.1_amd64.deb"
    wget $download_1604

    export pkg_name=`echo $download_1604 | sed -e s/.*powershell/powershell/`
    dpkg -r powershell
    dpkg -i pkg_name

    apt-get install -y omi-psrp-server

    apt-get install -y git
    apt-get install -y nfs-common
    sed -e s/"httpsport=0"/"httpsport=0,443"/ < /etc/opt/omi/conf/omiserver.conf > /tmp/x
    /bin//cp /tmp/x /etc/opt/omi/conf/omiserver.conf
    /opt/omi/bin/omiserver -s
    /opt/omi/bin/omiserver -d

    sed -e s/"PasswordAuthentication no"/"PasswordAuthentication yes"/ < /etc/ssh/sshd_config > /tmp/x
    /bin/cp /tmp/x /etc/ssh/sshd_conf
    service ssh restart
   
    cd
    git clone https://github.com/FawcettJohnW/Framework-Scripts.git
    mkdir runonce.d runonce.d/ran
    cp Framework-Scripts/update_and_copy.ps1 runonce.d/
    
    echo "@reboot root /root/Framework-Scripts/runonce.ps1" >> /etc/crontab
    ufw allow 443
    ufw allow 5986
else
    echo "RPM-based system"
    yum install yum-utils
    package-cleanup --oldkernels --count=2

    useradd -d /home/mstest -s /bin/bash -G wheel -m mstest -p 'P@$$w0rd!'
    curl https://packages.microsoft.com/config/rhel/7/prod.repo | sudo tee /etc/yum.repos.d/microsoft.repo
    yum update -y

    # yum install -y powershell
    yum install -y powershell
    yum erase -y powershell
    export download_normal="https://github.com/PowerShell/PowerShell/releases/download/v6.0.0-beta.2/powershell-6.0.0_beta.2-1.el7.x86_64.rpm"
    export doenload_suse="https://github.com/PowerShell/PowerShell/releases/download/v6.0.0-beta.2/powershell-6.0.0_beta.2-1.suse.42.1.x86_64.rpm"
    wget $download_normal
    rpm -i $download_normal

    yum install -y omi
    yum install -y psrp-omi-serverssh
    yum install -y git
    yum install -y nfs-utils

    sed -e s/"httpsport=0"/"httpsport=0,443"/ < /etc/opt/omi/conf/omiserver.conf > /tmp/x
    /bin/cp /tmp/x /etc/opt/omi/conf/omiserver.conf
    /opt/omi/bin/omiserver -s
    /opt/omi/bin/omiserver -d
    sed -e s/"PasswordAuthentication no"/"PasswordAuthentication yes"/ < /etc/ssh/sshd_config > /tmp/x
    /bin/cp /tmp/x /etc/ssh/sshd_conf
    systemctl stop sshd
    cd
    git clone https://github.com/FawcettJohnW/Framework-Scripts.git
    mkdir runonce.d runonce.d/ran
    cp Framework-Scripts/update_and_copy.ps1 runonce.d/
    echo "@reboot root /root/Framework-Scripts/runonce.ps1" >> /etc/crontab

    firewall-cmd --zone=public --add-port=443/tcp --permanent
    systemctl stop firewalld
    systemctl start firewalld
fi
