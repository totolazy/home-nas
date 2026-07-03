#!/bin/bash
# ============================================================
# 瀹跺涵NAS - 鑽峰叞VPS 涓€閿儴缃茶剼鏈?#
# 閮ㄧ讲缁勪欢:
#   - Caddy (鍙嶅悜浠ｇ悊, 鑷姩 HTTPS)
#   - Hysteria 2 Server (鍔犲瘑闅ч亾, 鏃?tcpForwarding)
#   - OpenList (鏂囦欢鍒楄〃, 瑁告満瀹夎)
#   - qBittorrent (BT 涓嬭浇, Docker)
#   - Aria2 (澶氬崗璁笅杞? Docker)
#   - AriaNg (Aria2 WebUI, Docker)
#
# 涓ゆ潯涓嬭浇璺緞:
#   1. OpenList 鍐呯疆璋冪敤 qB/Aria2 鈫?榛樿璺緞 鈫?鑷姩涓婁紶缃戠洏
#   2. WebUI 鎵嬪姩閫夋嫨 /opt/mac/ 鈫?Mac rsync 鍥炰紶
#
# 鐢ㄦ硶: chmod +x setup-netherlands.sh && sudo ./setup-netherlands.sh
# ============================================================
set -euo pipefail

# ============================================================
# 棰滆壊瀹氫箟
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "\n${BLUE}==== $* ====${NC}"; }

# ============================================================
# 鏉冮檺妫€鏌?# ============================================================
if [ "$(id -u)" -ne 0 ]; then
    log_error "璇蜂互 root 鐢ㄦ埛杩愯姝よ剼鏈? sudo ./setup-netherlands.sh"
    exit 1
fi

# ============================================================
# 榛樿閰嶇疆
# ============================================================
HY2_PORT=8443
OPENLIST_PORT=5244
QB_PORT=8080
ARIA_PORT=6800
ARIANG_PORT=6880
MAC_DOWNLOAD_DIR=/opt/mac
DEFAULT_DOWNLOAD_DIR=/opt/downloads
ARIA2_RPC_SECRET="openlist2024"

# ============================================================
# Step 1: 浜や簰寮忚緭鍏?# ============================================================
log_step "Step 1: 閰嶇疆纭"

echo "========================================"
echo "  瀹跺涵NAS - 鑽峰叞VPS 涓€閿儴缃茶剼鏈?
echo "========================================"
echo ""

read -rp "璇疯緭鍏?HY2 璁よ瘉瀵嗙爜: " HY2_PASSWORD
if [ -z "$HY2_PASSWORD" ]; then
    log_error "HY2 璁よ瘉瀵嗙爜涓嶈兘涓虹┖"
    exit 1
fi

read -rp "璇疯緭鍏?OpenList 瀛愬煙鍚?(榛樿: nllist.dickgroup.xyz): " DOMAIN_OPENLIST
DOMAIN_OPENLIST=${DOMAIN_OPENLIST:-nllist.dickgroup.xyz}

read -rp "璇疯緭鍏?qBittorrent 瀛愬煙鍚?(榛樿: qb.dickgroup.xyz): " DOMAIN_QB
DOMAIN_QB=${DOMAIN_QB:-qb.dickgroup.xyz}

read -rp "璇疯緭鍏?AriaNg 瀛愬煙鍚?(榛樿: aria.dickgroup.xyz): " DOMAIN_ARIA
DOMAIN_ARIA=${DOMAIN_ARIA:-aria.dickgroup.xyz}

echo ""
log_info "閰嶇疆纭:"
echo "  HY2 绔彛:        ${HY2_PORT}"
echo "  OpenList 鍩熷悕:   ${DOMAIN_OPENLIST}  鈫?:${OPENLIST_PORT}"
echo "  qB WebUI 鍩熷悕:   ${DOMAIN_QB}       鈫?:${QB_PORT}"
echo "  AriaNg 鍩熷悕:     ${DOMAIN_ARIA}     鈫?:${ARIANG_PORT}"
echo "  Mac 鍥炰紶鐩綍:     ${MAC_DOWNLOAD_DIR}"
echo "  榛樿涓嬭浇鐩綍:     ${DEFAULT_DOWNLOAD_DIR} (OpenList 鈫?缃戠洏鑷姩涓婁紶)"
echo ""

read -rp "纭浠ヤ笂閰嶇疆? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "宸插彇娑堥儴缃?
    exit 0
fi

# ============================================================
# Step 2: 瀹夎绯荤粺渚濊禆
# ============================================================
log_step "Step 2: 瀹夎绯荤粺渚濊禆"

log_info "鏇存柊杞欢鍖呭垪琛?.."
apt-get update -y

log_info "瀹夎鍩虹宸ュ叿..."
apt-get install -y curl wget openssl ca-certificates

# 瀹夎 Docker
if ! command -v docker &>/dev/null; then
    log_info "瀹夎 Docker..."
    curl -fsSL https://get.docker.com | bash
    systemctl enable --now docker
    log_info "Docker 宸插畨瑁呭苟鍚姩"
else
    log_info "Docker 宸插畨瑁? $(docker --version)"
fi

# 瀹夎 Hysteria 2
if ! command -v hysteria &>/dev/null; then
    log_info "瀹夎 Hysteria 2..."
    HY2_VER=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
    if [ -z "$HY2_VER" ]; then
        log_error "鏃犳硶鑾峰彇 Hysteria 2 鏈€鏂扮増鏈彿"
        exit 1
    fi
    log_info "涓嬭浇 Hysteria 2 ${HY2_VER}..."
    wget -q -O /usr/local/bin/hysteria "https://github.com/apernet/hysteria/releases/download/${HY2_VER}/hysteria-linux-amd64"
    chmod +x /usr/local/bin/hysteria
    log_info "Hysteria 2 宸插畨瑁? $(hysteria version 2>&1 | head -1 || echo 'v${HY2_VER}')"
else
    log_info "Hysteria 2 宸插畨瑁? $(hysteria version 2>&1 | head -1 || true)"
fi

# ============================================================
# Step 3: 瀹夎 Caddy
# ============================================================
log_step "Step 3: 瀹夎 Caddy"

if ! command -v caddy &>/dev/null; then
    log_info "瀹夎 Caddy..."
    curl -fsSL https://getcaddy.com | bash -s personal
    log_info "Caddy 宸插畨瑁? $(caddy version)"
else
    log_info "Caddy 宸插畨瑁? $(caddy version)"
fi

# ============================================================
# Step 4: 鍒涘缓涓嬭浇鐩綍
# ============================================================
log_step "Step 4: 鍒涘缓涓嬭浇鐩綍"

# /opt/downloads: 榛樿涓嬭浇璺緞 (OpenList 璋冪敤 qB/Aria2 鈫?鑷姩涓婁紶缃戠洏)
mkdir -p "${DEFAULT_DOWNLOAD_DIR}"
chmod 777 "${DEFAULT_DOWNLOAD_DIR}"
log_info "榛樿涓嬭浇鐩綍宸插垱寤? ${DEFAULT_DOWNLOAD_DIR} (OpenList 鈫?缃戠洏)"

# /opt/mac: Mac rsync 鍥炰紶涓撶敤鐩綍 (WebUI 鎵嬪姩閫夋嫨)
mkdir -p "${MAC_DOWNLOAD_DIR}"
chmod 777 "${MAC_DOWNLOAD_DIR}"
log_info "Mac 鍥炰紶鐩綍宸插垱寤? ${MAC_DOWNLOAD_DIR} (WebUI 鈫?rsync 鍥炰紶)"

# ============================================================
# Step 5: 瀹夎 OpenList锛堜竴閿剼鏈級
# ============================================================
log_step "Step 5: 瀹夎 OpenList"

if systemctl is-active --quiet openlist 2>/dev/null; then
    log_info "OpenList 宸插湪杩愯锛岃烦杩囧畨瑁?
else
    log_info "涓嬭浇骞舵墽琛?OpenList 瀹夎鑴氭湰..."
    curl -fsSL https://res.oplist.org/script/v4.sh -o install-openlist-v4.sh
    bash install-openlist-v4.sh
    rm -f install-openlist-v4.sh
    sleep 2
    systemctl enable --now openlist 2>/dev/null || {
        log_warn "OpenList systemd 鏈嶅姟鏈嚜鍔ㄥ垱寤猴紝灏濊瘯鎵嬪姩鍚姩..."
        nohup /opt/openlist/openlist > /var/log/openlist.log 2>&1 &
    }
    log_info "OpenList 宸插惎鍔紝鐩戝惉绔彛: ${OPENLIST_PORT}"
fi

# ============================================================
# Step 6: 閮ㄧ讲 qBittorrent锛圖ocker, --network host锛?# ============================================================
log_step "Step 6: 閮ㄧ讲 qBittorrent"

if docker ps -a --format "{{.Names}}" | grep -q "^qbittorrent$"; then
    log_info "绉婚櫎宸插瓨鍦ㄧ殑 qbittorrent 瀹瑰櫒..."
    docker rm -f qbittorrent 2>/dev/null || true
fi

docker run -d --name qbittorrent \
  --network host \
  -e PUID=1000 \
  -e PGID=1000 \
  -e WEBUI_PORT=${QB_PORT} \
  -v ${DEFAULT_DOWNLOAD_DIR}:/downloads \
  -v ${MAC_DOWNLOAD_DIR}:${MAC_DOWNLOAD_DIR} \
  -v /opt/qbittorrent-config:/config \
  --restart unless-stopped \
  linuxserver/qbittorrent

log_info "qBittorrent 宸查儴缃诧紝WebUI 绔彛: ${QB_PORT}"
log_info "  - 榛樿淇濆瓨璺緞: /downloads (= ${DEFAULT_DOWNLOAD_DIR}, OpenList 鑷姩涓婁紶缃戠洏)"
log_info "  - Mac 鍥炰紶璺緞: ${MAC_DOWNLOAD_DIR} (WebUI 鎵嬪姩閫夋嫨)"

# ============================================================
# Step 7: 閮ㄧ讲 Aria2锛圖ocker, --network host锛?# ============================================================
log_step "Step 7: 閮ㄧ讲 Aria2"

if docker ps -a --format "{{.Names}}" | grep -q "^aria2$"; then
    log_info "绉婚櫎宸插瓨鍦ㄧ殑 aria2 瀹瑰櫒..."
    docker rm -f aria2 2>/dev/null || true
fi

docker run -d --name aria2 \
  --network host \
  -e RPC_SECRET=${ARIA2_RPC_SECRET} \
  -e RPC_PORT=${ARIA_PORT} \
  -v ${DEFAULT_DOWNLOAD_DIR}:/downloads \
  -v ${MAC_DOWNLOAD_DIR}:${MAC_DOWNLOAD_DIR} \
  -v /opt/aria2-config:/config \
  --restart unless-stopped \
  p3terx/aria2-pro

log_info "Aria2 宸查儴缃诧紝RPC 绔彛: ${ARIA_PORT}"
log_info "  - 榛樿淇濆瓨璺緞: /downloads (= ${DEFAULT_DOWNLOAD_DIR}, OpenList 鑷姩涓婁紶缃戠洏)"
log_info "  - Mac 鍥炰紶璺緞: ${MAC_DOWNLOAD_DIR} (WebUI 鎵嬪姩閫夋嫨)"

# ============================================================
# Step 8: 閮ㄧ讲 AriaNg锛圖ocker, --network host锛?# ============================================================
log_step "Step 8: 閮ㄧ讲 AriaNg"

if docker ps -a --format "{{.Names}}" | grep -q "^ariang$"; then
    log_info "绉婚櫎宸插瓨鍦ㄧ殑 ariang 瀹瑰櫒..."
    docker rm -f ariang 2>/dev/null || true
fi

docker run -d --name ariang \
  --network host \
  -e ARIANG_PORT=${ARIANG_PORT} \
  --restart unless-stopped \
  p3terx/ariang

log_info "AriaNg 宸查儴缃诧紝WebUI 绔彛: ${ARIANG_PORT}"
log_info "  - AriaNg 杩炴帴 Aria2 RPC 鏃朵娇鐢? localhost:${ARIA_PORT}"
log_info "  - RPC 瀵嗛挜: ${ARIA2_RPC_SECRET}"

# ============================================================
# Step 9: 鐢熸垚 HY2 Server 閰嶇疆涓庤嚜绛惧悕璇佷功
# ============================================================
log_step "Step 9: 鐢熸垚 HY2 Server 閰嶇疆"

mkdir -p /etc/hysteria

# 鐢熸垚鑷鍚嶈瘉涔?log_info "鐢熸垚鑷鍚嶈瘉涔?(CN=${DOMAIN_OPENLIST})..."
openssl genrsa -out /etc/hysteria/server.key 2048

# -addext 鐢ㄤ簬娣诲姞 SAN锛屽吋瀹?OpenSSL 1.1.1+
openssl req -new -x509 -key /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 \
  -subj "/CN=${DOMAIN_OPENLIST}" \
  -addext "subjectAltName=DNS:${DOMAIN_OPENLIST},DNS:${DOMAIN_QB},DNS:${DOMAIN_ARIA}" \
  2>/dev/null || {
    # 鍏煎鏃х増 OpenSSL 鐨勫洖閫€鏂规 (鏃?-addext)
    log_warn "OpenSSL 涓嶆敮鎸?-addext锛屼娇鐢ㄥ熀纭€ CN 鏂瑰紡鐢熸垚璇佷功..."
    openssl req -new -x509 -key /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 \
      -subj "/CN=${DOMAIN_OPENLIST}"
}

# 鑽峰叞 HY2 Server 涓嶉厤 tcpForwarding锛岀鍙ｈ浆鍙戝湪 Mac Client 渚ч厤缃?cat > /etc/hysteria/server.yaml <<EOF
listen: :${HY2_PORT}
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: "${HY2_PASSWORD}"
EOF

log_info "HY2 Server 閰嶇疆宸茬敓鎴? /etc/hysteria/server.yaml"
log_info "  - tcpForwarding: 鏈厤缃?(绔彛杞彂鍦?Mac Client 渚?"

# ============================================================
# Step 10: 鍒涘缓 HY2 systemd 鏈嶅姟
# ============================================================
log_step "Step 10: 鍒涘缓 HY2 systemd 鏈嶅姟"

cat > /etc/systemd/system/hysteria-server.service <<EOF
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
EOF

systemctl daemon-reload
systemctl enable --now hysteria-server

if systemctl is-active --quiet hysteria-server; then
    log_info "HY2 Server 宸插惎鍔ㄥ苟璁句负寮€鏈鸿嚜鍚?
else
    log_warn "HY2 Server 鏈兘鍚姩锛岃妫€鏌? journalctl -u hysteria-server -f"
fi

# ============================================================
# Step 11: 鐢熸垚 Caddy 鍙嶅悜浠ｇ悊閰嶇疆
# ============================================================
log_step "Step 11: 鐢熸垚 Caddy 閰嶇疆"

mkdir -p /etc/caddy

cat > /etc/caddy/Caddyfile <<EOF
${DOMAIN_OPENLIST} {
    reverse_proxy 127.0.0.1:${OPENLIST_PORT}
}
${DOMAIN_QB} {
    reverse_proxy 127.0.0.1:${QB_PORT}
}
${DOMAIN_ARIA} {
    reverse_proxy 127.0.0.1:${ARIANG_PORT}
}
EOF

systemctl enable --now caddy 2>/dev/null || true
systemctl restart caddy

if systemctl is-active --quiet caddy; then
    log_info "Caddy 閰嶇疆宸插簲鐢ㄥ苟閲嶅惎"
else
    log_warn "Caddy 鏈兘鍚姩锛岃妫€鏌? journalctl -u caddy -f"
fi

# ============================================================
# Step 12: 杈撳嚭閮ㄧ讲缁撴灉
# ============================================================
log_step "Step 12: 閮ㄧ讲缁撴灉"

echo ""
echo "========================================"
echo "  鑽峰叞 VPS 閮ㄧ讲瀹屾垚锛?
echo "========================================"
echo ""
echo "--- 鏈嶅姟鐘舵€?---"
echo ""
echo "Caddy:"
systemctl is-active caddy 2>/dev/null && echo "  鉁?杩愯涓? || echo "  鉁?鏈繍琛?
echo ""
echo "Hysteria 2 Server:"
systemctl is-active hysteria-server 2>/dev/null && echo "  鉁?杩愯涓? || echo "  鉁?鏈繍琛?
echo ""
echo "OpenList:"
systemctl is-active openlist 2>/dev/null && echo "  鉁?杩愯涓? || echo "  鉁?鏈繍琛?(璇锋鏌ュ畨瑁?"
echo ""
echo "Docker 瀹瑰櫒:"
docker ps --format "  {{.Names}}: {{.Status}}" 2>/dev/null || echo "  Docker 鏈繍琛?
echo ""
echo "--- 璁块棶鍦板潃 ---"
echo "  OpenList:  https://${DOMAIN_OPENLIST}"
echo "  qB WebUI:  https://${DOMAIN_QB}       (榛樿: admin / adminadmin)"
echo "  AriaNg:    https://${DOMAIN_ARIA}"
echo ""
echo "--- 鍏抽敭淇℃伅 ---"
echo "  HY2 绔彛:           ${HY2_PORT}"
echo "  HY2 瀵嗙爜:           ${HY2_PASSWORD}"
echo "  Aria2 RPC 瀵嗛挜:     ${ARIA2_RPC_SECRET}"
echo "  Aria2 RPC 绔彛:     ${ARIA_PORT}"
echo "  榛樿涓嬭浇鐩綍:        ${DEFAULT_DOWNLOAD_DIR}  (OpenList 鈫?缃戠洏鑷姩涓婁紶)"
echo "  Mac 鍥炰紶鐩綍:        ${MAC_DOWNLOAD_DIR}       (WebUI 鎵嬪姩閫夋嫨 鈫?rsync 鍥炰紶)"
echo ""
echo "--- 涓嬭浇璺緞璇存槑 ---"
echo "  璺緞 1 (OpenList): 鍐呯疆璋冪敤 qB/Aria2 鈫?${DEFAULT_DOWNLOAD_DIR} 鈫?鑷姩涓婁紶缃戠洏"
echo "  璺緞 2 (WebUI):    鎵嬪姩閫夋嫨 ${MAC_DOWNLOAD_DIR} 鈫?Mac rsync pullback"
echo ""
echo "--- 楠岃瘉鍛戒护 ---"
echo "  curl -I https://${DOMAIN_OPENLIST}"
echo "  curl -I https://${DOMAIN_QB}"
echo "  curl -I https://${DOMAIN_ARIA}"
echo "  systemctl status hysteria-server caddy openlist"
echo "  docker ps"
echo ""
echo "========================================"

