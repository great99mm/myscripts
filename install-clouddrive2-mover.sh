#!/usr/bin/env bash
set -Eeuo pipefail

REPO_OWNER="great99mm"
REPO_NAME="myscripts"
BRANCH="main"
SCRIPT_SUBDIR="clouddrive2-mover"

TMP_DIR="$(mktemp -d)"
ARCHIVE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${BRANCH}.tar.gz"
ARCHIVE_ROOT="${REPO_NAME}-${BRANCH}"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

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

need_sudo() {
    [[ $EUID -ne 0 ]]
}

run_privileged() {
    if need_sudo; then
        sudo "$@"
    else
        "$@"
    fi
}

install_packages() {
    local manager="$1"
    shift
    local packages=("$@")

    case "$manager" in
        apt)
            run_privileged apt-get update
            run_privileged apt-get install -y "${packages[@]}"
            ;;
        dnf)
            run_privileged dnf install -y "${packages[@]}"
            ;;
        yum)
            run_privileged yum install -y "${packages[@]}"
            ;;
        pacman)
            run_privileged pacman -Sy --noconfirm "${packages[@]}"
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
    if ! command -v systemctl >/dev/null 2>&1; then
        err "系统没有 systemctl，不能安装 systemd 服务"
        exit 1
    fi

    if [[ ! -d /run/systemd/system ]]; then
        err "当前系统看起来不是 systemd 环境"
        exit 1
    fi
}

check_source_dir_hint() {
    local src_dir="${SRC_DIR:-/opt/media/CloudDrive}"
    if [[ ! -e "$src_dir" ]]; then
        err "源目录不存在: $src_dir"
        err "先确认 CloudDrive2 已挂载，或者安装时传入正确的 SRC_DIR"
        exit 1
    fi
}

if need_sudo && ! command -v sudo >/dev/null 2>&1; then
    err "当前不是 root，且系统没有 sudo，没法继续安装"
    exit 1
fi

ensure_cmd curl curl
ensure_cmd tar tar
require_systemd
check_source_dir_hint

log "下载 ${REPO_OWNER}/${REPO_NAME}..."
curl -fsSL "$ARCHIVE_URL" | tar -xz -C "$TMP_DIR"

INSTALL_SCRIPT="$TMP_DIR/$ARCHIVE_ROOT/$SCRIPT_SUBDIR/install.sh"
if [[ ! -f "$INSTALL_SCRIPT" ]]; then
    err "没找到安装脚本: $INSTALL_SCRIPT"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    exec sudo --preserve-env=SRC_DIR,DST_DIR,STAGE_DIR,LOG_DIR,LOCK_FILE,RETRY_TIMES,RETRY_DELAY,STABLE_CHECKS,STABLE_INTERVAL,OVERWRITE,CLEAN_EMPTY_DIRS,CHECK_MOUNTPOINT,ENABLE_NOW bash "$INSTALL_SCRIPT"
else
    exec bash "$INSTALL_SCRIPT"
fi
