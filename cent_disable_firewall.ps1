#!/usr/bin/powershell
firewall-cmd --zone=public --add-port=443/tcp --permanent
systemctl stop firewalld
systemctl start firewalld

