#!/bin/bash
# ============================================================================
#  TinyTool - 一条命令，开启自动化运维旅程
#  Author : Hayoko
#  Site   : tinytool.hayoko.cn
#  Desc   : 极简、高效、自动化的 Linux 运维工具
#           自动适配 CentOS / Ubuntu / Debian
# ============================================================================

readonly VERSION="1.0.0"
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
        remote_ver=$(grep -m1 'readonly VERSION=' "$tmp" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
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
  ╔══════════════════════════════════════════════╗
  ║          _   _ _   _               _         ║
  ║         | |_(_) |_| |_ _ __  ___| |__        ║
  ║         | __| | __| __| '_ \/ __| '_ \       ║
  ║         | |_| | |_| |_| |_) \__ \ | | |      ║
  ║          \__|_|\__|\__| .__/|___/_| |_|      ║
  ║                       |_|                     ║
  ║        一条命令，开启自动化运维旅程           ║
  ╚══════════════════════════════════════════════╝
BANNER
    echo -e "${C_0}"
    echo -e "  ${C_D}版本:${C_0} v${VERSION}  ${C_D}系统:${C_0} ${SYS^} ${SYS_VER}  ${C_D}架构:${C_0} ${ARCH}  ${C_D}包管:${C_0} ${PM}"
    _line
}

main_menu() {
    while true; do
        show_banner
        echo -e "  ${C_G}1)${C_0}  系统自检······················健康度检测与报告"
        echo -e "  ${C_G}2)${C_0}  软件源管理····················更换国内镜像源"
        echo -e "  ${C_G}3)${C_0}  存储管理······················挂载、扩容、占用分析"
        echo -e "  ${C_G}4)${C_0}  系统管理······················系统更新、时区、Swap"
        echo -e "  ${C_G}5)${C_0}  DNS 管理·······················切换、测试、恢复"
        echo -e "  ${C_G}6)${C_0}  网络管理······················SSH端口、防火墙、测速、邮件检测"
        echo -e "  ${C_G}7)${C_0}  SSH 管理······················SSH配置查看与安全加固"
        echo -e "  ${C_G}8)${C_0}  宝塔管理······················安装、密码、挂载数据盘"
        echo -e "  ${C_G}9)${C_0}  Caddy 管理·····················安装、卸载、状态"
        echo -e "  ${C_G}10)${C_0} Docker 管理····················安装、迁移、清理"
        echo -e "  ${C_G}11)${C_0} 进程监控······················实时进程查看与管理"
        echo -e "  ${C_G}12)${C_0} 日志工具······················系统日志快速查看"
        echo -e "  ${C_G}13)${C_0} 定时任务······················Crontab 管理"
        echo -e "  ${C_G}14)${C_0} 配置导出······················系统配置一键导出"
        echo -e "  ${C_G}15)${C_0} 1Panel 管理···················安装、信息、密码、卸载"
        echo -e "  ${C_R}0)${C_0}  退出程序"
        echo ""
        _line

        read -rp "$(echo -e "${C_W}请选择 [0-15]: ${C_0}")" choice
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
            11) m_process ;;
            12) m_logs ;;
            13) m_cron ;;
            14) m_export ;;
            15) m_1panel ;;
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
            delay=$(ping -c2 -W2 "$target" 2>/dev/null | tail -1 | grep -oE '=[0-9.]+/' | tr -d '=/')
            printf "  ${C_G}√${C_0} %-25s %-8s 延迟 %sms\n" "$target" "[$label]" "${delay:-N/A}"
        else
            printf "  ${C_R}×${C_0} %-25s %-8s 不通\n" "$target" "[$label]"
        fi
    done
    echo ""
    _info "下载速度测试"
    _line
    local speed
    speed=$(curl -o /dev/null -s -w '%{speed_download}' --max-time 5 "https://mirrors.aliyun.com/centos/timestamp.txt" 2>/dev/null)
    if [[ -n "$speed" && "$speed" != "0.000" ]]; then
        local speed_mb
        speed_mb=$(awk "BEGIN{printf \"%.1f\", ${speed}/1048576}")
        echo -e "  下载速度: ${C_W}${speed_mb} MB/s${C_0}"
    else
        _warn "下载测试失败"
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
        "阿里云镜像|https://mirrors.aliyun.com/centos/timestamp.txt"
        "腾讯云镜像|https://mirrors.cloud.tencent.com/centos/timestamp.txt"
        "华为云镜像|https://mirrors.huaweicloud.com/centos/timestamp.txt"
        "清华源|https://mirrors.tuna.tsinghua.edu.cn/centos/timestamp.txt"
        "中科大源|https://mirrors.ustc.edu.cn/centos/timestamp.txt"
    )

    local results=()

    for entry in "${nodes[@]}"; do
        local name="${entry%%|*}"
        local url="${entry##*|}"
        # 使用 curl 测速：下载 5 秒
        local speed size time_s http_code
        local output
        output=$(curl -o /dev/null -s -w '%{speed_download} %{size_download} %{time_total} %{http_code}' \
            --max-time 8 --connect-timeout 4 "$url" 2>/dev/null)
        read -r speed size time_s http_code <<< "$output"

        if [[ "$http_code" =~ ^2 && "$speed" != "0.000" ]]; then
            local speed_mb
            speed_mb=$(awk "BEGIN{printf \"%.2f\", ${speed}/1048576}")
            printf "  ${C_G}%-12s${C_0} 下载: ${C_W}%7s MB/s${C_0}  耗时: ${C_D}%ss${C_0}\n" "$name" "$speed_mb" "${time_s}"
            results+=("${name}|${speed_mb}")
        else
            printf "  ${C_R}%-12s${C_0} 连接失败或超时\n" "$name"
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
        local avg
        avg=$(awk "BEGIN{printf \"%.2f\", ${total}/${count}}")
        echo -e "  ${C_P}平均下载速度: ${C_W}${avg} MB/s${C_0} (${count} 个节点)"
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

# ============================ 入口 ==========================================
main() {
    check_root
    detect_system
    self_update
    env_repair
    main_menu
}

main "$@"
