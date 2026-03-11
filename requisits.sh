#!/bin/bash
# prereqs.sh — Instala Docker + Docker Compose y verifica puerto 9100
# Compatible con: Ubuntu 20/22/24, Amazon Linux 2, Amazon Linux 2023
# Uso: curl -O https://raw.githubusercontent.com/ArielLorusso/node-exporter_metrics/refs/heads/main/prereqs.sh && chmod +x prereqs.sh && ./prereqs.sh

set -e  # detener si cualquier comando falla

# ─── Colores ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ok()   { echo -e "${GREEN}✔ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
info() { echo -e "${BLUE}ℹ $1${NC}"; }
err()  { echo -e "${RED}✘ $1${NC}"; }

echo ""
echo "══════════════════════════════════════════════════════"
echo "  prereqs.sh — Node Exporter Docker Setup"
echo "══════════════════════════════════════════════════════"
echo ""

# ─── Detectar distro ────────────────────────────────────────────────────────
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

DISTRO=$(detect_distro)
info "Distro detectada: $DISTRO"

# ─── 1. Docker ──────────────────────────────────────────────────────────────
echo ""
echo "── 1. Verificando Docker ───────────────────────────────"

if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
    ok "Docker ya instalado: v$DOCKER_VERSION"
else
    warn "Docker no encontrado. Instalando..."

    case "$DISTRO" in
        ubuntu|debian)
            sudo apt-get update -qq
            sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
                sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
                https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
                sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update -qq
            sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        amzn)
            # Detectar Amazon Linux 2 vs 2023
            if grep -q "Amazon Linux 2023" /etc/os-release 2>/dev/null; then
                info "Amazon Linux 2023 detectado"
                sudo dnf install -y docker
                sudo systemctl enable --now docker
                # Compose plugin para AL2023
                COMPOSE_VERSION="v2.24.5"
                sudo mkdir -p /usr/local/lib/docker/cli-plugins
                sudo curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
                    -o /usr/local/lib/docker/cli-plugins/docker-compose
                sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
            else
                info "Amazon Linux 2 detectado"
                sudo amazon-linux-extras install docker -y
                sudo systemctl enable --now docker
                # Compose para AL2
                sudo curl -fsSL "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-linux-x86_64" \
                    -o /usr/local/bin/docker-compose
                sudo chmod +x /usr/local/bin/docker-compose
            fi
            ;;
        *)
            err "Distro '$DISTRO' no soportada automáticamente."
            err "Instalá Docker manualmente: https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac

    ok "Docker instalado correctamente"
fi

# ─── 2. Agregar usuario al grupo docker ─────────────────────────────────────
if ! groups "$USER" | grep -q '\bdocker\b'; then
    warn "Usuario '$USER' no está en el grupo docker. Agregando..."
    sudo usermod -aG docker "$USER"
    warn "Necesitás cerrar y reabrir sesión SSH para que tome efecto."
    warn "Por ahora el script continúa usando sudo para docker."
    DOCKER_CMD="sudo docker"
else
    ok "Usuario '$USER' ya está en el grupo docker"
    DOCKER_CMD="docker"
fi

# ─── 3. Iniciar servicio docker ──────────────────────────────────────────────
echo ""
echo "── 2. Verificando servicio Docker ─────────────────────"

if ! $DOCKER_CMD info &> /dev/null; then
    warn "Docker daemon no está corriendo. Iniciando..."
    sudo systemctl start docker
    sleep 2
fi

if $DOCKER_CMD info &> /dev/null; then
    ok "Docker daemon corriendo"
else
    err "No se pudo iniciar Docker daemon"
    exit 1
fi

# ─── 4. Docker Compose ──────────────────────────────────────────────────────
echo ""
echo "── 3. Verificando Docker Compose ──────────────────────"

# Verificar plugin moderno (docker compose)
if $DOCKER_CMD compose version &> /dev/null; then
    COMPOSE_VERSION=$($DOCKER_CMD compose version --short 2>/dev/null || echo "desconocida")
    ok "docker compose (plugin) disponible: v$COMPOSE_VERSION"
    COMPOSE_CMD="$DOCKER_CMD compose"

# Verificar binario legacy (docker-compose)
elif command -v docker-compose &> /dev/null; then
    COMPOSE_VERSION=$(docker-compose --version | grep -oP '\d+\.\d+\.\d+' | head -1)
    ok "docker-compose (legacy) disponible: v$COMPOSE_VERSION"
    COMPOSE_CMD="docker-compose"

else
    warn "Docker Compose no encontrado. Instalando plugin..."
    COMPOSE_VERSION="v2.24.5"
    sudo mkdir -p /usr/local/lib/docker/cli-plugins
    sudo curl -fsSL \
        "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
        -o /usr/local/lib/docker/cli-plugins/docker-compose
    sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    ok "Docker Compose plugin instalado: $COMPOSE_VERSION"
    COMPOSE_CMD="$DOCKER_CMD compose"
fi

# ─── 5. Puerto 9100 ─────────────────────────────────────────────────────────
echo ""
echo "── 4. Verificando puerto 9100 ──────────────────────────"

# Verificar si algo ya está escuchando en 9100
if ss -tlnp 2>/dev/null | grep -q ':9100' || netstat -tlnp 2>/dev/null | grep -q ':9100'; then
    warn "Puerto 9100 ya está en uso. Verificá que no haya otro node-exporter corriendo:"
    ss -tlnp | grep ':9100' 2>/dev/null || netstat -tlnp | grep ':9100' 2>/dev/null
else
    ok "Puerto 9100 libre y disponible para node-exporter"
fi

# Verificar firewall local (iptables/ufw)
if command -v ufw &> /dev/null && sudo ufw status | grep -q "active"; then
    if sudo ufw status | grep -q "9100"; then
        ok "ufw: puerto 9100 ya permitido"
    else
        warn "ufw activo pero puerto 9100 no está en las reglas"
        info "Para abrirlo localmente: sudo ufw allow 9100/tcp"
        info "IMPORTANTE: También debés abrir el puerto en el Security Group de AWS"
    fi
else
    ok "Sin firewall local activo (ufw inactivo o no instalado)"
fi

# ─── 6. IP pública ──────────────────────────────────────────────────────────
echo ""
echo "── 5. Información de red ───────────────────────────────"

PUBLIC_IP=$(curl -s --max-time 5 http://checkip.amazonaws.com 2>/dev/null || \
            curl -s --max-time 5 https://ifconfig.me 2>/dev/null || \
            echo "no disponible")

PRIVATE_IP=$(hostname -I | awk '{print $1}')

ok "IP privada:  $PRIVATE_IP"
ok "IP pública:  $PUBLIC_IP"

# ─── 7. Resumen final ───────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"
echo "  Resumen"
echo "══════════════════════════════════════════════════════"
echo ""
ok "Sistema listo para correr node-exporter"
echo ""
info "Comando para levantar node-exporter:"
echo "  $COMPOSE_CMD -f docker-compose.node-exporter.yml up -d"
echo ""

echo -e "${YELLOW}ACCIÓN REQUERIDA en AWS Console / CLI:${NC}"
echo "  Abrí el puerto 9100 en el Security Group de esta instancia"
echo "  Solo para la IP de tu servidor Prometheus (más seguro):"
echo ""
echo "  aws ec2 authorize-security-group-ingress \\"
echo "    --group-id <SG-ID> \\"
echo "    --protocol tcp \\"
echo "    --port 9100 \\"
echo "    --cidr <IP-PROMETHEUS>/32"
echo ""
echo "  Luego agregá en prometheus.yml del servidor central:"
echo ""
echo "  - job_name: 'esta-ec2'"
echo "    static_configs:"
echo "      - targets: ['${PUBLIC_IP}:9100']"
echo "        labels:"
echo "          host: 'nombre-descriptivo'"
echo ""
echo "══════════════════════════════════════════════════════"
