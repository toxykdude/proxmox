#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts
# Author: Based on tteck's template
# License: MIT
# Source: https://supabase.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y curl wget git nano htop net-tools ca-certificates gnupg lsb-release ufw
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
# Install Node.js
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
site_url = "http://localhost:3000"
additional_redirect_urls = ["https://localhost:3000"]
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

msg_info "Creating Systemd Service"
# Create systemd service for Supabase
cat <<EOF > /etc/systemd/system/supabase.service
[Unit]
Description=Supabase Local Development
After=docker.service
Requires=docker.service

[Service]
Type=forking
User=supabase
Group=supabase
WorkingDirectory=/home/supabase/supabase-project
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=/bin/bash -c 'supabase start'
ExecStop=/bin/bash -c 'supabase stop'
ExecReload=/bin/bash -c 'supabase stop && supabase start'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable supabase.service
msg_ok "Created Systemd Service"

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
sudo -u supabase supabase start

# Start the systemd service
systemctl start supabase.service

# Get container IP
CONTAINER_IP=$(hostname -I | awk '{print $1}')

msg_ok "Started Supabase Services"

msg_info "Creating Management Scripts"
# Create management scripts
sudo -u supabase cat <<EOF > /home/supabase/manage-supabase.sh
#!/bin/bash
# Supabase Management Script

case "\$1" in
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
        BACKUP_FILE="/home/supabase/backups/supabase_backup_\$(date +%Y%m%d_%H%M%S).sql"
        mkdir -p /home/supabase/backups
        docker exec supabase_db_supabase-project pg_dump -U postgres postgres > "\$BACKUP_FILE"
        echo "Backup created: \$BACKUP_FILE"
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
        echo "Usage: \$0 {start|stop|restart|status|logs|backup|info}"
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
sudo -u supabase cat <<EOF > /home/supabase/backup-cron.sh
#!/bin/bash
cd /home/supabase/supabase-project
docker exec supabase_db_supabase-project pg_dump -U postgres postgres > /home/supabase/backups/supabase_backup_\$(date +\%Y\%m\%d_\%H\%M\%S).sql
# Keep only last 7 backups
find /home/supabase/backups -name "supabase_backup_*.sql" -type f -mtime +7 -delete
EOF

chmod +x /home/supabase/backup-cron.sh
chown supabase:supabase /home/supabase/backup-cron.sh

# Add cron job (daily at 2 AM)
(sudo -u supabase crontab -l 2>/dev/null; echo "0 2 * * * /home/supabase/backup-cron.sh") | sudo -u supabase crontab -
msg_ok "Set up Backup Cron Job"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

# Final information display
echo -e "\n\n"
echo -e "${GREEN}=== Supabase Installation Complete ===${NC}"
echo -e "${BLUE}Container IP:${NC} ${CONTAINER_IP}"
echo -e "${BLUE}Studio URL:${NC} http://${CONTAINER_IP}:3000"
echo -e "${BLUE}API URL:${NC} http://${CONTAINER_IP}:54321"
echo -e "${BLUE}Database URL:${NC} postgresql://postgres:postgres@${CONTAINER_IP}:54322/postgres"
echo -e "\n${YELLOW}Management Commands:${NC}"
echo -e "  supabase-manage start    - Start Supabase"
echo -e "  supabase-manage stop     - Stop Supabase"
echo -e "  supabase-manage restart  - Restart Supabase"
echo -e "  supabase-manage status   - Show status"
echo -e "  supabase-manage logs     - View logs"
echo -e "  supabase-manage backup   - Create backup"
echo -e "  supabase-manage info     - Show connection info"
echo -e "\n${YELLOW}Important Files:${NC}"
echo -e "  Environment: /home/supabase/supabase-project/.env"
echo -e "  Config: /home/supabase/supabase-project/supabase/config.toml"
echo -e "  Backups: /home/supabase/backups/"
echo -e "\n${RED}Note:${NC} Initial startup may take several minutes while Docker images are downloaded."
echo -e "${RED}Note:${NC} Change default passwords in .env file for production use."
echo -e "\n"
