#!/bin/bash

# Check if WireGuard is installed
if command -v wg >/dev/null 2>&1 || command -v wireguard >/dev/null 2>&1; then
    echo "WireGuard CLI is accessible."
else
    echo "WireGuard not found, installing Wireguard"
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update
            sudo apt-get install -y wireguard
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y wireguard-tools
        else
            echo "Please install WireGuard manually: https://www.wireguard.com/install/"
            exit 1
        fi
fi

#Rest of your configuration here


####This file is being used as a template