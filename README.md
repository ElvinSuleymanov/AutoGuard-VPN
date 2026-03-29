# 🛡️ AutoGuard VPN

A self-hosted VPN stack with automated client registration, ad blocking, and recursive DNS — all containerized with Docker.

## Stack

| Container | Image | Role |
|---|---|---|
| `wireguard` | linuxserver/wireguard | VPN server |
| `wg-sidecar` | custom | Peer registration agent |
| `auth-service` | custom | Client authentication |
| `nginx-proxy` | nginx | TLS reverse proxy |
| `pihole` | pihole/pihole | DNS-based ad & tracker blocking |
| `unbound` | mvance/unbound | Recursive DNS resolver |

All services run on an isolated Docker bridge network (`172.29.144.0/24`).

---

## Architecture

### 🔧 Setup & Registration

When a new client runs the setup script, the request flows through Nginx → Auth → wg-sidecar, which registers the peer directly into WireGuard from within its shared network namespace.

![Setup phase](assets/setup_phase.svg)

### 🌐 VPN Usage

Once registered, the client connects directly to WireGuard over UDP. All DNS queries are filtered by Pi-hole and resolved recursively by Unbound — no third-party DNS provider involved.

![Usage phase](assets/usage_phase.svg)

---

## Quick Start

### Prerequisites

- Docker & Docker Compose
- A Linux server with a public IP

### Install

```bash
git clone https://github.com/yourname/autoguard-vpn.git
cd autoguard-vpn
chmod +x setup.sh
./setup.sh
```

The setup script will:

1. Detect your public IP and timezone
2. Generate secrets and write `.env`
3. Spin up all containers with health checks
4. Generate client setup scripts (`setupclient.ps1` / `setupclient.sh`)

### Connect a client

Run the generated script on your client device:

```bash
# Linux / macOS
bash setupclient.sh

# Windows (PowerShell)
.\setupclient.ps1
```

---

## Configuration

All settings are written to `.env` by the setup script. You can override defaults before running:

| Variable | Default | Description |
|---|---|---|
| `PORT_WG` | `51820` | WireGuard UDP port |
| `PORT_AUTH` | `5000` | Auth service port |
| `PORT_SIDECAR` | `6000` | Sidecar port |
| `IP_WG` | `172.29.144.10` | WireGuard container IP |
| `IP_PIHOLE` | `172.29.144.30` | Pi-hole container IP |
| `IP_UNBOUND` | `172.29.144.20` | Unbound container IP |

---
