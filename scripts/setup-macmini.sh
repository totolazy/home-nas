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
# =============================================
# Step 2: 安装 Homebrew 和依赖
# =============================================

log_step "Step 2: 安装 Homebrew 和依赖"

# 检查 Homebrew
if command -v brew &>/dev/null; then
    BREW_PREFIX=$(brew --prefix)
    log_info "Homebrew 已安装 (${BREW_PREFIX})"
else
    log_warn "Homebrew 未安装，开始安装..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Apple Silicon 和 Intel 路径不同
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        BREW_PREFIX="/opt/homebrew"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
        BREW_PREFIX="/usr/local"
    fi
    log_info "Homebrew 安装完成 (${BREW_PREFIX})"
fi

# 安装 hysteria
if command -v hysteria &>/dev/null; then
    log_info "hysteria 已安装: $(hysteria version 2>&1 | head -1)"
else
    log_info "安装 hysteria..."
    brew install hysteria
    log_info "hysteria 安装完成: $(hysteria version 2>&1 | head -1)"
fi
# =============================================
# Step 3: 安装 OpenList
# =============================================

log_step "Step 3: 安装 OpenList"

if command -v openlist &>/dev/null; then
    log_info "OpenList 已安装"
else
    log_info "开始安装 OpenList..."
    curl -fsSL https://raw.githubusercontent.com/OpenListTeam/OpenList/main/install.sh | bash
fi

# 找到 openlist 二进制位置
OPENLIST_BIN=""
for candidate in /usr/local/bin/openlist /opt/openlist/openlist /opt/homebrew/bin/openlist; do
    if [[ -x "$candidate" ]]; then
        OPENLIST_BIN="$candidate"
        break
    fi
done

if [[ -z "$OPENLIST_BIN" ]]; then
    log_error "未找到 openlist 二进制，请确认 OpenList 安装成功后再运行本脚本。"
    exit 1
fi
log_info "OpenList 二进制: ${OPENLIST_BIN}"

# 创建 LaunchAgent（macOS 没有 systemd）
OPENLIST_PLIST="$HOME/Library/LaunchAgents/com.nas.openlist.plist"
mkdir -p "$HOME/Library/LaunchAgents"

if [[ -f "$OPENLIST_PLIST" ]]; then
    log_info "OpenList LaunchAgent 已存在，先停止..."
    launchctl bootout "gui/$(id -u)" "$OPENLIST_PLIST" 2>/dev/null || true
fi

cat > "$OPENLIST_PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nas.openlist</string>
    <key>ProgramArguments</key>
    <array>
        <string>${OPENLIST_BIN}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/openlist.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/openlist.log</string>
</dict>
</plist>
PLISTEOF

log_info "加载 OpenList LaunchAgent..."
launchctl bootstrap "gui/$(id -u)" "$OPENLIST_PLIST"
log_info "OpenList LaunchAgent 已加载并启动"
