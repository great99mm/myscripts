#!/usr/bin/env python3
"""M-Team 收藏批量下载 - 直接导入 qBittorrent"""

import requests
import json
import time
import sys
import os

# M-Team 配置（优先读取环境变量）
API_KEY = os.environ.get("MTEAM_API_KEY", "")
BASE_URL = os.environ.get("MTEAM_API_URL", "https://api.m-team.cc")
REQUEST_INTERVAL = int(os.environ.get("MTEAM_INTERVAL", "3"))

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    "Accept": "application/json",
    "Content-Type": "application/json",
    "x-api-key": API_KEY,
}

# qBittorrent 配置（优先读取环境变量）
QB_URL = os.environ.get("QB_URL", "http://localhost:8080")
QB_USER = os.environ.get("QB_USER", "admin")
QB_PASS = os.environ.get("QB_PASS", "")


def qb_login():
    """登录 qBittorrent"""
    session = requests.Session()
    resp = session.post(f"{QB_URL}/api/v2/auth/login", data={
        "username": QB_USER,
        "password": QB_PASS
    })
    if resp.text == "Ok.":
        print("[✓] qBittorrent 登录成功")
        return session
    else:
        print(f"[!] qBittorrent 登录失败: {resp.text}")
        return None


def qb_add_torrent(session, url):
    """添加种子到 qBittorrent"""
    resp = session.post(f"{QB_URL}/api/v2/torrents/add", data={
        "urls": url
    })
    return resp.text == "Ok."


def search_favorites(page=1, page_size=100):
    """搜索收藏"""
    url = f"{BASE_URL}/api/torrent/search"
    data = {
        "pageNumber": page,
        "pageSize": page_size,
        "mode": "adult",
        "onlyFav": True
    }
    
    try:
        resp = requests.post(url, headers=HEADERS, json=data)
        if resp.status_code == 200:
            return resp.json()
    except Exception as e:
        print(f"[!] 请求失败: {e}")
    return None


def get_dl_token(torrent_id):
    """获取种子下载链接"""
    url = f"{BASE_URL}/api/torrent/genDlToken"
    
    try:
        headers_no_ct = {k: v for k, v in HEADERS.items() if k != "Content-Type"}
        files = {"id": (None, str(torrent_id))}
        resp = requests.post(url, headers=headers_no_ct, files=files)
        if resp.status_code == 200:
            result = resp.json()
            if result.get("code") == "0" or result.get("code") == 0:
                return result.get("data")
    except Exception as e:
        pass
    return None


def main():
    # 解析页码参数
    start_page = 1
    end_page = None
    
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if '-' in arg:
            parts = arg.split('-')
            start_page = int(parts[0])
            end_page = int(parts[1])
        else:
            start_page = int(arg)
            end_page = start_page
    
    print("=" * 60)
    print("M-Team 收藏 → qBittorrent 自动导入")
    if end_page:
        print(f"页码范围: 第 {start_page} 页 到 第 {end_page} 页")
    else:
        print(f"从第 {start_page} 页开始")
    print("=" * 60)
    
    # 登录 qBittorrent
    qb = qb_login()
    if not qb:
        return
    
    # 获取所有收藏
    print("\n[*] 获取收藏列表...")
    
    all_torrents = []
    page = start_page
    
    while True:
        print(f"[*] 第 {page} 页...", end="")
        result = search_favorites(page=page)
        
        if not result or result.get("code") != "0":
            print(" 失败")
            break
        
        data = result.get("data", {})
        torrents = data.get("data", [])
        
        if not torrents:
            print(" 无数据")
            break
        
        all_torrents.extend(torrents)
        print(f" {len(torrents)} 个")
        
        # 检查是否到达结束页
        if end_page and page >= end_page:
            break
        
        total = int(data.get("total", 0))
        if len(all_torrents) >= total - (start_page - 1) * 100:
            break
        
        page += 1
        time.sleep(1)
    
    # 去重
    seen = set()
    unique_torrents = []
    for t in all_torrents:
        if t["id"] not in seen:
            seen.add(t["id"])
            unique_torrents.append(t)
    
    print(f"\n[✓] 共 {len(unique_torrents)} 个收藏")
    
    # 开始处理
    print(f"\n{'=' * 60}")
    print(f"开始导入（每 {REQUEST_INTERVAL} 秒 1 个）")
    print(f"{'=' * 60}")
    
    success = 0
    failed = []
    
    for i, t in enumerate(unique_torrents, 1):
        tid = t["id"]
        name = t.get("name", "")[:40]
        print(f"[{i}/{len(unique_torrents)}] {tid} - {name}...", end="")
        
        # 获取下载链接
        dl_url = get_dl_token(tid)
        
        if dl_url:
            # 添加到 qBittorrent
            if qb_add_torrent(qb, dl_url):
                success += 1
                print(" ✓")
            else:
                failed.append(t)
                print(" ✗ (添加失败)")
        else:
            failed.append(t)
            print(" ✗ (获取链接失败)")
        
        time.sleep(REQUEST_INTERVAL)
    
    # 重试失败的
    if failed:
        print(f"\n{'=' * 60}")
        print(f"重试 {len(failed)} 个失败的种子...")
        print(f"{'=' * 60}")
        
        time.sleep(10)
        
        still_failed = []
        for i, t in enumerate(failed, 1):
            tid = t["id"]
            name = t.get("name", "")[:40]
            print(f"[重试 {i}/{len(failed)}] {tid} - {name}...", end="")
            
            dl_url = get_dl_token(tid)
            
            if dl_url:
                if qb_add_torrent(qb, dl_url):
                    success += 1
                    print(" ✓")
                else:
                    still_failed.append(tid)
                    print(" ✗")
            else:
                still_failed.append(tid)
                print(" ✗")
            
            time.sleep(REQUEST_INTERVAL)
        
        failed = still_failed
    
    # 结果
    print(f"\n{'=' * 60}")
    print(f"完成！")
    print(f"成功导入: {success} 个")
    print(f"失败: {len(failed)} 个")
    if failed:
        print(f"失败 ID: {','.join(failed[:20])}{'...' if len(failed) > 20 else ''}")
    print(f"{'=' * 60}")


if __name__ == "__main__":
    main()
