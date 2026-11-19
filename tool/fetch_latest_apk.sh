#!/bin/sh
# 下载最新 prerelease/release 的 arm64 APK 到 /var/minis/attachments/（供真机安装验证）。
#
# 用法：bash tool/fetch_latest_apk.sh [tag]
#   不带 tag → 取最新 release（优先 prerelease，因真机验证用预发版）
#   带 tag   → 取指定 tag
#
# 依赖：curl + python3（解析 GitHub API JSON）
set -e

REPO="yingo-server/TiernanMusic-Next"
# Token 只从环境变量读，绝不写进仓库（GitHub secret scanning 会拦截 push，
# 且泄露的 token 必须撤销重发）。
: "${GITHUB_TOKEN:?请先设置 GITHUB_TOKEN 环境变量（export GITHUB_TOKEN=xxx）}"
TOKEN="$GITHUB_TOKEN"
OUT_DIR="/var/minis/attachments"
TAG="${1:-}"

API="https://api.github.com/repos/$REPO"
AUTH="Authorization: token $TOKEN"

if [ -z "$TAG" ]; then
  TAG=$(curl -s -H "$AUTH" "$API/releases?per_page=10" | python3 -c "
import sys, json
rels = json.load(sys.stdin)
# 优先 prerelease（真机验证用），否则取最新正式版
pre = [r for r in rels if r.get('prerelease')]
pool = pre if pre else rels
print(pool[0]['tag_name'] if pool else '')
")
fi

if [ -z "$TAG" ]; then
  echo "ERROR: 找不到可用 release" >&2
  exit 1
fi

echo "目标 tag: $TAG"

curl -s -H "$AUTH" "$API/releases/tags/$TAG" | python3 -c "
import sys, json
r = json.load(sys.stdin)
assets = [a for a in r.get('assets', []) if a['name'].endswith('.apk')]
if not assets:
    print('ERROR: 该 release 无 APK 资产'); sys.exit(1)
# 优先 arm64（主流真机）
arm = [a for a in assets if 'arm64-v8a' in a['name']] or assets
print(arm[0]['browser_download_url'])
" > /tmp/_apk_url.txt

URL=$(cat /tmp/_apk_url.txt)
echo "下载地址: $URL"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/$(basename "$URL")"
curl -L -H "$AUTH" -o "$OUT" "$URL"
ls -lh "$OUT"
echo "完成: $OUT"
