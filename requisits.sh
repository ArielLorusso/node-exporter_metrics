#!/bin/bash
# prereqs.sh - Node Exporter: instala Docker, abre firewall, levanta contenedor
# Compatible con: Ubuntu 20/22/24, Amazon Linux 2, Amazon Linux 2023
# Uso:
#   curl -O https://raw.githubusercontent.com/ArielLorusso/node-exporter_metrics/refs/heads/main/prereqs.sh
#   curl -O https://raw.githubusercontent.com/ArielLorusso/node-exporter_metrics/refs/heads/main/docker-compose.node-exporter.yml
#   chmod +x prereqs.sh && ./prereqs.sh

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}OK  $1${NC}"; }
warn() { echo -e "${YELLOW}>>  $1${NC}"; }
info() { echo -e "${BLUE}... $1${NC}"; }
err()  { echo -e "${RED}ERR $1${NC}"; }

echo ""
echo "======================================================"
echo "  prereqs.sh - Node Exporter Docker Setup"
echo "======================================================"
echo ""

# Detectar distro
DISTRO=$(. /etc/os-release 2>/dev/null && echo "$ID" || echo "unknown")
info "Distro: $DISTRO"

# ── 1. Docker ──────────────────────────────────────────
echo ""
echo "-- 1. Docker ------------------------------------------"

if command -v docker &> /dev/null; then
    ok "Docker ya instalado: $(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)"
else
    warn "Instalando Docker..."
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
            if grep -q "Amazon Linux 2023" /etc/os-release 2>/dev/null; then
                sudo dnf install -y docker
                sudo systemctl enable --now docker
                COMPOSE_VERSION="v2.24.5"
                sudo mkdir -p /usr/local/lib/docker/cli-plugins
                sudo curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
                    -o /usr/local/lib/docker/cli-plugins/docker-compose
                sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
            else
                sudo amazon-linux-extras install docker -y
                sudo systemctl enable --now docker
                sudo curl -fsSL "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-linux-x86_64" \
                    -o /usr/local/bin/docker-compose
                sudo chmod +x /usr/local/bin/docker-compose
            fi
            ;;
        *)
            err "Distro '$DISTRO' no soportada. Instala Docker manualmente: https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac
    ok "Docker instalado"
fi

# Agregar usuario al grupo docker si hace falta
if ! groups "$USER" | grep -q '\bdocker\b'; then
    sudo usermod -aG docker "$USER"
    warn "Usuario agregado al grupo docker (requiere nueva sesion SSH para tomar efecto)"
    DOCKER_CMD="sudo docker"
else
    DOCKER_CMD="docker"
fi

# ── 2. Iniciar Docker daemon ───────────────────────────
echo ""
echo "-- 2. Docker daemon -----------------------------------"

if ! $DOCKER_CMD info &> /dev/null; then
    warn "Iniciando Docker daemon..."
    sudo systemctl start docker
    sleep 2
fi
ok "Docker daemon corriendo"

# ── 3. Docker Compose ──────────────────────────────────
echo ""
echo "-- 3. Docker Compose ----------------------------------"

if $DOCKER_CMD compose version &> /dev/null; then
    ok "docker compose (plugin): $($DOCKER_CMD compose version --short 2>/dev/null)"
    COMPOSE_CMD="$DOCKER_CMD compose"
elif command -v docker-compose &> /dev/null; then
    ok "docker-compose (legacy): $(docker-compose --version | grep -oP '\d+\.\d+\.\d+' | head -1)"
    COMPOSE_CMD="docker-compose"
else
    warn "Instalando Docker Compose plugin..."
    sudo mkdir -p /usr/local/lib/docker/cli-plugins
    sudo curl -fsSL \
        "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-linux-x86_64" \
        -o /usr/local/lib/docker/cli-plugins/docker-compose
    sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    ok "Docker Compose instalado: v2.24.5"
    COMPOSE_CMD="$DOCKER_CMD compose"
fi

# ── 4. Firewall ufw ────────────────────────────────────
echo ""
echo "-- 4. Firewall ----------------------------------------"

if command -v ufw &> /dev/null && sudo ufw status | grep -q "active"; then
    if sudo ufw status | grep -q "9100"; then
        ok "ufw: puerto 9100 ya permitido"
    else
        warn "Abriendo puerto 9100 en ufw..."
        sudo ufw allow 9100/tcp
        ok "ufw: puerto 9100 abierto"
    fi
else
    ok "Sin firewall ufw activo"
fi

# ── 5. Levantar node-exporter ──────────────────────────
echo ""
echo "-- 5. Node Exporter -----------------------------------"

COMPOSE_FILE="docker-compose.node-exporter.yml"

# Verificar que el archivo existe
if [ ! -f "$COMPOSE_FILE" ]; then
    warn "No se encontro $COMPOSE_FILE en el directorio actual. Descargando..."
    curl -fsSL -O "https://raw.githubusercontent.com/ArielLorusso/node-exporter_metrics/refs/heads/main/docker-compose.node-exporter.yml"
fi

# Si ya hay un contenedor corriendo, no hacer nada
if $DOCKER_CMD ps --format '{{.Names}}' | grep -q '^node-exporter$'; then
    ok "node-exporter ya esta corriendo"
else
    warn "Levantando node-exporter..."
    $COMPOSE_CMD -f "$COMPOSE_FILE" up -d
    sleep 3
fi

# Verificar que responde
if curl -s --max-time 5 http://localhost:9100/metrics | grep -q "node_exporter_build_info"; then
    ok "node-exporter responde en :9100"
else
    err "node-exporter no responde. Ver logs:"
    $DOCKER_CMD logs node-exporter --tail=20
    exit 1
fi

# ── 6. Info de red y metadatos AWS ─────────────────────
echo ""
echo "-- 6. Red ---------------------------------------------"

IMDS_TOKEN=$(curl -s --max-time 3 -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || true)

if [ -n "$IMDS_TOKEN" ]; then
    INSTANCE_ID=$(curl -s --max-time 3 -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
        http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null)
    REGION=$(curl -s --max-time 3 -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
        http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null)
    PUBLIC_IP=$(curl -s --max-time 3 -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
        http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
    IS_EC2=true
    ok "EC2: $INSTANCE_ID  region: $REGION"
else
    PUBLIC_IP=$(curl -s --max-time 5 http://checkip.amazonaws.com 2>/dev/null || echo "no-disponible")
    INSTANCE_ID="no-disponible"
    REGION="no-disponible"
    IS_EC2=false
    info "No se detectaron metadatos EC2"
fi

PRIVATE_IP=$(hostname -I | awk '{print $1}')
ok "IP privada: $PRIVATE_IP"
ok "IP publica: $PUBLIC_IP"

# ── 7. Instrucciones para el servidor Prometheus ───────
echo ""
echo "======================================================"
echo "  LISTO - node-exporter corriendo en :9100"
echo "======================================================"
echo ""
echo "  Verificacion:"
echo "  curl http://localhost:9100/metrics | head -3"
echo ""

if [ "$IS_EC2" = true ]; then
    echo -e "${YELLOW}======================================================"
    echo "  ACCION REQUERIDA en tu PC (servidor Prometheus)"
    echo -e "======================================================${NC}"
    echo ""
    echo "  # Abrir puerto 9100 en el Security Group:"
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
    echo "  # Agregar en prometheus.yml:"
    echo ""
    echo "  - job_name: 'ec2-${INSTANCE_ID}'"
    echo "    static_configs:"
    echo "      - targets: ['${PUBLIC_IP}:9100']"
    echo "        labels:"
    echo "          host: 'nombre-descriptivo'"
    echo "          instance_id: '${INSTANCE_ID}'"
    echo "          region: '${REGION}'"
    echo ""
    echo "  # Recargar Prometheus sin reiniciar:"
    echo ""
    echo "  curl -X POST http://localhost:9090/-/reload"
fi

echo ""
echo "======================================================"

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