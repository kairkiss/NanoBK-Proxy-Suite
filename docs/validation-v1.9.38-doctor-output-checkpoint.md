# v1.9.38 — Doctor Output Checkpoint

> 验证类型：Doctor 输出检查点
> 日期：2026-06-05
> 基线 commit：`d8b1daaff6c9dff20ef3ca9b8eee77830c78e3fe`
> 基线信息：`feat: add web doctor summary`

---

## 1. 本轮目标与结论

**v1.9.38 是检查点/验证任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无 CLI 行为变更
- ✅ 无部署逻辑变更
- ✅ 未执行真实 doctor
- ✅ 无 tag/release
- ✅ 目的是验证 v1.9.36/v1.9.37 后 Bot/Web Doctor Summary 一致性和安全性

**结论：Bot/Web Doctor Summary 实现一致、安全、合约对齐、高级模式感知，未绕过 redaction 或向新手暴露完整技术诊断。**

---

## 2. 当前 Doctor 输出架构

### Bot

| 特性 | 说明 |
|------|------|
| 默认行为 | `/doctor` 显示安全新手摘要 |
| 数据源 | `nanobk --json status` 结构化 JSON |
| 高级 OFF | 调用 `--json status`，构建摘要，不调用 `nanobk doctor` |
| 高级 ON | 先显示摘要，再附加脱敏完整诊断（带警告） |
| 完整诊断 | 使用 `safe_output()` 脱敏 |
| i18n | zh/en 标签 |
| 合约 | 符合 v1.9.35 schema |

### Web

| 特性 | 说明 |
|------|------|
| 默认行为 | `/doctor` 显示安全新手摘要卡片 |
| 数据源 | `nanobk --json status` 结构化 JSON |
| 高级 OFF | 调用 `--json status`，构建摘要，不调用 `nanobk doctor` |
| 高级 ON | 先显示摘要卡片，再在折叠 `<details>` 中渲染脱敏完整诊断（带警告） |
| 完整诊断 | 使用 `safe_output()` 脱敏 |
| i18n | zh/en 标签 |
| 合约 | 符合 v1.9.35 schema |
| /api/status | 未变更 |

### 共享

| 特性 | 说明 |
|------|------|
| Redaction | 未变更 |
| CLI | 未变更 |
| installer/doctor.sh | 未变更 |
| Production status wrapper | 未实现 |
| Dirty VPS status wrapping | 未实现 |
| Raw subscription delivery | 未实现 |

---

## 3. Bot 检查点

| 检查项 | 结果 |
|--------|------|
| /doctor 保持 owner-only | ✅ |
| 使用 `run_nanobk(config, ["--json", "status"])` 构建摘要 | ✅ |
| 高级 OFF 不调用 `run_nanobk(config, ["doctor"])` | ✅ |
| 高级 ON 仅在门控后调用完整 doctor | ✅ |
| 完整输出有警告 | ✅ |
| 完整输出使用 `safe_output()` | ✅ |
| 摘要 schema 匹配 v1.9.35 | ✅ |
| Unknown/failed/missing/partial 保持诚实 | ✅ |
| i18n 键存在（zh/en） | ✅ |
| 摘要中无原始 IP/domain/URL/token/private key | ✅ |
| /status_json、高级模式、rotate 未变更 | ✅ |

---

## 4. Web 检查点

| 检查项 | 结果 |
|--------|------|
| /doctor 保持 login-required | ✅ |
| POST 保持 CSRF 保护 | ✅ |
| 使用 `run_nanobk(config, ["--json", "status"])` 构建摘要 | ✅ |
| 高级 OFF 不调用 `run_nanobk(config, ["doctor"])` | ✅ |
| 高级 ON 仅在门控后调用完整 doctor | ✅ |
| 完整输出有警告 | ✅ |
| 完整输出使用 `safe_output()` | ✅ |
| 完整输出在折叠 `<details>` 中 | ✅ |
| 摘要 schema 匹配 v1.9.35 | ✅ |
| Unknown/failed/missing/partial 保持诚实 | ✅ |
| i18n 键存在（zh/en） | ✅ |
| 摘要中无原始 IP/domain/URL/token/private key | ✅ |
| /api/status、Raw JSON 门控、高级模式、rotate 未变更 | ✅ |

---

## 5. 一致性矩阵

| 边界/能力 | Bot v1.9.36 | Web v1.9.37 | 测试覆盖 | 剩余风险 |
|-----------|:-----------:|:-----------:|:--------:|:--------:|
| 合约 schema | ✅ | ✅ | 合约测试 + checkpoint | 无 |
| 摘要数据源 | `--json status` | `--json status` | 源码检查 | 无 |
| 高级 OFF 行为 | 仅摘要 | 仅摘要 | 源码检查 + checkpoint | 无 |
| 高级 ON 行为 | 摘要 + 完整诊断 | 摘要 + 完整诊断 | 源码检查 + checkpoint | 无 |
| 完整诊断警告 | ✅ | ✅ | 源码检查 + checkpoint | 无 |
| 完整诊断 redaction | `safe_output()` | `safe_output()` | 源码检查 | 无 |
| 完整诊断默认可见性 | 高级模式门控 | 高级模式门控 + 折叠 | 源码检查 + checkpoint | 无 |
| Unknown 处理 | 保持 unknown | 保持 unknown | fixture 测试 | 无 |
| Failed 处理 | 保持 failed | 保持 failed | fixture 测试 | 无 |
| Missing config 处理 | 不变为 healthy | 不变为 healthy | fixture 测试 | 无 |
| Partial services 处理 | 保持 partial | 保持 partial | fixture 测试 | 无 |
| Cloudflare missing 处理 | 不变为 verified | 不变为 verified | fixture 测试 | 无 |
| i18n 标签 | zh/en | zh/en | i18n 测试 + checkpoint | 无 |
| 机器状态值稳定 | ✅ | ✅ | checkpoint | 无 |
| 无原始 IP/domain/URL | ✅ | ✅ | checkpoint | 无 |
| 无 token/private key | ✅ | ✅ | checkpoint | 无 |
| 无直接 env 读取 | ✅ | ✅ | 源码检查 | 无 |
| 无直接写入 | ✅ | ✅ | 源码检查 | 无 |
| /status_json 未变更 | ✅ | — | Bot 测试 | 无 |
| /api/status 未变更 | — | ✅ | Web 测试 | 无 |
| Raw JSON 门控未变更 | ✅ | ✅ | 门控测试 | 无 |
| 高级模式未变更 | ✅ | ✅ | 高级模式测试 | 无 |
| rotate 未变更 | ✅ | ✅ | 源码检查 | 无 |
| 无 CLI/installer 变更 | ✅ | ✅ | 源码检查 | 无 |
| 无 tag/release | ✅ | ✅ | Git 检查 | 无 |

---

## 6. 安全决策

**Doctor Summary 对新手 Bot/Web 控制面 UX 是安全的。**

但 Doctor Summary 不构成以下许可：

- ❌ 泄漏原始 IP/domain/URL
- ❌ 泄漏 workers.dev
- ❌ 泄漏 subscription URL/path
- ❌ 泄漏 token/secret/private key
- ❌ 读取 env 文件
- ❌ 改变 CLI doctor 行为
- ❌ 实现 doctor --json
- ❌ 运行 production status wrapper
- ❌ 运行 dirty VPS status wrapping
- ❌ 交付 subscription
- ❌ 运行 repair/restart/Cloudflare mutation
- ❌ tag/release

---

## 7. 就绪决策

**A. READY FOR LIMITED REAL BOT/WEB DOCTOR SMOKE RETEST PLANNING**

原因：v1.9.36/v1.9.37 改变了实际的 Bot/Web /doctor 行为。在开始 systemd/Web production runner 工作之前，应在真实 Bot/Web session 中验证新的 Doctor Summary 行为，不运行部署或 Cloudflare 变更。

约束：
- 控制面仅限
- 无部署
- 无 Cloudflare 变更
- 无 rotate 执行
- 无 tag/release

---

## 8. 可能的下一步选项

| 选项 | 内容 | 推荐 |
|------|------|------|
| **选项 1** | v1.9.39 — 有限真实 Bot/Web Doctor 冒烟重测计划 | ✅ 推荐 |
| 选项 2 | v1.9.39 — Bot/Web systemd 安装规划 | 次选 |
| 选项 3 | v1.9.39 — Web Production Runner 规划 | 次选 |
| 选项 4 | v1.9.39 — Fingerprint Redaction 策略规划 | 可选 |

**推荐选项 1：v1.9.39 — 有限真实 Bot/Web Doctor 冒烟重测计划**

原因：v1.9.36/v1.9.37 改变了实际的 Bot/Web /doctor 行为。在开始 systemd/Web production runner 工作之前，应验证新的 Doctor Summary 行为。

---

## 9. 真实冒烟重测定位

| 约束 | 说明 |
|------|------|
| 不运行完整真实 VPS 部署 | ✅ |
| 不运行 Cloudflare 变更 | ✅ |
| 不运行真实 rotate | ✅ |
| 重测应仅限控制面 | ✅ |
| 重测重点 | Bot /doctor 高级 OFF 摘要、Bot /doctor 高级 ON 摘要 + 脱敏完整诊断、Web /doctor 高级 OFF 摘要卡片、Web /doctor 高级 ON 折叠完整诊断 |
| 安全检查 | 无原始 IP/domain/URL/token/workers.dev/subscription URL/private key |
| 现有门控 | status/status_json/advanced/rotate 仍正常 |
| 用户报告 | 不粘贴包含敏感数据的完整输出 |
| 报告格式 | PASS/FAIL + 仅脱敏注释 |

---

## 10. 剩余阻塞项

| 阻塞项 | 状态 |
|--------|------|
| 真实 Doctor 冒烟重测 | 待规划 |
| Bot/Web systemd 产品化 | 待规划 |
| Web production runner | 待规划 |
| CLI 版本显示策略 | 待规划 |
| Fingerprint redaction 策略 | 待规划 |
| Raw subscription 交付 | 阻塞 |
| Subscription QR 交付 | 阻塞 |
| Production status wrapper | 阻塞 |
| Dirty VPS status wrapping | 阻塞 |
| Operation-log full rollout | 阻塞 |
| 直接 Bot/Web repair/restart | 阻塞 |
| Cloudflare mutating operations | 阻塞 |
| Full clean VPS release-candidate regression | 阻塞 |
| Release/tag | 阻塞 |

---

## 11. 测试运行

| 测试 | 结果 |
|------|------|
| `python3 tests/doctor-summary-contract-v1.9.35.py` | ✅ 352 passed |
| `python3 tests/bot-doctor-summary-v1.9.36.py` | ✅ 163 passed |
| `python3 tests/web-doctor-summary-v1.9.37.py` | ✅ 164 passed |
| `python3 tests/doctor-output-checkpoint-v1.9.38.py` | ✅ 208 passed |
| `python3 tests/bot-i18n-minimal-v1.9.30.py` | ✅ 116 passed |
| `python3 tests/web-i18n-minimal-v1.9.31.py` | ✅ 123 passed |
| `python3 tests/i18n-checkpoint-v1.9.32.py` | ✅ 167 passed |
| `python3 tests/bot-advanced-mode-v1.9.16.py` | ✅ 65 passed |
| `python3 tests/web-advanced-mode-v1.9.17.py` | ✅ 64 passed |
| `python3 tests/bot-status-json-soft-gate-v1.9.20.py` | ✅ 50 passed |
| `python3 tests/web-raw-json-soft-gate-v1.9.21.py` | ✅ 48 passed |
| `python3 tests/raw-json-gating-checkpoint-v1.9.22.py` | ✅ 58 passed |
| `bash tests/bot-cli-mock.sh` | ✅ All passed |
| `bash tests/web-panel-mock.sh` | ✅ All passed |
| `python3 bot/nanobk_bot.py --self-test` | ✅ 180 passed |
| `python3 web/app.py --self-test` | ✅ 106 passed |

---

## 12. 已知限制

| 限制 | 说明 |
|------|------|
| 无真实 Bot/Web session 重测 | Doctor Summary 后未重测 |
| 未执行真实 doctor | 本检查点未执行 |
| 完整诊断源仍为文本 | doctor.sh 文本输出 |
| CLI doctor --json 未实现 | 独立任务 |
| Bot/Web 当前重复摘要构建逻辑 | 未来可提取共享模块 |
| Production status wrapper 仍阻塞 | 未批准 |
| Raw subscription delivery 仍阻塞 | 未批准 |

---

## 13. Guardrails

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
| 9 | 无 production status wrapper | ✅ |
| 10 | 无 dirty VPS status wrapping | ✅ |
| 11 | 无 operation-log full rollout | ✅ |
| 12 | 无 raw subscription delivery | ✅ |
| 13 | 无 tag/release | ✅ |
