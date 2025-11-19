#!/usr/bin/env bash
set -euo pipefail

# Colores ANSI
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color (reset)

# Espacio mínimo requerido en GB
MIN_SPACE_GB=5

# ─────────────────────────────────────────────────────────────────────────────
# Verificar espacio en disco disponible
# ─────────────────────────────────────────────────────────────────────────────
check_disk_space() {
    echo "Verificando espacio en disco..."
    
    # Obtener espacio disponible en GB en /var/lib
    AVAILABLE_SPACE=$(df -BG /var/lib | tail -1 | awk '{print $4}' | sed 's/G//')
    
    echo "Espacio disponible en /var/lib: ${AVAILABLE_SPACE}GB"
    
    if [ "$AVAILABLE_SPACE" -lt "$MIN_SPACE_GB" ]; then
        echo -e "${YELLOW}⚠️  Espacio en disco bajo (${AVAILABLE_SPACE}GB disponibles, se requieren al menos ${MIN_SPACE_GB}GB)${NC}"
        echo "Intentando liberar espacio..."
        
        # Limpiar recursos de Docker
        clean_docker_resources
        
        # Verificar nuevamente
        AVAILABLE_SPACE=$(df -BG /var/lib | tail -1 | awk '{print $4}' | sed 's/G//')
        echo "Espacio disponible después de limpieza: ${AVAILABLE_SPACE}GB"
        
        if [ "$AVAILABLE_SPACE" -lt "$MIN_SPACE_GB" ]; then
            echo -e "${RED}ERROR: Espacio insuficiente incluso después de la limpieza.${NC}"
            echo "Opciones:"
            echo "  1. Libera espacio manualmente con: sudo apt clean && sudo apt autoremove"
            echo "  2. Aumenta el tamaño del disco de tu servidor"
            echo "  3. Elimina archivos innecesarios"
            exit 1
        fi
    else
        echo -e "${GREEN}✓ Espacio en disco suficiente${NC}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Limpiar recursos de Docker para liberar espacio
# ─────────────────────────────────────────────────────────────────────────────
clean_docker_resources() {
    echo "Limpiando recursos de Docker..."
    
    if command -v docker >/dev/null 2>&1; then
        # Eliminar contenedores detenidos
        echo "  - Eliminando contenedores detenidos..."
        sudo docker container prune -f || true
        
        # Eliminar imágenes sin usar
        echo "  - Eliminando imágenes sin usar..."
        sudo docker image prune -a -f || true
        
        # Eliminar volúmenes sin usar
        echo "  - Eliminando volúmenes sin usar..."
        sudo docker volume prune -f || true
        
        # Eliminar redes sin usar
        echo "  - Eliminando redes sin usar..."
        sudo docker network prune -f || true
        
        # Limpieza completa del sistema
        echo "  - Limpieza completa del sistema Docker..."
        sudo docker system prune -a -f --volumes || true
        
        echo -e "${GREEN}✓ Limpieza de Docker completada${NC}"
    fi
    
    # Limpiar caché de APT
    echo "  - Limpiando caché de APT..."
    sudo apt clean || true
    sudo apt autoremove -y || true
    
    echo -e "${GREEN}✓ Limpieza del sistema completada${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Determinar el directorio del script
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# Configurar permisos del sistema para contenedores
# ─────────────────────────────────────────────────────────────────────────────
configure_system_permissions() {
    echo "Configurando permisos del sistema para contenedores..."
    
    # Permitir que contenedores usen puertos no privilegiados (< 1024)
    if [ -f /proc/sys/net/ipv4/ip_unprivileged_port_start ]; then
        CURRENT_PORT=$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start)
        echo "  - Puerto no privilegiado actual: $CURRENT_PORT"
        
        # Establecer en 0 para permitir todos los puertos
        sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0
        
        # Hacer el cambio permanente
        if ! grep -q "net.ipv4.ip_unprivileged_port_start" /etc/sysctl.conf; then
            echo "net.ipv4.ip_unprivileged_port_start=0" | sudo tee -a /etc/sysctl.conf
        else
            sudo sed -i 's/^net.ipv4.ip_unprivileged_port_start=.*/net.ipv4.ip_unprivileged_port_start=0/' /etc/sysctl.conf
        fi
        
        echo -e "${GREEN}✓ Permisos de puertos configurados${NC}"
    fi
    
    # Configurar AppArmor para Docker si está presente
    if command -v apparmor_status >/dev/null 2>&1; then
        echo "  - AppArmor detectado, configurando para Docker..."
        
        # Verificar si el perfil docker-default existe
        if [ -f /etc/apparmor.d/docker ]; then
            sudo apparmor_parser -r /etc/apparmor.d/docker 2>/dev/null || true
        fi
        
        # Recargar perfiles de AppArmor
        sudo systemctl reload apparmor.service 2>/dev/null || true
        
        # Verificar el estado
        if sudo aa-status 2>/dev/null | grep -q "docker"; then
            echo -e "${GREEN}  ✓ AppArmor configurado${NC}"
        else
            echo -e "${YELLOW}  ⚠ AppArmor puede estar causando problemas${NC}"
            echo "  Intentando poner Docker en modo complain..."
            sudo aa-complain /etc/apparmor.d/docker 2>/dev/null || true
        fi
    fi
    
    # Reiniciar Docker para aplicar cambios
    echo "  - Reiniciando servicio Docker..."
    sudo systemctl restart docker
    sleep 3
    echo -e "${GREEN}✓ Docker reiniciado${NC}"
}

# Verificar espacio en disco antes de comenzar
check_disk_space

# Configurar permisos del sistema
configure_system_permissions

# ─────────────────────────────────────────────────────────────────────────────
# Cargar variables de entorno del .env (requiere que exista en el mismo directorio)
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a && source "$SCRIPT_DIR/.env" && set +a
    echo -e "${GREEN}Archivo .env cargado correctamente desde: $SCRIPT_DIR/.env${NC}"
else
    echo -e "${RED}ERROR: No se encontró el archivo .env en: $SCRIPT_DIR${NC}"
    echo "Por favor, crea un archivo .env en el mismo directorio que este script."
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
# Verificar que exista docker-compose.yml
# ─────────────────────────────────────────────────────────────────────────────
if [[ ! -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
    echo -e "${RED}ERROR: No se encontró el archivo docker-compose.yml en: $SCRIPT_DIR${NC}"
    echo "Por favor, asegúrate de tener el archivo docker-compose.yml en el mismo directorio que este script."
    exit 1
fi

echo -e "${GREEN}✓ docker-compose.yml encontrado${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# Crear docker-compose modificado para evitar errores de sysctls
# ─────────────────────────────────────────────────────────────────────────────
create_fixed_compose() {
    echo "Creando configuración de Docker Compose optimizada..."
    
    # Crear backup si no existe
    if [[ ! -f "$SCRIPT_DIR/docker-compose.yml.original" ]]; then
        cp "$SCRIPT_DIR/docker-compose.yml" "$SCRIPT_DIR/docker-compose.yml.original"
        echo "  - Backup creado: docker-compose.yml.original"
    fi
    
    # Crear versión modificada con cap_add y privileged para evolution_api
    cat > "$SCRIPT_DIR/docker-compose.yml" <<'EOF'
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
    cap_add:
      - NET_ADMIN
      - SYS_ADMIN
    security_opt:
      - apparmor=unconfined
    privileged: true
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
    
    echo -e "${GREEN}✓ Docker Compose configurado con permisos necesarios${NC}"
}

create_fixed_compose

# ─────────────────────────────────────────────────────────────────────────────
# Detener y limpiar contenedores existentes en caso de error previo
# ─────────────────────────────────────────────────────────────────────────────
cleanup_failed_containers() {
    echo "Limpiando contenedores con errores..."
    
    # Detener contenedores que puedan estar en estado fallido
    if sudo docker ps -a --format '{{.Names}}' | grep -E "(evolution|redis|postgres)" >/dev/null 2>&1; then
        echo "  - Deteniendo contenedores existentes..."
        sudo docker compose -f "$SCRIPT_DIR/docker-compose.yml" down -v 2>/dev/null || true
        sleep 3
        
        # Forzar eliminación de contenedores que no se detuvieron
        for container in $(sudo docker ps -a --format '{{.Names}}' | grep -E "(evolution|redis|postgres)"); do
            echo "  - Eliminando contenedor: $container"
            sudo docker rm -f "$container" 2>/dev/null || true
        done
        
        sleep 2
    fi
    
    # Limpiar redes que puedan estar en conflicto
    if sudo docker network ls | grep -q "evolution-net"; then
        echo "  - Eliminando red evolution-net..."
        sudo docker network rm evolution-net 2>/dev/null || true
    fi
    
    # Limpiar volúmenes huérfanos
    echo "  - Limpiando volúmenes..."
    sudo docker volume prune -f >/dev/null 2>&1 || true
}

# ─────────────────────────────────────────────────────────────────────────────
# Instalación de Evolution API
# ─────────────────────────────────────────────────────────────────────────────
if sudo docker ps --format '{{.Names}}' | grep -q "evolution_api"; then
    echo "Evolution API ya está ejecutándose."
else
    echo "Instalando Evolution API y servicios..."
    echo "Directorio de trabajo: $SCRIPT_DIR"
    
    # Limpiar contenedores fallidos si existen
    cleanup_failed_containers
    
    # Ejecutar docker compose desde el directorio del script
    cd "$SCRIPT_DIR"
    
    echo ""
    echo "Iniciando servicios con Docker Compose..."
    echo "Esto puede tardar algunos minutos mientras se descargan las imágenes..."
    echo ""
    
    # Pull de las imágenes primero para mejor diagnóstico
    echo "Descargando imágenes de Docker..."
    sudo docker compose -f "$SCRIPT_DIR/docker-compose.yml" pull
    
    echo ""
    echo "Iniciando contenedores..."
    
    # Intentar iniciar con docker compose
    if sudo docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d; then
        echo -e "${GREEN}✓ Servicios iniciados correctamente${NC}"
    else
        echo -e "${RED}✗ Error al iniciar servicios${NC}"
        echo ""
        echo "Mostrando logs de los contenedores:"
        sudo docker compose -f "$SCRIPT_DIR/docker-compose.yml" logs --tail=50
        echo ""
        echo -e "${YELLOW}Intentando diagnóstico adicional...${NC}"
        
        # Verificar estado de contenedores
        echo "Estado de contenedores:"
        sudo docker ps -a | grep -E "(evolution|redis|postgres|CONTAINER)"
        
        exit 1
    fi
fi

CHECK_APP_MAX_ATTEMPTS=12
CHECK_APP_DELAY_SECONDS=5

# Función para validar que un puerto esté accesible localmente
# Recibe Puerto y Nombre de la Aplicación
# Realiza hasta CHECK_APP_MAX_ATTEMPTS intentos con CHECK_APP_DELAY_SECONDS segundos de delay. 
check_local_port() {
    local PORT=$1
    local APP_NAME=$2
    local attempt=1

    echo "Esperando a que ${APP_NAME} esté listo..."

    while ((attempt <= CHECK_APP_MAX_ATTEMPTS)); do
        echo -e "  Intento ${attempt}/${CHECK_APP_MAX_ATTEMPTS}: Verificando acceso local a ${APP_NAME}..."

        # Verificar si el contenedor está corriendo
        if sudo docker ps --format '{{.Names}}' | grep -q "evolution"; then
            # Verificar respuesta local (localhost/127.0.0.1)
            if nc -z -w5 127.0.0.1 "${PORT}" 2>/dev/null; then
                echo -e "${GREEN}✓ ¡Instalación completada! ${APP_NAME} funcionando localmente en: http://localhost:${PORT}${NC}"
                return 0
            elif curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${PORT}" 2>/dev/null | grep -q "[2-5][0-9][0-9]"; then
                echo -e "${GREEN}✓ ¡Instalación completada! ${APP_NAME} funcionando localmente en: http://localhost:${PORT}${NC}"
                return 0
            else
                echo "    Puerto aún no disponible, esperando..."
            fi
        else
            echo -e "${YELLOW}    Contenedor aún no está corriendo, esperando...${NC}"
        fi
        
        sleep ${CHECK_APP_DELAY_SECONDS}
        attempt=$((attempt + 1))
    done

    # Si llegamos aquí, todos los intentos fallaron
    echo -e "${RED}✗ Error: El puerto ${PORT} para ${APP_NAME} no es accesible después de ${CHECK_APP_MAX_ATTEMPTS} intentos.${NC}"
    echo ""
    echo "Diagnóstico:"
    echo "1. Estado de los contenedores:"
    sudo docker ps -a | grep -E "(CONTAINER|evolution)"
    echo ""
    echo "2. Logs recientes de Evolution API:"
    sudo docker compose -f "$SCRIPT_DIR/docker-compose.yml" logs --tail=30 2>/dev/null || echo "   No se pudieron obtener los logs"
    echo ""
    echo "3. Puertos en uso:"
    sudo netstat -tlnp | grep ":${PORT}" || sudo ss -tlnp | grep ":${PORT}" || echo "   Puerto ${PORT} no está en uso"
    echo ""
    echo "Para más detalles, ejecuta:"
    echo "  sudo docker compose -f $SCRIPT_DIR/docker-compose.yml logs -f"
    
    return 1
}

# Verificar disponibilidad del puerto
if check_local_port "${EVOLUTION_API_PORT}" "Evolution API"; then
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}   Instalación completada exitosamente${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Accede a Evolution API en: http://localhost:${EVOLUTION_API_PORT}"
    echo ""
    echo "Comandos útiles:"
    echo "  - Ver logs: sudo docker compose -f $SCRIPT_DIR/docker-compose.yml logs -f"
    echo "  - Detener servicios: sudo docker compose -f $SCRIPT_DIR/docker-compose.yml down"
    echo "  - Reiniciar servicios: sudo docker compose -f $SCRIPT_DIR/docker-compose.yml restart"
else
    echo -e "\n${YELLOW}========================================${NC}"
    echo -e "${YELLOW}   Instalación completada con warnings${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo "Los servicios fueron instalados pero no responden aún en el puerto esperado."
    echo "Esto puede ser normal si los contenedores necesitan más tiempo para iniciar."
    echo ""
    echo "Verifica el estado con:"
    echo "  sudo docker compose -f $SCRIPT_DIR/docker-compose.yml ps"
    echo "  sudo docker compose -f $SCRIPT_DIR/docker-compose.yml logs -f"
fi

# Refrescar grupos para la sesión actual
newgrp docker
