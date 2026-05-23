#!/usr/bin/env bash
set -Eeuo pipefail

PREFIX="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"
ENV_DIR="/etc/default"
APP_NAME="clouddrive2-mover"
SERVICE_NAME="clouddrive2-mover.service"
TIMER_NAME="clouddrive2-mover.timer"

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

err() {
    printf '[%s] ERROR: %s\n' "$(date '+%F %T')" "$*" >&2
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        err "缺少命令: $1"
        exit 1
    }
}

detect_pkg_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo apt
    elif command -v dnf >/dev/null 2>&1; then
        echo dnf
    elif command -v yum >/dev/null 2>&1; then
        echo yum
    elif command -v pacman >/dev/null 2>&1; then
        echo pacman
    else
        echo unknown
    fi
}

install_packages() {
    local manager="$1"
    shift
    local packages=("$@")

    case "$manager" in
        apt)
            apt-get update
            apt-get install -y "${packages[@]}"
            ;;
        dnf)
            dnf install -y "${packages[@]}"
            ;;
        yum)
            yum install -y "${packages[@]}"
            ;;
        pacman)
            pacman -Sy --noconfirm "${packages[@]}"
            ;;
        *)
            err "不支持自动安装依赖，请手动安装: ${packages[*]}"
            exit 1
            ;;
    esac
}

ensure_cmd() {
    local cmd="$1"
    local package="$2"
    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi

    local manager
    manager="$(detect_pkg_manager)"
    log "缺少 $cmd，尝试自动安装包: $package"
    install_packages "$manager" "$package"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        err "安装后仍然缺少命令: $cmd"
        exit 1
    fi
}

require_systemd() {
    require_cmd systemctl
    if [[ ! -d /run/systemd/system ]]; then
        err "当前系统不是 systemd 环境，不能安装 timer 服务"
        exit 1
    fi
}

check_src_dir() {
    if [[ ! -e "$SRC_DIR" ]]; then
        err "源目录不存在: $SRC_DIR"
        err "请先确认 CloudDrive2 已挂载，或者通过 SRC_DIR 指定正确路径"
        exit 1
    fi
}

validate_config() {
    if ! [[ "$CONCURRENCY" =~ ^[0-9]+$ ]] || (( CONCURRENCY < 1 )); then
        err "并发数必须是大于等于 1 的整数，当前: $CONCURRENCY"
        exit 1
    fi
}

self_check() {
    log "开始安装后自检"

    if ! systemctl list-unit-files "$SERVICE_NAME" >/dev/null 2>&1; then
        err "service 未正确安装: $SERVICE_NAME"
        exit 1
    fi

    if ! systemctl list-unit-files "$TIMER_NAME" >/dev/null 2>&1; then
        err "timer 未正确安装: $TIMER_NAME"
        exit 1
    fi

    if [[ "$ENABLE_NOW" == "1" ]]; then
        if ! systemctl is-enabled "$TIMER_NAME" >/dev/null 2>&1; then
            err "timer 未启用: $TIMER_NAME"
            exit 1
        fi
    fi

    if ! bash "$PREFIX/clouddrive2-mover.sh" --self-check; then
        err "主脚本自检失败"
        exit 1
    fi

    log "自检完成"
}

test_telegram() {
    [[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]] || return 0

    log "发送 Telegram 测试消息"
    if curl -fsS -X POST \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TG_CHAT_ID}" \
        --data-urlencode "text=CloudDrive2 Mover 安装完成，Telegram 通知测试成功。" \
        >/dev/null; then
        log "Telegram 测试消息发送成功"
    else
        err "Telegram 测试消息发送失败，请检查 TG_BOT_TOKEN 和 TG_CHAT_ID"
        err "配置文件已写入，可稍后修改: $ENV_DIR/clouddrive2-mover"
    fi
}

usage() {
    cat <<'EOF'
用法:
  sudo bash install.sh

可选环境变量:
  SRC_DIR=/opt/media/CloudDrive
  DST_DIR=/opt/media/115完成
  STAGE_DIR=/opt/media/115完成/.staging
  LOG_DIR=/var/log/clouddrive2-mover
  ENABLE_NOW=1
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $EUID -ne 0 ]]; then
    err "请用 root 执行安装脚本。"
    exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

SRC_DIR="${SRC_DIR:-/opt/media/CloudDrive}"
DST_DIR="${DST_DIR:-/opt/media/115完成}"
STAGE_DIR="${STAGE_DIR:-/opt/media/115mvtmp/.staging}"
LOG_DIR="${LOG_DIR:-/var/log/clouddrive2-mover}"
LOCK_FILE="${LOCK_FILE:-/run/clouddrive2-mover.lock}"
RETRY_TIMES="${RETRY_TIMES:-3}"
RETRY_DELAY="${RETRY_DELAY:-10}"
STABLE_CHECKS="${STABLE_CHECKS:-2}"
STABLE_INTERVAL="${STABLE_INTERVAL:-5}"
OVERWRITE="${OVERWRITE:-0}"
CLEAN_EMPTY_DIRS="${CLEAN_EMPTY_DIRS:-1}"
CHECK_MOUNTPOINT="${CHECK_MOUNTPOINT:-1}"
ENABLE_NOW="${ENABLE_NOW:-1}"
DRY_RUN="${DRY_RUN:-0}"
CONCURRENCY="${CONCURRENCY:-2}"
TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"
TG_CHAT_ID="${TG_CHAT_ID:-}"

prompt_input() {
    local var_name="$1"
    local prompt_text="$2"
    local default_value="$3"
    local secret="${4:-0}"
    local input=""

    if [[ ! -r /dev/tty ]]; then
        printf -v "$var_name" '%s' "$default_value"
        return 0
    fi

    if [[ "$secret" == "1" ]]; then
        read -r -s -p "$prompt_text: " input </dev/tty
        printf '\n' >/dev/tty
    else
        read -r -p "$prompt_text [$default_value]: " input </dev/tty
    fi

    if [[ "$secret" != "1" ]]; then
        input="${input:-$default_value}"
    fi
    printf -v "$var_name" '%s' "$input"
}

prompt_yes_no() {
    local var_name="$1"
    local prompt_text="$2"
    local default_value="$3"
    local input=""

    if [[ ! -r /dev/tty ]]; then
        printf -v "$var_name" '%s' "$default_value"
        return 0
    fi

    read -r -p "$prompt_text [$default_value]: " input </dev/tty
    input="${input:-$default_value}"
    case "$input" in
        y|Y|yes|YES|1) printf -v "$var_name" '1' ;;
        n|N|no|NO|0) printf -v "$var_name" '0' ;;
        *) printf -v "$var_name" '%s' "$default_value" ;;
    esac
}

interactive_config() {
    prompt_input SRC_DIR "请输入 CloudDrive2 挂载源目录" "$SRC_DIR"
    prompt_input DST_DIR "请输入本地目标目录" "$DST_DIR"
    prompt_input STAGE_DIR "请输入 staging 临时目录" "$STAGE_DIR"
    prompt_input LOG_DIR "请输入日志目录" "$LOG_DIR"
    prompt_input CONCURRENCY "请输入并发数" "$CONCURRENCY"
    prompt_yes_no CHECK_MOUNTPOINT "是否开启挂载点检查？(y/n)" "$CHECK_MOUNTPOINT"
    prompt_yes_no DRY_RUN "首次运行是否启用 dry-run？(y/n)" "$DRY_RUN"
    prompt_input TG_BOT_TOKEN "请输入 Telegram Bot Token，可留空" "$TG_BOT_TOKEN" 1
    prompt_input TG_CHAT_ID "请输入 Telegram Chat ID，可留空" "$TG_CHAT_ID"
    prompt_yes_no ENABLE_NOW "安装后是否立即启用定时器？(y/n)" "$ENABLE_NOW"
}

interactive_config
ensure_cmd install coreutils
ensure_cmd rsync rsync
ensure_cmd curl curl
ensure_cmd find findutils
ensure_cmd stat coreutils
ensure_cmd flock util-linux
if [[ "$CHECK_MOUNTPOINT" == "1" ]]; then
    ensure_cmd mountpoint util-linux
fi
require_systemd
check_src_dir
validate_config

log "安装 ${APP_NAME}"
log "源目录: $SRC_DIR"
log "目标目录: $DST_DIR"

install -d -m 755 "$PREFIX" "$SYSTEMD_DIR" "$ENV_DIR" "$LOG_DIR" "$STAGE_DIR" "$DST_DIR"
install -m 755 "$SCRIPT_DIR/clouddrive2-mover.sh" "$PREFIX/clouddrive2-mover.sh"
install -m 755 "$SCRIPT_DIR/uninstall.sh" "$PREFIX/clouddrive2-mover-uninstall.sh"
install -m 755 "$SCRIPT_DIR/upgrade.sh" "$PREFIX/clouddrive2-mover-upgrade.sh"
install -m 644 "$SCRIPT_DIR/clouddrive2-mover.service" "$SYSTEMD_DIR/clouddrive2-mover.service"
install -m 644 "$SCRIPT_DIR/clouddrive2-mover.timer" "$SYSTEMD_DIR/clouddrive2-mover.timer"

write_env() {
    {
        printf 'SRC_DIR=%q\n' "$SRC_DIR"
        printf 'DST_DIR=%q\n' "$DST_DIR"
        printf 'STAGE_DIR=%q\n' "$STAGE_DIR"
        printf 'LOG_DIR=%q\n' "$LOG_DIR"
        printf 'LOCK_FILE=%q\n' "$LOCK_FILE"
        printf 'RETRY_TIMES=%q\n' "$RETRY_TIMES"
        printf 'RETRY_DELAY=%q\n' "$RETRY_DELAY"
        printf 'STABLE_CHECKS=%q\n' "$STABLE_CHECKS"
        printf 'STABLE_INTERVAL=%q\n' "$STABLE_INTERVAL"
        printf 'OVERWRITE=%q\n' "$OVERWRITE"
        printf 'CLEAN_EMPTY_DIRS=%q\n' "$CLEAN_EMPTY_DIRS"
        printf 'CHECK_MOUNTPOINT=%q\n' "$CHECK_MOUNTPOINT"
        printf 'DRY_RUN=%q\n' "$DRY_RUN"
        printf 'CONCURRENCY=%q\n' "$CONCURRENCY"
        printf 'TG_BOT_TOKEN=%q\n' "$TG_BOT_TOKEN"
        printf 'TG_CHAT_ID=%q\n' "$TG_CHAT_ID"
    } > "$ENV_DIR/clouddrive2-mover"
}

write_env

systemctl daemon-reload

if [[ "$ENABLE_NOW" == "1" ]]; then
    systemctl enable --now clouddrive2-mover.timer
fi

self_check
test_telegram

cat <<EOF
安装完成。

配置文件:
  $ENV_DIR/clouddrive2-mover

脚本路径:
  $PREFIX/clouddrive2-mover.sh
  $PREFIX/clouddrive2-mover-uninstall.sh
  $PREFIX/clouddrive2-mover-upgrade.sh

常用命令:
  systemctl status clouddrive2-mover.timer
  systemctl start clouddrive2-mover.service
  journalctl -u clouddrive2-mover.service -f

如需修改配置:
  编辑 $ENV_DIR/clouddrive2-mover
  然后执行 systemctl restart clouddrive2-mover.timer

卸载:
  sudo bash $PREFIX/clouddrive2-mover-uninstall.sh

升级:
  curl -fsSL https://raw.githubusercontent.com/great99mm/myscripts/main/upgrade-clouddrive2-mover.sh | bash
EOF
