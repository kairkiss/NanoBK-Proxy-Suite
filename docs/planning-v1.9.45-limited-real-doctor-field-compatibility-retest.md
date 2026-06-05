# v1.9.45 — Limited Real Doctor Field Compatibility Retest Plan

> 规划类型：有限真实 Doctor 字段兼容性重测计划
> 日期：2026-06-05
> 基线 commit：`5e55a85e1155b70ea56bb7a156fa5123256fcb1b`
> 基线信息：`test: add v1.9.44 doctor field compatibility checkpoint`

---

## 1. 本轮目标与结论

**v1.9.45 是规划/文档任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无 CLI 行为变更
- ✅ 无部署逻辑变更
- ✅ Claude Code 未执行真实 status
- ✅ Claude Code 未执行真实 doctor
- ✅ 无 tag/release
- ✅ 目的是规划用户手动重测 T15-P2-001 修复

**结论：定义安全的控制面仅限真实重测计划，确认 v1.9.43 字段兼容性修复在真实 Bot/Web session 中生效。用户手动执行，Claude Code 仅编写计划。**

---

## 2. 为什么需要这次复测

| 原因 | 说明 |
|------|------|
| T15 发现 Profile/Config unknown | Doctor Summary 显示 unknown，Dashboard/Status 显示 present |
| v1.9.43 修复了 builder 兼容性 | 支持 `profile.exists`、`configDir`、`security.secretsExists` |
| v1.9.44 源码/fixture 级别验证通过 | 242 项检查全部通过 |
| 真实 UI 应在推进前确认 | 避免在 fingerprint/i18n/systemd 工作中发现回归 |
| 这不是完整部署回归 | 仅控制面 |

---

## 3. 测试范围

### 允许

- 现有脏测试 VPS
- 现有部署
- Bot /doctor 高级 OFF/ON
- Web /doctor 高级 OFF/ON
- 快速 /status 健全性检查
- 快速 /status_json 门控健全性检查
- Web Raw JSON 门控健全性检查
- 四协议服务状态观察（不修改）

### 不允许

- 完整重新部署
- Cloudflare 变更
- 真实 rotate
- Repair/restart
- Production status wrapper
- Dirty VPS status wrapping
- Raw subscription delivery
- 读取 env 文件
- 粘贴完整原始诊断

---

## 4. 前置条件

| 条件 | 说明 |
|------|------|
| 仓库更新至 v1.9.44 或更高 | 确认 `git log -1` 显示正确 commit |
| 包含 v1.9.43 fix commit | 确保 builder 已修复 |
| Bot/Web env 文件存在且 chmod 600 | 不 cat 它们 |
| Bot token 有效且不粘贴 | 安全使用 |
| Web token 仅本地使用且不粘贴 | 安全使用 |
| Web 仅本地或 SSH 隧道 | 不公开暴露 |
| 四协议服务观察但不修改 | 保持现状 |
| 用户准备脱敏报告模板 | 参见第 8 节 |

---

## 5. Bot 重测清单

| # | 操作 | 预期结果 | PASS/FAIL |
|---|------|----------|-----------|
| 1 | 确认 Bot 正在运行 | Bot 进程活跃 | |
| 2 | 发送 `/advanced off` | 高级模式禁用 | |
| 3 | 发送 `/doctor` | 显示 Doctor Summary | |
| 4 | 验证高级 OFF 仅摘要 | 无完整技术输出 | |
| 5 | 验证 Profile 现在显示 present | 如真实证据存在 | |
| 6 | 验证 Config 现在显示 present | 如真实证据存在 | |
| 7 | 验证 Services 仍 active | 四协议状态正确 | |
| 8 | 验证 Cloudflare/Subscription/Security 仍诚实 | 无伪造成功 | |
| 9 | 验证无 raw config path/IP/domain/URL/token/private key | 安全 | |
| 10 | 发送 `/advanced on` | 高级模式启用 | |
| 11 | 发送 `/doctor` | 显示摘要 + 完整诊断 | |
| 12 | 验证摘要先出现 | 摘要在完整诊断之前 | |
| 13 | 验证完整诊断警告出现 | ⚠️ 高级诊断警告 | |
| 14 | 验证完整诊断已脱敏 | 无原始 token/private key/URL | |
| 15 | 发送 `/advanced off` | 高级模式禁用 | |
| 16 | 发送 `/status_json` | 门控行为验证 | |
| 17 | 验证门控仍阻止 JSON（高级 OFF） | 仅引导 | |
| 18 | 确认 Bot 仍正常运行 | 进程和连接正常 | |

### 预期 PASS 标准

- 步骤 5-6：Profile/Config 显示 present（非 unknown）
- 步骤 9：无安全泄露
- 步骤 14：完整诊断脱敏
- 步骤 17：门控正常

---

## 6. Web 重测清单

| # | 操作 | 预期结果 | PASS/FAIL |
|---|------|----------|-----------|
| 1 | 安全启动 Web（仅本地或 SSH 隧道） | Web 可访问 | |
| 2 | 登录 | 成功登录 | |
| 3 | 访问 Dashboard 和 Status | 安全卡片正常 | |
| 4 | 验证 Dashboard/Status 仍显示安全卡片 | 无原始值 | |
| 5 | 禁用高级模式 | 高级模式禁用 | |
| 6 | 访问 Doctor 页面 | Doctor 页面加载 | |
| 7 | 运行 Doctor | 显示摘要卡片 | |
| 8 | 验证高级 OFF 仅摘要卡片 | 无完整技术转储 | |
| 9 | 验证 Profile 现在显示 present | 如真实证据存在 | |
| 10 | 验证 Config 现在显示 present | 如真实证据存在 | |
| 11 | 验证无 raw config path/IP/domain/URL/token/private key | 安全 | |
| 12 | 启用高级模式 | 高级模式启用 | |
| 13 | 再次运行 Doctor | 显示摘要 + 完整诊断 | |
| 14 | 验证摘要先出现 | 摘要在完整诊断之前 | |
| 15 | 验证完整诊断警告出现 | ⚠️ 高级诊断警告 | |
| 16 | 验证完整诊断已脱敏 | 无原始 token/private key/URL | |
| 17 | 禁用高级模式或登出 | 高级模式禁用 | |
| 18 | 验证 Raw JSON 门控仍正常 | 行为不变 | |
| 19 | 确认 Web 仍仅本地 | 不公开暴露 | |

### 预期 PASS 标准

- 步骤 9-10：Profile/Config 显示 present（非 unknown）
- 步骤 11：无安全泄露
- 步骤 16：完整诊断脱敏
- 步骤 18：门控正常

---

## 7. 泄漏清单

### 禁止观察项

| 类别 | 严重度 | 说明 |
|------|:------:|------|
| 原始 configDir 路径 | P1 | 如出现在 Doctor Summary 中 |
| 原始 IPv4 | P1 | 如出现在 Doctor Summary 中 |
| 原始 IPv6 | P1 | 如出现在 Doctor Summary 中 |
| 原始 domain | P1 | 如出现在 Doctor Summary 中 |
| 原始 URL | P1 | 如出现在 Doctor Summary 中 |
| workers.dev | P1 | 如出现在任何输出中 |
| subscription URL/path | P0 | 如出现在任何输出中 |
| Bot token | P0 | 如出现在任何输出中 |
| Web token | P0 | 如出现在任何输出中 |
| Cloudflare/Admin token | P0 | 如出现在任何输出中 |
| Reality private key | P0 | 如出现在任何输出中 |
| 原始 env 内容 | P0 | 如出现在任何输出中 |
| Private key 文本 | P0 | 如出现在任何输出中 |
| Profile/Config 仍 unknown（Dashboard/Status 显示 present） | P1 | 修复未生效 |
| 完整诊断在高级 OFF 时可见 | P1 | 门控失效 |
| /doctor 改变服务状态 | P1 | 破坏性命令 |

---

## 8. 预期报告模板

```
# Doctor Field Compatibility Retest Report

## 环境摘要

- OS: [发行版，不写真实 IP]
- 测试方式: 本地 / SSH 隧道
- Bot token 状态: 有效 / 已重新生成
- Web 访问: 仅本地
- 仓库 commit: [commit hash]
- 四协议服务: HY2/TUIC/REALITY/TROJAN [状态]

## Bot Doctor 字段兼容性结果

| # | 结果 | 备注 |
|---|------|------|
| 1 | PASS/FAIL | |
| ... | ... | |
| 18 | PASS/FAIL | |

## Web Doctor 字段兼容性结果

| # | 结果 | 备注 |
|---|------|------|
| 1 | PASS/FAIL | |
| ... | ... | |
| 19 | PASS/FAIL | |

## 泄漏清单结果

- Profile/Config 现在显示 present: 是/否
- 原始 configDir 路径出现: 是/否
- 原始 IP/domain/URL 出现: 是/否
- 原始 token/private key 出现: 是/否
- 高级 OFF 时完整诊断可见: 是/否
- 其他: [描述]

## 现有门控健全性

- Bot /status: PASS/FAIL
- Bot /status_json 门控: PASS/FAIL
- Web Dashboard/Status: PASS/FAIL
- Web Raw JSON 门控: PASS/FAIL
- 四协议服务: 仍活跃 / 有变化

## 发现的问题

- [问题描述，不包含原始值]

## 最终判定

- [ ] PASS
- [ ] PASS WITH POLISH
- [ ] BLOCKED

## 给 ChatGPT 的备注

[脱敏备注]

---

⚠️ 不要粘贴完整 doctor 输出。
⚠️ 不要粘贴 raw JSON body。
⚠️ 不要粘贴 env 内容。
⚠️ 不要粘贴包含原始值的截图。
```

---

## 9. 失败处理

| 情况 | 处理 |
|------|------|
| Profile/Config 仍 unknown | 报告 P1 或 P2（取决于真实证据） |
| 原始 secret 出现 | 停止测试，撤销/重新生成 token，仅报告类别 |
| 完整诊断在高级 OFF 时可见 | 停止，报告 P1 |
| 服务状态意外变更 | 停止，不修复，记录 |
| Bot/Web 是旧进程 | 安全重启并重测，报告为测试问题 |

---

## 10. 暂不测试内容

| 内容 | 说明 |
|------|------|
| 完整干净 VPS 部署 | 未批准 |
| Cloudflare 变更 | 未批准 |
| 真实 rotate | 未批准 |
| Repair/restart | 未批准 |
| systemd 安装 | 未批准 |
| Web production runner | 未批准 |
| Subscription delivery/QR | 未批准 |
| Production status wrapper | 未批准 |
| Dirty VPS status wrapping | 未批准 |
| Operation-log full rollout | 未批准 |
| Tag/release | 未批准 |

---

## 11. 就绪决策

**A. READY FOR USER-RUN LIMITED REAL DOCTOR FIELD COMPATIBILITY RETEST AFTER CHATGPT REVIEW**

约束：
- 仅用户手动执行
- 仅控制面
- 仅脱敏报告
- 无部署
- 无 Cloudflare 变更
- 无真实 rotate
- 无 tag/release

---

## 12. 测试后决策树

| 结果 | 下一步 |
|------|--------|
| **PASS** | 进入 v1.9.46 规划：Fingerprint Redaction 策略或语言传播规划 |
| **PASS WITH POLISH** | 记录验证并规划针对性打磨 |
| **BLOCKED** | 停止 v1.9 功能工作，先修复阻塞项 |

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
| 9 | 无真实 status 执行（Claude Code） | ✅ |
| 10 | 无真实 doctor 执行（Claude Code） | ✅ |
| 11 | 无 production status wrapper | ✅ |
| 12 | 无 dirty VPS status wrapping | ✅ |
| 13 | 无 operation-log full rollout | ✅ |
| 14 | 无 raw subscription delivery | ✅ |
| 15 | 无 tag/release | ✅ |
