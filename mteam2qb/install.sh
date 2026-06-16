#!/bin/bash
#
# 安装 mteam2qb 到系统命令
#

INSTALL_DIR="/usr/local/bin"
SCRIPT_URL="https://raw.githubusercontent.com/great99mm/myscripts/main/mteam2qb/mteam_to_qb.py"
CONFIG_FILE="$HOME/.mteam2qb.conf"
SCRIPT_PATH="$INSTALL_DIR/mteam2qb"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    M-Team 收藏导入工具安装${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 读取配置
echo -e "${YELLOW}请填写配置信息：${NC}"
echo ""

read -p "M-Team API Key: " MTEAM_API_KEY
read -p "qBittorrent 地址 (默认 http://localhost:8080): " QB_URL
QB_URL=${QB_URL:-"http://localhost:8080"}
read -p "qBittorrent 用户名 (默认 admin): " QB_USER
QB_USER=${QB_USER:-"admin"}
read -sp "qBittorrent 密码: " QB_PASS
echo ""
read -p "请求间隔秒数 (默认 3): " MTEAM_INTERVAL
MTEAM_INTERVAL=${MTEAM_INTERVAL:-"3"}

# 保存配置
cat > "$CONFIG_FILE" << EOF
# mteam2qb 配置文件
MTEAM_API_KEY="$MTEAM_API_KEY"
QB_URL="$QB_URL"
QB_USER="$QB_USER"
QB_PASS="$QB_PASS"
MTEAM_INTERVAL="$MTEAM_INTERVAL"
EOF

chmod 600 "$CONFIG_FILE"

echo ""
echo -e "${GREEN}配置已保存到: $CONFIG_FILE${NC}"

# 下载脚本
echo -e "${GREEN}下载脚本...${NC}"
curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_PATH"

# 创建包装脚本，自动加载配置
cat > "${SCRIPT_PATH}.sh" << 'WRAPPER'
#!/bin/bash
CONFIG_FILE="$HOME/.mteam2qb.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    export MTEAM_API_KEY QB_URL QB_USER QB_PASS MTEAM_INTERVAL
fi
python3 "${0%.sh}" "$@"
WRAPPER

chmod +x "$SCRIPT_PATH"
chmod +x "${SCRIPT_PATH}.sh"

# 创建符号链接
ln -sf "${SCRIPT_PATH}.sh" "$INSTALL_DIR/mteam2qb"

echo -e "${GREEN}安装完成！${NC}"
echo ""
echo "使用: mteam2qb [页码]"
echo "  mteam2qb       # 全部导入"
echo "  mteam2qb 2     # 从第2页开始"
echo "  mteam2qb 2-5   # 只跑第2-5页"
echo ""
echo "配置文件: $CONFIG_FILE"
