# 批4 整理（2026-11-15）

主题：UI 功能补全。按新规矩：已有客观报告复用，1-2 个小缺口主线直接修，不为凑数派代理。

## 检查结论（复用）
- `docs/autonomous_lineB_features.md` / `lineB_c.md`：本地曲库、最近播放、MV 页、MV/FM 入口、六类搜索、收藏/歌单写回执、评论受限态等原缺口清单。
- 主线 `rg` 复核 L7 占位：首页/设置/库/播放页占位已清；只剩搜索页 `_segment != 0` 写死「分类搜索暂不可用」。
- `appGraph.searchTyped` 与 `SearchTypedLogic.typed()` 已装配并导出 `SearchType`，属真实可接能力。

## 修复结果（主线）
- `lib/surface/pages/search_page.dart`：接入 `bridge_core.SearchType`，新增 `kSearchSegmentTypes`；`_doSearch` 按分段走 `search.search()` / `searchTyped.typed()`；SegmentedButton 切段即重搜；删「分类搜索暂不可用」空态。
- 此前已收口（不再重复派代理）：首页瘦身+热搜搬迁+历史持久化、主题四档生效（L6 ThemeController）、bar 按 navOrder 排序、登录三 Tab 弹层、library 本地曲库/最近播放真数据、MV 页 + player_page「查看 MV」/「个人 FM」直接启动、账号区拆分。
- 写回执 `_ok()` 已由批2 修为 `status==1 && error_code==0`。

## 门禁
- `dart format --output=none lib tool test`：通过
- `bash tool/local_gate.sh`：`FINAL-OK`
- `python3 tool/analyze_gate.py`：`analyze_gate ok`

## 未覆盖（不冒充）
- 评论发表/点赞、歌词行 seek、收藏/歌单写回执三态实测、FM/云盘/高潮真机验证、每日推荐 200103 登录态均保留在 `docs/ACCEPTANCE_CHECKLIST.md`。
- 搜索六类端点本身未在本批重新三态实测；UI 只接已装配 L5 能力，切段失败会走页面错误态。
