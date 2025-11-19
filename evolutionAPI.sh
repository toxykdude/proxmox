#!/usr/bin/env bash
set -euo pipefail

# Colores ANSI
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color (reset)

# ─────────────────────────────────────────────────────────────────────────────
# Cargar variables de entorno del .env (requiere que exista en el mismo directorio)
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f .env ]]; then
    set -a && source .env && set +a
else
    echo "ERROR: No se encontró el archivo .env. Crea uno."
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Actualizar repositorios y paquetes
# ─────────────────────────────────────────────────────────────────────────────
sudo apt update

# ─────────────────────────────────────────────────────────────────────────────
# Instalar prerequisitos (si faltan)
# ─────────────────────────────────────────────────────────────────────────────
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# ─────────────────────────────────────────────────────────────────────────────
# Instalación de Docker (si no está instalado)
# ─────────────────────────────────────────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker no encontrado. Instalando Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
        sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" |
        sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
    echo -e "${GREEN}Docker instalado: $(docker --version)${NC}"
else
    echo "Docker ya está instalado: $(docker --version)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Instalación de Docker Compose CLI plugin (si no está instalado)
# ─────────────────────────────────────────────────────────────────────────────
if ! docker compose version >/dev/null 2>&1; then
    echo "Docker Compose CLI plugin no encontrado. Instalando..."
    sudo apt-get install -y docker-compose-plugin
    echo -e "${GREEN}Docker Compose instalado: $(docker compose version)${NC}"
else
    echo "Docker Compose ya está instalado: $(docker compose version)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Instalación de Evolution API (si no está instalado)
# ─────────────────────────────────────────────────────────────────────────────
if sudo docker ps -a --format '{{.Names}}' | grep -q "evolution_api"; then
    echo "Evolution API ya está instalado y configurado."
else
    echo "Instalando Evolution API y servicios (corriendo docker-compose.yml) ..."
    sudo docker compose up -d

    echo -e "${GREEN}Evolution API y servicios instalados${NC}"
fi

CHECK_APP_MAX_ATTEMPTS=5
CHECK_APP_DELAY_SECONDS=5

# Función para validar que un puerto esté accesible localmente
# Recibe Puerto y Nombre de la Aplicación
# Realiza hasta CHECK_APP_MAX_ATTEMPTS intentos con CHECK_APP_DELAY_SECONDS segundos de delay. 
# Si tras CHECK_APP_MAX_ATTEMPTS fallos, muestra error y termina.
check_local_port() {
    local PORT=$1
    local APP_NAME=$2
    local attempt=1

    while ((attempt <= CHECK_APP_MAX_ATTEMPTS)); do

        echo -e "Verificando acceso local a ${APP_NAME} . . . "

        sleep ${CHECK_APP_DELAY_SECONDS}
        
        # Verificar respuesta local (localhost/127.0.0.1)
        if nc -z -w5 127.0.0.1 "${PORT}"; then
            echo -e "${GREEN}¡Instalación completada! ${APP_NAME} funcionando localmente en: http://localhost:${PORT}${NC}"
            return 0
        fi
        attempt=$((attempt + 1))
    done

    # Si llegamos aquí, todos los intentos fallaron
    echo -e "${RED}Error: El puerto ${PORT} para ${APP_NAME} no es accesible localmente en localhost:${PORT}. Verifica que el contenedor esté ejecutándose correctamente.${NC}"
}

check_local_port "${EVOLUTION_API_PORT}" "Evolution API"

# Refrescar grupos para la sesión actual
newgrp docker
