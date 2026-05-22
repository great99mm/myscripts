# myscripts

我自己的一些脚本集合。

## 目前包含

### CloudDrive2 Mover

把 CloudDrive2 挂载目录里的内容，安全搬运到本地目录。

一键安装：

```bash
curl -fsSL https://raw.githubusercontent.com/great99mm/myscripts/main/install-clouddrive2-mover.sh | bash
```

安装器会自动：

- 检查是否为 systemd 系统
- 检查 CloudDrive2 挂载源目录是否存在
- 自动安装缺少的基础依赖（如 `curl` / `tar` / `sudo`）
- 安装完成后自动跑一次自检

项目说明见：

- `clouddrive2-mover/README.md`
