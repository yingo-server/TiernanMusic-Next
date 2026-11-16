# A2 两个密码学 P0 的独立复核（主会话，2026-11-16）

> 子代理为只读静态分析（禁止跑 dart），其 P0 为推导结论。主会话用 Python 精确仿真 Dart 64 位有符号 int 语义独立验证，避免误改本就正确的代码。
> 验证脚本：`docs/deep_audit/verify_a2_p0.py`（可复现，纯独立仿真，不改仓库代码）。

## P0 #1 · `crypto_aes.dart:574` AES 密钥扩展 Rcon 恒 0x01 —— ✅ 确认为真 bug

**验证方法**：用 FIPS-197 附录 C.1 标准向量（key=`000102…0f`，plaintext=`00112233445566778899aabbccddeeff`，期望密文=`69c4e0d86a7b0430d8cdb78070b4c55a`），分别以「恒 0x01」与「标准 Rcon 序列」仿真 `_expandKey` + `_encryptBlock`。

**结果**：
```
[AES Rcon=const1   ] ciphertext=891a2af93dc9b72af8eb10887a272c14  FAIL
[AES Rcon=standard ] ciphertext=69c4e0d86a7b0430d8cdb78070b4c55a  PASS
```

**裁定**：Rcon 必须按轮次取 `[0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36][i~/16 − 1]`。当前实现只第 1 轮正确，第 2–10 轮轮密钥全错 → 与标准 AES **无法互通**。

**与历史"实测通过"的悖论解释**：encrypt/decrypt 共用同一套（错误）轮密钥，因此 `decrypt(encrypt(x)) == x` 自洽；自洽测试/只看格式的测试不会暴露此 bug，只有与上游标准 AES 互通时才失败。这解释了为何带病上线至今。

**修复建议（待阶段 A 全部审完后主会话亲修）**：
- 首选（符合用户"算法用成熟库"）：把 `AesCbc` 的块加密替换为成熟库实现（`encrypt: ^5.x` 或 `cryptography`），自研 `crypto_aes.dart` 退役或仅留兼容壳。
- 若短期只修 bug：按上面 Rcon 数组改一行，并**必须**补 FIPS-197 C.1 + NIST SP800-38A CBC 向量离线回归。

## P0 #2 · `crypto_bigint.dart:82` BigIntL.mul 32-bit 相乘溢出 —— ❌ 误报，实现正确

**验证方法**：精确仿真 Dart 64 位有符号 int 的 `&`、`>>>`、乘法回绕语义，对内层循环 `t = r[i+j] + limbs[i]*o.limbs[j] + carry; r[i+j]=t & 0xffffffff; carry = t >>> 32` 做 20 万组随机 32-bit 相乘 + 4 组极端边界值。

**结果**：
```
[BigIntL.mul 仿真] 200000 组 32-bit 相乘, 错误数=0
边界 0xffffffff*0xffffffff: got=0xfffffffe00000001 truth=0xfffffffe00000001 OK
边界 0xffffffff*0x1:        got=0xffffffff truth=0xffffffff OK
边界 0x80000000*0xffffffff: got=0x7fffffff80000000 truth=0x7fffffff80000000 OK
边界 0xffffffff*0x80000000: got=0x7fffffff80000000 truth=0x7fffffff80000000 OK
```

**裁定：误报，禁止据此改代码。** 数学原因：
1. 两个 32-bit 无符号数之积 `a*b ≤ (2^32−1)² = 2^64−2^33+1`，自带 **2^33 余量**；
2. `r[i+j] ≤ 2^32−1`、`carry ≤ 2^32−1`，两者和 ≤ 2^33−2，**填不满该余量**；
3. 故 `t = r[i+j] + a*b + carry ≤ 2^64−1`，**不越 64 位**，其补码位模式即为正确的 64 位乘积；
4. `& 0xffffffff` 取低 32 位、`>>> 32`（Dart 无符号右移，按 64 位补码位模式操作）取高 32 位 —— 二者操作的都是这个正确位模式，结果正确。

子代理的推理「`0xffffffff*0xffffffff ≈ 2^64` 超过 int64 上限会 wrap 成负数致结果错」不成立：wrap 后位模式不变，`&`/`>>>` 是按位运算，不受有符号解释影响。

**加固验证**（`docs/deep_audit/verify_bigint_fast.py`，仿真完整 `mul` 的多 limb 累加 + carry 传播链，并用 `mul` 作原语跑平方乘 modPow 对照 Python）：
```
[完整 mul] 100000 组 1~4 limb(含顶 limb 拉满边界): 错误数=0
[modPow 平方乘, mul 作原语] 3000 组: 错误数=0
```
`mul` 正确 ⇒ 基于它的 `modPow`（重复 `mul(base,base).mod(m)`）自然正确。双重验证一致。

**处置**：`bA2_c2.md` 该条 P0 **撤销**（降级为「已复核·非缺陷」）。连带推论「RSA modPow 从第 2 次平方起全错、rsaEncrypt2 输出错误密文」一并作废。RSA 完整正确性留待阶段 A 修复期用真实 dart + 已知密文向量终验（本轮子代理禁跑 dart）。

## 对其他发现的影响

- P0 #1（AES）与 C3「自研 AES 不可信、YKG 应用成熟库」结论**互相印证**：进一步支持「YKG 新代码一律用成熟库、不复用自研 AesCbc」的设计（`docs/YKG_LINK_CRYPTO_DESIGN.md` §8 已如此规定）。
- C2 的其余 P1/P2（inflight clear 竞态、缓存失效语义、cacheKey 降级、body 流超时、dfid 随机性等）未做算法仿真，保持原判，待交叉汇总。
