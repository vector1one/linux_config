#!/bin/bash
# Docker_QoL.sh - Install Docker Engine, Compose, Buildx, and Portainer

set -e

echo "[*] Updating package list..."
sudo apt update

echo "[*] Installing prerequisites..."
sudo apt install -y ca-certificates apt-transport-https software-properties-common curl

echo "[*] Adding Docker’s official GPG key..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "[*] Adding Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update

echo "[*] Installing Docker Engine and plugins..."
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[*] Enabling and starting Docker..."
sudo systemctl enable --now docker

echo "[*] Deploying Portainer (Docker UI)..."
sudo docker volume create portainer_data
sudo docker run -d \
  --name portainer \
  --restart=always \
  -p 9000:9000 -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest

echo "[*] Docker and Portainer installation complete!"
echo "→ Access Portainer UI at: http://<your-server-ip>:9000"
