# v1.9.42 — Doctor Summary Field Compatibility Fixture Tests

> 验证类型：Doctor Summary 字段兼容性 Fixture 测试
> 日期：2026-06-05
> 基线 commit：`209010280fdb38223f94dc044b0e7d95dab89b93`
> 基线信息：`docs: add v1.9.41 doctor summary field compatibility planning`

---

## 1. 本轮目标与结论

**v1.9.42 是 fixture/test/文档任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无 CLI 行为变更
- ✅ 无部署逻辑变更
- ✅ 未执行真实 status
- ✅ 未执行真实 doctor
- ✅ 无 tag/release
- ✅ 目的是在实现前锁定安全的 realistic status shape 到测试中

**结论：创建了 6 个 fake realistic status 输入 fixture 和 6 个预期摘要 fixture，覆盖 T15-P2-001 的 profile.exists、security.secretsExists、configDir 字段兼容性场景。合约测试 294 项全部通过。**

---

## 2. Fixture 集摘要

### 输入 Fixtures

| 文件 | 场景 | 说明 |
|------|------|------|
| `realistic-status.json` | 真实 shape | `profile.exists: true`，`security.secretsExists: true`，`configDir` 非空，无 `profile.currentPath`/`profile.domain` |
| `profile-exists-no-domain.json` | Profile 存在但无域名 | `profile.exists: true`，顶层 `domain` 为 `"<not set>"` |
| `profile-missing-explicit.json` | Profile 明确缺失 | `profile.exists: false`，warnings 包含 "Profile not found" |
| `security-missing-secrets.json` | Secrets 缺失 | `security.secretsExists: false`，profile 也缺失 |
| `profile-present-services-missing.json` | Profile 存在但服务缺失 | `profile.exists: true`，services 全 unknown |
| `dashboard-compatible-shape.json` | 向后兼容 | 包含 `profile.currentPath`/`profile.domain` + `profile.exists` |

### 预期摘要 Fixtures

| 文件 | 预期 overall | 预期 profile | 预期 config |
|------|:------------:|:------------:|:-----------:|
| `expected-realistic-summary.json` | healthy | present | present |
| `expected-profile-exists-no-domain-summary.json` | healthy | present | present |
| `expected-profile-missing-explicit-summary.json` | unknown | missing | missing |
| `expected-security-missing-secrets-summary.json` | unknown | missing | missing |
| `expected-profile-present-services-missing-summary.json` | unknown | present | present |
| `expected-dashboard-compatible-summary.json` | healthy | present | present |

---

## 3. 映射合约

### Profile 映射规则

| 条件 | 结果 | Fixture 验证 |
|------|:----:|:------------:|
| `profile.currentPath` 存在且非空 | present | dashboard-compatible |
| `profile.domain` 存在且非空 | present | dashboard-compatible |
| `profile.exists == true` | present | realistic, profile-exists-no-domain, profile-present-services-missing |
| 顶层 `domain` 存在且不为 `"<not set>"` | present | realistic |
| `profile.exists == false` | missing | profile-missing-explicit, security-missing-secrets |
| warnings 包含 "profile not found" | missing | profile-missing-explicit |
| 字段不存在且无安全推断 | unknown | — |

### Config 映射规则

| 条件 | 结果 | Fixture 验证 |
|------|:----:|:------------:|
| profile 为 present | present | realistic, profile-exists-no-domain, dashboard-compatible |
| `configDir` 存在且非空 | 支持 present | realistic, profile-exists-no-domain |
| `security.secretsExists == true` | 支持 present | realistic |
| warnings 包含 "config directory not found" | missing | security-missing-secrets |
| `security.secretsExists == false` 且 profile 缺失 | missing | security-missing-secrets |
| 无安全证据 | unknown | — |

### Security 映射规则

| 条件 | 结果 | Fixture 验证 |
|------|:----:|:------------:|
| `security.secretsMode` 存在 | ok | realistic |
| `security` 为 dict 但无 secretsMode | warning | security-missing-secrets |
| `security` 不是 dict | unknown | — |

---

## 4. 诚实性规则

| 规则 | 验证 |
|------|------|
| missing 保持 missing | ✅ profile-missing-explicit |
| unknown 保持 unknown（无证据） | ✅ v1.9.35 unknown fixture |
| partial/failed 不变为 healthy | ✅ v1.9.35 partial fixture |
| Cloudflare missing 不变为 verified | ✅ v1.9.35 cf_missing fixture |
| services missing → overall 不为 healthy | ✅ profile-present-services-missing |
| 不输出 raw 路径 | ✅ 安全规则检查 |

---

## 5. 安全规则

| 规则 | 验证 |
|------|------|
| 预期摘要无 raw IP（192.0.2.x） | ✅ |
| 预期摘要无 raw domain（example.invalid） | ✅ |
| 预期摘要无 http:// 或 https:// | ✅ |
| 预期摘要无 workers.dev | ✅ |
| 预期摘要无 TOKEN/SECRET/PRIVATE_KEY | ✅ |
| 预期摘要无 fake configDir 路径 | ✅ |
| 预期摘要无 /etc/nanobk | ✅ |
| 预期摘要无完整诊断文本 | ✅ |
| 输入 fixture 仅包含 fake 安全值 | ✅ |
| 无真实 env 读取 | ✅ |
| 无真实 status/doctor 执行 | ✅ |

---

## 6. 测试摘要

`tests/doctor-field-compatibility-fixtures-v1.9.42.py`（294 项）：

| 检查类别 | 项数 | 说明 |
|----------|:----:|------|
| Fixture 存在性 | 12 | 6 输入 + 6 预期 |
| JSON 有效性 | 12 | 所有 JSON 可解析 |
| 预期 schema | ~168 | 6 个预期摘要 × 28 schema 检查 |
| 映射规则 | 18 | 6 场景的关键字段验证 |
| 诚实性规则 | 6 | missing/unknown/partial/failed 不变 |
| 安全规则 | ~102 | 6 预期摘要 × 17 禁止模式 |
| 实现就绪性 | 4 | 无 Bot/Web 导入，合约数据验证 |
| 回归 | 8 | v1.9.35 fixture 仍存在 |

**注意：** 此测试验证合约 fixture 数据，不验证运行时输出。当前 builder 不要求通过这些 fixture。v1.9.43 将更新 builder 测试以消费这些 fixture。

---

## 7. 就绪决策

**A. READY FOR BOT/WEB FIELD COMPATIBILITY MINIMAL FIX AFTER CHATGPT REVIEW**

原因：fixture 已锁定安全的 realistic status shape，下一步可以安全地更新 Bot/Web builder 以消费这些 fixture。

约束：
- 最小实现
- 仅修改 builder 逻辑
- 无 CLI 变更
- 无真实 status 执行
- 无 release/tag

---

## 8. 未变更内容

| 组件 | 状态 |
|------|------|
| Bot（bot/nanobk_bot.py） | 未变更 |
| Web（web/app.py） | 未变更 |
| CLI（bin/nanobk） | 未变更 |
| installer | 未变更 |
| redaction | 未变更 |
| 运行时行为 | 未变更 |
| tag/release | 无 |

---

## 9. 已知限制

| 限制 | 说明 |
|------|------|
| 仅 fixture 测试 | builder 尚未修复 |
| 真实 status shape 仍由 fake fixture 表示 | 基于 v1.9.41 源码审计 |
| Bot/Web builder 逻辑重复 | 未来可提取共享模块 |
| v1.9.43 需要实现 | 本文档仅锁定合约 |

---

## 10. 下一步

**推荐：v1.9.43 — Bot/Web Doctor Summary Field Compatibility Minimal Fix**

需 ChatGPT 审核后实施。
