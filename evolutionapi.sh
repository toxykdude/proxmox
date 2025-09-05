#!/usr/bin/env bash
# ----------------------------------------------------------------------------------
# Evolution API LXC Installer for Proxmox VE
# Style: Community-Scripts (uses build.func)
# Repo idea: https://github.com/community-scripts/ProxmoxVE
# Author: toxykdude
# ----------------------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

# ----- Load Community build helpers (colors, header_info, msg_*, build_container, etc.) -----
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# ----- Ensure dialog/whiptail available for menus -----
if ! command -v whiptail >/dev/null 2>&1; then
  apt-get update -y >/dev/null
  apt-get install -y whiptail >/dev/null
fi

header_info
APP="Evolution API"
description="WhatsApp Evolution API server with Node.js + PM2"
echo -e "${BL}This installer will create a new LXC and set up ${APP}.${CL}"
echo

# ----- Helpers -----
next_id() {
  if command -v pct >/dev/null 2>&1; then
    pct nextid
  else
    pvesh get /cluster/nextid
  fi
}
storages_with() { pvesm status -content "$1" | awk 'NR>1 {print $1}'; }

# ----- Defaults -----
DEF_OS="debian"
DEF_OS_VER="12"              # Debian 12 or Ubuntu 22.04
DEF_HOSTNAME="evolutionapi"
DEF_CTID="$(next_id)"
DEF_CPU="2"
DEF_RAM="1024"
DEF_DISK="8"
DEF_BRIDGE="vmbr0"
DEF_IPMODE="DHCP"
DEF_STATIC_IP="192.168.1.50/24"
DEF_GATEWAY="192.168.1.1"

# Storage defaults
DEF_TPL_STORE="$(storages_with vztmpl | head -n1)"
DEF_CT_STORE="$(storages_with rootdir | head -n1)"
[ -z "${DEF_TPL_STORE}" ] && DEF_TPL_STORE="local"
[ -z "${DEF_CT_STORE}" ] && DEF_CT_STORE="local-lvm"

# ----- OS Choice -----
OS_CHOICE=$(whiptail --title "Base OS" --radiolist "Select the container OS:" 12 70 2 \
"debian-12"  "Debian 12 (Bookworm) — recommended" ON \
"ubuntu-22.04" "Ubuntu 22.04 LTS (Jammy)" OFF 3>&1 1>&2 2>&3) || exit 1

case "$OS_CHOICE" in
  debian-12)
    var_os="debian"
    var_version="12"
    ;;
  ubuntu-22.04)
    var_os="ubuntu"
    var_version="22.04"
    ;;
esac

# ----- Basic params -----
var_ctid=$(whiptail --inputbox "Container ID (CTID):" 10 60 "$DEF_CTID" 3>&1 1>&2 2>&3) || exit 1
HN=$(whiptail --inputbox "Hostname:" 10 60 "$DEF_HOSTNAME" 3>&1 1>&2 2>&3) || exit 1
var_cpu=$(whiptail --inputbox "CPU Cores:" 10 60 "$DEF_CPU" 3>&1 1>&2 2>&3) || exit 1
var_ram=$(whiptail --inputbox "Memory (MiB):" 10 60 "$DEF_RAM" 3>&1 1>&2 2>&3) || exit 1
var_disk=$(whiptail --inputbox "Disk size (GiB):" 10 60 "$DEF_DISK" 3>&1 1>&2 2>&3) || exit 1

# ----- Storage -----
# Template storage (vztmpl)
TEMPLATE_STORAGE=$(whiptail --menu "Select template storage (vztmpl):" 18 70 10 \
$(storages_with vztmpl | awk '{print $1" -"}') 3>&1 1>&2 2>&3) || exit 1
[ -z "$TEMPLATE_STORAGE" ] && TEMPLATE_STORAGE="$DEF_TPL_STORE"

# CT rootfs storage (rootdir)
var_storage=$(whiptail --menu "Select container rootfs storage (rootdir):" 18 70 10 \
$(storages_with rootdir | awk '{print $1" -"}') 3>&1 1>&2 2>&3) || exit 1
[ -z "$var_storage" ] && var_storage="$DEF_CT_STORE"

# ----- Network -----
BR=$(whiptail --inputbox "Linux bridge (e.g., vmbr0):" 10 60 "$DEF_BRIDGE" 3>&1 1>&2 2>&3) || exit 1
IPMODE=$(whiptail --title "IP Configuration" --radiolist "Select IP mode:" 12 70 2 \
"DHCP"  "Automatic from DHCP" ON \
"STATIC" "Static IP" OFF 3>&1 1>&2 2>&3) || exit 1

if [[ "$IPMODE" == "STATIC" ]]; then
  STATIC_IP=$(whiptail --inputbox "Static IP (CIDR), e.g. 192.168.1.50/24:" 10 60 "$DEF_STATIC_IP" 3>&1 1>&2 2>&3) || exit 1
  GATEWAY=$(whiptail --inputbox "Gateway IP, e.g. 192.168.1.1:" 10 60 "$DEF_GATEWAY" 3>&1 1>&2 2>&3) || exit 1
  var_net="static=${STATIC_IP},gw=${GATEWAY}"
else
  var_net="dhcp"
fi
var_bridge="$BR"

# ----- Tag (image type) used by build.func -----
# Standard images are fine (debian/ubuntu standard)
var_tag="standard"

# ----- Show summary -----
SUMMARY=$(cat <<EOF
OS:          ${var_os} ${var_version} (${var_tag})
CTID:        ${var_ctid}
Hostname:    ${HN}
CPU:         ${var_cpu}
RAM:         ${var_ram} MiB
Disk:        ${var_disk} GiB
Storage:     ${var_storage}
Template st: ${TEMPLATE_STORAGE}
Bridge:      ${var_bridge}
IP:          ${var_net}
EOF
)
whiptail --title "Confirm Settings" --yesno "$SUMMARY\n\nProceed?" 18 72 || exit 1

# ----- Build container (build.func reads var_* and global HN) -----
msg_info "Preparing LXC template and container…"
export TEMPLATE_STORAGE
build_container
msg_ok "Container created: CTID ${CTID}"

# ----- App install inside container -----
post_install() {
  set -e
  echo "Updating apt and installing dependencies…"
  apt-get update
  apt-get install -y curl git build-essential

  echo "Installing Node.js 20 (NodeSource)…"
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs

  echo "Installing PM2…"
  npm install -g pm2

  echo "Cloning Evolution API…"
  mkdir -p /opt
  cd /opt
  if [ ! -d evolutionapi ]; then
    git clone https://github.com/EvolutionAPI/evolution-api evolutionapi
  fi
  cd evolutionapi

  echo "Installing Evolution API dependencies…"
  npm install

  # You can export ENV here if you need specific config (PORT, etc.)
  # Example:
  # export PORT=3000
  # export NODE_ENV=production

  echo "Starting Evolution API with PM2…"
  pm2 start src/index.js --name evolutionapi

  echo "Enabling PM2 startup and saving process list…"
  pm2 startup systemd -u root --hp /root >/dev/null
  pm2 save
}

msg_info "Installing ${APP} inside the container…"
pct exec "$CTID" -- bash -lc "$(declare -f post_install); post_install"
msg_ok "${APP} installed"

# ----- Final info -----
IP=$(pct exec "$CTID" -- bash -lc "hostname -I | awk '{print \$1}'" || true)
PORT_GUESS="3000"
header_info
echo -e "${GR}-------------------------------------------------${CL}"
echo -e "${GR}  ${APP} deployment completed!${CL}"
echo -e "${GR}-------------------------------------------------${CL}"
echo -e "${BL}Container ID:${CL}  ${CTID}"
echo -e "${BL}Hostname:${CL}      ${HN}"
echo -e "${BL}IP Address:${CL}    ${IP:-"(DHCP pending)"}"
echo -e "${BL}Service:${CL}       PM2-managed (evolutionapi)"
echo -e "${BL}Try:${CL}           http://${IP:-<CT-IP>}:${PORT_GUESS}"
echo

# ----- Optional: Post-run tip -----
echo -e "${YW}Tips:${CL}
- Edit config in /opt/evolutionapi if needed, then:
    pct exec ${CTID} -- bash -lc 'cd /opt/evolutionapi && pm2 restart evolutionapi'
- View logs:
    pct exec ${CTID} -- bash -lc 'pm2 logs evolutionapi'
"
