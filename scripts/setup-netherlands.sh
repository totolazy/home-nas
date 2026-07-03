#!/bin/bash
# ============================================================
# 家庭NAS - 荷兰VPS 一键部署脚本
#
# 部署组件:
#   - Caddy (反向代理, 自动 HTTPS)
#   - Hysteria 2 Server (加密隧道, 无 tcpForwarding)
#   - OpenList (文件列表, 裸机安装)
#   - qBittorrent (BT 下载, Docker)
#   - Aria2 (多协议下载, Docker)
#   - AriaNg (Aria2 WebUI, Docker)
#
# 两条下载路径:
#   1. OpenList 内置调用 qB/Aria2 → 默认路径 → 自动上传网盘
#   2. WebUI 手动选择 /opt/mac/ → Mac rsync 回传
#
# 用法: chmod +x setup-netherlands.sh && sudo ./setup-netherlands.sh
# ============================================================
set -euo pipefail

# ============================================================
# 颜色定义
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
# 权限检查
# ============================================================
if [ "$(id -u)" -ne 0 ]; then
    log_error "请以 root 用户运行此脚本: sudo ./setup-netherlands.sh"
    exit 1
fi

# ============================================================
# 默认配置
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
# Step 1: 交互式输入
# ============================================================
log_step "Step 1: 配置确认"

echo "========================================"
echo "  家庭NAS - 荷兰VPS 一键部署脚本"
echo "========================================"
echo ""

read -rp "请输入 HY2 认证密码: " HY2_PASSWORD
if [ -z "$HY2_PASSWORD" ]; then
    log_error "HY2 认证密码不能为空"
    exit 1
fi

read -rp "请输入 OpenList 子域名 (默认: nllist.dickgroup.xyz): " DOMAIN_OPENLIST
DOMAIN_OPENLIST=${DOMAIN_OPENLIST:-nllist.dickgroup.xyz}

read -rp "请输入 qBittorrent 子域名 (默认: qb.dickgroup.xyz): " DOMAIN_QB
DOMAIN_QB=${DOMAIN_QB:-qb.dickgroup.xyz}

read -rp "请输入 AriaNg 子域名 (默认: aria.dickgroup.xyz): " DOMAIN_ARIA
DOMAIN_ARIA=${DOMAIN_ARIA:-aria.dickgroup.xyz}

echo ""
log_info "配置确认:"
echo "  HY2 端口:        ${HY2_PORT}"
echo "  OpenList 域名:   ${DOMAIN_OPENLIST}  → :${OPENLIST_PORT}"
echo "  qB WebUI 域名:   ${DOMAIN_QB}       → :${QB_PORT}"
echo "  AriaNg 域名:     ${DOMAIN_ARIA}     → :${ARIANG_PORT}"
echo "  Mac 回传目录:     ${MAC_DOWNLOAD_DIR}"
echo "  默认下载目录:     ${DEFAULT_DOWNLOAD_DIR} (OpenList → 网盘自动上传)"
echo ""

read -rp "确认以上配置? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "已取消部署"
    exit 0
fi

# ============================================================
# Step 2: 安装系统依赖
# ============================================================
log_step "Step 2: 安装系统依赖"

log_info "更新软件包列表..."
apt-get update -y

log_info "安装基础工具..."
apt-get install -y curl wget openssl ca-certificates

# 安装 Docker
if ! command -v docker &>/dev/null; then
    log_info "安装 Docker..."
    curl -fsSL https://get.docker.com | bash
    systemctl enable --now docker
    log_info "Docker 已安装并启动"
else
    log_info "Docker 已安装: $(docker --version)"
fi

# 安装 Hysteria 2
if ! command -v hysteria &>/dev/null; then
    log_info "安装 Hysteria 2..."
    HY2_VER=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
    if [ -z "$HY2_VER" ]; then
        log_error "无法获取 Hysteria 2 最新版本号"
        exit 1
    fi
    log_info "下载 Hysteria 2 ${HY2_VER}..."
    wget -q -O /usr/local/bin/hysteria "https://github.com/apernet/hysteria/releases/download/${HY2_VER}/hysteria-linux-amd64"
    chmod +x /usr/local/bin/hysteria
    log_info "Hysteria 2 已安装: $(hysteria version 2>&1 | head -1 || echo 'v${HY2_VER}')"
else
    log_info "Hysteria 2 已安装: $(hysteria version 2>&1 | head -1 || true)"
fi

# ============================================================
# Step 3: 安装 Caddy
# ============================================================
log_step "Step 3: 安装 Caddy"

if ! command -v caddy &>/dev/null; then
    log_info "安装 Caddy..."
    curl -fsSL https://getcaddy.com | bash -s personal
    log_info "Caddy 已安装: $(caddy version)"
else
    log_info "Caddy 已安装: $(caddy version)"
fi

# ============================================================
# Step 4: 创建下载目录
# ============================================================
log_step "Step 4: 创建下载目录"

# /opt/downloads: 默认下载路径 (OpenList 调用 qB/Aria2 → 自动上传网盘)
mkdir -p "${DEFAULT_DOWNLOAD_DIR}"
chmod 777 "${DEFAULT_DOWNLOAD_DIR}"
log_info "默认下载目录已创建: ${DEFAULT_DOWNLOAD_DIR} (OpenList → 网盘)"

# /opt/mac: Mac rsync 回传专用目录 (WebUI 手动选择)
mkdir -p "${MAC_DOWNLOAD_DIR}"
chmod 777 "${MAC_DOWNLOAD_DIR}"
log_info "Mac 回传目录已创建: ${MAC_DOWNLOAD_DIR} (WebUI → rsync 回传)"

# ============================================================
# Step 5: 安装 OpenList（一键脚本）
# ============================================================
log_step "Step 5: 安装 OpenList"

if systemctl is-active --quiet openlist 2>/dev/null; then
    log_info "OpenList 已在运行，跳过安装"
else
    log_info "下载并执行 OpenList 安装脚本..."
    curl -fsSL https://raw.githubusercontent.com/OpenListTeam/OpenList/main/install.sh | bash
    sleep 2
    systemctl enable --now openlist 2>/dev/null || {
        log_warn "OpenList systemd 服务未自动创建，尝试手动启动..."
        nohup /opt/openlist/openlist > /var/log/openlist.log 2>&1 &
    }
    log_info "OpenList 已启动，监听端口: ${OPENLIST_PORT}"
fi

# ============================================================
# Step 6: 部署 qBittorrent（Docker, --network host）
# ============================================================
log_step "Step 6: 部署 qBittorrent"

if docker ps -a --format "{{.Names}}" | grep -q "^qbittorrent$"; then
    log_info "移除已存在的 qbittorrent 容器..."
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

log_info "qBittorrent 已部署，WebUI 端口: ${QB_PORT}"
log_info "  - 默认保存路径: /downloads (= ${DEFAULT_DOWNLOAD_DIR}, OpenList 自动上传网盘)"
log_info "  - Mac 回传路径: ${MAC_DOWNLOAD_DIR} (WebUI 手动选择)"

# ============================================================
# Step 7: 部署 Aria2（Docker, --network host）
# ============================================================
log_step "Step 7: 部署 Aria2"

if docker ps -a --format "{{.Names}}" | grep -q "^aria2$"; then
    log_info "移除已存在的 aria2 容器..."
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

log_info "Aria2 已部署，RPC 端口: ${ARIA_PORT}"
log_info "  - 默认保存路径: /downloads (= ${DEFAULT_DOWNLOAD_DIR}, OpenList 自动上传网盘)"
log_info "  - Mac 回传路径: ${MAC_DOWNLOAD_DIR} (WebUI 手动选择)"

# ============================================================
# Step 8: 部署 AriaNg（Docker, --network host）
# ============================================================
log_step "Step 8: 部署 AriaNg"

if docker ps -a --format "{{.Names}}" | grep -q "^ariang$"; then
    log_info "移除已存在的 ariang 容器..."
    docker rm -f ariang 2>/dev/null || true
fi

docker run -d --name ariang \
  --network host \
  -e ARIANG_PORT=${ARIANG_PORT} \
  --restart unless-stopped \
  p3terx/ariang

log_info "AriaNg 已部署，WebUI 端口: ${ARIANG_PORT}"
log_info "  - AriaNg 连接 Aria2 RPC 时使用: localhost:${ARIA_PORT}"
log_info "  - RPC 密钥: ${ARIA2_RPC_SECRET}"

# ============================================================
# Step 9: 生成 HY2 Server 配置与自签名证书
# ============================================================
log_step "Step 9: 生成 HY2 Server 配置"

mkdir -p /etc/hysteria

# 生成自签名证书
log_info "生成自签名证书 (CN=${DOMAIN_OPENLIST})..."
openssl genrsa -out /etc/hysteria/server.key 2048

# -addext 用于添加 SAN，兼容 OpenSSL 1.1.1+
openssl req -new -x509 -key /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 \
  -subj "/CN=${DOMAIN_OPENLIST}" \
  -addext "subjectAltName=DNS:${DOMAIN_OPENLIST},DNS:${DOMAIN_QB},DNS:${DOMAIN_ARIA}" \
  2>/dev/null || {
    # 兼容旧版 OpenSSL 的回退方案 (无 -addext)
    log_warn "OpenSSL 不支持 -addext，使用基础 CN 方式生成证书..."
    openssl req -new -x509 -key /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 \
      -subj "/CN=${DOMAIN_OPENLIST}"
}

# 荷兰 HY2 Server 不配 tcpForwarding，端口转发在 Mac Client 侧配置
cat > /etc/hysteria/server.yaml <<EOF
listen: :${HY2_PORT}
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: "${HY2_PASSWORD}"
EOF

log_info "HY2 Server 配置已生成: /etc/hysteria/server.yaml"
log_info "  - tcpForwarding: 未配置 (端口转发在 Mac Client 侧)"

# ============================================================
# Step 10: 创建 HY2 systemd 服务
# ============================================================
log_step "Step 10: 创建 HY2 systemd 服务"

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
    log_info "HY2 Server 已启动并设为开机自启"
else
    log_warn "HY2 Server 未能启动，请检查: journalctl -u hysteria-server -f"
fi

# ============================================================
# Step 11: 生成 Caddy 反向代理配置
# ============================================================
log_step "Step 11: 生成 Caddy 配置"

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
    log_info "Caddy 配置已应用并重启"
else
    log_warn "Caddy 未能启动，请检查: journalctl -u caddy -f"
fi

# ============================================================
# Step 12: 输出部署结果
# ============================================================
log_step "Step 12: 部署结果"

echo ""
echo "========================================"
echo "  荷兰 VPS 部署完成！"
echo "========================================"
echo ""
echo "--- 服务状态 ---"
echo ""
echo "Caddy:"
systemctl is-active caddy 2>/dev/null && echo "  ✓ 运行中" || echo "  ✗ 未运行"
echo ""
echo "Hysteria 2 Server:"
systemctl is-active hysteria-server 2>/dev/null && echo "  ✓ 运行中" || echo "  ✗ 未运行"
echo ""
echo "OpenList:"
systemctl is-active openlist 2>/dev/null && echo "  ✓ 运行中" || echo "  ✗ 未运行 (请检查安装)"
echo ""
echo "Docker 容器:"
docker ps --format "  {{.Names}}: {{.Status}}" 2>/dev/null || echo "  Docker 未运行"
echo ""
echo "--- 访问地址 ---"
echo "  OpenList:  https://${DOMAIN_OPENLIST}"
echo "  qB WebUI:  https://${DOMAIN_QB}       (默认: admin / adminadmin)"
echo "  AriaNg:    https://${DOMAIN_ARIA}"
echo ""
echo "--- 关键信息 ---"
echo "  HY2 端口:           ${HY2_PORT}"
echo "  HY2 密码:           ${HY2_PASSWORD}"
echo "  Aria2 RPC 密钥:     ${ARIA2_RPC_SECRET}"
echo "  Aria2 RPC 端口:     ${ARIA_PORT}"
echo "  默认下载目录:        ${DEFAULT_DOWNLOAD_DIR}  (OpenList → 网盘自动上传)"
echo "  Mac 回传目录:        ${MAC_DOWNLOAD_DIR}       (WebUI 手动选择 → rsync 回传)"
echo ""
echo "--- 下载路径说明 ---"
echo "  路径 1 (OpenList): 内置调用 qB/Aria2 → ${DEFAULT_DOWNLOAD_DIR} → 自动上传网盘"
echo "  路径 2 (WebUI):    手动选择 ${MAC_DOWNLOAD_DIR} → Mac rsync pullback"
echo ""
echo "--- 验证命令 ---"
echo "  curl -I https://${DOMAIN_OPENLIST}"
echo "  curl -I https://${DOMAIN_QB}"
echo "  curl -I https://${DOMAIN_ARIA}"
echo "  systemctl status hysteria-server caddy openlist"
echo "  docker ps"
echo ""
echo "========================================"

