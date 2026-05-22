#!/usr/bin/env bash
set -Eeuo pipefail

PREFIX="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"
ENV_DIR="/etc/default"
APP_NAME="clouddrive2-mover"

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
    echo "请用 root 执行安装脚本。"
    exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

SRC_DIR="${SRC_DIR:-/opt/media/CloudDrive}"
DST_DIR="${DST_DIR:-/opt/media/115完成}"
STAGE_DIR="${STAGE_DIR:-$DST_DIR/.staging}"
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

install -d -m 755 "$PREFIX" "$SYSTEMD_DIR" "$ENV_DIR" "$LOG_DIR" "$STAGE_DIR" "$DST_DIR"
install -m 755 "$SCRIPT_DIR/clouddrive2-mover.sh" "$PREFIX/clouddrive2-mover.sh"
install -m 644 "$SCRIPT_DIR/clouddrive2-mover.service" "$SYSTEMD_DIR/clouddrive2-mover.service"
install -m 644 "$SCRIPT_DIR/clouddrive2-mover.timer" "$SYSTEMD_DIR/clouddrive2-mover.timer"

cat > "$ENV_DIR/clouddrive2-mover" <<EOF
SRC_DIR=$SRC_DIR
DST_DIR=$DST_DIR
STAGE_DIR=$STAGE_DIR
LOG_DIR=$LOG_DIR
LOCK_FILE=$LOCK_FILE
RETRY_TIMES=$RETRY_TIMES
RETRY_DELAY=$RETRY_DELAY
STABLE_CHECKS=$STABLE_CHECKS
STABLE_INTERVAL=$STABLE_INTERVAL
OVERWRITE=$OVERWRITE
CLEAN_EMPTY_DIRS=$CLEAN_EMPTY_DIRS
CHECK_MOUNTPOINT=$CHECK_MOUNTPOINT
EOF

systemctl daemon-reload

if [[ "$ENABLE_NOW" == "1" ]]; then
    systemctl enable --now clouddrive2-mover.timer
fi

cat <<EOF
安装完成。

配置文件:
  $ENV_DIR/clouddrive2-mover

脚本路径:
  $PREFIX/clouddrive2-mover.sh

常用命令:
  systemctl status clouddrive2-mover.timer
  systemctl start clouddrive2-mover.service
  journalctl -u clouddrive2-mover.service -f
EOF
