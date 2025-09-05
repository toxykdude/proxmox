#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts
# Author: Based on tteck's community-scripts template
# License: MIT
# Source: https://supabase.com/
# GitHub: https://github.com/toxykdude/proxmox

# Colors for output
RD='\033[01;31m'
GN='\033[1;92m'
BL='\033[36m'
YW='\033[33m'
CL='\033[0m'
CM='\033[0;36m'

function header_info {
clear
cat <<"EOF"
   _____                  __                    
  / ___/__  ______  ____ / /_  ____ __________ 
  \__ \/ / / / __ \/ __ `/ __ \/ __ `/ ___/ _ \
 ___/ / /_/ / /_/ / /_/ / /_/ / /_/ (__  )  __/
/____/\__,_/ .___/\__,_/_.___/\__,_/____/\___/ 
          /_/                                  

EOF
}

# App Variable(s)
APP="Supabase"
NSAPP="supabase"

# Check if running on Proxmox
if ! command -v pveversion >/dev/null 2>&1; then
    echo -e "${RD}This script must be run on a Proxmox VE host.${CL}"
    exit 1
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RD}This script must be run as root${CL}" 
   exit 1
fi

header_info
echo -e "${BL}[INFO]${GN} This script will create a new ${APP} LXC Container${CL}"
echo -e "${BL}[INFO]${YW} Container will be configured with Docker and all Supabase services${CL}"

# Set default values
CTID=$(pvesh get /cluster/nextid)
CTNAME="supabase"
DISK_SIZE="8"
CORES="2"
RAM="4096"
BRIDGE="vmbr0"
NET="dhcp"
OSTYPE="ubuntu"
OSVERSION="22.04"
TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
STORAGE="local-lxc"

echo -e "\n${BL}Container Configuration:${CL}"
echo -e "  ${CM}Container ID:${CL} ${CTID}"
echo -e "  ${CM}Hostname:${CL} ${CTNAME}"
echo -e "  ${CM}Disk Size:${CL} ${DISK_SIZE}GB"
echo -e "  ${CM}Cores:${CL} ${CORES}"
echo -e "  ${CM}RAM:${CL} ${RAM}MB"
echo -e "  ${CM}Network:${CL} ${NET}"
echo -e "  ${CM}OS:${CL} ${OSTYPE} ${OSVERSION}"

read -p "Press Enter to continue or Ctrl+C to cancel..."

echo -e "\n${GN}Downloading Ubuntu template if needed...${CL}"
if ! pveam list $STORAGE | grep -q $TEMPLATE; then
    pveam download $STORAGE $TEMPLATE
fi

echo -e "${GN}Creating LXC container...${CL}"
pct create $CTID $STORAGE:vztmpl/$TEMPLATE \
  --arch amd64 \
  --cores $CORES \
  --hostname $CTNAME \
  --memory $RAM \
  --net0 name=eth0,bridge=$BRIDGE,ip=$NET \
  --onboot 1 \
  --ostype $OSTYPE \
  --rootfs $STORAGE:$DISK_SIZE \
  --swap 512 \
  --unprivileged 1 \
  --features keyctl=1,nesting=1

if [ $? -ne 0 ]; then
    echo -e "${RD}Failed to create container${CL}"
    exit 1
fi

echo -e "${GN}Container created successfully!${CL}"
echo -e "${GN}Starting container...${CL}"

pct start $CTID

# Wait for container to start
echo -e "${GN}Waiting for container to fully start...${CL}"
sleep 10

# Wait for network
echo -e "${GN}Waiting for network connectivity...${CL}"
for i in {1..30}; do
    if pct exec $CTID -- ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${GN}Network is ready${CL}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RD}Network timeout - but continuing anyway${CL}"
        break
    fi
    sleep 2
done

echo -e "${GN}Installing Supabase...${CL}"
echo -e "${YW}This may take 10-15 minutes. Please be patient...${CL}"

# Execute the install script inside the container
pct exec $CTID -- bash -c "$(curl -fsSL https://raw.githubusercontent.com/toxykdude/proxmox/refs/heads/main/ProxmoxVE/install/supabase-install.sh)" 2>&1

if [ $? -eq 0 ]; then
    echo -e "\n${GN}✅ Supabase installation completed successfully!${CL}"
    
    # Get container IP
    CONTAINER_IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')
    
    echo -e "\n${BL}🌐 Access Information:${CL}"
    echo -e "  ${CM}Studio URL:${CL} http://${CONTAINER_IP}:3000"
    echo -e "  ${CM}API URL:${CL} http://${CONTAINER_IP}:54321"
    echo -e "  ${CM}Database:${CL} postgresql://postgres:postgres@${CONTAINER_IP}:54322/postgres"
    
    echo -e "\n${BL}🔧 Management Commands:${CL}"
    echo -e "  ${CM}Enter container:${CL} pct enter ${CTID}"
    echo -e "  ${CM}Start Supabase:${CL} pct exec ${CTID} -- supabase-manage start"
    echo -e "  ${CM}Stop Supabase:${CL} pct exec ${CTID} -- supabase-manage stop"
    echo -e "  ${CM}Check status:${CL} pct exec ${CTID} -- supabase-manage status"
    echo -e "  ${CM}Get info:${CL} pct exec ${CTID} -- supabase-manage info"
    
    echo -e "\n${GN}🎉 Setup complete! You can now access Supabase Studio at: http://${CONTAINER_IP}:3000${CL}"
else
    echo -e "\n${RD}❌ Installation failed. Check the logs above for details.${CL}"
    echo -e "${YW}Container ${CTID} was created but Supabase installation failed.${CL}"
    echo -e "${YW}You can try running the installation manually:${CL}"
    echo -e "  pct enter ${CTID}"
    echo -e "  curl -fsSL https://raw.githubusercontent.com/toxykdude/proxmox/refs/heads/main/ProxmoxVE/install/supabase-install.sh | bash"
    exit 1
fi
