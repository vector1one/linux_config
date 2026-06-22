#!/bin/bash
# Docker_QoL.sh - Install Docker Engine, Compose, Buildx, and Portainer
#MSB145

set -e

echo "[*] Updating package list..."
sudo apt update

echo "[*] Installing prerequisites..."
sudo apt install -y ca-certificates apt-transport-https software-properties-common curl

# Add Docker's official GPG key:
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF


echo "[*] Installing Docker Engine and plugins..."
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
