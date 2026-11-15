# 批3-F1 MV端点修正 · 修改说明

改动文件（仅 2 个）：
- lib/core/net/endpoint_registry.dart（336→379 行）
- lib/core/net/endpoints/mv_endpoints.dart（386→499 行，≤500 达标）

## 1. endpoint_registry.dart
1. videoDetail 契约注释修正：对齐 batch3_c1.md §1.2 data[0] 平铺契约，明确 body 需
   data:[{video_id}]/show_resolution:1/mid/uuid=md5(dfid+mid)/key=signParamsKey(秒)/token/
   appid/clientver/clienttime；并注明 r/ext/cmd/qualities 是 trackermv /v2/interface/index
   （video_url.js L4-10）参数、不是 /v1/video body 参数（防再混入）。原声明注释里的
   「备用 /kmr/v2/videos」移除。
2. videoDetailKmrV2 死声明删除（三态实测 404），原位留「已弃用」注释说明批3-F1 删除与
   复活条件（需重新三态实测）。
3. 新增 anonymousSongUrl 声明：GET /v5/url @ trackercdn.kugou.com，signType none（notSign，
   song_url.js L51）、encryptKey:true（L50）、cacheable:false；标「待实测」，注明匿名 20028
   fail_process:['pkg'] 风险（field_truth_test L403-408）。
4. 新增 registerDevice 声明：POST https://userservice.kugou.com/risk/v2/r_register_dev
   （register_dev.js L104-105），signType none + clearDefaultParams；注释含
   playlistAesEncrypt body（L98）、query part/platid/p=rsaEncrypt2({aes,uid,token})（L100）、
   响应 AES 解密 data.dfid 写 cookie（L119-122）；标「待实测」。

## 2. mv_endpoints.dart
1. getVideoQualities 重写（修契约错位）：body 由 {'hash'} 改为上游全参
   （data:[{video_id}]、show_resolution:1、mid、uuid=md5(dfid+mid)、key=signParamsKey、
   dfid/token/appid/clientver/clienttime）；解析改 data[0] 平铺 → MvQuality.fromFlat
   （喂入点建立，含 data 平铺兜底）；videoDetailKmrV2 fallback 调用删除（空档显式 Log，
   注明 fallback removed: 404 deprecated）。新增 import：dart:convert、crypto_rsa、
   signing(KugouSign,md5Hex)。
2. 旧数组解析 _parseQualities 删除（死代码，随 fallback 一并清）。
3. 新增 registerDevice(client)：dataMap 设备指纹默认值对齐 register_dev.js L13-96
   （brand=Redmi/device=marble/Xiaomi、imei/uuid/suuid/serialnum=匿名 dfid 兼作
   KUGOU_API_GUID、userid:0）；playlistAesEncrypt → rawBody 密文，p=rsaEncrypt2({aes,
   uid:'0',token:''})，query part:1/platid:2（platid 2 vs 上游明示 1 标注待实测定稿）；
   响应 _raw_text → playlistAesDecrypt → status==1 时 data.dfid 回写 client.session.dfid
   （等价上游写 cookie）。全函数标「待实测」，未实测前调用方不得依赖。
4. 新增 anonymousPlayUrl(client, hash, {quality='128'})：调 anonymousSongUrl 端点，
   IsFreePart:1 恒传（song_url.js L32 试听语义，匿名可拿 128 试听），匿名随机 dfid 复用
   session.dfid 首访随机 24 位（L52 语义）；响应按 §A3-1 顶层即数据解析，返回
   ParsedPlayUrlShim——ParsedPlayUrl 同构镜像（L4 侧，字段一一对应，不 import L5，
   跨层只经六桥），isFreePart/end_byte/timeLength 等试听语义齐全。20028 风险注释在案。
5. 行数控制：压缩注释/常量体后全文件 499 行。

## 自检结论
- 契约修正逐条完成（videoDetail body、data[0] 平铺解析、kmr fallback 删除）。
- registerDevice / anonymousPlayUrl 两封装 + 两个 registry 声明均带「待实测」（共 15 处
  mv_endpoints / 6 处 registry 标注）；platid 1/2 变体、hex 大小写等不确定点全部显式标注，
  未冒充可用。
- MvQuality.fromFlat 已有生产喂入点（getVideoQualities L~306）。
- 未跑分析器、未提交、无真实网络调用；括号/圆括号平衡校验通过（脚本级，非 dart analyze）。
- 后续建议：探针（batch3_c3.md §5 顺序）实测 r_register_dev 与匿名 /v5/url 后回填真实
  platid / hex 形态 / 20028 形态锚点。
