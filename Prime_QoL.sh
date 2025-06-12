#!/bin/bash
# Linux_QoL.sh - Quality of Life package installer for Ubuntu
#starts headless and provides some admin tools
#installs Docker and portainer
#MSB145

echo "[*] Updating package list..."
sudo apt update

echo "[*] Installing system tools (htop, curl, git, openssh-client, open-vm-tools-desktop, nfs-common, cockpit)..."
sudo apt install -y htop curl git openssh-client open-vm-tools-desktop nfs-common cockpit

echo "[*] Installing Docker Engine and plugins..."

# Install Docker prerequisites
sudo apt install -y ca-certificates apt-transport-https software-properties-common

# Add Docker’s official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[*] Enabling and starting Docker and Cockpit..."
sudo systemctl enable --now docker
sudo systemctl enable --now cockpit.socket

echo "[*] Deploying Portainer (Docker UI)..."
sudo docker volume create portainer_data
sudo docker run -d \
  --name portainer \
  --restart=always \
  -p 9000:9000 -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest

# Startup target comments and manual steps:
echo ""
echo "# To start server in text mode (multi-user):"
echo "# sudo systemctl set-default multi-user.target"
echo "# To bring up the desktop session later, use:"
echo "# sudo /usr/sbin/init 5"
echo ""
echo "[*] All requested tools and Docker/Portainer are installed!"
echo "→ Access Portainer UI at: http://<your-server-ip>:9000"
echo "→ Access Cockpit UI at: https://<your-server-ip>:9090"
echo "Profit"
