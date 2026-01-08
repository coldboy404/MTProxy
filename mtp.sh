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

set -Eeuo pipefail
trap 'echo -e "${Red}错误: 第 ${LINENO} 行失败: ${BASH_COMMAND}${Nc}"' ERR

BIN_PATH="/usr/local/bin/mtg"
PY_DIR="/opt/mtprotoproxy"
VENV_DIR="${PY_DIR}/venv"
MTP_CMD="/usr/local/bin/mtp"
CONFIG_DIR="/etc/mtg"
SERVICE_FILE="/etc/systemd/system/mtg.service"
SCRIPT_URL="https://raw.githubusercontent.com/weaponchiang/MTProxy/main/mtp.sh"

check_root() { [[ "$(id -u)" != "0" ]] && echo -e "${Red}错误: 请以 root 运行！${Nc}" && exit 1; }
check_init_system() { [[ ! -f /usr/bin/systemctl ]] && echo -e "${Red}错误: 仅支持 Systemd 系统。${Nc}" && exit 1; }

# --- 新增：稳健 apt 安装（防 Ctrl+C 打断 / dpkg 半安装） ---
apt_install() {
    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    export APT_LISTCHANGES_FRONTEND=none
    export UCF_FORCE_CONFFNEW=1

    local OPTS=(
      -y --no-install-recommends
      -o Dpkg::Use-Pty=0
      -o Dpkg::Lock::Timeout=180
      -o Dpkg::Options::=--force-confdef
      -o Dpkg::Options::=--force-confold
    )

    echo -e "${Yellow}[TIP] 安装依赖中：下载完成后会解包/配置，可能几分钟无输出，请不要 Ctrl+C。${Nc}"
    trap 'echo -e "\n${Yellow}[TIP] 依赖安装进行中，已忽略 Ctrl+C，请等待完成...${Nc}"' INT

    dpkg --configure -a >/dev/null 2>&1 || true
    apt-get -f install -y >/dev/null 2>&1 || true

    apt-get "${OPTS[@]}" update
    stdbuf -oL -eL apt-get "${OPTS[@]}" install "$@"

    trap - INT
}

open_port() {
    local PORT=$1
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --zone=public --add-port=${PORT}/tcp --permanent && firewall-cmd --reload
    fi
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        ufw allow ${PORT}/tcp
    fi
    iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT 2>/dev/null || true
}

close_port() {
    local PORT=$1
    [[ -z "$PORT" ]] && return
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --zone=public --remove-port=${PORT}/tcp --permanent && firewall-cmd --reload
    fi
    [[ -x "$(command -v ufw)" ]] && ufw delete allow ${PORT}/tcp >/dev/null 2>&1 || true
    iptables -D INPUT -p tcp --dport ${PORT} -j ACCEPT 2>/dev/null || true
}

update_script() {
    echo -e "${Blue}正在从远程更新脚本...${Nc}"
    TMP_FILE=$(mktemp)
    if wget -qO "$TMP_FILE" "$SCRIPT_URL"; then
        mv "$TMP_FILE" "$MTP_CMD" && chmod +x "$MTP_CMD"
        cp "$MTP_CMD" "$0" 2>/dev/null || true
        echo -e "${Green}管理脚本更新成功！请重新运行。${Nc}"
        exit 0
    else
        echo -e "${Red}更新失败，请检查网络。${Nc}"
    fi
}

install_mtp() {
    echo -e "${Yellow}请选择版本：${Nc}"
    echo -e "1) Go 版      (9seconds - 推荐)"
    echo -e "2) Python 版  (alexbers - 兼容)"
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

    if ! command -v apt-get >/dev/null 2>&1; then
        echo -e "${Red}当前系统未检测到 apt-get，Python 版安装仅对 Debian/Ubuntu 做了自动依赖。${Nc}"
        exit 1
    fi

    # 关键修复：用 apt_install（防 Ctrl+C 打断）+ venv（避免 break-system-packages）
    apt_install python3-dev python3-pip git xxd python3-cryptography python3-venv python3.13-venv

    command -v xxd >/dev/null 2>&1 || { echo -e "${Red}xxd 未安装成功（依赖被中断）。${Nc}"; exit 1; }
    command -v python3 >/dev/null 2>&1 || { echo -e "${Red}python3 不存在。${Nc}"; exit 1; }

    rm -rf "$PY_DIR"
    git clone https://github.com/alexbers/mtprotoproxy.git "$PY_DIR"

    echo -e "${Blue}创建 venv 并安装依赖...${Nc}"
    python3 -m venv "$VENV_DIR" || { echo -e "${Red}venv 创建失败，请确认 python3.13-venv 已安装。${Nc}"; exit 1; }
    [[ -x "${VENV_DIR}/bin/pip" ]] || { echo -e "${Red}venv pip 不存在（ensurepip 缺失）。${Nc}"; exit 1; }

    "${VENV_DIR}/bin/pip" install -U pip wheel setuptools
    "${VENV_DIR}/bin/pip" install pycryptodome

    mkdir -p "$CONFIG_DIR"
    read -p "伪装域名 (默认: azure.microsoft.com): " DOMAIN
    DOMAIN=${DOMAIN:-azure.microsoft.com}
    RAW_S=$(head -c 16 /dev/urandom | xxd -ps -c 16 | tr -d '[:space:]')
    D_HEX=$(echo -n "$DOMAIN" | xxd -p -c 256 | tr -d '[:space:]')
    read -p "监听端口 (默认随机): " PORT
    PORT=${PORT:-$((10000 + RANDOM % 20000))}

    SECRET="ee${RAW_S}${D_HEX}"
    [[ "$SECRET" =~ ^ee[0-9a-f]+$ ]] || { echo -e "${Red}SECRET 生成失败：$SECRET${Nc}"; exit 1; }

    echo -e "CORE=PY\nPORT=${PORT}\nSECRET=${SECRET}\nDOMAIN=${DOMAIN}" > "${CONFIG_DIR}/config"
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
ExecStart=${VENV_DIR}/bin/python mtprotoproxy.py config.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    finish_install "$PORT"
}

finish_install() {
    open_port "$1"
    # 你要求的修复：enable --now
    systemctl daemon-reload && systemctl enable --now mtg
    wget -qO "$MTP_CMD" "$SCRIPT_URL" && chmod +x "$MTP_CMD" || true
    echo -e "${Green}安装成功！${Nc}"
    show_info
}

show_info() {
    [[ ! -f "${CONFIG_DIR}/config" ]] && return
    # shellcheck disable=SC1090
    source "${CONFIG_DIR}/config"
    IP4=$(curl -s4 --connect-timeout 5 ip.sb || curl -s4 ipinfo.io/ip || true)
    IP6=$(curl -s6 --connect-timeout 5 ip.sb || curl -s6 icanhazip.com || true)
    echo -e "\n${Green}======= MTProxy 信息 =======${Nc}"
    echo -e "端口: ${Yellow}${PORT}${Nc} | 域名: ${Blue}${DOMAIN}${Nc}"
    echo -e "密钥: ${Yellow}${SECRET}${Nc}"
    [[ -n "$IP4" ]] && echo -e "IPv4: ${Green}tg://proxy?server=${IP4}&port=${PORT}&secret=${SECRET}${Nc}"
    [[ -n "$IP6" ]] && echo -e "IPv6: ${Green}tg://proxy?server=[${IP6}]&port=${PORT}&secret=${SECRET}${Nc}"
    echo -e "============================\n"
}

uninstall_all() {
    echo -e "${Yellow}正在卸载...${Nc}"
    if [[ -f "${CONFIG_DIR}/config" ]]; then
      # shellcheck disable=SC1090
      source "${CONFIG_DIR}/config" || true
      close_port "${PORT:-}"
    fi
    systemctl stop mtg 2>/dev/null || true
    systemctl disable mtg 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload || true
    rm -rf "$CONFIG_DIR" "$PY_DIR" "$BIN_PATH" "$MTP_CMD"
    echo -e "${Green}已卸载。${Nc}"
    exit 0
}

menu() {
    systemctl daemon-reload >/dev/null 2>&1 || true
    clear
    echo -e "${Green}MTProxy (Go/Python) 管理脚本${Nc}"
    echo -e "----------------------------------"
    if systemctl is-active --quiet mtg; then
        # shellcheck disable=SC1090
        source "${CONFIG_DIR}/config" 2>/dev/null || true
        echo -e "服务状态: ${Green}● 运行中 (${CORE:-版})${Nc}"
    elif [[ ! -f "$SERVICE_FILE" ]]; then
        echo -e "服务状态: ${Yellow}○ 未安装${Nc}"
    else
        echo -e "服务状态: ${Red}○ 已停止${Nc}"
    fi
    echo -e "----------------------------------"
    echo -e "1. 安 装  / 重 置"
    echo -e "2. 修 改 配 置"
    echo -e "3. 查 看 信 息"
    echo -e "4. 更 新 脚 本"
    echo -e "5. 重 启 服 务"
    echo -e "6. 停 止 服 务"
    echo -e "7. 卸 载 程 序"
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