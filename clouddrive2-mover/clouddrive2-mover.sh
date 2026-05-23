#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob dotglob

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
DRY_RUN="${DRY_RUN:-0}"
CONCURRENCY="${CONCURRENCY:-2}"
TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"
TG_CHAT_ID="${TG_CHAT_ID:-}"

TOTAL_ITEMS=0
COPIED_FILES=0
COPIED_DIRS=0
SKIPPED_ITEMS=0
FAILED_ITEMS=0
DRYRUN_ITEMS=0
SUMMARY_SENT=0
RUN_MODE="run"
SHOULD_SUMMARIZE=1

usage() {
    cat <<'EOF'
用法:
  clouddrive2-mover.sh
  clouddrive2-mover.sh --dry-run
  clouddrive2-mover.sh --self-check
  clouddrive2-mover.sh -h | --help
EOF
}

mkdir -p "$DST_DIR" "$STAGE_DIR" "$LOG_DIR"
LOG_FILE="$LOG_DIR/move_$(date +%Y%m%d_%H%M%S).log"
STATS_FILE="$(mktemp "$LOG_DIR/stats.XXXXXX")"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "已有实例在运行，退出。"
    exit 1
fi

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

warn() {
    log "WARN: $*"
}

err() {
    log "ERROR: $*"
}

record_stat() {
    printf '%s\n' "$1" >> "$STATS_FILE"
}

aggregate_stats() {
    [[ -f "$STATS_FILE" ]] || return 0

    TOTAL_ITEMS=0
    COPIED_FILES=0
    COPIED_DIRS=0
    SKIPPED_ITEMS=0
    FAILED_ITEMS=0
    DRYRUN_ITEMS=0

    local stat
    while IFS= read -r stat; do
        case "$stat" in
            total) ((TOTAL_ITEMS+=1)) ;;
            copied_file) ((COPIED_FILES+=1)) ;;
            copied_dir) ((COPIED_DIRS+=1)) ;;
            skipped) ((SKIPPED_ITEMS+=1)) ;;
            failed) ((FAILED_ITEMS+=1)) ;;
            dryrun) ((DRYRUN_ITEMS+=1)) ;;
        esac
    done < "$STATS_FILE"
}

send_telegram() {
    [[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]] || return 0

    curl -fsS -X POST \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TG_CHAT_ID}" \
        --data-urlencode "text=$1" \
        >/dev/null 2>&1 || true
}

print_summary() {
    local status_text="$1"
    aggregate_stats
    log "摘要: mode=${RUN_MODE}, total=${TOTAL_ITEMS}, files=${COPIED_FILES}, dirs=${COPIED_DIRS}, skipped=${SKIPPED_ITEMS}, failed=${FAILED_ITEMS}, dryrun=${DRYRUN_ITEMS}"

    if [[ "$SUMMARY_SENT" -eq 0 ]]; then
        send_telegram "CloudDrive2 Mover ${status_text}
模式: ${RUN_MODE}
源目录: ${SRC_DIR}
目标目录: ${DST_DIR}
总项目: ${TOTAL_ITEMS}
完成文件: ${COPIED_FILES}
完成目录: ${COPIED_DIRS}
跳过: ${SKIPPED_ITEMS}
失败: ${FAILED_ITEMS}
Dry Run 项目: ${DRYRUN_ITEMS}
日志: ${LOG_FILE}"
        SUMMARY_SENT=1
    fi
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        err "缺少命令: $1"
        exit 1
    }
}

on_exit() {
    local code=$?
    if [[ $code -ne 0 ]]; then
        err "脚本异常退出，退出码: $code"
        if [[ "$SHOULD_SUMMARIZE" -eq 1 ]]; then
            print_summary "失败"
        fi
    else
        log "脚本正常结束"
        if [[ "$SHOULD_SUMMARIZE" -eq 1 ]]; then
            print_summary "完成"
        fi
    fi
    rm -f "$STATS_FILE" 2>/dev/null || true
}
trap on_exit EXIT

retry() {
    local n=1
    while true; do
        if "$@"; then
            return 0
        fi
        if (( n >= RETRY_TIMES )); then
            return 1
        fi
        warn "命令失败，第 ${n}/${RETRY_TIMES} 次，${RETRY_DELAY}s 后重试: $*"
        sleep "$RETRY_DELAY"
        ((n++))
    done
}

get_size() {
    stat -c '%s' "$1"
}

wait_file_stable() {
    local file="$1"
    local i last current

    [[ -f "$file" || -L "$file" ]] || return 0

    last="$(get_size "$file" 2>/dev/null || echo -1)"
    for ((i=1; i<=STABLE_CHECKS; i++)); do
        sleep "$STABLE_INTERVAL"
        current="$(get_size "$file" 2>/dev/null || echo -1)"
        if [[ "$current" != "$last" ]]; then
            warn "文件仍在变化，跳过本轮: $file"
            return 1
        fi
        last="$current"
    done
    return 0
}

publish_path() {
    local tmp="$1"
    local dst="$2"
    local backup=""

    mkdir -p "$(dirname "$dst")"

    if [[ -e "$dst" ]]; then
        if [[ "$OVERWRITE" -eq 0 ]]; then
            warn "目标已存在，跳过发布: $dst"
            return 2
        fi
        backup="${dst}.bak.$$"
        mv -- "$dst" "$backup"
    fi

    if mv -- "$tmp" "$dst"; then
        [[ -n "$backup" && -e "$backup" ]] && rm -rf -- "$backup"
        return 0
    fi

    if [[ -n "$backup" && -e "$backup" && ! -e "$dst" ]]; then
        mv -- "$backup" "$dst" || true
    fi
    return 1
}

copy_file() {
    local src="$1"
    local name dst tmp src_size_before src_size_after tmp_size rc

    name="$(basename -- "$src")"
    dst="$DST_DIR/$name"
    tmp="$STAGE_DIR/${name}.part.$$"
    ((TOTAL_ITEMS+=1))
    record_stat total

    if [[ -e "$dst" && "$OVERWRITE" -eq 0 ]]; then
        warn "目标已存在，跳过文件: $name"
        ((SKIPPED_ITEMS+=1))
        record_stat skipped
        return 0
    fi

    if ! wait_file_stable "$src"; then
        ((SKIPPED_ITEMS+=1))
        record_stat skipped
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[DRY-RUN] 将复制文件: $src -> $dst"
        ((DRYRUN_ITEMS+=1))
        record_stat dryrun
        return 0
    fi

    src_size_before="$(get_size "$src" 2>/dev/null || echo -1)"
    log "开始复制文件: $name"
    rm -f -- "$tmp"
    retry rsync -a --partial --append-verify -- "$src" "$tmp"

    src_size_after="$(get_size "$src" 2>/dev/null || echo -1)"
    tmp_size="$(get_size "$tmp" 2>/dev/null || echo -2)"

    if [[ "$src_size_before" != "$src_size_after" ]]; then
        warn "源文件大小发生变化，跳过删除源文件: $name"
        rm -f -- "$tmp"
        return 1
    fi

    if [[ "$src_size_after" != "$tmp_size" ]]; then
        err "大小校验失败: $name (src=$src_size_after, tmp=$tmp_size)"
        rm -f -- "$tmp"
        return 1
    fi

    set +e
    publish_path "$tmp" "$dst"
    rc=$?
    set -e

    case "$rc" in
        0)
            retry rm -f -- "$src"
            log "完成文件: $name"
            ((COPIED_FILES+=1))
            record_stat copied_file
            ;;
        2)
            rm -f -- "$tmp" 2>/dev/null || true
            warn "发布跳过，保留源文件: $name"
            ((SKIPPED_ITEMS+=1))
            record_stat skipped
            ;;
        *)
            err "发布失败: $name"
            rm -f -- "$tmp" 2>/dev/null || true
            ((FAILED_ITEMS+=1))
            record_stat failed
            return 1
            ;;
    esac
}

copy_dir() {
    local src="$1"
    local name dst tmp rc

    name="$(basename -- "$src")"
    dst="$DST_DIR/$name"
    tmp="$STAGE_DIR/${name}.part.$$"
    ((TOTAL_ITEMS+=1))
    record_stat total

    if [[ -e "$dst" && "$OVERWRITE" -eq 0 ]]; then
        warn "目标已存在，跳过目录: $name/"
        ((SKIPPED_ITEMS+=1))
        record_stat skipped
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[DRY-RUN] 将复制目录: $src -> $dst"
        ((DRYRUN_ITEMS+=1))
        record_stat dryrun
        return 0
    fi

    log "开始复制目录: $name/"
    rm -rf -- "$tmp"
    mkdir -p -- "$tmp"

    retry rsync -a --delete --partial -- "$src"/ "$tmp"/
    retry rsync -a --delete --partial -- "$src"/ "$tmp"/

    set +e
    publish_path "$tmp" "$dst"
    rc=$?
    set -e

    case "$rc" in
        0)
            retry rm -rf -- "$src"
            log "完成目录: $name/"
            ((COPIED_DIRS+=1))
            record_stat copied_dir
            ;;
        2)
            rm -rf -- "$tmp" 2>/dev/null || true
            warn "发布跳过，保留源目录: $name/"
            ((SKIPPED_ITEMS+=1))
            record_stat skipped
            ;;
        *)
            err "发布目录失败: $name/"
            rm -rf -- "$tmp" 2>/dev/null || true
            ((FAILED_ITEMS+=1))
            record_stat failed
            return 1
            ;;
    esac
}

process_one() {
    local item="$1"
    if [[ -L "$item" || -f "$item" ]]; then
        copy_file "$item"
    elif [[ -d "$item" ]]; then
        copy_dir "$item"
    else
        warn "跳过不支持的类型: $item"
        ((SKIPPED_ITEMS+=1))
        record_stat skipped
    fi
}

process_one_job() {
    trap - EXIT
    process_one "$1"
}

process_all_items() {
    local failed_ref=0
    local active_jobs=0
    local item

    if ! [[ "$CONCURRENCY" =~ ^[0-9]+$ ]] || (( CONCURRENCY < 1 )); then
        err "CONCURRENCY 必须是大于等于 1 的整数，当前: $CONCURRENCY"
        return 1
    fi

    log "并发数: $CONCURRENCY"

    if (( CONCURRENCY == 1 )); then
        for item in "$SRC_DIR"/*; do
            [[ -e "$item" ]] || continue
            if ! process_one "$item"; then
                failed_ref=1
                warn "处理失败，继续下一个: $item"
            fi
        done
        return "$failed_ref"
    fi

    for item in "$SRC_DIR"/*; do
        [[ -e "$item" ]] || continue
        process_one_job "$item" &
        active_jobs=$((active_jobs + 1))

        if (( active_jobs >= CONCURRENCY )); then
            if ! wait -n; then
                failed_ref=1
            fi
            active_jobs=$((active_jobs - 1))
        fi
    done

    while (( active_jobs > 0 )); do
        if ! wait -n; then
            failed_ref=1
        fi
        active_jobs=$((active_jobs - 1))
    done

    return "$failed_ref"
}

cleanup_empty_dirs() {
    [[ "$CLEAN_EMPTY_DIRS" -eq 1 ]] || return 0
    log "清理源目录空目录"
    find "$SRC_DIR" -depth -type d -empty -delete 2>/dev/null || true
}

require_cmd rsync
require_cmd flock
require_cmd stat
require_cmd find

if [[ -n "$TG_BOT_TOKEN" || -n "$TG_CHAT_ID" ]]; then
    require_cmd curl
fi

if [[ "$CHECK_MOUNTPOINT" -eq 1 ]]; then
    require_cmd mountpoint
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    SHOULD_SUMMARIZE=0
    usage
    exit 0
fi

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    RUN_MODE="dry-run"
fi

log "========== 开始处理 =========="
log "源目录: $SRC_DIR"
log "目标目录: $DST_DIR"
log "临时目录: $STAGE_DIR"
log "日志文件: $LOG_FILE"

if [[ ! -d "$SRC_DIR" ]]; then
    err "源目录不存在: $SRC_DIR"
    exit 1
fi

if [[ "$CHECK_MOUNTPOINT" -eq 1 ]] && ! mountpoint -q "$SRC_DIR"; then
    err "源目录不是挂载点或尚未挂载: $SRC_DIR"
    exit 1
fi

if [[ "${1:-}" == "--self-check" ]]; then
    SHOULD_SUMMARIZE=0
    log "自检通过"
    exit 0
fi

failed=0
if ! process_all_items; then
    failed=1
fi

cleanup_empty_dirs

if [[ "$failed" -eq 0 ]]; then
    log "========== 全部完成 =========="
else
    warn "========== 部分完成，有失败项目 =========="
    exit 2
fi
