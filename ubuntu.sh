#!/bin/bash
#bluff need a gui server to boot headless with features.
#add/remove as you see fit 
#simple customise env script

#system
/usr/bin/apt update 
/usr/bin/apt install -y htop
/usr/bin/apt install -y net-tools
/usr/bin/apt install -y open-vm-tools-desktop
/usr/bin/apt install -y openssh-server
/usr/bin/apt install -y curl
/usr/bin/apt install -y git
/usr/bin/apt install -y nmap
/usr/bin/apt install -y gparted
#openjdk-11-jdk
/usr/bin/apt install -y docker
/usr/bin/apt install -y docker-compose


#start server init 3
sudo systemctl set-default multi-user.target
#reboot for headless or
#/usr/sbin/init 3

#
#still a WIP
#lvm expander
#cd ~/Downloads
#mkdir Git
#cd Git
#git clone https://github.com/vector1one/diskimage_ubuntu.git
#chmod a+x diskimage_ubuntu.sh

#adding in smbv1 connection
#sudo apt install samba
#/etc/samba.samba.conf
#add in "client min protocol = CORE" under global settings
