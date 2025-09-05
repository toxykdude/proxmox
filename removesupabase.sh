#!/usr/bin/env bash

# Supabase Removal Script for Proxmox Host
# This script safely removes all Supabase components installed on the host

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Supabase Removal Script ===${NC}"
echo -e "${YELLOW}This will completely remove Supabase from your Proxmox host${NC}"
echo -e "${RED}WARNING: This will delete all data and cannot be undone!${NC}"
echo ""

read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm
if [[ $confirm != "yes" ]]; then
    echo "Removal cancelled."
    exit 0
fi

echo -e "\n${BLUE}Starting Supabase removal process...${NC}\n"

# Function to display progress
msg_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

msg_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

msg_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

msg_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Stop and disable Supabase service
msg_info "Stopping Supabase services"
if systemctl is-active --quiet supabase.service 2>/dev/null; then
    systemctl stop supabase.service
    msg_ok "Stopped Supabase service"
else
    msg_warn "Supabase service was not running"
fi

if systemctl is-enabled --quiet supabase.service 2>/dev/null; then
    systemctl disable supabase.service
    msg_ok "Disabled Supabase service"
fi

# Stop Supabase if running as user
msg_info "Stopping user Supabase processes"
if [ -d "/home/supabase/supabase-project" ]; then
    sudo -u supabase bash -c 'cd /home/supabase/supabase-project && supabase stop' 2>/dev/null || true
    msg_ok "Stopped user Supabase processes"
fi

# Remove Docker containers related to Supabase
msg_info "Removing Supabase Docker containers"
SUPABASE_CONTAINERS=$(docker ps -a --filter "name=supabase" --format "{{.Names}}" 2>/dev/null || true)
if [ ! -z "$SUPABASE_CONTAINERS" ]; then
    echo "$SUPABASE_CONTAINERS" | while read -r container; do
        if [ ! -z "$container" ]; then
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
            msg_ok "Removed container: $container"
        fi
    done
else
    msg_warn "No Supabase containers found"
fi

# Remove Docker images related to Supabase
msg_info "Removing Supabase Docker images"
SUPABASE_IMAGES=$(docker images --filter "reference=supabase/*" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null || true)
if [ ! -z "$SUPABASE_IMAGES" ]; then
    echo "$SUPABASE_IMAGES" | while read -r image; do
        if [ ! -z "$image" ]; then
            docker rmi "$image" 2>/dev/null || true
            msg_ok "Removed image: $image"
        fi
    done
else
    msg_warn "No Supabase images found"
fi

# Remove additional Docker images that might be related
ADDITIONAL_IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "(postgres:|postgrest|gotrue|realtime|storage-api|kong:|deno:|edge-runtime)" 2>/dev/null || true)
if [ ! -z "$ADDITIONAL_IMAGES" ]; then
    msg_info "Removing additional related Docker images"
    echo "$ADDITIONAL_IMAGES" | while read -r image; do
        if [ ! -z "$image" ]; then
            docker rmi "$image" 2>/dev/null || true
            msg_ok "Removed image: $image"
        fi
    done
fi

# Remove Docker networks
msg_info "Removing Supabase Docker networks"
SUPABASE_NETWORKS=$(docker network ls --filter "name=supabase" --format "{{.Name}}" 2>/dev/null || true)
if [ ! -z "$SUPABASE_NETWORKS" ]; then
    echo "$SUPABASE_NETWORKS" | while read -r network; do
        if [ ! -z "$network" ] && [ "$network" != "bridge" ] && [ "$network" != "host" ] && [ "$network" != "none" ]; then
            docker network rm "$network" 2>/dev/null || true
            msg_ok "Removed network: $network"
        fi
    done
else
    msg_warn "No Supabase networks found"
fi

# Remove Docker volumes
msg_info "Removing Supabase Docker volumes"
SUPABASE_VOLUMES=$(docker volume ls --filter "name=supabase" --format "{{.Name}}" 2>/dev/null || true)
if [ ! -z "$SUPABASE_VOLUMES" ]; then
    echo "$SUPABASE_VOLUMES" | while read -r volume; do
        if [ ! -z "$volume" ]; then
            docker volume rm "$volume" 2>/dev/null || true
            msg_ok "Removed volume: $volume"
        fi
    done
else
    msg_warn "No Supabase volumes found"
fi

# Remove systemd service file
msg_info "Removing systemd service file"
if [ -f "/etc/systemd/system/supabase.service" ]; then
    rm -f /etc/systemd/system/supabase.service
    systemctl daemon-reload
    msg_ok "Removed systemd service file"
else
    msg_warn "Systemd service file not found"
fi

# Remove management script symlink
msg_info "Removing management script"
if [ -L "/usr/local/bin/supabase-manage" ]; then
    rm -f /usr/local/bin/supabase-manage
    msg_ok "Removed management script symlink"
else
    msg_warn "Management script symlink not found"
fi

# Remove supabase user and home directory
msg_info "Removing supabase user and data"
if id "supabase" &>/dev/null; then
    # Stop any processes running as supabase user
    pkill -u supabase 2>/dev/null || true
    sleep 2
    
    # Remove cron jobs
    sudo -u supabase crontab -r 2>/dev/null || true
    
    # Remove user and home directory
    userdel -r supabase 2>/dev/null || true
    msg_ok "Removed supabase user and home directory"
else
    msg_warn "Supabase user not found"
fi

# Remove sudoers file
msg_info "Removing sudoers configuration"
if [ -f "/etc/sudoers.d/supabase" ]; then
    rm -f /etc/sudoers.d/supabase
    msg_ok "Removed sudoers configuration"
else
    msg_warn "Sudoers configuration not found"
fi

# Remove firewall rules (optional - ask user)
read -p "Do you want to remove the UFW firewall rules for Supabase ports? (y/n): " remove_fw
if [[ $remove_fw =~ ^[Yy]$ ]]; then
    msg_info "Removing firewall rules"
    ufw --force delete allow 3000/tcp 2>/dev/null || true
    ufw --force delete allow 54321/tcp 2>/dev/null || true
    ufw --force delete allow 54322/tcp 2>/dev/null || true
    ufw --force delete allow 54323/tcp 2>/dev/null || true
    ufw --force delete allow 54324/tcp 2>/dev/null || true
    ufw --force delete allow 54325/tcp 2>/dev/null || true
    msg_ok "Removed firewall rules"
else
    msg_warn "Kept firewall rules (remove manually if needed)"
fi

# Ask about removing Node.js and npm (since they might be used for other things)
read -p "Do you want to remove Node.js and npm? (y/n): " remove_node
if [[ $remove_node =~ ^[Yy]$ ]]; then
    msg_info "Removing Node.js and npm"
    
    # Remove Supabase CLI globally
    npm uninstall -g supabase 2>/dev/null || true
    
    # Remove Node.js
    apt-get remove -y nodejs npm 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
    
    # Remove Node.js repository
    rm -f /etc/apt/sources.list.d/nodesource.list
    rm -f /usr/share/keyrings/nodesource.gpg
    
    msg_ok "Removed Node.js and npm"
else
    msg_info "Removing Supabase CLI only"
    npm uninstall -g supabase 2>/dev/null || true
    msg_ok "Removed Supabase CLI"
fi

# Ask about removing Docker (since it might be used for other containers)
read -p "Do you want to remove Docker completely? (y/n): " remove_docker
if [[ $remove_docker =~ ^[Yy]$ ]]; then
    msg_info "Removing Docker"
    
    # Stop Docker service
    systemctl stop docker 2>/dev/null || true
    systemctl disable docker 2>/dev/null || true
    
    # Remove Docker packages
    apt-get remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
    apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
    
    # Remove Docker repository and GPG key
    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /etc/apt/keyrings/docker.asc
    
    # Remove Docker data directory
    rm -rf /var/lib/docker
    rm -rf /var/lib/containerd
    
    msg_ok "Removed Docker completely"
else
    msg_warn "Kept Docker (remove manually if needed)"
    msg_info "Running Docker cleanup"
    docker system prune -af 2>/dev/null || true
    msg_ok "Cleaned up unused Docker resources"
fi

# Clean up any remaining files
msg_info "Cleaning up remaining files"
rm -rf /tmp/supabase* 2>/dev/null || true
rm -rf /var/tmp/supabase* 2>/dev/null || true

# Update package database
msg_info "Updating package database"
apt-get update 2>/dev/null || true
msg_ok "Updated package database"

# Final cleanup
msg_info "Final system cleanup"
apt-get autoremove -y 2>/dev/null || true
apt-get autoclean 2>/dev/null || true
msg_ok "System cleanup completed"

echo -e "\n${GREEN}=== Supabase Removal Complete ===${NC}"
echo -e "${BLUE}Summary of actions taken:${NC}"
echo -e "  ✓ Stopped and removed Supabase services"
echo -e "  ✓ Removed Docker containers, images, networks, and volumes"
echo -e "  ✓ Removed systemd service and management scripts"
echo -e "  ✓ Removed supabase user and data directory"
echo -e "  ✓ Cleaned up configuration files"

if [[ $remove_node =~ ^[Yy]$ ]]; then
    echo -e "  ✓ Removed Node.js and npm"
else
    echo -e "  ✓ Removed Supabase CLI only"
fi

if [[ $remove_docker =~ ^[Yy]$ ]]; then
    echo -e "  ✓ Removed Docker completely"
else
    echo -e "  ✓ Cleaned up Docker resources"
fi

if [[ $remove_fw =~ ^[Yy]$ ]]; then
    echo -e "  ✓ Removed firewall rules"
fi

echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "  1. Create a new LXC container with nesting enabled"
echo -e "  2. Run the Supabase installation script in the LXC container"
echo -e "  3. Verify all components are working properly"

echo -e "\n${GREEN}Your Proxmox host is now clean and ready for LXC deployment!${NC}"
