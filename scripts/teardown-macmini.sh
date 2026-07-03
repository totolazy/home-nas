#!/bin/bash
set -euo pipefail

# =============================================
# Mac Mini NAS 一键卸载脚本
# 卸载 HY2 Client x2 + OpenList + rsync 回传
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
# Step 1: 交互式确认
# =============================================

echo ""
echo "======================================"
echo "  Mac Mini NAS 一键卸载脚本"
echo "======================================"
echo ""

echo -e "${YELLOW}⚠️  此脚本将执行以下操作:${NC}"
echo ""
echo "  1. 停止并删除 HY2 LaunchAgent (上海 + 荷兰)"
echo "  2. 清除 crontab 中的 rsync 回传任务"
echo "  3. brew uninstall hysteria"
echo "  4. 删除 /opt/hysteria /opt/scripts 目录"
echo "  5. 删除日志文件 (nas-pullback.log + HY2 + OpenList)"
echo "  6. 停止并删除 OpenList LaunchAgent 和相关目录"
echo ""
echo -e "${YELLOW}以下内容不会被删除:${NC}"
echo "  - Homebrew 及已安装的其他软件"
echo "  - 系统工具 (rsync 等)"
echo "  - SSH 密钥"
echo "  - 外接盘下载目录"
echo ""

read -rp "确认卸载？输入 YES 继续: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
    echo "已取消卸载。"
    exit 0
fi

echo ""
log_info "开始卸载..."

# =============================================
# Step 2: 停止并删除 HY2 LaunchAgents
# =============================================

log_step "Step 1/6: 停止并删除 HY2 LaunchAgents"

GUI_UID="gui/$(id -u)"
LA_DIR="$HOME/Library/LaunchAgents"

for label in com.nas.hysteria-shanghai com.nas.hysteria-netherlands; do
    PLIST="$LA_DIR/${label}.plist"
    if [[ -f "$PLIST" ]]; then
        log_info "卸载 LaunchAgent: $label"
        launchctl bootout "$GUI_UID" "$PLIST" 2>/dev/null || true
        rm -f "$PLIST"
    else
        log_info "$label 未找到，跳过"
    fi
done

# =============================================
# Step 3: 清除 crontab 回传任务
# =============================================

log_step "Step 2/6: 清除 crontab 中的 rsync 回传任务"

CURRENT_CRON=$(crontab -l 2>/dev/null || true)
if echo "$CURRENT_CRON" | grep -q "pullback.sh"; then
    echo "$CURRENT_CRON" | grep -v "pullback.sh" | crontab -
    log_info "已清除 crontab 中的 pullback.sh 任务"
else
    log_info "crontab 中未找到 pullback.sh 任务，跳过"
fi

# 如果 crontab 已空，删除整个 crontab
if crontab -l 2>/dev/null | grep -qv '^#' || [[ -z "$(crontab -l 2>/dev/null | grep -v '^#')" ]]; then
    :
else
    crontab -r 2>/dev/null && log_info "crontab 已清空，已删除" || true
fi

# =============================================
# Step 4: brew uninstall hysteria
# =============================================

log_step "Step 3/6: 卸载 hysteria (Homebrew)"

if command -v brew &>/dev/null; then
    if brew list --formula 2>/dev/null | grep -q "^hysteria$"; then
        log_info "卸载 hysteria..."
        brew uninstall hysteria
    else
        log_info "hysteria 未通过 Homebrew 安装，跳过"
    fi
else
    log_warn "未检测到 Homebrew，跳过 hysteria 卸载"
fi

# =============================================
# Step 5: 删除项目目录
# =============================================

log_step "Step 4/6: 删除项目目录"

for dir in /opt/hysteria /opt/scripts; do
    if [[ -d "$dir" ]]; then
        log_info "删除目录: $dir"
        rm -rf "$dir"
    else
        log_info "目录 $dir 不存在，跳过"
    fi
done

# =============================================
# Step 6: 删除日志文件
# =============================================

log_step "Step 5/6: 删除日志文件"

# /var/log 路径 (用户明确要求)
if [[ -f "/var/log/nas-pullback.log" ]]; then
    log_info "删除: /var/log/nas-pullback.log"
    sudo rm -f /var/log/nas-pullback.log 2>/dev/null || rm -f /var/log/nas-pullback.log 2>/dev/null || true
fi

# ~/Library/Logs 路径 (setup 脚本实际使用)
for logfile in \
    "$HOME/Library/Logs/nas-pullback.log" \
    "$HOME/Library/Logs/hysteria-shanghai.log" \
    "$HOME/Library/Logs/hysteria-netherlands.log" \
    "$HOME/Library/Logs/openlist.log"; do
    if [[ -f "$logfile" ]]; then
        log_info "删除: $logfile"
        rm -f "$logfile"
    fi
done

# =============================================
# Step 7: 停止并删除 OpenList
# =============================================

log_step "Step 6/6: 停止并删除 OpenList"

OPENLIST_PLIST="$HOME/Library/LaunchAgents/com.nas.openlist.plist"
if [[ -f "$OPENLIST_PLIST" ]]; then
    log_info "卸载 OpenList LaunchAgent..."
    launchctl bootout "$GUI_UID" "$OPENLIST_PLIST" 2>/dev/null || true
    rm -f "$OPENLIST_PLIST"
else
    log_info "OpenList LaunchAgent 未找到，跳过"
fi

# 删除 OpenList 安装目录
if [[ -d "/opt/openlist" ]]; then
    log_info "删除目录: /opt/openlist"
    rm -rf /opt/openlist
fi

# =============================================
# 输出卸载结果
# =============================================

echo ""
echo "======================================"
echo "       Mac Mini 卸载完成"
echo "======================================"
echo ""
echo "  已移除:"
echo "    - HY2 LaunchAgents (上海 + 荷兰)"
echo "    - crontab rsync 回传任务"
echo "    - hysteria (brew)"
echo "    - /opt/hysteria /opt/scripts"
echo "    - 日志文件"
echo "    - OpenList LaunchAgent + /opt/openlist"
echo ""
echo "  已保留:"
echo "    - Homebrew"
echo "    - 系统工具 (rsync 等)"
echo "    - SSH 密钥"
echo "    - 下载目录"
echo ""
echo "======================================"
log_info "卸载完毕。"
