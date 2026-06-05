# v1.9.39 — Limited Real Bot/Web Doctor Smoke Retest Plan

> 规划类型：有限真实 Bot/Web Doctor 冒烟重测计划
> 日期：2026-06-05
> 基线 commit：`a04ebc6496d3a29e0d01d7e228d3ff98495c323f`
> 基线信息：`test: add v1.9.38 doctor output checkpoint`

---

## 1. 本轮目标与结论

**v1.9.39 是规划/文档任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无 CLI 行为变更
- ✅ 无部署逻辑变更
- ✅ Claude Code 未执行真实 doctor
- ✅ 无 tag/release
- ✅ 目的是规划安全的用户手动 Bot/Web Doctor 冒烟重测

**结论：定义安全的控制面仅限真实重测计划，覆盖 Bot/Web /doctor 新摘要行为验证。用户手动执行，Claude Code 仅编写计划。**

---

## 2. 为什么需要这次重测

| 原因 | 说明 |
|------|------|
| v1.9.28 已证明 Bot/Web 真实控制面可用 | PASS WITH POLISH |
| v1.9.36 和 v1.9.37 改变了实际 /doctor 行为 | 从原始技术输出变为安全摘要 |
| /doctor 是用户面向且诊断敏感的 | 需要验证新手体验 |
| 需要确认摘要行为在真实 Bot/Web session 中正确 | 避免在 systemd/Web runner 工作中发现回归 |
| 这不是完整部署回归 | 仅控制面 |

---

## 3. 测试范围

### 允许

- 仅限控制面 Bot/Web 重测
- 仅限现有测试 VPS
- 仅限现有部署
- Bot /doctor
- Web /doctor
- 现有 status/status_json/advanced/Raw JSON 门控健全性检查
- Web /api/status 脱敏健全性检查
- 可选 Web rotate 页面 dry-run 可见性检查（仅在已安全时）

### 不允许

- 完整 VPS 重新部署
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
| 仓库更新至 v1.9.38 或更高 | 确认 `git log -1` 显示正确 commit |
| Bot token 已重新生成 | 如果之前 token 暴露过 |
| `/usr/local/bin/nanobk` 指向当前仓库 | 如需要 |
| 现有 Bot/Web env 文件存在且 chmod 600 | 不 cat 它们 |
| 现有四协议服务不应被有意修改 | 保持现状 |
| Web 应仅本地运行或通过 SSH 隧道 | 不公开暴露 |
| 用户应准备脱敏笔记模板 | 参见第 9 节 |

---

## 5. 安全报告规则

### 可以报告

- PASS/FAIL
- 脱敏注释
- 仅在模糊 IP/domain/token/URL 后的截图
- 通用状态词：healthy/partial/failed/unknown
- 是否出现了原始值（不复制它们）

### 不可以报告

- 原始 Bot token
- 原始 Web token
- 原始 IP/IPv6/domain
- workers.dev
- Subscription URL/path
- 完整 Raw JSON body
- 完整 doctor 输出
- .env 内容
- Reality private key
- Cloudflare/Admin token
- Private key/fingerprint（如不确定）

---

## 6. Bot Doctor 重测清单

### 步骤

| # | 操作 | 预期结果 | PASS/FAIL |
|---|------|----------|-----------|
| 1 | 确认 Bot 正在运行 | Bot 进程活跃，Telegram 连接正常 | |
| 2 | 发送 `/start` | 显示 Control Center 菜单 | |
| 3 | 发送 `/status` | 显示安全摘要（无原始 IP/domain） | |
| 4 | 发送 `/advanced status` | 显示高级模式状态（应为 OFF） | |
| 5 | 确保高级模式 OFF | 如果 ON，发送 `/advanced off` | |
| 6 | 发送 `/doctor` | 显示 Doctor Summary | |
| 7 | 验证仅摘要： | | |
| 7a | | 标题/摘要出现 | |
| 7b | | overall/control plane/CLI/profile/config/services/cloudflare/subscription/security/next step 可见 | |
| 7c | | 无完整技术输出 | |
| 7d | | 默认无 OS/kernel/工具路径/配置路径/端口转储 | |
| 7e | | 无原始 IP/domain/URL/token/private key | |
| 7f | | 提示完整诊断仅限高级模式 | |
| 8 | 发送 `/advanced on` | 显示高级模式启用警告 | |
| 9 | 发送 `/doctor` | 显示摘要 + 完整诊断 | |
| 10 | 验证摘要先出现 | 摘要在完整诊断之前 | |
| 11 | 验证完整诊断警告出现 | ⚠️ 高级诊断警告 | |
| 12 | 验证完整诊断已脱敏 | 无原始 IP/domain/URL/token/private key/workers.dev/subscription URL | |
| 13 | **不要粘贴完整诊断到报告中** | — | |
| 14 | 发送 `/advanced off` | 显示高级模式禁用 | |
| 15 | 再次发送 `/doctor` | 仅显示摘要，无完整诊断 | |
| 16 | 确认 `/status_json` 软门控仍正常 | OFF 时不输出 JSON | |
| 17 | 确认 rotate 按钮/命令仍不执行（无确认） | 行为不变 | |
| 18 | 确认 Bot 仍正常运行 | 进程和连接正常 | |

### 预期 PASS 标准

- 步骤 7：仅摘要，无技术细节泄漏
- 步骤 12：完整诊断脱敏
- 步骤 15：高级 OFF 时完整诊断消失
- 步骤 16-17：现有门控不变

---

## 7. Web Doctor 重测清单

### 步骤

| # | 操作 | 预期结果 | PASS/FAIL |
|---|------|----------|-----------|
| 1 | 安全启动 Web（仅本地或 SSH 隧道） | Web 可访问 | |
| 2 | 登录 | 成功登录 | |
| 3 | 访问 Dashboard | 显示安全卡片 | |
| 4 | 访问 Status | 显示安全卡片 + Raw JSON 门控 | |
| 5 | 确认安全卡片和 Raw JSON 门控仍正常 | 行为不变 | |
| 6 | 访问 Doctor 页面（高级 OFF） | 显示 Doctor 页面 | |
| 7 | 运行 Doctor | 显示摘要卡片 | |
| 8 | 验证仅摘要卡片： | | |
| 8a | | overall/control plane/CLI/profile/config/services/cloudflare/subscription/security/next step 可见 | |
| 8b | | 无完整技术输出 | |
| 8c | | 默认无 OS/kernel/工具路径/配置路径/端口转储 | |
| 8d | | 无原始 IP/domain/URL/token/private key | |
| 8e | | 提示完整诊断仅限高级模式 | |
| 9 | 启用 Web 高级模式 | 高级模式启用 | |
| 10 | 再次运行 Doctor | 显示摘要卡片 + 完整诊断 | |
| 11 | 验证摘要卡片先出现 | 摘要在完整诊断之前 | |
| 12 | 验证完整诊断警告出现 | ⚠️ 高级诊断警告 | |
| 13 | 验证完整诊断默认折叠或在 details 中 | 折叠状态 | |
| 14 | 展开 details（仅在安全时），检查脱敏，**不要复制原始输出** | 无原始 IP/domain/URL/token/private key/workers.dev/subscription URL | |
| 15 | 禁用高级模式或登出 | 高级模式禁用 | |
| 16 | 再次运行/访问 Doctor | 完整诊断隐藏 | |
| 17 | 确认 `/api/status` 仍脱敏 | 返回脱敏 JSON | |
| 18 | 确认 rotate dry-run/confirm 页面不变（如检查） | 行为不变 | |
| 19 | 确认 Web 仍仅本地 | 不公开暴露 | |

### 预期 PASS 标准

- 步骤 8：仅摘要卡片，无技术细节泄漏
- 步骤 14：完整诊断脱敏且折叠
- 步骤 16：高级 OFF 时完整诊断隐藏
- 步骤 17：/api/status 仍脱敏

---

## 8. 泄漏清单

### 禁止观察项

| 类别 | 严重度 | 说明 |
|------|:------:|------|
| 原始 IPv4 | P1 | 如出现在新手摘要中 |
| 原始 IPv6 | P1 | 如出现在新手摘要中 |
| 原始 domain | P1 | 如出现在新手摘要中 |
| 原始 URL | P1 | 如出现在新手摘要中 |
| workers.dev | P1 | 如出现在任何输出中 |
| subscription URL/path | P0 | 如出现在任何输出中 |
| Bot token | P0 | 如出现在任何输出中 |
| Web token | P0 | 如出现在任何输出中 |
| Cloudflare/Admin token | P0 | 如出现在任何输出中 |
| Reality private key | P0 | 如出现在任何输出中 |
| Private key 文本 | P0 | 如出现在任何输出中 |
| 原始 env 内容 | P0 | 如出现在任何输出中 |
| 原始 fingerprint（如产品决策说隐藏） | P2 | 如不确定 |
| 高级 OFF 时显示完整诊断 | P1 | 门控失效 |
| /doctor 运行破坏性命令 | P1 | 服务状态变更 |
| 摘要措辞混乱 | P2 | UX 问题 |
| 高级完整输出过长或丑陋但已脱敏 | P2 | UX 问题 |
| i18n 措辞问题 | P2 | 本地化问题 |
| 测试者使用错误端点/旧仓库 | 测试问题 | 需重测 |

---

## 9. 预期报告模板

```
# Doctor Smoke Retest Report

## 环境摘要

- OS: [发行版，不写真实 IP]
- 测试方式: 本地 / SSH 隧道
- Bot token 状态: 已重新生成 / 未暴露
- Web 访问: 仅本地

## 仓库 commit 确认

- git log -1: [commit hash]

## Bot Doctor 清单结果

| # | 结果 | 备注 |
|---|------|------|
| 1 | PASS/FAIL | |
| 2 | PASS/FAIL | |
| ... | ... | |
| 18 | PASS/FAIL | |

## Web Doctor 清单结果

| # | 结果 | 备注 |
|---|------|------|
| 1 | PASS/FAIL | |
| 2 | PASS/FAIL | |
| ... | ... | |
| 19 | PASS/FAIL | |

## 泄漏清单结果

- 原始 IP/domain/URL 出现在摘要中: 是/否
- 原始 token/private key 出现: 是/否
- 高级 OFF 时完整诊断可见: 是/否
- 其他: [描述]

## 现有门控健全性

- Bot /status: PASS/FAIL
- Bot /status_json 软门控: PASS/FAIL
- Bot /advanced on/off: PASS/FAIL
- Web Dashboard 卡片: PASS/FAIL
- Web Raw JSON 门控: PASS/FAIL
- Web 高级切换: PASS/FAIL
- Web /api/status: PASS/FAIL
- Rotate 行为: PASS/FAIL/未检查

## 发现的问题

- [问题描述，不包含原始值]

## 最终判定

- [ ] PASS
- [ ] PASS WITH POLISH
- [ ] BLOCKED

## 给 ChatGPT 的备注

[脱敏备注]

---

⚠️ 不要粘贴原始 doctor 输出。
⚠️ 不要粘贴 env 内容。
⚠️ 不要粘贴包含原始值的截图。
```

---

## 10. 失败处理

### 如果出现原始密钥

1. 停止测试
2. 不要粘贴它
3. 撤销/重新生成受影响的 token（如适用）
4. 仅报告类别

### 如果 Bot/Web 崩溃

1. 报告脱敏症状
2. 不要粘贴 env/日志密钥
3. 仅分享脱敏的最后一行（如需要）

### 如果高级 OFF 时显示完整诊断

1. 标记 P1
2. 在审查前不要继续高级完整输出测试

### 如果部署/协议服务意外变更

1. 停止
2. 记录服务状态变更
3. 除非后续明确批准，否则不要运行 repair/restart

---

## 11. 暂不测试内容

| 内容 | 说明 |
|------|------|
| 完整干净 VPS 部署 | 未批准 |
| Cloudflare 部署/验证/变更 | 未批准 |
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

## 12. 就绪决策

**A. READY FOR USER-RUN LIMITED REAL BOT/WEB DOCTOR SMOKE RETEST AFTER CHATGPT REVIEW**

约束：
- 仅用户手动执行
- 仅控制面
- 仅脱敏报告
- 无部署
- 无 Cloudflare 变更
- 无真实 rotate
- 无 tag/release

---

## 13. 测试后决策树

| 结果 | 下一步 |
|------|--------|
| **PASS** | 进入 v1.9.40 规划：Bot/Web systemd 产品化或 Web production runner 规划 |
| **PASS WITH POLISH** | 记录验证并规划针对性打磨 |
| **BLOCKED** | 停止 v1.9 功能工作，先修复阻塞项 |

---

## 14. Guardrails

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
