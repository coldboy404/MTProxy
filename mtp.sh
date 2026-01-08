#!/usr/bin/env bash
#=========================================================
#   System Required: CentOS 7+ / Debian 8+ / Ubuntu 16+
#   Description: MTProxy (Go & Python) One-click Installer
#=========================================================

Red="\033[31m"
Green="\033[32m"
Yellow="\033[33m"
Blue="\033[34m"
Nc="\033[0m"

set +u

BIN_PATH="/usr/local/bin/mtg"
PY_DIR="/opt/mtprotoproxy"
MTP_CMD="/usr/local/bin/mtp"
CONFIG_DIR="/etc/mtg"
SERVICE_FILE="/etc/systemd/system/mtg.service"
SCRIPT_URL="https://raw.githubusercontent.com/weaponchiang/MTProxy/main/mtp.sh"

check_root() { [[ "$(id -u)" != "0" ]] && echo -e "${Red}错误: 请以 root 运行！${Nc}" && exit 1; }
check_init_system() { [[ ! -f /usr/bin/systemctl ]] && echo -e "${Red}错误: 仅支持 Systemd 系统。${Nc}" && exit 1; }

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
    echo -e "${Blue}正在从远程更新脚本...${Nc}"
    TMP_FILE=$(mktemp)
    if wget -qO "$TMP_FILE" "$SCRIPT_URL"; then
        mv "$TMP_FILE" "$MTP_CMD" && chmod +x "$MTP_CMD"
        cp "$MTP_CMD" "$0" 2>/dev/null
        echo -e "${Green}管理脚本更新成功！请重新运行。${Nc}"
        exit 0
    else
        echo -e "${Red}更新失败，请检查网络。${Nc}"
    fi
}

install_mtp() {
    echo -e "${Yellow}请选择版本：${Nc}"
    echo -e "1) Go 版      (9seconds - 推荐：省资源，高性能)"
    echo -e "2) Python 版  (alexbers - 兼容：配置模式)"
    read -p "选择 [1-2]: " core_choice
    [[ "$core_choice" == "2" ]] && install_py_version || install_go_version
}

install_go_version() {
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
    VERSION=$(curl -s https://api.github.com/repos/9seconds/mtg/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    VERSION=${VERSION:-"v2.1.7"}
    echo -e "${Blue}正在下载程序文件...${Nc}"
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
    echo -e "${Blue}正在配置环境...${Nc}"
    
    # 1. 设置免交互变量
    export DEBIAN_FRONTEND=noninteractive
    
    # 2. 先更新源
    apt-get update
    
    # 3. 【绝对核心修复】先卸载 needrestart。这就是导致卡死的罪魁祸首。
    # 加 || true 防止因为没装这个包报错退出
    apt-get purge -y needrestart >/dev/null 2>&1 || true
    
    # 4. 现在再安装依赖，此时没有拦截进程，apt 不会卡住
    apt-get install -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        python3-dev python3-pip git xxd python3-cryptography

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

    echo -e "CORE=PY\nPORT=${PORT}\nSECRET=ee${RAW_S}${D_HEX}\nDOMAIN=${DOMAIN}" > "${CONFIG_DIR}/config"
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
    echo -e "${Green}安装成功！${Nc}"
    show_info
}

show_info() {
    [[ ! -f "${CONFIG_DIR}/config" ]] && return
    source "${CONFIG_DIR}/config"
    IP4=$(curl -s4 --connect-timeout 5 ip.sb || curl -s4 ipinfo.io/ip)
    IP6=$(curl -s6 --connect-timeout 5 ip.sb || curl -s6 icanhazip.com)
    echo -e "\n${Green}======= MTProxy 信息 =======${Nc}"
    echo -e "端口: ${Yellow}${PORT}${Nc} | 域名: ${Blue}${DOMAIN}${Nc}"
    echo -e "密钥: ${Yellow}${SECRET}${Nc}"
    [[ -n "$IP4" ]] && echo -e "IPv4: ${Green}tg://proxy?server=${IP4}&port=${PORT}&secret=${SECRET}${Nc}"
    [[ -n "$IP6" ]] && echo -e "IPv6: ${Green}tg://proxy?server=[${IP6}]&port=${PORT}&secret=${SECRET}${Nc}"
    echo -e "============================\n"
}

uninstall_all() {
    echo -e "${Yellow}正在卸载...${Nc}"
    [[ -f "${CONFIG_DIR}/config" ]] && source "${CONFIG_DIR}/config" && close_port "$PORT"
    systemctl stop mtg 2>/dev/null
    systemctl disable mtg 2>/dev/null
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    if command -v pip3 >/dev/null 2>&1; then
        pip3 uninstall -y pycryptodome uvloop 2>/dev/null
    fi
    rm -rf "$CONFIG_DIR" "$PY_DIR" "$BIN_PATH" "$MTP_CMD"
    echo -e "${Green}已卸载。${Nc}"
    exit 0
}

menu() {
    systemctl daemon-reload
    clear
    echo -e "${Green}MTProxy (Go/Python) 管 理 脚 本${Nc}"
    echo -e "----------------------------------"
    if systemctl is-active --quiet mtg; then
        source "${CONFIG_DIR}/config" 2>/dev/null
        echo -e "服 务 状 态 : ${Green}● 运 行 中 (${CORE:-版})${Nc}"
    elif [[ ! -f "$SERVICE_FILE" ]]; then
        echo -e "服 务 状 态 : ${Yellow}○ 未 安 装${Nc}"
    else
        echo -e "服 务 状 态 : ${Red}○ 已 停 止${Nc}"
    fi
    echo -e "----------------------------------"
    echo -e "1. 安 装  / 重 置"
    echo -e "2. 修 改  端 口 /域 名"
    echo -e "3. 查 看  链 接 信 息"
    echo -e "4. 更 新  脚 本"
    echo -e "5. 重 启  服 务"
    echo -e "6. 停 止  服 务"
    echo -e "7. 卸 载"
    echo -e "0. 退 出"
    echo -e "----------------------------------"
    read -p "选 择  [0-7]: " choice
    case "$choice" in
        1) install_mtp ;;
        2) [[ ! -f "${CONFIG_DIR}/config" ]] && echo -e "${Red}未安装！${Nc}" || install_mtp ;;
        3) show_info ;;
        4) update_script ;;
        5) systemctl restart mtg && echo -e "已重启" ;;
        6) systemctl stop mtg && echo -e "已停止" ;;
        7) uninstall_all ;;
        *) exit 0 ;;
    esac
}

check_root
check_init_system
menu
