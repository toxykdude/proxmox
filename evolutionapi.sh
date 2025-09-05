#!/usr/bin/env bash
# ----------------------------------------------------------------------------------
# Evolution API LXC Installer for Proxmox VE
# Inspired by: https://github.com/community-scripts/ProxmoxVE
# Author: toxykdude
# ----------------------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

APP="Evolution API"
VAR_LIB_CT="/var/lib/vz/template/cache"
CTID=${CTID:-900}
HOSTNAME="evolutionapi"
DISK_SIZE="8G"
RAM_SIZE="1024"
BRIDGE="vmbr0"
NET="dhcp"

YW=$'\033[33m'
RD=$'\033[01;31m'
GR=$'\033[1;92m'
BL=$'\033[36m'
CL=$'\033[m'

# Error handler
error_exit() {
  echo -e "${RD}Error: $1${CL}"
  exit 1
}

# Header
clear
echo -e "${GR}
-------------------------------------------------
   ${APP} LXC Installer for Proxmox VE
-------------------------------------------------
${CL}"

# Check root
if [[ $EUID -ne 0 ]]; then
  error_exit "This script must be run as root."
fi

# Find latest Debian 12 template
echo -e "${BL}Checking container template...${CL}"
LATEST_DEBIAN=$(pveam available | grep debian-12-standard | sort -V | tail -n1 | awk '{print $2}')

if [[ -z "$LATEST_DEBIAN" ]]; then
  error_exit "No Debian 12 template found in pveam available list."
fi

TEMPLATE_FILE="${VAR_LIB_CT}/${LATEST_DEBIAN##*/}"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo -e "${BL}Downloading Debian template: ${LATEST_DEBIAN}${CL}"
  pveam download local "$LATEST_DEBIAN" || error_exit "Template download failed"
fi

# Create LXC container
echo -e "${BL}Creating LXC container (CTID: ${CTID})...${CL}"
pct create $CTID "$TEMPLATE_FILE" \
  --hostname $HOSTNAME \
  --rootfs local-lvm:${DISK_SIZE} \
  --memory $RAM_SIZE \
  --net0 name=eth0,bridge=$BRIDGE,ip=${NET} \
  --unprivileged 1 \
  --features nesting=1 || error_exit "LXC creation failed"

# Start container
echo -e "${BL}Starting container...${CL}"
pct start $CTID
sleep 5

# Install Evolution API inside LXC
echo -e "${BL}Installing ${APP} inside container...${CL}"
pct exec $CTID -- bash -c "
  set -e
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
"

# Success message
IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')
echo -e "${GR}
-------------------------------------------------
   ${APP} installation completed successfully!
   Container ID: ${CTID}
   Hostname:     ${HOSTNAME}
   IP Address:   ${IP}
   Service:      running via pm2
-------------------------------------------------
${CL}"
