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
#openjdk-11-jdk
/usr/bin/apt install -y docker
/usr/bin/apt install -y docker-compose


#start server init 3
sudo systemctl set-default multi-user.target
#reboot for headless or
#/usr/sbin/init 3

#lvm expander
cd /home/cptadmin/Documents
mkdir Git
cd Git
git clone https://github.com/vector1one/diskimage_ubuntu.git
chmod a+x diskimage_ubuntu.sh

