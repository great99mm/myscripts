#!/bin/bash
#
# 安装 qbmanager 到系统命令
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/usr/local/bin"
CONFIG_FILE="$HOME/.qbmanager.conf"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    qBittorrent 管理工具安装${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 读取配置
echo -e "${YELLOW}请填写配置信息：${NC}"
echo ""

read -p "qBittorrent 地址 (默认 http://localhost:8080): " QB_URL
QB_URL=${QB_URL:-"http://localhost:8080"}
read -p "qBittorrent 用户名 (默认 admin): " QB_USER
QB_USER=${QB_USER:-"admin"}
read -sp "qBittorrent 密码: " QB_PASS
echo ""
read -p "下载目录路径 (默认 /opt/media/downloads): " DISK_PATH
DISK_PATH=${DISK_PATH:-"/opt/media/downloads"}
read -p "磁盘阈值 TB (默认 1.5): " DISK_THRESHOLD_TB
DISK_THRESHOLD_TB=${DISK_THRESHOLD_TB:-"1.5"}
read -p "恢复阈值 TB (默认 1.6): " DISK_RESUME_TB
DISK_RESUME_TB=${DISK_RESUME_TB:-"1.6"}
read -p "rclone 远程路径 (默认 gd:media/nsfw): " RCLONE_REMOTE
RCLONE_REMOTE=${RCLONE_REMOTE:-"gd:media/nsfw"}
read -p "电报 Bot Token (可选): " TG_BOT_TOKEN
read -p "电报 Chat ID (可选): " TG_CHAT_ID

# 保存配置
cat > "$CONFIG_FILE" << EOF
# qbmanager 配置文件
QB_URL="$QB_URL"
QB_USER="$QB_USER"
QB_PASS="$QB_PASS"
DISK_PATH="$DISK_PATH"
DISK_THRESHOLD_TB="$DISK_THRESHOLD_TB"
DISK_RESUME_TB="$DISK_RESUME_TB"
RCLONE_REMOTE="$RCLONE_REMOTE"
TG_BOT_TOKEN="$TG_BOT_TOKEN"
TG_CHAT_ID="$TG_CHAT_ID"
EOF

chmod 600 "$CONFIG_FILE"

echo ""
echo -e "${GREEN}配置已保存到: $CONFIG_FILE${NC}"

# 创建包装脚本
cat > "$INSTALL_DIR/qbmanager" << 'WRAPPER'
#!/bin/bash
CONFIG_FILE="$HOME/.qbmanager.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    export QB_URL QB_USER QB_PASS DISK_PATH DISK_THRESHOLD_TB DISK_RESUME_TB
    export RCLONE_REMOTE TG_BOT_TOKEN TG_CHAT_ID
fi

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
# 查找实际脚本位置
if [ -f "$SCRIPT_DIR/qb_manager.sh" ]; then
    bash "$SCRIPT_DIR/qb_manager.sh" "$@"
elif [ -f "/usr/local/share/qbmanager/qb_manager.sh" ]; then
    bash "/usr/local/share/qbmanager/qb_manager.sh" "$@"
else
    echo "找不到 qb_manager.sh"
    exit 1
fi
WRAPPER

chmod +x "$INSTALL_DIR/qbmanager"

# 复制脚本到共享目录
mkdir -p /usr/local/share/qbmanager
cp "$SCRIPT_DIR/qb_manager.sh" /usr/local/share/qbmanager/
cp "$SCRIPT_DIR/qb_manager.py" /usr/local/share/qbmanager/

echo -e "${GREEN}安装完成！${NC}"
echo ""
echo "使用: qbmanager"
echo "  qbmanager start    # 启动"
echo "  qbmanager stop     # 停止"
echo "  qbmanager status   # 查看状态"
echo "  qbmanager update   # 更新"
echo ""
echo "配置文件: $CONFIG_FILE"
