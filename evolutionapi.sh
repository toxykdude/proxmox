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
IMAGE="debian-12-standard_12.2-1_amd64.tar.zst"

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

# Ensure pveam template exists
echo -e "${BL}Checking container template...${CL}"
if [[ ! -f "${VAR_LIB_CT}/${IMAGE}" ]]; then
  echo -e "${BL}Downloading Debian template...${CL}"
  pveam update >/dev/null
  pveam download local debian-12-standard_12.2-1_amd64.tar.zst || error_exit "Template download failed"
fi

# Create LXC container
echo -e "${BL}Creating LXC container (CTID: ${CTID})...${CL}"
pct create $CTID ${VAR_LIB_CT}/${IMAGE} \
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
  pm2 startup systemd
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

