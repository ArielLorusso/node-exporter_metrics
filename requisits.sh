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

# ─── 6. IP pública e Instance ID desde metadatos de AWS ────────────────────
echo ""
echo "── 5. Información de red ───────────────────────────────"

# IMDSv2: token de sesión requerido por AWS desde 2019
IMDS_TOKEN=$(curl -s --max-time 3 -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)

if [ -n "$IMDS_TOKEN" ]; then
    # Estamos en una EC2 — podemos obtener metadatos
    INSTANCE_ID=$(curl -s --max-time 3 -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
        http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null)
    REGION=$(curl -s --max-time 3 -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
        http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null)
    PUBLIC_IP=$(curl -s --max-time 3 -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
        http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
    IS_EC2=true
    ok "EC2 detectada — Instance ID: $INSTANCE_ID  Región: $REGION"
else
    # No es EC2 o metadatos no disponibles
    PUBLIC_IP=$(curl -s --max-time 5 http://checkip.amazonaws.com 2>/dev/null || \
                curl -s --max-time 5 https://ifconfig.me 2>/dev/null || \
                echo "no disponible")
    INSTANCE_ID="no-disponible"
    REGION="no-disponible"
    IS_EC2=false
    info "No se detectaron metadatos de EC2 (puede ser una VM local)"
fi

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
info "Comando para levantar node-exporter (correr en ESTA máquina):"
echo ""
echo "  $COMPOSE_CMD -f docker-compose.node-exporter.yml up -d"
echo ""

if [ "$IS_EC2" = true ]; then
    echo -e "${YELLOW}══ ACCIÓN REQUERIDA — Correr en tu PC (servidor Prometheus) ══${NC}"
    echo ""
    echo "  # 1. Obtener el SG-ID de esta instancia y abrir puerto 9100:"
    echo ""
    echo "  SG_ID=\$(aws ec2 describe-instances \\"
    echo "    --instance-ids ${INSTANCE_ID} \\"
    echo "    --region ${REGION} \\"
    echo "    --query 'Reservations[].Instances[].SecurityGroups[].GroupId' \\"
    echo "    --output text)"
    echo ""
    echo "  aws ec2 authorize-security-group-ingress \\"
    echo "    --group-id \$SG_ID \\"
    echo "    --protocol tcp \\"
    echo "    --port 9100 \\"
    echo "    --region ${REGION} \\"
    echo "    --cidr \$(curl -s -4 ifconfig.me)/32"
    echo ""
    echo "  # 2. Agregar en prometheus.yml del servidor central:"
    echo ""
    echo "  - job_name: 'ec2-${INSTANCE_ID}'"
    echo "    static_configs:"
    echo "      - targets: ['${PUBLIC_IP}:9100']"
    echo "        labels:"
    echo "          host: 'nombre-descriptivo'   # <-- cambiá esto"
    echo "          instance_id: '${INSTANCE_ID}'"
    echo "          region: '${REGION}'"
    echo ""
    echo "  # 3. Recargar Prometheus sin reiniciar:"
    echo ""
    echo "  curl -X POST http://localhost:9090/-/reload"
else
    echo -e "${YELLOW}ACCIÓN REQUERIDA:${NC}"
    echo "  Abrí el puerto 9100 en tu firewall para la IP del servidor Prometheus"
fi

echo ""
echo "══════════════════════════════════════════════════════"

# INSPECCIONAR ID e IP

    # PROBLEMA:
    
        #   EC2 (TARGET)                    Tu PC (HOST)
        #   ┌─────────────────┐             ┌──────────────────┐
        #   │ Sabe su:        │             │ Tiene:           │
        #   │ ✅ Instance ID  │             │ ✅ AWS CLI con   │
        #   │ ✅ IP privada   │             │    credenciales  │
        #   │ ✅ IP pública   │             │ ✅ Puede llamar  │
        #   │ ❌ SG-ID real   │             │    describe-inst │
        #   │ ❌ IP de quien  │             │ ✅ Sabe su IP    │
        #   │    la monitorea │             │    pública       │
        #   └─────────────────┘             └──────────────────┘
        #   
        #       EC2 no tiene credenciales AWS por defecto, 
        #       así que no puede llamar a describe-instances
    
    # SOLUCION: 

        # el script ahora usa IMDSv2 (Instance Metadata Service v2)  
        # el sistema interno de AWS que toda EC2 tiene en 169.254.169.254


# SEGURIDAD    usamos Variable de entorno 

    #  Qué es ?
        
        #   Variable de entorno:  export MI_VAR="valor"  → heredada por procesos hijos
        #   Variable de shell:           MI_VAR="valor"  → solo en este proceso bash

    #  Es seguro ?
 
        #   Riesgo               Nivel      Por qué
        #   ─────────────────────────────────────────────────────
        #   Queda guardada         ✅ Bajo    Se borra al cerrar terminal
        #   Aparece en ps aux      ✅ Bajo    Solo el nombre de var, no el valor  
        #   Queda en .bash_history ⚠️ Medio   El COMANDO queda, pero SG-ID no es secreto
        #   Aparece en logs        ✅ Bajo    No se loguea automáticamente