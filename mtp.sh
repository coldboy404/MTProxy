#!/usr/bin/env bash
#=========================================================
# MTProxy (Go / Python) One-click Installer
# Debian 11 / 12 / 13 | Ubuntu 20.04+
#=========================================================

set -Eeuo pipefail
IFS=$'\n\t'

Red="\033[31m"; Green="\033[32m"; Yellow="\033[33m"; Blue="\033[34m"; Nc="\033[0m"

BIN_PATH="/usr/local/bin/mtg"
PY_DIR="/opt/mtprotoproxy"
VENV_DIR="${PY_DIR}/venv"
CONFIG_DIR="/etc/mtg"
SERVICE_FILE="/etc/systemd/system/mtg.service"
SCRIPT_URL="https://raw.githubusercontent.com/weaponchiang/MTProxy/main/mtp.sh"

trap 'echo -e "${Red}错误：第 ${LINENO} 行命令失败：${BASH_COMMAND}${Nc}"; exit 1' ERR

check_root() { [[ "$(id -u)" == "0" ]] || { echo -e "${Red}请使用 root 运行${Nc}"; exit 1; }; }
check_systemd() { [[ -x /usr/bin/systemctl ]] || { echo -e "${Red}仅支持 systemd 系统${Nc}"; exit 1; }; }

# ---------------- APT 安装（防 Ctrl+C / dpkg 锁） ----------------
apt_install() {
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a
  export APT_LISTCHANGES_FRONTEND=none

  local OPTS=(
    -y --no-install-recommends
    -o Dpkg::Use-Pty=0
    -o Dpkg::Lock::Timeout=180
    -o Dpkg::Options::=--force-confdef
    -o Dpkg::Options::=--force-confold
  )

  echo -e "${Yellow}[TIP] 正在安装系统依赖，下载后会解包/配置，可能几分钟无输出，请勿 Ctrl+C${Nc}"

  trap 'echo -e "\n${Yellow}[TIP] apt 安装中，已忽略 Ctrl+C，请等待完成...${Nc}"' INT

  dpkg --configure -a >/dev/null 2>&1 || true
  apt-get -f install -y >/dev/null 2>&1 || true

  apt-get "${OPTS[@]}" update
  stdbuf -oL -eL apt-get "${OPTS[@]}" install "$@"

  trap - INT
}

# ---------------- 防火墙 ----------------
open_port() {
  iptables -I INPUT -p tcp --dport "$1" -j ACCEPT 2>/dev/null || true
}

# ---------------- Python 版 ----------------
install_python() {
  echo -e "${Blue}[INFO] 安装 Python 版 MTProxy${Nc}"

  apt_install \
    ca-certificates curl git xxd \
    python3 python3-dev python3-pip \
    python3-venv python3.13-venv \
    python3-cryptography build-essential

  for c in git xxd python3; do
    command -v "$c" >/dev/null || { echo -e "${Red}缺少依赖：$c${Nc}"; exit 1; }
  done

  rm -rf "$PY_DIR"
  git clone --depth=1 https://github.com/alexbers/mtprotoproxy.git "$PY_DIR"

  echo -e "${Blue}[INFO] 创建 venv${Nc}"
  python3 -m venv "$VENV_DIR"
  [[ -x "$VENV_DIR/bin/python" ]] || { echo -e "${Red}venv 创建失败${Nc}"; exit 1; }

  "$VENV_DIR/bin/pip" install -U pip wheel setuptools
  "$VENV_DIR/bin/pip" install pycryptodome

  mkdir -p "$CONFIG_DIR"

  read -r -p "伪装域名 (默认 azure.microsoft.com): " DOMAIN
  DOMAIN="${DOMAIN:-azure.microsoft.com}"

  RAW_S="$(head -c 16 /dev/urandom | xxd -ps)"
  D_HEX="$(echo -n "$DOMAIN" | xxd -p)"

  read -r -p "监听端口 (默认随机): " PORT
  PORT="${PORT:-$((10000 + RANDOM % 20000))}"

  SECRET="ee${RAW_S}${D_HEX}"
  [[ "$SECRET" =~ ^ee[0-9a-f]+$ ]] || { echo -e "${Red}SECRET 生成失败${Nc}"; exit 1; }

  cat > "${CONFIG_DIR}/config" <<EOF
CORE=PY
PORT=${PORT}
SECRET=${SECRET}
DOMAIN=${DOMAIN}
EOF

  cat > "${PY_DIR}/config.py" <<EOF
PORT = ${PORT}
USERS = { "tg": "${RAW_S}" }
MODES = { "classic": False, "secure": False, "tls": True }
TLS_DOMAIN = "${DOMAIN}"
EOF

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=MTProxy (Python)
After=network.target

[Service]
WorkingDirectory=${PY_DIR}
ExecStart=${VENV_DIR}/bin/python ${PY_DIR}/mtprotoproxy.py ${PY_DIR}/config.py
Restart=always
RestartSec=2
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  open_port "$PORT"
  systemctl daemon-reload
  systemctl enable --now mtg

  show_info
}

# ---------------- 信息 ----------------
show_info() {
  source "${CONFIG_DIR}/config"
  IP4="$(curl -s4 ip.sb || true)"
  IP6="$(curl -s6 ip.sb || true)"

  echo -e "\n${Green}======= MTProxy 信息 =======${Nc}"
  echo -e "端口: ${PORT}"
  echo -e "域名: ${DOMAIN}"
  echo -e "密钥: ${SECRET}"
  [[ -n "$IP4" ]] && echo -e "IPv4: tg://proxy?server=${IP4}&port=${PORT}&secret=${SECRET}"
  [[ -n "$IP6" ]] && echo -e "IPv6: tg://proxy?server=[${IP6}]&port=${PORT}&secret=${SECRET}"
  echo -e "============================\n"
}

# ---------------- 菜单 ----------------
menu() {
  clear
  echo -e "${Green}MTProxy 管理脚本${Nc}"
  echo "----------------------------------"
  systemctl is-active --quiet mtg && echo -e "服务状态: ${Green}运行中${Nc}" || echo -e "服务状态: ${Yellow}未运行${Nc}"
  echo "----------------------------------"
  echo "1. 安装 Python 版"
  echo "2. 查看信息"
  echo "3. 重启服务"
  echo "4. 停止服务"
  echo "0. 退出"
  read -r -p "选择 [0-4]: " c
  case "$c" in
    1) install_python ;;
    2) show_info ;;
    3) systemctl restart mtg ;;
    4) systemctl stop mtg ;;
    *) exit 0 ;;
  esac
}

check_root
check_systemd
menu