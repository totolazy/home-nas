#!/bin/bash
# ============================================================
# 家庭NAS - 荷兰 VPS 卸载脚本
# 清理: Docker 容器 (qbittorrent/aria2/ariang)、
#        Hysteria 2 Server、OpenList、Caddy 站点配置
# 保留: Docker Engine、Caddy 软件本身
#
# 用法: sudo bash teardown-netherlands.sh
# ============================================================

set -euo pipefail

# ============================================================
# 颜色
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ============================================================
# 前置检查
# ============================================================
if [ "$(id -u)" -ne 0 ]; then
    log_error "请使用 root 权限运行: sudo bash $0"
    exit 1
fi

# ============================================================
# 交互式确认
# ============================================================
echo ""
echo "=============================================="
echo "  荷兰 VPS 卸载脚本"
echo "=============================================="
echo ""
echo -e "  ${RED}将删除以下内容:${NC}"
echo ""
echo "  Docker 容器:"
echo "    - qbittorrent"
echo "    - aria2"
echo "    - ariang"
echo ""
echo "  数据目录:"
echo "    - /opt/qbittorrent-config"
echo "    - /opt/aria2-config"
echo "    - /opt/mac"
echo ""
echo "  系统服务:"
echo "    - Hysteria 2 Server (hysteria-server)"
echo "    - OpenList (openlist)"
echo ""
echo "  配置文件:"
echo "    - /etc/caddy/Caddyfile (清空)"
echo "    - /etc/hysteria/"
echo "    - /etc/systemd/system/hysteria-server.service"
echo "    - /etc/systemd/system/openlist.service"
echo "    - /usr/local/bin/hysteria"
echo "    - /opt/openlist"
echo ""
echo -e "  ${GREEN}保留:${NC}"
echo "    - Docker Engine"
echo "    - Caddy 软件"
echo ""
echo "=============================================="
echo ""

read -p "确认卸载？输入 yes 继续: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    log_info "已取消。"
    exit 0
fi

echo ""
log_warn "开始卸载..."

# ============================================================
# Step 1: 停止并删除 Docker 容器
# ============================================================
echo ""
log_info "删除 Docker 容器..."

for container in qbittorrent aria2 ariang; do
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$container"; then
        log_info "  删除容器: $container"
        docker rm -f "$container"
    else
        log_info "  容器 $container 不存在，跳过。"
    fi
done

# ============================================================
# Step 2: 删除数据目录
# ============================================================
echo ""
log_info "删除数据目录..."
rm -rf /opt/qbittorrent-config
rm -rf /opt/aria2-config
rm -rf /opt/mac
log_info "  /opt/qbittorrent-config 已删除"
log_info "  /opt/aria2-config 已删除"
log_info "  /opt/mac 已删除"

# ============================================================
# Step 3: 停止并删除 Hysteria 2 Server
# ============================================================
echo ""
log_info "停止并删除 Hysteria 2 Server..."

if systemctl is-active --quiet hysteria-server 2>/dev/null; then
    log_info "  停止 hysteria-server 服务..."
    systemctl stop hysteria-server
else
    log_info "  hysteria-server 服务未运行，跳过停止。"
fi

if systemctl is-enabled --quiet hysteria-server 2>/dev/null; then
    log_info "  禁用 hysteria-server 开机自启..."
    systemctl disable hysteria-server
fi

rm -f /etc/systemd/system/hysteria-server.service
systemctl daemon-reload
rm -rf /etc/hysteria
rm -f /usr/local/bin/hysteria
log_info "  Hysteria 2 Server 相关文件已删除。"

# ============================================================
# Step 4: 停止并删除 OpenList
# ============================================================
echo ""
log_info "停止并删除 OpenList..."

if systemctl is-active --quiet openlist 2>/dev/null; then
    log_info "  停止 openlist 服务..."
    systemctl stop openlist
else
    log_info "  openlist 服务未运行，跳过停止。"
fi

if systemctl is-enabled --quiet openlist 2>/dev/null; then
    log_info "  禁用 openlist 开机自启..."
    systemctl disable openlist
fi

rm -f /etc/systemd/system/openlist.service
systemctl daemon-reload
rm -rf /opt/openlist
log_info "  OpenList 相关文件已删除。"

# ============================================================
# Step 5: 清空 Caddy 配置
# ============================================================
echo ""
log_info "清空 Caddy 配置..."

if [ -f /etc/caddy/Caddyfile ]; then
    > /etc/caddy/Caddyfile
    systemctl reload caddy 2>/dev/null || systemctl restart caddy
    log_info "  Caddy 配置已清空并重载。"
else
    log_info "  /etc/caddy/Caddyfile 不存在，跳过。"
fi

# ============================================================
# 完成
# ============================================================
echo ""
echo "=============================================="
echo -e "  ${GREEN}荷兰 VPS 卸载完成${NC}"
echo "=============================================="
