#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "=== Updating system packages and installing prerequisites ==="
sudo apt update && sudo apt upgrade -y
sudo apt install ca-certificates curl gnupg -y

echo "=== Adding Docker's official GPG key and repository ==="
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "=== Installing Docker Engine and Docker Compose plugin ==="
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

echo "=== Adding current user to the docker group ==="
sudo usermod -aG docker $USER

echo "=== Checking Docker service status ==="
sudo systemctl is-active docker

echo "=== Done! Docker has been successfully installed. Please restart your session or run 'newgrp docker'. ==="
