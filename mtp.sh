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

set -u

BIN_PATH="/usr/local/bin/mtg"
PY_DIR="/opt/mtprotoproxy"
MTP_CMD="/usr/local/bin/mtp"
CONFIG_DIR="/etc/mtg"
SCRIPT_URL="https://raw.githubusercontent.com/weaponchiang/MTProxy/main/mtp.sh"

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${Red}错误: 本脚本必须以 root 用户运行！${Nc}"
        exit 1
    fi
}

check_init_system() {
    if ! command -v systemctl >/dev/null 2>&1; then
        echo -e "${Red}错误: 仅支持 Systemd 系统。${Nc}"
        exit 1
    fi
}

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
    if [ -z "$PORT" ]; then return; fi
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --zone=public --remove-port=${PORT}/tcp --permanent && firewall-cmd --reload
    fi
    if command -v ufw >/dev/null 2>&1; then ufw delete allow ${PORT}/tcp >/dev/null 2>&1; fi
    iptables -D INPUT -p tcp --dport ${PORT} -j ACCEPT 2>/dev/null
}

install_mtp() {
    echo -e "${Yellow}请选择要安装的版本：${Nc}"
    echo -e "1) Go 版 (mtg - 占用极低，高性能)"
    echo -e "2) Python 版 (mtprotoproxy - 支持更灵活的混淆)"
    read -p "选择 [1-2]: " core_choice

    if [ "$core_choice" == "2" ]; then
        install_py_version
    else
        install_go_version
    fi
}

install_go_version() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) echo -e "${Red}不支持的架构${Nc}"; exit 1 ;;
    esac

    VERSION=$(curl -s https://api.github.com/repos/9seconds/mtg/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    VERSION=${VERSION:-"v2.1.7"}
    VER_NUM=${VERSION#v}
    DOWNLOAD_URL="https://github.com/9seconds/mtg/releases/download/${VERSION}/mtg-${VER_NUM}-linux-${ARCH}.tar.gz"
    
    echo -e "${Blue}正在下载 Go 版核心...${Nc}"
    wget -qO- "$DOWNLOAD_URL" | tar xz -C /tmp
    mv /tmp/mtg-*/mtg "$BIN_PATH" && chmod +x "$BIN_PATH"
    
    mkdir -p "$CONFIG_DIR"
    read -p "伪装域名 (默认: www.microsoft.com): " DOMAIN
    DOMAIN=${DOMAIN:-www.microsoft.com}
    SECRET=$($BIN_PATH generate-secret --hex "$DOMAIN")
    read -p "端口 (默认随机): " PORT
    PORT=${PORT:-$((10000 + RANDOM % 20000))}

    echo -e "CORE=GO\nPORT=${PORT}\nSECRET=${SECRET}\nDOMAIN=${DOMAIN}" > "${CONFIG_DIR}/config"
    
    cat > /etc/systemd/system/mtg.service <<EOF
[Unit]
Description=MTProxy Go Service
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
    echo -e "${Blue}正在准备 Python 环境...${Nc}"
    # 自动修复 dpkg 锁定问题
    dpkg --configure -a >/dev/null 2>&1
    
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y python3-dev python3-pip git xxd python3-cryptography
    elif command -v yum >/dev/null 2>&1; then
        yum install -y python3-devel python3-pip git vim-common
    fi

    rm -rf "$PY_DIR"
    git clone https://github.com/alexbers/mtprotoproxy.git "$PY_DIR"
    pip3 install --upgrade pip --break-system-packages 2>/dev/null
    pip3 install -r "${PY_DIR}/requirements.txt" --break-system-packages || pip3 install pycryptodome uvloop cryptography --break-system-packages

    mkdir -p "$CONFIG_DIR"
    read -p "伪装域名 (默认: www.microsoft.com): " DOMAIN
    DOMAIN=${DOMAIN:-www.microsoft.com}
    
    # 密钥生成
    SECRET_RAW=$(head -c 16 /dev/urandom | xxd -ps | tr -d '[:space:]')
    DOMAIN_HEX=$(echo -n "$DOMAIN" | xxd -p | tr -d '[:space:]')
    FINAL_SECRET="ee${SECRET_RAW}${DOMAIN_HEX}"

    read -p "端口 (默认随机): " PORT
    PORT=${PORT:-$((10000 + RANDOM % 20000))}

    echo -e "CORE=PY\nPORT=${PORT}\nSECRET=${FINAL_SECRET}\nDOMAIN=${DOMAIN}\nRAW_SECRET=${SECRET_RAW}\nDOMAIN_HEX=${DOMAIN_HEX}" > "${CONFIG_DIR}/config"

    # 修正后的启动命令 (不带 -p -s 标签，直接按顺序传值)
    # 顺序：python3 mtprotoproxy.py [端口] [密钥] -t [伪装域名HEX]
    cat > /etc/systemd/system/mtg.service <<EOF
[Unit]
Description=MTProxy Python Service
After=network.target
[Service]
WorkingDirectory=${PY_DIR}
ExecStart=/usr/bin/python3 mtprotoproxy.py ${PORT} ${SECRET_RAW} -t ${DOMAIN_HEX}
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
    
    echo -e "\n${Green}========================================${Nc}"
    echo -e "${Green}服务已安装并启动成功！${Nc}"
    echo -e "${Yellow}快捷管理指令: mtp ${Nc}"
    echo -e "${Green}========================================${Nc}\n"
    show_info
}

modify_config() {
    if [ ! -f "${CONFIG_DIR}/config" ]; then echo -e "${Red}请先安装！${Nc}"; return; fi
    source "${CONFIG_DIR}/config"
    OLD_PORT=$PORT
    
    read -p "新端口 (当前: $PORT): " NEW_PORT
    NEW_PORT=${NEW_PORT:-$PORT}
    read -p "新域名 (当前: $DOMAIN): " NEW_DOMAIN
    NEW_DOMAIN=${NEW_DOMAIN:-$DOMAIN}

    [ "$NEW_PORT" != "$OLD_PORT" ] && close_port "$OLD_PORT" && open_port "$NEW_PORT"

    if [ "$CORE" == "GO" ]; then
        NEW_SECRET=$($BIN_PATH generate-secret --hex "$NEW_DOMAIN")
        sed -i "s|simple-run .*|simple-run 0.0.0.0:${NEW_PORT} ${NEW_SECRET}|" /etc/systemd/system/mtg.service
        echo -e "CORE=GO\nPORT=${NEW_PORT}\nSECRET=${NEW_SECRET}\nDOMAIN=${NEW_DOMAIN}" > "${CONFIG_DIR}/config"
    else
        SECRET_RAW=$(head -c 16 /dev/urandom | xxd -ps | tr -d '[:space:]')
        D_HEX=$(echo -n "$NEW_DOMAIN" | xxd -p | tr -d '[:space:]')
        NEW_SECRET="ee${SECRET_RAW}${D_HEX}"
        # 修正修改配置时的参数顺序
        sed -i "s|python3 mtprotoproxy.py .*|python3 mtprotoproxy.py ${NEW_PORT} ${SECRET_RAW} -t ${D_HEX}|" /etc/systemd/system/mtg.service
        echo -e "CORE=PY\nPORT=${NEW_PORT}\nSECRET=${NEW_SECRET}\nDOMAIN=${NEW_DOMAIN}\nRAW_SECRET=${SECRET_RAW}\nDOMAIN_HEX=${D_HEX}" > "${CONFIG_DIR}/config"
    fi

    systemctl daemon-reload && systemctl restart mtg
    echo -e "${Green}配置修改成功！${Nc}"
    show_info
}

show_info() {
    [ ! -f "${CONFIG_DIR}/config" ] && return
    source "${CONFIG_DIR}/config"
    IP=$(curl -s4 ip.sb || curl -s4 ipinfo.io/ip)
    
    echo -e "\n${Green}======= MTProxy 信息 (${CORE}版) =======${Nc}"
    echo -e "端口  : ${Yellow}${PORT}${Nc}"
    echo -e "域名  : ${Blue}${DOMAIN}${Nc}"
    echo -e "密钥  : ${Yellow}${SECRET}${Nc}"
    echo -e "链接  : ${Green}tg://proxy?server=${IP}&port=${PORT}&secret=${SECRET}${Nc}"
    echo -e "========================================\n"
}

uninstall_mtp() {
    read -p "确定卸载吗？(y/n): " confirm
    [[ "$confirm" != "y" ]] && return
    if [ -f "${CONFIG_DIR}/config" ]; then
        source "${CONFIG_DIR}/config"
        close_port "$PORT"
    fi
    systemctl stop mtg 2>/dev/null; systemctl disable mtg 2>/dev/null
    rm -f /etc/systemd/system/mtg.service
    rm -rf "$CONFIG_DIR" "$BIN_PATH" "$PY_DIR" "$MTP_CMD"
    echo -e "${Green}卸载成功。${Nc}"
}

menu() {
    clear
    echo -e "${Green}MTProxy (Go/Python) 多版本脚本${Nc}"
    echo -e "----------------------------"
    if pgrep -f "mtg|mtprotoproxy" >/dev/null; then
        echo -e "服务状态: ${Green}运行中${Nc}"
    else
        echo -e "服务状态: ${Red}未运行${Nc}"
    fi
    echo -e "----------------------------"
    echo -e "1. 安装 MTProxy"
    echo -e "2. 修改 端口或域名"
    echo -e "3. 查看 链接信息"
    echo -e "4. 更新 管理脚本"
    echo -e "5. 重启 服务"
    echo -e "6. 卸载 MTProxy"
    echo -e "0. 退出"
    echo -e "----------------------------"
    read -p "选择: " choice
    case "$choice" in
        1) install_mtp ;;
        2) modify_config ;;
        3) show_info ;;
        4) 
            wget -qO "$MTP_CMD" "$SCRIPT_URL" && chmod +x "$MTP_CMD"
            echo -e "${Green}脚本已更新！${Nc}" ;;
        5) systemctl restart mtg; echo -e "${Green}已重启${Nc}" ;;
        6) uninstall_mtp ;;
        0) exit 0 ;;
    esac
}

check_root
check_init_system
menu
