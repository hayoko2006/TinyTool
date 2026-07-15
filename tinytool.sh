#!/bin/bash
# ============================================================================
#  TinyTool - 一条命令，开启自动化运维旅程
#  Author : Hayoko
#  Site   : tinytool.hayoko.cn
#  Desc   : 极简、高效、自动化的 Linux 运维工具
#           自动适配 CentOS / Ubuntu / Debian
# ============================================================================

readonly VERSION="2.0.1-1"
readonly SCRIPT_URL="https://tinytool.hayoko.cn/tinytool.sh"
readonly GITHUB_RAW="https://raw.githubusercontent.com/hayoko2006/TinyTool/main/tinytool.sh"

# ============================ 颜色与通用函数 ================================
if [[ -t 1 ]]; then
    readonly C_R='\033[31m'   # 红
    readonly C_G='\033[32m'   # 绿
    readonly C_Y='\033[33m'   # 黄
    readonly C_B='\033[34m'   # 蓝
    readonly C_P='\033[35m'   # 紫
    readonly C_C='\033[36m'   # 青
    readonly C_W='\033[1;37m' # 白(粗)
    readonly C_D='\033[90m'   # 灰
    readonly C_0='\033[0m'    # 重置
else
    readonly C_R='' C_G='' C_Y='' C_B='' C_P='' C_C='' C_W='' C_D='' C_0=''
fi

_log()  { echo -e "${C_D}[$(date '+%H:%M:%S')]${C_0} $*"; }
_ok()   { echo -e "${C_G}[√]${C_0} $*"; }
_err()  { echo -e "${C_R}[×]${C_0} $*"; }
_warn() { echo -e "${C_Y}[!]${C_0} $*"; }
_info() { echo -e "${C_C}[i]${C_0} $*"; }

# 进度条
_bar() {
    local cur=$1 total=$2 width=30
    local pct=$(( cur * 100 / total ))
    local filled=$(( pct * width / 100 ))
    printf "\r${C_C}[${C_G}$(printf '#%.0s' $(seq 1 $filled))${C_D}$(printf '.%.0s' $(seq 1 $(( width - filled ))))${C_C}]${C_0} ${pct}%%"
}

# 确认操作
_confirm() {
    local msg=$1
    read -rp "$(echo -e "${C_Y}[?]${C_0} ${msg} [y/N]: ")" ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

# 暂停
_pause() { read -rp "$(echo -e "${C_D}按回车继续...${C_0}")"; }

# 分隔线
_line() { echo -e "${C_D}────────────────────────────────────────────────${C_0}"; }

# 标题
_title() { echo -e "\n${C_P}═══ $* ═══${C_0}\n"; }

# 检查命令是否存在
_has() { command -v "$1" &>/dev/null; }

# 安装软件包
_pkg_install() {
    if [[ "$PM" == "apt" ]]; then
        apt-get update -qq && apt-get install -y -qq "$@"
    elif [[ "$PM" == "yum" ]]; then
        yum install -y -q "$@"
    elif [[ "$PM" == "dnf" ]]; then
        dnf install -y -q "$@"
    fi
}

# ============================ Root 检查 ======================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        _err "请使用 root 用户运行此脚本！"
        _info "提示: sudo -i 切换 root 后重试"
        exit 1
    fi
}

# ============================ 系统检测 ======================================
# 全局变量
SYS=""
SYS_VER=""
PM=""
ARCH=""

detect_system() {
    ARCH=$(uname -m)

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        SYS=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
        SYS_VER=$(echo "$VERSION_ID" | cut -d. -f1)
    elif [[ -f /etc/redhat-release ]]; then
        SYS="centos"
        SYS_VER=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
    else
        _err "无法识别系统类型！"
        exit 1
    fi

    # 统一发行版判断
    case "$SYS" in
        centos|rhel|rocky|almalinux|fedora)
            if _has dnf; then PM="dnf"; else PM="yum"; fi
            SYS="centos"
            ;;
        ubuntu|debian|linuxmint)
            PM="apt"
            ;;
        *)
            _warn "未完全适配的系统: $SYS，将尝试通用模式"
            if _has apt-get; then PM="apt"; elif _has dnf; then PM="dnf"; else PM="yum"; fi
            ;;
    esac
}

# ============================ 自我更新 ======================================
self_update() {
    _title "检查更新"
    local tmp
    tmp=$(mktemp)
    if curl -sL --connect-timeout 5 "$SCRIPT_URL" -o "$tmp" 2>/dev/null; then
        local remote_ver
        remote_ver=$(grep -m1 'readonly VERSION=' "$tmp" | sed 's/.*readonly VERSION="\([^"]*\)".*/\1/')
        if [[ -n "$remote_ver" && "$remote_ver" != "$VERSION" ]]; then
            _info "发现新版本: $remote_ver (当前: $VERSION)"
            if _confirm "是否更新到最新版本？"; then
                # 找到脚本自身路径
                local self="$0"
                [[ "$0" == "bash" || -z "$self" ]] && self="/usr/local/bin/tinytool"
                cp "$tmp" "$self" && chmod +x "$self"
                _ok "更新完成！正在重新启动..."
                rm -f "$tmp"
                exec bash "$self"
            fi
        else
            _ok "已是最新版本 ($VERSION)"
        fi
    else
        _warn "无法连接更新服务器，跳过更新检查"
    fi
    rm -f "$tmp"
}

# ============================ 环境修复 ======================================
env_repair() {
    _title "环境修复"
    local missing=()

    # 检查基础工具
    for cmd in curl wget tar; do
        if ! _has "$cmd"; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        _warn "缺少工具: ${missing[*]}"
        _info "正在自动安装..."
        _pkg_install "${missing[@]}" && _ok "基础工具安装完成" || _err "安装失败，请手动安装: ${missing[*]}"
    else
        _ok "基础工具完整"
    fi

    # 检查 DNS 解析
    if ! ping -c1 -W2 tinytool.hayoko.cn &>/dev/null && ! nslookup tinytool.hayoko.cn &>/dev/null 2>&1; then
        _warn "DNS 解析异常，尝试修复..."
        if grep -q "nameserver 8.8.8.8" /etc/resolv.conf 2>/dev/null; then
            :
        else
            cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null
            echo -e "nameserver 8.8.8.8\nnameserver 114.114.114.114" > /etc/resolv.conf
            _ok "DNS 已临时修复 (8.8.8.8 / 114.114.114.114)"
        fi
    else
        _ok "网络连通正常"
    fi

    # 修复时间偏差
    if _has ntpdate; then
        _info "同步系统时间..."
        ntpdate -u pool.ntp.org &>/dev/null && _ok "时间已同步" || _warn "时间同步失败"
    fi
}

# ============================ 主菜单 ========================================
show_banner() {
    clear
    echo -e "${C_C}"
    cat << 'BANNER'
  ╔══════════════════════════════════════════════════════════╗
  ║  _____   _                   _____                   _    ║
  ║ |_   _| (_)  _ __    _   _  |_   _|   ___     ___   | |   ║
  ║   | |   | | | '_ \  | | | |   | |    / _ \   / _ \  | |   ║
  ║   | |   | | | | | | | |_| |   | |   | (_) | | (_) | | |   ║
  ║   |_|   |_| |_| |_|  \__, |   |_|    \___/   \___/  |_|   ║
  ║                      |___/                                ║
  ║            一条命令，开启自动化运维旅程                  ║
  ╚══════════════════════════════════════════════════════════╝
BANNER
    echo -e "${C_0}"
    echo -e "  ${C_D}版本:${C_0} v${VERSION}  ${C_D}系统:${C_0} ${SYS^} ${SYS_VER}  ${C_D}架构:${C_0} ${ARCH}  ${C_D}包管:${C_0} ${PM}"
    _line
}

main_menu() {
    while true; do
        show_banner
        echo -e "  ${C_D}─── 系统管理 ─────────────────────────────────${C_0}"
        echo -e "  ${C_G} 1)${C_0} 系统自检              健康度检测与报告"
        echo -e "  ${C_G} 2)${C_0} 软件源管理            更换国内镜像源"
        echo -e "  ${C_G} 3)${C_0} 存储管理              挂载、扩容、占用分析"
        echo -e "  ${C_G} 4)${C_0} 系统管理              系统更新、时区、Swap"
        echo -e "  ${C_G} 5)${C_0} DNS 管理              切换、测试、恢复"
        echo ""
        echo -e "  ${C_D}─── 网络 & 安全 ──────────────────────────────${C_0}"
        echo -e "  ${C_G} 6)${C_0} 网络管理              SSH端口、防火墙、测速"
        echo -e "  ${C_G} 7)${C_0} SSH 管理              配置查看与安全加固"
        echo ""
        echo -e "  ${C_D}─── 面板 & 容器 ──────────────────────────────${C_0}"
        echo -e "  ${C_G} 8)${C_0} 宝塔管理              安装、密码、挂载数据盘"
        echo -e "  ${C_G} 9)${C_0} Caddy 管理            安装、卸载、状态"
        echo -e "  ${C_G}10)${C_0} Docker 管理           安装、迁移、清理"
        echo -e "  ${C_G}11)${C_0} 1Panel 管理           安装、信息、密码、卸载"
        echo ""
        echo -e "  ${C_D}─── 网站 & 数据库 ────────────────────────────${C_0}"
        echo -e "  ${C_G}12)${C_0} 网站管理              站点检测、SSL、虚拟主机"
        echo -e "  ${C_G}13)${C_0} 数据库管理            MySQL/MariaDB/Redis"
        echo ""
        echo -e "  ${C_D}─── 运维 & 安全 ──────────────────────────────${C_0}"
        echo -e "  ${C_G}14)${C_0} 备份管理              打包、远程传输、定时"
        echo -e "  ${C_G}15)${C_0} 安全扫描              基线检查、恶意脚本"
        echo -e "  ${C_G}16)${C_0} 用户权限              用户管理、sudo、权限修复"
        echo -e "  ${C_G}17)${C_0} 磁盘IO测试            性能测试、健康检测"
        echo ""
        echo -e "  ${C_D}─── 实用工具 ─────────────────────────────────${C_0}"
        echo -e "  ${C_G}18)${C_0} 进程监控              实时进程查看与管理"
        echo -e "  ${C_G}19)${C_0} 日志工具              系统日志快速查看"
        echo -e "  ${C_G}20)${C_0} 定时任务              Crontab 管理"
        echo -e "  ${C_G}21)${C_0} 配置导出              系统配置一键导出"
        echo -e "  ${C_G}22)${C_0} 邮件告警              邮件配置与系统告警"
        echo -e "  ${C_G}23)${C_0} 内网穿透              frp/nps 安装配置"
        echo -e "  ${C_G}24)${C_0} LNMP/LAMP             一键安装与环境管理"
        echo ""
        echo -e "  ${C_R} 0)${C_0} 退出程序"
        echo ""
        _line

        read -rp "$(echo -e "${C_W}请选择 [0-24]: ${C_0}")" choice
        case "$choice" in
            1)  m_syscheck ;;
            2)  m_mirror ;;
            3)  m_storage ;;
            4)  m_system ;;
            5)  m_dns ;;
            6)  m_network ;;
            7)  m_ssh ;;
            8)  m_baota ;;
            9)  m_caddy ;;
            10) m_docker ;;
            11) m_1panel ;;
            12) m_web ;;
            13) m_db ;;
            14) m_backup ;;
            15) m_security ;;
            16) m_user ;;
            17) m_io ;;
            18) m_process ;;
            19) m_logs ;;
            20) m_cron ;;
            21) m_export ;;
            22) m_mail ;;
            23) m_nat ;;
            24) m_lnmp ;;
            0)  echo -e "${C_G}感谢使用 TinyTool，再见！${C_0}"; exit 0 ;;
            *)  _warn "无效选择" ;;
        esac
        _pause
    done
}

# ============================ 模块 1: 系统自检 ==============================
m_syscheck() {
    _title "系统自检 - 健康度检测与报告"
    local score=100
    local report=""
    local issues=()

    echo -e "${C_C}【1/8】系统信息${C_0}"
    _line
    local hostname_val kernel_val uptime_val
    hostname_val=$(hostname)
    kernel_val=$(uname -r)
    uptime_val=$(uptime -p 2>/dev/null | sed 's/up //')
    echo -e "  主机名   : ${C_W}${hostname_val}${C_0}"
    echo -e "  内核     : ${C_W}${kernel_val}${C_0}"
    echo -e "  运行时间 : ${C_W}${uptime_val}${C_0}"
    echo -e "  系统     : ${C_W}${SYS^} ${SYS_VER} (${ARCH})${C_0}"
    echo ""

    echo -e "${C_C}【2/8】CPU 状态${C_0}"
    _line
    local cpu_model cpu_cores cpu_load
    cpu_model=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')
    cpu_cores=$(grep -c ^processor /proc/cpuinfo)
    read -r cpu_load _ < /proc/loadavg
    echo -e "  型号   : ${C_W}${cpu_model}${C_0}"
    echo -e "  核心数 : ${C_W}${cpu_cores}${C_0}"
    echo -e "  负载   : ${C_W}${cpu_load}${C_0} (1分钟)"
    # 负载检测
    local load_int=${cpu_load%.*}
    if [[ ${load_int:-0} -ge ${cpu_cores:-1} ]]; then
        score=$((score - 15))
        issues+=("CPU 负载过高 (${cpu_load})")
        _warn "  状态   : 负载过高！"
    else
        _ok "  状态   : 正常"
    fi
    echo ""

    echo -e "${C_C}【3/8】内存状态${C_0}"
    _line
    local mem_total mem_used mem_free mem_pct
    mem_total=$(free -m | awk '/Mem:/ {printf "%.0f", $2}')
    mem_used=$(free -m | awk '/Mem:/ {printf "%.0f", $2 - $7}')  # available = $7 on newer, fallback
    [[ -z "$mem_used" ]] && mem_used=$(free -m | awk '/Mem:/ {printf "%.0f", $3}')
    if [[ ${mem_total:-0} -gt 0 ]]; then
        mem_pct=$(( mem_used * 100 / mem_total ))
    else
        mem_pct=0
    fi
    echo -e "  总量   : ${C_W}${mem_total}MB${C_0}"
    echo -e "  已用   : ${C_W}${mem_used}MB${C_0} (${mem_pct}%)"
    echo -e "  可用   : ${C_W}$(( mem_total - mem_used ))MB${C_0}"
    # 内存使用检测
    if [[ ${mem_pct:-0} -ge 90 ]]; then
        score=$((score - 15))
        issues+=("内存使用率过高 (${mem_pct}%)")
        _err "  状态   : 内存不足！"
    elif [[ ${mem_pct:-0} -ge 75 ]]; then
        score=$((score - 8))
        issues+=("内存使用率偏高 (${mem_pct}%)")
        _warn "  状态   : 内存使用偏高"
    else
        _ok "  状态   : 正常"
    fi
    echo ""

    # Swap 检测
    local swap_total swap_used
    swap_total=$(free -m | awk '/Swap:/ {print $2}')
    if [[ ${swap_total:-0} -gt 0 ]]; then
        swap_used=$(free -m | awk '/Swap:/ {print $3}')
        local swap_pct=$(( swap_used * 100 / swap_total ))
        echo -e "  Swap   : ${C_W}${swap_used}MB / ${swap_total}MB${C_0} (${swap_pct}%)"
        if [[ ${swap_pct:-0} -ge 50 ]]; then
            score=$((score - 5))
            issues+=("Swap 使用率较高 (${swap_pct}%)")
            _warn "  状态   : Swap 使用较高"
        else
            _ok "  状态   : Swap 正常"
        fi
    else
        echo -e "  Swap   : ${C_D}未启用${C_0}"
        _warn "  状态   : 建议启用 Swap"
    fi
    echo ""

    echo -e "${C_C}【4/8】磁盘状态${C_0}"
    _line
    df -h | grep -vE 'tmpfs|devtmpfs|overlay' | while read -r line; do
        local pcent
        pcent=$(echo "$line" | awk '{print $5}' | tr -d '%')
        local dev=$(echo "$line" | awk '{print $1}')
        local mnt=$(echo "$line" | awk '{print $6}')
        local sz=$(echo "$line" | awk '{print $2}')
        local used=$(echo "$line" | awk '{print $3}')
        local avail=$(echo "$line" | awk '{print $4}')
        if [[ ${pcent:-0} -ge 95 ]]; then
            printf "  ${C_R}%-16s %-8s %s/%s (可用%s) %s  严重！${C_0}\n" "$dev" "$mnt" "$used" "$sz" "$avail" "${pcent}%"
        elif [[ ${pcent:-0} -ge 85 ]]; then
            printf "  ${C_Y}%-16s %-8s %s/%s (可用%s) %s  偏高${C_0}\n" "$dev" "$mnt" "$used" "$sz" "$avail" "${pcent}%"
        else
            printf "  ${C_G}%-16s %-8s %s/%s (可用%s) %s${C_0}\n" "$dev" "$mnt" "$used" "$sz" "$avail" "${pcent}%"
        fi
    done
    # 根分区检测
    local root_pct
    root_pct=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    if [[ ${root_pct:-0} -ge 95 ]]; then
        score=$((score - 20))
        issues+=("根分区使用率过高 (${root_pct}%)")
    elif [[ ${root_pct:-0} -ge 85 ]]; then
        score=$((score - 10))
        issues+=("根分区使用率偏高 (${root_pct}%)")
    fi
    echo ""

    echo -e "${C_C}【5/8】网络状态${C_0}"
    _line
    local net_ip
    # 内网IP
    net_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [[ -z "$net_ip" ]] && net_ip=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127 | head -1)
    echo -e "  内网IP : ${C_W}${net_ip:-未知}${C_0}"
    # 外网连通性
    if ping -c1 -W2 223.5.5.5 &>/dev/null; then
        _ok "  外网   : 连通 (223.5.5.5)"
    else
        score=$((score - 10))
        issues+=("外网连通性异常")
        _err "  外网   : 不通"
    fi
    # DNS 解析
    if nslookup baidu.com &>/dev/null 2>&1; then
        _ok "  DNS    : 解析正常"
    else
        score=$((score - 8))
        issues+=("DNS 解析异常")
        _err "  DNS    : 解析失败"
    fi
    echo ""

    echo -e "${C_C}【6/8】安全检查${C_0}"
    _line
    # SSH root 登录检测
    if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
        _warn "  SSH    : 允许 root 直接登录 (建议禁止)"
        score=$((score - 5))
        issues+=("SSH 允许 root 直接登录")
    else
        _ok "  SSH    : root 登录配置合理"
    fi
    # 密码登录检测
    if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
        _warn "  SSH    : 允许密码登录 (建议使用密钥)"
        score=$((score - 3))
        issues+=("SSH 允许密码登录")
    else
        _ok "  SSH    : 密码登录已限制"
    fi
    # 防火墙状态
    if _has firewall-cmd && systemctl is-active firewalld &>/dev/null; then
        _ok "  防火墙 : firewalld 已启用"
    elif _has ufw && ufw status 2>/dev/null | grep -q "active"; then
        _ok "  防火墙 : ufw 已启用"
    else
        _warn "  防火墙 : 未启用 (建议开启)"
        score=$((score - 5))
        issues+=("防火墙未启用")
    fi
    # SELinux
    if _has getenforce; then
        local selinux_stat
        selinux_stat=$(getenforce 2>/dev/null)
        if [[ "$selinux_stat" == "Enforcing" ]]; then
            echo -e "  SELinux: ${C_Y}${selinux_stat}${C_0} (可能影响部分服务)"
        else
            echo -e "  SELinux: ${C_G}${selinux_stat}${C_0}"
        fi
    fi
    echo ""

    echo -e "${C_C}【7/8】关键服务${C_0}"
    _line
    for svc in sshd crond cron systemd-journald; do
        if systemctl is-active "$svc" &>/dev/null; then
            printf "  ${C_G}●${C_0} %-20s 运行中\n" "$svc"
        elif systemctl list-unit-files 2>/dev/null | grep -q "$svc"; then
            printf "  ${C_R}○${C_0} %-20s 未运行\n" "$svc"
        fi
    done
    echo ""

    echo -e "${C_C}【8/8】系统更新${C_0}"
    _line
    local update_count=0
    if [[ "$PM" == "apt" ]]; then
        apt-get -s upgrade 2>/dev/null | grep -c "^Inst" | { read -r c; echo "  可更新包: ${C_W}${c:-0}${C_0} 个"; }
    elif [[ "$PM" == "yum" ]]; then
        yum check-update --quiet 2>/dev/null | grep -c "\." | { read -r c; echo "  可更新包: ${C_W}${c:-0}${C_0} 个"; }
    elif [[ "$PM" == "dnf" ]]; then
        dnf check-update --quiet 2>/dev/null | grep -c "\." | { read -r c; echo "  可更新包: ${C_W}${c:-0}${C_0} 个"; }
    fi
    echo ""

    # 健康度报告
    _line
    echo -e "\n${C_P}═══ 健康度报告 ═══${C_0}\n"
    local grade color
    if [[ $score -ge 90 ]]; then
        grade="A"; color="$C_G"
    elif [[ $score -ge 75 ]]; then
        grade="B"; color="$C_G"
    elif [[ $score -ge 60 ]]; then
        grade="C"; color="$C_Y"
    elif [[ $score -ge 40 ]]; then
        grade="D"; color="$C_Y"
    else
        grade="F"; color="$C_R"
    fi

    echo -e "  ${color}┌──────────────────┐${C_0}"
    echo -e "  ${color}│  健康度: ${score}/100  │${C_0}  评级: ${color}${grade}${C_0}"
    echo -e "  ${color}└──────────────────┘${C_0}\n"

    if [[ ${#issues[@]} -gt 0 ]]; then
        _warn "发现 ${#issues[@]} 个问题:"
        for i in "${!issues[@]}"; do
            echo -e "  ${C_R}$((i+1)).${C_0} ${issues[$i]}"
        done
    else
        _ok "系统运行状况良好，未发现明显问题！"
    fi

    # 保存报告
    local report_file="/tmp/tinytool_health_$(date +%Y%m%d_%H%M%S).log"
    {
        echo "TinyTool 健康度报告 - $(date)"
        echo "主机: ${hostname_val} | 系统: ${SYS^} ${SYS_VER}"
        echo "健康度: ${score}/100 (评级: ${grade})"
        echo ""
        echo "问题列表:"
        for i in "${!issues[@]}"; do
            echo "  $((i+1)). ${issues[$i]}"
        done
    } > "$report_file" 2>/dev/null
    echo ""
    _info "报告已保存至: ${report_file}"
}

# ============================ 模块 2: 软件源管理 ============================
m_mirror() {
    _title "软件源管理 - 更换国内镜像源"
    while true; do
        echo -e "  ${C_G}1)${C_0} 阿里云源"
        echo -e "  ${C_G}2)${C_0} 清华源 (TUNA)"
        echo -e "  ${C_G}3)${C_0} 中科大源 (USTC)"
        echo -e "  ${C_G}4)${C_0} 腾讯云源"
        echo -e "  ${C_G}5)${C_0} 华为云源"
        echo -e "  ${C_G}6)${C_0} 恢复默认源"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择镜像源 [0-6]: ${C_0}")" choice
        case "$choice" in
            1) _switch_mirror "aliyun" ;; 2) _switch_mirror "tuna" ;;
            3) _switch_mirror "ustc" ;; 4) _switch_mirror "tencent" ;;
            5) _switch_mirror "huawei" ;; 6) _restore_mirror ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
    done
}

_switch_mirror() {
    local provider=$1
    local base_url=""

    case "$provider" in
        aliyun)  base_url="mirrors.aliyun.com" ;;
        tuna)    base_url="mirrors.tuna.tsinghua.edu.cn" ;;
        ustc)    base_url="mirrors.ustc.edu.cn" ;;
        tencent) base_url="mirrors.cloud.tencent.com" ;;
        huawei)  base_url="mirrors.huaweicloud.com" ;;
    esac

    _info "正在更换为 ${provider} 源 (${base_url})..."

    if [[ "$SYS" == "centos" ]]; then
        # CentOS / RHEL 系列
        local repo_dir="/etc/yum.repos.d"
        local codename="$SYS_VER"
        # 判断是否 CentOS Stream
        local stream=""
        if [[ -f /etc/centos-release ]] && grep -q "Stream" /etc/centos-release; then
            stream="stream"
        fi

        # 备份
        mkdir -p "${repo_dir}/backup_$(date +%Y%m%d)"
        cp -f "${repo_dir}"/*.repo "${repo_dir}/backup_$(date +%Y%m%d)/" 2>/dev/null

        if [[ "$provider" == "aliyun" ]]; then
            if [[ "$SYS_VER" == "8" || "$stream" == "stream" ]]; then
                cat > "${repo_dir}/CentOS-Base.repo" << EOF
[baseos]
name=CentOS Stream \$releasever - BaseOS
baseurl=https://${base_url}/centos-stream/\$releasever/BaseOS/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=https://${base_url}/centos-stream/RPM-GPG-KEY-CentOS-Official

[appstream]
name=CentOS Stream \$releasever - AppStream
baseurl=https://${base_url}/centos-stream/\$releasever/AppStream/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=https://${base_url}/centos-stream/RPM-GPG-KEY-CentOS-Official
EOF
            else
                cat > "${repo_dir}/CentOS-Base.repo" << EOF
[base]
name=CentOS-\$releasever - Base
baseurl=https://${base_url}/centos/\$releasever/os/\$basearch/
gpgcheck=1
gpgkey=https://${base_url}/centos/RPM-GPG-KEY-CentOS-\$releasever

[updates]
name=CentOS-\$releasever - Updates
baseurl=https://${base_url}/centos/\$releasever/updates/\$basearch/
gpgcheck=1
gpgkey=https://${base_url}/centos/RPM-GPG-KEY-CentOS-\$releasever

[extras]
name=CentOS-\$releasever - Extras
baseurl=https://${base_url}/centos/\$releasever/extras/\$basearch/
gpgcheck=1
gpgkey=https://${base_url}/centos/RPM-GPG-KEY-CentOS-\$releasever
EOF
            fi
        else
            # 使用 sed 替换为通用镜像
            for f in "${repo_dir}"/CentOS-*.repo; do
                [[ -f "$f" ]] || continue
                sed -i.bak \
                    -e "s|mirrorlist=|#mirrorlist=|g" \
                    -e "s|#\?baseurl=http://mirror.centos.org|baseurl=https://${base_url}|g" \
                    -e "s|http://mirrors.aliyun.com|https://${base_url}|g" \
                    -e "s|http://mirrors.tuna.tsinghua.edu.cn|https://${base_url}|g" \
                    "$f"
            done
        fi

        _info "正在生成缓存..."
        if [[ "$PM" == "dnf" ]]; then
            dnf clean all && dnf makecache && _ok "源更换成功 (${provider})"
        else
            yum clean all && yum makecache && _ok "源更换成功 (${provider})"
        fi

    else
        # Ubuntu / Debian 系列
        local list_file="/etc/apt/sources.list"
        local distro=""
        local release=""

        if [[ "$SYS" == "ubuntu" ]]; then
            distro="ubuntu"
            release=$(. /etc/os-release; echo "$VERSION_CODENAME")
        else
            distro="debian"
            release=$(. /etc/os-release; echo "$VERSION_CODENAME")
        fi

        # 备份
        [[ -f "$list_file" ]] && cp -f "$list_file" "${list_file}.bak_$(date +%Y%m%d)"

        local url_prefix=""
        case "$provider" in
            aliyun)  url_prefix="https://mirrors.aliyun.com" ;;
            tuna)    url_prefix="https://mirrors.tuna.tsinghua.edu.cn" ;;
            ustc)    url_prefix="https://mirrors.ustc.edu.cn" ;;
            tencent) url_prefix="https://mirrors.cloud.tencent.com" ;;
            huawei)  url_prefix="https://mirrors.huaweicloud.com" ;;
        esac

        if [[ "$distro" == "ubuntu" ]]; then
            cat > "$list_file" << EOF
deb ${url_prefix}/ubuntu/ ${release} main restricted universe multiverse
deb ${url_prefix}/ubuntu/ ${release}-updates main restricted universe multiverse
deb ${url_prefix}/ubuntu/ ${release}-backports main restricted universe multiverse
deb ${url_prefix}/ubuntu/ ${release}-security main restricted universe multiverse
EOF
        else
            cat > "$list_file" << EOF
deb ${url_prefix}/debian/ ${release} main contrib non-free non-free-firmware
deb ${url_prefix}/debian/ ${release}-updates main contrib non-free non-free-firmware
deb ${url_prefix}/debian-security/ ${release}-security main contrib non-free non-free-firmware
EOF
        fi

        _info "正在更新索引..."
        apt-get update -qq && _ok "源更换成功 (${provider})"
    fi
}

_restore_mirror() {
    _info "正在恢复默认源..."
    if [[ "$SYS" == "centos" ]]; then
        local backup_dir
        backup_dir=$(ls -d /etc/yum.repos.d/backup_* 2>/dev/null | sort -r | head -1)
        if [[ -n "$backup_dir" ]]; then
            rm -f /etc/yum.repos.d/*.repo
            cp -f "${backup_dir}"/*.repo /etc/yum.repos.d/ 2>/dev/null
            ${PM} clean all && ${PM} makecache
            _ok "已恢复默认源 (来自 ${backup_dir})"
        else
            _err "未找到备份，无法恢复"
        fi
    else
        local backup
        backup=$(ls -t /etc/apt/sources.list.bak_* 2>/dev/null | head -1)
        if [[ -n "$backup" ]]; then
            cp -f "$backup" /etc/apt/sources.list
            apt-get update -qq
            _ok "已恢复默认源 (来自 ${backup})"
        else
            _err "未找到备份，无法恢复"
        fi
    fi
}

# ============================ 模块 3: 存储管理 ==============================
m_storage() {
    _title "存储管理 - 挂载、扩容、占用分析"
    while true; do
        echo -e "  ${C_G}1)${C_0} 查看磁盘与分区"
        echo -e "  ${C_G}2)${C_0} 自动挂载数据盘"
        echo -e "  ${C_G}3)${C_0} 在线扩容 (LVM)"
        echo -e "  ${C_G}4)${C_0} 磁盘占用分析"
        echo -e "  ${C_G}5)${C_0} 大文件排查 (TOP 20)"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-5]: ${C_0}")" choice
        case "$choice" in
            1) _storage_list ;; 2) _storage_mount ;;
            3) _storage_expand ;; 4) _storage_usage ;;
            5) _storage_bigfiles ;; 0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_storage_list() {
    _info "磁盘与分区信息"
    _line
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL 2>/dev/null || lsblk
    echo ""
    _info "挂载情况"
    _line
    df -hT | grep -vE 'tmpfs|devtmpfs|overlay'
    echo ""
    _info "块设备使用率"
    _line
    df -h --output=source,target,size,used,avail,pcent | grep -vE 'tmpfs|devtmpfs'
}

_storage_mount() {
    _info "检测未挂载的数据盘..."
    _line
    # 列出未挂载的磁盘(排除系统盘)
    local sys_disk
    sys_disk=$(lsblk -ndo PKNAME $(df / --output=source | tail -1) 2>/dev/null)
    [[ -z "$sys_disk" ]] && sys_disk=$(lsblk -ndo NAME $(df / --output=source | tail -1 | sed 's/[0-9]*$//' | sed 's|/dev/||') 2>/dev/null)

    local disks=()
    while read -r name size type; do
        # 排除 loop 和系统盘
        [[ "$type" != "disk" ]] && continue
        [[ "$name" == "$sys_disk" ]] && continue
        [[ "$name" == "loop"* ]] && continue
        disks+=("$name|$size")
    done < <(lsblk -ndo NAME,SIZE,TYPE 2>/dev/null)

    if [[ ${#disks[@]} -eq 0 ]]; then
        _warn "未发现可挂载的新数据盘"
        return
    fi

    echo -e "发现以下数据盘:"
    for i in "${!disks[@]}"; do
        IFS='|' read -r name size <<< "${disks[$i]}"
        echo -e "  ${C_G}$((i+1)))${C_0} /dev/$name  ($size)"
    done
    echo ""
    read -rp "$(echo -e "${C_W}选择要挂载的磁盘 [1-${#disks[@]}]: ${C_0}")" sel
    local idx=$((sel - 1))
    if [[ $idx -lt 0 || $idx -ge ${#disks[@]} ]]; then
        _err "无效选择"
        return
    fi

    IFS='|' read -r disk_name disk_size <<< "${disks[$idx]}"
    local dev="/dev/$disk_name"

    read -rp "$(echo -e "${C_W}挂载点 (默认 /data): ${C_0}")" mnt
    mnt="${mnt:-/data}"

    _info "即将格式化 ${dev} 并挂载到 ${mnt}"
    _confirm "此操作将清除 ${dev} 上所有数据，确认？" || return

    # 检查是否已挂载
    if mount | grep -q "^${dev}"; then
        _warn "${dev} 已挂载，先卸载..."
        umount "$dev" 2>/dev/null
    fi

    # 格式化
    _info "格式化 ${dev} (ext4)..."
    mkfs.ext4 -F "$dev" && _ok "格式化完成" || { _err "格式化失败"; return; }

    # 创建挂载点并挂载
    mkdir -p "$mnt"
    mount "$dev" "$mnt" && _ok "挂载成功: ${dev} -> ${mnt}" || { _err "挂载失败"; return; }

    # 写入 fstab 持久化
    local uuid
    uuid=$(blkid -s UUID -o value "$dev")
    if [[ -n "$uuid" ]]; then
        # 避免重复写入
        if ! grep -q "$uuid" /etc/fstab; then
            echo "UUID=$uuid  $mnt  ext4  defaults,noatime  0 2" >> /etc/fstab
            _ok "已写入 /etc/fstab (开机自动挂载)"
        fi
    fi

    # 验证
    mount -a 2>/dev/null && _ok "fstab 配置验证通过" || _warn "fstab 验证异常，请检查"
    df -hT "$mnt"
}

_storage_expand() {
    _info "LVM 在线扩容"
    _line
    # 检查是否有 LVM
    if ! _has lvs; then
        _warn "未检测到 LVM，尝试直接扩容根分区..."
        # 检查 growpart
        if ! _has growpart; then
            _info "安装 growpart..."
            _pkg_install cloud-utils-growpart 2>/dev/null || _pkg_install cloud-utils 2>/dev/null
        fi
        local root_part root_disk part_num
        root_part=$(lsblk -ndo PKNAME $(df / --output=source | tail -1) 2>/dev/null)
        local root_dev=$(df / --output=source | tail -1)
        # 尝试 growpart
        if [[ -n "$root_dev" ]]; then
            local disk_name="${root_dev%p*}"
            local part_num="${root_part: -1}"
            _info "尝试扩容 ${disk_name} 分区 ${part_num}..."
            growpart "$disk_name" "$part_num" 2>/dev/null && _ok "分区扩容完成"
            # resize filesystem
            if [[ "$root_dev" == *"nvme"* || "$root_dev" == *"xvd"* ]]; then
                resize2fs "$root_dev" 2>/dev/null || xfs_growfs / 2>/dev/null
            else
                resize2fs "$root_dev" 2>/dev/null || xfs_growfs / 2>/dev/null
            fi
            _ok "文件系统已扩容"
            df -h /
        fi
        return
    fi

    echo -e "当前 LVM 信息:"
    lvs 2>/dev/null
    echo ""
    echo -e "可用 PV:"
    pvs 2>/dev/null
    echo ""

    # 查找有剩余空间的 VG
    local vg_name lv_path
    vg_name=$(vgs --noheadings -o vg_name 2>/dev/null | tr -d ' ' | head -1)
    if [[ -z "$vg_name" ]]; then
        _err "未找到 VG"
        return
    fi

    lv_path=$(lvs --noheadings -o lv_path 2>/dev/null | tr -d ' ' | head -1)
    local vg_free
    vg_free=$(vgs --noheadings -o vg_free --units m "$vg_name" 2>/dev/null | tr -d ' ' | sed 's/[mM]//')

    if [[ "${vg_free:-0}" -le 0 ]]; then
        _warn "VG ${vg_name} 没有空闲空间"
        return
    fi

    _info "VG ${vg_name} 剩余: ${vg_free}MB"
    if _confirm "将全部空闲空间分配给 ${lv_path} ？"; then
        lvextend -l +100%FREE "$lv_path" 2>/dev/null && _ok "LV 扩容完成"
        # resize fs
        resize2fs "$lv_path" 2>/dev/null || xfs_growfs "$(df --output=target "$lv_path" | tail -1)" 2>/dev/null
        _ok "文件系统已扩容"
        df -h
    fi
}

_storage_usage() {
    _info "磁盘占用分析 (一级目录)"
    _line
    du -sh /* 2>/dev/null | sort -rh | head -20
    echo ""
    _info "详细分析 (可交互)"
    _line
    echo -e "  ${C_D}提示: 输入路径进行深度分析，直接回车分析 /${C_0}"
    read -rp "$(echo -e "${C_W}分析路径: ${C_0}")" path
    path="${path:-/}"
    echo ""
    du -sh "${path}"/* 2>/dev/null | sort -rh | head -30
}

_storage_bigfiles() {
    _info "查找大文件 (>100MB)"
    _line
    find / -type f -size +100M 2>/dev/null | head -20 | while read -r f; do
        local sz
        sz=$(du -h "$f" 2>/dev/null | cut -f1)
        printf "  ${C_Y}%-8s${C_0} %s\n" "$sz" "$f"
    done
    echo ""
    _info "查找大日志文件"
    _line
    find /var/log -type f -name "*.log" -size +10M 2>/dev/null | while read -r f; do
        local sz
        sz=$(du -h "$f" 2>/dev/null | cut -f1)
        printf "  ${C_Y}%-8s${C_0} %s\n" "$sz" "$f"
    done
}

# ============================ 模块 4: 系统管理 ==============================
m_system() {
    _title "系统管理 - 更新、时区、Swap"
    while true; do
        echo -e "  ${C_G}1)${C_0} 系统更新 (全部升级)"
        echo -e "  ${C_G}2)${C_0} 设置时区 (Asia/Shanghai)"
        echo -e "  ${C_G}3)${C_0} Swap 管理"
        echo -e "  ${C_G}4)${C_0} 清理系统缓存"
        echo -e "  ${C_G}5)${C_0} 查看/管理自启服务"
        echo -e "  ${C_G}6)${C_0} 重启服务器"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-6]: ${C_0}")" choice
        case "$choice" in
            1) _sys_update ;; 2) _sys_timezone ;;
            3) _sys_swap ;; 4) _sys_clean ;;
            5) _sys_services ;; 6) _sys_reboot ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "6" && "$choice" != "0" ]] && _pause
    done
}

_sys_update() {
    _info "正在更新系统..."
    _confirm "将更新所有软件包，可能耗时较长，确认？" || return
    if [[ "$PM" == "apt" ]]; then
        apt-get update -qq
        apt-get upgrade -y
        apt-get autoremove -y
    elif [[ "$PM" == "dnf" ]]; then
        dnf upgrade -y --refresh
        dnf autoremove -y
    else
        yum update -y
        yum autoremove -y 2>/dev/null
    fi
    _ok "系统更新完成"
}

_sys_timezone() {
    _info "设置时区为 Asia/Shanghai..."
    if _has timedatectl; then
        timedatectl set-timezone Asia/Shanghai && _ok "时区设置完成"
        timedatectl status
    else
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
        echo "Asia/Shanghai" > /etc/timezone
        _ok "时区设置完成 ($(date))"
    fi
    # 同步时间
    if ! _has ntpdate; then
        _pkg_install ntpdate 2>/dev/null
    fi
    if _has ntpdate; then
        ntpdate -u pool.ntp.org 2>/dev/null && _ok "时间已同步" || _warn "时间同步失败"
    fi
}

_sys_swap() {
    _title "Swap 管理"
    echo -e "  ${C_G}1)${C_0} 创建 Swap"
    echo -e "  ${C_G}2)${C_0} 调整 Swap 大小"
    echo -e "  ${C_G}3)${C_0} 关闭 Swap"
    echo -e "  ${C_G}4)${C_0} 调整 swappiness"
    echo -e "  ${C_G}0)${C_0} 返回"
    echo ""
    read -rp "$(echo -e "${C_W}选择 [0-4]: ${C_0}")" sc
    case "$sc" in
        1)
            local cur_swap
            cur_swap=$(free -m | awk '/Swap:/ {print $2}')
            if [[ ${cur_swap:-0} -gt 0 ]]; then
                _warn "已存在 Swap (${cur_swap}MB)，请先关闭再创建"
                return
            fi
            local mem_total
            mem_total=$(free -m | awk '/Mem:/ {print $2}')
            local suggest=$(( mem_total ))
            [[ $suggest -gt 4096 ]] && suggest=4096
            read -rp "$(echo -e "${C_W}Swap 大小 MB (建议 ${suggest}): ${C_0}")" swap_sz
            swap_sz="${swap_sz:-$suggest}"
            local swap_file="/swapfile"
            _info "创建 ${swap_sz}MB Swap 文件..."
            dd if=/dev/zero of="$swap_file" bs=1M count="$swap_sz" status=progress
            chmod 600 "$swap_file"
            mkswap "$swap_file"
            swapon "$swap_file"
            # 持久化
            if ! grep -q "$swap_file" /etc/fstab; then
                echo "$swap_file  none  swap  defaults  0 0" >> /etc/fstab
            fi
            sysctl vm.swappiness=10
            _ok "Swap 创建完成"
            free -h
            ;;
        2)
            _info "调整需要先关闭再重建..."
            _confirm "确认调整 Swap？" || return
            swapoff /swapfile 2>/dev/null
            local mem_total
            mem_total=$(free -m | awk '/Mem:/ {print $2}')
            local suggest=$(( mem_total ))
            [[ $suggest -gt 4096 ]] && suggest=4096
            read -rp "$(echo -e "${C_W}新 Swap 大小 MB (建议 ${suggest}): ${C_0}")" swap_sz
            swap_sz="${swap_sz:-$suggest}"
            dd if=/dev/zero of=/swapfile bs=1M count="$swap_sz" status=progress
            chmod 600 /swapfile
            mkswap /swapfile
            swapon /swapfile
            _ok "Swap 调整完成"
            free -h
            ;;
        3)
            _confirm "确认关闭并删除 Swap？" || return
            swapoff -a
            sed -i '/swap/d' /etc/fstab
            rm -f /swapfile
            _ok "Swap 已关闭并清理"
            ;;
        4)
            local cur_sw
            cur_sw=$(cat /proc/sys/vm/swappiness)
            echo -e "当前 swappiness: ${C_W}${cur_sw}${C_0}"
            read -rp "$(echo -e "${C_W}设置 swappiness (0-100，建议 10): ${C_0}")" sw
            sw="${sw:-10}"
            sysctl vm.swappiness="$sw"
            if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
                echo "vm.swappiness=$sw" >> /etc/sysctl.conf
            else
                sed -i "s/vm.swappiness=.*/vm.swappiness=$sw/" /etc/sysctl.conf
            fi
            sysctl -p 2>/dev/null
            _ok "swappiness 已设置为 $sw"
            ;;
        0) return ;;
    esac
}

_sys_clean() {
    _info "清理系统缓存..."
    if [[ "$PM" == "apt" ]]; then
        apt-get clean
        apt-get autoremove -y
        rm -rf /var/cache/apt/archives/*
    elif [[ "$PM" == "dnf" ]]; then
        dnf clean all
        dnf autoremove -y
    else
        yum clean all
        yum autoremove -y 2>/dev/null
    fi
    # 清理日志
    journalctl --vacuum-time=3d 2>/dev/null
    # 清理临时文件
    find /tmp -type f -atime +7 -delete 2>/dev/null
    _ok "清理完成"
    df -h /
}

_sys_services() {
    _info "已启用的自启服务:"
    _line
    systemctl list-unit-files --type=service --state=enabled 2>/dev/null | head -30
    echo ""
    _info "正在运行的服务:"
    _line
    systemctl list-units --type=service --state=running 2>/dev/null | head -20
}

_sys_reboot() {
    _confirm "确认重启服务器？" || return
    _warn "服务器将在 3 秒后重启..."
    sleep 3
    reboot
}

# ============================ 模块 5: DNS 管理 ===============================
m_dns() {
    _title "DNS 管理 - 切换、测试、恢复"
    while true; do
        echo -e "  ${C_G}1)${C_0} 查看当前 DNS"
        echo -e "  ${C_G}2)${C_0} 切换 DNS"
        echo -e "  ${C_G}3)${C_0} 测试 DNS 解析"
        echo -e "  ${C_G}4)${C_0} 恢复 DNS"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-4]: ${C_0}")" choice
        case "$choice" in
            1) _dns_show ;; 2) _dns_switch ;;
            3) _dns_test ;; 4) _dns_restore ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_dns_show() {
    _info "当前 DNS 配置"
    _line
    echo -e "  ${C_D}/etc/resolv.conf:${C_0}"
    cat /etc/resolv.conf
    echo ""
    if _has resolvectl; then
        echo -e "  ${C_D}systemd-resolved 状态:${C_0}"
        resolvectl status 2>/dev/null | head -20
    fi
}

_dns_switch() {
    _title "切换 DNS"
    echo -e "  ${C_G}1)${C_0} 阿里 DNS     (223.5.5.5 / 223.6.6.6)"
    echo -e "  ${C_G}2)${C_0} 腾讯 DNS     (119.29.29.29)"
    echo -e "  ${C_G}3)${C_0} 114 DNS      (114.114.114.114)"
    echo -e "  ${C_G}4)${C_0} Google DNS   (8.8.8.8 / 8.8.4.4)"
    echo -e "  ${C_G}5)${C_0} Cloudflare   (1.1.1.1 / 1.0.0.1)"
    echo -e "  ${C_G}0)${C_0} 返回"
    echo ""
    read -rp "$(echo -e "${C_W}选择 [0-5]: ${C_0}")" dc
    local dns1 dns2
    case "$dc" in
        1) dns1="223.5.5.5";    dns2="223.6.6.6" ;;
        2) dns1="119.29.29.29"; dns2="119.28.28.28" ;;
        3) dns1="114.114.114.114"; dns2="114.114.115.115" ;;
        4) dns1="8.8.8.8";   dns2="8.8.4.4" ;;
        5) dns1="1.1.1.1";   dns2="1.0.0.1" ;;
        0) return ;;
        *) _warn "无效选择"; return ;;
    esac

    # 备份
    [[ ! -f /etc/resolv.conf.bak ]] && cp /etc/resolv.conf /etc/resolv.conf.bak

    _info "切换 DNS 为 ${dns1} / ${dns2}..."
    # 如果是 systemd-resolved 管理的
    if _has resolvectl && systemctl is-active systemd-resolved &>/dev/null; then
        # 取消链接，直接写文件
        rm -f /etc/resolv.conf
        cat > /etc/resolv.conf << EOF
nameserver ${dns1}
nameserver ${dns2}
options timeout:2 attempts:3
EOF
        _warn "检测到 systemd-resolved，已直接写入 resolv.conf"
    else
        cat > /etc/resolv.conf << EOF
nameserver ${dns1}
nameserver ${dns2}
options timeout:2 attempts:3
EOF
    fi
    _ok "DNS 已切换"
    cat /etc/resolv.conf

    # 防止 NetworkManager 覆盖
    if _has nmcli && systemctl is-active NetworkManager &>/dev/null; then
        _info "防止 NetworkManager 覆盖 DNS..."
        local ifname
        ifname=$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep ":connected" | head -1 | cut -d: -f1)
        if [[ -n "$ifname" ]]; then
            nmcli con mod "$ifname" ipv4.dns "${dns1} ${dns2}" 2>/dev/null
            nmcli con mod "$ifname" ipv4.ignore-auto-dns yes 2>/dev/null
            nmcli con up "$ifname" 2>/dev/null
            _ok "NetworkManager DNS 已设置"
        fi
    fi
}

_dns_test() {
    _info "DNS 解析测试"
    _line
    local domains=("baidu.com" "google.com" "github.com" "tinytool.hayoko.cn")
    for domain in "${domains[@]}"; do
        local result
        result=$(nslookup "$domain" 2>&1 | grep -A1 "Name:" | grep "Address" | head -1 | awk '{print $2}')
        if [[ -n "$result" ]]; then
            printf "  ${C_G}√${C_0}  %-20s -> %s\n" "$domain" "$result"
        else
            printf "  ${C_R}×${C_0}  %-20s -> 解析失败\n" "$domain"
        fi
    done
    echo ""
    _info "DNS 响应速度测试"
    _line
    for dns in 223.5.5.5 8.8.8.8 114.114.114.114; do
        local time
        time=$(ping -c3 -W2 "$dns" 2>/dev/null | tail -1 | grep -oE '[0-9.]+/' | head -1 | tr -d '/')
        if [[ -n "$time" ]]; then
            printf "  %-16s 延迟: %s ms\n" "$dns" "$time"
        else
            printf "  %-16s ${C_R}不可达${C_0}\n" "$dns"
        fi
    done
}

_dns_restore() {
    if [[ -f /etc/resolv.conf.bak ]]; then
        cp /etc/resolv.conf.bak /etc/resolv.conf
        _ok "DNS 已恢复"
        cat /etc/resolv.conf
    else
        _err "未找到备份文件 /etc/resolv.conf.bak"
    fi
}

# ============================ 模块 6: 网络管理 ==============================
m_network() {
    _title "网络管理 - SSH端口、防火墙、邮件检测"
    while true; do
        echo -e "  ${C_G}1)${C_0} 查看/修改 SSH 端口"
        echo -e "  ${C_G}2)${C_0} 防火墙管理"
        echo -e "  ${C_G}3)${C_0} 邮件服务检测"
        echo -e "  ${C_G}4)${C_0} 网络连通性测试"
        echo -e "  ${C_G}5)${C_0} 端口扫描"
        echo -e "  ${C_G}6)${C_0} 查看网络连接"
        echo -e "  ${C_G}7)${C_0} 网络测速"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-7]: ${C_0}")" choice
        case "$choice" in
            1) _net_sshport ;; 2) _net_firewall ;;
            3) _net_mail ;; 4) _net_test ;;
            5) _net_portscan ;; 6) _net_connections ;;
            7) _net_speedtest ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_net_sshport() {
    _info "当前 SSH 端口配置"
    _line
    local current_port
    current_port=$(grep -m1 "^#\?Port " /etc/ssh/sshd_config | awk '{print $2}')
    [[ -z "$current_port" ]] && current_port="22"
    echo -e "  当前端口: ${C_W}${current_port}${C_0}"
    echo ""
    read -rp "$(echo -e "${C_W}输入新 SSH 端口 (1-65535，回车跳过): ${C_0}")" new_port
    [[ -z "$new_port" ]] && return

    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 || "$new_port" -gt 65535 ]]; then
        _err "无效端口号"
        return
    fi

    _confirm "确认将 SSH 端口改为 ${new_port}？" || return

    # 备份
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    # 修改端口
    if grep -q "^Port " /etc/ssh/sshd_config; then
        sed -i "s/^Port .*/Port ${new_port}/" /etc/ssh/sshd_config
    elif grep -q "^#Port " /etc/ssh/sshd_config; then
        sed -i "s/^#Port .*/Port ${new_port}/" /etc/ssh/sshd_config
    else
        echo "Port ${new_port}" >> /etc/ssh/sshd_config
    fi

    # 防火墙放行
    if _has firewall-cmd && systemctl is-active firewalld &>/dev/null; then
        firewall-cmd --permanent --add-port="${new_port}/tcp"
        firewall-cmd --permanent --remove-port="${current_port}/tcp" 2>/dev/null
        firewall-cmd --reload
        _ok "firewalld 已放行端口 ${new_port}"
    elif _has ufw; then
        ufw allow "${new_port}/tcp"
        _ok "ufw 已放行端口 ${new_port}"
    fi

    # 重启 SSH
    if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
        _ok "SSH 端口已修改为 ${new_port}"
        _warn "请使用新端口重新连接: ssh -p ${new_port} user@host"
        _warn "当前连接不会断开，请验证新端口可用后再关闭此会话"
    else
        _err "SSH 重启失败，正在回滚..."
        cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
        systemctl restart sshd 2>/dev/null
    fi
}

_net_firewall() {
    _title "防火墙管理"
    if _has firewall-cmd && systemctl is-active firewalld &>/dev/null; then
        echo -e "  ${C_G}1)${C_0} 查看防火墙状态"
        echo -e "  ${C_G}2)${C_0} 开放端口"
        echo -e "  ${C_G}3)${C_0} 关闭端口"
        echo -e "  ${C_G}4)${C_0} 查看已开放端口"
        echo -e "  ${C_G}5)${C_0} 开启/关闭防火墙"
        echo -e "  ${C_G}0)${C_0} 返回"
        read -rp "选择 [0-5]: " fc
        case "$fc" in
            1) firewall-cmd --state; firewall-cmd --list-all ;;
            2) read -rp "端口 (如 8080/tcp): " p; firewall-cmd --permanent --add-port="$p" && firewall-cmd --reload && _ok "已开放 $p" ;;
            3) read -rp "端口: " p; firewall-cmd --permanent --remove-port="$p" && firewall-cmd --reload && _ok "已关闭 $p" ;;
            4) firewall-cmd --list-ports ;;
            5) read -rp "1=开启 2=关闭: " sw; [[ "$sw" == "1" ]] && { systemctl start firewalld; systemctl enable firewalld; _ok "已开启"; } || { systemctl stop firewalld; systemctl disable firewalld; _ok "已关闭"; } ;;
            0) return ;;
        esac
    elif _has ufw; then
        echo -e "  ${C_G}1)${C_0} 查看状态"
        echo -e "  ${C_G}2)${C_0} 开放端口"
        echo -e "  ${C_G}3)${C_0} 关闭端口"
        echo -e "  ${C_G}4)${C_0} 开启/关闭"
        echo -e "  ${C_G}0)${C_0} 返回"
        read -rp "选择 [0-4]: " fc
        case "$fc" in
            1) ufw status verbose ;;
            2) read -rp "端口 (如 8080): " p; ufw allow "$p" && _ok "已开放 $p" ;;
            3) read -rp "端口: " p; ufw deny "$p" && _ok "已关闭 $p" ;;
            4) read -rp "1=开启 2=关闭: " sw; [[ "$sw" == "1" ]] && { ufw enable; _ok "已开启"; } || { ufw disable; _ok "已关闭"; } ;;
            0) return ;;
        esac
    else
        _warn "未检测到 firewalld 或 ufw"
        _info "是否安装防火墙？(1=firewalld 2=ufw)"
        read -rp "选择: " fi
        case "$fi" in
            1) _pkg_install firewalld; systemctl start firewalld; systemctl enable firewalld; _ok "firewalld 已安装并启动" ;;
            2) _pkg_install ufw; ufw enable; _ok "ufw 已安装并启动" ;;
        esac
    fi
}

_net_mail() {
    _info "邮件服务检测"
    _line
    # 检测常见邮件服务
    local mail_services=("postfix" "sendmail" "exim4" "dovecot")
    local found=0
    for svc in "${mail_services[@]}"; do
        if systemctl is-active "$svc" &>/dev/null; then
            printf "  ${C_G}●${C_0} %-12s 运行中\n" "$svc"
            found=1
        elif _has "$svc"; then
            printf "  ${C_D}○${C_0} %-12s 已安装未运行\n" "$svc"
            found=1
        fi
    done
    [[ $found -eq 0 ]] && _info "未检测到邮件服务"

    echo ""
    _info "邮件端口检测"
    _line
    local ports=("25:SMTP" "465:SMTPS" "587:Submission" "110:POP3" "995:POP3S" "143:IMAP" "993:IMAPS")
    for entry in "${ports[@]}"; do
        local port="${entry%%:*}"
        local name="${entry##*:}"
        if ss -tlnp | grep -q ":${port} " ; then
            printf "  ${C_G}●${C_0} %-5s %-12s 监听中\n" "$port" "$name"
        else
            printf "  ${C_D}○${C_0} %-5s %-12s 未监听\n" "$port" "$name"
        fi
    done
    echo ""
    _info "MX 记录检测"
    _line
    if _has dig; then
        dig MX +short "$(hostname -d 2>/dev/null)" 2>/dev/null | head -5
    elif _has nslookup; then
        nslookup -type=mx "$(hostname -d 2>/dev/null)" 2>/dev/null | grep "mail exchanger"
    fi
}

_net_test() {
    _info "网络连通性测试"
    _line
    local targets=("223.5.5.5:国内" "8.8.8.8:国际" "mirrors.aliyun.com:镜像源" "github.com:GitHub" "tinytool.hayoko.cn:更新源")
    for entry in "${targets[@]}"; do
        local target="${entry%%:*}"
        local label="${entry##*:}"
        if ping -c2 -W2 "$target" &>/dev/null; then
            local delay
            # 兼容不同系统的 ping 输出格式 (rtt min/avg/max/mdev = x/x/x/x ms)
            delay=$(ping -c2 -W2 "$target" 2>/dev/null | tail -1 | grep -oE '[0-9.]+/[0-9.]+' | head -1 | cut -d/ -f2)
            printf "  ${C_G}√${C_0} %-25s %-8s 延迟 %sms\n" "$target" "[$label]" "${delay:-N/A}"
        else
            printf "  ${C_R}×${C_0} %-25s %-8s 不通\n" "$target" "[$label]"
        fi
    done
    echo ""
    _info "下载速度测试"
    _line
    # 使用多个备用 URL，取第一个成功的
    local speed http_code
    local test_urls=(
        "https://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-Official"
        "https://mirrors.cloud.tencent.com/centos/RPM-GPG-KEY-CentOS-Official"
        "https://mirrors.tuna.tsinghua.edu.cn/centos/RPM-GPG-KEY-CentOS-Official"
    )
    for url in "${test_urls[@]}"; do
        local result
        result=$(curl -o /dev/null -s -L -w '%{speed_download} %{http_code}' --max-time 8 --connect-timeout 4 "$url" 2>/dev/null)
        read -r speed http_code <<< "$result"
        if [[ "$http_code" =~ ^2 && "$speed" != "0.000" && -n "$speed" ]]; then
            break
        fi
    done
    if [[ -n "$speed" && "$speed" != "0.000" ]]; then
        local speed_mb
        speed_mb=$(awk "BEGIN{printf \"%.1f\", ${speed}/1048576}")
        local speed_kb
        speed_kb=$(awk "BEGIN{printf \"%.0f\", ${speed}/1024}")
        if (( $(awk "BEGIN{print (${speed_mb} < 1.0) ? 1 : 0}") )); then
            echo -e "  下载速度: ${C_W}${speed_kb} KB/s${C_0}"
        else
            echo -e "  下载速度: ${C_W}${speed_mb} MB/s${C_0}"
        fi
    else
        _warn "下载测试失败 (所有节点均不可达)"
    fi
}

_net_portscan() {
    read -rp "$(echo -e "${C_W}扫描本机端口范围 (如 1-1000，默认 1-1000): ${C_0}")" range
    range="${range:-1-1000}"
    local start="${range%-*}"
    local end="${range#*-}"
    _info "扫描本机 ${start}-${end} 端口..."
    _line
    if _has ss; then
        ss -tlnp | awk 'NR>1 {split($4,a,":"); print a[length(a)]}' | sort -n | while read -r p; do
            if [[ "$p" -ge "$start" && "$p" -le "$end" ]] 2>/dev/null; then
                local svc
                svc=$(grep "^[[:space:]]*$p/" /etc/services 2>/dev/null | head -1 | awk '{print $1}')
                printf "  ${C_G}●${C_0} %-6s %s\n" "$p" "${svc:-unknown}"
            fi
        done
    elif _has netstat; then
        netstat -tlnp | awk 'NR>2 {split($4,a,":"); print a[length(a)]}' | sort -n | while read -r p; do
            if [[ "$p" -ge "$start" && "$p" -le "$end" ]] 2>/dev/null; then
                printf "  ${C_G}●${C_0} %-6s\n" "$p"
            fi
        done
    fi
}

_net_speedtest() {
    _title "网络测速"
    echo -e "  ${C_G}1)${C_0} 综合带宽测速"
    echo -e "  ${C_G}2)${C_0} 热门网站测速"
    echo -e "  ${C_G}3)${C_0} 国内各节点延迟测试"
    echo -e "  ${C_G}0)${C_0} 返回"
    read -rp "$(echo -e "${C_W}选择 [0-3]: ${C_0}")" sc
    case "$sc" in
        1) _speedtest_bandwidth ;;
 2) _speedtest_sites ;; 3) _speedtest_latency ;; 0) return ;; esac
}

# ---------- 带宽测速 ----------
_speedtest_bandwidth() {
    _info "综合带宽测速"
    _line

    # 检查是否有 speedtest-cli
    if _has speedtest-cli; then
        _info "检测到 speedtest-cli，使用专业测速..."
        _confirm "使用 speedtest-cli 进行完整测速？(需 30-60 秒)" && {
            speedtest-cli --simple 2>/dev/null && return
        }
    fi

    # 如果没有 speedtest-cli 提示安装
    if ! _has speedtest-cli; then
        _info "安装 speedtest-cli 可获得更精准的测速结果"
        _confirm "是否安装 speedtest-cli？" && {
            _pkg_install python3-pip 2>/dev/null
            pip3 install speedtest-cli -q 2>/dev/null && _ok "安装成功" || _warn "安装失败"
            if _has speedtest-cli; then
                speedtest-cli --simple 2>/dev/null && return
            fi
        }
    fi

    # 内置测速：多节点下载
    _info "使用多节点下载测试带宽..."
    _line

    local nodes=(
        "阿里云镜像|https://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-Official"
        "腾讯云镜像|https://mirrors.cloud.tencent.com/centos/RPM-GPG-KEY-CentOS-Official"
        "华为云镜像|https://mirrors.huaweicloud.com/centos/RPM-GPG-KEY-CentOS-Official"
        "清华源|https://mirrors.tuna.tsinghua.edu.cn/centos/RPM-GPG-KEY-CentOS-Official"
        "中科大源|https://mirrors.ustc.edu.cn/centos/RPM-GPG-KEY-CentOS-Official"
    )

    local results=()

    for entry in "${nodes[@]}"; do
        local name="${entry%%|*}"
        local url="${entry##*|}"
        local size time_s http_code output
        # 使用 curl 测速，-L 跟随重定向
        output=$(curl -o /dev/null -s -L -w '%{size_download} %{time_total} %{http_code}' \
            --max-time 10 --connect-timeout 5 "$url" 2>/dev/null)
        read -r size time_s http_code <<< "$output"

        if [[ "$http_code" =~ ^2 && "$size" -gt 100 ]]; then
            # 计算平均下载速度 (bytes/s)
            local avg_speed_bps
            avg_speed_bps=$(awk "BEGIN{printf \"%.0f\", ${size}/${time_s}}")
            local speed_mb speed_kb
            speed_mb=$(awk "BEGIN{printf \"%.2f\", ${avg_speed_bps}/1048576}")
            speed_kb=$(awk "BEGIN{printf \"%.0f\", ${avg_speed_bps}/1024}")
            # 小于 1MB/s 显示 KB/s，否则显示 MB/s
            if (( $(awk "BEGIN{print (${speed_mb} < 1.0) ? 1 : 0}") )); then
                printf "  ${C_G}%-12s${C_0} 下载: ${C_W}%6s KB/s${C_0}  耗时: ${C_D}%ss${C_0}  大小: ${C_D}%s${C_0}\n" "$name" "$speed_kb" "${time_s}" "${size}B"
                results+=("${name}|${speed_mb}")
            else
                printf "  ${C_G}%-12s${C_0} 下载: ${C_W}%6s MB/s${C_0}  耗时: ${C_D}%ss${C_0}  大小: ${C_D}%s${C_0}\n" "$name" "$speed_mb" "${time_s}" "${size}B"
                results+=("${name}|${speed_mb}")
            fi
        else
            printf "  ${C_R}%-12s${C_0} 连接失败或文件无效 (HTTP %s)\n" "$name" "${http_code:-N/A}"
            results+=("${name}|失败")
        fi
    done

    # 计算平均速度
    echo ""
    local total=0 count=0
    for r in "${results[@]}"; do
        local s="${r##*|}"
        if [[ "$s" != "失败" ]]; then
            total=$(awk "BEGIN{print ${total}+${s}}")
            count=$((count + 1))
        fi
    done
    if [[ $count -gt 0 ]]; then
        local avg avg_kb
        avg=$(awk "BEGIN{printf \"%.2f\", ${total}/${count}}")
        avg_kb=$(awk "BEGIN{printf \"%.0f\", (${total}/${count})*1024}")
        if (( $(awk "BEGIN{print (${avg} < 1.0) ? 1 : 0}") )); then
            echo -e "  ${C_P}平均下载速度: ${C_W}${avg_kb} KB/s${C_0} (${count} 个节点)"
        else
            echo -e "  ${C_P}平均下载速度: ${C_W}${avg} MB/s${C_0} (${count} 个节点)"
        fi
    else
        _warn "所有节点测试失败，请检查网络"
    fi
}

# ---------- 热门网站测速 ----------
_speedtest_sites() {
    _title "热门网站测速"
    _line

    local sites=(
        "百度       |https://www.baidu.com"
        "淘宝       |https://www.taobao.com"
        "京东       |https://www.jd.com"
        "Bilibili   |https://www.bilibili.com"
        "知乎       |https://www.zhihu.com"
        "微博       |https://weibo.com"
        "GitHub     |https://github.com"
        "Google     |https://www.google.com"
        "YouTube    |https://www.youtube.com"
        "Cloudflare |https://www.cloudflare.com"
    )

    echo -e "  ${C_D}正在测试 ${#sites[@]} 个热门网站的 TCP 连接时间...${C_0}"
    echo ""
    printf "  ${C_D}%-12s${C_0}  %-8s  %-10s  %s\n" "网站" "状态" "响应时间" "TTFB"
    _line

    for entry in "${sites[@]}"; do
        local name="${entry%%|*}"
        local url="${entry##*|}"

        # curl -o /dev/null 测量 time_total (总时间) 和 time_starttransfer (TTFB)
        local result
        result=$(curl -o /dev/null -s -w '%{http_code} %{time_total} %{time_starttransfer}' \
            --max-time 8 --connect-timeout 4 -L "$url" 2>/dev/null)
        local http_code time_total ttfb
        read -r http_code time_total ttfb <<< "$result"

        if [[ "$http_code" =~ ^[23] ]]; then
            local ms_total ms_ttfb
            ms_total=$(awk "BEGIN{printf \"%.0f\", ${time_total}*1000}")
            ms_ttfb=$(awk "BEGIN{printf \"%.0f\", ${ttfb}*1000}")
            if [[ ${ms_total:-0} -lt 500 ]]; then
                printf "  ${C_G}%-12s${C_0}  %-8s  ${C_G}%-6s ms${C_0}  TTFB: %s ms\n" "$name" "$http_code" "$ms_total" "$ms_ttfb"
            elif [[ ${ms_total:-0} -lt 1500 ]]; then
                printf "  ${C_Y}%-12s${C_0}  %-8s  ${C_Y}%-6s ms${C_0}  TTFB: %s ms\n" "$name" "$http_code" "$ms_total" "$ms_ttfb"
            else
                printf "  ${C_R}%-12s${C_0}  %-8s  ${C_R}%-6s ms${C_0}  TTFB: %s ms\n" "$name" "$http_code" "$ms_total" "$ms_ttfb"
            fi
        else
            printf "  ${C_D}%-12s${C_0}  %-8s  超时/不可达\n" "$name" "${http_code:-N/A}"
        fi
    done
}

# ---------- 延迟测试 ----------
_speedtest_latency() {
    _title "国内各节点延迟测试"
    _line

    local nodes=(
        "北京电信|202.96.209.133"
        "上海电信|101.226.4.6"
        "广州电信|14.215.116.1"
        "北京联通|202.106.195.68"
        "上海联通|210.22.97.1"
        "广州联通|221.5.88.88"
        "北京移动|221.179.155.161"
        "上海移动|221.183.41.1"
        "广州移动|120.196.165.24"
        "成都电信|61.139.2.69"
        "武汉电信|202.103.24.12"
        "南京电信|221.131.143.69"
        "深圳联通|221.5.88.88"
        "阿里DNS|223.5.5.5"
        "腾讯DNS|119.29.29.29"
        "114DNS|114.114.114.114"
    )

    echo -e "  ${C_D}正在 ping ${#nodes[@]} 个节点 (各 3 次)...\n${C_0}"

    for entry in "${nodes[@]}"; do
        local name="${entry%%|*}"
        local ip="${entry##*|}"

        # ping 3 次取平均
        local ping_out
        ping_out=$(ping -c 3 -W 3 -q "$ip" 2>/dev/null)

        if [[ $? -eq 0 ]]; then
            local avg loss
            avg=$(echo "$ping_out" | grep -oP 'rtt min/avg/max/mdev = \K[0-9.]+' | head -1)
            loss=$(echo "$ping_out" | grep -oP '\d+(?=% packet loss)')
            loss="${loss:-0}"

            if [[ -n "$avg" ]]; then
                local ms
                ms=$(awk "BEGIN{printf \"%.1f\", ${avg}}")
                if (( $(awk "BEGIN{print ($ms < 30) ? 1 : 0}") )); then
                    printf "  ${C_G}%-14s${C_0} 延迟: ${C_G}%6s ms${C_0}  丢包: %s%%\n" "$name" "$ms" "$loss"
                elif (( $(awk "BEGIN{print ($ms < 80) ? 1 : 0}") )); then
                    printf "  ${C_Y}%-14s${C_0} 延迟: ${C_Y}%6s ms${C_0}  丢包: %s%%\n" "$name" "$ms" "$loss"
                else
                    printf "  ${C_R}%-14s${C_0} 延迟: ${C_R}%6s ms${C_0}  丢包: %s%%\n" "$name" "$ms" "$loss"
                fi
            else
                printf "  ${C_Y}%-14s${C_0} 延迟:     N/A ms  丢包: %s%%\n" "$name" "$loss"
            fi
        else
            printf "  ${C_D}%-14s${C_0} 不可达\n" "$name"
        fi
    done
}

_net_connections() {
    _info "当前网络连接"
    _line
    echo -e "${C_C}TCP 连接统计:${C_0}"
    if _has ss; then
        ss -s
        echo ""
        echo -e "${C_C}监听端口:${C_0}"
        ss -tlnp | head -30
        echo ""
        echo -e "${C_C}已建立连接 (前20):${C_0}"
        ss -tnp state established | head -20
    elif _has netstat; then
        netstat -tlnp | head -30
    fi
}

# ============================ 模块 7: SSH 管理 ===============================
m_ssh() {
    _title "SSH 管理 - 配置查看与安全加固"
    while true; do
        echo -e "  ${C_G}1)${C_0} 查看 SSH 配置"
        echo -e "  ${C_G}2)${C_0} SSH 安全加固 (一键)"
        echo -e "  ${C_G}3)${C_0} 禁止 root 密码登录"
        echo -e "  ${C_G}4)${C_0} 禁止密码登录 (仅密钥)"
        echo -e "  ${C_G}5)${C_0} 安装/配置密钥登录"
        echo -e "  ${C_G}6)${C_0} 查看 SSH 登录日志"
        echo -e "  ${C_G}7)${C_0} 安装 fail2ban 防爆破"
        echo -e "  ${C_G}8)${C_0} 恢复 SSH 默认配置"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-8]: ${C_0}")" choice
        case "$choice" in
            1) _ssh_view ;; 2) _ssh_harden ;;
            3) _ssh_disable_root ;; 4) _ssh_keyonly ;;
            5) _ssh_setup_key ;; 6) _ssh_logs ;;
            7) _ssh_fail2ban ;; 8) _ssh_restore ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_ssh_view() {
    _info "SSH 配置概览"
    _line
    local sshd_config="/etc/ssh/sshd_config"
    echo -e "  端口              : $(grep -m1 '^#\?Port ' $sshd_config | awk '{print $2}')"
    echo -e "  PermitRootLogin   : $(grep -m1 '^#\?PermitRootLogin ' $sshd_config | awk '{print $2}')"
    echo -e "  PasswordAuth      : $(grep -m1 '^#\?PasswordAuthentication ' $sshd_config | awk '{print $2}')"
    echo -e "  PubkeyAuth        : $(grep -m1 '^#\?PubkeyAuthentication ' $sshd_config | awk '{print $2}')"
    echo -e "  MaxAuthTries      : $(grep -m1 '^#\?MaxAuthTries ' $sshd_config | awk '{print $2}')"
    echo -e "  ClientAliveInterval: $(grep -m1 '^#\?ClientAliveInterval ' $sshd_config | awk '{print $2}')"
    echo -e "  PermitEmptyPasswd : $(grep -m1 '^#\?PermitEmptyPasswords ' $sshd_config | awk '{print $2}')"
    echo -e "  X11Forwarding     : $(grep -m1 '^#\?X11Forwarding ' $sshd_config | awk '{print $2}')"
    echo ""
    _info "SSH 服务状态"
    systemctl status sshd 2>/dev/null | head -10 || systemctl status ssh 2>/dev/null | head -10
}

_ssh_harden() {
    _title "SSH 安全加固"
    local sshd_config="/etc/ssh/sshd_config"
    _confirm "将执行以下安全加固:\n  - 禁止空密码登录\n  - 禁止 X11 转发\n  - 设置 MaxAuthTries=3\n  - 设置连接超时\n  - 使用强加密算法\n\n确认？" || return

    # 备份
    cp "$sshd_config" "${sshd_config}.bak_harden"

    _ssh_set "PermitEmptyPasswords" "no"
    _ssh_set "X11Forwarding" "no"
    _ssh_set "MaxAuthTries" "3"
    _ssh_set "ClientAliveInterval" "300"
    _ssh_set "ClientAliveCountMax" "2"
    _ssh_set "Protocol" "2"
    _ssh_set "LoginGraceTime" "30"
    _ssh_set "AllowTcpForwarding" "no"

    # 强加密算法
    if ! grep -q "^Ciphers " "$sshd_config"; then
        cat >> "$sshd_config" << 'EOF'
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
EOF
    fi

    # 验证配置
    if sshd -t 2>/dev/null; then
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
        _ok "SSH 安全加固完成并已重启"
    else
        _err "配置语法错误，正在回滚..."
        cp "${sshd_config}.bak_harden" "$sshd_config"
        systemctl restart sshd 2>/dev/null
    fi
}

# 通用 SSH 配置设置函数
_ssh_set() {
    local key=$1 val=$2
    local sshd_config="/etc/ssh/sshd_config"
    if grep -q "^${key} " "$sshd_config"; then
        sed -i "s/^${key} .*/${key} ${val}/" "$sshd_config"
    elif grep -q "^#${key} " "$sshd_config"; then
        sed -i "s/^#${key} .*/${key} ${val}/" "$sshd_config"
    else
        echo "${key} ${val}" >> "$sshd_config"
    fi
}

_ssh_disable_root() {
    _confirm "禁止 root 通过密码直接登录 (保留密钥登录)？" || return
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    _ssh_set "PermitRootLogin" "prohibit-password"
    if sshd -t 2>/dev/null; then
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
        _ok "已禁止 root 密码登录 (密钥仍可登录)"
        _warn "请确保已有密钥登录方式，否则可能无法以 root 登录"
    else
        _err "配置错误，已回滚"
        cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
    fi
}

_ssh_keyonly() {
    _confirm "禁止所有密码登录，仅允许密钥登录？\n请确保已配置密钥，否则将无法登录！" || return
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    _ssh_set "PasswordAuthentication" "no"
    _ssh_set "ChallengeResponseAuthentication" "no"
    _ssh_set "UsePAM" "no"
    if sshd -t 2>/dev/null; then
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
        _ok "已设置为仅密钥登录"
        _warn "请保持当前连接，用新终端验证密钥登录后再关闭"
    else
        _err "配置错误，已回滚"
        cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
    fi
}

_ssh_setup_key() {
    _title "配置密钥登录"
    echo -e "  ${C_G}1)${C_0} 生成新密钥对"
    echo -e "  ${C_G}2)${C_0} 导入公钥到服务器"
    echo -e "  ${C_G}0)${C_0} 返回"
    read -rp "选择 [0-2]: " kc
    case "$kc" in
        1)
            read -rp "密钥类型 (1=ed25519[推荐] 2=rsa): " kt
            local keyfile="${HOME}/.ssh/id_ed25519"
            mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
            if [[ "$kt" == "2" ]]; then
                keyfile="${HOME}/.ssh/id_rsa"
                ssh-keygen -t rsa -b 4096 -f "$keyfile"
            else
                ssh-keygen -t ed25519 -f "$keyfile"
            fi
            _ok "密钥已生成: ${keyfile}"
            echo -e "  ${C_D}公钥:${C_0}"
            cat "${keyfile}.pub"
            echo -e "\n  ${C_D}私钥 (请下载保存，不要泄露):${C_0}"
            _warn "私钥路径: ${keyfile}"
            ;;
        2)
            read -rp "粘贴公钥内容: " pubkey
            if [[ -n "$pubkey" ]]; then
                mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
                echo "$pubkey" >> "${HOME}/.ssh/authorized_keys"
                chmod 600 "${HOME}/.ssh/authorized_keys"
                _ok "公钥已添加"
            else
                _err "公钥内容为空"
            fi
            ;;
        0) return ;;
    esac
}

_ssh_logs() {
    _title "SSH 登录日志"
    echo -e "  ${C_G}1)${C_0} 最近成功登录"
    echo -e "  ${C_G}2)${C_0} 登录失败记录"
    echo -e "  ${C_G}3)${C_0} 当前在线用户"
    echo -e "  ${C_G}4)${C_0} 暴力破解统计"
    echo -e "  ${C_G}0)${C_0} 返回"
    read -rp "选择 [0-4]: " lc
    case "$lc" in
        1) _info "最近成功登录"; last -20 ;;
        2) _info "登录失败记录"; journalctl -u sshd --no-pager -n 50 2>/dev/null | grep -i "fail\|invalid\|error" | tail -20 || grep "Failed password" /var/log/auth.log 2>/dev/null | tail -20 ;;
        3) _info "当前在线用户"; w ;;
        4)
            _info "暴力破解 IP 统计 (Top 20)"
            _line
            journalctl -u sshd --no-pager 2>/dev/null | grep "Failed password" | grep -oE 'from [0-9.]+' | awk '{print $2}' | sort | uniq -c | sort -rn | head -20 \
            || grep "Failed password" /var/log/auth.log 2>/dev/null | grep -oE 'from [0-9.]+' | awk '{print $2}' | sort | uniq -c | sort -rn | head -20
            ;;
        0) return ;;
    esac
}

_ssh_fail2ban() {
    if _has fail2ban-client && systemctl is-active fail2ban &>/dev/null; then
        _info "fail2ban 已安装，状态:"
        fail2ban-client status sshd 2>/dev/null
        echo ""
        echo -e "  ${C_G}1)${C_0} 查看被封禁 IP"
        echo -e "  ${C_G}2)${C_0} 解封 IP"
        echo -e "  ${C_G}3)${C_0} 卸载 fail2ban"
        read -rp "选择 [1-3]: " fc
        case "$fc" in
            1) fail2ban-client status sshd ;;
            2) read -rp "要解封的 IP: " ip; fail2ban-client set sshd unbanip "$ip" && _ok "已解封 $ip" ;;
            3) _pkg_remove fail2ban && _ok "已卸载" ;;
        esac
        return
    fi

    _info "安装 fail2ban..."
    _pkg_install fail2ban
    # 配置
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
banaction = firewallcmd-ipset
backend = systemd

[sshd]
enabled = true
port = ssh
EOF
    # 检测 ufw 则改用
    if _has ufw; then
        sed -i 's/banaction = firewallcmd-ipset/banaction = ufw/' /etc/fail2ban/jail.local
    fi
    systemctl enable fail2ban
    systemctl restart fail2ban
    sleep 2
    if systemctl is-active fail2ban &>/dev/null; then
        _ok "fail2ban 安装成功"
        fail2ban-client status sshd 2>/dev/null
    else
        _err "fail2ban 启动失败，请检查日志"
    fi
}

_ssh_restore() {
    if [[ -f /etc/ssh/sshd_config.bak ]]; then
        _confirm "确认恢复 SSH 默认配置？" || return
        cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
        _ok "SSH 配置已恢复"
    else
        _err "未找到备份文件"
    fi
}

# ============================ 模块 8: 宝塔管理 ==============================
m_baota() {
    _title "宝塔管理 - 安装、密码、挂载数据盘"
    while true; do
        echo -e "  ${C_G}1)${C_0} 安装宝塔面板"
        echo -e " ${C_G}2)${C_0} 查看宝塔信息"
        echo -e "  ${C_G}3)${C_0} 重置宝塔密码"
        echo -e "  ${C_G}4)${C_0} 挂载数据盘到 /www"
        echo -e "  ${C_G}5)${C_0} 卸载宝塔面板"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-5]: ${C_0}")" choice
        case "$choice" in
            1) _baota_install ;; 2) _baota_info ;;
            3) _baota_password ;; 4) _baota_mount ;;
            5) _baota_uninstall ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_baota_install() {
    _confirm "将安装宝塔面板，过程可能需要 5-10 分钟，确认？" || return
    _info "正在安装宝塔面板..."
    if [[ "$SYS" == "centos" ]]; then
        curl -sSO https://download.bt.cn/install/install_panel.sh && bash install_panel.sh ed8484bec
    else
        curl -sSO https://download.bt.cn/install/install-ubuntu_6.0.sh && bash install-ubuntu_6.0.sh ed8484bec
    fi
    _ok "宝塔安装脚本执行完毕"
    _info "请查看上方输出获取面板登录信息"
}

_baota_info() {
    if [[ -f /etc/init.d/bt ]]; then
        _info "宝塔面板信息"
        /etc/init.d/bt default 2>/dev/null
        echo ""
        _info "面板状态"
        /etc/init.d/bt status 2>/dev/null
    elif _has bt; then
        bt default 2>/dev/null
    else
        _err "未检测到宝塔面板"
    fi
}

_baota_password() {
    if [[ ! -f /etc/init.d/bt ]] && ! _has bt; then
        _err "未检测到宝塔面板"
        return
    fi
    read -rp "$(echo -e "${C_W}输入新密码: ${C_0}")" newpass
    [[ -z "$newpass" ]] && return
    if _has bt; then
        echo "$newpass" | bt 5
    else
        cd /www/server/panel && python tools.py panel "$newpass"
    fi
    _ok "宝塔密码已重置为: $newpass"
}

_baota_mount() {
    _info "检测可挂载的数据盘..."
    _line
    # 列出未挂载或未挂到 /www 的磁盘
    local disks=()
    while read -r name size type mnt; do
        [[ "$type" != "disk" ]] && continue
        [[ "$name" == "loop"* ]] && continue
        [[ "$mnt" == "/www" ]] && continue
        disks+=("$name|$size|$mnt")
    done < <(lsblk -nlo NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null)

    # 排除系统盘
    local sys_disk
    sys_disk=$(lsblk -ndo PKNAME "$(df / --output=source | tail -1)" 2>/dev/null)
    local filtered=()
    for d in "${disks[@]}"; do
        local dn="${d%%|*}"
        [[ "$dn" == "$sys_disk" ]] && continue
        filtered+=("$d")
    done

    if [[ ${#filtered[@]} -eq 0 ]]; then
        _warn "未发现可挂载的数据盘"
        return
    fi

    echo -e "可用数据盘:"
    for i in "${!filtered[@]}"; do
        IFS='|' read -r name size mnt <<< "${filtered[$i]}"
        echo -e "  ${C_G}$((i+1)))${C_0} /dev/$name  ($size)  ${C_D}当前挂载: ${mnt:-未挂载}${C_0}"
    done
    echo ""
    read -rp "$(echo -e "${C_W}选择磁盘 [1-${#filtered[@]}]: ${C_0}")" sel
    local idx=$((sel - 1))
    if [[ $idx -lt 0 || $idx -ge ${#filtered[@]} ]]; then
        _err "无效选择"
        return
    fi

    IFS='|' read -r disk_name disk_size disk_mnt <<< "${filtered[$idx]}"
    local dev="/dev/$disk_name"

    if [[ "$disk_mnt" == "/" ]]; then
        _err "不能挂载系统盘到 /www"
        return
    fi

    _confirm "将 ${dev} 格式化并挂载到 /www，数据将被清除，确认？" || return

    # 如果已挂载到其他位置，先卸载
    if [[ -n "$disk_mnt" ]]; then
        umount "$dev" 2>/dev/null
        sed -i "\|${dev}|d" /etc/fstab
    fi

    # 格式化
    mkfs.ext4 -F "$dev"
    mkdir -p /www
    mount "$dev" /www

    # 持久化
    local uuid
    uuid=$(blkid -s UUID -o value "$dev")
    if [[ -n "$uuid" ]] && ! grep -q "$uuid" /etc/fstab; then
        echo "UUID=$uuid  /www  ext4  defaults,noatime  0 2" >> /etc/fstab
    fi

    _ok "数据盘已挂载到 /www"
    df -hT /www

    # 如果宝塔已安装，提示迁移
    if [[ -d /www/server/panel ]]; then
        _info "检测到宝塔已安装，数据盘已挂载到 /www"
        _ok "宝塔数据将直接使用新磁盘"
    fi
}

_baota_uninstall() {
    _confirm "确认卸载宝塔面板？此操作不可逆！" || return
    if _has bt; then
        bt stop 2>/dev/null
    fi
    if [[ -f /etc/init.d/bt ]]; then
        /etc/init.d/bt stop 2>/dev/null
    fi
    # 使用官方卸载脚本
    wget -O uninstall.sh https://download.bt.cn/install/bt-uninstall.sh 2>/dev/null && bash uninstall.sh
    rm -f uninstall.sh
    _ok "宝塔面板已卸载"
}

# ============================ 模块 9: Caddy 管理 ============================
m_caddy() {
    _title "Caddy 管理 - 安装、卸载、状态"
    while true; do
        echo -e "  ${C_G}1)${C_0} 安装 Caddy"
        echo -e "  ${C_G}2)${C_0} 查看状态"
        echo -e "  ${C_G}3)${C_0} 启动/停止/重启"
        echo -e "  ${C_G}4)${C_0} 编辑 Caddyfile"
        echo -e "  ${C_G}5)${C_0} 卸载 Caddy"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-5]: ${C_0}")" choice
        case "$choice" in
            1) _caddy_install ;; 2) _caddy_status ;;
            3) _caddy_control ;; 4) _caddy_edit ;;
            5) _caddy_uninstall ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_caddy_install() {
    if _has caddy; then
        _warn "Caddy 已安装: $(caddy version 2>/dev/null)"
        _confirm "是否重新安装？" || return
    fi

    _info "安装 Caddy..."
    # 安装依赖
    _pkg_install debian-keyring debian-archive-keyring apt-transport-https curl 2>/dev/null

    if [[ "$PM" == "apt" ]]; then
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
        apt-get update -qq
        apt-get install -y caddy
    elif [[ "$PM" == "dnf" ]] || [[ "$PM" == "yum" ]]; then
        _pkg_install copr-plugin 2>/dev/null
        dnf copr enable -y @caddy/caddy 2>/dev/null
        $PM install -y caddy
    fi

    if _has caddy; then
        systemctl enable caddy
        systemctl start caddy
        _ok "Caddy 安装完成"
        caddy version
        echo -e "  ${C_D}配置文件: /etc/caddy/Caddyfile${C_0}"
        echo -e "  ${C_D}网站目录: /var/www${C_0}"
    else
        _err "安装失败"
    fi
}

_caddy_status() {
    if ! _has caddy; then
        _err "Caddy 未安装"
        return
    fi
    _info "Caddy 状态"
    systemctl status caddy --no-pager | head -15
    echo ""
    _info "Caddy 版本"
    caddy version 2>/dev/null
    echo ""
    _info "Caddyfile 配置"
    _line
    [[ -f /etc/caddy/Caddyfile ]] && cat /etc/caddy/Caddyfile || _warn "Caddyfile 不存在"
}

_caddy_control() {
    if ! _has caddy; then
        _err "Caddy 未安装"
        return
    fi
    echo -e "  ${C_G}1)${C_0} 启动  ${C_G}2)${C_0} 停止  ${C_G}3)${C_0} 重启  ${C_G}4)${C_0} 重载配置"
    read -rp "选择 [1-4]: " cc
    case "$cc" in
        1) systemctl start caddy && _ok "Caddy 已启动" ;;
        2) systemctl stop caddy && _ok "Caddy 已停止" ;;
        3) systemctl restart caddy && _ok "Caddy 已重启" ;;
        4) systemctl reload caddy && _ok "配置已重载" ;;
    esac
}

_caddy_edit() {
    local caddyfile="/etc/caddy/Caddyfile"
    if [[ ! -f "$caddyfile" ]]; then
        mkdir -p /etc/caddy
        cat > "$caddyfile" << 'EOF'
# Caddyfile 示例配置
# yourdomain.com {
#     root * /var/www/html
#     file_server
#     # 自动 HTTPS
# }
EOF
        _info "已创建默认 Caddyfile"
    fi
    echo -e "  ${C_D}当前 Caddyfile 内容:${C_0}"
    cat "$caddyfile"
    echo ""
    if _confirm "是否编辑 Caddyfile？"; then
        local editor=""
        _has nano && editor="nano"
        _has vim && editor="vim"
        _has vi && editor="vi"
        if [[ -n "$editor" ]]; then
            $editor "$caddyfile"
            caddy validate --config "$caddyfile" 2>/dev/null && _ok "配置有效" || _warn "配置可能有问题"
        else
            _warn "未找到编辑器 (nano/vim)，安装中..."
            _pkg_install nano && nano "$caddyfile"
        fi
    fi
}

_caddy_uninstall() {
    if ! _has caddy; then
        _err "Caddy 未安装"
        return
    fi
    _confirm "确认卸载 Caddy？" || return
    systemctl stop caddy 2>/dev/null
    systemctl disable caddy 2>/dev/null
    if [[ "$PM" == "apt" ]]; then
        apt-get remove --purge -y caddy
        rm -f /etc/apt/sources.list.d/caddy-stable.list
        rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    else
        $PM remove -y caddy
    fi
    rm -rf /etc/caddy
    _ok "Caddy 已卸载"
}

# ============================ 模块 10: Docker 管理 ==========================
m_docker() {
    _title "Docker 管理 - 安装、迁移、清理"
    while true; do
        echo -e "  ${C_G}1)${C_0} 安装 Docker"
        echo -e "  ${C_G}2)${C_0} 查看 Docker 状态"
        echo -e "  ${C_G}3)${C_0} 迁移 Docker 数据目录"
        echo -e "  ${C_G}4)${C_0} 清理 Docker (镜像/容器/卷)"
        echo -e "  ${C_G}5)${C_0} Docker Compose 管理"
        echo -e "  ${C_G}6)${C_0} 卸载 Docker"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-6]: ${C_0}")" choice
        case "$choice" in
            1) _docker_install ;; 2) _docker_status ;;
            3) _docker_migrate ;; 4) _docker_clean ;;
            5) _docker_compose ;; 6) _docker_uninstall ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_docker_install() {
    if _has docker; then
        _warn "Docker 已安装: $(docker --version)"
        _confirm "是否重新安装/更新？" || return
    fi

    _info "安装 Docker (官方脚本)..."
    # 使用国内镜像加速的官方安装脚本
    curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun

    if _has docker; then
        systemctl enable docker
        systemctl start docker
        _ok "Docker 安装完成"

        # 配置国内镜像加速
        _info "配置镜像加速器..."
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << 'EOF'
{
    "registry-mirrors": [
        "https://docker.1ms.run",
        "https://docker.xuanyuan.me"
    ],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
EOF
        systemctl daemon-reload
        systemctl restart docker

        # 验证
        docker version 2>/dev/null
        echo ""
        docker run --rm hello-world 2>/dev/null && _ok "Docker 运行正常" || _warn "测试运行失败，请检查"

        # 安装 compose 插件
        _info "安装 Docker Compose 插件..."
        if [[ "$PM" == "apt" ]]; then
            apt-get install -y docker-compose-plugin 2>/dev/null
        else
            $PM install -y docker-compose-plugin 2>/dev/null
        fi
        docker compose version 2>/dev/null && _ok "Compose 已安装"
    else
        _err "Docker 安装失败"
    fi
}

_docker_status() {
    if ! _has docker; then
        _err "Docker 未安装"
        return
    fi
    _info "Docker 版本"
    docker version 2>/dev/null
    echo ""
    _info "Docker 系统信息"
    docker info 2>/dev/null | head -30
    echo ""
    _info "容器列表"
    docker ps -a 2>/dev/null
    echo ""
    _info "镜像列表"
    docker images 2>/dev/null
    echo ""
    _info "磁盘使用"
    docker system df 2>/dev/null
}

_docker_migrate() {
    if ! _has docker; then
        _err "Docker 未安装"
        return
    fi

    local default_dir="/var/lib/docker"
    local cur_dir
    cur_dir=$(docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $NF}')
    echo -e "  当前数据目录: ${C_W}${cur_dir}${C_0}"
    echo -e "  默认目录: ${C_D}${default_dir}${C_0}"
    echo ""
    read -rp "$(echo -e "${C_W}迁移目标目录 (如 /data/docker): ${C_0}")" new_dir
    [[ -z "$new_dir" ]] && return

    if [[ "$new_dir" == "$cur_dir" ]]; then
        _warn "目标目录与当前目录相同"
        return
    fi

    _confirm "将停止 Docker 服务并迁移数据到 ${new_dir}，确认？" || return

    _info "停止 Docker..."
    systemctl stop docker
    systemctl stop docker.socket 2>/dev/null

    # 创建目标目录
    mkdir -p "$new_dir"

    # 复制数据
    _info "迁移数据 (可能耗时较长)..."
    if _has rsync; then
        rsync -aP "$cur_dir/" "$new_dir/"
    else
        cp -rp "$cur_dir"/* "$new_dir/"
    fi

    # 备份原目录
    _info "备份原目录..."
    mv "$cur_dir" "${cur_dir}.bak"

    # 配置 Docker 使用新目录
    mkdir -p /etc/docker
    if [[ -f /etc/docker/daemon.json ]]; then
        # 如果已有 daemon.json，添加 data-root
        if grep -q "data-root" /etc/docker/daemon.json; then
            sed -i "s|\"data-root\".*|\"data-root\": \"${new_dir}\"|" /etc/docker/daemon.json
        else
            sed -i "1s/{/{\n    \"data-root\": \"${new_dir}\",/" /etc/docker/daemon.json
        fi
    else
        cat > /etc/docker/daemon.json << EOF
{
    "data-root": "${new_dir}",
    "registry-mirrors": [
        "https://docker.1ms.run",
        "https://docker.xuanyuan.me"
    ],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
EOF
    fi

    # 启动 Docker
    systemctl daemon-reload
    systemctl start docker

    sleep 3
    if docker info &>/dev/null; then
        local check_dir
        check_dir=$(docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $NF}')
        if [[ "$check_dir" == "$new_dir" ]]; then
            _ok "Docker 数据已迁移到 ${new_dir}"
            _info "确认无误后可删除备份: rm -rf ${cur_dir}.bak"
        else
            _err "迁移验证失败，当前目录: ${check_dir}"
        fi
    else
        _err "Docker 启动失败，正在回滚..."
        rm -f /etc/docker/daemon.json
        mv "${cur_dir}.bak" "$cur_dir"
        systemctl start docker
    fi
}

_docker_clean() {
    if ! _has docker; then
        _err "Docker 未安装"
        return
    fi
    _info "Docker 清理前:"
    docker system df 2>/dev/null
    echo ""
    echo -e "  ${C_G}1)${C_0} 清理已停止的容器"
    echo -e "  ${C_G}2)${C_0} 清理悬空镜像 (dangling)"
    echo -e "  ${C_G}3)${C_0} 清理未使用的镜像"
    echo -e "  ${C_G}4)${C_0} 清理未使用的卷"
    echo -e "  ${C_G}5)${C_0} 一键全量清理 (谨慎)"
    echo -e "  ${C_G}0)${C_0} 返回"
    read -rp "选择 [0-5]: " cc
    case "$cc" in
        1) docker container prune -f && _ok "已清理停止的容器" ;;
        2) docker image prune -f && _ok "已清理悬空镜像" ;;
        3) _confirm "将删除所有未被使用的镜像，确认？" && docker image prune -a -f && _ok "已清理未使用镜像" ;;
        4) _confirm "将删除所有未被使用的卷，确认？" && docker volume prune -f && _ok "已清理未使用卷" ;;
        5) _confirm "⚠ 将删除所有未使用的容器、镜像、网络、缓存！确认？" && docker system prune -a --volumes -f && _ok "全量清理完成" ;;
        0) return ;;
    esac
    echo ""
    _info "Docker 清理后:"
    docker system df 2>/dev/null
}

_docker_compose() {
    if ! _has docker; then
        _err "Docker 未安装"
        return
    fi
    if docker compose version &>/dev/null; then
        _ok "Docker Compose 已安装: $(docker compose version)"
    else
        _info "安装 Docker Compose 插件..."
        if [[ "$PM" == "apt" ]]; then
            apt-get install -y docker-compose-plugin
        else
            $PM install -y docker-compose-plugin
        fi
        docker compose version 2>/dev/null && _ok "安装成功" || _err "安装失败"
        return
    fi
    echo ""
    echo -e "  ${C_G}1)${C_0} 查看 compose 项目"
    echo -e "  ${C_G}2)${C_0} 安装独立版 compose v2"
    echo -e "  ${C_G}0)${C_0} 返回"
    read -rp "选择 [0-2]: " cc
    case "$cc" in
        1) docker compose ls -a 2>/dev/null ;;
        2)
            _info "安装独立版 docker-compose..."
            local compose_url
            local compose_ver
            compose_ver=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | grep -oE '[0-9.]+')
            compose_url="https://github.com/docker/compose/releases/download/v${compose_ver}/docker-compose-linux-${ARCH//x86_64/x86_64}"
            curl -L "$compose_url" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            docker-compose version 2>/dev/null && _ok "独立版 compose 安装成功"
            ;;
    esac
}

_docker_uninstall() {
    if ! _has docker; then
        _err "Docker 未安装"
        return
    fi
    _confirm "确认卸载 Docker？所有容器将停止，镜像将删除！" || return
    systemctl stop docker
    systemctl stop docker.socket 2>/dev/null

    if [[ "$PM" == "apt" ]]; then
        apt-get remove --purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras 2>/dev/null
        apt-get autoremove -y
    else
        $PM remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null
    fi

    # 清理残留
    read -rp "是否删除所有 Docker 数据 (镜像/容器/卷)？[y/N]: " del
    if [[ "$del" =~ ^[Yy]$ ]]; then
        rm -rf /var/lib/docker
        rm -rf /var/lib/containerd
        rm -f /etc/docker/daemon.json
        _ok "Docker 数据已清理"
    fi
    _ok "Docker 已卸载"
}

# 卸载软件包辅助函数
_pkg_remove() {
    if [[ "$PM" == "apt" ]]; then
        apt-get remove --purge -y "$@"
    elif [[ "$PM" == "dnf" ]]; then
        dnf remove -y "$@"
    else
        yum remove -y "$@"
    fi
}

# ============================ 模块 11: 进程监控 =============================
m_process() {
    _title "进程监控 - 实时进程查看与管理"
    while true; do
        echo -e "  ${C_G}1)${C_0} 实时进程 TOP 20 (CPU)"
        echo -e "  ${C_G}2)${C_0} 实时进程 TOP 20 (内存)"
        echo -e "  ${C_G}3)${C_0} 按名称查找进程"
        echo -e "  ${C_G}4)${C_0} 按端口查找进程"
        echo -e "  ${C_G}5)${C_0} 结束进程 (kill)"
        echo -e "  ${C_G}6)${C_0} 结束进程 (kill -9)"
        echo -e "  ${C_G}7)${C_0} 查看进程树"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-7]: ${C_0}")" choice
        case "$choice" in
            1) _proc_top_cpu ;; 2) _proc_top_mem ;;
            3) _proc_find_name ;; 4) _proc_find_port ;;
            5) _proc_kill ;; 6) _proc_kill9 ;;
            7) _proc_tree ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_proc_top_cpu() {
    _info "CPU 占用 TOP 20"
    _line
    ps -eo pid,ppid,cmd,pcpu,pmem,etime --sort=-%cpu | head -21
}

_proc_top_mem() {
    _info "内存占用 TOP 20"
    _line
    ps -eo pid,ppid,cmd,pmem,pcpu,etime --sort=-%mem | head -21
}

_proc_find_name() {
    read -rp "$(echo -e "${C_W}进程名称 (部分匹配): ${C_0}")" name
    [[ -z "$name" ]] && return
    _info "查找包含 '${name}' 的进程"
    _line
    ps -eo pid,ppid,cmd,pcpu,pmem,etime | grep -i "$name" | grep -v grep || _warn "未找到进程"
}

_proc_find_port() {
    read -rp "$(echo -e "${C_W}端口号: ${C_0}")" port
    [[ -z "$port" ]] && return
    _info "查找监听端口 ${port} 的进程"
    _line
    if _has ss; then
        ss -tlnp | grep ":${port} " || _warn "未找到监听该端口的进程"
    elif _has lsof; then
        lsof -i ":${port}" || _warn "未找到监听该端口的进程"
    else
        netstat -tlnp 2>/dev/null | grep ":${port} " || _warn "未找到监听该端口的进程"
    fi
}

_proc_kill() {
    read -rp "$(echo -e "${C_W}输入 PID: ${C_0}")" pid
    [[ -z "$pid" ]] && return
    if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
        _err "无效的 PID"
        return
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
        _err "进程 ${pid} 不存在"
        return
    fi
    _confirm "确认结束进程 ${pid}？" || return
    kill "$pid" && _ok "进程 ${pid} 已结束" || _err "结束失败"
}

_proc_kill9() {
    read -rp "$(echo -e "${C_W}输入 PID: ${C_0}")" pid
    [[ -z "$pid" ]] && return
    if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
        _err "无效的 PID"
        return
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
        _err "进程 ${pid} 不存在"
        return
    fi
    _confirm "⚠ 强制结束进程 ${pid} (kill -9)，可能导致数据丢失！" || return
    kill -9 "$pid" && _ok "进程 ${pid} 已强制结束" || _err "结束失败"
}

_proc_tree() {
    if _has pstree; then
        pstree -p | head -60
    elif _has ps; then
        ps -ejH | head -60
    else
        _err "未找到 pstree 或 ps"
    fi
}

# ============================ 模块 12: 日志工具 =============================
m_logs() {
    _title "日志工具 - 系统日志快速查看"
    while true; do
        echo -e "  ${C_G}1)${C_0} 查看系统日志 (journalctl)"
        echo -e "  ${C_G}2)${C_0} 查看认证日志 (SSH/login)"
        echo -e "  ${C_G}3)${C_0} 查看 Nginx/Apache 日志"
        echo -e "  ${C_G}4)${C_0} 查看 dmesg 内核日志"
        echo -e "  ${C_G}5)${C_0} 查看最近启动日志"
        echo -e "  ${C_G}6)${C_0} 日志关键词搜索"
        echo -e "  ${C_G}7)${C_0} 清空日志文件"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-7]: ${C_0}")" choice
        case "$choice" in
            1) _log_journal ;; 2) _log_auth ;;
            3) _log_web ;; 4) _log_dmesg ;;
            5) _log_boot ;; 6) _log_search ;;
            7) _log_clear ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_log_journal() {
    if _has journalctl; then
        _info "最近 50 条系统日志"
        _line
        journalctl --no-pager -n 50 2>/dev/null | tail -40
        echo ""
        echo -e "  ${C_D}提示: 指定服务日志请输入服务名${C_0}"
        read -rp "$(echo -e "${C_W}查看特定服务日志 (如 nginx, sshd, 回车跳过): ${C_0}")" svc
        if [[ -n "$svc" ]]; then
            journalctl -u "$svc" --no-pager -n 30 2>/dev/null || _warn "未找到服务 ${svc}"
        fi
    else
        _warn "未安装 systemd-journald，尝试读取 syslog..."
        tail -n 50 /var/log/syslog 2>/dev/null || tail -n 50 /var/log/messages 2>/dev/null || _err "未找到系统日志"
    fi
}

_log_auth() {
    _info "认证日志 (SSH 登录/失败)"
    _line
    if _has journalctl; then
        journalctl -u sshd --no-pager -n 50 2>/dev/null || journalctl -u ssh --no-pager -n 50 2>/dev/null
    else
        tail -n 50 /var/log/auth.log 2>/dev/null || tail -n 50 /var/log/secure 2>/dev/null
    fi
}

_log_web() {
    _info "Web 服务器日志"
    _line
    if [[ -d /var/log/nginx ]]; then
        echo -e "${C_C}Nginx 访问日志 (最近 20 条):${C_0}"
        tail -n 20 /var/log/nginx/access.log 2>/dev/null
        echo ""
        echo -e "${C_C}Nginx 错误日志 (最近 20 条):${C_0}"
        tail -n 20 /var/log/nginx/error.log 2>/dev/null
    elif [[ -d /var/log/apache2 ]]; then
        echo -e "${C_C}Apache 访问日志 (最近 20 条):${C_0}"
        tail -n 20 /var/log/apache2/access.log 2>/dev/null
        echo ""
        echo -e "${C_C}Apache 错误日志 (最近 20 条):${C_0}"
        tail -n 20 /var/log/apache2/error.log 2>/dev/null
    elif [[ -d /var/log/httpd ]]; then
        echo -e "${C_C}Apache 访问日志 (最近 20 条):${C_0}"
        tail -n 20 /var/log/httpd/access_log 2>/dev/null
        echo ""
        echo -e "${C_C}Apache 错误日志 (最近 20 条):${C_0}"
        tail -n 20 /var/log/httpd/error_log 2>/dev/null
    else
        _warn "未检测到 Nginx/Apache 日志目录"
    fi
}

_log_dmesg() {
    _info "内核 dmesg 日志"
    _line
    dmesg -T 2>/dev/null | tail -50 || dmesg | tail -50
}

_log_boot() {
    if _has journalctl; then
        _info "启动日志"
        journalctl -b --no-pager | tail -50
    else
        _warn "当前系统不支持 journalctl 启动日志"
    fi
}

_log_search() {
    read -rp "$(echo -e "${C_W}搜索关键词: ${C_0}")" kw
    [[ -z "$kw" ]] && return
    _info "在系统日志中搜索 '${kw}'"
    _line
    if _has journalctl; then
        journalctl --no-pager -g "$kw" 2>/dev/null | tail -30 || journalctl --no-pager | grep -i "$kw" | tail -30
    else
        grep -ri "$kw" /var/log/syslog /var/log/messages /var/log/auth.log /var/log/secure 2>/dev/null | tail -30
    fi
}

_log_clear() {
    _warn "此操作将清空日志文件，数据不可恢复！"
    _confirm "确认清空日志？" || return
    # 安全清空方式（保留文件）
    for f in /var/log/syslog /var/log/messages /var/log/auth.log /var/log/secure \
             /var/log/nginx/access.log /var/log/nginx/error.log \
             /var/log/apache2/access.log /var/log/apache2/error.log \
             /var/log/httpd/access_log /var/log/httpd/error_log; do
        [[ -f "$f" ]] && : > "$f"
    done
    # journalctl
    if _has journalctl; then
        journalctl --vacuum-size=1M 2>/dev/null || journalctl --vacuum-time=1s 2>/dev/null
    fi
    _ok "日志已清空"
}

# ============================ 模块 13: 定时任务 =============================
m_cron() {
    _title "定时任务 - Crontab 管理"
    while true; do
        echo -e "  ${C_G}1)${C_0} 查看当前定时任务"
        echo -e "  ${C_G}2)${C_0} 新增定时任务"
        echo -e "  ${C_G}3)${C_0} 删除定时任务"
        echo -e "  ${C_G}4)${C_0} 编辑 crontab (高级)"
        echo -e "  ${C_G}5)${C_0} 查看 cron 服务状态"
        echo -e "  ${C_G}6)${C_0} 常用任务模板"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-6]: ${C_0}")" choice
        case "$choice" in
            1) _cron_list ;; 2) _cron_add ;;
            3) _cron_del ;; 4) _cron_edit ;;
            5) _cron_status ;; 6) _cron_templates ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_cron_list() {
    _info "当前用户的定时任务"
    _line
    crontab -l 2>/dev/null || _info "暂无定时任务"
    echo ""
    _info "系统级定时任务 (/etc/crontab)"
    _line
    [[ -f /etc/crontab ]] && cat /etc/crontab 2>/dev/null | grep -v "^#" | grep -v "^$" || _info "无"
}

_cron_add() {
    _info "新增定时任务"
    _line
    echo -e "  ${C_D}Cron 格式: 分 时 日 月 周 命令${C_0}"
    echo -e "  ${C_D}示例: 0 2 * * * /path/to/backup.sh${C_0}"
    echo ""
    read -rp "$(echo -e "${C_W}分钟 (0-59, *): ${C_0}")" m
    read -rp "$(echo -e "${C_W}小时 (0-23, *): ${C_0}")" h
    read -rp "$(echo -e "${C_W}日期 (1-31, *): ${C_0}")" dom
    read -rp "$(echo -e "${C_W}月份 (1-12, *): ${C_0}")" mon
    read -rp "$(echo -e "${C_W}星期 (0-7, *): ${C_0}")" dow
    read -rp "$(echo -e "${C_W}执行的命令: ${C_0}")" cmd

    [[ -z "$cmd" ]] && { _err "命令不能为空"; return; }
    m="${m:-*}"; h="${h:-*}"; dom="${dom:-*}"; mon="${mon:-*}"; dow="${dow:-*}"
    local entry="${m} ${h} ${dom} ${mon} ${dow} ${cmd}"

    # 验证
    if ! _confirm "确认添加: ${entry} ？"; then
        return
    fi

    # 安全追加
    (crontab -l 2>/dev/null; echo "$entry") | crontab -
    _ok "定时任务已添加"
    echo ""
    _info "当前任务列表:"
    crontab -l 2>/dev/null
}

_cron_del() {
    local current
    current=$(crontab -l 2>/dev/null)
    if [[ -z "$current" ]]; then
        _info "当前没有定时任务"
        return
    fi
    _info "当前定时任务:"
    _line
    local tasks=()
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        tasks+=("$line")
    done <<< "$current"

    if [[ ${#tasks[@]} -eq 0 ]]; then
        _info "没有可删除的任务"
        return
    fi

    for i in "${!tasks[@]}"; do
        printf "  ${C_G}%d)${C_0} %s\n" "$((i+1))" "${tasks[$i]}"
    done
    echo ""
    read -rp "$(echo -e "${C_W}选择要删除的任务编号 (0=取消): ${C_0}")" idx
    [[ "$idx" == "0" ]] && return
    local del_idx=$((idx - 1))
    if [[ $del_idx -lt 0 || $del_idx -ge ${#tasks[@]} ]]; then
        _err "无效编号"
        return
    fi

    # 重建 crontab，跳过要删除的
    local new_tasks=""
    for i in "${!tasks[@]}"; do
        if [[ $i -ne $del_idx ]]; then
            new_tasks+="${tasks[$i]}\n"
        fi
    done
    printf "%b" "$new_tasks" | crontab -
    _ok "任务已删除"
}

_cron_edit() {
    _info "打开 crontab 编辑器..."
    local editor=""
    _has nano && editor="nano"
    _has vim && editor="vim"
    _has vi && editor="vi"
    if [[ -n "$editor" ]]; then
        EDITOR="$editor" crontab -e
    else
        _warn "未找到编辑器，安装 nano..."
        _pkg_install nano && EDITOR=nano crontab -e
    fi
}

_cron_status() {
    _info "Cron 服务状态"
    _line
    local svc=""
    if systemctl list-unit-files 2>/dev/null | grep -q "^crond"; then
        svc="crond"
    elif systemctl list-unit-files 2>/dev/null | grep -q "^cron"; then
        svc="cron"
    fi
    if [[ -n "$svc" ]]; then
        systemctl status "$svc" --no-pager | head -10
        echo ""
        systemctl is-enabled "$svc" 2>/dev/null && _ok "已设置为开机启动" || _warn "未设置为开机启动"
    else
        _warn "未检测到 cron 服务"
    fi
}

_cron_templates() {
    _info "常用定时任务模板"
    _line
    echo -e "  ${C_D}复制以下整行到 crontab 即可${C_0}"
    echo ""
    echo -e "  ${C_C}# 每天凌晨 2 点执行备份${C_0}"
    echo -e "  0 2 * * * /path/to/backup.sh"
    echo ""
    echo -e "  ${C_C}# 每 5 分钟检查服务状态${C_0}"
    echo -e "  */5 * * * * /path/to/check.sh"
    echo ""
    echo -e "  ${C_C}# 每周日 3:30 清理日志${C_0}"
    echo -e "  30 3 * * 0 /path/to/clean.sh"
    echo ""
    echo -e "  ${C_C}# 每月 1 号 0:00 执行${C_0}"
    echo -e "  0 0 1 * * /path/to/monthly.sh"
    echo ""
    echo -e "  ${C_C}# 每 10 分钟同步时间${C_0}"
    echo -e "  */10 * * * * /usr/sbin/ntpdate -u pool.ntp.org"
    echo ""
    echo -e "  ${C_C}# 每天重启服务${C_0}"
    echo -e "  0 4 * * * systemctl restart nginx"
}

# ============================ 模块 14: 配置导出 =============================
m_export() {
    _title "配置导出 - 系统配置一键导出"
    local out_dir="/tmp/tinytool_export_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$out_dir"

    _info "正在导出系统配置到 ${out_dir}..."
    _line

    # 1. 系统信息
    _info "导出系统信息..."
    {
        echo "主机名: $(hostname)"
        echo "系统: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
        echo "内核: $(uname -r)"
        echo "架构: $(uname -m)"
        echo "时间: $(date)"
        echo "运行时间: $(uptime -p 2>/dev/null)"
    } > "${out_dir}/system_info.txt"

    # 2. 网络配置
    _info "导出网络配置..."
    ip addr 2>/dev/null > "${out_dir}/network_interfaces.txt"
    ip route 2>/dev/null > "${out_dir}/network_routes.txt"
    cat /etc/resolv.conf 2>/dev/null > "${out_dir}/dns_config.txt"
    [[ -f /etc/netplan/00-installer-config.yaml ]] && cp /etc/netplan/*.yaml "${out_dir}/" 2>/dev/null
    [[ -f /etc/sysconfig/network-scripts/ifcfg-eth0 ]] && cp /etc/sysconfig/network-scripts/ifcfg-* "${out_dir}/" 2>/dev/null

    # 3. SSH 配置
    _info "导出 SSH 配置..."
    cp /etc/ssh/sshd_config "${out_dir}/sshd_config" 2>/dev/null
    cat /etc/ssh/ssh_config 2>/dev/null > "${out_dir}/ssh_config.txt"

    # 4. 防火墙配置
    _info "导出防火墙配置..."
    if _has firewall-cmd; then
        firewall-cmd --list-all 2>/dev/null > "${out_dir}/firewall_cmd.txt"
    fi
    if _has ufw; then
        ufw status verbose 2>/dev/null > "${out_dir}/ufw_status.txt"
    fi
    iptables -L -n -v 2>/dev/null > "${out_dir}/iptables.txt"

    # 5. 定时任务
    _info "导出定时任务..."
    crontab -l 2>/dev/null > "${out_dir}/crontab.txt"
    cat /etc/crontab 2>/dev/null > "${out_dir}/crontab_system.txt"

    # 6. 磁盘与挂载
    _info "导出磁盘配置..."
    df -h > "${out_dir}/disk_usage.txt"
    lsblk > "${out_dir}/lsblk.txt"
    cat /etc/fstab > "${out_dir}/fstab.txt"

    # 7. 已安装软件包列表
    _info "导出软件包列表..."
    if [[ "$PM" == "apt" ]]; then
        dpkg -l > "${out_dir}/packages.txt" 2>/dev/null
    else
        rpm -qa > "${out_dir}/packages.txt" 2>/dev/null
    fi

    # 8. 服务列表
    _info "导出服务列表..."
    systemctl list-units --type=service --state=running --no-pager 2>/dev/null > "${out_dir}/running_services.txt"
    systemctl list-unit-files --type=service --state=enabled --no-pager 2>/dev/null > "${out_dir}/enabled_services.txt"

    # 9. 环境变量
    env 2>/dev/null > "${out_dir}/env.txt"

    # 打包
    local tar_file="${out_dir}.tar.gz"
    tar -czf "$tar_file" -C "$(dirname "$out_dir")" "$(basename "$out_dir")" 2>/dev/null

    echo ""
    _ok "系统配置导出完成！"
    echo ""
    echo -e "  ${C_C}导出目录:${C_0} ${out_dir}"
    echo -e "  ${C_C}压缩包  :${C_0} ${tar_file}"
    echo ""
    _info "导出的文件列表:"
    ls -lh "$out_dir" 2>/dev/null | tail -n +2
    echo ""
    _info "压缩包大小:"
    ls -lh "$tar_file" 2>/dev/null | awk '{print $5, $9}'
    echo ""
    _warn "请下载以下文件后妥善保管: ${tar_file}"
}

# ============================ 模块 15: 1Panel 管理 ============================
m_1panel() {
    _title "1Panel 管理 - 安装、信息、密码、卸载"
    while true; do
        echo -e "  ${C_G}1)${C_0} 安装 1Panel"
        echo -e "  ${C_G}2)${C_0} 查看面板信息"
        echo -e "  ${C_G}3)${C_0} 重置密码"
        echo -e "  ${C_G}4)${C_0} 修改端口"
        echo -e "  ${C_G}5)${C_0} 查看 1Panel 状态"
        echo -e "  ${C_G}6)${C_0} 重启 1Panel"
        echo -e "  ${C_G}7)${C_0} 挂载数据盘到 1Panel"
        echo -e "  ${C_G}8)${C_0} 卸载 1Panel"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-8]: ${C_0}")" choice
        case "$choice" in
            1) _1panel_install ;; 2) _1panel_info ;;
            3) _1panel_password ;; 4) _1panel_port ;;
            5) _1panel_status ;; 6) _1panel_restart ;;
            7) _1panel_mount ;; 8) _1panel_uninstall ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_1panel_install() {
    if _has 1pctl; then
        _warn "1Panel 已安装"
        _confirm "是否重新安装 (将卸载后重装)？" || return
    fi

    _info "检查 Docker..."
    if ! _has docker; then
        _warn "1Panel 依赖 Docker，正在安装 Docker..."
        curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
        if ! _has docker; then
            _err "Docker 安装失败，1Panel 无法继续安装"
            return
        fi
        systemctl enable docker && systemctl start docker
        _ok "Docker 安装完成"
    fi

    _confirm "将安装 1Panel，过程约 3-5 分钟，确认？" || return
    _info "正在安装 1Panel..."
    curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o /tmp/1panel_install.sh
    bash /tmp/1panel_install.sh
    rm -f /tmp/1panel_install.sh

    if _has 1pctl; then
        _ok "1Panel 安装完成"
        echo ""
        _1panel_info
    else
        _err "1Panel 安装失败，请查看上方日志"
    fi
}

_1panel_info() {
    if ! _has 1pctl; then
        _err "1Panel 未安装"
        return
    fi
    _info "1Panel 信息"
    _line
    1pctl user-info
}

_1panel_password() {
    if ! _has 1pctl; then
        _err "1Panel 未安装"
        return
    fi
    read -rp "$(echo -e "${C_W}输入新密码 (回车自动生成): ${C_0}")" newpass
    if [[ -n "$newpass" ]]; then
        echo "$newpass" | 1pctl update password
    else
        1pctl update password
    fi
    _ok "密码已更新，新信息如下:"
    1pctl user-info
}

_1panel_port() {
    if ! _has 1pctl; then
        _err "1Panel 未安装"
        return
    fi
    local cur_port
    cur_port=$(1pctl user-info 2>/dev/null | grep -oP '端口.*?:\s*\K\d+')
    echo -e "  当前端口: ${C_W}${cur_port:-未知}${C_0}"
    echo ""
    read -rp "$(echo -e "${C_W}输入新端口号: ${C_0}")" new_port
    [[ -z "$new_port" ]] && return
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 || "$new_port" -gt 65535 ]]; then
        _err "无效端口号"
        return
    fi
    1pctl update port "$new_port"
    _ok "端口已修改为 ${new_port}"
    # 防火墙放行
    if _has firewall-cmd && systemctl is-active firewalld &>/dev/null; then
        firewall-cmd --permanent --add-port="${new_port}/tcp" && firewall-cmd --reload
        _ok "firewalld 已放行端口 ${new_port}"
    elif _has ufw; then
        ufw allow "${new_port}/tcp" && _ok "ufw 已放行端口 ${new_port}"
    fi
}

_1panel_status() {
    if ! _has 1pctl; then
        _err "1Panel 未安装"
        return
    fi
    _info "1Panel 运行状态"
    _line
    1pctl status
    echo ""
    _info "Docker 容器状态"
    docker ps --filter "name=1panel" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null
}

_1panel_restart() {
    if ! _has 1pctl; then
        _err "1Panel 未安装"
        return
    fi
    _confirm "确认重启 1Panel？" || return
    1pctl restart && _ok "1Panel 已重启" || _err "重启失败"
}

_1panel_mount() {
    if ! _has 1pctl; then
        _warn "1Panel 未安装，请先安装后再挂载数据盘"
        return
    fi

    _info "1Panel 默认数据目录:"
    docker inspect 1panel 2>/dev/null | grep -oP 'Source.*?1panel[^"]*' | head -3
    local default_dir
    default_dir=$(docker inspect 1panel 2>/dev/null | grep -oP '(?<=Source":")[^"]+' | grep 1panel | head -1)
    echo -e "  数据目录: ${C_W}${default_dir:-/opt/1panel}${C_0}"
    echo ""
    read -rp "$(echo -e "${C_W}数据盘挂载点 (如 /data): ${C_0}")" mnt
    [[ -z "$mnt" ]] && return

    if [[ ! -d "$mnt" ]]; then
        _err "目录 ${mnt} 不存在，请先挂载数据盘 (使用存储管理功能)"
        return
    fi

    local target="${mnt}/1panel"
    _confirm "将 1Panel 数据迁移到 ${target} ？" || return

    _info "停止 1Panel..."
    1pctl stop 2>/dev/null

    # 迁移数据
    mkdir -p "$target"
    if [[ -d "${default_dir:-/opt/1panel}" ]]; then
        _info "正在迁移数据..."
        cp -rp "${default_dir:-/opt/1panel}"/* "$target/"
        _ok "数据迁移完成"
    fi

    _info "更新 1Panel 数据目录配置..."
    sed -i "s|BASE_DIR=.*|BASE_DIR=${target}|g" /usr/local/bin/1pctl 2>/dev/null

    _info "启动 1Panel..."
    1pctl start 2>/dev/null
    _ok "1Panel 数据盘挂载完成"
}

_1panel_uninstall() {
    if ! _has 1pctl; then
        _err "1Panel 未安装"
        return
    fi
    _warn "⚠ 此操作将卸载 1Panel 及其所有数据（包括网站、数据库等），不可逆！"
    _confirm "确认卸载 1Panel？" || return
    1pctl uninstall
    _ok "1Panel 已卸载"
}


# ============================ 模块: 网站管理 =============================
m_web() {
    _title "网站管理 - 站点检测、Web服务器、SSL证书"
    while true; do
        echo -e "  ${C_G}1)${C_0} 站点状态检测"
        echo -e "  ${C_G}2)${C_0} Nginx 配置查看"
        echo -e "  ${C_G}3)${C_0} Caddy 配置查看"
        echo -e "  ${C_G}4)${C_0} SSL 证书检测"
        echo -e "  ${C_G}5)${C_0} Let's Encrypt 一键申请"
        echo -e "  ${C_G}6)${C_0} SSL 证书续期"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-6]: ${C_0}")" choice
        case "$choice" in
            1) _web_status ;; 2) _web_nginx ;;
            3) _web_caddy ;; 4) _web_ssl_check ;;
            5) _web_ssl_apply ;; 6) _web_ssl_renew ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_web_status() {
    read -rp "$(echo -e "${C_W}输入域名 (回车检测 localhost): ${C_0}")" domain
    [[ -z "$domain" ]] && domain="localhost"

    local url="http://${domain}"
    _info "检测站点: $url"
    _line

    if ! _has curl; then
        _warn "curl 未安装，尝试安装..."
        _pkg_install curl || { _err "curl 安装失败"; return; }
    fi

    local http_code redirect_url resp_time
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -L --connect-timeout 10 "$url" 2>/dev/null)
    redirect_url=$(curl -s -o /dev/null -w "%{url_effective}" -L --connect-timeout 10 "$url" 2>/dev/null)
    resp_time=$(curl -s -o /dev/null -w "%{time_total}" -L --connect-timeout 10 "$url" 2>/dev/null)

    echo -e "  HTTP 状态码: ${C_W}${http_code:-未知}${C_0}"
    echo -e "  最终 URL:    ${C_W}${redirect_url}${C_0}"
    echo -e "  响应时间:    ${C_W}${resp_time:-未知} 秒${C_0}"

    # SSL 过期检测
    if [[ "$redirect_url" == https* ]]; then
        _line
        _info "SSL 证书信息"
        local ssl_info
        ssl_info=$(echo | timeout 5 openssl s_client -connect "${domain}:443" -servername "$domain" 2>/dev/null | openssl x509 -noout -dates -subject 2>/dev/null)
        if [[ -n "$ssl_info" ]]; then
            local not_after
            not_after=$(echo "$ssl_info" | grep notAfter | cut -d= -f2)
            echo -e "  过期时间: ${C_W}${not_after}${C_0}"
            if [[ -n "$not_after" ]]; then
                local exp_ts now_ts days_left
                exp_ts=$(date -d "$not_after" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" +%s 2>/dev/null)
                now_ts=$(date +%s)
                if [[ -n "$exp_ts" ]]; then
                    days_left=$(( (exp_ts - now_ts) / 86400 ))
                    if [[ $days_left -lt 7 ]]; then
                        _err "SSL 证书将在 ${days_left} 天后过期！"
                    elif [[ $days_left -lt 30 ]]; then
                        _warn "SSL 证书将在 ${days_left} 天后过期"
                    else
                        _ok "SSL 证书还有 ${days_left} 天过期"
                    fi
                fi
            fi
        else
            _warn "无法获取 SSL 证书信息"
        fi
    fi
}

_web_nginx() {
    if ! _has nginx; then
        _err "Nginx 未安装"
        return
    fi
    _info "Nginx 版本"
    nginx -v 2>&1
    echo ""
    _info "Nginx 运行状态"
    systemctl status nginx --no-pager 2>/dev/null | head -10 || service nginx status 2>/dev/null | head -10
    echo ""
    _info "Nginx 配置"
    _line
    if [[ -d /etc/nginx/sites-enabled ]]; then
        for f in /etc/nginx/sites-enabled/*; do
            [[ -f "$f" ]] || continue
            echo -e "${C_C}--- $(basename "$f") ---${C_0}"
            cat "$f"
            echo ""
        done
    elif [[ -d /etc/nginx/conf.d ]]; then
        for f in /etc/nginx/conf.d/*.conf; do
            [[ -f "$f" ]] || continue
            echo -e "${C_C}--- $(basename "$f") ---${C_0}"
            cat "$f"
            echo ""
        done
    elif [[ -f /etc/nginx/nginx.conf ]]; then
        echo -e "${C_C}--- /etc/nginx/nginx.conf ---${C_0}"
        cat /etc/nginx/nginx.conf
    else
        _warn "未找到 Nginx 配置文件"
    fi
}

_web_caddy() {
    local caddyfile="/etc/caddy/Caddyfile"
    if [[ ! -f "$caddyfile" ]]; then
        _err "Caddyfile 不存在: $caddyfile"
        return
    fi
    _info "Caddy 配置"
    _line
    cat "$caddyfile"
    echo ""
    if _has caddy; then
        _info "配置验证"
        caddy validate --config "$caddyfile" 2>/dev/null && _ok "配置有效" || _warn "配置可能有问题"
    fi
}

_web_ssl_check() {
    local le_dir="/etc/letsencrypt/live"
    if [[ ! -d "$le_dir" ]]; then
        _err "Let's Encrypt 证书目录不存在: $le_dir"
        return
    fi
    _info "SSL 证书列表"
    _line
    local found=0
    for d in "$le_dir"/*; do
        [[ -d "$d" ]] || continue
        local cert="$d/fullchain.pem"
        [[ -f "$cert" ]] || continue
        local domain
        domain=$(basename "$d")
        local not_after
        not_after=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2)
        local days_left=""
        if [[ -n "$not_after" ]]; then
            local exp_ts now_ts
            exp_ts=$(date -d "$not_after" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" +%s 2>/dev/null)
            now_ts=$(date +%s)
            [[ -n "$exp_ts" ]] && days_left=$(( (exp_ts - now_ts) / 86400 ))
        fi
        found=1
        if [[ -n "$days_left" && "$days_left" -lt 7 ]]; then
            echo -e "  ${C_R}${domain}${C_0} - 过期时间: ${not_after} (${days_left} 天后过期)"
        elif [[ -n "$days_left" && "$days_left" -lt 30 ]]; then
            echo -e "  ${C_Y}${domain}${C_0} - 过期时间: ${not_after} (${days_left} 天后过期)"
        else
            echo -e "  ${C_G}${domain}${C_0} - 过期时间: ${not_after:-未知} (${days_left:-未知} 天后过期)"
        fi
    done
    [[ "$found" -eq 0 ]] && _warn "未找到 Let's Encrypt 证书"
}

_web_ssl_apply() {
    check_root
    read -rp "$(echo -e "${C_W}输入域名 (多个用空格分隔): ${C_0}")" domains
    [[ -z "$domains" ]] && { _err "域名不能为空"; return; }

    # 检测并安装 certbot
    if ! _has certbot; then
        _info "正在安装 certbot..."
        if [[ "$PM" == "apt" ]]; then
            _pkg_install certbot python3-certbot-nginx python3-certbot-apache 2>/dev/null || _pkg_install certbot
        else
            _pkg_install certbot
        fi
        if ! _has certbot; then
            _info "尝试通过 snap 安装 certbot..."
            if _has snap; then
                snap install certbot --classic 2>/dev/null && ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null
            fi
        fi
    fi
    if ! _has certbot; then
        _err "certbot 安装失败"
        return
    fi

    _info "申请 Let's Encrypt 证书..."
    local webroot_arg=""
    if [[ -d /var/www/html ]]; then
        webroot_arg="--webroot -w /var/www/html"
    elif [[ -d /usr/share/nginx/html ]]; then
        webroot_arg="--webroot -w /usr/share/nginx/html"
    fi

    certbot certonly --standalone -d "$domains" --agree-tos --no-eff-email -m "admin@${domains%% *}" --non-interactive 2>/dev/null || \
    certbot certonly $webroot_arg -d "$domains" --agree-tos --no-eff-email -m "admin@${domains%% *}" --non-interactive 2>/dev/null || \
    certbot --nginx -d "$domains" --agree-tos --no-eff-email --non-interactive 2>/dev/null || \
    certbot --apache -d "$domains" --agree-tos --no-eff-email --non-interactive 2>/dev/null

    if [[ $? -eq 0 ]]; then
        _ok "证书申请成功"
        _web_ssl_check
    else
        _err "证书申请失败，请确保域名已解析到本机且 80 端口可访问"
    fi
}

_web_ssl_renew() {
    check_root
    if ! _has certbot; then
        _err "certbot 未安装"
        return
    fi
    _info "测试 SSL 证书续期..."
    certbot renew --dry-run
    if [[ $? -eq 0 ]]; then
        _ok "续期测试通过"
        _confirm "是否立即执行真实续期？" && certbot renew && _ok "续期完成" || _info "已跳过真实续期"
    else
        _err "续期测试失败，请检查配置"
    fi
}

# ============================ 模块: 数据库管理 =============================
m_db() {
    _title "数据库管理 - MySQL/MariaDB、Redis"
    while true; do
        echo -e "  ${C_G}1)${C_0} MySQL/MariaDB 状态"
        echo -e "  ${C_G}2)${C_0} MySQL 性能查看"
        echo -e "  ${C_G}3)${C_0} MySQL 一键备份"
        echo -e "  ${C_G}4)${C_0} Redis 状态查看"
        echo -e "  ${C_G}5)${C_0} Redis 一键备份"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-5]: ${C_0}")" choice
        case "$choice" in
            1) _db_mysql_status ;; 2) _db_mysql_perf ;;
            3) _db_mysql_backup ;; 4) _db_redis_status ;;
            5) _db_redis_backup ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_db_mysql_status() {
    local svc=""
    if systemctl is-active mariadb &>/dev/null; then
        svc="mariadb"
    elif systemctl is-active mysql &>/dev/null; then
        svc="mysql"
    elif service mariadb status &>/dev/null 2>&1; then
        svc="mariadb"
    elif service mysql status &>/dev/null 2>&1; then
        svc="mysql"
    fi

    if [[ -z "$svc" ]]; then
        _err "MySQL/MariaDB 未运行或未安装"
        return
    fi

    _info "服务状态: ${C_W}${svc}${C_0}"
    systemctl status "$svc" --no-pager 2>/dev/null | head -10 || service "$svc" status 2>/dev/null | head -10
    echo ""

    if _has mysql; then
        _info "版本信息"
        mysql -V 2>/dev/null || mariadb -V 2>/dev/null
        echo ""

        local creds="-u root"
        # 尝试无密码连接
        if ! mysql $creds -e "SELECT 1" &>/dev/null; then
            read -rsp "$(echo -e "${C_W}输入 MySQL root 密码 (回车尝试无密码): ${C_0}")" mpwd
            echo ""
            [[ -n "$mpwd" ]] && creds="-u root -p'$mpwd'"
        fi

        _info "连接数信息"
        _line
        mysql $creds -e "SHOW STATUS LIKE 'Threads_connected'; SHOW STATUS LIKE 'Max_used_connections'; SHOW STATUS LIKE 'Uptime';" 2>/dev/null || _warn "无法连接 MySQL"
    fi
}

_db_mysql_perf() {
    local creds="-u root"
    if ! mysql $creds -e "SELECT 1" &>/dev/null; then
        read -rsp "$(echo -e "${C_W}输入 MySQL root 密码 (回车尝试无密码): ${C_0}")" mpwd
        echo ""
        [[ -n "$mpwd" ]] && creds="-u root -p'$mpwd'"
    fi

    _info "当前进程列表"
    _line
    mysql $creds -e "SHOW PROCESSLIST;" 2>/dev/null || { _err "无法连接 MySQL"; return; }
    echo ""

    _info "关键变量"
    _line
    mysql $creds -e "SHOW VARIABLES LIKE 'max_connections'; SHOW VARIABLES LIKE 'wait_timeout'; SHOW VARIABLES LIKE 'interactive_timeout';" 2>/dev/null
    echo ""

    _info "InnoDB 状态"
    _line
    mysql $creds -e "SHOW ENGINE INNODB STATUS\G" 2>/dev/null | head -40 || _warn "无法获取 InnoDB 状态"
}

_db_mysql_backup() {
    check_root
    local creds="-u root"
    if ! mysql $creds -e "SELECT 1" &>/dev/null; then
        read -rsp "$(echo -e "${C_W}输入 MySQL root 密码 (回车尝试无密码): ${C_0}")" mpwd
        echo ""
        [[ -n "$mpwd" ]] && creds="-u root -p'$mpwd'"
    fi

    _info "可用数据库"
    _line
    local dbs
    dbs=$(mysql $creds -e "SHOW DATABASES;" 2>/dev/null | grep -v "Database\|information_schema\|performance_schema\|sys\|mysql")
    echo "$dbs"
    echo ""
    read -rp "$(echo -e "${C_W}输入要备份的数据库名 (输入 * 备份全部): ${C_0}")" dbname
    [[ -z "$dbname" ]] && { _err "数据库名不能为空"; return; }

    local backup_dir="/backup/mysql"
    mkdir -p "$backup_dir"
    local date_str
    date_str=$(date +%Y%m%d_%H%M%S)

    if [[ "$dbname" == "*" ]]; then
        local filename="all_databases_${date_str}.sql"
        _info "正在备份所有数据库..."
        mysqldump $creds --all-databases --single-transaction --quick > "${backup_dir}/${filename}" 2>/dev/null
    else
        local filename="${dbname}_${date_str}.sql"
        _info "正在备份数据库: ${dbname}..."
        mysqldump $creds "$dbname" --single-transaction --quick > "${backup_dir}/${filename}" 2>/dev/null
    fi

    if [[ $? -eq 0 && -f "${backup_dir}/${filename}" ]]; then
        _ok "备份完成: ${backup_dir}/${filename}"
        _info "压缩备份文件中..."
        gzip -f "${backup_dir}/${filename}"
        local final_size
        final_size=$(du -h "${backup_dir}/${filename}.gz" 2>/dev/null | cut -f1)
        _ok "压缩完成: ${backup_dir}/${filename}.gz (${final_size})"
    else
        _err "备份失败"
    fi
}

_db_redis_status() {
    if ! _has redis-cli; then
        _err "Redis 未安装"
        return
    fi
    _info "Redis 运行状态"
    systemctl status redis --no-pager 2>/dev/null | head -8 || systemctl status redis-server --no-pager 2>/dev/null | head -8 || _warn "无法获取服务状态"
    echo ""

    _info "Redis 关键指标"
    _line
    redis-cli info 2>/dev/null | grep -E "^# Server|^redis_version|^connected_clients|^used_memory_human|^used_memory_peak_human|^total_system_memory_human|^keyspace_hits|^keyspace_misses|^instantaneous_ops_per_sec|^rdb_last_bgsave_status" || _err "无法连接 Redis"
    echo ""

    local hits misses ratio
    hits=$(redis-cli info stats 2>/dev/null | grep keyspace_hits | cut -d: -f2 | tr -d '\r')
    misses=$(redis-cli info stats 2>/dev/null | grep keyspace_misses | cut -d: -f2 | tr -d '\r')
    if [[ -n "$hits" && -n "$misses" && $((hits + misses)) -gt 0 ]]; then
        ratio=$(echo "scale=2; $hits * 100 / ($hits + $misses)" | bc 2>/dev/null || echo "N/A")
        echo -e "  命中率: ${C_W}${ratio}%${C_0}"
    fi
}

_db_redis_backup() {
    check_root
    if ! _has redis-cli; then
        _err "Redis 未安装"
        return
    fi

    local backup_dir="/backup/redis"
    mkdir -p "$backup_dir"
    local date_str
    date_str=$(date +%Y%m%d_%H%M%S)

    _info "执行 BGSAVE..."
    redis-cli BGSAVE 2>/dev/null
    if [[ $? -ne 0 ]]; then
        _warn "BGSAVE 失败，尝试 SAVE..."
        redis-cli SAVE 2>/dev/null || { _err "Redis 备份失败"; return; }
    fi

    # 等待 rdb 文件生成
    sleep 2

    local rdb_path
    rdb_path=$(redis-cli CONFIG GET dir 2>/dev/null | tail -1 | tr -d '\r')
    local rdb_file
    rdb_file=$(redis-cli CONFIG GET dbfilename 2>/dev/null | tail -1 | tr -d '\r')
    [[ -z "$rdb_path" ]] && rdb_path="/var/lib/redis"
    [[ -z "$rdb_file" ]] && rdb_file="dump.rdb"

    local src="${rdb_path}/${rdb_file}"
    if [[ ! -f "$src" ]]; then
        src="/var/lib/redis/dump.rdb"
    fi
    if [[ ! -f "$src" ]]; then
        _err "未找到 Redis RDB 文件"
        return
    fi

    cp "$src" "${backup_dir}/dump_${date_str}.rdb"
    if [[ $? -eq 0 ]]; then
        _ok "Redis 备份完成: ${backup_dir}/dump_${date_str}.rdb"
        local size
        size=$(du -h "${backup_dir}/dump_${date_str}.rdb" 2>/dev/null | cut -f1)
        _info "备份大小: ${size}"
    else
        _err "备份复制失败"
    fi
}

# ============================ 模块: 备份管理 =============================
m_backup() {
    _title "备份管理 - 打包、远程传输、定时任务"
    while true; do
        echo -e "  ${C_G}1)${C_0} 目录一键打包"
        echo -e "  ${C_G}2)${C_0} 备份到远程服务器"
        echo -e "  ${C_G}3)${C_0} 备份定时任务"
        echo -e "  ${C_G}4)${C_0} 查看备份记录"
        echo -e "  ${C_G}5)${C_0} 清理旧备份"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-5]: ${C_0}")" choice
        case "$choice" in
            1) _backup_pack ;; 2) _backup_remote ;;
            3) _backup_cron ;; 4) _backup_list ;;
            5) _backup_clean ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_backup_pack() {
    check_root
    read -rp "$(echo -e "${C_W}输入要打包的目录: ${C_0}")" src_dir
    [[ -z "$src_dir" || ! -d "$src_dir" ]] && { _err "目录不存在"; return; }

    local backup_dir="/backup/archive"
    mkdir -p "$backup_dir"
    local date_str name
    date_str=$(date +%Y%m%d_%H%M%S)
    name=$(basename "$src_dir")
    local out="${backup_dir}/${name}_${date_str}.tar.gz"

    read -rp "$(echo -e "${C_W}排除模式 (如 '*.log cache/'，回车无排除): ${C_0}")" exclude

    _info "开始打包 ${src_dir} ..."
    if [[ -n "$exclude" ]]; then
        tar -czf "$out" --exclude="${exclude}" -C "$(dirname "$src_dir")" "$name" 2>/dev/null
    else
        tar -czf "$out" -C "$(dirname "$src_dir")" "$name" 2>/dev/null
    fi

    if [[ $? -eq 0 && -f "$out" ]]; then
        local size
        size=$(du -h "$out" 2>/dev/null | cut -f1)
        _ok "打包完成: $out (${size})"
    else
        _err "打包失败"
    fi
}

_backup_remote() {
    check_root
    local backup_dir="/backup"
    _info "本地备份文件"
    _line
    find "$backup_dir" -maxdepth 2 -type f \( -name "*.tar.gz" -o -name "*.sql.gz" -o -name "*.rdb" \) -exec ls -lh {} \; 2>/dev/null || _warn "未找到备份文件"
    echo ""

    read -rp "$(echo -e "${C_W}选择要上传的备份文件完整路径: ${C_0}")" file
    [[ ! -f "$file" ]] && { _err "文件不存在"; return; }

    read -rp "$(echo -e "${C_W}远程服务器 [user@host]: ${C_0}")" remote
    [[ -z "$remote" ]] && { _err "远程服务器不能为空"; return; }
    read -rp "$(echo -e "${C_W}远程目标路径 (默认 /backup): ${C_0}")" rpath
    [[ -z "$rpath" ]] && rpath="/backup"
    read -rp "$(echo -e "${C_W}SSH 端口 (默认 22): ${C_0}")" rport
    [[ -z "$rport" ]] && rport="22"

    if _has rsync; then
        _info "使用 rsync 上传..."
        rsync -avz -e "ssh -p ${rport}" "$file" "${remote}:${rpath}/"
    elif _has scp; then
        _info "使用 scp 上传..."
        scp -P "${rport}" "$file" "${remote}:${rpath}/"
    else
        _warn "未找到 rsync 或 scp，尝试安装 rsync..."
        _pkg_install rsync && rsync -avz -e "ssh -p ${rport}" "$file" "${remote}:${rpath}/" || { _err "上传失败"; return; }
    fi

    if [[ $? -eq 0 ]]; then
        _ok "上传成功: ${remote}:${rpath}/$(basename "$file")"
    else
        _err "上传失败"
    fi
}

_backup_cron() {
    check_root
    _info "当前备份相关定时任务"
    _line
    crontab -l 2>/dev/null | grep -i backup || _warn "暂无备份定时任务"
    echo ""

    echo -e "  ${C_G}1)${C_0} 添加目录定时打包"
    echo -e "  ${C_G}2)${C_0} 添加 MySQL 定时备份"
    echo -e "  ${C_G}3)${C_0} 删除备份定时任务"
    read -rp "$(echo -e "${C_W}选择 [1-3]: ${C_0}")" cchoice

    case "$cchoice" in
        1)
            read -rp "$(echo -e "${C_W}要打包的目录: ${C_0}")" cdir
            [[ ! -d "$cdir" ]] && { _err "目录不存在"; return; }
            read -rp "$(echo -e "${C_W}Cron 表达式 (如 '0 3 * * *' 表示每天3点): ${C_0}")" cronexp
            [[ -z "$cronexp" ]] && { _err "表达式不能为空"; return; }
            local name
            name=$(basename "$cdir")
            (crontab -l 2>/dev/null; echo "${cronexp} tar -czf /backup/archive/${name}_\$(date +\\%Y\\%m\\%d_\\%H\\%M\\%S).tar.gz ${cdir}") | crontab -
            _ok "定时任务已添加"
            ;;
        2)
            read -rp "$(echo -e "${C_W}数据库名 (* 表示全部): ${C_0}")" cdb
            [[ -z "$cdb" ]] && cdb="*"
            read -rp "$(echo -e "${C_W}Cron 表达式 (如 '0 3 * * *'): ${C_0}")" cronexp
            [[ -z "$cronexp" ]] && { _err "表达式不能为空"; return; }
            read -rsp "$(echo -e "${C_W}MySQL root 密码 (回车无密码): ${C_0}")" cpwd
            echo ""
            local creds=""
            [[ -n "$cpwd" ]] && creds="-p'${cpwd}'"
            if [[ "$cdb" == "*" ]]; then
                (crontab -l 2>/dev/null; echo "${cronexp} mysqldump -u root ${creds} --all-databases --single-transaction --quick | gzip > /backup/mysql/all_\$(date +\\%Y\\%m\\%d_\\%H\\%M\\%S).sql.gz") | crontab -
            else
                (crontab -l 2>/dev/null; echo "${cronexp} mysqldump -u root ${creds} ${cdb} --single-transaction --quick | gzip > /backup/mysql/${cdb}_\$(date +\\%Y\\%m\\%d_\\%H\\%M\\%S).sql.gz") | crontab -
            fi
            _ok "定时任务已添加"
            ;;
        3)
            read -rp "$(echo -e "${C_W}输入要删除任务的关键词: ${C_0}")" kw
            [[ -z "$kw" ]] && return
            crontab -l 2>/dev/null | grep -v "$kw" | crontab -
            _ok "相关定时任务已删除"
            ;;
    esac
}

_backup_list() {
    local backup_dir="/backup"
    if [[ ! -d "$backup_dir" ]]; then
        _err "备份目录不存在: $backup_dir"
        return
    fi
    _info "备份文件列表"
    _line
    find "$backup_dir" -maxdepth 3 -type f \( -name "*.tar.gz" -o -name "*.sql" -o -name "*.sql.gz" -o -name "*.rdb" -o -name "*.zip" \) -printf "  %TY-%Tm-%Td %TH:%TM  %10s  %p\n" 2>/dev/null || \
    find "$backup_dir" -maxdepth 3 -type f \( -name "*.tar.gz" -o -name "*.sql" -o -name "*.sql.gz" -o -name "*.rdb" -o -name "*.zip" \) -exec ls -lh {} \; 2>/dev/null
    echo ""
    local total
    total=$(du -sh "$backup_dir" 2>/dev/null | cut -f1)
    _info "备份目录总大小: ${total}"
}

_backup_clean() {
    check_root
    read -rp "$(echo -e "${C_W}删除 N 天前的备份 (输入天数 N): ${C_0}")" days
    if ! [[ "$days" =~ ^[0-9]+$ ]] || [[ "$days" -lt 1 ]]; then
        _err "请输入有效的正整数天数"
        return
    fi

    local backup_dir="/backup"
    _info "查找 ${days} 天前的备份文件..."
    local found
    found=$(find "$backup_dir" -maxdepth 3 -type f -mtime +"$days" 2>/dev/null)
    if [[ -z "$found" ]]; then
        _ok "未发现 ${days} 天前的备份文件"
        return
    fi

    echo "$found"
    _confirm "确认删除以上文件？" || return
    find "$backup_dir" -maxdepth 3 -type f -mtime +"$days" -delete 2>/dev/null
    _ok "旧备份清理完成"
}

# ============================ 模块: 安全扫描 =============================
m_security() {
    _title "安全扫描 - 系统安全、恶意脚本、登录审计"
    while true; do
        echo -e "  ${C_G}1)${C_0} 系统安全扫描"
        echo -e "  ${C_G}2)${C_0} 恶意脚本检测"
        echo -e "  ${C_G}3)${C_0} 登录审计"
        echo -e "  ${C_G}4)${C_0} 一键封禁 IP"
        echo -e "  ${C_G}5)${C_0} 查看开放端口风险"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-5]: ${C_0}")" choice
        case "$choice" in
            1) _security_scan ;; 2) _security_malware ;;
            3) _security_login ;; 4) _security_banip ;;
            5) _security_ports ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_security_scan() {
    check_root
    _title "系统安全扫描"

    _info "1) 检查空密码用户"
    _line
    local empty_pass
    empty_pass=$(awk -F: '$2 == "" {print $1}' /etc/shadow 2>/dev/null)
    if [[ -n "$empty_pass" ]]; then
        _err "发现空密码用户:"
        echo "$empty_pass"
    else
        _ok "未发现空密码用户"
    fi
    echo ""

    _info "2) 检查 SUID 文件 (前 20 个)"
    _line
    local suid_files
    suid_files=$(find / -perm -4000 -type f 2>/dev/null | head -20)
    if [[ -n "$suid_files" ]]; then
        echo "$suid_files"
        _warn "发现 SUID 文件，请确认是否合法"
    else
        _ok "未发现异常 SUID 文件"
    fi
    echo ""

    _info "3) 检查世界可写目录"
    _line
    local ww_dirs
    ww_dirs=$(find / -type d -perm -0002 ! -perm -1000 2>/dev/null | grep -v "proc\|sys\|snap\|cgroup" | head -20)
    if [[ -n "$ww_dirs" ]]; then
        echo "$ww_dirs"
        _warn "发现没有 sticky bit 的世界可写目录"
    else
        _ok "未发现风险世界可写目录"
    fi
    echo ""

    _info "4) 检查 SSH root 密码登录"
    _line
    if grep -qE "^PermitRootLogin\s+(yes|without-password)" /etc/ssh/sshd_config 2>/dev/null; then
        _err "SSH root 密码登录已开启，建议改为禁止: PermitRootLogin no"
    elif grep -qE "^PermitRootLogin\s+no" /etc/ssh/sshd_config 2>/dev/null; then
        _ok "SSH root 密码登录已禁止"
    else
        _warn "未明确配置 PermitRootLogin，默认可能允许 root 登录"
    fi
    echo ""

    _info "5) 检查密码策略"
    _line
    if [[ -f /etc/login.defs ]]; then
        grep -E "PASS_MAX_DAYS|PASS_MIN_DAYS|PASS_MIN_LEN" /etc/login.defs 2>/dev/null | grep -v "^#" | head -5 || _warn "未配置密码策略"
    else
        _warn "未找到 /etc/login.defs"
    fi
}

_security_malware() {
    check_root
    _info "扫描 webshell 特征文件..."
    _line

    local scan_dirs="/var/www /home"
    local patterns="eval\|assert\|base64_decode\|shell_exec\|exec\|system\|passthru\|preg_replace.*e\|file_put_contents\|file_get_contents.*http"
    local found=0

    for dir in $scan_dirs; do
        [[ ! -d "$dir" ]] && continue
        _info "扫描目录: $dir"
        while IFS= read -r -d '' file; do
            local base
            base=$(basename "$file" | tr '[:upper:]' '[:lower:]')
            # 跳过常见非脚本文件
            [[ "$base" == *".jpg" || "$base" == *".png" || "$base" == *".gif" || "$base" == *".css" || "$base" == *".js" ]] && continue
            if grep -l "$patterns" "$file" &>/dev/null; then
                found=1
                echo -e "  ${C_R}[可疑]${C_0} $file"
                grep -n "$patterns" "$file" 2>/dev/null | head -3 | sed 's/^/      /'
            fi
        done < <(find "$dir" -type f \( -name "*.php" -o -name "*.jsp" -o -name "*.asp" -o -name "*.aspx" -o -name "*.sh" -o -name "*.py" \) -print0 2>/dev/null)
    done

    if [[ "$found" -eq 0 ]]; then
        _ok "未发现明显的 webshell 特征文件"
    else
        _warn "发现可疑文件，请人工复核"
    fi
}

_security_login() {
    _info "登录审计"
    _line

    _info "最近登录记录 (last)"
    last -20 2>/dev/null | head -22 || _warn "无法获取登录记录"
    echo ""

    _info "失败登录记录 (lastb)"
    lastb -20 2>/dev/null | head -22 || _warn "无法获取失败登录记录 (可能需要 root)"
    echo ""

    _info "TOP 攻击 IP (失败登录)"
    _line
    if [[ -f /var/log/auth.log ]]; then
        grep "Failed password" /var/log/auth.log 2>/dev/null | awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head -10 || _warn "暂无数据"
    elif [[ -f /var/log/secure ]]; then
        grep "Failed password" /var/log/secure 2>/dev/null | awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head -10 || _warn "暂无数据"
    else
        _warn "未找到认证日志文件"
    fi
    echo ""

    _info "当前在线用户"
    who 2>/dev/null || _warn "无法获取"
}

_security_banip() {
    check_root
    read -rp "$(echo -e "${C_W}输入要封禁的 IP: ${C_0}")" ip
    [[ -z "$ip" ]] && return
    if ! [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        _err "无效的 IP 地址"
        return
    fi

    # 优先使用 fail2ban
    if _has fail2ban-client && systemctl is-active fail2ban &>/dev/null; then
        _info "使用 fail2ban 封禁 ${ip}..."
        fail2ban-client set sshd banip "$ip" 2>/dev/null && _ok "fail2ban 已封禁 ${ip}" || _err "fail2ban 封禁失败"
    else
        _info "使用 iptables 封禁 ${ip}..."
        if _has iptables; then
            iptables -I INPUT -s "$ip" -j DROP 2>/dev/null
            _ok "iptables 已封禁 ${ip}"
            # 尝试持久化
            if _has iptables-save; then
                iptables-save > /etc/iptables.rules 2>/dev/null && _info "规则已保存到 /etc/iptables.rules"
            fi
        elif _has nft; then
            nft add rule inet filter input ip saddr "$ip" drop 2>/dev/null && _ok "nftables 已封禁 ${ip}" || _err "nftables 封禁失败"
        else
            _err "未找到 iptables 或 nftables"
        fi
    fi
}

_security_ports() {
    _info "监听端口及服务"
    _line
    if _has ss; then
        ss -tulpn 2>/dev/null | grep LISTEN || ss -tulp 2>/dev/null | grep LISTEN
    elif _has netstat; then
        netstat -tulpn 2>/dev/null | grep LISTEN || netstat -tulp 2>/dev/null | grep LISTEN
    else
        _warn "未找到 ss 或 netstat"
        _pkg_install iproute2 net-tools 2>/dev/null
        ss -tulpn 2>/dev/null | grep LISTEN || _err "无法获取端口信息"
    fi
    echo ""

    _info "常见风险端口提示"
    _line
    echo -e "  ${C_Y}21${C_0}   FTP - 建议使用 SFTP 替代"
    echo -e "  ${C_Y}23${C_0}   Telnet - 明文传输，建议禁用"
    echo -e "  ${C_Y}3306${C_0} MySQL - 建议限制访问来源"
    echo -e "  ${C_Y}6379${C_0} Redis - 建议配置密码和绑定 IP"
    echo -e "  ${C_Y}9200${C_0} Elasticsearch - 建议配置认证"
}

# ============================ 模块: 磁盘IO性能 =============================
m_io() {
    _title "磁盘 IO 性能 - 监控、测试、健康检测"
    while true; do
        echo -e "  ${C_G}1)${C_0} 磁盘 IO 实时监控"
        echo -e "  ${C_G}2)${C_0} 磁盘读写速度测试"
        echo -e "  ${C_G}3)${C_0} 磁盘健康检测"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-3]: ${C_0}")" choice
        case "$choice" in
            1) _io_monitor ;; 2) _io_test ;;
            3) _io_smart ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_io_monitor() {
    check_root
    if _has iotop; then
        _info "启动 iotop (按 Q 退出)..."
        iotop -o -b -n 10 2>/dev/null || iotop -o 2>/dev/null
    else
        _warn "iotop 未安装，尝试安装..."
        _pkg_install iotop 2>/dev/null
        if _has iotop; then
            iotop -o -b -n 10 2>/dev/null
        else
            _warn "iotop 安装失败，尝试使用 iostat..."
            if _has iostat; then
                iostat -x 1 10 2>/dev/null
            else
                _pkg_install sysstat 2>/dev/null && iostat -x 1 10 2>/dev/null || _err "无法安装 IO 监控工具"
            fi
        fi
    fi
}

_io_test() {
    check_root
    if ! _has fio; then
        _info "fio 未安装，正在安装..."
        _pkg_install fio 2>/dev/null || { _err "fio 安装失败"; return; }
    fi

    read -rp "$(echo -e "${C_W}测试目录 (默认 /tmp): ${C_0}")" testdir
    [[ -z "$testdir" ]] && testdir="/tmp"
    [[ ! -d "$testdir" ]] && { _err "目录不存在"; return; }

    _confirm "将在 ${testdir} 运行 fio 测试，可能耗时数分钟，确认？" || return

    _info "顺序读测试 (128k)..."
    fio --name=seq_read --directory="$testdir" --rw=read --bs=128k --size=512m --numjobs=1 --runtime=30 --direct=1 --group_reporting 2>/dev/null | grep -E "read:|BW|IOPS" | head -5
    echo ""

    _info "顺序写测试 (128k)..."
    fio --name=seq_write --directory="$testdir" --rw=write --bs=128k --size=512m --numjobs=1 --runtime=30 --direct=1 --group_reporting 2>/dev/null | grep -E "write:|BW|IOPS" | head -5
    echo ""

    _info "随机读测试 (4k)..."
    fio --name=rand_read --directory="$testdir" --rw=randread --bs=4k --size=256m --numjobs=4 --runtime=30 --direct=1 --group_reporting 2>/dev/null | grep -E "read:|BW|IOPS" | head -5
    echo ""

    _info "随机写测试 (4k)..."
    fio --name=rand_write --directory="$testdir" --rw=randwrite --bs=4k --size=256m --numjobs=4 --runtime=30 --direct=1 --group_reporting 2>/dev/null | grep -E "write:|BW|IOPS" | head -5
    echo ""

    rm -f "${testdir}"/seq_read.* "${testdir}"/seq_write.* "${testdir}"/rand_read.* "${testdir}"/rand_write.* 2>/dev/null
    _ok "测试完成，临时文件已清理"
}

_io_smart() {
    if ! _has smartctl; then
        _warn "smartctl 未安装，尝试安装..."
        _pkg_install smartmontools 2>/dev/null || { _err "smartmontools 安装失败"; return; }
    fi

    _info "可用磁盘"
    _line
    lsblk -ndo NAME,SIZE,TYPE,MODEL 2>/dev/null | grep disk || fdisk -l 2>/dev/null | grep "Disk /dev" | head -10
    echo ""
    read -rp "$(echo -e "${C_W}输入磁盘设备 (如 /dev/sda): ${C_0}")" disk
    [[ -z "$disk" ]] && return
    if [[ ! -b "$disk" ]]; then
        _err "设备不存在: $disk"
        return
    fi

    _info "SMART 状态: ${disk}"
    _line
    smartctl -H "$disk" 2>/dev/null || _err "无法获取 SMART 状态"
    echo ""
    _info "详细 SMART 信息"
    _line
    smartctl -a "$disk" 2>/dev/null | grep -E "Model|Serial|Temperature|Reallocated|Pending|Uncorrectable|Power_On|Wear_Level" || _warn "无法获取详细信息"
}

# ============================ 模块: 用户权限 =============================
m_user() {
    _title "用户权限 - 用户管理、sudo、权限修复"
    while true; do
        echo -e "  ${C_G}1)${C_0} 查看系统用户"
        echo -e "  ${C_G}2)${C_0} 添加用户"
        echo -e "  ${C_G}3)${C_0} 删除用户"
        echo -e "  ${C_G}4)${C_0} 修改用户密码"
        echo -e "  ${C_G}5)${C_0} 添加/移除 sudo 权限"
        echo -e "  ${C_G}6)${C_0} 文件权限批量修复"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-6]: ${C_0}")" choice
        case "$choice" in
            1) _user_list ;; 2) _user_add ;;
            3) _user_del ;; 4) _user_passwd ;;
            5) _user_sudo ;; 6) _user_fixperms ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_user_list() {
    _info "系统用户列表"
    _line
    printf "  %-15s %-6s %-6s %-20s %s\n" "用户名" "UID" "GID" "家目录" "Shell"
    while IFS=: read -r user pass uid gid desc home shell; do
        [[ "$uid" -ge 1000 && "$uid" -lt 65534 ]] || [[ "$uid" -eq 0 ]] || continue
        printf "  %-15s %-6s %-6s %-20s %s\n" "$user" "$uid" "$gid" "$home" "$shell"
    done < /etc/passwd
    echo ""
    _info "当前在线用户"
    who 2>/dev/null || _warn "无法获取"
}

_user_add() {
    check_root
    read -rp "$(echo -e "${C_W}输入用户名: ${C_0}")" username
    [[ -z "$username" ]] && return
    if id "$username" &>/dev/null; then
        _err "用户已存在"
        return
    fi

    read -rp "$(echo -e "${C_W}输入密码 (回车自动生成): ${C_0}")" upass
    if [[ -z "$upass" ]]; then
        upass=$(tr -dc 'a-zA-Z0-9' < /dev/urandom 2>/dev/null | head -c 12)
        _info "自动生成密码: ${C_W}${upass}${C_0}"
    fi

    read -rp "$(echo -e "${C_W}是否添加 sudo 权限 [y/N]: ${C_0}")" sudo_yes

    useradd -m -s /bin/bash "$username" 2>/dev/null
    if [[ $? -ne 0 ]]; then
        _err "用户创建失败"
        return
    fi

    echo "${username}:${upass}" | chpasswd 2>/dev/null
    _ok "用户 ${username} 创建成功"

    if [[ "$sudo_yes" =~ ^[Yy]$ ]]; then
        if [[ -d /etc/sudoers.d ]]; then
            echo "${username} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${username}" && chmod 440 "/etc/sudoers.d/${username}"
        else
            echo "${username} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
        fi
        _ok "已添加 sudo 权限"
    fi
}

_user_del() {
    check_root
    read -rp "$(echo -e "${C_W}输入要删除的用户名: ${C_0}")" username
    [[ -z "$username" ]] && return
    if [[ "$username" == "root" ]]; then
        _err "不能删除 root 用户"
        return
    fi
    if ! id "$username" &>/dev/null; then
        _err "用户不存在"
        return
    fi
    _confirm "确认删除用户 ${username} 及其家目录？" || return
    userdel -r "$username" 2>/dev/null && _ok "用户 ${username} 已删除" || _err "删除失败"
    rm -f "/etc/sudoers.d/${username}" 2>/dev/null
}

_user_passwd() {
    check_root
    read -rp "$(echo -e "${C_W}输入用户名: ${C_0}")" username
    [[ -z "$username" ]] && return
    if ! id "$username" &>/dev/null; then
        _err "用户不存在"
        return
    fi
    read -rsp "$(echo -e "${C_W}输入新密码: ${C_0}")" upass
    echo ""
    [[ -z "$upass" ]] && { _err "密码不能为空"; return; }
    echo "${username}:${upass}" | chpasswd 2>/dev/null && _ok "密码已修改" || _err "密码修改失败"
}

_user_sudo() {
    check_root
    read -rp "$(echo -e "${C_W}输入用户名: ${C_0}")" username
    [[ -z "$username" ]] && return
    if ! id "$username" &>/dev/null; then
        _err "用户不存在"
        return
    fi

    echo -e "  ${C_G}1)${C_0} 添加 sudo 权限"
    echo -e "  ${C_G}2)${C_0} 移除 sudo 权限"
    read -rp "$(echo -e "${C_W}选择 [1-2]: ${C_0}")" schoice

    case "$schoice" in
        1)
            if [[ -d /etc/sudoers.d ]]; then
                echo "${username} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${username}" && chmod 440 "/etc/sudoers.d/${username}"
            else
                if ! grep -q "^${username} " /etc/sudoers; then
                    echo "${username} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
                fi
            fi
            _ok "已添加 sudo 权限"
            ;;
        2)
            rm -f "/etc/sudoers.d/${username}" 2>/dev/null
            sed -i "/^${username} /d" /etc/sudoers 2>/dev/null
            _ok "已移除 sudo 权限"
            ;;
    esac
}

_user_fixperms() {
    check_root
    read -rp "$(echo -e "${C_W}目标目录 (默认 /www): ${C_0}")" target
    [[ -z "$target" ]] && target="/www"
    [[ ! -d "$target" ]] && { _err "目录不存在: $target"; return; }

    read -rp "$(echo -e "${C_W}设置所有者 (默认 www): ${C_0}")" owner
    [[ -z "$owner" ]] && owner="www"
    read -rp "$(echo -e "${C_W}设置所属组 (默认 www): ${C_0}")" group
    [[ -z "$group" ]] && group="www"

    _confirm "将 ${target} 权限修复为 755 ${owner}:${group}？" || return

    chown -R "${owner}:${group}" "$target" 2>/dev/null
    find "$target" -type d -exec chmod 755 {} \; 2>/dev/null
    find "$target" -type f -exec chmod 644 {} \; 2>/dev/null
    _ok "权限修复完成"
    _info "目录: 755, 文件: 644, 所有者: ${owner}:${group}"
}

# ============================ 模块: 内网穿透 =============================
m_nat() {
    _title "内网穿透 - frp、nps 安装与配置"
    while true; do
        echo -e "  ${C_G}1)${C_0} 安装 frp"
        echo -e "  ${C_G}2)${C_0} 配置 frpc"
        echo -e "  ${C_G}3)${C_0} 启动/停止 frpc"
        echo -e "  ${C_G}4)${C_0} 安装 nps"
        echo -e "  ${C_G}5)${C_0} 查看内网穿透状态"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-5]: ${C_0}")" choice
        case "$choice" in
            1) _nat_frp_install ;; 2) _nat_frpc_config ;;
            3) _nat_frpc_control ;; 4) _nat_nps_install ;;
            5) _nat_status ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_nat_frp_install() {
    check_root
    local frp_dir="/opt/frp"
    if [[ -d "$frp_dir" ]]; then
        _warn "frp 目录已存在: $frp_dir"
        _confirm "是否重新安装？" || return
        rm -rf "$frp_dir"
    fi

    _info "获取最新 frp 版本..."
    local latest
    latest=$(curl -sL https://api.github.com/repos/fatedier/frp/releases/latest 2>/dev/null | grep '"tag_name":' | head -1 | cut -d'"' -f4)
    [[ -z "$latest" ]] && latest="v0.60.0"
    _info "最新版本: ${latest}"

    local arch
    case "$(uname -m)" in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l) arch="arm" ;;
        *) arch="amd64" ;;
    esac

    local download_url="https://github.com/fatedier/frp/releases/download/${latest}/frp_${latest#v}_linux_${arch}.tar.gz"
    local tmpfile="/tmp/frp.tar.gz"

    _info "下载 frp..."
    curl -sL "$download_url" -o "$tmpfile" 2>/dev/null || wget -q "$download_url" -O "$tmpfile" 2>/dev/null
    if [[ ! -f "$tmpfile" ]]; then
        _err "下载失败"
        return
    fi

    mkdir -p "$frp_dir"
    tar -xzf "$tmpfile" -C "$frp_dir" --strip-components=1 2>/dev/null
    rm -f "$tmpfile"

    if [[ ! -f "${frp_dir}/frpc" ]]; then
        _err "安装失败，未找到 frpc"
        return
    fi

    chmod +x "${frp_dir}"/frpc "${frp_dir}"/frps 2>/dev/null
    _ok "frp 安装完成: ${frp_dir}"
    echo -e "  ${C_D}frpc: ${frp_dir}/frpc${C_0}"
    echo -e "  ${C_D}frps: ${frp_dir}/frps${C_0}"
}

_nat_frpc_config() {
    check_root
    local frp_dir="/opt/frp"
    if [[ ! -d "$frp_dir" ]]; then
        _err "frp 未安装，请先安装"
        return
    fi

    local config="${frp_dir}/frpc.toml"
    _info "配置 frpc"
    read -rp "$(echo -e "${C_W}服务器地址 (frps IP/域名): ${C_0}")" server_addr
    [[ -z "$server_addr" ]] && { _err "服务器地址不能为空"; return; }
    read -rp "$(echo -e "${C_W}服务器端口 (默认 7000): ${C_0}")" server_port
    [[ -z "$server_port" ]] && server_port="7000"
    read -rp "$(echo -e "${C_W}认证 Token: ${C_0}")" token
    read -rp "$(echo -e "${C_W}本地服务端口 (如 8080): ${C_0}")" local_port
    [[ -z "$local_port" ]] && { _err "本地端口不能为空"; return; }
    read -rp "$(echo -e "${C_W}远程映射端口 (如 18080): ${C_0}")" remote_port
    [[ -z "$remote_port" ]] && remote_port="18080"
    read -rp "$(echo -e "${C_W}代理名称 (默认 web): ${C_0}")" proxy_name
    [[ -z "$proxy_name" ]] && proxy_name="web"

    cat > "$config" << EOF
serverAddr = "${server_addr}"
serverPort = ${server_port}
auth.method = "token"
auth.token = "${token}"

[[proxies]]
name = "${proxy_name}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${local_port}
remotePort = ${remote_port}
EOF

    _ok "frpc 配置已写入: $config"
    echo ""
    cat "$config"
}

_nat_frpc_control() {
    check_root
    local frp_dir="/opt/frp"
    if [[ ! -f "${frp_dir}/frpc" ]]; then
        _err "frpc 未安装"
        return
    fi

    local svc_file="/etc/systemd/system/frpc.service"
    if [[ ! -f "$svc_file" ]]; then
        _info "创建 systemd 服务..."
        cat > "$svc_file" << EOF
[Unit]
Description=frp client
After=network.target

[Service]
Type=simple
WorkingDirectory=${frp_dir}
ExecStart=${frp_dir}/frpc -c ${frp_dir}/frpc.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload 2>/dev/null
        systemctl enable frpc 2>/dev/null
        _ok "frpc systemd 服务已创建"
    fi

    echo -e "  ${C_G}1)${C_0} 启动  ${C_G}2)${C_0} 停止  ${C_G}3)${C_0} 重启  ${C_G}4)${C_0} 查看状态"
    read -rp "$(echo -e "${C_W}选择 [1-4]: ${C_0}")" fc
    case "$fc" in
        1) systemctl start frpc && _ok "frpc 已启动" ;;
        2) systemctl stop frpc && _ok "frpc 已停止" ;;
        3) systemctl restart frpc && _ok "frpc 已重启" ;;
        4) systemctl status frpc --no-pager | head -15 ;;
    esac
}

_nat_nps_install() {
    check_root
    local nps_dir="/opt/nps"
    if [[ -d "$nps_dir" ]]; then
        _warn "nps 目录已存在"
        _confirm "是否重新安装？" || return
        systemctl stop nps 2>/dev/null
        rm -rf "$nps_dir"
    fi

    _info "获取最新 nps 版本..."
    local latest
    latest=$(curl -sL https://api.github.com/repos/ehang-io/nps/releases/latest 2>/dev/null | grep '"tag_name":' | head -1 | cut -d'"' -f4)
    [[ -z "$latest" ]] && latest="v0.26.10"
    _info "最新版本: ${latest}"

    local arch
    case "$(uname -m)" in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l) arch="arm_v7" ;;
        *) arch="amd64" ;;
    esac

    local download_url="https://github.com/ehang-io/nps/releases/download/${latest}/linux_${arch}_server.tar.gz"
    local tmpfile="/tmp/nps.tar.gz"

    _info "下载 nps..."
    curl -sL "$download_url" -o "$tmpfile" 2>/dev/null || wget -q "$download_url" -O "$tmpfile" 2>/dev/null
    if [[ ! -f "$tmpfile" ]]; then
        _err "下载失败"
        return
    fi

    mkdir -p "$nps_dir"
    tar -xzf "$tmpfile" -C "$nps_dir" --strip-components=1 2>/dev/null
    rm -f "$tmpfile"

    if [[ ! -f "${nps_dir}/nps" ]]; then
        _err "安装失败"
        return
    fi

    chmod +x "${nps_dir}"/nps "${nps_dir}"/npc 2>/dev/null

    # 创建 systemd 服务
    cat > /etc/systemd/system/nps.service << EOF
[Unit]
Description=nps server
After=network.target

[Service]
Type=simple
WorkingDirectory=${nps_dir}
ExecStart=${nps_dir}/nps
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload 2>/dev/null
    systemctl enable nps 2>/dev/null
    systemctl start nps 2>/dev/null

    _ok "nps 安装完成"
    echo -e "  ${C_D}安装目录: ${nps_dir}${C_0}"
    echo -e "  ${C_D}管理面板: http://$(hostname -I 2>/dev/null | awk '{print $1}'):8080${C_0}"
    echo -e "  ${C_D}默认账号: admin / 123${C_0}"
}

_nat_status() {
    _info "内网穿透服务状态"
    _line

    if systemctl is-active frpc &>/dev/null; then
        _ok "frpc 运行中"
        systemctl status frpc --no-pager 2>/dev/null | head -8
    else
        _warn "frpc 未运行或未安装"
    fi
    echo ""

    if systemctl is-active nps &>/dev/null; then
        _ok "nps 运行中"
        systemctl status nps --no-pager 2>/dev/null | head -8
    else
        _warn "nps 未运行或未安装"
    fi
    echo ""

    if systemctl is-active frps &>/dev/null; then
        _ok "frps 运行中"
        systemctl status frps --no-pager 2>/dev/null | head -8
    else
        _warn "frps 未运行或未安装"
    fi
}

# ============================ 模块: 邮件告警 =============================
m_mail() {
    _title "邮件告警 - 邮件配置、测试、系统告警"
    while true; do
        echo -e "  ${C_G}1)${C_0} 配置邮件发送"
        echo -e "  ${C_G}2)${C_0} 发送测试邮件"
        echo -e "  ${C_G}3)${C_0} 查看邮件配置"
        echo -e "  ${C_G}4)${C_0} 设置系统告警"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-4]: ${C_0}")" choice
        case "$choice" in
            1) _mail_config ;; 2) _mail_test ;;
            3) _mail_view ;; 4) _mail_alert ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_mail_config() {
    check_root
    _info "选择邮件发送方式"
    echo -e "  ${C_G}1)${C_0} msmtp + mutt"
    echo -e "  ${C_G}2)${C_0} mailx ( heirloom-mailx )"
    read -rp "$(echo -e "${C_W}选择 [1-2]: ${C_0}")" mchoice

    read -rp "$(echo -e "${C_W}SMTP 服务器 (如 smtp.qq.com:587): ${C_0}")" smtp_server
    [[ -z "$smtp_server" ]] && { _err "SMTP 服务器不能为空"; return; }
    read -rp "$(echo -e "${C_W}发件人邮箱: ${C_0}")" from_email
    [[ -z "$from_email" ]] && { _err "发件人邮箱不能为空"; return; }
    read -rsp "$(echo -e "${C_W}邮箱密码/授权码: ${C_0}")" smtp_pass
    echo ""
    [[ -z "$smtp_pass" ]] && { _err "密码不能为空"; return; }
    read -rp "$(echo -e "${C_W}收件人邮箱 (默认同发件人): ${C_0}")" to_email
    [[ -z "$to_email" ]] && to_email="$from_email"

    case "$mchoice" in
        1)
            _pkg_install msmtp mutt 2>/dev/null || { _err "安装失败"; return; }
            mkdir -p /etc/msmtp
            cat > /etc/msmtprc << EOF
defaults
auth           on
tls            on
tls_starttls   on
logfile        /var/log/msmtp.log

account default
host           ${smtp_server%%:*}
port           ${smtp_server##*:}
from           ${from_email}
user           ${from_email}
password       ${smtp_pass}
EOF
            chmod 600 /etc/msmtprc
            ln -sf /usr/bin/msmtp /usr/sbin/sendmail 2>/dev/null
            _ok "msmtp 配置完成"
            ;;
        2)
            _pkg_install mailx 2>/dev/null || _pkg_install heirloom-mailx 2>/dev/null || { _err "安装失败"; return; }
            cat > /etc/mail.rc << EOF
set from=${from_email}
set smtp=${smtp_server}
set smtp-auth-user=${from_email}
set smtp-auth-password=${smtp_pass}
set smtp-auth=login
EOF
            _ok "mailx 配置完成"
            ;;
        *)
            _warn "无效选择"
            return
            ;;
    esac

    # 保存通用配置
    cat > /etc/tinytool_mail.conf << EOF
TO_EMAIL=${to_email}
FROM_EMAIL=${from_email}
METHOD=${mchoice}
EOF
    chmod 600 /etc/tinytool_mail.conf
    _ok "邮件配置已保存"
}

_mail_test() {
    check_root
    if [[ ! -f /etc/tinytool_mail.conf ]]; then
        _err "邮件未配置，请先配置"
        return
    fi
    source /etc/tinytool_mail.conf

    read -rp "$(echo -e "${C_W}收件人邮箱 (默认 ${TO_EMAIL}): ${C_0}")" test_to
    [[ -z "$test_to" ]] && test_to="$TO_EMAIL"

    _info "发送测试邮件到 ${test_to}..."
    local body="TinyTool 测试邮件\n\n时间: $(date)\n主机: $(hostname)\nIP: $(hostname -I 2>/dev/null | awk '{print $1}')"

    if [[ "$METHOD" == "1" ]]; then
        echo -e "$body" | mutt -s "TinyTool 测试邮件" "$test_to" 2>/dev/null && _ok "发送成功" || _err "发送失败"
    else
        echo -e "$body" | mail -s "TinyTool 测试邮件" "$test_to" 2>/dev/null && _ok "发送成功" || _err "发送失败"
    fi
}

_mail_view() {
    _info "当前邮件配置"
    _line
    if [[ -f /etc/tinytool_mail.conf ]]; then
        cat /etc/tinytool_mail.conf
    else
        _warn "未找到邮件配置"
    fi
    echo ""
    if [[ -f /etc/msmtprc ]]; then
        _info "msmtp 配置"
        _line
        cat /etc/msmtprc | grep -v password || true
    fi
    if [[ -f /etc/mail.rc ]]; then
        _info "mailx 配置"
        _line
        cat /etc/mail.rc | grep -v password || true
    fi
}

_mail_alert() {
    check_root
    if [[ ! -f /etc/tinytool_mail.conf ]]; then
        _err "邮件未配置，请先配置邮件发送"
        return
    fi
    source /etc/tinytool_mail.conf

    read -rp "$(echo -e "${C_W}磁盘使用率告警阈值 % (默认 90): ${C_0}")" disk_thresh
    [[ -z "$disk_thresh" ]] && disk_thresh="90"
    read -rp "$(echo -e "${C_W}内存使用率告警阈值 % (默认 90): ${C_0}")" mem_thresh
    [[ -z "$mem_thresh" ]] && mem_thresh="90"

    local script="/usr/local/bin/tinytool_alert.sh"
    cat > "$script" << 'EOF'
#!/bin/bash
source /etc/tinytool_mail.conf
DISK_THRESH=THRESH_DISK
MEM_THRESH=THRESH_MEM
HOST=$(hostname)
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
ALERT_MSG=""

# 磁盘检查
disk_usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
if [[ "$disk_usage" -ge "$DISK_THRESH" ]]; then
    ALERT_MSG="${ALERT_MSG}磁盘使用率告警: ${disk_usage}%\n"
fi

# 内存检查
mem_usage=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')
if [[ "$mem_usage" -ge "$MEM_THRESH" ]]; then
    ALERT_MSG="${ALERT_MSG}内存使用率告警: ${mem_usage}%\n"
fi

if [[ -n "$ALERT_MSG" ]]; then
    BODY="主机: ${HOST}\nIP: ${IP}\n时间: $(date)\n\n${ALERT_MSG}"
    if [[ "$METHOD" == "1" ]]; then
        echo -e "$BODY" | mutt -s "[告警] ${HOST} 资源异常" "$TO_EMAIL"
    else
        echo -e "$BODY" | mail -s "[告警] ${HOST} 资源异常" "$TO_EMAIL"
    fi
fi
EOF
    sed -i "s/THRESH_DISK/${disk_thresh}/g" "$script"
    sed -i "s/THRESH_MEM/${mem_thresh}/g" "$script"
    chmod +x "$script"

    read -rp "$(echo -e "${C_W}Cron 检查间隔 (如 '*/10 * * * *' 每10分钟): ${C_0}")" cronexp
    [[ -z "$cronexp" ]] && cronexp="*/10 * * * *"

    (crontab -l 2>/dev/null | grep -v "tinytool_alert"; echo "${cronexp} ${script}") | crontab -
    _ok "系统告警已设置"
    _info "告警脚本: ${script}"
    _info "检查间隔: ${cronexp}"
}

# ============================ 模块: LNMP/LAMP =============================
m_lnmp() {
    _title "LNMP/LAMP - 一键安装、状态、虚拟主机"
    while true; do
        echo -e "  ${C_G}1)${C_0} 一键安装 LNMP"
        echo -e "  ${C_G}2)${C_0} 一键安装 LAMP"
        echo -e "  ${C_G}3)${C_0} 查看 LNMP/LAMP 状态"
        echo -e "  ${C_G}4)${C_0} 添加虚拟主机"
        echo -e "  ${C_G}5)${C_0} 删除虚拟主机"
        echo -e "  ${C_G}0)${C_0} 返回主菜单"
        echo ""
        read -rp "$(echo -e "${C_W}选择 [0-5]: ${C_0}")" choice
        case "$choice" in
            1) _lnmp_install ;; 2) _lamp_install ;;
            3) _lnmp_status ;; 4) _lnmp_vhost_add ;;
            5) _lnmp_vhost_del ;;
            0) break ;; *) _warn "无效选择" ;;
        esac
        [[ "$choice" != "0" ]] && _pause
    done
}

_lnmp_install() {
    check_root
    if _has nginx && _has mysql 2>/dev/null || _has mariadb 2>/dev/null; then
        _warn "检测到已安装的 Web/DB 服务"
        _confirm "继续安装可能冲突，是否继续？" || return
    fi

    _info "正在安装 LNMP (Nginx + MySQL/MariaDB + PHP)..."
    if [[ "$PM" == "apt" ]]; then
        _pkg_install nginx
        _pkg_install mariadb-server mariadb-client || _pkg_install mysql-server mysql-client
        _pkg_install php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-zip
    else
        _pkg_install epel-release 2>/dev/null
        _pkg_install nginx
        _pkg_install mariadb-server mariadb || _pkg_install mysql-community-server
        _pkg_install php php-fpm php-mysqlnd php-gd php-mbstring php-xml php-zip
    fi

    systemctl enable nginx 2>/dev/null; systemctl start nginx 2>/dev/null
    systemctl enable php-fpm 2>/dev/null; systemctl start php-fpm 2>/dev/null
    systemctl enable mariadb 2>/dev/null; systemctl start mariadb 2>/dev/null || \
    systemctl enable mysql 2>/dev/null; systemctl start mysql 2>/dev/null

    _ok "LNMP 安装完成"
    _lnmp_status
}

_lamp_install() {
    check_root
    if _has httpd 2>/dev/null || _has apache2 2>/dev/null; then
        _warn "检测到已安装的 Apache"
        _confirm "继续安装可能冲突，是否继续？" || return
    fi

    _info "正在安装 LAMP (Apache + MySQL/MariaDB + PHP)..."
    if [[ "$PM" == "apt" ]]; then
        _pkg_install apache2
        _pkg_install mariadb-server mariadb-client || _pkg_install mysql-server mysql-client
        _pkg_install libapache2-mod-php php-mysql php-curl php-gd php-mbstring php-xml php-zip
        a2enmod php* 2>/dev/null || a2enmod mpm_prefork 2>/dev/null
    else
        _pkg_install httpd
        _pkg_install mariadb-server mariadb || _pkg_install mysql-community-server
        _pkg_install php php-mysqlnd php-gd php-mbstring php-xml php-zip
    fi

    systemctl enable apache2 2>/dev/null; systemctl start apache2 2>/dev/null || \
    systemctl enable httpd 2>/dev/null; systemctl start httpd 2>/dev/null
    systemctl enable mariadb 2>/dev/null; systemctl start mariadb 2>/dev/null || \
    systemctl enable mysql 2>/dev/null; systemctl start mysql 2>/dev/null

    _ok "LAMP 安装完成"
    _lnmp_status
}

_lnmp_status() {
    _info "Web 服务器状态"
    _line
    if systemctl is-active nginx &>/dev/null; then
        _ok "Nginx: 运行中"
        systemctl status nginx --no-pager 2>/dev/null | head -5
    elif systemctl is-active apache2 &>/dev/null || systemctl is-active httpd &>/dev/null; then
        _ok "Apache: 运行中"
        systemctl status apache2 --no-pager 2>/dev/null | head -5 || systemctl status httpd --no-pager 2>/dev/null | head -5
    else
        _warn "Web 服务器未运行"
    fi
    echo ""

    _info "数据库状态"
    _line
    if systemctl is-active mariadb &>/dev/null; then
        _ok "MariaDB: 运行中"
        systemctl status mariadb --no-pager 2>/dev/null | head -5
    elif systemctl is-active mysql &>/dev/null; then
        _ok "MySQL: 运行中"
        systemctl status mysql --no-pager 2>/dev/null | head -5
    else
        _warn "数据库未运行"
    fi
    echo ""

    _info "PHP 状态"
    _line
    if systemctl is-active php-fpm &>/dev/null; then
        _ok "PHP-FPM: 运行中"
        php -v 2>/dev/null | head -1
    elif systemctl is-active php*-fpm &>/dev/null; then
        _ok "PHP-FPM: 运行中"
        php -v 2>/dev/null | head -1
    else
        _warn "PHP-FPM 未运行或未安装"
    fi
}

_lnmp_vhost_add() {
    check_root
    read -rp "$(echo -e "${C_W}域名 (如 example.com): ${C_0}")" domain
    [[ -z "$domain" ]] && { _err "域名不能为空"; return; }
    read -rp "$(echo -e "${C_W}网站目录 (默认 /var/www/${domain}): ${C_0}")" vhost_dir
    [[ -z "$vhost_dir" ]] && vhost_dir="/var/www/${domain}"
    mkdir -p "$vhost_dir"

    echo -e "  ${C_G}1)${C_0} Nginx  ${C_G}2)${C_0} Apache"
    read -rp "$(echo -e "${C_W}选择 Web 服务器 [1-2]: ${C_0}")" ws

    case "$ws" in
        1)
            if ! _has nginx; then
                _err "Nginx 未安装"
                return
            fi
            local conf
            if [[ -d /etc/nginx/sites-available ]]; then
                conf="/etc/nginx/sites-available/${domain}"
                cat > "$conf" << EOF
server {
    listen 80;
    server_name ${domain} www.${domain};
    root ${vhost_dir};
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \\.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php-fpm.sock;
    }
}
EOF
                ln -sf "$conf" "/etc/nginx/sites-enabled/${domain}" 2>/dev/null
            else
                conf="/etc/nginx/conf.d/${domain}.conf"
                cat > "$conf" << EOF
server {
    listen 80;
    server_name ${domain} www.${domain};
    root ${vhost_dir};
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \\.php$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        include fastcgi_params;
    }
}
EOF
            fi
            nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null && _ok "Nginx 虚拟主机已创建"
            ;;
        2)
            if ! _has apache2 && ! _has httpd; then
                _err "Apache 未安装"
                return
            fi
            if [[ -d /etc/apache2/sites-available ]]; then
                local conf="/etc/apache2/sites-available/${domain}.conf"
                cat > "$conf" << EOF
<VirtualHost *:80>
    ServerName ${domain}
    ServerAlias www.${domain}
    DocumentRoot ${vhost_dir}
    <Directory ${vhost_dir}>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/${domain}-error.log
    CustomLog \${APACHE_LOG_DIR}/${domain}-access.log combined
</VirtualHost>
EOF
                a2ensite "${domain}.conf" 2>/dev/null
                systemctl reload apache2 2>/dev/null && _ok "Apache 虚拟主机已创建"
            else
                local conf="/etc/httpd/conf.d/${domain}.conf"
                cat > "$conf" << EOF
<VirtualHost *:80>
    ServerName ${domain}
    ServerAlias www.${domain}
    DocumentRoot ${vhost_dir}
    <Directory ${vhost_dir}>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog /var/log/httpd/${domain}-error.log
    CustomLog /var/log/httpd/${domain}-access.log combined
</VirtualHost>
EOF
                systemctl reload httpd 2>/dev/null && _ok "Apache 虚拟主机已创建"
            fi
            ;;
        *)
            _warn "无效选择"
            return
            ;;
    esac

    # 创建默认 index 文件
    cat > "${vhost_dir}/index.html" << EOF
<!DOCTYPE html>
<html><head><title>Welcome ${domain}</title></head>
<body><h1>${domain} is working!</h1></body></html>
EOF
    chown -R www-data:www-data "$vhost_dir" 2>/dev/null || chown -R apache:apache "$vhost_dir" 2>/dev/null || chown -R nginx:nginx "$vhost_dir" 2>/dev/null
    _ok "网站目录: ${vhost_dir}"
}

_lnmp_vhost_del() {
    check_root
    read -rp "$(echo -e "${C_W}输入要删除的域名: ${C_0}")" domain
    [[ -z "$domain" ]] && return

    _confirm "确认删除 ${domain} 的虚拟主机配置？" || return

    # Nginx
    rm -f "/etc/nginx/sites-enabled/${domain}" 2>/dev/null
    rm -f "/etc/nginx/sites-available/${domain}" 2>/dev/null
    rm -f "/etc/nginx/conf.d/${domain}.conf" 2>/dev/null

    # Apache
    a2dissite "${domain}.conf" 2>/dev/null
    rm -f "/etc/apache2/sites-available/${domain}.conf" 2>/dev/null
    rm -f "/etc/httpd/conf.d/${domain}.conf" 2>/dev/null

    systemctl reload nginx 2>/dev/null
    systemctl reload apache2 2>/dev/null
    systemctl reload httpd 2>/dev/null
    _ok "虚拟主机配置已删除"

    read -rp "$(echo -e "${C_W}是否同时删除网站目录 /var/www/${domain} [y/N]: ${C_0}")" deldir
    if [[ "$deldir" =~ ^[Yy]$ ]]; then
        rm -rf "/var/www/${domain}" 2>/dev/null
        _ok "网站目录已删除"
    fi
}

# ============================ 入口 ==========================================
main() {
    check_root
    detect_system
    self_update
    env_repair
    main_menu
}

main "$@"
