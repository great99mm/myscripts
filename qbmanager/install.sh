#!/bin/bash
#
# 安装脚本 - 把命令安装到系统路径
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/usr/local/bin"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}安装脚本到系统命令...${NC}"

# 创建符号链接
ln -sf "$SCRIPT_DIR/qb_manager.sh" "$INSTALL_DIR/qbmanager"
ln -sf "$SCRIPT_DIR/mteam_to_qb.py" "$INSTALL_DIR/mteam2qb"

chmod +x "$SCRIPT_DIR/qb_manager.sh"
chmod +x "$SCRIPT_DIR/mteam_to_qb.py"

echo -e "${GREEN}安装完成！${NC}"
echo ""
echo -e "可用命令："
echo -e "  ${YELLOW}qbmanager${NC}        - qBittorrent 管理菜单"
echo -e "  ${YELLOW}qbmanager start${NC}  - 启动服务"
echo -e "  ${YELLOW}qbmanager stop${NC}   - 停止服务"
echo -e "  ${YELLOW}qbmanager status${NC} - 查看状态"
echo -e "  ${YELLOW}qbmanager update${NC} - 更新脚本"
echo ""
echo -e "  ${YELLOW}mteam2qb${NC}         - M-Team 收藏导入 qBittorrent"
echo -e "  ${YELLOW}mteam2qb 2${NC}       - 从第2页开始"
echo -e "  ${YELLOW}mteam2qb 2-5${NC}     - 只跑第2-5页"
