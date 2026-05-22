# CloudDrive2 Mover

把 CloudDrive2 挂载目录里的内容，安全搬运到本地目录。

核心思路：

- 不直接对挂载源做 `mv`
- 先复制到本地 `.staging`
- 本地 `rename` 发布到正式目录
- 成功后再删除源
- 配合 `systemd timer` 定时执行

## 文件说明

- `clouddrive2-mover.sh`：主脚本
- `clouddrive2-mover.service`：systemd service
- `clouddrive2-mover.timer`：systemd timer
- `clouddrive2-mover.env.example`：配置示例
- `install.sh`：一键安装脚本
- `uninstall.sh`：卸载脚本

## 一键安装

### curl | bash

默认安装：

```bash
curl -fsSL https://raw.githubusercontent.com/great99mm/myscripts/main/install-clouddrive2-mover.sh | bash
```

这个安装器会先做几件事：

- 检查当前系统是否使用 `systemd`
- 检查 `SRC_DIR` 是否存在
- 自动安装缺少的基础依赖（`curl`、`tar`、`sudo`）
- 安装完成后自动跑一次 service 自检
- 安装时交互输入源目录、目标目录和 Telegram 配置

自定义目录：

```bash
SRC_DIR=/opt/media/CloudDrive \
DST_DIR=/opt/media/115完成 \
STAGE_DIR=/opt/media/115mvtmp/.staging \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/great99mm/myscripts/main/install-clouddrive2-mover.sh)"
```

如果你的挂载目录不是标准 mountpoint，可以关闭挂载点检查：

```bash
CHECK_MOUNTPOINT=0 bash -c "$(curl -fsSL https://raw.githubusercontent.com/great99mm/myscripts/main/install-clouddrive2-mover.sh)"
```

### git clone

```bash
git clone <你的仓库地址>
cd clouddrive2-mover
sudo bash install.sh
```

如果要自定义路径：

```bash
sudo SRC_DIR=/opt/media/CloudDrive \
     DST_DIR=/opt/media/115完成 \
     STAGE_DIR=/opt/media/115mvtmp/.staging \
     bash install.sh
```

## 默认定时

- 开机 10 分钟后运行一次
- 之后每 30 分钟运行一次

## 常用命令

```bash
systemctl status clouddrive2-mover.timer
systemctl list-timers | grep clouddrive2-mover
systemctl start clouddrive2-mover.service
journalctl -u clouddrive2-mover.service -f
```

## Dry Run

安装时会询问是否先启用 dry-run。

手动临时执行 dry-run：

```bash
sudo DRY_RUN=1 /usr/local/bin/clouddrive2-mover.sh --dry-run
```

## Telegram 通知

安装时会提示输入：

- `TG_BOT_TOKEN`
- `TG_CHAT_ID`

配置后每次任务结束会发送摘要通知。
安装完成后，如果这两个值都不为空，会立即发送一条 Telegram 测试消息。

## 配置文件

安装后配置文件在：

```bash
/etc/default/clouddrive2-mover
```

改完后执行：

```bash
sudo systemctl daemon-reload
sudo systemctl restart clouddrive2-mover.timer
```

## 卸载

```bash
sudo bash /usr/local/bin/clouddrive2-mover-uninstall.sh
```

如果连日志目录和 staging 目录也要一起删：

```bash
sudo REMOVE_LOG_DIR=1 REMOVE_STAGE_DIR=1 bash /usr/local/bin/clouddrive2-mover-uninstall.sh
```

## 建议

第一次先把脚本里的删除逻辑观察清楚，确认没问题再长期跑。
如果你想更保守，可以先备份一份源数据再启用自动删除。
