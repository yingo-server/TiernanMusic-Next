#!/bin/bash
# 本地门禁：全绿输出 FINAL-OK；失败输出 VIOLATION/FAIL 并退出 1。
#
# 批08 事故复盘：原脚本用超宽的 rg 黑名单过滤 dart analyze 输出，既漏真错误
# （CI 连红两天无人察觉），又误报 2000+ 条 isar 注解噪音。改为：
#   ① dart format 语法闸（不依赖 Flutter SDK，抓编译级语法错）
#   ② analyze_gate（只挑「缺失名属于项目内类型」的真错误，精确）
#   ③ 纯 Dart 契约自检（锚点/可达性/启动/下载）
set -e
cd /var/minis/workspace/NextWorkspace/TiernanMusic-Next

echo "== layer_audit =="
python3 tool/layer_audit.py || exit 1

echo "== dart syntax gate =="
if ! /opt/dart/bin/dart format --output=none lib tool > /tmp/syntax.log 2>&1; then
  grep -i "could not format" /tmp/syntax.log | head -20
  echo "FAIL-syntax"
  exit 1
fi
echo PASS-syntax

echo "== analyze gate (project-type errors only) =="
python3 tool/analyze_gate.py || exit 1

echo "== md5 smoke =="
/opt/dart/bin/dart run tool/md5_smoke.dart >/dev/null 2>&1 || { echo FAIL-md5; exit 1; }
echo PASS-md5

echo "== field truth anchors =="
/opt/dart/bin/dart run tool/field_truth_test.dart 2>&1 | tail -1 | grep -q "FIELD-TRUTH-OK" || {
  echo FAIL-field-truth; exit 1; }
echo PASS-field-truth

echo "== feature reachability =="
/opt/dart/bin/dart run tool/feature_reachability_test.dart 2>&1 | tail -1 | grep -q "FEATURE-REACHABILITY-OK" || {
  echo FAIL-reachability; exit 1; }
echo PASS-reachability

echo "== boot contract =="
/opt/dart/bin/dart run tool/boot_contract_test.dart 2>&1 | tail -1 | grep -q "0 failed" || {
  echo FAIL-boot-contract; exit 1; }
echo PASS-boot-contract

echo "== play contract (three-state verdict + quality ladder) =="
/opt/dart/bin/dart run tool/play_contract_test.dart 2>&1 | tail -1 | grep -q "0 failed" || {
  echo FAIL-play-contract; exit 1; }
echo PASS-play-contract

echo "== resolve contract (three-state + prefetch) =="
/opt/dart/bin/dart run tool/resolve_contract_test.dart 2>&1 | tail -1 | grep -q "0 failed" || {
  echo FAIL-resolve-contract; exit 1; }
echo PASS-resolve-contract

echo "== download contract =="
/opt/dart/bin/dart run tool/download_contract_test.dart 2>&1 | tail -1 | grep -q "0 failed" || {
  echo FAIL-download-contract; exit 1; }
echo PASS-download-contract

echo FINAL-OK
