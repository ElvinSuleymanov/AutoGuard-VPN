#!/bin/bash


#Defaults below

SERVER_IP="YOUR-PUBLIC-IP"
SERVER_PORT="YOUR-SERVER-PORT"
AUTH_KEY="AUTH_KEY"
CONF_FILE_PATH="/etc/wireguard/wg0.conf"
INTERFACE_NAME="wg0"

check_wireguard_interface() {
    if ip link show "$INTERFACE_NAME" > /dev/null 2>&1; then

        INTERFACE_STATE=$(ip link show wg0 2>/dev/null | grep -w "UP" && echo "up" || echo "down")

        if [ "$INTERFACE_STATE" = "up" ]; then
            return 0
        fi
    fi
}

check_wireguard_installation() {
    if command -v wg >/dev/null 2>&1 || command -v wireguard >/dev/null 2>&1; then
    echo "WireGuard CLI is accessible."
    return 0
}

try_install_wireguard() {
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y wireguard
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y wireguard-tools
    else
        echo "Please install WireGuard manually: https://www.wireguard.com/install/"
        exit 1
    fi
}



# Check if WireGuard is installed

#Rest of your configuration here



####This file is being used as a template