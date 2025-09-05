#!/usr/bin/env bash
# ----------------------------------------------------------------------------------
# Supabase Installer for Proxmox VE
# Inspired by: https://github.com/community-scripts/ProxmoxVE
# Author: toxykdude
# ----------------------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

# Variables
APP="Supabase"
REPO_URL="https://github.com/supabase/supabase"
INSTALL_DIR="/opt/supabase"
DOCKER_COMPOSE_FILE="docker-compose.yml"

# Colors
YW=$(echo "\033[33m")
RD=$(echo "\033[01;31m")
GR=$(echo "\033[1;92m")
BL=$(echo "\033[36m")
CL=$(echo "\033[m")

# Error handler
error_exit() {
    echo -e "${RD}Error: $1${CL}"
    exit 1
}

# Check root
if [[ $EUID -ne 0 ]]; then
    error_exit "This script must be run as root."
fi

# Header
clear
echo -e "${GR}
-------------------------------------------------
   ${APP} Installer for Proxmox VE
-------------------------------------------------
${CL}"

# Function to check command existence
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install dependencies
echo -e "${BL}Updating system and installing dependencies...${CL}"
apt-get update -y || error_exit "apt update failed"
apt-get install -y curl git docker.io docker-compose-plugin || error_exit "dependency install failed"

# Enable and start Docker
systemctl enable --now docker || error_exit "failed to start Docker"

# Setup install directory
if [[ ! -d "$INSTALL_DIR" ]]; then
    echo -e "${BL}Creating directory ${INSTALL_DIR}...${CL}"
    mkdir -p "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

# Clone or update Supabase repo
if [[ ! -d ".git" ]]; then
    echo -e "${BL}Cloning Supabase repository...${CL}"
    git clone --depth=1 "$REPO_URL" . || error_exit "git clone failed"
else
    echo -e "${BL}Updating existing Supabase repo...${CL}"
    git pull || error_exit "git pull failed"
fi

# Ensure docker-compose.yml exists
if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
    error_exit "docker-compose.yml not found in repo. Check Supabase structure."
fi

# Start Supabase
echo -e "${BL}Starting Supabase services with Docker Compose...${CL}"
docker compose -f "$DOCKER_COMPOSE_FILE" up -d || error_exit "Supabase startup failed"

# Success
echo -e "${GR}
-------------------------------------------------
   ${APP} installation completed successfully!
   Directory: ${INSTALL_DIR}
   To manage services: cd ${INSTALL_DIR} && docker compose ps
-------------------------------------------------
${CL}"
