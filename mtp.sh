#!/usr/bin/env bash
#=========================================================
#   System Required: CentOS 7+ / Debian 8+ / Ubuntu 16+ / Alpine
#   Description: MTProxy (Go version) One-click Installer
#   Github: https://github.com/9seconds/mtg
#   Optimized by: You
#=========================================================

# 颜色定义
Red="\033[31m"
Green="\033[32m"
Yellow="\033[33m"
Blue="\033[34m"
Nc="\033[0m"

set -u

# --- 全局配置 ---
BIN_PATH="/usr/local/bin/mtg"
MTP_CMD="/usr/local/bin/mtp"
CONFIG_DIR="/etc/mtg"
DEFAULT_VERSION="v2.1.7"
# 指向你自己的仓库，确保生成的快捷指令 'mtp' 拉取的是这个脚本
SCRIPT_URL="https://raw.githubusercontent.com/weaponchiang/MTProxy/main/mtp.sh"

# --- 1. 系统检查与依赖 ---

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${Red}错误: 本脚本必须以 root 用户运行！${Nc}"
        exit 1
    fi
}

check_init_system() {
    if [ -f /etc/alpine-release ] || [ -f /sbin/openrc-run ]; then
        INIT_SYSTEM="openrc"
    elif command -v systemctl >/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
    else
        echo -e "${Red}错误: 仅支持 Systemd 或 OpenRC 系统。${Nc}"
        exit 1
    fi
}

check_deps() {
    echo -e "${Blue}正在检查系统依赖...${Nc}"
    if command -v apk >/dev/null 2>&1; then
        PM="apk"
        PM_INSTALL="apk add --no-cache"
    elif command -v apt-get >/dev/null 2>&1; then
        PM="apt-get"
        PM_INSTALL="apt-get install -y"
        $PM update -q
    elif command -v yum >/dev/null 2>&1; then
        PM="yum"
        PM_INSTALL="yum install -y"
    else
        echo -e "${Red}未检测到支持的包管理器。${Nc}"
        return
    fi

    deps="curl wget tar grep coreutils ca-certificates"
    for dep in $deps; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo -e "安装依赖: ${Yellow}$dep${Nc}"
            $PM_INSTALL $dep
        fi
    done
}

sync_time() {
    echo -e "${Blue}正在同步系统时间...${Nc}"
    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl set-ntp true 2>/dev/null
    fi
    date -s "$(curl -sI g.cn | grep Date | cut -d' ' -f3-6)Z" >/dev/null 2>&1
    echo -e "${Green}时间同步完成。${Nc}"
}

detect_arch() {
    arch=$(uname -m)
    case "$arch" in
        x86_64) echo "amd64" ;;
        i386|i686) echo "386" ;;
        aarch64) echo "arm64" ;;
        armv7l) echo "armv7" ;;
        *) echo "unsupported" ;;
    esac
}

get_latest_version() {
    latest_version=$(curl -s https://api.github.com/repos/9seconds/mtg/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$latest_version" ]; then
        echo "$DEFAULT_VERSION"
    else
        echo "$latest_version"
    fi
}

# --- 2. 核心功能函数 ---

open_port() {
    local PORT=$1
    echo -e "${Blue}正在尝试开放防火墙端口: ${PORT}...${Nc}"
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --zone=public --add-port=${PORT}/tcp --permanent
        firewall-cmd --reload
    fi
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        ufw allow ${PORT}/tcp
    fi
    if command -v iptables >/dev/null 2>&1; then
        if ! iptables -C INPUT -p tcp --dport ${PORT} -j ACCEPT 2>/dev/null; then
            iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
            if command -v netfilter-persistent >/dev/null 2>&1; then
                netfilter-persistent save 2>/dev/null
            elif command -v service >/dev/null 2>&1; then
                 service iptables save 2>/dev/null
            fi
        fi
    fi
}

close_port() {
    local PORT=$1
    echo -e "${Blue}正在关闭防火墙端口: ${PORT}...${Nc}"
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --zone=public --remove-port=${PORT}/tcp --permanent 2>/dev/null
        firewall-cmd --reload 2>/dev/null
    fi
    if command -v ufw >/dev/null 2>&1; then ufw delete allow ${PORT}/tcp >/dev/null 2>&1; fi
    if command -v iptables >/dev/null 2>&1; then
        iptables -D INPUT -p tcp --dport ${PORT} -j ACCEPT 2>/dev/null
        if command -v netfilter-persistent >/dev/null 2>&1; then netfilter-persistent save 2>/dev/null; fi
    fi
}

install_mtg() {
    check_deps
    sync_time
    ARCH=$(detect_arch)
    if [ "$ARCH" = "unsupported" ]; then 
        echo -e "${Red}不支持的架构: $(uname -m)${Nc}"
        exit 1
    fi

    echo -e "${Blue}正在获取最新版本信息...${Nc}"
    VERSION=$(get_latest_version)
    VER_NUM=${VERSION#v}
    FILENAME="mtg-${VER_NUM}-linux-${ARCH}.tar.gz"
    DOWNLOAD_URL="https://github.com/9seconds/mtg/releases/download/${VERSION}/${FILENAME}"

    TMP_DIR=$(mktemp -d)
    if ! wget -q --show-progress -O "${TMP_DIR}/${FILENAME}" "$DOWNLOAD_URL"; then
        echo -e "${Red}下载失败！${Nc}"
        rm -rf "$TMP_DIR"
        exit 1
    fi

    tar -xzf "${TMP_DIR}/${FILENAME}" -C "${TMP_DIR}"
    BINARY=$(find "${TMP_DIR}" -type f -name mtg | head -n 1)
    if [ -f "$BINARY" ]; then
        mv "$BINARY" "$BIN_PATH"
        chmod +x "$BIN_PATH"
    else
        rm -rf "$TMP_DIR"; exit 1
    fi
    rm -rf "$TMP_DIR"

    # 安装快捷指令
    wget -q -O "$MTP_CMD" "$SCRIPT_URL" && chmod +x "$MTP_CMD"
    
    configure_mtg
}

configure_mtg() {
    mkdir -p "$CONFIG_DIR"
    echo -e "${Yellow}--- 配置 FakeTLS 模式 ---${Nc}"
    read -p "请输入伪装域名 (默认: www.microsoft.com): " DOMAIN
    DOMAIN=${DOMAIN:-www.microsoft.com}
    
    echo "正在生成密钥..."
    SECRET=$($BIN_PATH generate-secret --hex "$DOMAIN")
    
    read -p "请输入监听端口 (默认随机): " PORT
    if [ -z "$PORT" ]; then PORT=$((10000 + RANDOM % 20000)); fi

    echo "PORT=${PORT}" > "${CONFIG_DIR}/config"
    echo "SECRET=${SECRET}" >> "${CONFIG_DIR}/config"
    echo "DOMAIN=${DOMAIN}" >> "${CONFIG_DIR}/config"

    open_port "$PORT"
    install_service "$PORT" "$SECRET"
}

# --- 新增：修改配置功能 ---
modify_config() {
    if [ ! -f "${CONFIG_DIR}/config" ]; then
        echo -e "${Red}未检测到安装，请先选择选项 1 安装。${Nc}"
        return
    fi
    source "${CONFIG_DIR}/config"
    OLD_PORT=$PORT
    OLD_DOMAIN=$DOMAIN

    echo -e "${Yellow}--- 修改当前配置 ---${Nc}"
    read -p "请输入新端口 (当前: $OLD_PORT): " NEW_PORT
    NEW_PORT=${NEW_PORT:-$OLD_PORT}

    read -p "请输入新伪装域名 (当前: $OLD_DOMAIN): " NEW_DOMAIN
    NEW_DOMAIN=${NEW_DOMAIN:-$OLD_DOMAIN}

    # 如果信息没变则跳过
    if [ "$NEW_PORT" == "$OLD_PORT" ] && [ "$NEW_DOMAIN" == "$OLD_DOMAIN" ]; then
        echo -e "${Yellow}配置未发生改变。${Nc}"
        return
    fi

    echo -e "${Blue}正在更新配置...${Nc}"
    
    # 重新生成 Secret (域名变了 Secret 必须变)
    NEW_SECRET=$($BIN_PATH generate-secret --hex "$NEW_DOMAIN")

    # 处理防火墙
    if [ "$NEW_PORT" != "$OLD_PORT" ]; then
        close_port "$OLD_PORT"
        open_port "$NEW_PORT"
    fi

    # 写入新配置
    echo "PORT=${NEW_PORT}" > "${CONFIG_DIR}/config"
    echo "SECRET=${NEW_SECRET}" >> "${CONFIG_DIR}/config"
    echo "DOMAIN=${NEW_DOMAIN}" >> "${CONFIG_DIR}/config"

    # 更新服务并重启
    install_service "$NEW_PORT" "$NEW_SECRET"
    echo -e "${Green}配置修改完成！${Nc}"
}

install_service() {
    PORT=$1
    SECRET=$2
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        cat > /etc/systemd/system/mtg.service <<EOF
[Unit]
Description=MTG Proxy Service
After=network.target

[Service]
Type=simple
ExecStart=${BIN_PATH} simple-run 0.0.0.0:${PORT} ${SECRET}
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable mtg
        systemctl restart mtg
    else
        cat > /etc/init.d/mtg <<EOF
#!/sbin/openrc-run
name="mtg"
command="${BIN_PATH}"
command_args="simple-run 0.0.0.0:${PORT} ${SECRET}"
command_background=true
pidfile="/run/mtg.pid"
depend() { need net; }
EOF
        chmod +x /etc/init.d/mtg
        rc-update add mtg default
        rc-service mtg restart
    fi
    sleep 2
    check_status_bool && show_info
}

# --- 3. 管理功能 ---

show_info() {
    if [ ! -f "${CONFIG_DIR}/config" ]; then return; fi
    source "${CONFIG_DIR}/config"
    IPV4=$(curl -s4 --connect-timeout 3 ip.sb 2>/dev/null)
    echo -e "\n${Green}======= MTProxy 配置信息 =======${Nc}"
    echo -e "端口  : ${Yellow}${PORT}${Nc}"
    echo -e "密钥  : ${Yellow}${SECRET}${Nc}"
    echo -e "域名  : ${Blue}${DOMAIN}${Nc}"
    [ -n "$IPV4" ] && echo -e "链接  : ${Green}tg://proxy?server=${IPV4}&port=${PORT}&secret=${SECRET}${Nc}"
    echo -e "================================\n"
}

enable_bbr() {
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        echo -e "${Green}BBR 已经开启。${Nc}"
    else
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
        echo -e "${Green}BBR 开启成功！${Nc}"
    fi
}

uninstall_mtg() {
    read -p "确定要完全卸载吗？(y/n): " confirm
    [[ "$confirm" != "y" ]] && return
    if [ -f "${CONFIG_DIR}/config" ]; then
        source "${CONFIG_DIR}/config"
        close_port "$PORT"
    fi
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl stop mtg && systemctl disable mtg
        rm -f /etc/systemd/system/mtg.service
    else
        rc-service mtg stop && rc-update del mtg default
        rm -f /etc/init.d/mtg
    fi
    rm -f "$BIN_PATH" "$MTP_CMD"
    rm -rf "$CONFIG_DIR"
    echo -e "${Green}卸载清理完毕。${Nc}"
}

# --- 4. 状态检测与菜单 ---

check_status_bool() {
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl is-active --quiet mtg
    else
        pgrep -x "mtg" >/dev/null
    fi
}

check_status_display() {
    if [ ! -f "$BIN_PATH" ]; then echo -e "${Red}未安装${Nc}"
    elif check_status_bool; then echo -e "${Green}运行中${Nc}"
    else echo -e "${Red}已停止${Nc}"; fi
}

menu() {
    clear
    echo -e "${Green}MTProxy (Go版) 一键管理脚本${Nc}"
    echo -e "----------------------------"
    echo -e "当前状态: $(check_status_display)"
    echo -e "----------------------------"
    echo -e "1. 安装 MTProxy"
    echo -e "2. 修改 配置信息 (端口/域名)"
    echo -e "3. 查看 链接信息"
    echo -e "4. 开启 BBR 加速"
    echo -e "5. 停止 服务"
    echo -e "6. 重启 服务"
    echo -e "7. 卸载 MTProxy"
    echo -e "0. 退出"
    echo -e "----------------------------"
    read -p "请选择 [0-7]: " choice
    case "$choice" in
        1) install_mtg ;;
        2) modify_config ;;
        3) show_info ;;
        4) enable_bbr ;;
        5) if [ "$INIT_SYSTEM" = "systemd" ]; then systemctl stop mtg; else rc-service mtg stop; fi ;;
        6) if [ "$INIT_SYSTEM" = "systemd" ]; then systemctl restart mtg; else rc-service mtg restart; fi ;;
        7) uninstall_mtg ;;
        0) exit 0 ;;
        *) echo "无效输入" ;;
    esac
}

check_root
check_init_system
if [ $# -gt 0 ]; then
    case "$1" in
        install) install_mtg ;;
        uninstall) uninstall_mtg ;;
        info) show_info ;;
        *) echo "Usage: $0 {install|uninstall|info}" ;;
    esac
else
    menu
fi
