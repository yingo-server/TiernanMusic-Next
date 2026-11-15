batch=7
stage=release_retry
last_commit=db09368
stable_dispatch_first=failed_ci_compile_errors
fix=full-SDK compile errors + 1500-line rule
retry_timer=fab23e0d-2996-4e8d-9c76-c18c24d9c02a
note=首次 stable=true run 因并发代理遗留编译错失败；db09368 已修并推送。定时器在 push CI 绿后重发 stable=true，再终验 prerelease=false + 3 APK + verification.json。
