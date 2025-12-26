#!/usr/bin/env bash
#=========================================================
#   System Required: CentOS 7+ / Debian 8+ / Ubuntu 16+ / Alpine
#   Description: MTProxy (Go version) One-click Installer
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

# 修正后的版本获取函数
get_version_info() {
    # 获取本地版本: 尝试匹配 vX.X.X 格式
    if [ -f "$BIN_PATH" ]; then
        LOCAL_VER=$($BIN_PATH version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
        if [ -z "$LOCAL_VER" ]; then
            # 备选方案：直接取输出的第二个字段
            LOCAL_VER=$($BIN_PATH version 2>/dev/null | awk '{print $2}')
        fi
        [ -z "$LOCAL_VER" ] && LOCAL_VER="未知"
    else
        LOCAL_VER="未安装"
    fi

    # 获取远程最新版本
    REMOTE_VER=$(curl -s https://api.github.com/repos/9seconds/mtg/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [ -z "$REMOTE_VER" ] && REMOTE_VER="获取失败"
}

# --- 2. 防火墙操作 ---

open_port() {
    local PORT=$1
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --zone=public --add-port=${PORT}/tcp --permanent && firewall-cmd --reload
    fi
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        ufw allow ${PORT}/tcp
    fi
    iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT 2>/dev/null
}

close_port() {
    local PORT=$1
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --zone=public --remove-port=${PORT}/tcp --permanent && firewall-cmd --reload
    fi
    if command -v ufw >/dev/null 2>&1; then ufw delete allow ${PORT}/tcp >/dev/null 2>&1; fi
    iptables -D INPUT -p tcp --dport ${PORT} -j ACCEPT 2>/dev/null
}

# --- 3. 核心功能 ---

update_script() {
    echo -e "${Blue}正在更新管理脚本...${Nc}"
    TMP_FILE=$(mktemp)
    if wget -qO "$TMP_FILE" "$SCRIPT_URL"; then
        mv "$TMP_FILE" "$MTP_CMD" && chmod +x "$MTP_CMD"
        cp "$MTP_CMD" "$0" 2>/dev/null
        echo -e "${Green}脚本更新成功！请重新输入 mtp 运行。${Nc}"
        exit 0
    else
        echo -e "${Red}更新失败，请检查网络。${Nc}"
    fi
}

install_mtg() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        *) echo -e "${Red}不支持的架构: $ARCH${Nc}"; exit 1 ;;
    esac

    get_version_info
    VERSION=${REMOTE_VER}
    [[ "$VERSION" == "获取失败" || -z "$VERSION" ]] && VERSION=$DEFAULT_VERSION
    
    VER_NUM=${VERSION#v}
    DOWNLOAD_URL="https://github.com/9seconds/mtg/releases/download/${VERSION}/mtg-${VER_NUM}-linux-${ARCH}.tar.gz"
    
    echo -e "${Blue}正在安装核心版本: ${VERSION}...${Nc}"
    TMP_DIR=$(mktemp -d)
    if wget -qO- "$DOWNLOAD_URL" | tar xz -C "$TMP_DIR"; then
        BINARY=$(find "$TMP_DIR" -type f -name mtg | head -n 1)
        mv "$BINARY" "$BIN_PATH" && chmod +x "$BIN_PATH"
        rm -rf "$TMP_DIR"
    else
        echo -e "${Red}下载核心文件失败！${Nc}"; rm -rf "$TMP_DIR"; return
    fi
    
    wget -qO "$MTP_CMD" "$SCRIPT_URL" && chmod +x "$MTP_CMD"
    configure_mtg
}

configure_mtg() {
    mkdir -p "$CONFIG_DIR"
    echo -e "${Yellow}--- 配置 FakeTLS ---${Nc}"
    read -p "请输入伪装域名 (默认: www.microsoft.com): " DOMAIN
    DOMAIN=${DOMAIN:-www.microsoft.com}
    SECRET=$($BIN_PATH generate-secret --hex "$DOMAIN")
    read -p "请输入端口 (默认随机): " PORT
    PORT=${PORT:-$((10000 + RANDOM % 20000))}

    echo -e "PORT=${PORT}\nSECRET=${SECRET}\nDOMAIN=${DOMAIN}" > "${CONFIG_DIR}/config"
    open_port "$PORT"
    install_service "$PORT" "$SECRET"
}

modify_config() {
    if [ ! -f "${CONFIG_DIR}/config" ]; then echo -e "${Red}未安装，请先执行选项 1${Nc}"; return; fi
    source "${CONFIG_DIR}/config"
    OLD_PORT=$PORT
    
    read -p "新端口 (当前: $PORT): " NEW_PORT
    NEW_PORT=${NEW_PORT:-$PORT}
    read -p "新域名 (当前: $DOMAIN): " NEW_DOMAIN
    NEW_DOMAIN=${NEW_DOMAIN:-$DOMAIN}

    [ "$NEW_PORT" != "$OLD_PORT" ] && close_port "$OLD_PORT" && open_port "$NEW_PORT"
    
    NEW_SECRET=$($BIN_PATH generate-secret --hex "$NEW_DOMAIN")
    echo -e "PORT=${NEW_PORT}\nSECRET=${NEW_SECRET}\nDOMAIN=${NEW_DOMAIN}" > "${CONFIG_DIR}/config"
    
    install_service "$NEW_PORT" "$NEW_SECRET"
    echo -e "${Green}配置已更新。${Nc}"
}

install_service() {
    PORT=$1; SECRET=$2
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        cat > /etc/systemd/system/mtg.service <<EOF
[Unit]
Description=MTProxy Go Service
After=network.target
[Service]
ExecStart=${BIN_PATH} simple-run 0.0.0.0:${PORT} ${SECRET}
Restart=always
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload && systemctl restart mtg && systemctl enable mtg
    else
        cat > /etc/init.d/mtg <<EOF
#!/sbin/openrc-run
command="${BIN_PATH}"
command_args="simple-run 0.0.0.0:${PORT} ${SECRET}"
command_background=true
pidfile="/run/mtg.pid"
EOF
        chmod +x /etc/init.d/mtg && rc-service mtg restart && rc-update add mtg default
    fi
    show_info
}

show_info() {
    if [ ! -f "${CONFIG_DIR}/config" ]; then echo -e "${Red}暂无配置信息${Nc}"; return; fi
    source "${CONFIG_DIR}/config"
    
    echo -e "${Blue}正在获取 IP 地址 (IPv6 探测约需几秒)...${Nc}"
    # 使用多个源提高成功率
    IP4=$(curl -s4 --connect-timeout 5 ip.sb || curl -s4 --connect-timeout 5 ipinfo.io/ip)
    IP6=$(curl -s6 --connect-timeout 5 ip.sb || curl -s6 --connect-timeout 5 icanhazip.com)
    
    echo -e "\n${Green}======= MTProxy 配置信息 =======${Nc}"
    echo -e "端口  : ${Yellow}${PORT}${Nc}"
    echo -e "域名  : ${Blue}${DOMAIN}${Nc}"
    echo -e "密钥  : ${Yellow}${SECRET}${Nc}"
    
    [ -n "$IP4" ] && echo -e "IPv4链接: ${Green}tg://proxy?server=${IP4}&port=${PORT}&secret=${SECRET}${Nc}"
    [ -n "$IP6" ] && echo -e "IPv6链接: ${Green}tg://proxy?server=[${IP6}]&port=${PORT}&secret=${SECRET}${Nc}"
    echo -e "================================\n"
}

# --- 菜单界面 ---

menu() {
    get_version_info
    clear
    echo -e "${Green}MTProxy (Go版) 管理脚本${Nc}"
    echo -e "----------------------------"
    echo -e "本地版本: ${Blue}${LOCAL_VER}${Nc}"
    echo -e "最新版本: ${Yellow}${REMOTE_VER}${Nc}"
    echo -e "----------------------------"
    
    if [ ! -f "$BIN_PATH" ]; then STATUS="${Red}未安装${Nc}"
    elif pgrep -x "mtg" >/dev/null; then STATUS="${Green}运行中${Nc}"
    else STATUS="${Red}已停止${Nc}"; fi
    
    echo -e "当前状态: $STATUS"
    echo -e "----------------------------"
    echo -e "1. 安装 / 覆盖安装 MTProxy"
    echo -e "2. 修改 配置 (端口/域名)"
    echo -e "3. 查看 链接信息"
    echo -e "4. 更新 管理脚本 (mtp.sh)"
    echo -e "5. 重启 服务"
    echo -e "6. 停止 服务"
    echo -e "7. 卸载 MTProxy"
    echo -e "0. 退出"
    echo -e "----------------------------"
    read -p "请选择 [0-7]: " choice
    case "$choice" in
        1) install_mtg ;;
        2) modify_config ;;
        3) show_info ;;
        4) update_script ;;
        5) systemctl restart mtg 2>/dev/null || rc-service mtg restart 2>/dev/null; echo -e "${Green}已尝试重启服务${Nc}" ;;
        6) systemctl stop mtg 2>/dev/null || rc-service mtg stop 2>/dev/null; echo -e "${Yellow}已尝试停止服务${Nc}" ;;
        7) 
            [ -f "${CONFIG_DIR}/config" ] && source "${CONFIG_DIR}/config" && close_port "$PORT"
            systemctl stop mtg 2>/dev/null; systemctl disable mtg 2>/dev/null
            rm -rf "$CONFIG_DIR" "$BIN_PATH" /etc/systemd/system/mtg.service /etc/init.d/mtg
            echo -e "${Green}卸载完成。${Nc}" ;;
        0) exit 0 ;;
        *) echo "无效选择" ;;
    esac
}

check_root
check_init_system
menu
