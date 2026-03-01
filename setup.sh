#!/bin/bash

# Define ANSI color codes for sophisticated output
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${CYAN}${BOLD}=================================================="
echo -e "   🛡️  WIREGUARD STACK AUTOMATION UTILITY"
echo -e "==================================================${NC}"

# Check for OS release info
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "Running on: $ID"
else
    echo "Error: /etc/os-release not found."
    exit 1
fi


DETECTED_TZ=$(timedatectl | grep "Time zone" | awk '{print $3}')
if [ -z "$DETECTED_TZ" ]; then
    DETECTED_TZ=$(cat /etc/timezone)
fi
echo "Detected Timezone: $DETECTED_TZ"


PUBLIC_IP=$(curl -s https://ifconfig.me/)

while true; do
    read -p "$PUBLIC_IP is your wireguard server ip? (y/n): " yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) read -p "Enter your wireguard server ip address: " PUBLIC_IP; break;;
        * ) echo "Please answer yes or no.";;
    esac
done



read -p "Enter WireGuard Public Port [51820]: " USER_PORT
USER_PORT=${USER_PORT:-51820} 

read -p "Enter Unbound container's IP address [172.20.0.20]: " IP_UNBOUND
IP_UNBOUND=${IP_UNBOUND:-172.20.0.20}

read -p "Enter IP of Pi-hole server [172.20.0.30]: " IP_PIHOLE
IP_PIHOLE=${IP_PIHOLE:-172.20.0.30}


WEBPASSWORD=$(openssl rand -base64 12)
echo -e "Your password is: ${BOLD}${WEBPASSWORD}${NC}"


cat <<EOF > .env
WEBPASSWORD=$WEBPASSWORD
TIMEZONE=$DETECTED_TZ
IP_UNBOUND=$IP_UNBOUND
IP_PIHOLE=$IP_PIHOLE
PUBLIC_IP=$PUBLIC_IP
WIREGUARD_PUBLIC_PORT=$USER_PORT
EOF

echo -e "${CYAN}Variables successfully written to .env${NC}"
chmod 600 .env

docker compose up  