#!/usr/bin/env bash

# GitHub: https://github.com/toxykdude/proxmox
# This script is generated from a web UI.

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD="-"
// FIX: Escaped shell variables to prevent TypeScript interpolation.
CM="\${GN}✓\${CL}"
CROSS="\${RD}✗\${CL}"

function msg_info() {
  // FIX: Escaped shell variables to prevent TypeScript interpolation.
  echo -e "\\n\${BL}[*]\${CL} \${1}"
}
function msg_ok() {
  // FIX: Escaped shell variables to prevent TypeScript interpolation.
  echo -e "\${BFR}\${CM} \${1}\${CL}"
}
function msg_error() {
  // FIX: Escaped shell variables to prevent TypeScript interpolation.
  echo -e "\${BFR}\${CROSS} \${1}\${CL}"
}

# Static settings
TEMPLATE_REPO="https://github.com/actions/runner-images"
# Find latest Ubuntu 22.04 release
// FIX: Escaped shell variable to prevent TypeScript interpolation.
URL=$(curl -s "https://api.github.com/repos/\${TEMPLATE_REPO}/releases" | grep "browser_download_url" | grep "ubuntu-2204" | grep "tar.gz" | head -n1 | cut -d'"' -f4)
TEMPLATE_FILE="\${URL##*/}"
TEMPLATE_NAME="\${TEMPLATE_FILE//-arm64/}" # remove -arm64
STORAGE_TYPE=$(pvesm status -storage local-lvm | awk 'NR>1 {print $2}')

# User-defined settings from generator
CTID="200"
HOSTNAME="supabase"
PASSWORD="testing123"
DISK_SIZE="16G"
CORES="2"
RAM_SIZE="2048"
BRIDGE="vmbr0"
STORAGE="local-lvm"
NETWORK_CONFIG="name=eth0,bridge=${BRIDGE},ip=dhcp"

# Supabase Secrets
POSTGRES_PASSWORD='9pMDcwNeimViwYIyEWNLkkmQkORCJ1mHgoCufVAK'
JWT_SECRET='3R2Kxw0ABgZAXaH9Ix1Dcpo5FfKZycaD8TKbmK95qXgpxF0tWRlewTEy2oDX7W4K'
ANON_KEY='jK9JqgpvjPxTqv3n3yGY8OS0gzGZsV7k3iExD64xSPMtOEuZnjNjTqzpFPw7aY9R'
SERVICE_ROLE_KEY='84LpexLeNdQQNndleA0GUQWqjqBbjdmRcW5BXuXv8uP6HlwTFitJ9aqzFQVzUSKi'

# Check for root
if [ "\$(id -u)" -ne 0 ]; then
  msg_error "This script must be run as root."
  exit 1
fi

# Check if CTID is in use
if pct status \${CTID} &>/dev/null; then
  msg_error "CT ID \${CTID} is already in use."
  exit 1
fi

msg_info "Starting Supabase LXC Container Setup..."

# Download LXC template
if [ ! -f "/var/lib/vz/template/cache/\${TEMPLATE_NAME}" ]; then
    msg_info "Downloading Ubuntu 22.04 LXC template..."
    wget -q --show-progress -O "/var/lib/vz/template/cache/\${TEMPLATE_FILE}" "\${URL}"
    # Check if download was successful
    if [ \$? -ne 0 ]; then
        msg_error "Failed to download LXC template."
        exit 1
    fi
    if [[ "\${TEMPLATE_FILE}" == *"-arm64"* ]]; then
        pct image unpack "/var/lib/vz/template/cache/\${TEMPLATE_FILE}" "/var/lib/vz/template/cache/\${TEMPLATE_NAME}"
    fi
    msg_ok "Template downloaded successfully."
else
    msg_ok "Ubuntu 22.04 LXC template already exists."
fi

msg_info "Creating LXC Container..."

pct create \${CTID} "/var/lib/vz/template/cache/\${TEMPLATE_NAME}" \\
  --hostname \${HOSTNAME} \\
  --password \${PASSWORD} \\
  --cores \${CORES} \\
  --memory \${RAM_SIZE} \\
  --net0 \${NETWORK_CONFIG} \\
  --onboot 1 \\
  --storage \${STORAGE} \\
  --rootfs \${STORAGE}:\${DISK_SIZE} \\
  --features nesting=1 \\
  --unprivileged 0 # Supabase with Docker needs a privileged container

if [ \$? -ne 0 ]; then
    msg_error "Failed to create LXC container."
    exit 1
fi
msg_ok "LXC Container created successfully."

msg_info "Starting LXC Container..."
pct start \${CTID}

msg_info "Waiting for container to be ready..."
sleep 5

msg_info "Installing Supabase inside the container..."
# Using a heredoc to run commands inside the LXC
pct exec \${CTID} -- bash <<EOF
# Update and install dependencies
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl git sudo

# Install Docker
msg_info "Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    msg_ok "Docker installed."
else
    msg_ok "Docker is already installed."
fi

# Install Docker Compose
msg_info "Installing Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    LATEST_COMPOSE=\$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep "tag_name" | cut -d'"' -f4)
    curl -L "https://github.com/docker/compose/releases/download/\${LATEST_COMPOSE}/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    msg_ok "Docker Compose installed."
else
    msg_ok "Docker Compose is already installed."
fi

# Clone Supabase
msg_info "Cloning Supabase repository..."
if [ ! -d "/opt/supabase" ]; then
    git clone --depth 1 https://github.com/supabase/supabase /opt/supabase
    msg_ok "Supabase repository cloned."
else
    msg_ok "Supabase repository already exists."
fi

cd /opt/supabase/docker

# Configure Supabase
msg_info "Configuring Supabase..."
cp .env.example .env

# Set secrets in .env file
// FIX: Escaped shell variables to prevent TypeScript interpolation.
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}|" .env
sed -i "s|^JWT_SECRET=.*|JWT_SECRET=\${JWT_SECRET}|" .env
sed -i "s|^ANON_KEY=.*|ANON_KEY=\${ANON_KEY}|" .env
sed -i "s|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=\${SERVICE_ROLE_KEY}|" .env
msg_ok "Supabase .env file configured."

# Start Supabase
msg_info "Starting Supabase with Docker Compose... (This may take a few minutes)"
docker-compose pull
docker-compose up -d

if [ \$? -eq 0 ]; then
    msg_ok "Supabase started successfully!"
else
    msg_error "Supabase failed to start. Check docker-compose logs in the container."
fi
EOF

msg_info "Installation script finished."

IP=\$(pct exec \${CTID} ip a s eth0 | awk '/inet / {print\$2}' | cut -d'/' -f1)

// FIX: Escaped shell variables to prevent TypeScript interpolation.
echo -e "\n\${GN}Supabase Installation Complete!\${CL}"
echo -e "Access your Supabase instance at:"
echo -e "  - API URL: \${BL}http://\${IP}:8000\${CL}"
echo -e "  - Supabase Studio: \${BL}http://\${IP}:3000\${CL}"
echo -e "\nYour keys and secrets are:"
echo -e "  - Postgres Password: \${YW}\${POSTGRES_PASSWORD}\${CL}"
echo -e "  - JWT Secret: \${YW}\${JWT_SECRET}\${CL}"
echo -e "  - Anon Key: \${YW}\${ANON_KEY}\${CL}"
echo -e "  - Service Role Key: \${YW}\${SERVICE_ROLE_KEY}\${CL}"
echo -e "\nIt might take a few minutes for all services to be fully available."
