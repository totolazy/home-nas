#!/bin/bash
set -euo pipefail

# =============================================
# Mac Mini NAS 一键部署脚�?# 部署 HY2 Client ×2 + OpenList + rsync 回传
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
# Step 1: 交互式输入配置参�?# =============================================

echo ""
echo "======================================"
echo "  Mac Mini NAS 一键部署脚�?
echo "======================================"
echo ""

echo ">>> 请输入上�?HY2 Server 连接信息 <<<"
read -rp "  IP 地址     : " SHANGHAI_IP
read -rp "  HY2 端口    [8443]: " SHANGHAI_HY2_PORT
SHANGHAI_HY2_PORT=${SHANGHAI_HY2_PORT:-8443}
read -rsp "  HY2 密码    : " SHANGHAI_HY2_PASSWORD
echo ""

echo ""
echo ">>> 请输入荷�?HY2 Server 连接信息 <<<"
read -rp "  IP 地址     : " NL_IP
read -rp "  HY2 端口    [8443]: " NL_HY2_PORT
NL_HY2_PORT=${NL_HY2_PORT:-8443}
read -rsp "  HY2 密码    : " NL_HY2_PASSWORD
echo ""

echo ""
read -rp ">>> 外接盘路�?(�?/Volumes/NAS/nas-downloads): " LOCAL_DOWNLOAD_DIR

# 固定参数
NL_USER="root"
NL_DOWNLOAD_DIR="/opt/mac"
OPENLIST_PORT=5244
RSYNC_INTERVAL=5

# 脚本目录
HYS_DIR="/opt/hysteria"
SCRIPTS_DIR="/opt/scripts"
LOG_FILE="$HOME/Library/Logs/nas-pullback.log"
#

mkdir -p "$HOME/Library/Logs"

# =============================================
# 确认信息
# =============================================

echo ""
echo "======================================"
echo "          配置确认"
echo "======================================"
echo "  Shanghai: ${SHANGHAI_IP}:${SHANGHAI_HY2_PORT}"
echo "  NL:       ${NL_IP}:${NL_HY2_PORT}"
echo "  外接�?    ${LOCAL_DOWNLOAD_DIR}"
echo "  rsync:    �?${RSYNC_INTERVAL} min �?NL:${NL_DOWNLOAD_DIR} 回传"
echo "======================================"

read -rp "确认无误，开始部署？[Y/n] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]] && [[ -n "$CONFIRM" ]]; then
    echo "已取消部署�?
    exit 0
fi

echo ""
log_info "开始部�?.."
# =============================================
# Step 2: 安装 Homebrew 和依�?# =============================================

log_step "Step 2: 安装 Homebrew 和依�?

# 检�?Homebrew
if command -v brew &>/dev/null; then
    BREW_PREFIX=$(brew --prefix)
    log_info "Homebrew 已安�?(${BREW_PREFIX})"
else
    log_warn "Homebrew 未安装，开始安�?.."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Apple Silicon �?Intel 路径不同
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
    log_info "hysteria 已安�? $(hysteria version 2>&1 | head -1)"
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
    log_info "OpenList 已安�?
else
    log_info "开始安�?OpenList..."
    curl -fsSL https://res.oplist.org.cn/script/v4.sh -o /tmp/install-openlist-v4.sh
    sudo bash /tmp/install-openlist-v4.sh
    rm -f /tmp/install-openlist-v4.sh
fi

# 找到 openlist 二进制位�?OPENLIST_BIN=""
for candidate in /usr/local/bin/openlist /opt/openlist/openlist /opt/homebrew/bin/openlist; do
    if [[ -x "$candidate" ]]; then
        OPENLIST_BIN="$candidate"
        break
    fi
done

if [[ -z "$OPENLIST_BIN" ]]; then
    log_error "未找�?openlist 二进制，请确�?OpenList 安装成功后再运行本脚本�?
    exit 1
fi
log_info "OpenList 二进�? ${OPENLIST_BIN}"

# 创建 LaunchAgent（macOS 没有 systemd�?OPENLIST_PLIST="$HOME/Library/LaunchAgents/com.nas.openlist.plist"
mkdir -p "$HOME/Library/LaunchAgents"

if [[ -f "$OPENLIST_PLIST" ]]; then
    log_info "OpenList LaunchAgent 已存在，先停�?.."
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
    <string>$HOME/Library/Logs/openlist.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/openlist.log</string>
</dict>
</plist>
PLISTEOF

log_info "加载 OpenList LaunchAgent..."
launchctl bootstrap "gui/$(id -u)" "$OPENLIST_PLIST"
log_info "OpenList LaunchAgent 已加载并启动"
# =============================================
# Step 4: 生成 HY2 Client 配置 - 至上�?# =============================================

log_step "Step 4: 生成 HY2 Client 配置 (上海)"

mkdir -p "$HYS_DIR"

cat > "$HYS_DIR/shanghai.yaml" << YAMLEOF
server: ${SHANGHAI_IP}:${SHANGHAI_HY2_PORT}

auth: ${SHANGHAI_HY2_PASSWORD}

tls:
  sni: ${SHANGHAI_IP}
  insecure: true
YAMLEOF

log_info "上海 HY2 Client 配置已写�?$HYS_DIR/shanghai.yaml"
# =============================================
# Step 5: 生成 HY2 Client 配置 - 至荷�?# =============================================

log_step "Step 5: 生成 HY2 Client 配置 (荷兰)"

cat > "$HYS_DIR/netherlands.yaml" << YAMLEOF
server: ${NL_IP}:${NL_HY2_PORT}

auth: ${NL_HY2_PASSWORD}

tls:
  sni: ${NL_IP}
  insecure: true

tcpForwarding:
  - listen: 127.0.0.1:9092
    remote: 127.0.0.1:22
YAMLEOF

log_info "荷兰 HY2 Client 配置已写�?$HYS_DIR/netherlands.yaml"
# =============================================
# Step 6: 创建 HY2 LaunchAgents
# =============================================

log_step "Step 6: 创建 HY2 LaunchAgents"

# 定位 hysteria 二进�?HYS_BIN=""
for candidate in /opt/homebrew/bin/hysteria /usr/local/bin/hysteria; do
    if [[ -x "$candidate" ]]; then
        HYS_BIN="$candidate"
        break
    fi
done
if [[ -z "$HYS_BIN" ]]; then
    HYS_BIN="$(command -v hysteria)"
fi
log_info "hysteria 二进�? ${HYS_BIN}"

LA_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$LA_DIR"

# --- 上海 HY2 Client LaunchAgent ---
SH_AGENT="$LA_DIR/com.nas.hysteria-shanghai.plist"
if [[ -f "$SH_AGENT" ]]; then
    launchctl bootout "gui/$(id -u)" "$SH_AGENT" 2>/dev/null || true
fi

cat > "$SH_AGENT" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nas.hysteria-shanghai</string>
    <key>ProgramArguments</key>
    <array>
        <string>${HYS_BIN}</string>
        <string>-c</string>
        <string>${HYS_DIR}/shanghai.yaml</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/hysteria-shanghai.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/hysteria-shanghai.log</string>
</dict>
</plist>
PLISTEOF

launchctl bootstrap "gui/$(id -u)" "$SH_AGENT"
log_info "上海 HY2 Client LaunchAgent 已加�?

# --- 荷兰 HY2 Client LaunchAgent ---
NL_AGENT="$LA_DIR/com.nas.hysteria-netherlands.plist"
if [[ -f "$NL_AGENT" ]]; then
    launchctl bootout "gui/$(id -u)" "$NL_AGENT" 2>/dev/null || true
fi

cat > "$NL_AGENT" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nas.hysteria-netherlands</string>
    <key>ProgramArguments</key>
    <array>
        <string>${HYS_BIN}</string>
        <string>-c</string>
        <string>${HYS_DIR}/netherlands.yaml</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/hysteria-netherlands.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/hysteria-netherlands.log</string>
</dict>
</plist>
PLISTEOF

launchctl bootstrap "gui/$(id -u)" "$NL_AGENT"
log_info "荷兰 HY2 Client LaunchAgent 已加�?
# =============================================
# Step 7: 生成 rsync 回传脚本
# =============================================

log_step "Step 7: 生成 rsync 回传脚本"

mkdir -p "$SCRIPTS_DIR"
mkdir -p "$LOCAL_DOWNLOAD_DIR"

cat > "$SCRIPTS_DIR/pullback.sh" << 'SCRIPTEOF'
#!/bin/bash
set -euo pipefail

REMOTE_HOST="127.0.0.1"
REMOTE_PORT="9092"
REMOTE_USER="PLACEHOLDER_NL_USER"
REMOTE_DIR="PLACEHOLDER_NL_DOWNLOAD_DIR/"
LOCAL_DIR="PLACEHOLDER_LOCAL_DOWNLOAD_DIR"

SSH_OPTS="-p ${REMOTE_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

mkdir -p "$LOCAL_DIR"

# rsync: 增量同步，排除未完成下载文件，传完自动删除源文件
rsync -av --remove-source-files \
    --exclude='*.!qB' \
    --exclude='*.aria2' \
    -e "ssh ${SSH_OPTS}" \
    "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}" "${LOCAL_DIR}/"

# 清理荷兰侧空目录
ssh ${SSH_OPTS} "${REMOTE_USER}@${REMOTE_HOST}" \
    "find ${REMOTE_DIR%/} -type d -empty -delete 2>/dev/null" || true
SCRIPTEOF

# 替换占位符为实际�?sed -i '' "s|PLACEHOLDER_NL_USER|${NL_USER}|g" "$SCRIPTS_DIR/pullback.sh"
sed -i '' "s|PLACEHOLDER_NL_DOWNLOAD_DIR|${NL_DOWNLOAD_DIR}|g" "$SCRIPTS_DIR/pullback.sh"
sed -i '' "s|PLACEHOLDER_LOCAL_DOWNLOAD_DIR|${LOCAL_DOWNLOAD_DIR}|g" "$SCRIPTS_DIR/pullback.sh"

chmod +x "$SCRIPTS_DIR/pullback.sh"
log_info "回传脚本已写�?$SCRIPTS_DIR/pullback.sh"
# =============================================
# Step 8: 配置 crontab
# =============================================

log_step "Step 8: 配置 crontab 定时回传"

CRON_ENTRY="*/${RSYNC_INTERVAL} * * * * ${SCRIPTS_DIR}/pullback.sh >> ${LOG_FILE} 2>&1"

# 避免重复添加
if crontab -l 2>/dev/null | grep -F "pullback.sh" &>/dev/null; then
    log_info "crontab 已存在回传任务，跳过"
else
    (crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -
    log_info "crontab 已添�? �?${RSYNC_INTERVAL} min 执行回传 (日志: ${LOG_FILE})"
fi
# =============================================
# Step 9: 输出部署结果
# =============================================

echo ""
echo "======================================"
echo "       Mac Mini 部署完成"
echo "======================================"
echo ""

# SSH Key 设置 (rsync 依赖)
SSH_KEY="$HOME/.ssh/id_ed25519"
if [[ ! -f "$SSH_KEY" ]]; then
    log_warn "未检测到 SSH 密钥，正在生�?.."
    mkdir -p "$HOME/.ssh"
    ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -q
fi
PUBKEY=$(cat "${SSH_KEY}.pub")

echo "--- 部署摘要 ---"
echo ""
echo "  HY2 Client (上海):"
echo "    配置: ${HYS_DIR}/shanghai.yaml"
echo "    Agent: ${SH_AGENT}"
echo "    日志: $HOME/Library/Logs/hysteria-shanghai.log"
echo ""
echo "  HY2 Client (荷兰):"
echo "    配置: ${HYS_DIR}/netherlands.yaml"
echo "    Agent: ${NL_AGENT}"
echo "    日志: $HOME/Library/Logs/hysteria-netherlands.log"
echo "    隧道: 127.0.0.1:9092 -> NL:22"
echo ""
echo "  OpenList:"
echo "    Agent: ${OPENLIST_PLIST}"
echo "    日志: $HOME/Library/Logs/openlist.log"
echo ""
echo "  Rsync 回传:"
echo "    脚本: ${SCRIPTS_DIR}/pullback.sh"
echo "    频率: �?${RSYNC_INTERVAL} 分钟"
echo "    日志: ${LOG_FILE}"
echo "    本地目录: ${LOCAL_DOWNLOAD_DIR}"
echo "    远程目录: ${NL_DOWNLOAD_DIR}"
echo ""
echo "--- SSH 公钥 (需添加到荷兰服务器) ---"
echo "${PUBKEY}"
echo ""
echo "请在荷兰服务器上执行:"
echo "  echo '${PUBKEY}' >> ~/.ssh/authorized_keys"
echo ""
echo "--- 验证命令 ---"
echo ""
echo "  # 检�?HY2 Client 状�?
echo "  launchctl list | grep hysteria"
echo ""
echo "  # 检�?OpenList 状�?
echo "  launchctl list | grep openlist"
echo ""
echo "  # 检�?crontab"
echo "  crontab -l | grep pullback"
echo ""
echo "  # 手动测试 rsync (需先确�?SSH 密钥已添�?"
echo "  ${SCRIPTS_DIR}/pullback.sh"
echo ""
echo "  # 通过隧道 SSH 到荷�?
echo "  ssh -p 9092 -o StrictHostKeyChecking=no root@127.0.0.1"
echo ""
echo "  # 测试上海隧道: curl http://127.0.0.1:${OPENLIST_PORT}"
echo "  curl -I http://127.0.0.1:${OPENLIST_PORT}"
echo ""
echo "======================================"
log_info "全部部署完成!"
