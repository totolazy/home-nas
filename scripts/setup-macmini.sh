#!/bin/bash
set -euo pipefail

# =============================================
# Mac Mini NAS 一键部署脚本
# 部署 HY2 Client ×2 + OpenList + rsync 回传
# =============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "\n${BLUE}>>>${NC} $1"; }

# =============================================
# Step 1: 交互式输入配置参数
# =============================================

echo ""
echo "======================================"
echo "  Mac Mini NAS 一键部署脚本"
echo "======================================"
echo ""

echo ">>> 请输入上海 HY2 Server 连接信息 <<<"
read -rp "  IP 地址     : " SHANGHAI_IP
read -rp "  HY2 端口    [8443]: " SHANGHAI_HY2_PORT
SHANGHAI_HY2_PORT=${SHANGHAI_HY2_PORT:-8443}
read -rsp "  HY2 密码    : " SHANGHAI_HY2_PASSWORD
echo ""

echo ""
echo ">>> 请输入荷兰 HY2 Server 连接信息 <<<"
read -rp "  IP 地址     : " NL_IP
read -rp "  HY2 端口    [8443]: " NL_HY2_PORT
NL_HY2_PORT=${NL_HY2_PORT:-8443}
read -rsp "  HY2 密码    : " NL_HY2_PASSWORD
echo ""

echo ""
read -rp ">>> 外接盘路径 (如 /Volumes/NAS/nas-downloads): " LOCAL_DOWNLOAD_DIR

# 固定参数
NL_USER="root"
NL_DOWNLOAD_DIR="/opt/mac"
OPENLIST_PORT=5244
RSYNC_INTERVAL=5

# 脚本目录
HYS_DIR="/opt/hysteria"
SCRIPTS_DIR="/opt/scripts"
LOG_FILE="/var/log/nas-pullback.log"

# =============================================
# 确认信息
# =============================================

echo ""
echo "======================================"
echo "          配置确认"
echo "======================================"
echo "  Shanghai: ${SHANGHAI_IP}:${SHANGHAI_HY2_PORT}"
echo "  NL:       ${NL_IP}:${NL_HY2_PORT}"
echo "  外接盘:    ${LOCAL_DOWNLOAD_DIR}"
echo "  rsync:    每 ${RSYNC_INTERVAL} min 从 NL:${NL_DOWNLOAD_DIR} 回传"
echo "======================================"

read -rp "确认无误，开始部署？[Y/n] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]] && [[ -n "$CONFIRM" ]]; then
    echo "已取消部署。"
    exit 0
fi

echo ""
log_info "开始部署..."
