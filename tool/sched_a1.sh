#!/bin/sh
set -e
minis-scheduled create \
  --label "A1批催总结" \
  --after 50m \
  --target follow-up \
  --prompt "【A1 批 · 50 分钟催总结】任务书：/var/minis/workspace/NextWorkspace/TiernanMusic-Next/docs/DEEP_AUDIT_14_BATCH_PLAN.md，状态：docs/DEEP_AUDIT_STATE.md。A1 三个子代理（job: f448ab0e-186c-4bb5-a0ac-76ec921021d5 / a4fec2ee-a982-4e6d-a869-e37f918ec9d8 / b3b81a8e-bd6b-495b-ac45-2a45b9af1778）应在 60 分钟硬超时。动作：1) 用 subagent_task action=status 查看三个 job 状态；2) 对仍 running 的用 steer 催它『用已有发现立即收口，未查完标未覆盖，现在把结论追加落盘到 docs/deep_audit/bA1_c*.md 并结束』；3) 检查 docs/deep_audit/bA1_c1.md、bA1_c2.md、bA1_c3.md 三个文件是否已实时落盘（ls -la 看大小与修改时间）；4) 读三个文件做交叉比对（同文件被多视角命中=确认，分歧=待复核）；5) 写 docs/deep_audit/bA1_summary.md：共识问题清单 + 分歧清单 + 本批 P0 汇总；6) 更新 docs/DEEP_AUDIT_STATE.md 中 A1 行状态；7) 若 A1 三份报告都已有结论，则立即派 A2 批三个子代理（core·net 底座，视角同 A1），并为 A2 设 50 分钟催总结定时器；若仍有未完成，则再设一个 10 分钟后的单次定时器收口。禁止 sleep 轮询。"
echo "--- scheduled created ---"
minis-scheduled list 2>&1 | head -20
