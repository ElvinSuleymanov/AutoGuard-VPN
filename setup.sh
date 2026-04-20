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
    SUBNET="172.29.144.0/24"
    IP_WG="172.29.144.10"
    IP_UNBOUND="172.29.144.20"
    IP_PIHOLE="172.29.144.30"
    IP_NGINX="172.29.144.40"
    IP_AUTH="172.29.144.50"
    IP_SIDECAR="172.29.144.60"
    INTERNAL_SUBNET="10.13.26.0"
    PORT_WG="51820"
    PORT_AUTH="5000"
    PORT_SIDECAR="6000"
    INTERFACE_NAME="wg0"

# Checks whether docker installed or not
    error() {
        echo -e "\n❌ ERROR: $1\n" >&2
        exit 1
    }

    log_success() { echo -e "${GREEN}${BOLD}✅ $1${NC}"; }
    log_warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }

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
        # shellcheck source=/dev/null
        . /etc/os-release
        echo "Running on: $ID"
    fi

# Timezone Detection
    detect_timezone() {
        DETECTED_TZ=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}')
        if [ -z "$DETECTED_TZ" ]; then
            DETECTED_TZ=$(cat /etc/timezone 2>/dev/null || echo "UTC")
        fi
        echo "Detected Timezone: $DETECTED_TZ"
    }

    detect_timezone

    ENV_FILE=".env"

# Try to fetch public ip either enter it manually if something wrong
    detect_public_ip() {
        local fetched suggested
        fetched=$(curl -s --max-time 5 https://ifconfig.me/ || echo "")
        suggested="${PUBLIC_IP:-$fetched}"

        while true; do
            echo -e "Is ${BOLD}${suggested}${NC} your WireGuard server IP? (y/n): "
            read -r yn
            case $yn in
                [Yy]* ) PUBLIC_IP="$suggested"; break ;;
                [Nn]* )
                    echo -n "Enter your WireGuard server IP address: "
                    read -r PUBLIC_IP
                    break ;;
                * ) echo "Please answer yes or no." ;;
            esac
        done
    }

    detect_public_ip

# Token generating
    generate_password() { openssl rand -base64 12; }
    generate_token()    { openssl rand -hex "${1:-32}"; }

    WEBPASSWORD=$(generate_password)
    REGISTRATION_TOKEN=$(generate_token 32)

    generate_wireguard_keys() {
        local tmp_pem="/tmp/wg_server_private_$$.pem"

        openssl genpkey -algorithm X25519 -out "$tmp_pem" 2>/dev/null \
            || error "Failed to generate WireGuard private key."

        SERVER_PRIVATE_KEY=$(openssl pkey -in "$tmp_pem" -outform DER | tail -c 32 | base64)
        SERVER_PUBLIC_KEY=$(openssl pkey -in "$tmp_pem" -pubout -outform DER | tail -c 32 | base64)

        rm -f "$tmp_pem"
        log_success "WireGuard keypair generated."
    }

    install_wireguard_keys() {
        local keys_dir="./wireguard/keys"
        mkdir -p "$keys_dir"

        sed -i "s|your-private-key|${SERVER_PRIVATE_KEY}|g" ./wireguard/wg_confs/wg0.conf \
            || log_warn "Could not patch wg0.conf — file may not exist yet."

        echo "$SERVER_PUBLIC_KEY" > "$keys_dir/server_public.key"
        chmod 644 "$keys_dir/server_public.key"
    }

    generate_wireguard_keys
    install_wireguard_keys

# Configuration of reverse proxy(This section will only be used for secure communication during installation phase)

    NGINX_CONF="./nginx/nginx.conf"
    CERTS_DIR="./certs"

    generate_self_signed_cert() {
        local out_dir="${1:-./certs}"
        local cn="${2:-localhost}"
        mkdir -p "$out_dir"

        openssl req -x509 -nodes -days 365 \
            -newkey rsa:2048 \
            -keyout "$out_dir/privkey.pem" \
            -out    "$out_dir/fullchain.pem" \
            -subj   "/CN=${cn}" 2>/dev/null \
            || error "Failed to generate self-signed certificate."

        echo "Self-signed certificates generated in $out_dir"
    }

    configure_nginx() {
        local conf="${1:-$NGINX_CONF}"
        [ -f "$conf" ] || error "Nginx config not found: $conf"

        sed -i -E "s#proxy_pass http://[^:]+:[0-9]+;#proxy_pass http://${IP_AUTH}:${PORT_AUTH};#" "$conf"
        sed -i -E "s#server_name public_ip;#server_name ${PUBLIC_IP};#" "$conf"
    }

    generate_self_signed_cert "$CERTS_DIR" "localhost"
    configure_nginx "$NGINX_CONF"

# Writing to .env file
    write_env_var() { echo "${1}=${2}" >> "$ENV_FILE"; }

    write_env_file() {
        : > "$ENV_FILE"
        chmod 600 "$ENV_FILE"

        write_env_var SUBNET               "$SUBNET"
        write_env_var INTERNAL_SUBNET      "$INTERNAL_SUBNET"
        write_env_var DETECTED_TZ          "$DETECTED_TZ"
        write_env_var IP_WG                "$IP_WG"
        write_env_var IP_UNBOUND           "$IP_UNBOUND"
        write_env_var IP_PIHOLE            "$IP_PIHOLE"
        write_env_var IP_NGINX             "$IP_NGINX"
        write_env_var IP_AUTH              "$IP_AUTH"
        write_env_var IP_SIDECAR           "$IP_SIDECAR"
        write_env_var PORT_WG              "$PORT_WG"
        write_env_var PORT_AUTH            "$PORT_AUTH"
        write_env_var PORT_SIDECAR         "$PORT_SIDECAR"
        write_env_var PUBLIC_IP            "$PUBLIC_IP"
        write_env_var WEBPASSWORD          "$WEBPASSWORD"
        write_env_var REGISTRATION_TOKEN   "$REGISTRATION_TOKEN"
    }

    write_env_file

# Composing containers
    docker compose up -d --wait
    COMPOSE_EXIT=$?
    echo "Waiting for app to be ready..."

    wait_for_stack() {
        local timeout="${1:-120}"
        local elapsed=0

        until [ "$(docker compose ps --status running -q | wc -l)" -eq \
                "$(docker compose ps -q | wc -l)" ]; do
            sleep 2
            elapsed=$((elapsed + 2))
            if [ "$elapsed" -ge "$timeout" ]; then
                error "Timed out waiting for services after ${timeout}s. Run: docker compose logs"
            fi
        done
    }

    wait_for_stack 120
    echo "All services are up!"
    echo "App is ready!"
    SERVER_PUBLIC_KEY=$(docker exec wireguard wg show wg0 public-key)
    write_env_var SERVER_PUBLIC_KEY "$SERVER_PUBLIC_KEY"

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

    inject_placeholders() {
        local file="$1"
        local shell="${2:-bash}"

        if [ "$shell" = "ps1" ]; then
            sed -i "s|PLACEHOLDER_SERVER_PUBLIC_IP|${PUBLIC_IP}|g"    "$file"
            sed -i "s|PLACEHOLDER_SERVER_PORT|${PORT_WG}|g"           "$file"
            sed -i "s|PLACEHOLDER_PUBLIC_KEY|${SERVER_PUBLIC_KEY}|g"  "$file"
            sed -i "s|PLACEHOLDER_INTERFACE_NAME|${INTERFACE_NAME}|g" "$file"
            sed -i "s|PLACEHOLDER_AUTH_KEY|${REGISTRATION_TOKEN}|g"   "$file"
        else
            sed -i "s|PLACEHOLDER-PUBLIC-IP|${PUBLIC_IP}|g"           "$file"
            sed -i "s|PLACEHOLDER-SERVER-PORT|${PORT_WG}|g"           "$file"
            sed -i "s|PLACEHOLDER-PUBLIC-KEY|${SERVER_PUBLIC_KEY}|g"  "$file"
            sed -i "s|PLACEHOLDER-INTERFACE-NAME|${INTERFACE_NAME}|g" "$file"
            sed -i "s|PLACEHOLDER-AUTH_KEY|${REGISTRATION_TOKEN}|g"   "$file"
        fi
    }

    inject_placeholders "./scripts/setupclient.ps1" "ps1"
    inject_placeholders "./scripts/setupclient.sh"  "bash"

    chmod +x ./scripts/*.sh

# Configuration of wireguard