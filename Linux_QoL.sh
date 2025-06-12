#!/bin/bash
# Linux_QoL.sh - Quality of Life package installer for Ubuntu
#starts headless and provides some admin tools
#MSB145


echo "[*] Updating package list..."
sudo apt update

echo "[*] Installing htop, curl, git, openssh-client, open-vm-tools-desktop..."
sudo apt install -y htop curl git openssh-client open-vm-tools-desktop gparted nmap nfs-common

echo "[*] Installing Cockpit..."
sudo apt install -y cockpit

echo "[*] Enabling and starting Cockpit..."
sudo systemctl enable --now cockpit.socket

echo "start server init 3"
sudo systemctl set-default multi-user.target
#use /usr/sbin/init 5 to bring up the desktop



echo "[*] All requested tools are installed!"
