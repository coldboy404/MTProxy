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

# 遇到错误不立即退出，由逻辑控制
set -u

# --- 全局配置 ---
BIN_PATH="/usr/local/bin/mtg"
CONFIG_DIR="/etc/mtg"
# 默认 fallback 版本，以防 API 失败
DEFAULT_VERSION="v2.1.7"

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
    
    # 检测包管理器
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
        echo -e "${Red}未检测到支持的包管理器，请手动安装 curl, wget, tar。${Nc}"
        return
    fi

    deps="curl wget tar grep coreutils"
    for dep in $deps; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo -e "安装依赖: ${Yellow}$dep${Nc}"
            $PM_INSTALL $dep
        fi
    done
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
    # 尝试从 GitHub API 获取最新版本号
    latest_version=$(curl -s https://api.github.com/repos/9seconds/mtg/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$latest_version" ]; then
        echo "$DEFAULT_VERSION"
    else
        echo "$latest_version"
    fi
}

# --- 2. 核心功能函数 ---

install_mtg() {
    check_deps
    ARCH=$(detect_arch)
    if [ "$ARCH" = "unsupported" ]; then 
        echo -e "${Red}不支持的架构: $(uname -m)${Nc}"
        exit 1
    fi

    echo -e "${Blue}正在获取最新版本信息...${Nc}"
    VERSION=$(get_latest_version)
    echo -e "检测到最新版本: ${Green}${VERSION}${Nc}"

    # 构造下载链接 (适配 9seconds/mtg 的命名规则)
    # 文件名格式通常为: mtg-<version>-linux-<arch>.tar.gz
    # 注意：版本号 v2.x.x 在文件名中通常不带 'v'，需要去掉
    VER_NUM=${VERSION#v}
    FILENAME="mtg-${VER_NUM}-linux-${ARCH}.tar.gz"
    DOWNLOAD_URL="https://github.com/9seconds/mtg/releases/download/${VERSION}/${FILENAME}"

    TMP_DIR=$(mktemp -d)
    echo -e "${Blue}正在下载: ${DOWNLOAD_URL}${Nc}"
    
    if ! wget -q --show-progress -O "${TMP_DIR}/${FILENAME}" "$DOWNLOAD_URL"; then
        echo -e "${Red}下载失败！请检查网络或 GitHub 连接。${Nc}"
        rm -rf "$TMP_DIR"
        exit 1
    fi

    echo "正在解压..."
    tar -xzf "${TMP_DIR}/${FILENAME}" -C "${TMP_DIR}"
    # 查找解压后的二进制文件
    BINARY=$(find "${TMP_DIR}" -type f -name mtg | head -n 1)
    
    if [ -f "$BINARY" ]; then
        mv "$BINARY" "$BIN_PATH"
        chmod +x "$BIN_PATH"
        echo -e "${Green}MTG 主程序安装成功！${Nc}"
    else
        echo -e "${Red}解压失败，未找到二进制文件。${Nc}"
        rm -rf "$TMP_DIR"
        exit 1
    fi
    rm -rf "$TMP_DIR"

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
    if [ -z "$PORT" ]; then
        PORT=$((10000 + RANDOM % 20000))
    fi

    # 保存配置
    echo "PORT=${PORT}" > "${CONFIG_DIR}/config"
    echo "SECRET=${SECRET}" >> "${CONFIG_DIR}/config"
    echo "DOMAIN=${DOMAIN}" >> "${CONFIG_DIR}/config"

    install_service "$PORT" "$SECRET"
}

install_service() {
    PORT=$1
    SECRET=$2
    SERVICE_FILE=""

    if [ "$INIT_SYSTEM" = "systemd" ]; then
        SERVICE_FILE="/etc/systemd/system/mtg.service"
        cat > "$SERVICE_FILE" <<EOF
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

    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        SERVICE_FILE="/etc/init.d/mtg"
        cat > "$SERVICE_FILE" <<EOF
#!/sbin/openrc-run
name="mtg"
command="${BIN_PATH}"
command_args="simple-run 0.0.0.0:${PORT} ${SECRET}"
command_background=true
pidfile="/run/mtg.pid"
depend() {
    need net
}
EOF
        chmod +x "$SERVICE_FILE"
        rc-update add mtg default
        rc-service mtg restart
    fi

    echo -e "${Green}服务安装并启动成功！${Nc}"
    show_info
}

# --- 3. 管理功能 ---

show_info() {
    if [ ! -f "${CONFIG_DIR}/config" ]; then
        echo -e "${Red}未检测到配置文件，请先安装。${Nc}"
        return
    fi
    source "${CONFIG_DIR}/config"
    
    # 获取 IP
    IPV4=$(curl -s4 --connect-timeout 3 ip.sb 2>/dev/null || echo "无法获取")
    
    echo -e "\n${Green}======= MTProxy 配置信息 =======${Nc}"
    echo -e "IP地址: ${Yellow}${IPV4}${Nc}"
    echo -e "端口  : ${Yellow}${PORT}${Nc}"
    echo -e "密钥  : ${Yellow}${SECRET}${Nc}"
    echo -e "域名  : ${Blue}${DOMAIN}${Nc}"
    echo -e "--------------------------------"
    echo -e "TG链接: ${Green}tg://proxy?server=${IPV4}&port=${PORT}&secret=${SECRET}${Nc}"
    echo -e "================================\n"
}

enable_bbr() {
    echo -e "${Blue}正在检测 BBR...${Nc}"
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        echo -e "${Green}BBR 已经开启，无需重复操作。${Nc}"
    else
        echo "正在开启 BBR..."
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
        echo -e "${Green}BBR 开启成功！${Nc}"
    fi
}

uninstall_mtg() {
    read -p "确定要卸载吗？(y/n): " confirm
    [[ "$confirm" != "y" ]] && return

    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl stop mtg
        systemctl disable mtg
        rm -f /etc/systemd/system/mtg.service
        systemctl daemon-reload
    else
        rc-service mtg stop
        rc-update del mtg default
        rm -f /etc/init.d/mtg
    fi

    rm -f "$BIN_PATH"
    rm -rf "$CONFIG_DIR"
    echo -e "${Green}卸载完成。${Nc}"
}

# --- 4. 菜单逻辑 ---

menu() {
    clear
    echo -e "${Green}MTProxy (Go版) 一键管理脚本${Nc}"
    echo -e "----------------------------"
    echo -e "1. 安装 / 重置配置"
    echo -e "2. 查看 链接信息"
    echo -e "3. 开启 BBR 加速"
    echo -e "4. 停止 服务"
    echo -e "5. 重启 服务"
    echo -e "6. 卸载 MTProxy"
    echo -e "0. 退出"
    echo -e "----------------------------"
    read -p "请选择 [0-6]: " choice

    case "$choice" in
        1) install_mtg ;;
        2) show_info ;;
        3) enable_bbr ;;
        4) 
           if [ "$INIT_SYSTEM" = "systemd" ]; then systemctl stop mtg; else rc-service mtg stop; fi
           echo "已停止" ;;
        5) 
           if [ "$INIT_SYSTEM" = "systemd" ]; then systemctl restart mtg; else rc-service mtg restart; fi
           echo "已重启" ;;
        6) uninstall_mtg ;;
        0) exit 0 ;;
        *) echo "无效输入" ;;
    esac
}

# --- 入口 ---
check_root
check_init_system

if [ $# -gt 0 ]; then
    # 支持命令行参数，方便非交互模式
    case "$1" in
        install) install_mtg ;;
        uninstall) uninstall_mtg ;;
        info) show_info ;;
        *) echo "Usage: $0 {install|uninstall|info}" ;;
    esac
else
    menu
fi
