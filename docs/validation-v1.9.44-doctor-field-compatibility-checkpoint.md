# v1.9.44 — Doctor Summary Field Compatibility Checkpoint

> 验证类型：Doctor Summary 字段兼容性检查点
> 日期：2026-06-05
> 基线 commit：`99ad7debc1af1c41d6ea326f9b37ed623a9770dc`
> 基线信息：`fix: align doctor summary field compatibility`

---

## 1. 本轮目标与结论

**v1.9.44 是检查点/验证任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无 CLI 行为变更
- ✅ 无部署逻辑变更
- ✅ 未执行真实 status
- ✅ 未执行真实 doctor
- ✅ 无 tag/release
- ✅ 目的是验证 v1.9.43 字段兼容性修复

**结论：T15-P2-001 在源码/fixture 级别已修复。Bot/Web Doctor Summary builder 现在正确推断 profile/config，兼容真实 status JSON shape，同时保持诚实性和安全性。**

---

## 2. 当前兼容性架构

| 特性 | 说明 |
|------|------|
| Bot builder | `build_doctor_summary()` 在 `bot/nanobk_bot.py` |
| Web builder | `build_doctor_summary()` 在 `web/app.py` |
| 共享模块 | 尚未提取（Bot/Web 逻辑重复） |
| 消费字段 | `profile.exists`、`configDir`、`security.secretsExists` |
| Schema | 保持 v1.9.35 合约 |
| 摘要 | 安全新手摘要 |
| 完整诊断 | 仅限高级模式 |
| 向后兼容 | v1.9.35 原有 fixture 仍通过 |

---

## 3. Bot 检查点

| 检查项 | 结果 |
|--------|------|
| `build_doctor_summary()` 支持 v1.9.42 fixtures | ✅ |
| `profile.exists == true` → profile present | ✅ |
| `profile.exists == false` → profile missing | ✅ |
| `configDir` 非空 → config present（路径不显示） | ✅ |
| `security.secretsExists == true` → config present | ✅ |
| explicit missing 保持 missing | ✅ |
| services missing 不变为 healthy | ✅ |
| 格式化摘要无 raw path/IP/domain/URL/token | ✅ |
| 高级 OFF/ON 行为不变 | ✅ |
| `safe_output` 完整诊断路径不变 | ✅ |

---

## 4. Web 检查点

| 检查项 | 结果 |
|--------|------|
| `build_doctor_summary()` 支持 v1.9.42 fixtures | ✅ |
| 与 Bot 相同规则 | ✅ |
| 摘要卡片无 raw path/IP/domain/URL/token | ✅ |
| 高级 OFF/ON 行为不变 | ✅ |
| 折叠完整诊断行为不变 | ✅ |
| `safe_output` 完整诊断路径不变 | ✅ |
| `/api/status` 不变 | ✅ |

---

## 5. 一致性矩阵

| 边界/能力 | Bot | Web | 测试覆盖 | 剩余风险 |
|-----------|:---:|:---:|:--------:|:--------:|
| v1.9.35 schema | ✅ | ✅ | 合约测试 | 无 |
| v1.9.42 fixtures consumed | ✅ | ✅ | 运行时测试 | 无 |
| `profile.exists == true` | ✅ | ✅ | 运行时测试 | 无 |
| `profile.exists == false` | ✅ | ✅ | 运行时测试 | 无 |
| configDir inference | ✅ | ✅ | 运行时测试 | 无 |
| `security.secretsExists == true` | ✅ | ✅ | 运行时测试 | 无 |
| `security.secretsExists == false` | ✅ | ✅ | 运行时测试 | 无 |
| currentPath/domain backward compat | ✅ | ✅ | 运行时测试 | 无 |
| no raw config path | ✅ | ✅ | 安全检查 | 无 |
| no raw IP/domain/URL/token | ✅ | ✅ | 安全检查 | 无 |
| unknown remains unknown | ✅ | ✅ | fixture 测试 | 无 |
| missing remains missing | ✅ | ✅ | fixture 测试 | 无 |
| services missing not healthy | ✅ | ✅ | fixture 测试 | 无 |
| Cloudflare missing not verified | ✅ | ✅ | fixture 测试 | 无 |
| full diagnostics advanced-only | ✅ | ✅ | 源码检查 | 无 |
| /status_json unchanged | ✅ | — | Bot 测试 | 无 |
| /api/status unchanged | — | ✅ | Web 测试 | 无 |
| redaction unchanged | ✅ | ✅ | redaction 测试 | 无 |
| advanced mode unchanged | ✅ | ✅ | 高级模式测试 | 无 |
| rotate unchanged | ✅ | ✅ | 源码检查 | 无 |
| CLI/installer unchanged | ✅ | ✅ | 源码检查 | 无 |
| no tag/release | ✅ | ✅ | Git 检查 | 无 |

---

## 6. 安全决策

**字段兼容性修复在源码/fixture 级别是安全的。**

但不构成以下许可：

- ❌ 泄漏 raw config 路径
- ❌ 泄漏 raw IP/domain/URL
- ❌ 泄漏 token/secret/private key
- ❌ 读取 env 文件
- ❌ 运行真实 status
- ❌ 运行真实 doctor
- ❌ 改变 CLI 输出
- ❌ 实现 production status wrapper
- ❌ 实现 dirty VPS status wrapping
- ❌ 交付 subscription
- ❌ tag/release

---

## 7. 就绪决策

**A. READY FOR LIMITED REAL DOCTOR FIELD COMPATIBILITY RETEST PLANNING**

原因：v1.9.43 修复了真实 T15 UI 问题。最安全的下一步是规划小型用户手动重测，确认 Bot/Web Doctor Summary 中 Profile/Config 不再显示 unknown。

约束：
- 仅控制面
- 无部署
- 无 Cloudflare 变更
- 无真实 rotate
- 仅脱敏 PASS/FAIL 报告
- 无 tag/release

---

## 8. 真实重测定位

| 约束 | 说明 |
|------|------|
| 不运行完整 VPS 部署 | ✅ |
| 不运行 Cloudflare 变更 | ✅ |
| 不运行真实 rotate | ✅ |
| 重测仅限控制面 | ✅ |
| 重测重点 | Bot /doctor 高级 OFF 显示 Profile/Config present；Web /doctor 高级 OFF 显示 Profile/Config present；高级 ON 仍正常；无 raw path/IP/domain/URL/token |
| 现有门控 | status/status_json/advanced 仍正常 |
| 报告格式 | 仅脱敏 PASS/FAIL |

---

## 9. 可能的下一步

| 选项 | 内容 | 推荐 |
|------|------|------|
| **选项 1** | v1.9.45 — 有限真实 Doctor 字段兼容性重测计划 | ✅ 推荐 |
| 选项 2 | v1.9.45 — Fingerprint Redaction 策略规划 | 次选 |
| 选项 3 | v1.9.45 — Bot/Web 语言传播规划 | 次选 |
| 选项 4 | v1.9.45 — Bot/Web systemd 规划 | 次选 |

**推荐选项 1：v1.9.45 — 有限真实 Doctor 字段兼容性重测计划**

原因：T15-P2-001 是真实环境发现。代码修复 + 检查点后，确认真实 UI 结果再进入 fingerprint/i18n/systemd 工作。

---

## 10. 已知限制

| 限制 | 说明 |
|------|------|
| 检查点未重测真实 Bot/Web session | 源码/fixture 验证 |
| 未执行真实 status | Claude Code 未执行 |
| 未执行真实 doctor | Claude Code 未执行 |
| Bot/Web builder 逻辑重复 | 未来可提取共享模块 |
| Fingerprint redaction 独立 | 未变更 |
| Web Doctor 折叠状态独立 | 未变更 |
| 语言传播独立 | 未变更 |
| systemd/Web production runner 独立 | 未变更 |

---

## 11. Guardrails

| # | 约束 | 状态 |
|---|------|------|
| 1 | 无 install.sh 行为变更 | ✅ |
| 2 | 无 bin/nanobk 行为变更 | ✅ |
| 3 | 无 installer/doctor.sh 行为变更 | ✅ |
| 4 | 无协议模板变更 | ✅ |
| 5 | 无 Worker 变更 | ✅ |
| 6 | 无 rotate sync 变更 | ✅ |
| 7 | 无直接 Bot/Web 写入 configs/systemd/secrets | ✅ |
| 8 | 无 raw env 读取 | ✅ |
| 9 | 无真实 status 执行 | ✅ |
| 10 | 无真实 doctor 执行 | ✅ |
| 11 | 无 production status wrapper | ✅ |
| 12 | 无 dirty VPS status wrapping | ✅ |
| 13 | 无 operation-log full rollout | ✅ |
| 14 | 无 raw subscription delivery | ✅ |
| 15 | 无 tag/release | ✅ |
