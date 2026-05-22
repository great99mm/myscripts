#!/usr/bin/env bash
set -Eeuo pipefail

PREFIX="/usr/local/bin"
SYSTEMD_DIR="/etc/systemd/system"
ENV_FILE="/etc/default/clouddrive2-mover"

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

err() {
    printf '[%s] ERROR: %s\n' "$(date '+%F %T')" "$*" >&2
}

if [[ $EUID -ne 0 ]]; then
    err "请用 root 执行卸载脚本。"
    exit 1
fi

REMOVE_LOG_DIR="${REMOVE_LOG_DIR:-0}"
REMOVE_STAGE_DIR="${REMOVE_STAGE_DIR:-0}"

if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now clouddrive2-mover.timer 2>/dev/null || true
    systemctl stop clouddrive2-mover.service 2>/dev/null || true
fi

LOG_DIR=""
STAGE_DIR=""
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

rm -f "$PREFIX/clouddrive2-mover.sh"
rm -f "$SYSTEMD_DIR/clouddrive2-mover.service"
rm -f "$SYSTEMD_DIR/clouddrive2-mover.timer"
rm -f "$ENV_FILE"

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
fi

if [[ "$REMOVE_LOG_DIR" == "1" && -n "${LOG_DIR:-}" && -d "$LOG_DIR" ]]; then
    log "删除日志目录: $LOG_DIR"
    rm -rf -- "$LOG_DIR"
fi

if [[ "$REMOVE_STAGE_DIR" == "1" && -n "${STAGE_DIR:-}" && -d "$STAGE_DIR" ]]; then
    log "删除 staging 目录: $STAGE_DIR"
    rm -rf -- "$STAGE_DIR"
fi

log "卸载完成。"
