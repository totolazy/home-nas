# 家庭 NAS 技术设计文档

> 日期：2026-07-03
> 状态：已确认

## 1. 需求背景

构建一个家庭 NAS 系统，满足以下核心需求：

- **文件同步备份**：Mac Mini 外接盘作为主存储
- **媒体中心**：通过 OpenList WebDAV 协议在手机播放视频
- **私有云盘**：OpenList 统一挂载本地盘和网盘，支持公网访问
- **公网访问**：使用纯 Hysteria 2 协议实现内网穿透，支持 HTTPS 域名访问
- **离线下载**：荷兰服务器高速下载，自动回传至 Mac Mini 本地盘

## 2. 节点拓扑

```
                  Cloudflare DNS
              +------------------+
              | openlist -> 上海IP |
              | nllist   -> 荷兰IP |
              | qb       -> 荷兰IP |
              | aria     -> 荷兰IP |
              +------------------+
                     |
        +------------+------------+
        |                         |
+----------------+       +----------------+
|  上海 (VPS)     |       |  荷兰 (VPS)     |
|  Caddy HTTPS    |       |  Caddy HTTPS    |
|  HY2 Server     |       |  HY2 Server     |
|  tcpFwd->Mac    |       |  OpenList       |
+-------+--------+       |  qB (Docker)    |
        | HY2             |  Aria2 (Docker)  |
        | (Mac->上海)      |  AriaNg (Docker) |
+-------+--------+       +-------+--------+
|  Mac Mini M4    |               | HY2
|  HY2 Client->上海|               | (Mac->荷兰)
|  HY2 Client->荷兰|<--------------+
|  OpenList       |
|  外接盘          |
|  rsync 回传脚本   |
+----------------+
```

### 节点说明

| 节点 | 角色 | 公网 IP |
|------|------|---------|
| 上海 VPS | 公网入口 + HY2 Server（Mac 穿透） | 有 |
| 荷兰 VPS | 下载引擎 + HY2 Server（文件回传） | 有 |
| Mac Mini M4 | 存储核心 + HY2 Client x2 | 无（家庭内网） |

## 3. 域名与证书

域名：`dickgroup.xyz`，Cloudflare DNS 管理。

| 子域名 | DNS A 记录 | 反代目标 | HTTPS 处理 |
|--------|------------|----------|------------|
| `openlist.dickgroup.xyz` | 上海 IP | HY2 隧道 -> Mac OpenList:5244 | 上海 Caddy |
| `nllist.dickgroup.xyz` | 荷兰 IP | 荷兰本地 OpenList:5244 | 荷兰 Caddy |
| `qb.dickgroup.xyz` | 荷兰 IP | 荷兰 qB WebUI:8080 | 荷兰 Caddy |
| `aria.dickgroup.xyz` | 荷兰 IP | 荷兰 AriaNg WebUI | 荷兰 Caddy |

证书由各自服务器上的 Caddy 自动申请 Let''s Encrypt 证书并自动续期。

## 4. 各节点软件栈

### 4.1 上海 VPS

| 组件 | 部署方式 | 用途 |
|------|----------|------|
| Caddy | 裸机安装 | `openlist.dickgroup.xyz` HTTPS 反代 |
| HY2 Server | 裸机安装 | 提供 tcpForwarding，Mac Client 连接后转发流量到 Mac OpenList |

Caddy 反代链：
```
openlist.dickgroup.xyz -> Caddy -> 127.0.0.1:15244 -> HY2 隧道 -> Mac 127.0.0.1:5244
```

HY2 Server 配置要点：
- `tcpForwarding`: listen `127.0.0.1:15244` -> remote `127.0.0.1:5244`（隧道对端 Mac）
- TLS 自签名证书（Mac Client 配置 `insecure: true`）
- 无需 masquerade，纯 HY2 模式

### 4.2 荷兰 VPS

| 组件 | 部署方式 | 用途 |
|------|----------|------|
| Caddy | 裸机安装 | 三个子域名 HTTPS 反代 |
| OpenList | 一键脚本裸装 | 网盘挂载 + WebDAV，监听 5244 |
| qBittorrent | Docker，`--network host` | BT 下载，WebUI 8080 |
| 下载目录 | /opt/mac/ | qB/Aria2 下载完成存放目录，供 Mac 回传 |
| Aria2 | Docker，`--network host` | HTTP/磁力下载，RPC 6800 |
| AriaNg | Docker，`--network host` | Aria2 WebUI |
| HY2 Server | 裸机安装 | 供 Mac Client 连接，提供文件回传通道 |

**两条下载路径：**

| 路径 | 触发方式 | 下载到 | 最终去向 |
|------|----------|--------|----------|
| 网盘 | OpenList 内置调用 qB/Aria2 | qB/Aria2 默认下载路径 | OpenList 自动上传网盘 |
| Mac 本地盘 | 手动打开 qB/Aria2 WebUI，选择 `/opt/mac/` | `/opt/mac/` | Mac rsync 回传至外接盘 |

Caddy 反代：
- `nllist.dickgroup.xyz` -> `127.0.0.1:5244`
- `qb.dickgroup.xyz` -> `127.0.0.1:8080`
- `aria.dickgroup.xyz` -> AriaNg 端口

### 4.3 Mac Mini M4

| 组件 | 部署方式 | 用途 |
|------|----------|------|
| OpenList | 一键脚本裸装 | 挂载外接盘 + 网盘，WebDAV 服务，监听 5244 |
| HY2 Client（至上海） | 裸机安装 | 连接上海 HY2 Server，承载公网穿透流量 |
| HY2 Client（至荷兰） | 裸机安装 | 连接荷兰 HY2 Server，承载文件回传流量 |
| rsync 回传脚本 | cron 每 5 分钟 | 通过 HY2 隧道 SSH 拉取荷兰下载完成的文件 |

HY2 Client 至荷兰的配置（两条 tcpForwarding）：
```yaml
tcpForwarding:
  - listen: 127.0.0.1:9092
    remote: 127.0.0.1:22      # SSH，供 rsync 使用
  - listen: 127.0.0.1:9093
    remote: 127.0.0.1:8080    # HTTP Server（可选，供浏览下载目录）
```

## 5. HY2 隧道设计

### 隧道 1：Mac -> 上海（公网穿透）

上海 HY2 Server 配置要点：
- `tcpForwarding`: listen `127.0.0.1:15244` -> remote `127.0.0.1:5244`
- Mac Client 连接后，上海 15244 端口流量通过隧道转发至 Mac 5244

数据流：用户 -> Cloudflare DNS -> 上海 IP:443 -> Caddy -> 127.0.0.1:15244 -> HY2 UDP -> Mac 127.0.0.1:5244 -> OpenList

### 隧道 2：Mac -> 荷兰（文件回传）

Mac HY2 Client tcpForwarding：
- listen `127.0.0.1:9092` -> remote `127.0.0.1:22`（荷兰 SSH）

数据流：Mac rsync -> ssh -p 9092 user@127.0.0.1 -> HY2 UDP -> 荷兰 SSH:22 -> 文件传输

### 设计要点

- 两条隧道均由 Mac 从内网主动发起，无需路由器端口转发
- 纯 HY2 模式，无 masquerade，无 SOCKS5，无 TUN
- TLS 使用自签名证书，Mac Client 配置 `insecure: true`
- HY2 使用 password 认证

## 6. 回传方案

### 6.1 流程

1. 荷兰 qB/Aria2 下载文件到统一目录 `/download/`
2. Mac cron 每 5 分钟执行 rsync，通过 HY2 隧道 SSH 连接荷兰
3. rsync 增量同步：只传新文件，支持断点续传
4. `--remove-source-files`：传完自动删除荷兰源文件
5. 回传完成后清理荷兰空目录

### 6.2 脚本逻辑

```bash
#!/bin/bash
REMOTE_HOST="127.0.0.1"
REMOTE_PORT="9092"
REMOTE_USER="root"
REMOTE_DIR="/opt/mac/"
LOCAL_DIR="/Volumes/外接盘/nas-downloads/"

# rsync 拉文件（增量、断点续传、传完删源）
# --exclude 跳过未完成的下载文件（qB 的 .!qB、Aria2 的 .aria2）
rsync -av --remove-source-files \
  --exclude="*.!qB" \
  --exclude="*.aria2" \
  -e "ssh -p $REMOTE_PORT -o StrictHostKeyChecking=no" \
  "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR" "$LOCAL_DIR"

# 清理空目录
ssh -p $REMOTE_PORT -o StrictHostKeyChecking=no \
  "$REMOTE_USER@$REMOTE_HOST" "find $REMOTE_DIR -type d -empty -delete"
```

## 7. 关键数据流

### 7.1 公网访问 Mac 本地盘文件

速度取决于家庭宽带上行 + HY2 加速。

### 7.2 公网访问网盘文件（302 直连）

OpenList 返回 302 重定向到云盘厂商 URL，手机直连云盘下载。不经过任何服务器。

### 7.3 荷兰服务公网访问

DNS 直连荷兰 IP，不经过上海，不经过 HY2，延迟最低。

### 7.4 离线下载 -> 本地盘

用户添加下载任务 -> 荷兰服务器下载完成 -> Mac cron rsync 通过 HY2 拉取 -> 文件到达外接盘 -> Mac OpenList 可访问。

## 8. 交付物


**Git 流程：** 所有代码修改通过 git 进行版本管理，每次改动后提交，最终版本 push 到 GitHub。

**仓库结构：**
```
.gitignore
README.md
scripts/
  setup-shanghai.sh
  setup-netherlands.sh
  setup-macmini.sh
```

三个一键部署脚本，发布至 GitHub 仓库：

| 脚本 | 目标机器 | 功能 |
|------|----------|------|
| `setup-shanghai.sh` | 上海 VPS | 安装 Caddy + HY2 Server + 配置 |
| `setup-netherlands.sh` | 荷兰 VPS | 安装 Caddy + HY2 Server + OpenList + qB/Aria2/AriaNg Docker |
| `setup-macmini.sh` | Mac Mini | 安装 OpenList + HY2 Client x2 + crontab 回传脚本 |

README 包含：架构说明图、前置条件、三条一键部署命令、部署后验证步骤。

## 9. 非功能需求

- **安全**：所有对外服务使用 HTTPS，HY2 隧道加密
- **可靠**：rsync 支持断点续传，HY2 自动重连
- **可维护**：一键脚本部署，配置集中在脚本变量中
- **性能**：HY2 纯 UDP 加速，荷兰服务直连不绕路，网盘 302 直连不经过中转
