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
    
    # Verificar y aplicar configuración de AppArmor si es necesario
    if command -v apparmor_status >/dev/null 2>&1; then
        echo "  - AppArmor detectado, verificando configuración..."
        # Recargar perfiles de AppArmor para Docker
        sudo systemctl reload apparmor.service 2>/dev/null || true
    fi
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

# ─────────────────────────────────────────────────────────────────────────────
# Detener y limpiar contenedores existentes en caso de error previo
# ─────────────────────────────────────────────────────────────────────────────
cleanup_failed_containers() {
    echo "Verificando contenedores con errores..."
    
    # Detener contenedores que puedan estar en estado fallido
    if sudo docker ps -a --format '{{.Names}}' | grep -q "evolution"; then
        echo "  - Deteniendo contenedores Evolution existentes..."
        sudo docker compose -f "$SCRIPT_DIR/docker-compose.yml" down 2>/dev/null || true
        sleep 2
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Instalación de Evolution API (si no está instalado)
# ─────────────────────────────────────────────────────────────────────────────
if sudo docker ps --format '{{.Names}}' | grep -q "evolution_api"; then
    echo "Evolution API ya está ejecutándose."
else
    echo "Instalando Evolution API y servicios (corriendo docker-compose.yml) ..."
    echo "Directorio de trabajo: $SCRIPT_DIR"
    
    # Limpiar contenedores fallidos si existen
    cleanup_failed_containers
    
    # Ejecutar docker compose desde el directorio del script
    cd "$SCRIPT_DIR"
    
    echo "Iniciando servicios..."
    if sudo docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d; then
        echo -e "${GREEN}Evolution API y servicios instalados correctamente${NC}"
    else
        echo -e "${RED}Error al iniciar los servicios. Intentando con configuración alternativa...${NC}"
        
        # Reintentar con privilegios adicionales si falló
        echo "Reintentando instalación..."
        sudo docker compose -f "$SCRIPT_DIR/docker-compose.yml" down 2>/dev/null || true
        sleep 3
        
        if sudo docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d; then
            echo -e "${GREEN}Evolution API y servicios instalados correctamente${NC}"
        else
            echo -e "${RED}Error persistente al iniciar servicios.${NC}"
            echo "Verifica los logs con: sudo docker compose -f $SCRIPT_DIR/docker-compose.yml logs"
            exit 1
        fi
    fi
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
