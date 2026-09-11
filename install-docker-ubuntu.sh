#!/usr/bin/env bash

# ==============================================================================
# Script: Automated Docker Engine & Docker Compose Installation
# Description: Installs Docker CE, containerd, Docker Compose plugin, configures
#              global log rotation (/etc/docker/daemon.json), sets up non-root
#              user permissions, and enables systemd auto-start.
# ==============================================================================

set -u

# Terminal output formatting colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Ensure root privileges
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be executed with root privileges (e.g., using sudo)."
    exit 1
fi

# Detect actual invoking user when run via sudo
TARGET_USER="${SUDO_USER:-$USER}"

echo "=================================================="
echo " Starting Docker Engine Installation & Tuning"
echo " Target user for group permissions: ${TARGET_USER}"
echo "=================================================="

# ------------------------------------------------------------------------------
# Step 1: Remove legacy Docker packages
# ------------------------------------------------------------------------------
log_info "Step 1/8: Removing old or conflicting Docker packages..."
if apt-get remove -y docker docker-engine docker.io containerd runc >/dev/null 2>&1; then
    log_success "Legacy packages removed or none were present."
else
    log_warning "Could not cleanly purge old Docker packages. Proceeding with installation."
fi

# ------------------------------------------------------------------------------
# Step 2: Install system prerequisites
# ------------------------------------------------------------------------------
log_info "Step 2/8: Installing system prerequisites (ca-certificates, curl, gnupg, jq)..."
if apt-get update -y >/dev/null && apt-get install -y ca-certificates curl gnupg lsb-release jq >/dev/null; then
    log_success "System prerequisites installed successfully."
else
    log_error "Failed to install prerequisite packages. Check apt repositories."
    exit 1
fi

# ------------------------------------------------------------------------------
# Step 3: Add Docker official GPG key
# ------------------------------------------------------------------------------
log_info "Step 3/8: Setting up Docker official GPG key..."
mkdir -p /etc/apt/keyrings
if curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --overwrite; then
    chmod a+r /etc/apt/keyrings/docker.gpg
    log_success "Docker GPG key downloaded and installed."
else
    log_error "Failed to download or dearmor Docker GPG key."
    exit 1
fi

# ------------------------------------------------------------------------------
# Step 4: Configure Docker repository
# ------------------------------------------------------------------------------
log_info "Step 4/8: Adding Docker APT repository..."
ARCH=$(dpkg --print-architecture)
CODENAME=$(lsb_release -cs)

DOCKER_LIST="/etc/apt/sources.list.d/docker.list"
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" > "$DOCKER_LIST"

if [ -f "$DOCKER_LIST" ]; then
    log_success "Docker repository configured for architecture: ${ARCH}, release: ${CODENAME}."
else
    log_error "Failed to write Docker repository configuration."
    exit 1
fi

# ------------------------------------------------------------------------------
# Step 5: Install Docker Engine and Compose plugin
# ------------------------------------------------------------------------------
log_info "Step 5/8: Installing Docker CE, CLI, containerd, and Compose plugin..."
if apt-get update -y >/dev/null && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin >/dev/null; then
    log_success "Docker Engine and packages installed successfully."
else
    log_error "Failed to install Docker packages from APT repository."
    exit 1
fi

# ------------------------------------------------------------------------------
# Step 6: Configure Global Docker Daemon Logging (/etc/docker/daemon.json)
# ------------------------------------------------------------------------------
log_info "Step 6/8: Configuring Docker daemon logging limits (max-size: 10m, max-file: 3, compress: true)..."

DAEMON_JSON="/etc/docker/daemon.json"
mkdir -p /etc/docker

if [ -f "$DAEMON_JSON" ] && [ -s "$DAEMON_JSON" ]; then
    log_info "Existing $DAEMON_JSON detected. Merging logging configurations..."
    TMP_JSON=$(mktemp)
    if jq '."log-driver" = "json-file" | ."log-opts" = {"max-size": "10m", "max-file": "3", "compress": "true"}' "$DAEMON_JSON" > "$TMP_JSON"; then
        mv "$TMP_JSON" "$DAEMON_JSON"
        chmod 644 "$DAEMON_JSON"
        log_success "Daemon configuration merged successfully."
    else
        log_warning "Failed to parse existing JSON with jq. Overwriting $DAEMON_JSON."
        rm -f "$TMP_JSON"
        cat << 'EOF' > "$DAEMON_JSON"
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3",
    "compress": "true"
  }
}
EOF
        chmod 644 "$DAEMON_JSON"
    fi
else
    cat << 'EOF' > "$DAEMON_JSON"
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3",
    "compress": "true"
  }
}
EOF
    chmod 644 "$DAEMON_JSON"
    log_success "Created $DAEMON_JSON with default log rotation limits."
fi

# ------------------------------------------------------------------------------
# Step 7: Manage User Permissions (Post-install step)
# ------------------------------------------------------------------------------
log_info "Step 7/8: Granting user '${TARGET_USER}' access to Docker group..."

if ! getent group docker >/dev/null; then
    groupadd docker
fi

if usermod -aG docker "$TARGET_USER"; then
    log_success "User '${TARGET_USER}' added to the 'docker' group."
else
    log_warning "Failed to add user '${TARGET_USER}' to the docker group."
fi

# ------------------------------------------------------------------------------
# Step 8: Enable systemd services and restart Docker
# ------------------------------------------------------------------------------
log_info "Step 8/8: Enabling auto-start and restarting Docker daemon to apply changes..."

systemctl enable docker.service >/dev/null 2>&1
systemctl enable containerd.service >/dev/null 2>&1

if systemctl restart docker; then
    log_success "Docker daemon restarted and active."
else
    log_error "Failed to restart Docker service. Please inspect logs via: journalctl -u docker"
    exit 1
fi

# ------------------------------------------------------------------------------
# Verification & Final Output
# ------------------------------------------------------------------------------
echo "=================================================="
log_info "Verifying Docker Installation Status..."
echo "--------------------------------------------------"

DOCKER_VER=$(docker --version 2>/dev/null || echo "Not Found")
COMPOSE_VER=$(docker compose version 2>/dev/null || echo "Not Found")

echo -e " Docker Version:  ${GREEN}${DOCKER_VER}${NC}"
echo -e " Compose Version: ${GREEN}${COMPOSE_VER}${NC}"

ACTIVE_LOG_DRIVER=$(docker info --format '{{.LoggingDriver}}' 2>/dev/null || echo "Unknown")
echo -e " Logging Driver:  ${GREEN}${ACTIVE_LOG_DRIVER}${NC}"

echo "--------------------------------------------------"
log_success "Docker installation and configuration complete!"
log_warning "To run Docker without 'sudo', log out and back in, or run: newgrp docker"
echo "=================================================="
