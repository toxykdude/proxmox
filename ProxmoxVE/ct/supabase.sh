#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts
# Author: Based on tteck's community-scripts template
# License: MIT
# Source: https://supabase.com/

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Override default setting
function header_info {
cat <<"EOF"
   _____                  __                    
  / ___/__  ______  ____ / /_  ____ __________ 
  \__ \/ / / / __ \/ __ `/ __ \/ __ `/ ___/ _ \
 ___/ / /_/ / /_/ / /_/ / /_/ / /_/ (__  )  __/
/____/\__,_/ .___/\__,_/_.___/\__,_/____/\___/ 
          /_/                                  

EOF
}
header_info
echo -e "Loading..."

# App Variable(s)
APP="Supabase"
var_cpu="2"
var_ram="4096"
var_disk="8"
var_os="ubuntu"
var_version="22.04"
var_unprivileged="1"

# App Output & Base Settings
header_info
echo -e "${GN}${APP} LXC${CL}"
echo -e "${BL}[INFO]${GN} This script will create a new ${APP} LXC Container${CL}"
echo -e "${BL}[INFO]${YW} Container will be configured with Docker and all Supabase services${CL}"

# Use this function to set variables in the container
variables
color
catch_errors

# Use this function to install the app (runs in the container)
function install_app() {
    msg_info "Installing Dependencies"
    $STD apt-get update
    $STD apt-get install -y \
        curl \
        wget \
        git \
        nano \
        htop \
        net-tools \
        ca-certificates \
        gnupg \
        lsb-release \
        ufw \
        software-properties-common \
        apt-transport-https
    msg_ok "Installed Dependencies"

    msg_info "Installing Docker"
    # Add Docker's official GPG key
    $STD mkdir -m 0755 -p /etc/apt/keyrings
    $STD curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    $STD chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    $STD apt-get update
    $STD apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    msg_ok "Installed Docker"

    msg_info "Creating Supabase User"
    # Create dedicated user for Supabase
    useradd -m -s /bin/bash -G docker supabase
    echo "supabase:$(openssl rand -base64 32)" | chpasswd

    # Set up sudo access
    echo "supabase ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/supabase
    msg_ok "Created Supabase User"

    msg_info "Installing Node.js and Supabase CLI"
    # Install Node.js 20.x
    $STD curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    $STD apt-get install -y nodejs

    # Install Supabase CLI
    $STD npm install -g supabase@latest
    msg_ok "Installed Node.js and Supabase CLI"

    msg_info "Setting up Supabase Project"
    # Create project directory
    sudo -u supabase mkdir -p /home/supabase/supabase-project
    cd /home/supabase/supabase-project

    # Initialize Supabase project as supabase user
    sudo -u supabase supabase init --workdir /home/supabase/supabase-project

    # Generate secure secrets
    POSTGRES_PASSWORD=$(openssl rand -base64 32)
    JWT_SECRET=$(openssl rand -base64 64)
    ANON_KEY=$(openssl rand -base64 32)
    SERVICE_ROLE_KEY=$(openssl rand -base64 32)

    # Create environment file
    sudo -u supabase cat <<EOF > /home/supabase/supabase-project/.env
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
JWT_SECRET=${JWT_SECRET}
ANON_KEY=${ANON_KEY}
SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}
EOF

    # Set proper permissions
    chown -R supabase:supabase /home/supabase/supabase-project
    chmod 600 /home/supabase/supabase-project/.env
    msg_ok "Set up Supabase Project"

    msg_info "Configuring Supabase Services"
    # Get container IP for configuration
    CONTAINER_IP=$(hostname -I | awk '{print $1}')
    
    # Update Supabase config for network access
    sudo -u supabase cat <<EOF > /home/supabase/supabase-project/supabase/config.toml
# A string used to distinguish different Supabase projects on the same host.
project_id = "supabase-project"

[api]
enabled = true
port = 54321
schemas = ["public", "graphql_public"]
extra_search_path = ["public", "extensions"]
max_rows = 1000

[db]
port = 54322
shadow_port = 54320
major_version = 15

[studio]
enabled = true
port = 3000
api_url = "http://0.0.0.0:54321"

[inbucket]
enabled = true
port = 54324
api_port = 54323
smtp_port = 54325

[storage]
enabled = true
file_size_limit = "50MiB"
buckets = []

[auth]
enabled = true
site_url = "http://${CONTAINER_IP}:3000"
additional_redirect_urls = ["http://${CONTAINER_IP}:3000", "http://localhost:3000"]
jwt_expiry = 3600
enable_signup = true
enable_email_confirmations = false
enable_sms_confirmations = false
enable_phone_signup = false

[edge_functions]
enabled = true
inspector_port = 8083

[analytics]
enabled = false
EOF

    # Set ownership
    chown supabase:supabase /home/supabase/supabase-project/supabase/config.toml
    msg_ok "Configured Supabase Services"

    msg_info "Creating Management Scripts"
    # Create management scripts
    sudo -u supabase cat <<'EOF' > /home/supabase/manage-supabase.sh
#!/bin/bash
# Supabase Management Script

CONTAINER_IP=$(hostname -I | awk '{print $1}')

case "$1" in
    start)
        echo "Starting Supabase..."
        cd /home/supabase/supabase-project && supabase start
        ;;
    stop)
        echo "Stopping Supabase..."
        cd /home/supabase/supabase-project && supabase stop
        ;;
    restart)
        echo "Restarting Supabase..."
        cd /home/supabase/supabase-project && supabase stop && supabase start
        ;;
    status)
        echo "Supabase Status:"
        cd /home/supabase/supabase-project && supabase status
        ;;
    logs)
        echo "Supabase Logs:"
        docker logs supabase_studio_supabase-project 2>/dev/null || echo "Studio logs not available"
        docker logs supabase_db_supabase-project 2>/dev/null || echo "Database logs not available"
        ;;
    backup)
        echo "Creating backup..."
        BACKUP_FILE="/home/supabase/backups/supabase_backup_$(date +%Y%m%d_%H%M%S).sql"
        mkdir -p /home/supabase/backups
        docker exec supabase_db_supabase-project pg_dump -U postgres postgres > "$BACKUP_FILE"
        echo "Backup created: $BACKUP_FILE"
        ;;
    info)
        echo "=== Supabase Information ==="
        echo "Studio URL: http://${CONTAINER_IP}:3000"
        echo "API URL: http://${CONTAINER_IP}:54321"
        echo "Database URL: postgresql://postgres:postgres@${CONTAINER_IP}:54322/postgres"
        echo ""
        echo "Environment file: /home/supabase/supabase-project/.env"
        echo "Config file: /home/supabase/supabase-project/supabase/config.toml"
        echo ""
        cd /home/supabase/supabase-project && supabase status 2>/dev/null || echo "Supabase is not running"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|backup|info}"
        exit 1
        ;;
esac
EOF

    chmod +x /home/supabase/manage-supabase.sh
    chown supabase:supabase /home/supabase/manage-supabase.sh

    # Create root symlink for easy access
    ln -sf /home/supabase/manage-supabase.sh /usr/local/bin/supabase-manage
    msg_ok "Created Management Scripts"

    msg_info "Setting up Backup Cron Job"
    # Set up automated daily backup
    sudo -u supabase mkdir -p /home/supabase/backups
    sudo -u supabase cat <<'EOF' > /home/supabase/backup-cron.sh
#!/bin/bash
cd /home/supabase/supabase-project
docker exec supabase_db_supabase-project pg_dump -U postgres postgres > /home/supabase/backups/supabase_backup_$(date +%Y%m%d_%H%M%S).sql
# Keep only last 7 backups
find /home/supabase/backups -name "supabase_backup_*.sql" -type f -mtime +7 -delete
EOF

    chmod +x /home/supabase/backup-cron.sh
    chown supabase:supabase /home/supabase/backup-cron.sh

    # Add cron job (daily at 2 AM)
    (sudo -u supabase crontab -l 2>/dev/null; echo "0 2 * * * /home/supabase/backup-cron.sh") | sudo -u supabase crontab -
    msg_ok "Set up Backup Cron Job"

    msg_info "Configuring Firewall"
    # Configure UFW firewall
    ufw --force enable

    # Allow SSH
    ufw allow 22/tcp

    # Allow Supabase services
    ufw allow 3000/tcp     # Studio
    ufw allow 54321/tcp    # API
    ufw allow 54322/tcp    # Database
    ufw allow 54323/tcp    # Auth
    ufw allow 54324/tcp    # Realtime/Inbucket
    ufw allow 54325/tcp    # Storage/SMTP

    msg_ok "Configured Firewall"

    msg_info "Starting Supabase Services"
    # Start Supabase (this will download Docker images)
    cd /home/supabase/supabase-project
    
    # Pre-pull images to speed up first start
    sudo -u supabase docker pull supabase/postgres:15.1.0.147
    sudo -u supabase docker pull postgrest/postgrest:v12.0.1
    sudo -u supabase docker pull supabase/gotrue:v2.132.3
    sudo -u supabase docker pull supabase/realtime:v2.25.50
    sudo -u supabase docker pull supabase/storage-api:v0.46.4
    sudo -u supabase docker pull supabase/studio:20240422-5cf8f30

    # Start Supabase services
    sudo -u supabase supabase start

    msg_ok "Started Supabase Services"

    msg_info "Creating Systemd Service"
    # Create systemd service for Supabase
    cat <<EOF > /etc/systemd/system/supabase.service
[Unit]
Description=Supabase Local Development
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=supabase
Group=supabase
WorkingDirectory=/home/supabase/supabase-project
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=/bin/bash -c 'supabase start'
ExecStop=/bin/bash -c 'supabase stop'
ExecReload=/bin/bash -c 'supabase stop && supabase start'

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable supabase.service
    msg_ok "Created Systemd Service"

    # Get final container IP and connection info
    CONTAINER_IP=$(hostname -I | awk '{print $1}')
    
    # Create welcome message
    cat <<EOF > /etc/motd

=== Supabase Container ===
Container IP: ${CONTAINER_IP}

🌐 Web Interfaces:
Studio: http://${CONTAINER_IP}:3000
API: http://${CONTAINER_IP}:54321

📊 Database:
URL: postgresql://postgres:postgres@${CONTAINER_IP}:54322/postgres

🔧 Management Commands:
supabase-manage start    - Start Supabase
supabase-manage stop     - Stop Supabase  
supabase-manage restart  - Restart Supabase
supabase-manage status   - Show status
supabase-manage logs     - View logs
supabase-manage backup   - Create backup
supabase-manage info     - Show connection info

📁 Important Files:
Environment: /home/supabase/supabase-project/.env
Config: /home/supabase/supabase-project/supabase/config.toml
Backups: /home/supabase/backups/

For more information: https://supabase.com/docs

EOF

    msg_info "Customizing Container"
    # Create app data path  
    mkdir -p /opt/supabase
    echo "${CONTAINER_IP}" > /opt/supabase/container_ip
    echo "Supabase configured successfully!" > /opt/supabase/install.log
    msg_ok "Customized Container"
}

# This starts the builds script
start
