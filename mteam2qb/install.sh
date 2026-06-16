#!/bin/bash
#
# 安装 mteam2qb 到系统命令
#

INSTALL_DIR="/usr/local/bin"
SCRIPT_URL="https://raw.githubusercontent.com/great99mm/myscripts/main/mteam2qb/mteam_to_qb.py"
SCRIPT_PATH="$INSTALL_DIR/mteam2qb"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}安装 mteam2qb...${NC}"

# 下载脚本
curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"

echo -e "${GREEN}安装完成！${NC}"
echo ""
echo -e "${YELLOW}配置环境变量（添加到 ~/.bashrc 或 /etc/profile）:${NC}"
echo ""
echo "  export MTEAM_API_KEY=\"你的M-Team API Key\""
echo "  export QB_URL=\"http://你的qB地址:8080\""
echo "  export QB_USER=\"admin\""
echo "  export QB_PASS=\"你的密码\""
echo ""
echo "使用: mteam2qb [页码]"
echo "  mteam2qb       # 全部导入"
echo "  mteam2qb 2     # 从第2页开始"
echo "  mteam2qb 2-5   # 只跑第2-5页"
