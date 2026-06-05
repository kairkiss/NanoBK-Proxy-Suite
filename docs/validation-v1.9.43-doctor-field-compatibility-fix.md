# v1.9.43 — Bot/Web Doctor Summary Field Compatibility Minimal Fix

> 验证类型：Bot/Web Doctor Summary 字段兼容性最小修复
> 日期：2026-06-05
> 基线 commit：`4457a10b40f0c67ba9ac679d72e491998ea360c6`
> 基线信息：`test: add v1.9.42 doctor field compatibility fixtures`

---

## 1. 本轮目标与结论

**v1.9.36/v1.9.37 Bot/Web Doctor Summary 字段兼容性修复：**

- ✅ 修复 T15-P2-001
- ✅ 无 CLI 行为变更
- ✅ 无安装器行为变更
- ✅ 无部署逻辑变更
- ✅ 未执行真实 status
- ✅ 未执行真实 doctor
- ✅ 无 tag/release

**结论：Bot/Web Doctor Summary builder 的 profile/config 推断逻辑现在兼容真实 `nanobk --json status` 输出 shape（`profile.exists`、`configDir`、`security.secretsExists`），同时保持与 v1.9.35 原有 fixture 的向后兼容。**

---

## 2. 变更路径

| 文件 | 变更 |
|------|------|
| `bot/nanobk_bot.py` | 更新 `build_doctor_summary()` 的 profile/config 推断逻辑 |
| `web/app.py` | 更新 `build_doctor_summary()` 的 profile/config 推断逻辑 |
| `tests/doctor-field-compatibility-runtime-v1.9.43.py` | 新增运行时兼容性测试（282 项） |
| `docs/validation-v1.9.43-doctor-field-compatibility-fix.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.43 条目 |
| `docs/roadmap.md` | 新增 v1.9.43 行 |

---

## 3. 兼容性修复摘要

### Profile 推断变更

| 条件 | 旧行为 | 新行为 |
|------|:------:|:------:|
| `profile.currentPath` 存在 | present | present（不变） |
| `profile.domain` 存在 | present | present（不变） |
| `profile.exists == true` | **unknown** | **present** |
| `profile.exists == false` | **unknown** | **missing** |
| 顶层 `domain` 不为 `"<not set>"` | present | present（不变） |

### Config 推断变更

| 条件 | 旧行为 | 新行为 |
|------|:------:|:------:|
| profile 为 present | present | present（不变） |
| `configDir` 非空字符串 | **unknown** | **present** |
| `security.secretsExists == true` | **unknown** | **present** |
| warnings 含 "config directory not found" | missing | missing（不变） |
| warnings 含 "profile not found" | missing | missing（不变） |

### Security 推断

未变更。`secretsMode` 存在 → ok，否则 → warning。

---

## 4. Bot 行为

- Bot `/doctor` 摘要现在处理 v1.9.42 realistic status shape
- 高级 OFF 仍为仅摘要
- 高级 ON 仍为摘要 + 脱敏完整诊断
- 完整输出 `safe_output()` 路径不变
- 摘要中无 raw path/domain/IP/URL

---

## 5. Web 行为

- Web `/doctor` 摘要卡片现在处理 v1.9.42 realistic status shape
- 高级 OFF 仍为仅摘要卡片
- 高级 ON 仍为摘要 + 警告 + 折叠 details 完整诊断
- 完整输出 `safe_output()` 路径不变
- 摘要中无 raw path/domain/IP/URL

---

## 6. 诚实性行为

| 规则 | 状态 |
|------|------|
| missing 保持 missing | ✅ |
| unknown 保持 unknown（无证据） | ✅ |
| services missing 不变为 healthy | ✅ |
| Cloudflare missing 不变为 verified | ✅ |
| 无伪造成功 | ✅ |

---

## 7. 安全行为

| 安全特性 | 状态 |
|----------|------|
| 无 raw configDir 路径显示 | ✅ |
| 无 raw IP/domain/URL/token/private key 显示 | ✅ |
| 无 env 读取 | ✅ |
| 无直接写入 | ✅ |
| 无 CLI 变更 | ✅ |
| 无 production status wrapper | ✅ |
| 无 dirty VPS status wrapping | ✅ |

---

## 8. 测试运行

| 测试 | 结果 |
|------|------|
| `python3 tests/doctor-summary-contract-v1.9.35.py` | ✅ 352 passed |
| `python3 tests/doctor-field-compatibility-fixtures-v1.9.42.py` | ✅ 294 passed |
| `python3 tests/doctor-field-compatibility-runtime-v1.9.43.py` | ✅ 282 passed |
| `python3 tests/bot-doctor-summary-v1.9.36.py` | ✅ 163 passed |
| `python3 tests/web-doctor-summary-v1.9.37.py` | ✅ 164 passed |
| `python3 tests/doctor-output-checkpoint-v1.9.38.py` | ✅ 208 passed |
| `python3 bot/nanobk_bot.py --self-test` | ✅ 180 passed |
| `python3 web/app.py --self-test` | ✅ 106 passed |
| `bash tests/bot-cli-mock.sh` | ✅ All passed |
| `bash tests/web-panel-mock.sh` | ✅ All passed |

---

## 9. 已知限制

| 限制 | 说明 |
|------|------|
| 真实 Bot/Web session 未重测 | 本实现周期未重测 |
| Claude Code 未执行真实 status | 仅使用 fake fixture |
| Bot/Web builder 逻辑重复 | 未来可提取共享模块 |
| Fingerprint redaction 仍为独立任务 | 未变更 |
| Web Doctor 折叠状态仍为独立打磨项 | 未变更 |

---

## 10. 下一步

**推荐：v1.9.44 — Doctor Summary Field Compatibility Checkpoint**

需 ChatGPT 审核后实施。
