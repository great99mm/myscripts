#!/usr/bin/env python3
"""
qBittorrent 自动管理脚本
- 磁盘空间监控：低于阈值暂停任务，恢复后继续
- 完成任务自动上传到 Google Drive
- 电报通知
- 后台运行，命令管理

用法：
  python3 qb_manager.py start       # 启动后台运行
  python3 qb_manager.py stop        # 停止
  python3 qb_manager.py status      # 查看状态
  python3 qb_manager.py logs        # 查看日志
  python3 qb_manager.py upload      # 手动触发上传检查
"""

import os
import sys
import time
import json
import signal
import logging
import subprocess
import requests
from datetime import datetime
from pathlib import Path

# ==================== 配置（优先读取环境变量）====================

# qBittorrent
QB_URL = os.environ.get("QB_URL", "http://localhost:8080")
QB_USER = os.environ.get("QB_USER", "admin")
QB_PASS = os.environ.get("QB_PASS", "")

# 磁盘监控
DISK_PATH = os.environ.get("DISK_PATH", "/downloads")
DISK_THRESHOLD_TB = float(os.environ.get("DISK_THRESHOLD_TB", "1.5"))
DISK_RESUME_TB = float(os.environ.get("DISK_RESUME_TB", "1.6"))

# rclone
RCLONE_REMOTE = os.environ.get("RCLONE_REMOTE", "gd:media/nsfw")
RCLONE_TRANSFERS = int(os.environ.get("RCLONE_TRANSFERS", "4"))
RCLONE_BW_LIMIT = os.environ.get("RCLONE_BW_LIMIT", "0")

# 电报通知
TG_BOT_TOKEN = os.environ.get("TG_BOT_TOKEN", "")
TG_CHAT_ID = os.environ.get("TG_CHAT_ID", "")

# 路径
SCRIPT_DIR = Path(__file__).parent
PID_FILE = SCRIPT_DIR / "qb_manager.pid"
LOG_FILE = SCRIPT_DIR / "qb_manager.log"
STATE_FILE = SCRIPT_DIR / "qb_manager_state.json"

# 检查间隔
CHECK_INTERVAL = 60  # 秒
UPLOAD_CHECK_INTERVAL = 60  # 上传检查间隔

# ==================== 日志 ====================

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE, encoding='utf-8'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# ==================== 工具函数 ====================

def send_telegram(message):
    """发送电报通知"""
    if not TG_BOT_TOKEN or not TG_CHAT_ID:
        return
    
    try:
        url = f"https://api.telegram.org/bot{TG_BOT_TOKEN}/sendMessage"
        data = {
            "chat_id": TG_CHAT_ID,
            "text": message,
            "parse_mode": "HTML"
        }
        requests.post(url, data=data, timeout=10)
    except Exception as e:
        logger.error(f"电报通知失败: {e}")


def get_disk_usage(path):
    """获取磁盘使用情况（TB）"""
    try:
        st = os.statvfs(path)
        free_bytes = st.f_bavail * st.f_frsize
        total_bytes = st.f_blocks * st.f_frsize
        free_tb = free_bytes / (1024 ** 4)
        total_tb = total_bytes / (1024 ** 4)
        return free_tb, total_tb
    except Exception as e:
        logger.error(f"获取磁盘信息失败: {e}")
        return None, None


def qb_login():
    """登录 qBittorrent"""
    session = requests.Session()
    resp = session.post(f"{QB_URL}/api/v2/auth/login", data={
        "username": QB_USER,
        "password": QB_PASS
    })
    if resp.text == "Ok.":
        return session
    return None


def qb_get_torrents(session, filter_type=None):
    """获取种子列表"""
    params = {}
    if filter_type:
        params["filter"] = filter_type
    
    resp = session.get(f"{QB_URL}/api/v2/torrents/info", params=params)
    if resp.status_code == 200:
        return resp.json()
    return []


def qb_pause_all(session):
    """暂停所有任务"""
    resp = session.post(f"{QB_URL}/api/v2/torrents/pause", data={"hashes": "all"})
    return resp.status_code == 200


def qb_resume_all(session):
    """恢复所有任务"""
    resp = session.post(f"{QB_URL}/api/v2/torrents/resume", data={"hashes": "all"})
    return resp.status_code == 200


def qb_get_completed(session):
    """获取已完成的任务（做种中）"""
    torrents = qb_get_torrents(session)
    return [t for t in torrents if t.get("state") in ("uploading", "stalledUP", "forcedUP")]


def rclone_upload(local_path, remote_path):
    """使用 rclone 移动文件"""
    cmd = [
        "rclone", "move",
        local_path,
        remote_path,
        f"--transfers={RCLONE_TRANSFERS}",
        f"--bw-limit={RCLONE_BW_LIMIT}",
        "--log-level=INFO"
    ]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=7200)
        return result.returncode == 0
    except Exception as e:
        logger.error(f"rclone 移动失败: {e}")
        return False


def load_state():
    """加载状态"""
    if STATE_FILE.exists():
        try:
            with open(STATE_FILE, 'r') as f:
                return json.load(f)
        except:
            pass
    return {"uploaded": [], "failed": [], "paused": False}


def save_state(state):
    """保存状态"""
    with open(STATE_FILE, 'w') as f:
        json.dump(state, f, indent=2)


# ==================== 主逻辑 ====================

class QBManager:
    def __init__(self):
        self.running = True
        self.state = load_state()
        self.qb_session = None
        self.last_upload_check = 0
        
    def connect_qb(self):
        """连接 qBittorrent"""
        self.qb_session = qb_login()
        if self.qb_session:
            logger.info("qBittorrent 连接成功")
            return True
        else:
            logger.error("qBittorrent 连接失败")
            return False
    
    def check_disk(self):
        """检查磁盘空间"""
        free_tb, total_tb = get_disk_usage(DISK_PATH)
        if free_tb is None:
            return
        
        logger.info(f"磁盘空间: {free_tb:.2f}TB / {total_tb:.2f}TB")
        
        # 空间不足，暂停任务
        if free_tb < DISK_THRESHOLD_TB and not self.state.get("paused"):
            logger.warning(f"磁盘空间不足 {DISK_THRESHOLD_TB}TB，暂停所有任务")
            if self.qb_session:
                qb_pause_all(self.qb_session)
                self.state["paused"] = True
                save_state(self.state)
                send_telegram(f"⚠️ 磁盘空间不足 {DISK_THRESHOLD_TB}TB\n已暂停所有下载任务\n剩余: {free_tb:.2f}TB")
        
        # 空间恢复，继续任务
        elif free_tb >= DISK_RESUME_TB and self.state.get("paused"):
            logger.info(f"磁盘空间恢复到 {DISK_RESUME_TB}TB，恢复任务")
            if self.qb_session:
                qb_resume_all(self.qb_session)
                self.state["paused"] = False
                save_state(self.state)
                send_telegram(f"✅ 磁盘空间已恢复\n已恢复所有下载任务\n剩余: {free_tb:.2f}TB")
    
    def check_uploads(self):
        """检查并上传完成的任务"""
        now = time.time()
        if now - self.last_upload_check < UPLOAD_CHECK_INTERVAL:
            return
        
        self.last_upload_check = now
        
        if not self.qb_session:
            return
        
        completed = qb_get_completed(self.qb_session)
        uploaded = self.state.get("uploaded", [])
        failed = self.state.get("failed", [])
        
        for torrent in completed:
            name = torrent.get("name", "")
            hash_val = torrent.get("hash", "")
            save_path = torrent.get("save_path", "")
            content_path = torrent.get("content_path", "")
            
            # 跳过已上传的
            if hash_val in uploaded:
                continue
            
            # 优先使用 content_path（完整路径）
            local_path = content_path if content_path else os.path.join(save_path, name)
            
            # 检查路径是否存在
            if not os.path.exists(local_path):
                # 如果之前失败过，继续重试
                if hash_val in failed:
                    logger.info(f"等待文件出现: {local_path}")
                continue
            
            logger.info(f"上传种子: {name}")
            logger.info(f"本地路径: {local_path}")
            send_telegram(f"📤 开始上传: {name}")
            
            # 上传，失败后一直重试
            retry_count = 0
            while True:
                retry_count += 1
                if rclone_upload(local_path, RCLONE_REMOTE):
                    logger.info(f"上传成功: {name}")
                    send_telegram(f"✅ 上传完成: {name}")
                    
                    # 记录已上传
                    self.state.setdefault("uploaded", []).append(hash_val)
                    # 从失败列表移除
                    if hash_val in self.state.get("failed", []):
                        self.state["failed"].remove(hash_val)
                    save_state(self.state)
                    break
                else:
                    logger.error(f"上传失败 (第{retry_count}次): {name}")
                    # 记录失败
                    if hash_val not in self.state.get("failed", []):
                        self.state.setdefault("failed", []).append(hash_val)
                    save_state(self.state)
                    
                    if retry_count == 1:
                        send_telegram(f"❌ 上传失败，将无限重试: {name}")
                    
                    # 等待30秒后重试
                    logger.info(f"30秒后重试...")
                    time.sleep(30)
    
    def run(self):
        """主循环"""
        logger.info("qBittorrent 管理器启动")
        send_telegram("🚀 qBittorrent 管理器已启动")
        
        while self.running:
            try:
                # 连接 qBittorrent
                if not self.qb_session:
                    if not self.connect_qb():
                        time.sleep(30)
                        continue
                
                # 检查磁盘
                self.check_disk()
                
                # 检查上传
                self.check_uploads()
                
            except Exception as e:
                logger.error(f"运行错误: {e}")
                self.qb_session = None
            
            time.sleep(CHECK_INTERVAL)
        
        logger.info("qBittorrent 管理器已停止")
    
    def stop(self):
        """停止"""
        self.running = False


# ==================== 命令管理 ====================

def start_daemon():
    """启动后台进程"""
    if PID_FILE.exists():
        pid = PID_FILE.read_text().strip()
        if os.path.exists(f"/proc/{pid}"):
            print(f"已在运行中 (PID: {pid})")
            return
    
    # 启动子进程
    pid = os.fork()
    if pid > 0:
        print(f"已启动 (PID: {pid})")
        return
    
    # 子进程
    os.setsid()
    PID_FILE.write_text(str(os.getpid()))
    
    manager = QBManager()
    
    def signal_handler(sig, frame):
        manager.stop()
        PID_FILE.unlink(missing_ok=True)
    
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    try:
        manager.run()
    finally:
        PID_FILE.unlink(missing_ok=True)


def stop_daemon():
    """停止后台进程"""
    if not PID_FILE.exists():
        print("未在运行")
        return
    
    pid = int(PID_FILE.read_text().strip())
    try:
        os.kill(pid, signal.SIGTERM)
        print(f"已停止 (PID: {pid})")
    except ProcessLookupError:
        print("进程不存在")
        PID_FILE.unlink(missing_ok=True)


def show_status():
    """显示状态"""
    if PID_FILE.exists():
        pid = PID_FILE.read_text().strip()
        if os.path.exists(f"/proc/{pid}"):
            print(f"状态: 运行中 (PID: {pid})")
        else:
            print("状态: 已停止 (PID 文件存在但进程不存在)")
    else:
        print("状态: 已停止")
    
    # 显示状态文件
    state = load_state()
    print(f"已上传: {len(state.get('uploaded', []))} 个")
    print(f"失败: {len(state.get('failed', []))} 个")
    print(f"暂停状态: {'是' if state.get('paused') else '否'}")
    
    # 显示磁盘
    free_tb, total_tb = get_disk_usage(DISK_PATH)
    if free_tb:
        print(f"磁盘空间: {free_tb:.2f}TB / {total_tb:.2f}TB")


def show_logs(lines=50):
    """显示日志"""
    if LOG_FILE.exists():
        subprocess.run(["tail", f"-n{lines}", str(LOG_FILE)])
    else:
        print("日志文件不存在")


def manual_upload():
    """手动触发上传检查"""
    print("手动触发上传检查...")
    manager = QBManager()
    if manager.connect_qb():
        manager.last_upload_check = 0
        manager.check_uploads()
        print("完成")
    else:
        print("连接 qBittorrent 失败")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    
    cmd = sys.argv[1].lower()
    
    if cmd == "start":
        start_daemon()
    elif cmd == "stop":
        stop_daemon()
    elif cmd == "status":
        show_status()
    elif cmd == "logs":
        lines = int(sys.argv[2]) if len(sys.argv) > 2 else 50
        show_logs(lines)
    elif cmd == "upload":
        manual_upload()
    else:
        print(f"未知命令: {cmd}")
        print(__doc__)


if __name__ == "__main__":
    main()
