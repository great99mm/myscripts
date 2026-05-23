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

need_sudo() {
    [[ $EUID -ne 0 ]]
}

if need_sudo && ! command -v sudo >/dev/null 2>&1; then
    err "当前不是 root，且系统没有 sudo，没法继续升级"
    exit 1
fi

command -v curl >/dev/null 2>&1 || {
    err "缺少 curl，请先安装 curl"
    exit 1
}

command -v tar >/dev/null 2>&1 || {
    err "缺少 tar，请先安装 tar"
    exit 1
}

log "下载 ${REPO_OWNER}/${REPO_NAME}..."
curl -fsSL "$ARCHIVE_URL" | tar -xz -C "$TMP_DIR"

UPGRADE_SCRIPT="$TMP_DIR/$ARCHIVE_ROOT/$SCRIPT_SUBDIR/upgrade.sh"
if [[ ! -f "$UPGRADE_SCRIPT" ]]; then
    err "没找到升级脚本: $UPGRADE_SCRIPT"
    exit 1
fi

if need_sudo; then
    exec sudo bash "$UPGRADE_SCRIPT"
else
    exec bash "$UPGRADE_SCRIPT"
fi
