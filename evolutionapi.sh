#!/usr/bin/env bash
# ----------------------------------------------------------------------------------
# Evolution API LXC Installer for Proxmox VE
# Based on: https://github.com/community-scripts/ProxmoxVE
# Author: toxykdude
# ----------------------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

# Load build functions
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# App details
APP="Evolution API"
var_os="debian"
var_version="12"
var_tag="standard"
var_ctid="900"
var_cpu="2"
var_ram="1024"
var_disk="8"
var_storage="local-lvm"
var_net="dhcp"
var_bridge="vmbr0"
description="WhatsApp Evolution API server with Node.js + PM2"

header_info
echo -e "${BL}Starting build for: ${APP}${CL}"

# Build container
build_container

# Post-install inside container
post_install() {
  echo -e "${BL}Installing ${APP} inside container...${CL}"
  apt-get update
  apt-get install -y curl git build-essential
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
  npm install -g pm2

  cd /opt
  git clone https://github.com/EvolutionAPI/evolution-api evolutionapi
  cd evolutionapi
  npm install

  pm2 start src/index.js --name evolutionapi
  pm2 startup systemd -u root --hp /root
  pm2 save
}

# Push post-install function into container
pct exec "$CTID" -- bash -c "$(declare -f post_install); post_install"

# Success message
IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
msg_ok "Installation of ${APP} completed"
msg_info "Container ID: $CTID"
msg_info "Hostname: $HN"
msg_info "IP Address: $IP"
msg_info "Service: running via pm2"
