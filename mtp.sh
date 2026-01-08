#!/usr/bin/env bash
#=========================================================
#   System Required: CentOS 7+ / Debian 8+ / Ubuntu 16+
#   Description: MTProxy (Go & Python) One-click Installer
#   Optimized: Debian 13 Fix, IPv6, Smart Status, Fast Clean
#=========================================================

Red="\033[31m"
Green="\033[32m"
Yellow="\033[33m"
Blue="\033[34m"
Nc="\033[0m"

# 取消严格模式，确保环境安装不中断
set +u

BIN_PATH="/usr/local/bin/mtg"
PY_DIR="/opt/mtprotoproxy"
MTP_CMD="/usr/local/bin/mtp"
CONFIG_DIR="/etc/mtg"
SERVICE_FILE="/etc/systemd/system/mtg.service"
SCRIPT_URL="https://raw.githubusercontent.com/weaponchiang/MTProxy/main/mtp.sh"

check_root() { [[ "$(id -u)" != "0" ]] && echo -e "${Red}错误: 请以 root 运行！${Nc}" && exit 1; }
check_init_system() { [[ ! -f /usr/bin/systemctl ]] && echo -e "${Red}错误: 仅支持 Systemd 系统。${Nc}" && exit 1; }

# --- 功能函数 ---
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
    [[ -z "$PORT" ]] && return
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --zone=public --remove-port=${PORT}/tcp --permanent && firewall-cmd --reload
    fi
    [[ -x "$(command -v ufw)" ]] && ufw delete allow ${PORT}/tcp >/dev/null 2>&1
    iptables -D INPUT -p tcp --dport ${PORT} -j ACCEPT 2>/dev/null
}

update_script() {
    echo -e "${Blue}正在更新管理脚本...${Nc}"
    TMP_FILE=$(mktemp)
    if wget -qO "$TMP_FILE" "$SCRIPT_URL"; then
        mv "$TMP_FILE" "$MTP_CMD" && chmod +x "$MTP_CMD"
        cp "$MTP_CMD" "$0" 2>/dev/null
        echo -e "${Green}更新成功！请重新运行 'mtp'。${Nc}"
        exit 0
    else
        echo -e "${Red}更新失败，请检查网络连接。${Nc}"
    fi
}

# --- 核心安装逻辑 ---
install_mtp() {
    echo -e "${Yellow}请选择版本：${Nc}"
    echo -e "1) Go 版     (9seconds - 推荐：省资源，高性能)"
    echo -e "2) Python 版 (alexbers - 兼容：配置模式)"
    read -p "选择 [1-2]: " core_choice
    [[ "$core_choice" == "2" ]] && install_py_version || install_go_version
}

install_go_version() {
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
    VERSION=$(curl -s https://api.github.com/repos/9seconds/mtg/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    VERSION=${VERSION:-"v2.1.7"}
    echo -e "${Blue}正在安装 Go 核心...${Nc}"
    wget -qO- "https://github.com/9seconds/mtg/releases/download/${VERSION}/mtg-${VERSION#v}-linux-${ARCH}.tar.gz" | tar xz -C /tmp
    mv /tmp/mtg-*/mtg "$BIN_PATH" && chmod +x "$BIN_PATH"
    
    mkdir -p "$CONFIG_DIR"
    read -p "伪装域名 (默认: azure.microsoft.com): " DOMAIN
    DOMAIN=${DOMAIN:-azure.microsoft.com}
    SECRET=$($BIN_PATH generate-secret --hex "$DOMAIN")
    read -p "监听端口 (默认随机): " PORT
    PORT=${PORT:-$((10000 + RANDOM % 20000))}

    echo -e "CORE=GO\nPORT=${PORT}\nSECRET=${SECRET}\nDOMAIN=${DOMAIN}" > "${CONFIG_DIR}/config"
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=MTProxy Service
After=network.target
[Service]
ExecStart=${BIN_PATH} simple-run 0.0.0.0:${PORT} ${SECRET}
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    finish_install "$PORT"
}

install_py_version() {
    echo -e "${Blue}正在配置 Python 环境 (Debian 13 深度静默模式)...${Nc}"
    export DEBIAN_FRONTEND=noninteractive
    echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections >/dev/null 2>&1

    apt-get update
    apt-get install -y -o Dpkg::Options::="--force-confdef" \
                   -o Dpkg::Options::="--force-confold" \
                   python3-dev python3-pip git xxd python3-cryptography debconf-utils

    rm -rf "$PY_DIR"
    git clone https://github.com/alexbers/mtprotoproxy.git "$PY_DIR"
    pip3 install pycryptodome uvloop --break-system-packages
    
    mkdir -p "$CONFIG_DIR"
    read -p "伪装域名 (默认: azure.microsoft.com): " DOMAIN
    DOMAIN=${DOMAIN:-azure.microsoft.com}
    RAW_S=$(head -c 16 /dev/urandom | xxd -ps -c 16 | tr -d '[:space:]')
    D_HEX=$(echo -n "$DOMAIN" | xxd -p -c 256 | tr -d '[:space:]')
    read -p "监听端口 (默认随机): " PORT
    PORT=${PORT:-$((10000 + RANDOM % 20000))}

    echo -e "CORE=PY\nPORT=${PORT}\nSECRET=ee${RAW_S}${D_HEX}\nDOMAIN=${DOMAIN}\nRAW_SECRET=${RAW_S}\nDOMAIN_HEX=${D_HEX}" > "${CONFIG_DIR}/config"
    cat > ${PY_DIR}/config.py <<EOF
PORT = ${PORT}
USERS = { "tg": "${RAW_S}" }
MODES = { "classic": False, "secure": False, "tls": True }
TLS_DOMAIN = "${DOMAIN}"
EOF
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=MTProxy Service
After=network.target
[Service]
WorkingDirectory=${PY_DIR}
ExecStart=/usr/bin/python3 mtprotoproxy.py config.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    finish_install "$PORT"
}

finish_install() {
    open_port "$1"
    systemctl daemon-reload && systemctl enable mtg && systemctl restart mtg
    wget -qO "$MTP_CMD" "$SCRIPT_URL" && chmod +x "$MTP_CMD"
    echo -e "\n${Green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${Nc}"
    echo -e "${Green}   安装成功！服务已稳定运行。          ${Nc}"
    echo -e "${Yellow}   >>> 管理快捷命令: ${Red}mtp${Nc}"
    echo -e "${Green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${Nc}\n"
    show_info
}

show_info() {
    [[ ! -f "${CONFIG_DIR}/config" ]] && return
    source "${CONFIG_DIR}/config"
    echo -e "${Blue}正在探测外网地址 (支持 IPv6)...${Nc}"
    IP4=$(curl -s4 --connect-timeout 5 ip.sb || curl -s4 ipinfo.io/ip)
    IP6=$(curl -s6 --connect-timeout 5 ip.sb || curl -s6 icanhazip.com)
    echo -e "\n${Green}======= MTProxy 信息 (${CORE}版) =======${Nc}"
    echo -e "端口: ${Yellow}${PORT}${Nc} | 域名: ${Blue}${DOMAIN}${Nc}"
    echo -e "密钥: ${Yellow}${SECRET}${Nc}"
    [[ -n "$IP4" ]] && echo -e "IPv4: ${Green}tg://proxy?server=${IP4}&port=${PORT}&secret=${SECRET}${Nc}"
    [[ -n "$IP6" ]] && echo -e "IPv6: ${Green}tg://proxy?server=[${IP6}]&port=${PORT}&secret=${SECRET}${Nc}"
    echo -e "========================================\n"
}

# --- 极速且干净的卸载 ---
uninstall_all() {
    echo -e "${Yellow}正在极速清理程序及依赖模块...${Nc}"
    [[ -f "${CONFIG_DIR}/config" ]] && source "${CONFIG_DIR}/config" && close_port "$PORT"
    
    systemctl stop mtg 2>/dev/null
    systemctl disable mtg 2>/dev/null
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null

    if command -v pip3 >/dev/null 2>&1; then
        echo -e "${Blue}正在移除 Python 核心依赖模块...${Nc}"
        pip3 uninstall -y pycryptodome uvloop 2>/dev/null
    fi

    rm -rf "$CONFIG_DIR"
    rm -rf "$PY_DIR"
    rm -f "$BIN_PATH"
    rm -f "$MTP_CMD"
    
    echo -e "${Green}卸载完成！系统已恢复纯净。${Nc}"
    exit 0
}

# --- 菜单界面 ---
menu() {
    systemctl daemon-reload
    clear
    echo -e "${Green}MTProxy (Go/Python) 管理脚本${Nc}"
    echo -e "----------------------------------"
    
    if systemctl is-active --quiet mtg; then
        source "${CONFIG_DIR}/config" 2>/dev/null
        echo -e "服务状态: ${Green}● 运行中 (${CORE:-未知}版)${Nc}"
    elif [[ ! -f "$SERVICE_FILE" ]]; then
        echo -e "服务状态: ${Yellow}○ 未安装${Nc}"
    else
        echo -e "服务状态: ${Red}○ 已停止${Nc}"
    fi
    
    echo -e "----------------------------------"
    echo -e "1. 安装 / 重置"
    echo -e "2. 修改 端口/域名"
    echo -e "3. 查看 链接信息"
    echo -e "4. 更新 脚本"
    echo -e "5. 重启 服务"
    echo -e "6. 停止 服务"
    echo -e "7. 卸载"
    echo -e "0. 退出"
    echo -e "----------------------------------"
    read -p "请选择 [0-7]: " choice
    case "$choice" in
        1) install_mtp ;;
        2) [[ ! -f "${CONFIG_DIR}/config" ]] && echo -e "${Red}未安装！${Nc}" && sleep 1 || { source "${CONFIG_DIR}/config"; close_port "$PORT"; install_mtp; } ;;
        3) show_info ;;
        4) update_script ;;
        5) systemctl restart mtg && echo -e "${Green}服务已重启${Nc}" ;;
        6) systemctl stop mtg && echo -e "${Yellow}服务已停止${Nc}" ;;
        7) uninstall_all ;;
        *) exit 0 ;;
    esac
}

check_root
check_init_system
menu
