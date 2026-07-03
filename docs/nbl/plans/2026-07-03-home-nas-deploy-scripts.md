# 家庭NAS 一键部署脚本 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use nbl.subagent-driven-development (recommended) or nbl.executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 编写三个一键部署脚本，分别部署上海VPS、荷兰VPS和Mac Mini，实现家庭NAS全栈自动化部署。

**Architecture:** 三个独立脚本，分别对应三台机器。每个脚本自包含：安装依赖、生成配置、启动服务。无跨任务依赖，可完全并行开发。

**Tech Stack:** Bash (Linux VPS) / Zsh (Mac Mini), Hysteria 2, Caddy, Docker, OpenList

---

### Task 1: `setup-shanghai.sh` —— 上海 VPS

**Dependencies:** None
**Parallelizable:** Yes

**Files:**
- Create: `scripts/setup-shanghai.sh`

- [ ] **Step 1: 创建脚本文件骨架**

脚本接收变量（通过环境变量或脚本顶部配置）：
- `DOMAIN=openlist.dickgroup.xyz`
- `HY2_PASSWORD`（HY2 认证密码）
- `HY2_PORT=8443`（HY2 监听端口）
- `TUNNEL_LOCAL_PORT=15244`（上海本地转发端口）
- `TUNNEL_REMOTE_PORT=5244`（隧道对端 Mac OpenList 端口）

- [ ] **Step 2: 安装系统依赖**

安装 Caddy 和 Hysteria 2：
- Caddy: 使用官方脚本 `curl -fsSL https://getcaddy.com | bash` 或 apt 安装
- Hysteria 2: 从 GitHub releases 下载二进制，chmod +x，放到 `/usr/local/bin/hysteria`

```bash
# Caddy 安装
apt-get update && apt-get install -y curl wget
curl -fsSL https://getcaddy.com | bash -s personal

# Hysteria 2 安装
HY2_VER=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep tag_name | cut -d '"' -f 4)
wget -O /usr/local/bin/hysteria "https://github.com/apernet/hysteria/releases/download/${HY2_VER}/hysteria-linux-amd64"
chmod +x /usr/local/bin/hysteria
```

- [ ] **Step 3: 生成 HY2 自签名证书**

```bash
mkdir -p /etc/hysteria
openssl genrsa -out /etc/hysteria/server.key 2048
openssl req -new -x509 -key /etc/hysteria/server.key -out /etc/hysteria/server.crt -days 3650 \
  -subj "/CN=${DOMAIN}"
```

- [ ] **Step 4: 生成 HY2 Server 配置文件**

写入 `/etc/hysteria/server.yaml`：

```yaml
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
```

- [ ] **Step 5: 创建 HY2 systemd 服务**

写入 `/etc/systemd/system/hysteria-server.service`：

```ini
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
```

`systemctl daemon-reload && systemctl enable --now hysteria-server`

- [ ] **Step 6: 生成 Caddy 配置**

写入 `/etc/caddy/Caddyfile`：

```
${DOMAIN} {
    reverse_proxy 127.0.0.1:${TUNNEL_LOCAL_PORT}
}
```

`systemctl restart caddy`

- [ ] **Step 7: 输出部署结果**

打印验证命令：
```bash
echo "=== 上海 VPS 部署完成 ==="
echo "Caddy 状态: systemctl status caddy"
echo "HY2 状态: systemctl status hysteria-server"
echo "验证: curl -I https://${DOMAIN}"
```

- [ ] **Step 8: Commit**

```bash
git add scripts/setup-shanghai.sh
git commit -m "feat: 上海VPS一键部署脚本 (Caddy + HY2 Server)"
```

---

### Task 2: `setup-netherlands.sh` —— 荷兰 VPS

**Dependencies:** None
**Parallelizable:** Yes

**Files:**
- Create: `scripts/setup-netherlands.sh`

- [ ] **Step 1: 创建脚本文件骨架**

脚本接收变量：
- `DOMAIN_OPENLIST=nllist.dickgroup.xyz`
- `DOMAIN_QB=qb.dickgroup.xyz`
- `DOMAIN_ARIA=aria.dickgroup.xyz`
- `HY2_PASSWORD`
- `HY2_PORT=8443`
- `OPENLIST_PORT=5244`
- `QB_PORT=8080`
- `ARIA_PORT=6800`
- `ARIANG_PORT=6880`（AriaNg WebUI 端口）
- `DOWNLOAD_DIR=/opt/mac`

- [ ] **Step 2: 安装系统依赖**

```bash
apt-get update && apt-get install -y curl wget
# Docker
curl -fsSL https://get.docker.com | bash
# Hysteria 2
HY2_VER=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep tag_name | cut -d '"' -f 4)
wget -O /usr/local/bin/hysteria "https://github.com/apernet/hysteria/releases/download/${HY2_VER}/hysteria-linux-amd64"
chmod +x /usr/local/bin/hysteria
```

- [ ] **Step 3: 安装 Caddy**

```bash
curl -fsSL https://getcaddy.com | bash -s personal
```

- [ ] **Step 4: 创建下载目录**

```bash
mkdir -p ${DOWNLOAD_DIR}
chmod 777 ${DOWNLOAD_DIR}
```

- [ ] **Step 5: 安装 OpenList（一键脚本）**

```bash
curl -fsSL https://raw.githubusercontent.com/OpenListTeam/OpenList/main/install.sh | bash
```

OpenList 自动监听 5244，安装后自动运行。服务管理：
```bash
systemctl enable --now openlist
```

- [ ] **Step 6: 部署 qBittorrent（Docker）**

```bash
docker run -d --name qbittorrent \
  --network host \
  -e PUID=1000 -e PGID=1000 \
  -e WEBUI_PORT=${QB_PORT} \
  -v ${DOWNLOAD_DIR}:/downloads \
  -v /opt/qbittorrent-config:/config \
  --restart unless-stopped \
  linuxserver/qbittorrent
```

- [ ] **Step 7: 部署 Aria2（Docker）**

```bash
docker run -d --name aria2 \
  --network host \
  -e RPC_SECRET=${ARIA2_RPC_SECRET:-openlist2024} \
  -e RPC_PORT=${ARIA_PORT} \
  -v ${DOWNLOAD_DIR}:/downloads \
  -v /opt/aria2-config:/config \
  --restart unless-stopped \
  p3terx/aria2-pro
```

- [ ] **Step 8: 部署 AriaNg（Docker）**

```bash
docker run -d --name ariang \
  --network host \
  -e ARIANG_PORT=${ARIANG_PORT} \
  --restart unless-stopped \
  p3terx/ariang
```

注意：AriaNg 通过 `--network host` 绑定宿主机端口，访问时用自己的 RPC 连接 `localhost:${ARIA_PORT}`。

- [ ] **Step 9: 生成 HY2 Server 配置**

写入 `/etc/hysteria/server.yaml`：

```yaml
listen: :${HY2_PORT}
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: ${HY2_PASSWORD}
```

注意：荷兰 HY2 Server **不配 tcpForwarding**，端口转发在 Mac Client 侧配置。
生成自签名证书同上。

- [ ] **Step 10: 创建 HY2 systemd 服务**

同上海脚本的 systemd 配置，`systemctl enable --now hysteria-server`。

- [ ] **Step 11: 生成 Caddy 配置**

写入 `/etc/caddy/Caddyfile`：

```
${DOMAIN_OPENLIST} {
    reverse_proxy 127.0.0.1:${OPENLIST_PORT}
}
${DOMAIN_QB} {
    reverse_proxy 127.0.0.1:${QB_PORT}
}
${DOMAIN_ARIA} {
    reverse_proxy 127.0.0.1:${ARIANG_PORT}
}
```

`systemctl restart caddy`

- [ ] **Step 12: 输出部署结果**

打印验证命令和关键信息：
- 各服务状态
- qB 默认用户名密码（admin/adminadmin，登录后建议修改）
- Aria2 RPC 密钥
- Docker 容器状态

- [ ] **Step 13: Commit**

---

### Task 3: `setup-macmini.sh` —— Mac Mini M4

**Dependencies:** None
**Parallelizable:** Yes

**Files:**
- Create: `scripts/setup-macmini.sh`

- [ ] **Step 1: 创建脚本文件骨架**

脚本接收变量：
- `SHANGHAI_IP`、`SHANGHAI_HY2_PORT=8443`、`SHANGHAI_HY2_PASSWORD`
- `NL_IP`、`NL_HY2_PORT=8443`、`NL_HY2_PASSWORD`
- `LOCAL_DOWNLOAD_DIR`（外接盘路径，如 `/Volumes/NAS/nas-downloads`）
- `NL_USER=root`
- `OPENLIST_PORT=5244`
- `RSYNC_INTERVAL=5`（分钟）

- [ ] **Step 2: 安装 Homebrew 和依赖**

```bash
# 如果未安装 Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# 安装 hysteria 和 rsync（macOS 自带 rsync）
brew install hysteria
```

- [ ] **Step 3: 安装 OpenList（一键脚本）**

OpenList 官方脚本支持 macOS：
```bash
curl -fsSL https://raw.githubusercontent.com/OpenListTeam/OpenList/main/install.sh | bash
```

macOS 上若不用 systemd，则创建 LaunchAgent。

- [ ] **Step 4: 生成 HY2 Client 配置（至上海）**

写入 `/opt/hysteria/shanghai.yaml`：

```yaml
server: ${SHANGHAI_IP}:${SHANGHAI_HY2_PORT}
auth: ${SHANGHAI_HY2_PASSWORD}
tls:
  sni: ${SHANGHAI_IP}
  insecure: true
```

注意：此 Client **不配** tcpForwarding。上海 Server 侧已配 `tcpForwarding: listen 15244 → remote 5244`，Mac 只需要保持连接在线。

- [ ] **Step 5: 生成 HY2 Client 配置（至荷兰）**

写入 `/opt/hysteria/netherlands.yaml`：

```yaml
server: ${NL_IP}:${NL_HY2_PORT}
auth: ${NL_HY2_PASSWORD}
tls:
  sni: ${NL_IP}
  insecure: true
tcpForwarding:
  - listen: 127.0.0.1:9092
    remote: 127.0.0.1:22
```

端口 9092 → 荷兰 SSH:22，供 rsync 使用。

- [ ] **Step 6: 创建 HY2 LaunchAgents**

两个 plist 文件，确保开机自启和崩溃重启：

`~/Library/LaunchAgents/com.nas.hysteria-shanghai.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nas.hysteria-shanghai</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/hysteria</string>
        <string>-c</string>
        <string>/opt/hysteria/shanghai.yaml</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

荷兰同理，替换名称和配置路径。`launchctl load` 加载。

- [ ] **Step 7: 生成 rsync 回传脚本**

写入 `/opt/scripts/pullback.sh`：

```bash
#!/bin/bash
REMOTE_HOST="127.0.0.1"
REMOTE_PORT="9092"
REMOTE_USER="${NL_USER}"
REMOTE_DIR="${NL_DOWNLOAD_DIR:-/opt/mac}/"
LOCAL_DIR="${LOCAL_DOWNLOAD_DIR}"

mkdir -p "$LOCAL_DIR"

rsync -av --remove-source-files \
  --exclude='*.!qB' \
  --exclude='*.aria2' \
  -e "ssh -p $REMOTE_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
  "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR" "$LOCAL_DIR"

ssh -p $REMOTE_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "$REMOTE_USER@$REMOTE_HOST" "find $REMOTE_DIR -type d -empty -delete 2>/dev/null"
```

`chmod +x /opt/scripts/pullback.sh`

- [ ] **Step 8: 配置 crontab**

```bash
(crontab -l 2>/dev/null; echo "*/${RSYNC_INTERVAL} * * * * /opt/scripts/pullback.sh >> /var/log/nas-pullback.log 2>&1") | crontab -
```

- [ ] **Step 9: 输出部署结果**

打印验证命令：
- 两个 HY2 Client 是否运行
- OpenList 是否运行
- crontab 是否配置成功
- `rsync` 手动测试命令

- [ ] **Step 10: Commit**

---

### Task 4: README.md

**Dependencies:** Task 1, Task 2, Task 3
**Parallelizable:** No（需要三个脚本就位后再写）

**Files:**
- Create: `README.md`

- [ ] **Step 1: 编写 README**

包含：
- 架构图（ASCII art 拓扑图）
- 前置条件（Cloudflare DNS 配置、各服务器 IP、域名）
- 三条部署命令（curl 远程执行）
- 部署后验证步骤
- 常见问题排查

- [ ] **Step 2: Commit**

---

### Task 5: .gitignore

**Dependencies:** None
**Parallelizable:** Yes

**Files:**
- Create: `.gitignore`

```
# macOS
.DS_Store
.AppleDouble
.LSOverride

# IDE
.vscode/
.idea/

# Logs
*.log

# Local config overrides (passwords, IPs)
*.local.env
```

- [ ] **Step 1: Commit**

---

**Execution Mode:** parallel

---

### Task 6: `teardown-shanghai.sh` —— 上海 VPS 卸载

**Dependencies:** Task 1
**Parallelizable:** No（依赖Task 1完成）

**Files:**
- Create: `scripts/teardown-shanghai.sh`

- [ ] **Step 1: 编写卸载脚本**

```bash
#!/bin/bash
echo "=== 上海 VPS 卸载脚本 ==="

# 停止并禁用 HY2
if systemctl is-active --quiet hysteria-server; then
    echo "停止 HY2 Server..."
    systemctl stop hysteria-server
    systemctl disable hysteria-server
fi

# 删除 HY2 文件
rm -f /etc/systemd/system/hysteria-server.service
systemctl daemon-reload
rm -rf /etc/hysteria
rm -f /usr/local/bin/hysteria

# 还原 Caddy 配置（仅删除项目配置，不动 Caddy 软件）
if [ -f /etc/caddy/Caddyfile ]; then
    echo "清除 Caddy 配置..."
    > /etc/caddy/Caddyfile
    systemctl restart caddy
fi

# 删除项目目录
rm -rf /opt/hysteria

echo "=== 卸载完成 ==="
```

- [ ] **Step 2: Commit**

### Task 7: `teardown-netherlands.sh` —— 荷兰 VPS 卸载

**Dependencies:** Task 2
**Parallelizable:** No（依赖Task 2完成）

**Files:**
- Create: `scripts/teardown-netherlands.sh`

- [ ] **Step 1: 编写卸载脚本**

```bash
#!/bin/bash
echo "=== 荷兰 VPS 卸载脚本 ==="

# 停止并删除 Docker 容器
for container in qbittorrent aria2 ariang; do
    if docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        echo "删除容器: $container"
        docker rm -f "$container"
    fi
done

# 删除 Docker 相关目录（可选，保留数据时注释掉）
rm -rf /opt/qbittorrent-config /opt/aria2-config

# 删除下载目录
rm -rf /opt/mac

# 停止并删除 HY2
if systemctl is-active --quiet hysteria-server; then
    systemctl stop hysteria-server
    systemctl disable hysteria-server
fi
rm -f /etc/systemd/system/hysteria-server.service
systemctl daemon-reload
rm -rf /etc/hysteria
rm -f /usr/local/bin/hysteria

# 停止并删除 OpenList
if systemctl is-active --quiet openlist; then
    systemctl stop openlist
    systemctl disable openlist
fi
rm -f /etc/systemd/system/openlist.service
systemctl daemon-reload
# OpenList 安装路径根据实际情况调整
rm -rf /opt/openlist

# 还原 Caddy
if [ -f /etc/caddy/Caddyfile ]; then
    > /etc/caddy/Caddyfile
    systemctl restart caddy
fi

echo "=== 卸载完成 ==="
```

- [ ] **Step 2: Commit**

### Task 8: `teardown-macmini.sh` —— Mac Mini 卸载

**Dependencies:** Task 3
**Parallelizable:** No（依赖Task 3完成）

**Files:**
- Create: `scripts/teardown-macmini.sh`

- [ ] **Step 1: 编写卸载脚本**

```bash
#!/bin/bash
echo "=== Mac Mini 卸载脚本 ==="

# 停止并删除 LaunchAgents
for agent in com.nas.hysteria-shanghai com.nas.hysteria-netherlands; do
    PLIST="$HOME/Library/LaunchAgents/${agent}.plist"
    if [ -f "$PLIST" ]; then
        echo "卸载 LaunchAgent: $agent"
        launchctl bootout gui/$(id -u) "$PLIST" 2>/dev/null
        rm -f "$PLIST"
    fi
done

# 删除 crontab 中的回传任务
crontab -l 2>/dev/null | grep -v "pullback.sh" | crontab -

# 卸载 hysteria（保留 brew 环境）
if brew list --formula | grep -q "^hysteria$"; then
    echo "卸载 hysteria..."
    brew uninstall hysteria
fi

# 删除项目目录
rm -rf /opt/hysteria
rm -rf /opt/scripts
rm -f /var/log/nas-pullback.log

# 删除 OpenList（根据实际安装路径）
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.openlist.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.openlist.plist
rm -rf /opt/openlist

echo "=== 卸载完成 ==="
```

- [ ] **Step 2: Commit**

---

**Execution Mode:** parallel
