#!/bin/bash
# ============================================================
# HomeNAS - Netherlands VPS One-Click Deploy Script
#
# Components:
#   - Caddy (reverse proxy, auto HTTPS)
#   - Hysteria 2 Server (encrypted tunnel, no tcpForwarding)
#   - OpenList (file listing, bare-metal install)
#   - qBittorrent (BT download, Docker)
#   - Aria2 (multi-protocol download, Docker)
#   - AriaNg (Aria2 WebUI, Docker)
#
# Two download paths:
#   1. OpenList internal -> qB/Aria2 -> default path -> auto upload cloud
#   2. WebUI manual select /opt/mac/ -> Mac rsync pullback
#
# Usage:
#   Interactive:       sudo ./setup-netherlands.sh
#   Non-interactive:   sudo bash setup-netherlands.sh <HY2_PASS> [OP_DOMAIN] [QB_DOMAIN] [ARIA_DOMAIN]
# ============================================================
set -eo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "\n${BLUE}==== $* ====${NC}\n"; }

# ============================================================
# Root check
# ============================================================
if [ "$(id -u)" != "0" ]; then
    log_error "Please run as root: sudo ./setup-netherlands.sh"
    exit 1
fi

# ============================================================
# Default config
# ============================================================
HY2_PORT=8443; OPENLIST_PORT=5244; QB_PORT=8080; ARIA_PORT=6800; ARIANG_PORT=6880
MAC_DOWNLOAD_DIR=/opt/mac; DEFAULT_DOWNLOAD_DIR=/opt/downloads; ARIA2_RPC_SECRET="openlist2024"

# ============================================================
# Step 1: Configuration (interactive or command-line args)
# ============================================================
log_step "Step 1: Configuration"

if [ -n "${1:-}" ]; then
    # Non-interactive mode: args from command line
    HY2_PASSWORD="$1"
    DOMAIN_OPENLIST="${2:-nllist.dickgroup.xyz}"
    DOMAIN_QB="${3:-qb.dickgroup.xyz}"
    DOMAIN_ARIA="${4:-aria.dickgroup.xyz}"
else
    # Interactive mode
    echo "========================================"
    echo "  HomeNAS - Netherlands VPS Deploy"
    echo "========================================"
    echo ""

    read -r -p "HY2 auth password: " HY2_PASSWORD
    if [ -z "$HY2_PASSWORD" ]; then
        log_error "HY2 password cannot be empty"
        exit 1
    fi

    read -r -p "OpenList subdomain [nllist.dickgroup.xyz]: " DOMAIN_OPENLIST
    DOMAIN_OPENLIST=${DOMAIN_OPENLIST:-nllist.dickgroup.xyz}

    read -r -p "qBittorrent subdomain [qb.dickgroup.xyz]: " DOMAIN_QB
    DOMAIN_QB=${DOMAIN_QB:-qb.dickgroup.xyz}

    read -r -p "AriaNg subdomain [aria.dickgroup.xyz]: " DOMAIN_ARIA
    DOMAIN_ARIA=${DOMAIN_ARIA:-aria.dickgroup.xyz}

    echo ""
    read -r -p "Confirm config? (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "Cancelled"
        exit 0
    fi
fi

log_info "HY2 port:        ${HY2_PORT}"
log_info "OpenList domain: ${DOMAIN_OPENLIST} -> :${OPENLIST_PORT}"
log_info "qB WebUI domain: ${DOMAIN_QB} -> :${QB_PORT}"
log_info "AriaNg domain:   ${DOMAIN_ARIA} -> :${ARIANG_PORT}"
log_info "Mac pullback:    ${MAC_DOWNLOAD_DIR}"
log_info "Default dl:      ${DEFAULT_DOWNLOAD_DIR} (OpenList -> cloud auto-upload)"

# ============================================================
# Step 2: System dependencies
# ============================================================
log_step "Step 2: System dependencies"

log_info "Updating package list..."
apt-get update -y

log_info "Installing base tools..."
apt-get install -y curl wget openssl ca-certificates

# Docker
if ! command -v docker &>/dev/null; then
    log_info "Installing Docker..."
    curl -fsSL https://get.docker.com | bash
    systemctl enable --now docker
    log_info "Docker installed and started"
else
    log_info "Docker: $(docker --version 2>&1)"
fi

# Hysteria 2
if ! command -v hysteria &>/dev/null; then
    log_info "Installing Hysteria 2..."
    HY2_VER=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
    if [ -z "$HY2_VER" ]; then
        log_error "Cannot get latest Hysteria 2 version"
        exit 1
    fi
    log_info "Downloading Hysteria 2 ${HY2_VER}..."
    wget -q -O /usr/local/bin/hysteria "https://github.com/apernet/hysteria/releases/download/${HY2_VER}/hysteria-linux-amd64"
    chmod +x /usr/local/bin/hysteria
    log_info "Hysteria 2 installed: $(hysteria version 2>&1 | head -1 || echo v${HY2_VER})"
else
    log_info "Hysteria 2: $(hysteria version 2>&1 | head -1 || true)"
fi

# ============================================================
# Step 3: Caddy (with apt fallback if getcaddy.com fails)
# ============================================================
log_step "Step 3: Caddy"

if ! command -v caddy &>/dev/null; then
    log_info "Installing Caddy via official script..."
    curl -fsSL https://getcaddy.com | bash -s personal 2>/dev/null || {
        log_warn "getcaddy.com failed, installing via apt..."
        apt-get install -y debian-keyring debian-archive-keyring 2>/dev/null || true
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null || true
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null 2>&1 || true
        apt-get update -y 2>/dev/null || true
        apt-get install -y caddy || {
            log_error "Caddy installation failed"
            exit 1
        }
    }
    log_info "Caddy installed: $(caddy version)"
else
    log_info "Caddy: $(caddy version)"
fi

# ============================================================
# Step 4: Download directories
# ============================================================
log_step "Step 4: Download directories"

# /opt/downloads: default path for OpenList-triggered downloads -> cloud auto-upload
mkdir -p "${DEFAULT_DOWNLOAD_DIR}"
chmod 777 "${DEFAULT_DOWNLOAD_DIR}"
log_info "Default dl dir: ${DEFAULT_DOWNLOAD_DIR} (OpenList -> cloud)"

# /opt/mac: Mac rsync pullback directory (WebUI manual selection)
mkdir -p "${MAC_DOWNLOAD_DIR}"
chmod 777 "${MAC_DOWNLOAD_DIR}"
log_info "Mac pullback dir: ${MAC_DOWNLOAD_DIR} (WebUI -> rsync)"

# ============================================================
# Step 5: OpenList (one-click install)
# ============================================================
log_step "Step 5: OpenList"

if systemctl is-active --quiet openlist 2>/dev/null; then
    log_info "OpenList already running"
else
    log_info "Installing OpenList..."
    curl -fsSL https://res.oplist.org/script/v4.sh -o install-openlist-v4.sh
    # Interactive flow: select "1" (install directly), then Enter, Enter again
    printf '1\n\n\n' | bash install-openlist-v4.sh 2>&1 | tee /tmp/openlist-install.log
    # Capture the last 15 lines of install output (contains credentials)
    OL_CREDENTIALS=$(tail -20 /tmp/openlist-install.log 2>/dev/null || true)
    rm -f install-openlist-v4.sh
    sleep 2
    systemctl enable --now openlist 2>/dev/null || {
        log_warn "OpenList systemd service not auto-created, starting manually..."
        nohup /opt/openlist/openlist > /var/log/openlist.log 2>&1 &
    }
    if [ -n "$OL_CREDENTIALS" ]; then
        log_info "OpenList credentials:"
        echo "$OL_CREDENTIALS" | while IFS= read -r line; do echo "    $line"; done
    fi
    rm -f /tmp/openlist-install.log
    log_info "OpenList started on port: ${OPENLIST_PORT}"
fi

# ============================================================
# Step 6: qBittorrent (Docker, --network host)
# ============================================================
log_step "Step 6: qBittorrent"

docker rm -f qbittorrent 2>/dev/null || true
docker run -d --name qbittorrent \
  --network host \
  -e PUID=1000 -e PGID=1000 \
  -e WEBUI_PORT=${QB_PORT} \
  -v ${DEFAULT_DOWNLOAD_DIR}:/downloads \
  -v ${MAC_DOWNLOAD_DIR}:${MAC_DOWNLOAD_DIR} \
  -v /opt/qbittorrent-config:/config \
  --restart unless-stopped \
  linuxserver/qbittorrent

log_info "qBittorrent deployed, WebUI port: ${QB_PORT}"
log_info "  - Default save path: /downloads (= ${DEFAULT_DOWNLOAD_DIR}, OpenList auto-upload cloud)"
log_info "  - Mac pullback path: ${MAC_DOWNLOAD_DIR} (WebUI manual selection)"

# ============================================================
# Step 7: Aria2 (Docker, --network host)
# ============================================================
log_step "Step 7: Aria2"

docker rm -f aria2 2>/dev/null || true
docker run -d --name aria2 \
  --network host \
  -e RPC_SECRET=${ARIA2_RPC_SECRET} \
  -e RPC_PORT=${ARIA_PORT} \
  -v ${DEFAULT_DOWNLOAD_DIR}:/downloads \
  -v ${MAC_DOWNLOAD_DIR}:${MAC_DOWNLOAD_DIR} \
  -v /opt/aria2-config:/config \
  --restart unless-stopped \
  p3terx/aria2-pro

log_info "Aria2 deployed, RPC port: ${ARIA_PORT}"
log_info "  - Default save path: /downloads (= ${DEFAULT_DOWNLOAD_DIR}, OpenList auto-upload cloud)"
log_info "  - Mac pullback path: ${MAC_DOWNLOAD_DIR} (WebUI manual selection)"

# ============================================================
# Step 8: AriaNg (Docker, --network host)
# ============================================================
log_step "Step 8: AriaNg"

docker rm -f ariang 2>/dev/null || true
docker run -d --name ariang \
  --network host \
  -e ARIANG_PORT=${ARIANG_PORT} \
  --restart unless-stopped \
  p3terx/ariang

log_info "AriaNg deployed, WebUI port: ${ARIANG_PORT}"
log_info "  - Connect Aria2 RPC at: localhost:${ARIA_PORT}"
log_info "  - RPC secret: ${ARIA2_RPC_SECRET}"

# ============================================================
# Step 9: HY2 Server config & self-signed cert
# ============================================================
log_step "Step 9: HY2 Server config"

mkdir -p /etc/hysteria

log_info "Generating self-signed cert (CN=${DOMAIN_OPENLIST})..."
openssl genrsa -out /etc/hysteria/server.key 2048

openssl req -new -x509 -key /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 \
  -subj "/CN=${DOMAIN_OPENLIST}" \
  -addext "subjectAltName=DNS:${DOMAIN_OPENLIST},DNS:${DOMAIN_QB},DNS:${DOMAIN_ARIA}" \
  2>/dev/null || {
    log_warn "OpenSSL -addext not supported, using CN-only cert..."
    openssl req -new -x509 -key /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 \
      -subj "/CN=${DOMAIN_OPENLIST}"
}

# IMPORTANT: Netherlands HY2 Server does NOT configure tcpForwarding.
# Port forwarding is configured on the Mac Client side instead.
cat > /etc/hysteria/server.yaml <<YEOF
listen: :${HY2_PORT}
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: "${HY2_PASSWORD}"
YEOF

log_info "HY2 config written: /etc/hysteria/server.yaml"
log_info "  - tcpForwarding: NOT configured (handled by Mac Client)"

# ============================================================
# Step 10: HY2 systemd service
# ============================================================
log_step "Step 10: HY2 systemd service"

cat > /etc/systemd/system/hysteria-server.service <<SEOF
[Unit]
Description=Hysteria 2 Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/server.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SEOF

systemctl daemon-reload
systemctl enable --now hysteria-server
sleep 1

if systemctl is-active --quiet hysteria-server 2>/dev/null; then
    log_info "HY2 Server running and enabled on boot"
else
    log_warn "HY2 Server failed to start, check: journalctl -u hysteria-server -f"
fi

# ============================================================
# Step 11: Caddy reverse proxy config
# ============================================================
log_step "Step 11: Caddy config"

mkdir -p /etc/caddy

# Caddyfile: each site block must have curly braces on separate lines
cat > /etc/caddy/Caddyfile <<CEOF
${DOMAIN_OPENLIST} {
    reverse_proxy 127.0.0.1:${OPENLIST_PORT}
}
${DOMAIN_QB} {
    reverse_proxy 127.0.0.1:${QB_PORT}
}
${DOMAIN_ARIA} {
    reverse_proxy 127.0.0.1:${ARIANG_PORT}
}
CEOF

# Validate Caddyfile syntax before restarting
if ! caddy validate --config /etc/caddy/Caddyfile 2>/dev/null; then
    log_error "Caddy config validation failed"
    cat /etc/caddy/Caddyfile
    exit 1
fi

systemctl enable --now caddy 2>/dev/null || true
systemctl restart caddy 2>/dev/null || {
    log_warn "Caddy restart failed, trying to start directly..."
    systemctl start caddy 2>/dev/null || true
}
sleep 2

if systemctl is-active --quiet caddy 2>/dev/null; then
    log_info "Caddy running with reverse proxy config"
else
    log_warn "Caddy failed to start, check: journalctl -u caddy -n 10"
    journalctl -u caddy --no-pager -n 5 2>/dev/null || true
fi

# ============================================================
# Step 12: Deployment result
# ============================================================
log_step "Step 12: Result"

echo ""
echo "========================================"
echo "  Netherlands VPS Deployment Complete!"
echo "========================================"
echo ""
echo "--- Service Status ---"
echo ""
echo "Caddy:"
systemctl is-active caddy 2>/dev/null && echo "  [OK] Running" || echo "  [FAIL] Not running"
echo ""
echo "Hysteria 2 Server:"
systemctl is-active hysteria-server 2>/dev/null && echo "  [OK] Running" || echo "  [FAIL] Not running"
echo ""
echo "OpenList:"
systemctl is-active openlist 2>/dev/null && echo "  [OK] Running" || echo "  [FAIL] Check install"
echo ""
echo "Docker containers:"
docker ps --format "  {{.Names}}: {{.Status}}" 2>/dev/null || echo "  N/A"
echo ""
echo "--- URLs ---"
echo "  OpenList:  https://${DOMAIN_OPENLIST}"
echo "  qB WebUI:  https://${DOMAIN_QB}       (default: admin / adminadmin)"
echo "  AriaNg:    https://${DOMAIN_ARIA}"
echo ""
echo "--- Key Info ---"
echo "  HY2 port:           ${HY2_PORT}"
echo "  HY2 password:       ${HY2_PASSWORD}"
echo "  Aria2 RPC secret:   ${ARIA2_RPC_SECRET}"
echo "  Aria2 RPC port:     ${ARIA_PORT}"
echo "  Default dl dir:     ${DEFAULT_DOWNLOAD_DIR}  (OpenList -> cloud auto-upload)"
echo "  Mac pullback dir:   ${MAC_DOWNLOAD_DIR}       (WebUI manual -> rsync)"
echo ""
echo "--- Download Paths ---"
echo "  Path 1 (OpenList): auto-call qB/Aria2 -> ${DEFAULT_DOWNLOAD_DIR} -> cloud upload"
echo "  Path 2 (WebUI):    manual select ${MAC_DOWNLOAD_DIR} -> Mac rsync pullback"
echo ""
echo "--- Verify ---"
echo "  curl -k https://${DOMAIN_OPENLIST}"
echo "  curl -k https://${DOMAIN_QB}"
echo "  curl -k https://${DOMAIN_ARIA}"
echo "  systemctl status hysteria-server caddy openlist"
echo "  docker ps"
echo ""
echo "========================================"
