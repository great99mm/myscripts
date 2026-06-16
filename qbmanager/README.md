# qBittorrent 自动管理脚本

## 安装

```bash
cd qbmanager
sudo ./install.sh
```

## 功能

- 磁盘空间监控：低于阈值暂停任务，恢复后继续
- 完成任务自动上传到 Google Drive（rclone move）
- 电报通知
- 失败无限重试
- 后台运行，命令管理

## 使用

```bash
qbmanager          # 进入管理菜单
qbmanager start    # 启动
qbmanager stop     # 停止
qbmanager restart  # 重启
qbmanager status   # 查看状态
qbmanager logs     # 查看日志
qbmanager upload   # 手动触发上传
qbmanager update   # 更新脚本
```

## 配置

通过环境变量配置（添加到 ~/.bashrc 或 /etc/profile）：

```bash
# qBittorrent
export QB_URL="http://你的qB地址:8080"
export QB_USER="admin"
export QB_PASS="你的密码"

# 磁盘监控
export DISK_PATH="/opt/media/downloads"
export DISK_THRESHOLD_TB="1.5"
export DISK_RESUME_TB="1.6"

# rclone
export RCLONE_REMOTE="gd:media/nsfw"

# 电报通知
export TG_BOT_TOKEN="你的Bot Token"
export TG_CHAT_ID="你的Chat ID"
```
