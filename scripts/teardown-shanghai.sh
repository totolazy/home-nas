#!/bin/bash
# ============================================================
# teardown-shanghai.sh —— 上海 VPS 卸载脚本
#
# 拆除 Caddy 反代配置 + Hysteria 2 Server
# 清理项目文件，不破坏系统原有环境
#
# 用法: sudo bash teardown-shanghai.sh
# ============================================================

set -euo pipefail

# ----------------------------------------------------------
# Step 0: 前置检查
# ----------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 权限运行: sudo bash $0"
    exit 1
fi

# ----------------------------------------------------------
# Step 1: 交互式确认
# ----------------------------------------------------------
echo "=============================================="
echo "  上海 VPS 卸载脚本"
echo "=============================================="
echo ""
echo "即将执行以下操作:"
echo ""
echo "  [1] 停止并禁用 hysteria-server systemd 服务"
echo "  [2] 删除 /etc/systemd/system/hysteria-server.service"
echo "  [3] 删除 /etc/hysteria/（HY2 配置、证书）"
echo "  [4] 删除 /usr/local/bin/hysteria（HY2 二进制）"
echo "  [5] 清空 /etc/caddy/Caddyfile 并重启 Caddy"
echo ""
echo "注意: Caddy 软件本身不会删除，仅清空项目配置。"
echo "      系统其他服务不受影响。"
echo ""
read -r -p "确认卸载？输入 y 继续: " CONFIRM
if [ "${CONFIRM,,}" != "y" ]; then
    echo "已取消。"
    exit 0
fi
echo ""

# ----------------------------------------------------------
# Step 2: 停止并移除 Hysteria 2 Server
# ----------------------------------------------------------
echo "=== [1/3] 停止并移除 Hysteria 2 Server ==="

if systemctl is-active --quiet hysteria-server 2>/dev/null; then
    echo "停止 hysteria-server 服务..."
    systemctl stop hysteria-server
    echo "  hysteria-server 已停止。"
else
    echo "hysteria-server 服务未在运行，跳过 stop。"
fi

if systemctl is-enabled --quiet hysteria-server 2>/dev/null; then
    echo "禁用 hysteria-server 开机自启..."
    systemctl disable hysteria-server
    echo "  hysteria-server 已禁用。"
else
    echo "hysteria-server 未启用开机自启，跳过 disable。"
fi

# 删除 systemd 服务文件
if [ -f /etc/systemd/system/hysteria-server.service ]; then
    rm -f /etc/systemd/system/hysteria-server.service
    systemctl daemon-reload
    echo "  已删除 /etc/systemd/system/hysteria-server.service"
fi

# 删除 HY2 配置文件与证书
if [ -d /etc/hysteria ]; then
    rm -rf /etc/hysteria
    echo "  已删除 /etc/hysteria/"
fi

# 删除 HY2 二进制
if [ -f /usr/local/bin/hysteria ]; then
    rm -f /usr/local/bin/hysteria
    echo "  已删除 /usr/local/bin/hysteria"
fi

echo ""

# ----------------------------------------------------------
# Step 3: 清空 Caddy 配置
# ----------------------------------------------------------
echo "=== [2/3] 清空 Caddy 配置 ==="

if [ -f /etc/caddy/Caddyfile ]; then
    echo "" > /etc/caddy/Caddyfile
    echo "  已清空 /etc/caddy/Caddyfile"
else
    echo "  /etc/caddy/Caddyfile 不存在，跳过。"
fi

if command -v caddy &>/dev/null; then
    echo "重启 Caddy..."
    systemctl restart caddy
    echo "  Caddy 已重启。"
else
    echo "Caddy 未安装，跳过 restart。"
fi

echo ""

# ----------------------------------------------------------
# Step 4: 完成
# ----------------------------------------------------------
echo "=============================================="
echo "  上海 VPS 卸载完成"
echo "=============================================="
echo ""
echo "已清理:"
echo "  - hysteria-server systemd 服务"
echo "  - /etc/systemd/system/hysteria-server.service"
echo "  - /etc/hysteria/"
echo "  - /usr/local/bin/hysteria"
echo "  - /etc/caddy/Caddyfile 配置"
echo ""
echo "保留未动:"
echo "  - Caddy 软件本身"
echo "  - 系统其他服务与配置"
echo ""
