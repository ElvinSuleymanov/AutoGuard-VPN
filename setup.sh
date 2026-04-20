#!/bin/bash

# ─── Colors ───────────────────────────────────────────────────────────────────
CYAN='\033[0;36m'
BOLD='\033[1m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# ─── Defaults ─────────────────────────────────────────────────────────────────
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
ENV_FILE=".env"
CERTS_DIR="./certs"
NGINX_CONF="./nginx/nginx.conf"

# ═══════════════════════════════════════════════════════════════════════════════
#  UTILITY
# ═══════════════════════════════════════════════════════════════════════════════

print_banner() {
    echo -e "${CYAN}${BOLD}=================================================="
    echo -e "   🛡️  WIREGUARD STACK AUTOMATION UTILITY   "
    echo -e "==================================================${NC}"
}

# Usage: error "Something went wrong"
error() {
    echo -e "\n${RED}❌ ERROR: $1${NC}\n" >&2
    exit 1
}

# Usage: log_info "Message"
log_info()    { echo -e "ℹ️  $1"; }
log_success() { echo -e "${GREEN}${BOLD}✅ $1${NC}"; }
log_warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }

# ═══════════════════════════════════════════════════════════════════════════════
#  DEPENDENCY CHECKS
# ═══════════════════════════════════════════════════════════════════════════════

# Usage: check_command docker
check_command() {
    command -v "$1" >/dev/null 2>&1 || error "'$1' is not installed.

  Please install it first:

  Docker:        https://docs.docker.com/engine/install/
  Docker Compose: https://docs.docker.com/compose/install/"
}

check_dependencies() {
    log_info "Checking system dependencies..."
    check_command docker
    check_command openssl

    if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
        error "Docker Compose is not installed.
  Install it from: https://docs.docker.com/compose/install/"
    fi

    log_success "Docker, Docker Compose, and OpenSSL are installed."
}

# ═══════════════════════════════════════════════════════════════════════════════
#  SYSTEM DETECTION
# ═══════════════════════════════════════════════════════════════════════════════

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_info "Running on: $ID"
    else
        log_warn "Could not detect Linux distribution."
    fi
}

# Sets DETECTED_TZ
detect_timezone() {
    DETECTED_TZ=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}')
    if [ -z "$DETECTED_TZ" ]; then
        DETECTED_TZ=$(cat /etc/timezone 2>/dev/null || echo "UTC")
    fi
    log_info "Detected timezone: $DETECTED_TZ"
}

# Tries to fetch public IP; prompts user to confirm or override.
# Sets PUBLIC_IP
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

    log_info "Using public IP: $PUBLIC_IP"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  SECRETS & KEY GENERATION
# ═══════════════════════════════════════════════════════════════════════════════

# Usage: generate_token <length_bytes>  → prints hex token
generate_token() {
    local bytes="${1:-32}"
    openssl rand -hex "$bytes"
}

# Usage: generate_password → prints base64 password
generate_password() {
    openssl rand -base64 12
}

# Generates a WireGuard X25519 keypair.
# Sets SERVER_PRIVATE_KEY and SERVER_PUBLIC_KEY.
generate_wireguard_keys() {
    local tmp_pem="/tmp/wg_server_private_$$.pem"

    openssl genpkey -algorithm X25519 -out "$tmp_pem" 2>/dev/null \
        || error "Failed to generate WireGuard private key."

    SERVER_PRIVATE_KEY=$(openssl pkey -in "$tmp_pem" -outform DER | tail -c 32 | base64)
    SERVER_PUBLIC_KEY=$(openssl pkey -in "$tmp_pem" -pubout -outform DER | tail -c 32 | base64)

    rm -f "$tmp_pem"
    log_success "WireGuard keypair generated."
}

# Writes the WireGuard keys to disk and patches wg0.conf.
install_wireguard_keys() {
    local keys_dir="./wireguard/keys"
    mkdir -p "$keys_dir"

    sed -i "s|your-private-key|${SERVER_PRIVATE_KEY}|g" ./wireguard/wg_confs/wg0.conf \
        || log_warn "Could not patch wg0.conf — file may not exist yet."

    echo "$SERVER_PUBLIC_KEY" > "$keys_dir/server_public.key"
    chmod 644 "$keys_dir/server_public.key"

    log_info "Server public key written to $keys_dir/server_public.key"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  TLS CERTIFICATES
# ═══════════════════════════════════════════════════════════════════════════════

# Usage: generate_self_signed_cert <output_dir> [common_name]
generate_self_signed_cert() {
    local out_dir="${1:-./certs}"
    local cn="${2:-localhost}"

    mkdir -p "$out_dir"

    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "$out_dir/privkey.pem" \
        -out   "$out_dir/fullchain.pem" \
        -subj  "/CN=${cn}" 2>/dev/null \
        || error "Failed to generate self-signed certificate."

    log_success "Self-signed certificate generated in $out_dir (CN=$cn)"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  NGINX CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

configure_nginx() {
    local conf="${1:-$NGINX_CONF}"

    [ -f "$conf" ] || error "Nginx config not found: $conf"

    sed -i -E "s#proxy_pass http://[^:]+:[0-9]+;#proxy_pass http://${IP_AUTH}:${PORT_AUTH};#" "$conf"
    sed -i -E "s#server_name public_ip;#server_name ${PUBLIC_IP};#" "$conf"

    log_success "Nginx config patched: proxy → ${IP_AUTH}:${PORT_AUTH}, server_name → ${PUBLIC_IP}"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  ENVIRONMENT FILE
# ═══════════════════════════════════════════════════════════════════════════════

# Usage: write_env_var KEY value
write_env_var() {
    echo "${1}=${2}" >> "$ENV_FILE"
}

init_env_file() {
    > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    log_info "Initialized $ENV_FILE"
}

write_env_file() {
    init_env_file

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
    write_env_var SIDECAR_TOKEN        "$SIDECAR_TOKEN"

    log_success "Environment file written to $ENV_FILE"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  DOCKER
# ═══════════════════════════════════════════════════════════════════════════════

start_stack() {
    log_info "Starting Docker Compose stack..."
    docker compose up -d --wait
}

# Blocks until all compose services report 'running'.
# Usage: wait_for_stack [timeout_seconds]
wait_for_stack() {
    local timeout="${1:-120}"
    local elapsed=0

    log_info "Waiting for all services to be healthy..."

    until [ "$(docker compose ps --status running -q | wc -l)" -eq \
            "$(docker compose ps -q | wc -l)" ]; do
        sleep 2
        elapsed=$((elapsed + 2))
        if [ "$elapsed" -ge "$timeout" ]; then
            error "Timed out waiting for services after ${timeout}s. Run: docker compose logs"
        fi
    done

    log_success "All services are up and running!"
}

# Reads the live WireGuard public key from the running container and appends it to .env
append_live_wg_pubkey() {
    local live_key
    live_key=$(docker exec wireguard wg show wg0 public-key 2>/dev/null) \
        || { log_warn "Could not read live WireGuard public key from container."; return; }

    write_env_var SERVER_PUBLIC_KEY "$live_key"
    log_info "Live WireGuard public key appended to $ENV_FILE"
}

check_stack_status() {
    local exit_code="${1:-0}"
    if [ "$exit_code" -eq 0 ]; then
        log_success "Stack is up and running!"
        docker compose ps
    else
        echo -e "\n${RED}${BOLD}❌ docker compose failed. Check logs with: docker compose logs${NC}"
        exit 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  CLIENT SCRIPT GENERATION
# ═══════════════════════════════════════════════════════════════════════════════

generate_powershell_client() {
    local out="${1:-./scripts/setupclient.ps1}"
    cat > "$out" <<'EOF'
if ((Get-Command wireguard -ErrorAction SilentlyContinue) -or (Get-Command wg -ErrorAction SilentlyContinue)) {
    Write-Output "WireGuard CLI is accessible."
} else {
    Write-Output "Binary not found in PATH."
}
EOF
    log_info "PowerShell client script written to $out"
}

generate_bash_client() {
    local out="${1:-./scripts/setupclient.sh}"
    cat > "$out" <<'EOF'
#!/bin/bash
# WireGuard client setup
EOF
    chmod +x "$out"
    log_info "Bash client script written to $out"
}

generate_client_scripts() {
    mkdir -p ./scripts
    generate_powershell_client "./scripts/setupclient.ps1"
    generate_bash_client       "./scripts/setupclient.sh"
    log_success "Client scripts generated in ./scripts/"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    print_banner

    # System checks
    check_dependencies
    detect_distro
    detect_timezone
    detect_public_ip

    # Generate all secrets up front
    WEBPASSWORD=$(generate_password)
    REGISTRATION_TOKEN=$(generate_token 32)
    SIDECAR_TOKEN=$(generate_token 32)

    # Keys & certs
    generate_wireguard_keys
    install_wireguard_keys
    generate_self_signed_cert "$CERTS_DIR" "localhost"

    # Configure services
    configure_nginx "$NGINX_CONF"

    # Persist configuration
    write_env_file

    # Bring stack up
    start_stack
    COMPOSE_EXIT=$?
    wait_for_stack 120
    append_live_wg_pubkey
    check_stack_status "$COMPOSE_EXIT"

    # Generate client helpers
    generate_client_scripts
}

main "$@"