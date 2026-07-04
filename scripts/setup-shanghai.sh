#!/bin/bash
# ============================================================
# setup-shanghai.sh —— 上海 VPS 一键部署脚本
#
# 部署 Caddy + Hysteria 2 Server
# Caddy 反代域名到 HY2 隧道端口
# HY2 tcpForwarding: 上海 15244 → Mac OpenList 5244
#
# 用法: sudo bash setup-shanghai.sh
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
# Step 1: 配置变量
# ----------------------------------------------------------
echo "=============================================="
echo "  上海 VPS 一键部署脚本"
echo "  Caddy + Hysteria 2 Server"
echo "=============================================="
echo ""

# 固定配置
HY2_PORT="${HY2_PORT:-8443}"
TUNNEL_LOCAL_PORT="${TUNNEL_LOCAL_PORT:-15244}"
TUNNEL_REMOTE_PORT="${TUNNEL_REMOTE_PORT:-5244}"
DEFAULT_DOMAIN="openlist.dickgroup.xyz"
DEFAULT_HY2_PASSWORD="859456"

# 交互式输入：域名
read -r -p "域名 (默认: ${DEFAULT_DOMAIN}): " DOMAIN
DOMAIN="${DOMAIN:-${DEFAULT_DOMAIN}}"

# 交互式输入：HY2 密码
read -r -s -p "HY2 认证密码 (默认: ${DEFAULT_HY2_PASSWORD}): " HY2_PASSWORD_INPUT
echo ""
HY2_PASSWORD="${HY2_PASSWORD_INPUT:-${DEFAULT_HY2_PASSWORD}}"

echo ""
echo "--- 配置确认 ---"
echo "  域名:        ${DOMAIN}"
echo "  HY2 端口:    ${HY2_PORT}"
echo "  隧道:        127.0.0.1:${TUNNEL_LOCAL_PORT} → 127.0.0.1:${TUNNEL_REMOTE_PORT}"
echo ""
read -r -p "确认开始部署? (y/n): " CONFIRM
if [ "${CONFIRM,,}" != "y" ]; then
    echo "已取消。"
    exit 0
fi
echo ""

# ----------------------------------------------------------
# Step 2: 安装系统依赖
# ----------------------------------------------------------
echo "=== [1/6] 安装系统依赖 ==="

apt-get update -qq
apt-get install -y -qq curl wget openssl apt-transport-https

# Caddy (apt repo, 避免 getcaddy.com SSL 问题)
if ! command -v caddy &>/dev/null; then
    echo "安装 Caddy ..."
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' 2>/dev/null | \
        gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null || true
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' 2>/dev/null | \
        tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null || true
    apt-get update -qq 2>/dev/null || true
    apt-get install -y caddy || {
        echo "Caddy apt 安装失败，尝试直接下载..."
        CADDY_VER=$(curl -s https://api.github.com/repos/caddyserver/caddy/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
        wget -q -O /usr/bin/caddy "https://github.com/caddyserver/caddy/releases/download/${CADDY_VER}/caddy_${CADDY_VER#v}_linux_amd64.tar.gz" 2>/dev/null || true
        curl -fsSL https://getcaddy.com | bash -s personal 2>/dev/null || {
            echo "所有 Caddy 安装方式均失败，请手动安装。"
            exit 1
        }
    }
else
    echo "Caddy 已安装，跳过。"
fi

# Hysteria 2
if ! command -v hysteria &>/dev/null; then
    echo "安装 Hysteria 2 ..."
    HY2_VER=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
    wget -q -O /usr/local/bin/hysteria "https://github.com/apernet/hysteria/releases/download/${HY2_VER}/hysteria-linux-amd64"
    chmod +x /usr/local/bin/hysteria
else
    echo "Hysteria 2 已安装，跳过。"
fi

echo ""

# ----------------------------------------------------------
# Step 3: 生成 HY2 自签名证书
# ----------------------------------------------------------
echo "=== [2/6] 生成 HY2 自签名证书 ==="

mkdir -p /etc/hysteria
openssl genrsa -out /etc/hysteria/server.key 2048
openssl req -new -x509 -key /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 \
    -subj "/CN=${DOMAIN}"

echo "证书已生成: /etc/hysteria/server.crt"
echo ""

# ----------------------------------------------------------
# Step 4: 生成 HY2 Server 配置文件
# ----------------------------------------------------------
echo "=== [3/6] 生成 HY2 Server 配置 ==="

cat > /etc/hysteria/server.yaml << EOF
listen: :${HY2_PORT}

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: ${HY2_PASSWORD}

tcpForwarding:
  - listen: 127.0.0.1:${TUNNEL_LOCAL_PORT}
    remote: 127.0.0.1:${TUNNEL_REMOTE_PORT}
EOF

echo "配置已写入: /etc/hysteria/server.yaml"
echo ""

# ----------------------------------------------------------
# Step 5: 创建 HY2 systemd 服务
# ----------------------------------------------------------
echo "=== [4/6] 创建 HY2 systemd 服务 ==="

cat > /etc/systemd/system/hysteria-server.service << EOF
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

echo "HY2 systemd 服务已创建并启动。"
echo ""

# ----------------------------------------------------------
# Step 6: 生成 Caddy 配置
# ----------------------------------------------------------
echo "=== [5/6] 生成 Caddy 配置 ==="

mkdir -p /etc/caddy

cat > /etc/caddy/Caddyfile << EOF
${DOMAIN} {
    reverse_proxy 127.0.0.1:${TUNNEL_LOCAL_PORT}
}
EOF

systemctl restart caddy

echo "Caddy 配置已写入: /etc/caddy/Caddyfile"
echo ""

# ----------------------------------------------------------
# Step 7: 输出部署结果
# ----------------------------------------------------------
sleep 2

echo "=============================================="
echo "  上海 VPS 部署完成！"
echo "=============================================="
echo ""
echo "验证命令:"
echo "  Caddy 状态:   systemctl status caddy"
echo "  HY2 状态:     systemctl status hysteria-server"
echo "  验证 HTTPS:   curl -sI https://${DOMAIN}"
echo "  查看日志:     journalctl -u hysteria-server -f"
echo ""

# 快速健康检查
echo "--- 服务健康检查 ---"

if systemctl is-active --quiet caddy; then
    echo "  Caddy:            运行中 ✓"
else
    echo "  Caddy:            未运行 ✗"
fi

if systemctl is-active --quiet hysteria-server; then
    echo "  Hysteria Server:  运行中 ✓"
else
    echo "  Hysteria Server:  未运行 ✗"
fi

systemctl is-enabled caddy &>/dev/null && echo "  Caddy 开机自启:    ✓" || echo "  Caddy 开机自启:    ✗"
systemctl is-enabled hysteria-server &>/dev/null && echo "  HY2 开机自启:      ✓" || echo "  HY2 开机自启:      ✗"

echo ""
echo "部署完成。HY2 监听端口: ${HY2_PORT}，自签名证书，无 masquerade。"