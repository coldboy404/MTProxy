#!/usr/bin/env bash
#=========================================================
#   System Required: CentOS 7+ / Debian 8+ / Ubuntu 16+
#   Description: MTProxy (Go & Python) One-click Installer
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
PY_DIR="/opt/mtprotoproxy"
MTP_CMD="/usr/local/bin/mtp"
CONFIG_DIR="/etc/mtg"
SCRIPT_URL="https://raw.githubusercontent.com/weaponchiang/MTProxy/main/mtp.sh"

# --- 1. 环境准备 ---

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${Red}错误: 本脚本必须以 root 用户运行！${Nc}"
        exit 1
    fi
}

check_init_system() {
    if command -v systemctl >/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
    else
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

# --- 2. 安装逻辑 ---

install_mtp() {
    echo -e "${Yellow}请选择要安装的版本：${Nc}"
    echo -e "1) Go 版 (9seconds/mtg - 轻量、高性能)"
    echo -e "2) Python 版 (alexbers/mtprotoproxy - 功能丰富、支持多端口)"
    read -p "选择 [1-2]: " core_choice

    if [ "$core_choice" == "1" ]; then
        install_go_version
    else
        install_py_version
    fi
}

install_go_version() {
    echo -e "${Blue}正在下载 Go 版核心...${Nc}"
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) echo -e "${Red}不支持的架构${Nc}"; exit 1 ;;
    esac

    VERSION=$(curl -s https://api.github.com/repos/9seconds/mtg/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    VER_NUM=${VERSION#v}
    DOWNLOAD_URL="https://github.com/9seconds/mtg/releases/download/${VERSION}/mtg-${VER_NUM}-linux-${ARCH}.tar.gz"
    
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
Description=MTProxy Go Version
After=network.target
[Service]
ExecStart=${BIN_PATH} simple-run 0.0.0.0:${PORT} ${SECRET}
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    finish_install "mtg" "$PORT"
}

install_py_version() {
    echo -e "${Blue}正在安装 Python 环境及依赖...${Nc}"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y python3-dev python3-pip git
    elif command -v yum >/dev/null 2>&1; then
        yum install -y python3-devel python3-pip git
    fi

    rm -rf "$PY_DIR"
    git clone https://github.com/alexbers/mtprotoproxy.git "$PY_DIR"
    pip3 install --upgrade pip
    pip3 install -r "${PY_DIR}/requirements.txt" || pip3 install pycryptodome uvloop

    mkdir -p "$CONFIG_DIR"
    read -p "伪装域名 (默认: www.google.com): " DOMAIN
    DOMAIN=${DOMAIN:-www.google.com}
    # Python版使用特殊的加密格式，这里生成一个32位随机hex
    SECRET=$(head -c 16 /dev/urandom | xxd -ps)
    # 组合为 FakeTLS 密钥格式 (ee + secret + domain_hex)
    DOMAIN_HEX=$(echo -n "$DOMAIN" | xxd -p)
    FINAL_SECRET="ee${SECRET}${DOMAIN_HEX}"

    read -p "端口 (默认随机): " PORT
    PORT=${PORT:-$((10000 + RANDOM % 20000))}

    echo -e "CORE=PY\nPORT=${PORT}\nSECRET=${FINAL_SECRET}\nDOMAIN=${DOMAIN}" > "${CONFIG_DIR}/config"

    cat > /etc/systemd/system/mtg.service <<EOF
[Unit]
Description=MTProxy Python Version
After=network.target
[Service]
WorkingDirectory=${PY_DIR}
ExecStart=/usr/bin/python3 mtprotoproxy.py -p ${PORT} -s ${SECRET} -t ${DOMAIN_HEX}
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    finish_install "mtg" "$PORT"
}

finish_install() {
    open_port "$2"
    systemctl daemon-reload
    systemctl enable "$1"
    systemctl restart "$1"
    wget -qO "$MTP_CMD" "$SCRIPT_URL" && chmod +x "$MTP_CMD"
    echo -e "${Green}安装完成！${Nc}"
    show_info
}

# --- 3. 管理功能 ---

modify_config() {
    if [ ! -f "${CONFIG_DIR}/config" ]; then echo -e "${Red}请先安装！${Nc}"; return; fi
    source "${CONFIG_DIR}/config"
    OLD_PORT=$PORT
    
    read -p "新端口 (当前: $PORT): " NEW_PORT
    NEW_PORT=${NEW_PORT:-$PORT}
    read -p "新域名 (当前: $DOMAIN): " NEW_DOMAIN
    NEW_DOMAIN=${NEW_DOMAIN:-$DOMAIN}

    [[ "$NEW_PORT" != "$OLD_PORT" ]] && close_port "$OLD_PORT" && open_port "$NEW_PORT"

    # 根据当前核心重新生成配置
    if [ "$CORE" == "GO" ]; then
        NEW_SECRET=$($BIN_PATH generate-secret --hex "$NEW_DOMAIN")
        # 更新 Systemd
        sed -i "s|simple-run .*|simple-run 0.0.0.0:${NEW_PORT} ${NEW_SECRET}|" /etc/systemd/system/mtg.service
    else
        SECRET_RAW=$(head -c 16 /dev/urandom | xxd -ps)
        DOMAIN_HEX=$(echo -n "$NEW_DOMAIN" | xxd -p)
        NEW_SECRET="ee${SECRET_RAW}${DOMAIN_HEX}"
        sed -i "s|python3 mtprotoproxy.py .*|python3 mtprotoproxy.py -p ${NEW_PORT} -s ${SECRET_RAW} -t ${DOMAIN_HEX}|" /etc/systemd/system/mtg.service
    fi

    echo -e "CORE=${CORE}\nPORT=${NEW_PORT}\nSECRET=${NEW_SECRET}\nDOMAIN=${NEW_DOMAIN}" > "${CONFIG_DIR}/config"
    systemctl daemon-reload && systemctl restart mtg
    echo -e "${Green}配置修改成功。${Nc}"
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
    systemctl stop mtg && systemctl disable mtg
    rm -rf "$CONFIG_DIR" "$BIN_PATH" "$PY_DIR" /etc/systemd/system/mtg.service "$MTP_CMD"
    echo -e "${Green}已彻底卸载。${Nc}"
}

# --- 4. 菜单 ---

menu() {
    clear
    echo -e "${Green}MTProxy 多版本一键管理脚本${Nc}"
    echo -e "----------------------------"
    if pgrep -f "mtg|mtprotoproxy" >/dev/null; then
        echo -e "服务状态: ${Green}运行中${Nc}"
    else
        echo -e "服务状态: ${Red}未运行/未安装${Nc}"
    fi
    echo -e "----------------------------"
    echo -e "1. 安装 MTProxy (Go/Python)"
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
            echo -e "${Green}更新成功${Nc}" ;;
        5) systemctl restart mtg; echo -e "${Green}已重启${Nc}" ;;
        6) uninstall_mtp ;;
        0) exit 0 ;;
    esac
}

check_root
check_init_system
menu
