# v1.9.27 — Limited Real Bot/Web Smoke Test Plan

> 规划类型：有限真实 Bot/Web 冒烟测试规划
> 日期：2026-06-05
> 基线 commit：`b34f44923fa6ccf008c894c8bf392a384d4f3716`
> 基线信息：`test: add v1.9.26 bot control center checkpoint`

---

## 1. 本轮目标与结论

**v1.9.27 是规划/文档任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时变更
- ✅ 无部署逻辑变更
- ✅ 无 tag/release
- ✅ 目的是规划有限真实 Bot/Web 冒烟测试，供用户后续手动执行

**结论：定义安全的、分步的、控制面-only 的真实 Bot/Web 冒烟测试计划。用户可在 ChatGPT 审核后手动执行，仅报告脱敏 PASS/FAIL 结果。**

---

## 2. 为什么现在只规划有限冒烟测试

| 理由 | 说明 |
|------|------|
| v1.9 变更范围有限 | 主要变更了 Bot/Web UI、redaction、诊断可见性和测试 |
| 核心未变更 | `installer/install.sh`、VPS 模板、Worker 核心、rotate sync、部署逻辑未变更 |
| 不需要完整回归 | 完整真实 VPS 部署回归应在部署/status/Cloudflare/rotate 核心变更或发布候选时进行 |
| 有限冒烟有价值 | 可验证真实 session UX、控制面安全、redaction 效果 |
| 不应变更生产状态 | 冒烟测试不应修改生产环境 |
| 不应暴露 secrets | 冒烟测试不应要求用户粘贴敏感信息 |

---

## 3. 测试范围

### 范围内

| 项目 | 说明 |
|------|------|
| Telegram Bot 真实 session | Bot 启动、菜单、命令 |
| Web Panel 真实浏览器 session | 登录、Dashboard、Status |
| owner-only 行为 | 非 owner 拒绝 |
| 安全状态摘要 | /status 安全卡片 |
| 控制中心菜单 | InlineKeyboardButton |
| 高级模式 | /advanced on/off/status |
| Raw JSON 门控 | /status_json OFF/ON |
| redaction | 地址类脱敏 |
| Web /api/status | redacted JSON |
| rotate 仅引导 | 不执行 rotate |
| 无 raw URL 显示 | 安全 |

### 范围外

| 项目 | 说明 |
|------|------|
| 重装 VPS | 不在范围内 |
| 部署协议 | 不在范围内 |
| Cloudflare Worker 变更 | 不在范围内 |
| Rotate 执行 | 不在范围内 |
| 订阅交付 | 不在范围内 |
| QR 交付 | 不在范围内 |
| Production status wrapper | 不在范围内 |
| Dirty VPS status wrapping | 不在范围内 |
| Repair/restart | 不在范围内 |
| Release/tag | 不在范围内 |

---

## 4. 绝对安全规则给用户

**用户必须遵守以下规则：**

- ❌ 不要粘贴真实 Bot token
- ❌ 不要粘贴 admin token
- ❌ 不要粘贴 Cloudflare token
- ❌ 不要粘贴 env 文件内容
- ❌ 不要粘贴真实 VPS IP 或 IPv6
- ❌ 不要粘贴真实域名
- ❌ 不要粘贴 workers.dev
- ❌ 不要粘贴 subscription URL
- ❌ 不要粘贴 Reality private key
- ❌ 如果分享截图，先脱敏所有地址/token/URL
- ✅ 优先分享 PASS/FAIL 和简短脱敏备注

---

## 5. 测试前准备

**安全预检清单：**

- [ ] 确认仓库在预期 commit
- [ ] 确认 Bot/Web 服务已从先前设置安装
- [ ] 不要重跑 Full Wizard（除非用户明确想重装）
- [ ] 确认测试者拥有 owner Telegram 账号
- [ ] 确认 Web 登录 token/password 在本地可用但不粘贴
- [ ] 确认测试可安全停止
- [ ] 确认不会执行 rotate/repair/restart

**安全检查命令（不包含 env 内容）：**

```bash
git rev-parse HEAD
git status -sb
```

优先使用 UI 级测试。

---

## 6. Bot 冒烟测试清单

| # | 步骤 | 操作 | 预期安全结果 | 不要分享 | PASS/FAIL |
|---|------|------|-------------|----------|-----------|
| 1 | 打开 Bot 聊天 | 启动 Telegram Bot | Bot 响应 | Bot token | |
| 2 | 发送 /start | 输入 /start | 显示 NanoBK Control Center 菜单 + 按钮 | — | |
| 3 | 验证菜单按钮 | 查看按钮 | 📊🧭🩺🔐🔄🌐❓ 按钮存在 | — | |
| 4 | 发送 /help | 输入 /help | 显示帮助文本，/status_json 在高级诊断区 | — | |
| 5 | 发送 /status | 输入 /status | 显示安全摘要（Overall/VPS/Protocols/CF/Subscription） | 无 raw IP/domain | |
| 6 | 按 Status Summary | 点击 📊 按钮 | 显示安全摘要 | 无 raw IP/domain | |
| 7 | 按 Recovery Help | 点击 🧭 按钮 | 显示恢复引导（/status、/doctor、SSH） | 无 raw URL | |
| 8 | 按 Diagnostics | 点击 🩺 按钮 | 显示诊断引导（/doctor、/advanced on、/status_json） | — | |
| 9 | 按 Advanced Mode | 点击 🔐 按钮 | 显示高级模式状态 + 命令引导 | — | |
| 10 | /advanced status | 输入 /advanced status | 显示"disabled" | — | |
| 11 | /status_json OFF | 输入 /status_json | 显示"not enabled"引导，不输出 JSON | — | |
| 12 | /advanced on | 输入 /advanced on | 显示启用警告（15 分钟过期） | — | |
| 13 | /status_json ON | 输入 /status_json | 显示警告 + redacted JSON | 无 raw token/IP/domain | |
| 14 | /advanced off | 输入 /advanced off | 显示"disabled" | — | |
| 15 | /status_json 再次 | 输入 /status_json | 显示"not enabled"引导 | — | |
| 16 | 按 Rotate Secrets | 点击 🔄 按钮 | 显示 rotate 命令引导，不执行 rotate | — | |
| 17 | 确认 rotate 仅引导 | 查看响应 | 列出 /rotate_* 命令，需确认 | — | |
| 18 | 按 Web Panel | 点击 🌐 按钮 | 显示 Web Panel 引导，无 raw URL | 无 raw URL | |
| 19 | 确认无 raw URL | 查看响应 | "Refer to your NanoBK configuration" | 无 workers.dev | |
| 20 | 非 owner 测试（可选） | 第二账号发 /start | 显示"Unauthorized" | — | |

**预期：无 raw IP/domain/token/workers.dev/subscription URL/private key。**

---

## 7. Web 冒烟测试清单

| # | 步骤 | 操作 | 预期安全结果 | 不要分享 | PASS/FAIL |
|---|------|------|-------------|----------|-----------|
| 1 | 打开 Web Panel | 浏览器访问 | 显示登录页 | 无 token | |
| 2 | 登录 | 输入 token | 进入 Dashboard | — | |
| 3 | 打开 Dashboard | 查看首页 | 显示安全卡片（Overall/VPS/CF/Sub） | 无 raw IP/domain | |
| 4 | 验证安全卡片 | 查看字段 | 显示 healthy/active/configured 等状态词 | — | |
| 5 | 打开 Status 页 | 点击 Status | 显示安全卡片 + 高级诊断区域 | — | |
| 6 | 验证安全卡片 | 查看字段 | 同 Dashboard 卡片 | — | |
| 7 | Raw JSON OFF | 高级模式未启用 | 显示锁定面板（🔒），不渲染 raw_json | — | |
| 8 | 启用高级模式 | 点击 Enable 按钮 | 显示警告，切换到启用状态 | — | |
| 9 | 验证警告出现 | 查看警告 | "Raw JSON is redacted..." | — | |
| 10 | Raw JSON ON | 查看 details | Raw JSON details 折叠存在 | — | |
| 11 | 展开 Raw JSON（可选） | 点击 details | 显示 redacted JSON | 无 raw token/IP/domain | |
| 12 | 验证值已脱敏 | 查看内容 | 无 raw IP/domain/token/URL | — | |
| 13 | 禁用高级模式或登出 | 点击 Disable 或 Logout | Raw JSON 锁定或 session 重置 | — | |
| 14 | 验证 Raw JSON 锁定 | 查看 Status 页 | 再次显示锁定面板 | — | |
| 15 | /api/status（可选） | 浏览器访问 | 返回 redacted JSON | 不粘贴 raw body | |
| 16 | 确认无敏感值 | 全局检查 | 无 raw IP/domain/token/workers.dev/subscription URL/private key | — | |

**预期：无 raw 敏感值可见，/api/status 脱敏，高级模式是 session 级别。**

---

## 8. Redaction 观察规则

### 安全报告示例

```
Bot /status: PASS, 显示 healthy/unknown 摘要，无 raw 地址。
/status_json OFF: PASS, 提示启用 /advanced on。
/status_json ON: PASS, 显示警告和 redacted JSON；无 raw token/IP。
Web Raw JSON OFF: PASS, 锁定面板。
Web Raw JSON ON: PASS, 仅 redacted details。
```

### 不安全报告示例

- 截图中包含 IP/domain/token
- 复制的 JSON body
- 复制的 subscription URL
- 复制的 env 内容

---

## 9. 失败处理

**如果某项测试失败：**

- ❌ 不要粘贴 raw 输出
- ✅ 用脱敏术语描述失败
- ✅ 如果 secret 出现，立即停止测试，不分享 secret
- ✅ 记录哪个屏幕/命令显示了它
- ✅ 仅分享脱敏截图或文本
- ❌ 不要运行 repair/restart/rotate（除非单独规划）
- ✅ 用脱敏 PASS/FAIL 表返回 ChatGPT

---

## 10. 测试报告模板

```
环境：
  仓库 commit: [commit hash]
  Bot 测试：是/否
  Web 测试：是/否
  真实 VPS 重部署：否
  Cloudflare 变更：否
  Rotate 执行：否

Bot 清单：
  /start:                    PASS / FAIL
  /status:                   PASS / FAIL
  Status 按钮:               PASS / FAIL
  Recovery:                  PASS / FAIL
  Diagnostics:               PASS / FAIL
  Advanced:                  PASS / FAIL
  /status_json OFF:          PASS / FAIL
  /status_json ON:           PASS / FAIL
  Rotate 引导:               PASS / FAIL
  Web Panel 引导:            PASS / FAIL
  非 owner 测试:             PASS / FAIL / 跳过

Web 清单：
  Login:                     PASS / FAIL
  Dashboard:                 PASS / FAIL
  Status:                    PASS / FAIL
  Raw JSON OFF:              PASS / FAIL
  Raw JSON ON:               PASS / FAIL
  /api/status 脱敏:          PASS / FAIL / 跳过
  Logout/重置:               PASS / FAIL / 跳过

泄露检查：
  Raw IP 显示？               否 / 是（脱敏备注）
  Raw token 显示？            否 / 是（脱敏备注）
  workers.dev 显示？          否 / 是（脱敏备注）
  subscription URL 显示？     否 / 是（脱敏备注）
  Reality private key 显示？  否 / 是（脱敏备注）

最终结果：
  PASS / PASS WITH ISSUE / BLOCKED
  脱敏备注：[备注]
```

---

## 11. 何时运行此测试

| 时机 | 推荐 |
|------|------|
| v1.9.27 规划经 ChatGPT 审核后 | ✅ 推荐 |
| 更深入 Bot/Web UX 打磨前 | ✅ 推荐 |
| v1.9 控制面检查点前 | ✅ 推荐 |
| 每次小文档/测试 commit 前 | ❌ 不需要 |
| 任何 release/tag 候选前 | ✅ 必须 |

---

## 12. 仍然阻塞的事项

| 事项 | 状态 | 说明 |
|------|------|------|
| Raw subscription delivery | 阻塞 | 需独立安全设计 |
| Subscription QR delivery | 阻塞 | 需独立安全设计 |
| Production status wrapper | 阻塞 | 未批准 |
| Dirty VPS status wrapping | 阻塞 | 未批准 |
| Operation-log full rollout | 阻塞 | 未批准 |
| 直接 Bot/Web repair/restart | 阻塞 | 未实现 |
| Cloudflare 变更操作 | 阻塞 | 未实现 |
| 直接 config/systemd/secrets 写入 | 阻塞 | 安全禁止 |
| Raw env 读取/显示 | 阻塞 | 安全禁止 |
| 完整真实 VPS 部署回归 | 阻塞 | 未到发布候选 |
| Release/tag | 阻塞 | 未批准 |

---

## 13. 就绪决策

**A. READY FOR USER-RUN LIMITED REAL BOT/WEB SMOKE TEST AFTER CHATGPT REVIEW**

**范围限制：**

- ✅ 用户手动执行
- ✅ 仅限控制面
- ❌ 不分享 secrets
- ❌ 不重部署
- ❌ 不变更 Cloudflare
- ❌ 不执行 rotate
- ❌ 不 tag/release

---

## 14. 下一步方案

| 方案 | 说明 | 推荐 |
|------|------|------|
| 用户运行有限真实 Bot/Web 冒烟测试并报告脱敏 PASS/FAIL | 用户手动执行 | ✅ 如用户准备就绪 |
| v1.9.28 — Web Dashboard UX 打磨规划 | 规划 Web UX 打磨 | 可选 |
| v1.9.28 — v1.9 控制面检查点 | 全面检查点 | 可选 |

**推荐：如用户准备就绪，运行有限真实 Bot/Web 冒烟测试并报告脱敏 PASS/FAIL。否则继续 v1.9.28 Web Dashboard UX 打磨规划。**

---

## 15. Guardrails

| # | 约束 | 说明 |
|---|------|------|
| 1 | 禁止修改 `install.sh` | 保护 v1.7.27 基线 |
| 2 | 禁止修改 `bin/nanobk` | 保护 CLI 核心 |
| 3 | 禁止修改协议模板 | 保护部署 |
| 4 | 禁止修改 Worker | 保护 Cloudflare |
| 5 | 禁止修改 rotate sync | 保护轮换 |
| 6 | 禁止直接 Bot/Web 写入 configs/systemd/secrets | 安全 |
| 7 | 禁止 raw env 读取 | 安全 |
| 8 | 禁止 production status wrapper | 未批准 |
| 9 | 禁止 dirty VPS status wrapping | 未批准 |
| 10 | 禁止 operation-log full rollout | 未批准 |
| 11 | 禁止 raw subscription delivery | 未批准 |
| 12 | 禁止 tag/release | 未批准 |
