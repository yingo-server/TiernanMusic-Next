# UX copy rewrite: string-value-only replacements (no structure change).
import os
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

# file -> list of (old, new); must appear as complete literal source text
PAGE_EDITS = {
  'lib/surface/pages/settings_page.dart': [
    ("Text('音质档位'", "Text('音质'"),
    ("Text('播放倍速'", "Text('倍速'"),
    ("_toast('缓存能力未装配')", "_toast('缓存功能暂未开放')"),
    ("'清理会话缓存与请求合并表'", "'清理临时缓存文件'"),
  ],
  'lib/surface/pages/player_page.dart': [
    ("Text('播放速度'", "Text('倍速'"),
    ("Text('下载失败：$e')", "Text('下载失败，请稍后重试')"),
    ("Text('FM 暂无可用曲目（端点待实测）')", "Text('FM 暂无可用曲目')"),
    ("Text('FM 启动失败：$e')", "Text('FM 启动失败，请重试')"),
    ("_msg('收藏失败：$e')", "_msg('收藏失败，请重试')"),
  ],
  'lib/surface/pages/mv_page.dart': [
    ("'装配图未就绪（MV 门面不可用）'", "'MV 功能暂未开放'"),
    ("'MV 地址不可用（可能被权限拦截）'", "'MV 暂不可用，可能是版权限制'"),
    ("'MV 地址为空'", "'MV 暂不可用'"),
    ("'http 明文链接已升级为 https'", "'已自动升级为安全链接（https）'"),
    ("'不支持的 MV 链接协议：$url'", "'MV 链接暂不支持，请重试'"),
    ("'MV 加载失败：$e'", "'MV 加载失败，请重试'"),
    ("'播放器已释放'", "'播放器已停止'"),
    ("'档位 $_quality'", "'音质 $_quality'"),
  ],
  'lib/surface/pages/library_page.dart': [
    ("Text('音乐库'", "Text('曲库'"),
    ("NavEntry('音乐库'", "NavEntry('曲库'"),
    ("title: '数据能力未装配'", "title: '数据加载暂不可用'"),
    ("title: '下载管理不可用'", "title: '下载管理暂不可用'"),
    ("subtitle: '下载能力未装配'", "subtitle: '下载功能暂未开放'"),
    ("subtitle: '在歌曲菜单里选择下载'", "subtitle: '在歌曲菜单中选择下载'"),
  ],
  'lib/surface/pages/login_sheet.dart': [
    ("'登录能力未装配'", "'登录功能暂未开放'"),
    ("_toast('验证码发送失败（接口待实测）')", "_toast('验证码发送失败，请稍后重试')"),
    ("'验证码登录端点待实测（needs probe）'", "'验证码登录暂不可用，请稍后重试'"),
    ("'登录失败：${res.error.isEmpty ? \\'未知错误\\' : res.error}'", "'登录失败，请检查账号信息后重试'"),
    ("_toast('密码登录待后端就绪')", "_toast('密码登录暂未开放')"),
    ("'二维码已过期，请下拉重试或退出重开'", "'二维码已过期，请刷新重试'"),
    ("'已在手机上扫码，请在手机端确认登录'", "'已扫码，请在手机上确认登录'"),
  ],
  'lib/surface/pages/search_page.dart': [
    ("'没有找到与「$_query」相关的歌曲'", "'没有找到与「$_query」相关的内容'"),
  ],
  'lib/surface/pages/home_page.dart': [
    ("'暂无每日推荐（登录后可能可见）'", "'登录后可查看每日推荐'"),
  ],
}

# arb key -> (zh, zh_Hant, en); only values touched, keys untouched
ARB_EDITS = {
  'errorNetwork': ('网络异常，请重试', '網路異常，請重試', 'Network error. Please retry.'),
  'errorTimeout': ('请求超时，请重试', '請求逾時，請重試', 'Request timed out. Please retry.'),
  'errorParse': ('数据解析失败，请重试', '資料解析失敗，請重試', 'Failed to parse response. Please retry.'),
  'errorServer': ('服务暂时不可用，请稍后重试', '服務暫時不可用，請稍後重試', 'Service temporarily unavailable. Please try again later.'),
  'errorGeneric': ('操作失败，请重试', '操作失敗，請重試', 'Operation failed. Please retry.'),
  'favoriteFailed': ('收藏失败，请重试', '收藏失敗，請重試', 'Favorite failed. Please retry.'),
  'downloadUnavailable': ('下载功能暂未开放', '下載功能暫未開放', 'Download not available yet'),
  'favoriteUnavailable': ('收藏功能暂未开放', '收藏功能暫未開放', 'Favorite not available yet'),
  'noPlayable': ('未找到可播放源，请换一首歌', '未找到可播放來源，請換一首歌', 'No playable source found — try another track'),
  'ykgRisk': ('此链接包含你的登录凭据，拿到链接并知道密码的人都能登录，请勿公开分享',
              '此連結包含你的登入憑據，拿到連結並知道密碼的人都能登入，請勿公開分享',
              'This link contains your credentials. Anyone with the link and password can sign in. Do not share publicly.'),
  'mvNoSong': ('缺少歌曲信息，无法查询 MV', '缺少歌曲資訊，無法查詢 MV', 'Missing song info, cannot look up MV'),
  'needVerification': ('需要人机验证（代码 20028）', '需要人機驗證（代碼 20028）', 'Human verification required (code 20028)'),
}

CODES = ['zh', 'zh_Hant', 'en']

changes = 0
for rel, pairs in PAGE_EDITS.items():
    path = f'{ROOT}/{rel}'
    src = open(path, encoding='utf-8').read()
    for old, new in pairs:
        n = src.count(old)
        if n == 0:
            print(f'skip (already applied or absent) {rel}: {old!r}')
            continue
        src = src.replace(old, new)
        changes += n
    open(path, 'w', encoding='utf-8').write(src)

for code in CODES:
    path = f'{ROOT}/lib/l10n/app_{code}.arb'
    src = open(path, encoding='utf-8').read()
    for key, vals in ARB_EDITS.items():
        v = vals[CODES.index(code)]
        import re
        pat = f'"{key}": "'
        i = src.index(pat)
        j = src.index('",', i)
        src = src[:i] + f'"{key}": "{v}",' + src[j+2:]
        changes += 1
    open(path, 'w', encoding='utf-8').write(src)

print('total value changes:', changes)
