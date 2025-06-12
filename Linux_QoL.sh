#!/bin/bash
# Linux_QoL.sh - Quality of Life package installer for Ubuntu

set -e

echo "[*] Updating package list..."
sudo apt update

echo "[*] Installing htop, curl, git, openssh-client, open-vm-tools-desktop..."
sudo apt install -y htop curl git openssh-client open-vm-tools-desktop gparted nmap nfs-common

echo "[*] Installing Docker and Docker Compose..."
# Install prerequisites
sudo apt install -y ca-certificates apt-transport-https software-properties-common

# Add Docker’s official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Add Docker’s repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[*] Installing Cockpit..."
sudo apt install -y cockpit

echo "[*] Enabling and starting Docker and Cockpit..."
sudo systemctl enable --now docker
sudo systemctl enable --now cockpit.socket

#echo "start server init 3"
#sudo systemctl set-default multi-user.target
#use /usr/sbin/init 5 to bring up the desktop



echo "[*] All requested tools are installed!"
