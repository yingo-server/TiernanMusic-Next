"""清理本次批次产生的中间 prerelease release + tag。

用法：python3 tool/cleanup_intermediate_releases.py <keep_tag> [删除的tag...]

背景：连续推送多个提交会让 CI 每次都打一个新 tag 发一个 prerelease，
用户面对一堆版本号无从下手。本脚本把中间版本删掉，只留最终一个
（keep_tag）。已标注 [KNOWN BROKEN] 的旧正式版不删。

注意：删 tag 后，CI 的版本号计算（当日已有 tag 最大序号 +1）会重新用序号，
所以保留的 keep_tag 必须是版本号最大者。
"""
import json
import os
import subprocess
import sys

TOKEN = os.environ.get("GITHUB_TOKEN")

API = "https://api.github.com/repos/yingo-server/TiernanMusic-Next"
REPO = "yingo-server/TiernanMusic-Next"


def api(method, path, data=None):
    cmd = ["curl", "-s", "-X", method,
           "-H", "Authorization: token " + TOKEN,
           "-H", "Accept: application/vnd.github+json",
           API + path]
    if data is not None:
        cmd += ["-d", json.dumps(data)]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    try:
        return json.loads(out)
    except Exception:
        return {"raw": out[:300]}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    if not args or "--help" in sys.argv or "-h" in sys.argv:
        print("用法: python3 tool/cleanup_intermediate_releases.py <keep_tag> [tag...]")
        print("  keep_tag  必须保留的版本（通常是版本号最大的那个）")
        print("  tag...    要额外删除的 tag；省略则自动删除所有其他 prerelease")
        print("注意：会自动删除 release 与 tag，务必先确认 keep_tag 正确。")
        sys.exit(0 if ("--help" in sys.argv or "-h" in sys.argv) else 1)
    if not TOKEN:
        print("ERROR: 请设置 GITHUB_TOKEN 环境变量")
        sys.exit(1)
    keep = args[0]
    targets = args[1:]

    if not targets:
        # 自动模式：只删"本次批次"产生的中间版本。
        # 批次识别：版本号 >= keep 前一个已存在的正式版之后的 prerelease。
        # 保守做法：只删与 keep **同一天**且序号小于 keep 的 prerelease
        # （本次批次都是当天连续序号），不动历史日期的 prerelease。
        rels = api("GET", "/releases?per_page=30")
        if isinstance(rels, dict):
            print("ERROR: 取 releases 失败:", rels)
            sys.exit(1)
        keep_day = keep[1:].rsplit(".", 1)[0] if keep.startswith("v") else ""
        targets = []
        for r in rels:
            tag = r.get("tag_name", "")
            if not r.get("prerelease") or tag == keep:
                continue
            day = tag[1:].rsplit(".", 1)[0] if tag.startswith("v") else ""
            if day == keep_day and tag < keep:
                targets.append(tag)
        targets = sorted(set(targets))
        print("将删除（仅同日期、序号小于 keep 的 prerelease）:", targets)
        if not targets:
            print("无需删除")
            return

    for tag in targets:
        # 1) 删 release
        rel = api("GET", "/releases/tags/" + tag)
        if "id" in rel:
            api("DELETE", "/releases/" + str(rel["id"]))
            print("deleted release:", tag)
        else:
            print("release not found (可能已删):", tag)
        # 2) 删 tag
        out = subprocess.run(
            ["git", "push", "--delete", "origin", "refs/tags/" + tag],
            capture_output=True, text=True)
        if out.returncode == 0:
            print("deleted tag:", tag)
        else:
            print("tag delete failed:", tag, out.stderr.strip()[:120])

    print("done. keep:", keep)


if __name__ == "__main__":
    main()
