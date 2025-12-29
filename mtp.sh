#!/usr/bin/env bash
#=========================================================
#   System Required: CentOS 7+ / Debian 8+ / Ubuntu 16+
#   Description: MTProxy (Go & Python) One-click Installer
#   Integrated Core: 9seconds (Go) & Alexbers (Python)
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
# 确保此链接指向你的最新脚本
SCRIPT_URL="https://raw.githubusercontent.com/weaponchiang/MTProxy/main/mtp.sh"

check_root() { [[ "$(id -u)" != "0" ]] && echo -e "${Red}错误: 请以 root 运行！${Nc}" && exit 1; }
check_init_system() { [[ ! -f /usr/bin/systemctl ]] && echo -e "${Red}错误: 仅支持 Systemd 系统。${Nc}" && exit 1; }

# --- 防火墙管理 ---
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

# --- 安装逻辑 ---

install_mtp() {
    echo -e "${Yellow}请选择要安装的版本：${Nc}"
    echo -e "1) Go 版     (作者: ${Blue}9seconds${Nc} - 高并发，内存占用极低)"
    echo -e "2) Python 版 (作者: ${Blue}alexbers${Nc} - 协议支持全，环境兼容好)"
    read -p "选择 [1-2]: " core_choice

    if [ "$core_choice" == "2" ]; then
        install_py_version
    else
        install_go_version
    fi
}

install_go_version() {
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
    VERSION=$(curl -s https://api.github.com/repos/9seconds/mtg/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    echo -e "${Blue}正在下载 Go 核心...${Nc}"
    wget -qO- "https://github.com/9seconds/mtg/releases/download/${VERSION}/mtg-${VERSION#v}-linux-${ARCH}.tar.gz" | tar xz -C /tmp
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
    echo -e "${Blue}正在配置 Python 环境...${Nc}"
    apt-get update && apt-get install -y python3-dev python3-pip git xxd python3-cryptography
    rm -rf "$PY_DIR"
    git clone https://github.com/alexbers/mtprotoproxy.git "$PY_DIR"
    pip3 install pycryptodome uvloop --break-system-packages

    mkdir -p "$CONFIG_DIR"
    read -p "伪装域名 (默认: www.icloud.com): " DOMAIN
    DOMAIN=${DOMAIN:-www.icloud.com}
    
    # 构造密钥
    RAW_S=$(head -c 16 /dev/urandom | xxd -ps -c 16 | tr -d '[:space:]')
    D_HEX=$(echo -n "$DOMAIN" | xxd -p -c 256 | tr -d '[:space:]')
    
    read -p "端口 (默认随机): " PORT
    PORT=${PORT:-$((10000 + RANDOM % 20000))}

    echo -e "CORE=PY\nPORT=${PORT}\nSECRET=ee${RAW_S}${D_HEX}\nDOMAIN=${DOMAIN}\nRAW_SECRET=${RAW_S}\nDOMAIN_HEX=${D_HEX}" > "${CONFIG_DIR}/config"

    # 适配 Debian 环境的启动参数
    cat > /etc/systemd/system/mtg.service <<EOF
[Unit]
Description=MTProxy Python Service
After=network.target
[Service]
WorkingDirectory=${PY_DIR}
ExecStart=/usr/bin/python3 mtprotoproxy.py ${PORT} ${RAW_S} -t ${D_HEX}
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
    echo -e "${Green}   MTProxy 安装成功！服务已进入运行状态。        ${Nc}"
    echo -e "${Yellow}   >>> 管理快捷键: ${Red}mtp${Yellow} (随时输入即可进入菜单) <<<   ${Nc}"
    echo -e "${Green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${Nc}\n"
    show_info
}

# --- 管理功能 ---

modify_config() {
    if [ ! -f "${CONFIG_DIR}/config" ]; then echo -e "${Red}未安装服务！${Nc}"; return; fi
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
        SECRET_RAW=$(head -c 16 /dev/urandom | xxd -ps -c 16 | tr -d '[:space:]')
        D_HEX=$(echo -n "$NEW_DOMAIN" | xxd -p -c 256 | tr -d '[:space:]')
        NEW_SECRET="ee${SECRET_RAW}${D_HEX}"
        sed -i "s|python3 mtprotoproxy.py .*|python3 mtprotoproxy.py ${NEW_PORT} ${SECRET_RAW} -t ${D_HEX}|" /etc/systemd/system/mtg.service
        echo -e "CORE=PY\nPORT=${NEW_PORT}\nSECRET=${NEW_SECRET}\nDOMAIN=${NEW_DOMAIN}\nRAW_SECRET=${SECRET_RAW}\nDOMAIN_HEX=${D_HEX}" > "${CONFIG_DIR}/config"
    fi

    systemctl daemon-reload && systemctl restart mtg
    echo -e "${Green}配置已更新。${Nc}"
    show_info
}

show_info() {
    [[ ! -f "${CONFIG_DIR}/config" ]] && return
    source "${CONFIG_DIR}/config"
    IP=$(curl -s4 ip.sb || curl -s4 ipinfo.io/ip)
    echo -e "${Green}======= MTProxy 链接信息 (${CORE}版) =======${Nc}"
    echo -e "端口  : ${Yellow}${PORT}${Nc}"
    echo -e "域名  : ${Blue}${DOMAIN}${Nc}"
    echo -e "密钥  : ${Yellow}${SECRET}${Nc}"
    echo -e "链接  : ${Green}tg://proxy?server=${IP}&port=${PORT}&secret=${SECRET}${Nc}"
    echo -e "========================================\n"
}

# --- 菜单界面 ---

menu() {
    clear
    echo -e "${Green}MTProxy (Go/Python) 管理脚本${Nc}"
    echo -e "----------------------------------"
    if systemctl is-active --quiet mtg; then
        echo -e "服务状态: ${Green}● 运行中 (Running)${Nc}"
    else
        echo -e "服务状态: ${Red}○ 未运行 (Stopped)${Nc}"
    fi
    echo -e "----------------------------------"
    echo -e "1. 安装 / 覆盖安装\n2. 修改 端口或域名\n3. 查看 链接信息\n4. 重启 代理服务\n5. 卸载 代理服务\n0. 退出脚本"
    echo -e "----------------------------------"
    read -p "请选择 [0-5]: " choice
    case "$choice" in
        1) install_mtp ;;
        2) modify_config ;;
        3) show_info ;;
        4) systemctl restart mtg; echo -e "${Green}服务已重启${Nc}" ;;
        5) source "${CONFIG_DIR}/config" && close_port "$PORT"
           systemctl stop mtg; systemctl disable mtg; rm -rf "$CONFIG_DIR" "$BIN_PATH" "$PY_DIR" "$MTP_CMD" /etc/systemd/system/mtg.service
           echo -e "${Green}卸载完成。${Nc}" ;;
        *) exit 0 ;;
    esac
}

check_root
check_init_system
menu
