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

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "缺少命令: $1" >&2
        exit 1
    }
}

require_cmd curl
require_cmd tar

echo "下载 ${REPO_OWNER}/${REPO_NAME}..."
curl -fsSL "$ARCHIVE_URL" | tar -xz -C "$TMP_DIR"

INSTALL_SCRIPT="$TMP_DIR/$ARCHIVE_ROOT/$SCRIPT_SUBDIR/install.sh"
if [[ ! -f "$INSTALL_SCRIPT" ]]; then
    echo "没找到安装脚本: $INSTALL_SCRIPT" >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    exec sudo --preserve-env=SRC_DIR,DST_DIR,STAGE_DIR,LOG_DIR,LOCK_FILE,RETRY_TIMES,RETRY_DELAY,STABLE_CHECKS,STABLE_INTERVAL,OVERWRITE,CLEAN_EMPTY_DIRS,CHECK_MOUNTPOINT,ENABLE_NOW bash "$INSTALL_SCRIPT"
else
    exec bash "$INSTALL_SCRIPT"
fi
