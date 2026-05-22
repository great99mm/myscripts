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

## 一键安装

### curl | bash

默认安装：

```bash
curl -fsSL https://raw.githubusercontent.com/great99mm/myscripts/main/install-clouddrive2-mover.sh | bash
```

自定义目录：

```bash
curl -fsSL https://raw.githubusercontent.com/great99mm/myscripts/main/install-clouddrive2-mover.sh | \
SRC_DIR=/opt/media/CloudDrive \
DST_DIR=/opt/media/115完成 \
STAGE_DIR=/opt/media/115完成/.staging \
bash
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
     STAGE_DIR=/opt/media/115完成/.staging \
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

## 建议

第一次先把脚本里的删除逻辑观察清楚，确认没问题再长期跑。
如果你想更保守，可以先备份一份源数据再启用自动删除。
