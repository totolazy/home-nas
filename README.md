 # 家庭 NAS — 一键部署

 三节点家庭私有云，基于 Hysteria 2 + OpenList，支持公网穿透、离线下载、网盘挂载。

 ## 架构

 ```
                   Cloudflare DNS
               ┌──────────────────┐
               │ openlist → 国内IP  │
               │ nllist   → 国外IP  │
               │ qb       → 国外IP  │
               │ aria     → 国外IP  │
               └──────────────────┘
                      │
         ┌────────────┴────────────┐
         ▼                         ▼
 ┌──────────────┐          ┌──────────────┐
 │  国内 VPS     │          │  国外 VPS     │
 │  Caddy HTTPS  │          │  Caddy HTTPS  │
 │  HY2 Server   │          │  HY2 Server   │
 │  tcpFwd→Mac   │          │  OpenList     │
 └──────┬───────┘          │  qB (Docker)  │
        │ HY2               │  Aria2 (Docker)│
        │                   │  AriaNg (Docker)│
 ┌──────┴───────┐          └──────┬───────┘
 │  Mac Mini M4  │                │ HY2
 │  HY2 Client→国内│               │
 │  HY2 Client→国外│◄─────────────┘
 │  OpenList     │    rsync 回传
 │  外接盘        │
 └──────────────┘
 ```

 ## 前置条件

 1. **域名**：`dickgroup.xyz` 托管在 Cloudflare
 2. **DNS 记录**（提前在 Cloudflare 添加）：
    - `域名` → A → 国内服务器 IP
    - `域名` → A → 国外服务器 IP
    - `域名` → A → 国外服务器 IP
    - `域名` → A → 国外服务器 IP
 3. **国内 VPS**：Debian/Ubuntu，root 权限，防火墙开放 80/443/UDP-8443
 4. **国外 VPS**：Debian/Ubuntu，root 权限，防火墙开放 80/443/UDP-8443，已安装 Docker
 5. **Mac Mini M4**：macOS，已安装 Homebrew，外接盘已挂载

 ## 一键部署

 在对应机器上分别执行：

 ```bash
 # 国内 VPS
 bash <(curl -fsSL https://raw.githubusercontent.com/totolazy/home-nas/main/scripts/setup-shanghai.sh)

 # 国外 VPS
 bash <(curl -fsSL https://raw.githubusercontent.com/totolazy/home-nas/main/scripts/setup-netherlands.sh)

 # Mac Mini
 bash <(curl -fsSL https://raw.githubusercontent.com/totolazy/home-nas/main/scripts/setup-macmini.sh)
 ```

 脚本启动后会交互式引导你输入服务器 IP、密码等参数。

 ## 卸载

 ```bash
 # 国内 VPS
 bash <(curl -fsSL https://raw.githubusercontent.com/totolazy/home-nas/main/scripts/teardown-shanghai.sh)

 # 国外 VPS
 bash <(curl -fsSL https://raw.githubusercontent.com/totolazy/home-nas/main/scripts/teardown-netherlands.sh)

 # Mac Mini
 bash <(curl -fsSL https://raw.githubusercontent.com/totolazy/home-nas/main/scripts/teardown-macmini.sh)
 ```

 卸载脚本会清理项目所有痕迹，不破坏系统原有环境（Homebrew/Docker/Caddy 软件包保留）。

 ## 验证

 部署完成后：

 ```bash
 # 国内：验证 HTTPS
 curl -I https://openlist.dickgroup.xyz

 # 国外：验证 HTTPS
 curl -I https://nllist.dickgroup.xyz
 curl -I https://qb.dickgroup.xyz
 curl -I https://aria.dickgroup.xyz

 # Mac Mini：验证回传
 /opt/scripts/pullback.sh
 ```

 ## 目录结构

 ```
 .
 ├── README.md
 ├── .gitignore
 ├── docs/
 │   └── nbl/
 │       ├── specs/   # 技术设计文档
 │       └── plans/   # 实现计划
 └── scripts/
     ├── setup-shanghai.sh
     ├── setup-netherlands.sh
     ├── setup-macmini.sh
     ├── teardown-shanghai.sh
     ├── teardown-netherlands.sh
     └── teardown-macmini.sh
 ```

 ## 许可

 MIT
