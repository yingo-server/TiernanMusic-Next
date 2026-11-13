#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""发布治理脚本：将仓库全部 release 标记为 prerelease（支持 dry-run / --apply / --restore）。

用法:
  python3 tool/release_to_prerelease.py            # dry-run，仅打印计划
  python3 tool/release_to_prerelease.py --apply    # 备份并逐条 PATCH prerelease=true
  python3 tool/release_to_prerelease.py --restore [--backup tool/releases_backup.json]
"""
import argparse
import json
import os
import sys
import time
import urllib.request
import urllib.error

REPO = "yingo-server/TiernanMusic-Next"
API = "https://api.github.com"
BACKUP_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "releases_backup.json")
TIMEOUT = 30
RETRIES = 3


def die(msg):
    print("[FATAL] %s" % msg)
    sys.exit(2)


def get_token():
    token = os.environ.get("GITHUB_TOKEN", "")
    if not token:
        die("环境变量 GITHUB_TOKEN 未设置（禁止硬编码 token）")
    return token


def api_request(method, url, token, body=None):
    """带超时 30s、3 次指数退避(1/2/4s)重试的 GitHub API 请求。返回 (status, data)。"""
    headers = {
        "Authorization": "token %s" % token,
        "Accept": "application/vnd.github+json",
        "User-Agent": "release-to-prerelease",
        "Content-Type": "application/json",
    }
    data = json.dumps(body).encode("utf-8") if body is not None else None
    for attempt in range(1, RETRIES + 1):
        try:
            req = urllib.request.Request(url, data=data, headers=headers, method=method)
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                return resp.status, json.loads(resp.read().decode("utf-8") or "null")
        except urllib.error.HTTPError as e:
            print("  [WARN] attempt %d: HTTP %s %s" % (attempt, e.code, e.reason))
        except Exception as e:
            print("  [WARN] attempt %d: %s" % (attempt, e))
        if attempt < RETRIES:
            backoff = 2 ** (attempt - 1)
            print("  [RETRY] sleep %ds" % backoff)
            time.sleep(backoff)
    return None, None


def fetch_releases(token):
    releases = []
    page = 1
    while True:
        url = "%s/repos/%s/releases?per_page=100&page=%d" % (API, REPO, page)
        status, data = api_request("GET", url, token)
        if status != 200 or not isinstance(data, list):
            return None
        releases.extend(data)
        if len(data) < 100:
            break
        page += 1
    return releases


def load_backup(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def do_dry_run(releases):
    print("=== DRY-RUN（不修改任何东西）===")
    for r in releases:
        print("%s: prerelease(before) -> %s" % (r.get("tag_name"), True))


def do_apply(releases, token):
    # 备份（已存在则加时间戳后缀，不覆盖旧备份）
    snapshot = [{"id": r["id"], "tag_name": r.get("tag_name"), "prerelease": r.get("prerelease"), "draft": r.get("draft")} for r in releases]
    backup_path = BACKUP_PATH
    if os.path.exists(backup_path):
        backup_path = backup_path.replace(".json", "_" + time.strftime("%Y%m%d_%H%M%S") + ".json")
        print("[BACKUP] 旧备份存在，写入新文件: %s" % backup_path)
    with open(backup_path, "w", encoding="utf-8") as f:
        json.dump(snapshot, f, ensure_ascii=False, indent=2)
    print("[BACKUP] 已保存 %d 条到 %s" % (len(snapshot), backup_path))

    total = need = changed = failed = skipped = 0
    for r in snapshot:
        total += 1
        if r["prerelease"]:
            skipped += 1
            print("%s: 已是 prerelease=true，跳过（幂等）" % r["tag_name"])
            continue
        need += 1
        url = "%s/repos/%s/releases/%d" % (API, REPO, r["id"])
        status, _ = api_request("PATCH", url, token, body={"prerelease": True})
        if status in (200, 201):
            changed += 1
            print("%s: PATCH 成功 (HTTP %s)" % (r["tag_name"], status))
        else:
            failed += 1
            print("%s: PATCH 失败" % r["tag_name"])
    print_stats(total, need, changed, failed)
    return failed


def do_restore(token, backup_path):
    try:
        backup = load_backup(backup_path)
    except Exception as e:
        die("读取备份 %s 失败: %s" % (backup_path, e))
    total = need = changed = failed = 0
    for item in backup:
        total += 1
        before = item["prerelease"]
        if before:
            print("%s: 原值已是 true，跳过" % item["tag_name"])
            continue
        need += 1
        url = "%s/repos/%s/releases/%d" % (API, REPO, item["id"])
        status, _ = api_request("PATCH", url, token, body={"prerelease": bool(before)})
        if status in (200, 201):
            changed += 1
            print("%s: 恢复为 %s (HTTP %s)" % (item["tag_name"], before, status))
        else:
            failed += 1
            print("%s: 恢复失败" % item["tag_name"])
    print_stats(total, need, changed, failed)
    return failed


def print_stats(total, need, changed, failed):
    print("=== 统计: 总数=%d 需改=%d 已改=%d 失败=%d ===" % (total, need, changed, failed))


def main():
    parser = argparse.ArgumentParser(description="将 TiernanMusic-Next 全部 release 标记为 prerelease")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--apply", action="store_true", help="备份后执行 PATCH")
    group.add_argument("--restore", action="store_true", help="按备份恢复 prerelease 原值")
    parser.add_argument("--backup", default=BACKUP_PATH, help="restore 使用的备份文件路径")
    args = parser.parse_args()

    token = get_token()
    failed = 0
    try:
        if args.restore:
            failed = do_restore(token, args.backup)
        else:
            releases = fetch_releases(token)
            if releases is None:
                die("获取 releases 列表失败（重试后仍失败）")
            if not releases:
                print("仓库无 release，无事可做。")
                return
            if args.apply:
                failed = do_apply(releases, token)
            else:
                do_dry_run(releases)
    except SystemExit:
        raise
    except Exception as e:
        print("[FATAL] 未捕获异常: %r" % e)
        sys.exit(1)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
