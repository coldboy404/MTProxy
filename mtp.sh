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

# 取消严格模式，防止安装中断
set +u

BIN_PATH="/usr/local/bin/mtg"
PY_DIR="/opt/mtprotoproxy"
MTP_CMD="/usr/local/bin/mtp"
CONFIG_DIR="/etc/mtg"
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

install_mtp() {
    echo -e "${Yellow}请选择要安装的版本：${Nc}"
    echo -e "1) Go 版     (作者: ${Blue}9seconds${Nc} - 推荐：极高性能)"
    echo -e "2) Python 版 (作者: ${Blue}alexbers${Nc} - 兼容：ellermister 模式)"
    read -p "选择 [1-2]: " core_choice
    [[ "$core_choice" == "2" ]] && install_py_version || install_go_version
}

install_go_version() {
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
    VERSION=$(curl -s https://api.github.com/repos/9seconds/mtg/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    VERSION=${VERSION:-"v2.1.7"}
    echo -e "${Blue}正在下载 Go 核心...${Nc}"
    wget -qO- "https://github.com/9seconds/mtg/releases/download/${VERSION}/mtg-${VERSION#v}-linux-${ARCH}.tar.gz" | tar xz -C /tmp
    mv /tmp/mtg-*/mtg "$BIN_PATH" && chmod +x "$BIN_PATH"
    
    mkdir -p "$CONFIG_DIR"
    read -p "伪装域名 (默认: azure.microsoft.com): " DOMAIN
    DOMAIN=${DOMAIN:-azure.microsoft.com}
    SECRET=$($BIN_PATH generate-secret --hex "$DOMAIN")
    read -p "端口 (默认随机): " PORT
    PORT=${PORT:-$((10000 + RANDOM % 20000))}

    echo -e "CORE=GO\nPORT=${PORT}\nSECRET=${SECRET}\nDOMAIN=${DOMAIN}" > "${CONFIG_DIR}/config"
    write_service_go "$PORT" "$SECRET"
    finish_install "$PORT"
}

install_py_version() {
    echo -e "${Blue}正在配置 Python 环境...${Nc}"
    apt-get update && apt-get install -y python3-dev python3-pip git xxd python3-cryptography
    rm -rf "$PY_DIR"
    git clone https://github.com/alexbers/mtprotoproxy.git "$PY_DIR"
    pip3 install pycryptodome uvloop --break-system-packages
    
    mkdir -p "$CONFIG_DIR"
    read -p "伪装域名 (默认: azure.microsoft.com): " DOMAIN
    DOMAIN=${DOMAIN:-azure.microsoft.com}
    
    RAW_S=$(head -c 16 /dev/urandom | xxd -ps -c 16 | tr -d '[:space:]')
    D_HEX=$(echo -n "$DOMAIN" | xxd -p -c 256 | tr -d '[:space:]')
    
    read -p "端口 (默认随机): " PORT
    PORT=${PORT:-$((10000 + RANDOM % 20000))}

    echo -e "CORE=PY\nPORT=${PORT}\nSECRET=ee${RAW_S}${D_HEX}\nDOMAIN=${DOMAIN}\nRAW_SECRET=${RAW_S}\nDOMAIN_HEX=${D_HEX}" > "${CONFIG_DIR}/config"

    cat > ${PY_DIR}/config.py <<EOF
PORT = ${PORT}
USERS = { "tg": "${RAW_S}" }
MODES = { "classic": False, "secure": False, "tls": True }
TLS_DOMAIN = "${DOMAIN}"
EOF
    write_service_py
    finish_install "$PORT"
}

write_service_go() {
    cat > /etc/systemd/system/mtg.service <<EOF
[Unit]
Description=MTProxy Service
After=network.target
[Service]
ExecStart=${BIN_PATH} simple-run 0.0.0.0:$1 $2
Restart=always
[Install]
WantedBy=multi-user.target
EOF
}

write_service_py() {
    cat > /etc/systemd/system/mtg.service <<EOF
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
}

finish_install() {
    open_port "$1"
    systemctl daemon-reload && systemctl enable mtg && systemctl restart mtg
    wget -qO "$MTP_CMD" "$SCRIPT_URL" && chmod +x "$MTP_CMD"
    echo -e "\n${Green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${Nc}"
    echo -e "${Green}   安装成功！代理服务已在后台悄悄启动。          ${Nc}"
    echo -e "${Yellow}   >>> 管理快捷键: ${Red}mtp${Yellow} (在终端输入即可管理) <<<   ${Nc}"
    echo -e "${Green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${Nc}\n"
    show_info
}

show_info() {
    [[ ! -f "${CONFIG_DIR}/config" ]] && return
    source "${CONFIG_DIR}/config"
    echo -e "${Blue}正在探测公网 IP (包含 IPv6)...${Nc}"
    IP4=$(curl -s4 --connect-timeout 5 ip.sb || curl -s4 ipinfo.io/ip)
    IP6=$(curl -s6 --connect-timeout 5 ip.sb || curl -s6 icanhazip.com)
    
    echo -e "\n${Green}======= MTProxy 链接信息 (${CORE}版) =======${Nc}"
    echo -e "端口  : ${Yellow}${PORT}${Nc} | 域名  : ${Blue}${DOMAIN}${Nc}"
    echo -e "密钥  : ${Yellow}${SECRET}${Nc}"
    [[ -n "$IP4" ]] && echo -e "IPv4 链接: ${Green}tg://proxy?server=${IP4}&port=${PORT}&secret=${SECRET}${Nc}"
    [[ -n "$IP6" ]] && echo -e "IPv6 链接: ${Green}tg://proxy?server=[${IP6}]&port=${PORT}&secret=${SECRET}${Nc}"
    echo -e "========================================\n"
}

menu() {
    clear
    echo -e "${Green}MTProxy (Go/Python) 多版本管理脚本${Nc}"
    echo -e "----------------------------------"
    if systemctl is-active --quiet mtg; then
        echo -e "服务状态: ${Green}● 运行中 (Running)${Nc}"
    else
        echo -e "服务状态: ${Red}○ 未运行 (Stopped)${Nc}"
    fi
    echo -e "----------------------------------"
    echo -e "1. 安装 / 覆盖安装\n2. 修改 端口或域名\n3. 查看 链接信息\n4. 重启 代理服务\n5. 卸载 代理服务\n0. 退出脚本"
    echo -e "----------------------------------"
    read -p "选择 [0-5]: " choice
    case "$choice" in
        1) install_mtp ;;
        2) modify_config ;;
        3) show_info ;;
        4) systemctl restart mtg; echo -e "${Green}已重启${Nc}" ;;
        5) source "${CONFIG_DIR}/config" && close_port "$PORT"
           systemctl stop mtg; systemctl disable mtg; rm -rf "$CONFIG_DIR" "$BIN_PATH" "$PY_DIR" "$MTP_CMD" /etc/systemd/system/mtg.service
           echo -e "${Green}卸载完成。${Nc}" ;;
        *) exit 0 ;;
    esac
}

# 解决修改配置的问题
modify_config() {
    if [ ! -f "${CONFIG_DIR}/config" ]; then echo -e "${Red}请先安装！${Nc}"; return; fi
    uninstall_mtp_temp
    install_mtp
}

uninstall_mtp_temp() {
    source "${CONFIG_DIR}/config"
    close_port "$PORT"
    systemctl stop mtg 2>/dev/null
}

check_root
check_init_system
menu
