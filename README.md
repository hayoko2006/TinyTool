# TinyTool

<p align="center">
  <img src="https://img.shields.io/badge/version-1.1.0-blue" alt="version">
  <img src="https://img.shields.io/badge/shell-bash-green" alt="shell">
  <img src="https://img.shields.io/badge/license-MIT-yellow" alt="license">
  <img src="https://img.shields.io/badge/platform-Linux-red" alt="platform">
  <img src="https://img.shields.io/badge/i18n-zh%20%7C%20en-purple" alt="i18n">
</p>

<p align="center">
  <b>中文</b> | <a href="#-english">English</a>
</p>

---

## 🇨🇳 中文

<p align="center"><b>一条命令，开启自动化运维旅程</b></p>

<p align="center">
  <a href="https://tinytool.hayoko.cn">官网</a> |
  <a href="https://github.com/hayoko2006/TinyTool">GitHub</a>
</p>

### 简介

TinyTool 是一个极简、高效、自动化的 Linux 运维工具。只需一条命令即可部署到任意 Linux 服务器，自动检测系统环境（CentOS / Ubuntu / Debian），提供 15 大功能模块的交互式运维界面。**支持中英文双语切换**，按 `L` 键即可切换语言。

### 快速开始

```bash
# 方式一（推荐）
bash <(curl -sL https://tinytool.hayoko.cn/tinytool.sh)

# 方式二（wget）
wget -qO- https://tinytool.hayoko.cn/tinytool.sh | bash

# 方式三（GitHub Raw）
bash <(curl -sL https://raw.githubusercontent.com/hayoko2006/TinyTool/main/tinytool.sh)
```

### 功能模块

**系统工具**

| # | 模块 | 功能描述 |
|---|------|---------|
| 1 | 系统自检 | CPU/内存/磁盘/网络/安全/服务/更新 8 项检测，生成健康度评分报告 |
| 2 | 软件源管理 | 阿里云/清华/中科大/腾讯/华为 5 大镜像源，一键切换，自动备份恢复 |
| 3 | 存储管理 | 磁盘分区查看、数据盘自动挂载(fstab 持久化)、LVM 在线扩容、占用分析、大文件排查 |
| 4 | 系统管理 | 一键系统更新、时区设置+时间同步、Swap 管理、缓存清理、自启服务查看、重启 |

**网络工具**

| # | 模块 | 功能描述 |
|---|------|---------|
| 5 | DNS 管理 | 5 种 DNS 切换、解析测试、延迟测速、一键恢复 |
| 6 | 网络管理 | SSH 端口修改、防火墙管理(firewalld/ufw)、网络测速(带宽/热门网站/延迟)、邮件服务检测、连通性测试、端口扫描 |
| 7 | SSH 管理 | 配置查看、一键安全加固、禁止 root 密码登录、仅密钥模式、密钥生成/导入、登录日志、fail2ban 防爆破 |

**面板与服务**

| # | 模块 | 功能描述 |
|---|------|---------|
| 8 | 宝塔管理 | 一键安装、面板信息查看、密码重置、数据盘挂载到 /www、卸载 |
| 9 | Caddy 管理 | 官方源安装、状态查看、启停控制、Caddyfile 编辑、卸载 |
| 10 | Docker 管理 | 官方脚本安装+国内镜像加速、数据目录迁移、分层清理、Compose 管理 |
| 15 | 1Panel 管理 | 一键安装、面板信息查看、密码重置、端口修改、状态/重启、数据盘迁移、卸载 |

**监控与日志**

| # | 模块 | 功能描述 |
|---|------|---------|
| 11 | 进程监控 | CPU/内存 TOP 20、按名称/端口查找进程、kill/kill -9 结束进程、进程树 |
| 12 | 日志工具 | 系统日志、认证日志、Nginx/Apache 日志、dmesg、启动日志、关键词搜索、日志清空 |

**实用工具**

| # | 模块 | 功能描述 |
|---|------|---------|
| 13 | 定时任务 | 查看/新增/删除 crontab 任务、编辑 crontab、服务状态、常用模板 |
| 14 | 配置导出 | 系统配置一键导出（网络/SSH/防火墙/定时任务/磁盘/软件包/服务列表），打包为 tar.gz |

### 系统要求

- **操作系统**: CentOS 7+ / RHEL / Rocky / AlmaLinux / Ubuntu 18.04+ / Debian 9+
- **权限**: root 用户
- **依赖**: 脚本会自动检测并安装缺失的基础工具（curl / wget / tar）

### 核心特性

- **自动适配系统**: 启动时自动检测 CentOS/Ubuntu/Debian，选择正确的包管理器
- **中英双语支持**: 自动检测系统语言，主菜单按 `L` 键可随时切换中英文
- **自我更新机制**: 启动时自动检查 `tinytool.hayoko.cn` 版本号，提示并自动更新
- **环境自动修复**: 检测缺失工具并自动安装、修复 DNS 解析异常、同步系统时间
- **安全防护**: 所有危险操作前均有确认提示，关键配置修改自动备份，配置验证失败自动回滚

### 项目结构

```
TinyTool/
├── tinytool.sh    # 主脚本（约 3300 行，15 个功能模块，中英双语）
├── README.md      # 项目说明（中英双语）
├── index.html     # 官网页面（中英双语）
├── _headers       # EdgeOne Pages Headers 配置
└── _redirects     # EdgeOne Pages Redirects 配置
```

### 部署到网站

将 `tinytool.sh` 上传到你的 Web 服务器，确保以纯文本方式提供访问：

```nginx
location /tinytool.sh {
    add_header Content-Type text/plain;
    add_header Cache-Control "no-cache";
}
```

### 开源协议

MIT License

---

## 🇬🇧 English

<p align="center"><b>One command, automate your ops journey</b></p>

<p align="center">
  <a href="https://tinytool.hayoko.cn">Website</a> |
  <a href="https://github.com/hayoko2006/TinyTool">GitHub</a>
</p>

### Introduction

TinyTool is a minimal, efficient, and automated Linux operations tool. Deploy to any Linux server with a single command. Auto-detects system environment (CentOS / Ubuntu / Debian) and provides an interactive ops interface with 15 feature modules. **Supports bilingual Chinese/English** — press `L` to switch languages.

### Quick Start

```bash
# Method 1 (recommended)
bash <(curl -sL https://tinytool.hayoko.cn/tinytool.sh)

# Method 2 (wget)
wget -qO- https://tinytool.hayoko.cn/tinytool.sh | bash

# Method 3 (GitHub Raw)
bash <(curl -sL https://raw.githubusercontent.com/hayoko2006/TinyTool/main/tinytool.sh)
```

### Feature Modules

**System Tools**

| # | Module | Description |
|---|--------|-------------|
| 1 | System Check | 8 health checks: CPU, memory, disk, network, security, services, updates. Generates a scored report |
| 2 | Repo Mirror | Switch between 5 mirrors (Aliyun/Tsinghua/USTC/Tencent/Huawei), auto backup & restore |
| 3 | Storage | Disk partition viewer, auto data disk mount (persistent fstab), LVM expansion, usage analysis, large file finder |
| 4 | System | One-click system update, timezone & time sync, Swap management, cache cleanup, services, reboot |

**Network Tools**

| # | Module | Description |
|---|--------|-------------|
| 5 | DNS | 5 DNS presets, resolution testing, latency benchmarking, one-click restore |
| 6 | Network | SSH port change, firewall (firewalld/ufw), speedtest (bandwidth/sites/latency), mail detection, connectivity test, port scan |
| 7 | SSH | Config viewer, one-click hardening, disable password auth, key-only mode, key generation/import, login logs, fail2ban |

**Panels & Services**

| # | Module | Description |
|---|--------|-------------|
| 8 | aaPanel | One-click install, info viewer, password reset, data disk mount to /www, uninstall |
| 9 | Caddy | Official repo install, status check, start/stop control, Caddyfile editor, uninstall |
| 10 | Docker | Official installer with mirror acceleration, data dir migration, layered cleanup, Compose management |
| 15 | 1Panel | One-click install, info viewer, password reset, port change, status/restart, data disk migration, uninstall |

**Monitor & Logs**

| # | Module | Description |
|---|--------|-------------|
| 11 | Process | CPU/Memory TOP 20, search by name/port, kill/kill -9, process tree |
| 12 | Logs | System logs, auth logs, Nginx/Apache logs, dmesg, boot logs, keyword search, clear logs |

**Utilities**

| # | Module | Description |
|---|--------|-------------|
| 13 | Cron | View/add/delete crontab tasks, edit crontab, service status, common templates |
| 14 | Export | Export all system configs (network/SSH/firewall/cron/disk/packages/services) as tar.gz |

### System Requirements

- **OS**: CentOS 7+ / RHEL / Rocky / AlmaLinux / Ubuntu 18.04+ / Debian 9+
- **Privilege**: root user
- **Dependencies**: Script auto-detects and installs missing basic tools (curl / wget / tar)

### Key Features

- **Auto system detection**: Detects CentOS/Ubuntu/Debian at startup and selects the correct package manager
- **Bilingual support**: Auto-detects system language, press `L` in the menu to switch anytime
- **Self-updating**: Auto-checks version from `tinytool.hayoko.cn` and prompts for updates
- **Auto env repair**: Installs missing tools, fixes DNS issues, syncs system time
- **Safety first**: Confirmation prompts for all dangerous operations; auto-backup before config changes; auto-rollback on validation failure

### Project Structure

```
TinyTool/
├── tinytool.sh    # Main script (~3300 lines, 15 modules, bilingual zh/en)
├── README.md      # Documentation (bilingual zh/en)
├── index.html     # Official website (bilingual zh/en)
├── _headers       # EdgeOne Pages Headers config
└── _redirects     # EdgeOne Pages Redirects config
```

### Deploy to Your Website

Upload `tinytool.sh` to your web server and ensure it's served as plain text:

```nginx
location /tinytool.sh {
    add_header Content-Type text/plain;
    add_header Cache-Control "no-cache";
}
```

### License

MIT License

---

<p align="center">Made with ❤️ by <a href="https://github.com/hayoko2006">Hayoko</a></p>
