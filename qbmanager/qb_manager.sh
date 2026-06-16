#!/bin/bash
#
# qBittorrent 自动管理脚本
# 仓库: https://github.com/great99mm/myscripts
#

SCRIPT_NAME="qb_manager"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_FILE="$SCRIPT_DIR/$SCRIPT_NAME.py"
PID_FILE="$SCRIPT_DIR/$SCRIPT_NAME.pid"
LOG_FILE="$SCRIPT_DIR/$SCRIPT_NAME.log"
STATE_FILE="$SCRIPT_DIR/${SCRIPT_NAME}_state.json"
REPO_URL="git@github.com:great99mm/myscripts.git"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查运行状态
check_status() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${GREEN}运行中${NC} (PID: $pid)"
            return 0
        else
            echo -e "${YELLOW}已停止${NC} (PID文件存在但进程不存在)"
            return 1
        fi
    else
        echo -e "${RED}未运行${NC}"
        return 1
    fi
}

# 显示状态信息
show_status() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    qBittorrent 自动管理脚本${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "运行状态: $(check_status)"
    
    # 显示磁盘空间
    if [ -d "/opt/media/downloads" ]; then
        local disk_info=$(df -h /opt/media/downloads | tail -1)
        echo -e "磁盘空间: $(echo $disk_info | awk '{print $4}') 可用 / $(echo $disk_info | awk '{print $2}') 总计"
    fi
    
    # 显示上传统计
    if [ -f "$STATE_FILE" ]; then
        local uploaded=$(python3 -c "import json; print(len(json.load(open('$STATE_FILE')).get('uploaded', [])))" 2>/dev/null || echo "0")
        local failed=$(python3 -c "import json; print(len(json.load(open('$STATE_FILE')).get('failed', [])))" 2>/dev/null || echo "0")
        echo -e "已上传: ${GREEN}$uploaded${NC} 个"
        echo -e "失败: ${RED}$failed${NC} 个"
    fi
    
    echo ""
}

# 启动服务
start_service() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${YELLOW}已在运行中 (PID: $pid)${NC}"
            return
        fi
    fi
    
    echo -e "${GREEN}启动服务...${NC}"
    nohup python3 "$SCRIPT_FILE" > /dev/null 2>&1 &
    echo $! > "$PID_FILE"
    echo -e "${GREEN}已启动 (PID: $!)${NC}"
}

# 停止服务
stop_service() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${YELLOW}停止服务 (PID: $pid)...${NC}"
            kill "$pid" 2>/dev/null
            rm -f "$PID_FILE"
            echo -e "${GREEN}已停止${NC}"
        else
            echo -e "${YELLOW}进程不存在，清理PID文件${NC}"
            rm -f "$PID_FILE"
        fi
    else
        echo -e "${YELLOW}未在运行${NC}"
    fi
}

# 重启服务
restart_service() {
    stop_service
    sleep 1
    start_service
}

# 查看日志
view_logs() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "${BLUE}最近50行日志:${NC}"
        echo "----------------------------------------"
        tail -n 50 "$LOG_FILE"
        echo "----------------------------------------"
    else
        echo -e "${YELLOW}日志文件不存在${NC}"
    fi
}

# 手动触发上传
manual_upload() {
    echo -e "${GREEN}手动触发上传检查...${NC}"
    python3 "$SCRIPT_FILE" upload
}

# 更新脚本
update_script() {
    echo -e "${BLUE}更新脚本...${NC}"
    
    # 检查是否是 git 仓库
    if [ ! -d "$SCRIPT_DIR/.git" ]; then
        echo -e "${YELLOW}初始化 git 仓库...${NC}"
        cd "$SCRIPT_DIR"
        git init
        git remote add origin "$REPO_URL"
    fi
    
    # 拉取更新
    cd "$SCRIPT_DIR"
    echo -e "${BLUE}拉取远程更新...${NC}"
    git fetch origin main 2>/dev/null
    
    # 检查是否有更新
    local LOCAL=$(git rev-parse HEAD 2>/dev/null)
    local REMOTE=$(git rev-parse origin/main 2>/dev/null)
    
    if [ "$LOCAL" = "$REMOTE" ]; then
        echo -e "${GREEN}已是最新版本${NC}"
    else
        echo -e "${YELLOW}发现新版本，更新中...${NC}"
        
        # 停止服务
        local was_running=0
        if [ -f "$PID_FILE" ]; then
            local pid=$(cat "$PID_FILE")
            if ps -p "$pid" > /dev/null 2>&1; then
                was_running=1
                stop_service
            fi
        fi
        
        # 备份当前版本
        cp "$SCRIPT_FILE" "${SCRIPT_FILE}.bak" 2>/dev/null
        
        # 拉取更新
        git reset --hard origin/main
        
        # 重启服务
        if [ $was_running -eq 1 ]; then
            start_service
        fi
        
        echo -e "${GREEN}更新完成！${NC}"
    fi
}

# 提交更改
commit_changes() {
    cd "$SCRIPT_DIR"
    
    if [ ! -d ".git" ]; then
        echo -e "${YELLOW}初始化 git 仓库...${NC}"
        git init
        git remote add origin "$REPO_URL"
    fi
    
    echo -e "${BLUE}提交更改...${NC}"
    git add -A
    git commit -m "更新脚本 $(date '+%Y-%m-%d %H:%M:%S')" 2>/dev/null
    
    echo -e "${BLUE}推送到远程...${NC}"
    git push origin main 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}推送成功！${NC}"
    else
        echo -e "${RED}推送失败，请检查 SSH 密钥配置${NC}"
    fi
}

# 显示管理菜单
show_menu() {
    while true; do
        show_status
        
        echo -e "${BLUE}========================================${NC}"
        echo -e "  ${GREEN}1)${NC} 启动服务"
        echo -e "  ${GREEN}2)${NC} 停止服务"
        echo -e "  ${GREEN}3)${NC} 重启服务"
        echo -e "  ${GREEN}4)${NC} 查看日志"
        echo -e "  ${GREEN}5)${NC} 手动上传"
        echo -e "  ${GREEN}6)${NC} 更新脚本"
        echo -e "  ${GREEN}7)${NC} 提交更改"
        echo -e "  ${GREEN}0)${NC} 退出"
        echo -e "${BLUE}========================================${NC}"
        
        read -p "请选择操作 [0-7]: " choice
        
        case $choice in
            1) start_service ;;
            2) stop_service ;;
            3) restart_service ;;
            4) view_logs ;;
            5) manual_upload ;;
            6) update_script ;;
            7) commit_changes ;;
            0) echo -e "${GREEN}退出${NC}"; exit 0 ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
        
        echo ""
        read -p "按 Enter 继续..."
    done
}

# 主函数
main() {
    # 如果有参数，直接执行
    case "${1:-}" in
        start) start_service ;;
        stop) stop_service ;;
        restart) restart_service ;;
        status) show_status ;;
        logs) view_logs ;;
        upload) manual_upload ;;
        update) update_script ;;
        commit) commit_changes ;;
        menu|"") show_menu ;;
        *) echo "用法: $0 {start|stop|restart|status|logs|upload|update|commit|menu}"; exit 1 ;;
    esac
}

main "$@"
