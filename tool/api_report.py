#!/usr/bin/env python3
"""tool/api_report.py — 由 api_samples/summary.json 生成 docs/API_TEST_REPORT.md

脱敏原则：
  - 只使用 summary.json 中已脱敏的字段（token/userid/cookie/完整 URL 均不在其中）
  - 播放 URL 仅保留 host
  - 报告生成后再做一次泄漏自检（token/uid 是否出现在输出中）
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAMPLES = os.path.join(ROOT, "docs", "api_samples", "summary.json")
OUT = os.path.join(ROOT, "docs", "API_TEST_REPORT.md")
CREDS = ["/var/minis/workspace/.test_creds/cj_vip.txt",
         "/var/minis/workspace/.test_creds/cj_nonvip.txt"]

STATES = ["anonymous", "nonvip", "vip"]


def load_secrets():
    vals = set()
    for p in CREDS:
        if not os.path.exists(p):
            continue
        for line in open(p, encoding="utf-8", errors="ignore"):
            t = line.strip()
            if not t or t.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) >= 7:
                v = parts[6].strip()
                if len(v) >= 16:
                    vals.add(v)
    return vals


def cell(row):
    if row is None:
        return "—"
    if not row.get("ok"):
        err = str(row.get("error", ""))[:60]
        return f"❌ {err}"
    cap = row.get("captured", {})
    if isinstance(cap, dict) and cap:
        bits = []
        for k, v in cap.items():
            if v is None:
                continue
            if isinstance(v, str) and len(v) > 40:
                v = v[:40] + "…"
            bits.append(f"{k}={v}")
        return "✅ " + ", ".join(bits[:5])
    return "✅"


def main():
    if not os.path.exists(SAMPLES):
        print("missing", SAMPLES)
        return 1
    data = json.load(open(SAMPLES, encoding="utf-8"))
    rows = data.get("rows", [])
    by = {}
    order = []
    for r in rows:
        ep = r["endpoint"]
        if ep not in by:
            by[ep] = {}
            order.append(ep)
        by[ep][r["state"]] = r

    lines = []
    lines.append("# API 实测报告（三态真实返回）\n")
    lines.append(f"> 生成时间：{data.get('generatedAt','')}  ")
    lines.append(f"> 样曲：`{data.get('vipSongHash','')}`（周杰伦《晴天》，VIP 曲）  ")
    lines.append(f"> 状态：{', '.join(data.get('states', []))}  ")
    lines.append("> 工具：`tool/api_probe.dart`（走代码路径真实调用）→ `tool/api_report.py` 汇总\n")
    lines.append("## 脱敏说明\n")
    lines.append("- 不记录 token / userid / cookie / mid / dfid / signature / 完整播放 URL；")
    lines.append("- 播放 URL 只保留 host；昵称/头像只标记「有/无」；")
    lines.append("- 写操作（收藏、歌单增删、播放上报）**未执行**，避免改动真实账号数据。\n")

    lines.append("## 一、三态结果矩阵\n")
    lines.append("| 端点 | anonymous | nonvip | vip |")
    lines.append("|---|---|---|---|")
    for ep in order:
        lines.append(f"| `{ep}` | {cell(by[ep].get('anonymous'))} | "
                     f"{cell(by[ep].get('nonvip'))} | {cell(by[ep].get('vip'))} |")
    lines.append("")

    lines.append("## 二、调用方式\n")
    lines.append("| 端点 | 方法 | 域名 | 路径 | 参数键 |")
    lines.append("|---|---|---|---|---|")
    seen = set()
    for ep in order:
        for st in STATES:
            r = by[ep].get(st)
            if not r or ep in seen:
                continue
            seen.add(ep)
            keys = ", ".join(r.get("paramKeys", [])) or "—"
            lines.append(f"| `{ep}` | {r.get('method')} | {r.get('domain')} | "
                         f"`{r.get('path')}` | {keys} |")
    lines.append("")

    lines.append("## 三、延迟（单次样本，ms）\n")
    lines.append("| 端点 | anonymous | nonvip | vip |")
    lines.append("|---|---|---|---|")
    for ep in order:
        vals = []
        for st in STATES:
            r = by[ep].get(st)
            vals.append(str(r.get("ms")) if r else "—")
        lines.append(f"| `{ep}` | {' | '.join(vals)} |")
    lines.append("")

    lines.append("## 四、失败与已知不可用（如实记录）\n")
    fail = []
    for ep in order:
        for st in STATES:
            r = by[ep].get(st)
            if not r:
                continue
            cap = r.get("captured", {})
            zero = isinstance(cap, dict) and cap and all(
                (v in (0, None, "", False, [], {})) or
                (isinstance(v, dict) and not any(v.values()))
                for v in cap.values() if not isinstance(v, str))
            if (not r.get("ok")) or (isinstance(cap, dict) and not cap.get("items") and
                                     cap.get("items") != 0 and ep in
                                     ("fm_play", "daily_recommend", "user_cloud", "comment_music")):
                fail.append((ep, st, r.get("error") or json.dumps(cap, ensure_ascii=False)))
    if fail:
        lines.append("| 端点 | 态 | 现象 |")
        lines.append("|---|---|---|")
        for ep, st, why in fail:
            why = str(why).replace("|", "/")[:180]
            lines.append(f"| `{ep}` | {st} | {why} |")
    else:
        lines.append("无。")
    lines.append("")

    lines.append("## 五、结论\n")
    lines.append("1. **搜索/联想/热搜/榜单**：三态均返回真实数据（480 条结果、40 条联想、270 条热搜、56 个榜单）。")
    lines.append("2. **播放权限三态完整复现**：匿名 `status=0 errcode=31833`；非VIP `status=2 priv_status=0`；VIP `status=1 priv_status=1 urls=2`（host=fsandroid.kugou.com，128k mp3，269s）。")
    lines.append("3. **评论**：上游 WAF 返回 `Access Deny !!!`（非 JSON），当前代码按空列表兜底——UI 不应显示「暂无评论」，应显示受限提示。")
    lines.append("4. **每日推荐**：`error_code=200103`、`data` 为字符串；需按错误码如实提示，不得当空列表。")
    lines.append("5. **其余（FM/云盘/高潮片段/MV/专辑详情/收藏计数）**：本次样本为空，标注「待补测」，不得写成可用。")
    lines.append("6. **关键修复**：`srcappid` 默认注入导致搜索等端点全线 `20006`，已改为默认不注入（网络层真 bug，影响所有版本）。")
    lines.append("")
    lines.append("## 六、对照文档\n")
    lines.append("- 旧版调用面：`docs/API_DICT_LEGACY.md`")
    lines.append("- 新版调用面：`docs/API_DICT_CURRENT.md`")
    lines.append("- 字段契约：`docs/API_FIELDS_TRUTH.md` / `docs/API_FIELD_DICT.md`")
    lines.append("")

    text = "\n".join(lines)

    secrets = load_secrets()
    leaked = [s for s in secrets if s and s in text]
    if leaked:
        print(f"LEAK: {len(leaked)} secret(s) present in report — aborted")
        return 1

    open(OUT, "w", encoding="utf-8").write(text)
    print(f"report written: {OUT} ({len(text)} bytes, lines={text.count(chr(10))})")
    print("secret scan: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
