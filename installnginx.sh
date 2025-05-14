#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo "[ERROR] Error occurred on line $LINENO" >&2; exit 1' ERR

# Variables
NPM_VERSION=""
NODE_VERSION="16.20.2"
PNPM_VERSION="8.15.0"
NVM_VERSION="0.39.7"
INSTALL_DIR="/opt/npm"
APP_USER="npmuser"

# Load helper functions
if [[ -f "$FUNCTIONS_FILE_PATH" ]]; then
  source "$FUNCTIONS_FILE_PATH"
else
  echo "[ERROR] Required functions file missing" >&2
  exit 1
fi

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Creating non-root user"
useradd -r -s /usr/sbin/nologin $APP_USER || true
msg_ok "User created"

msg_info "Installing dependencies"
$STD apt-get update
$STD apt-get -y install gnupg ca-certificates apache2-utils logrotate build-essential git curl
msg_ok "Dependencies installed"

msg_info "Installing Python dependencies"
$STD apt-get install -y python3 python3-dev python3-pip python3-venv python3-cffi
$STD python3 -m venv /opt/certbot/
source /opt/certbot/bin/activate
pip install --no-cache-dir certbot-dns-multi certbot certbot-dns-cloudflare
msg_ok "Python dependencies installed"

msg_info "Installing OpenResty"
curl --retry 5 --retry-delay 2 -fsSL https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/openresty.gpg
echo "deb http://openresty.org/package/debian $(lsb_release -cs) openresty" > /etc/apt/sources.list.d/openresty.list
$STD apt-get update
$STD apt-get install -y openresty
msg_ok "OpenResty installed"

msg_info "Installing Node.js via NVM"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v$NVM_VERSION/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install $NODE_VERSION
nvm use $NODE_VERSION
msg_ok "Node.js $NODE_VERSION installed"

msg_info "Installing pnpm"
npm install -g pnpm@$PNPM_VERSION
msg_ok "pnpm installed"

msg_info "Downloading Nginx Proxy Manager"
RELEASE=$(curl -fsSL https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest | jq -r .tag_name)
read -r -p "Install older version (v2.10.4)? <y/N>: " prompt
case "${prompt,,}" in
  y|yes)
    NPM_VERSION="2.10.4";;
  *)
    NPM_VERSION="${RELEASE#v}";;
esac

curl -fsSL "https://codeload.github.com/NginxProxyManager/nginx-proxy-manager/tar.gz/v$NPM_VERSION" | tar -xz -C /tmp
cd "/tmp/nginx-proxy-manager-$NPM_VERSION"
msg_ok "NPM v$NPM_VERSION downloaded"

msg_info "Setting up environment"
mkdir -p /app /data
cp -r backend/* /app
cp -r global/* /app/global
cp -r docker/rootfs/etc/nginx /etc/
cp -r docker/rootfs/var/www/html /var/www/
cp docker/rootfs/etc/letsencrypt.ini /etc/
cp docker/rootfs/etc/logrotate.d/nginx-proxy-manager /etc/logrotate.d/

mkdir -p /tmp/nginx/body /run/nginx /data/{nginx,custom_ssl,logs,access} \
  /data/nginx/{default_host,default_www,proxy_host,redirection_host,stream,dead_host,temp} \
  /var/lib/nginx/cache/{public,private} /var/cache/nginx/proxy_temp

chmod -R 750 /var/cache/nginx
chown -R $APP_USER:$APP_USER /var/cache/nginx /data /app

# Dummy cert creation
if [[ ! -f /data/nginx/dummycert.pem || ! -f /data/nginx/dummykey.pem ]]; then
  openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
    -subj "/O=NPM/OU=Dummy/CN=localhost" \
    -keyout /data/nginx/dummykey.pem -out /data/nginx/dummycert.pem
fi

# Build frontend
msg_info "Building frontend"
cd frontend
pnpm install
pnpm run build
cp -r dist/* /app/frontend
cp -r app-images/* /app/frontend/images
msg_ok "Frontend built"

# Backend
msg_info "Initializing backend"
rm -f /app/config/default.json
cat <<EOF > /app/config/production.json
{
  "database": {
    "engine": "knex-native",
    "knex": {
      "client": "sqlite3",
      "connection": {
        "filename": "/data/database.sqlite"
      }
    }
  }
}
EOF
cd /app
pnpm install
msg_ok "Backend initialized"

# Create systemd service
msg_info "Creating systemd service"
cat <<EOF > /etc/systemd/system/npm.service
[Unit]
Description=Nginx Proxy Manager
After=network.target

[Service]
Type=simple
User=$APP_USER
Environment=NODE_ENV=production
WorkingDirectory=/app
ExecStart=/root/.nvm/versions/node/v$NODE_VERSION/bin/node index.js
Restart=on-failure

# Security
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=yes
PrivateTmp=true
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Service created"

systemctl daemon-reexec
systemctl enable --now openresty
systemctl enable --now npm
msg_ok "Services started"

msg_info "Cleaning up"
rm -rf "/tmp/nginx-proxy-manager-$NPM_VERSION"
$STD apt-get autoremove -y
$STD apt-get autoclean -y
msg_ok "Cleanup done"
