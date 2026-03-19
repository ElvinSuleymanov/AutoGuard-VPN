#!/bin/bash

# Just colors
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    NC='\033[0m'
    echo -e "${CYAN}${BOLD}=================================================="
    echo -e "   🛡️  WIREGUARD STACK AUTOMATION UTILITY   "
    echo -e "==================================================${NC}"

# Change Defaults (Recommended)
    IP_WG="172.29.144.10"
    IP_UNBOUND="172.29.144.20"
    IP_PIHOLE="172.29.144.30"
    IP_NGINX="172.29.144.40"
    IP_AUTH="172.29.144.50"
    IP_SIDECAR="172.29.144.60"
    PORT_WG="51820"
    PORT_AUTH="5000"
    PORT_SIDECAR="6000"
# Checks whether docker installed or not
    error() {
        echo -e "\n❌ ERROR: $1\n" >&2
        exit 1
    }

    check_command() {
        command -v "$1" >/dev/null 2>&1 || error "$1 is not installed.

    Please install it first:

    Docker:
    https://docs.docker.com/engine/install/

    Docker Compose:
    https://docs.docker.com/compose/install/"
    }

    echo "🔎 Checking system dependencies..."

    check_command docker

    if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
        error "Docker Compose is not installed.

    Install it from:
    https://docs.docker.com/compose/install/"
    fi

    echo "✅ Docker and Docker Compose are installed."


# Distro detection (gonna use it in further versions)
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "Running on: $ID"
    fi

# Timezone Detection
    DETECTED_TZ=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}')
    if [ -z "$DETECTED_TZ" ]; then
        DETECTED_TZ=$(cat /etc/timezone 2>/dev/null || echo "UTC")
    fi
    echo "Detected Timezone: $DETECTED_TZ"

    ENV_FILE=".env"

# Try to fetch public ip either enter it manually if something wrong
    FETCHED_IP=$(curl -s --max-time 5 https://ifconfig.me/ || echo "")
    SUGGESTED_IP="${PUBLIC_IP:-$FETCHED_IP}"

    while true; do
        echo -e "Is ${BOLD}${SUGGESTED_IP}${NC} your WireGuard server IP? (y/n): "
        read -r yn
        case $yn in
            [Yy]* ) PUBLIC_IP="$SUGGESTED_IP"; break;;
            [Nn]* )
                echo -n "Enter your WireGuard server IP address: "
                read -r PUBLIC_IP
                break;;
            * ) echo "Please answer yes or no.";;
        esac
    done

# Other variables
    WEBPASSWORD=$(openssl rand -base64 12) #Pi-hole UI password
    REGISTRATION_TOKEN=$(openssl rand -hex 32)
    SIDECAR_TOKEN=$(openssl rand -hex 32)
# Writing to .env file
    > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    echo "DETECTED_TZ=$DETECTED_TZ"               >> "$ENV_FILE"
    echo "IP_UNBOUND=$IP_UNBOUND"                 >> "$ENV_FILE"
    echo "IP_PIHOLE=$IP_PIHOLE"                   >> "$ENV_FILE"
    echo "IP_NGINX=$IP_NGINX"                     >> "$ENV_FILE"
    echo "IP_WG=$IP_WG"                           >> "$ENV_FILE"
    echo "IP_AUTH=$IP_AUTH"                       >> "$ENV_FILE"
    echo "PORT_WG=$PORT_WG"                       >> "$ENV_FILE"
    echo "PORT_AUTH=$PORT_AUTH"                   >> "$ENV_FILE"
    echo "PUBLIC_IP=$PUBLIC_IP"                   >> "$ENV_FILE"
    echo "WEBPASSWORD=$WEBPASSWORD"               >> "$ENV_FILE"
    echo "REGISTRATION_TOKEN=$REGISTRATION_TOKEN" >> "$ENV_FILE"
    echo "IP_SIDECAR=$IP_SIDECAR"                 >> "$ENV_FILE"
    echo "PORT_SIDECAR=$PORT_SIDECAR"             >> "$ENV_FILE"
    echo "SIDECAR_TOKEN=$SIDECAR_TOKEN"           >> "$ENV_FILE"
# Composing containers

    docker compose up -d
    COMPOSE_EXIT=$?
    SERVER_PUBLIC_KEY=$(docker exec wireguard wg show wg0 public-key)
    echo "SERVER_PUBLIC_KEY=$SERVER_PUBLIC_KEY" >> "$ENV_FILE"

# Check if anything wrong
    if [ $COMPOSE_EXIT -eq 0 ]; then
        echo -e "\n${GREEN}${BOLD}✅ Stack is up and running!${NC}"
        docker compose ps
    else
        echo -e "\n${RED}${BOLD}❌ docker compose failed. Check logs with: docker compose logs${NC}"
        exit 1
    fi

 
# Client scripts generation

    mkdir -p ./scripts

    #Powershell scripting
        SCRIPT_POWERSHELL="if ((Get-Command wireguard -ErrorAction SilentlyContinue) -or (Get-Command wg -ErrorAction SilentlyContinue)) {
            Write-Output "WireGuard CLI is accessible."
        } else {
            Write-Output "Binary not found in PATH."
        }"

        echo $SCRIPT_POWERSHELL > setupclient.ps1

    #Bash scripting
        SCRIPT_BASH="#!/bin/bash"
        echo $SCRIPT_BASH > setupclient.sh
        
    chmod +x ./scripts/*



# Configuration of reverse proxy(This section will only be used for secure communication during installation phase)
    NGINX_CONF="./shared/nginx/nginx.conf"
    CERTS_DIR="./certs"
    mkdir -p "$CERTS_DIR"
    if [ -f "$CERTS_DIR/fullchain.pem" ] && [ -f "$CERTS_DIR/privkey.pem" ]; then
        echo "Found existing certificates in $CERTS_DIR"
    else
        echo "Certificates not found, generating self-signed certificates for testing..."

        openssl req -x509 -nodes -days 365 \
            -newkey rsa:2048 \
            -keyout "$CERTS_DIR/privkey.pem" \
            -out "$CERTS_DIR/fullchain.pem" \
            -subj "/CN=localhost"

        echo "Self-signed certificates generated in $CERTS_DIR"
    fi

    sed -i -E "s#proxy_pass http://[^:]+:[0-9]+;#proxy_pass http://${IP_AUTH}:${PORT_AUTH};#" "$NGINX_CONF"
    sed -i -E "s#server_name public_ip;#server_name $PUBLIC_IP;#" "$NGINX_CONF"