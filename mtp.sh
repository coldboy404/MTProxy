#!/usr/bin/env bash
#=========================================================
#   System Required: CentOS 7+ / Debian 8+ / Ubuntu 16+ / Alpine
#   Description: MTProxy (Go & Python) One-click Installer
#=========================================================

Red="\033[31m"
Green="\033[32m"
Yellow="\033[33m"
Blue="\033[34m"
Nc="\033[0m"

# 取消严格模式
set +u

BIN_PATH="/usr/local/bin/mtg"
PY_DIR="/opt/mtprotoproxy"
MTP_CMD="/usr/local/bin/mtp"
CONFIG_DIR="/etc/mtg"
SERVICE_NAME="mtg"
INIT_SYSTEM=""
OS_NAME=""
SCRIPT_VERSION="2026.05.22.1"
SCRIPT_URL="https://raw.githubusercontent.com/coldboy404/MTProxy/main/mtp.sh"

check_root() { [[ "$(id -u)" != "0" ]] && echo -e "${Red}错误: 请以 root 运行！${Nc}" && exit 1; }

detect_os_name() {
    if [[ -f /etc/os-release ]]; then
        OS_NAME=$(grep -E '^PRETTY_NAME=' /etc/os-release | head -1 | cut -d= -f2- | tr -d '"')
        [[ -z "$OS_NAME" ]] && OS_NAME=$(grep -E '^NAME=' /etc/os-release | head -1 | cut -d= -f2- | tr -d '"')
    fi
    [[ -z "$OS_NAME" ]] && OS_NAME=$(uname -s)
}

detect_init_system() {
    detect_os_name
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system || -d /etc/systemd/system ]]; then
        INIT_SYSTEM="systemd"
    elif command -v rc-service >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1; then
        INIT_SYSTEM="openrc"
    else
        echo -e "${Red}错误: 仅支持 Systemd 或 OpenRC 系统。${Nc}"
        exit 1
    fi
}

is_alpine() {
    [[ -f /etc/alpine-release ]] || grep -qi '^ID=alpine' /etc/os-release 2>/dev/null
}

apt_update_install() {
    local packages="$*"
    local apt_opts="-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

    if ! apt-get update; then
        echo -e "${Yellow}apt 更新失败，尝试修复 dpkg/依赖状态后重试...${Nc}"
        DEBIAN_FRONTEND=noninteractive dpkg --configure -a || true
        DEBIAN_FRONTEND=noninteractive apt-get $apt_opts -f install -y || true
        apt-get update || return 1
    fi

    if ! DEBIAN_FRONTEND=noninteractive apt-get $apt_opts install -y $packages; then
        echo -e "${Yellow}apt 安装失败，尝试执行 dpkg --configure -a 与 apt-get -f install 后重试...${Nc}"
        DEBIAN_FRONTEND=noninteractive dpkg --configure -a || true
        DEBIAN_FRONTEND=noninteractive apt-get $apt_opts -f install -y || true
        DEBIAN_FRONTEND=noninteractive apt-get $apt_opts install -y $packages || return 1
    fi
}

install_base_deps() {
    if is_alpine && command -v apk >/dev/null 2>&1; then
        apk add --no-cache bash curl wget tar gzip iproute2 iptables ca-certificates >/dev/null || return 1
    elif command -v apt-get >/dev/null 2>&1; then
        apt_update_install curl wget tar gzip iproute2 iptables ca-certificates || return 1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl wget tar gzip iproute iptables ca-certificates || return 1
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl wget tar gzip iproute iptables ca-certificates || return 1
    fi
}

# --- 服务管理兼容层 ---
write_service_file() {
    local CORE="$1"
    local PORT="$2"
    local SECRET="$3"

    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        if [[ "$CORE" == "GO" ]]; then
            cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=MTProxy Service
After=network.target
[Service]
ExecStart=${BIN_PATH} simple-run 0.0.0.0:${PORT} ${SECRET}
Restart=always
[Install]
WantedBy=multi-user.target
EOF
        else
            cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
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
        fi
    else
        cat > /etc/init.d/${SERVICE_NAME} <<EOF
#!/sbin/openrc-run
name="MTProxy Service"
description="MTProxy Service"
supervisor="supervise-daemon"
respawn_delay=3
respawn_max=0
command_background="yes"
EOF
        if [[ "$CORE" == "GO" ]]; then
            cat >> /etc/init.d/${SERVICE_NAME} <<EOF
command="${BIN_PATH}"
command_args="simple-run 0.0.0.0:${PORT} ${SECRET}"
EOF
        else
            cat >> /etc/init.d/${SERVICE_NAME} <<EOF
directory="${PY_DIR}"
command="/usr/bin/python3"
command_args="mtprotoproxy.py config.py"
EOF
        fi
        chmod +x /etc/init.d/${SERVICE_NAME}
    fi
}

service_enable() {
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        systemctl daemon-reload && systemctl enable ${SERVICE_NAME} >/dev/null 2>&1
    else
        rc-update add ${SERVICE_NAME} default >/dev/null 2>&1
    fi
}

service_restart() {
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        systemctl restart ${SERVICE_NAME}
    else
        rc-service ${SERVICE_NAME} restart
    fi
}

service_stop() {
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        systemctl stop ${SERVICE_NAME}
    else
        rc-service ${SERVICE_NAME} stop
    fi
}

service_disable() {
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        systemctl disable ${SERVICE_NAME} >/dev/null 2>&1
    else
        rc-update del ${SERVICE_NAME} default >/dev/null 2>&1
    fi
}

service_is_active() {
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        systemctl is-active --quiet ${SERVICE_NAME}
    else
        rc-service ${SERVICE_NAME} status >/dev/null 2>&1
    fi
}

service_status() {
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        systemctl --no-pager --full status ${SERVICE_NAME} || true
    else
        rc-service ${SERVICE_NAME} status || true
        tail -n 80 /var/log/${SERVICE_NAME}.log 2>/dev/null || true
    fi
}

remove_service_file() {
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        rm -f /etc/systemd/system/${SERVICE_NAME}.service
        systemctl daemon-reload 2>/dev/null || true
        systemctl reset-failed 2>/dev/null || true
    else
        rm -f /etc/init.d/${SERVICE_NAME}
    fi
}

firewalld_active() {
    command -v firewall-cmd >/dev/null 2>&1 || return 1
    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-active --quiet firewalld 2>/dev/null
    else
        return 1
    fi
}

# --- 功能函数 ---
open_port() {
    local PORT=$1
    if firewalld_active; then
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
    if firewalld_active; then
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

# --- 核心安装逻辑 ---
install_mtp() {
    local OLD_PORT="$1"
    echo -e "${Yellow}请选择版本：${Nc}"
    echo -e "1) Go 版     (9seconds - 推荐)"
    echo -e "2) Python 版 (alexbers - 兼容)"
    read -p "选择 [1-2]: " core_choice
    [[ "$core_choice" == "2" ]] && install_py_version "$OLD_PORT" || install_go_version "$OLD_PORT"
}

install_go_version() {
    local OLD_PORT="$1"
    install_base_deps
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

    rm -rf "$PY_DIR"
    write_service_file "GO" "$PORT" "$SECRET"
    finish_install "$PORT" "$OLD_PORT"
}

install_py_deps() {
    if is_alpine && command -v apk >/dev/null 2>&1; then
        apk add --no-cache python3 python3-dev py3-pip py3-cryptography git xxd build-base linux-headers || return 1
    elif command -v apt-get >/dev/null 2>&1; then
        apt_update_install python3-dev python3-pip git xxd python3-cryptography || return 1
    else
        echo -e "${Red}Python 版当前仅支持 Alpine/Debian/Ubuntu 系统。${Nc}"
        return 1
    fi
}

pip_install_py_deps() {
    if ! command -v pip3 >/dev/null 2>&1; then
        echo -e "${Red}安装失败：未找到 pip3，请检查 Python 依赖是否安装成功。${Nc}"
        return 1
    fi

    if pip3 install pycryptodome uvloop --break-system-packages 2>/dev/null; then
        return 0
    fi
    pip3 install pycryptodome uvloop || return 1
}

install_py_version() {
    local OLD_PORT="$1"
    echo -e "${Blue}正在配置 Python 环境...${Nc}"
    echo -e "${Yellow}>>> 提示：如果下载进度卡在 'Fetched ...' 不动，请按 1-2 次回车键继续！ <<<${Nc}"

    if ! install_base_deps; then
        echo -e "${Red}安装失败：基础依赖安装失败，请先修复软件包管理器状态后重试。${Nc}"
        exit 1
    fi
    if ! install_py_deps; then
        echo -e "${Red}安装失败：Python 依赖安装失败，请先修复软件包管理器状态后重试。${Nc}"
        exit 1
    fi
    rm -rf "$PY_DIR"
    if ! git clone https://github.com/alexbers/mtprotoproxy.git "$PY_DIR"; then
        echo -e "${Red}安装失败：mtprotoproxy 源码下载失败。${Nc}"
        exit 1
    fi
    if ! pip_install_py_deps; then
        echo -e "${Red}安装失败：Python pip 依赖安装失败。${Nc}"
        exit 1
    fi

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

    rm -f "$BIN_PATH"
    write_service_file "PY" "$PORT" ""
    finish_install "$PORT" "$OLD_PORT"
}

finish_install() {
    local NEW_PORT="$1"
    local OLD_PORT="$2"

    open_port "$NEW_PORT"

    if ! service_enable; then
        echo -e "${Red}安装失败：无法启用 ${SERVICE_NAME} 服务。${Nc}"
        service_status
        exit 1
    fi

    if ! service_restart; then
        echo -e "${Red}安装失败：${SERVICE_NAME} 服务启动失败。${Nc}"
        service_status
        exit 1
    fi

    if ! service_is_active; then
        echo -e "${Red}安装失败：${SERVICE_NAME} 服务未处于运行状态。${Nc}"
        service_status
        exit 1
    fi

    if [[ -n "$OLD_PORT" && "$OLD_PORT" != "$NEW_PORT" ]]; then
        close_port "$OLD_PORT"
    fi

    if wget -qO "$MTP_CMD" "$SCRIPT_URL"; then
        chmod +x "$MTP_CMD"
    else
        echo -e "${Yellow}警告：管理脚本更新失败，但代理服务已安装成功。${Nc}"
    fi

    echo -e "\n${Green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${Nc}"
    echo -e "${Green}   安装成功！代理服务已在后台稳定运行。          ${Nc}"
    echo -e "${Yellow}   >>> 管理快捷键: ${Red}mtp${Nc}"
    echo -e "${Green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${Nc}\n"
    show_info
}

show_info() {
    [[ ! -f "${CONFIG_DIR}/config" ]] && return
    source "${CONFIG_DIR}/config"

    has_global_ipv6() {
        ip -6 addr show scope global 2>/dev/null | grep -q 'inet6'
    }

    echo -e "${Blue}正在获取公网地址...${Nc}"

    IP4=$(curl -fs4 --connect-timeout 3 --max-time 5 ip.sb 2>/dev/null \
        || curl -fs4 --connect-timeout 3 --max-time 5 ipinfo.io/ip 2>/dev/null \
        || true)

    IP6=""
    IPv6_STATUS=""
    if has_global_ipv6; then
        IP6=$(curl -fs6 --connect-timeout 3 --max-time 5 ip.sb 2>/dev/null \
            || curl -fs6 --connect-timeout 3 --max-time 5 icanhazip.com 2>/dev/null \
            || true)
        [[ -z "$IP6" ]] && IPv6_STATUS="本机未探测到可用公网 IPv6 地址"
    else
        IPv6_STATUS="本机无公网 IPv6 地址"
    fi

    echo -e "\n${Green}======= MTProxy 链接信息 (${CORE}版) =======${Nc}"
    echo -e "代理端口: ${Yellow}${PORT}${Nc} | 伪装域名: ${Blue}${DOMAIN}${Nc}"
    echo -e "代理密钥: ${Yellow}${SECRET}${Nc}"
    [[ -n "$IP4" ]] && echo -e "IPv4 链接: ${Green}tg://proxy?server=${IP4}&port=${PORT}&secret=${SECRET}${Nc}"
    [[ -n "$IP6" ]] && echo -e "IPv6 链接: ${Green}tg://proxy?server=[${IP6}]&port=${PORT}&secret=${SECRET}${Nc}"
    [[ -n "$IPv6_STATUS" ]] && echo -e "IPv6 状态: ${Yellow}${IPv6_STATUS}${Nc}"
    [[ -z "$IP4" && -z "$IP6" ]] && echo -e "${Yellow}提示：未能探测到公网 IP，可稍后手动查看。${Nc}"
    echo -e "========================================\n"
}

# --- 菜单界面 ---

menu() {
    clear
    echo -e "${Green}MTProxy (Go/Python) 多版本脚本${Nc}"
    echo -e "脚本版本: ${Yellow}${SCRIPT_VERSION}${Nc}"
    echo -e "运行环境: ${Yellow}${OS_NAME}${Nc}"
    echo -e "----------------------------------"

    if service_is_active; then
        CURRENT_CORE="未知"
        [[ -f "${CONFIG_DIR}/config" ]] && source "${CONFIG_DIR}/config" && CURRENT_CORE=$CORE
        echo -e "服务状态: ${Green}● 运行中 (${CURRENT_CORE}版)${Nc}"
    elif [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" || -f "/etc/init.d/${SERVICE_NAME}" ]]; then
        echo -e "服务状态: ${Yellow}○ 已安装 (已停止)${Nc}"
    else
        echo -e "服务状态: ${Red}○ 未安装${Nc}"
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
        2)
            if [ ! -f "${CONFIG_DIR}/config" ]; then echo -e "${Red}未安装！${Nc}"; sleep 1; menu; fi
            source "${CONFIG_DIR}/config"
            OLD_PORT="$PORT"
            install_mtp "$OLD_PORT" ;;
        3) show_info ;;
        4) update_script ;;
        5)
            if service_restart && service_is_active; then
                echo -e "${Green}服务已重启${Nc}"
            else
                echo -e "${Red}服务重启失败${Nc}"
                service_status
            fi ;;
        6)
            if service_stop; then
                echo -e "${Yellow}服务已停止${Nc}"
            else
                echo -e "${Red}服务停止失败${Nc}"
                service_status
            fi ;;
        7)
            [[ -f "${CONFIG_DIR}/config" ]] && source "${CONFIG_DIR}/config" && close_port "$PORT"
            service_stop 2>/dev/null || true
            service_disable 2>/dev/null || true
            remove_service_file
            rm -rf "$CONFIG_DIR" "$BIN_PATH" "$PY_DIR" "$MTP_CMD"
            echo -e "${Green}已彻底卸载。${Nc}" ;;
        *) exit 0 ;;
    esac
}

check_root
detect_init_system
menu
