#!/usr/bin/env bash
set -euo pipefail

# Colores ANSI
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color (reset)

# Versión específica de Docker
DOCKER_VERSION="5:28.0.4-1~ubuntu.$(lsb_release -rs)~$(lsb_release -cs)"

# ─────────────────────────────────────────────────────────────────────────────
# Cargar variables de entorno del .env (requiere que exista en el mismo directorio)
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f .env ]]; then
    set -a && source .env && set +a
else
    echo -e "${RED}ERROR: No se encontró el archivo .env. Crea uno.${NC}"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Crear docker-compose.yml si no existe
# ─────────────────────────────────────────────────────────────────────────────
if [[ ! -f docker-compose.yml ]]; then
    echo -e "${YELLOW}docker-compose.yml no encontrado. Creando archivo...${NC}"
    cat > docker-compose.yml <<'EOF'
services:
  evolution_api:
    container_name: evolution_api
    image: atendai/evolution-api:latest
    restart: always
    depends_on:
      - redis
      - postgres
    ports:
      - ${EVOLUTION_API_PORT}:8080
    volumes:
      - evolution_instances:/evolution/instances
    networks:
      - evolution-net
    env_file:
      - .env
    expose:
      - 8080
  redis:
    image: redis:latest
    restart: always
    networks:
      - evolution-net
    container_name: redis
    command: >
      redis-server --port 6379 --appendonly yes
    volumes:
      - evolution_redis:/data
    ports:
      - ${REDIS_PORT}:6379
  postgres:
    container_name: postgres
    image: postgres:15
    networks:
      - evolution-net
    command:
      ["postgres", "-c", "max_connections=1000", "-c", "listen_addresses=*"]
    restart: always
    ports:
      - ${POSTGRESS_PORT}:5432
    environment:
      - POSTGRES_USER=${POSTGRESS_USER}
      - POSTGRES_PASSWORD=${POSTGRESS_PASS}
      - POSTGRES_DB=evolution
      - POSTGRES_HOST_AUTH_METHOD=trust
    volumes:
      - postgres_data:/var/lib/postgresql/data
    expose:
      - 5432
volumes:
  evolution_instances:
  evolution_redis:
  postgres_data:
networks:
  evolution-net:
    name: evolution-net
    driver: bridge
EOF
    echo -e "${GREEN}docker-compose.yml creado exitosamente.${NC}"
else
    echo "docker-compose.yml ya existe."
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
    lsb-release \
    netcat-openbsd

# ─────────────────────────────────────────────────────────────────────────────
# Instalación de Docker versión 28.0.4 (si no está instalado)
# ─────────────────────────────────────────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker no encontrado. Instalando Docker ${DOCKER_VERSION}..."
    
    # Agregar repositorio oficial de Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
        sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" |
        sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    
    sudo apt update
    
    # Instalar versión específica
    sudo apt install -y \
        docker-ce="${DOCKER_VERSION}" \
        docker-ce-cli="${DOCKER_VERSION}" \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    
    # Prevenir actualizaciones automáticas
    sudo apt-mark hold docker-ce docker-ce-cli
    
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
    echo -e "${GREEN}Docker instalado: $(docker --version)${NC}"
else
    CURRENT_VERSION=$(docker --version)
    echo "Docker ya está instalado: ${CURRENT_VERSION}"
    
    # Verificar si es la versión correcta
    if [[ ! "${CURRENT_VERSION}" =~ "28.0.4" ]]; then
        echo -e "${YELLOW}Advertencia: La versión instalada no es 28.0.4. Considera actualizar o reinstalar.${NC}"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Verificar Docker Compose CLI plugin
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

        echo -e "Verificando acceso local a ${APP_NAME} (intento ${attempt}/${CHECK_APP_MAX_ATTEMPTS})..."

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
    echo -e "${YELLOW}Ejecuta 'sudo docker ps' y 'sudo docker logs evolution_api' para más información.${NC}"
}

check_local_port "${EVOLUTION_API_PORT}" "Evolution API"

# ─────────────────────────────────────────────────────────────────────────────
# Información final
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Instalación completada${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "Evolution API: http://localhost:${EVOLUTION_API_PORT}"
echo -e "Redis: localhost:${REDIS_PORT}"
echo -e "PostgreSQL: localhost:${POSTGRESS_PORT}"
echo -e "${YELLOW}Nota: Es posible que necesites cerrar sesión y volver a iniciarla para usar Docker sin sudo.${NC}"

# Refrescar grupos para la sesión actual (intento de activar grupo docker)
newgrp docker || true
