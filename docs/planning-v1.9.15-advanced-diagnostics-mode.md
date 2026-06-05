# v1.9.15 — Advanced Diagnostics Mode Planning

> 规划类型：高级诊断模式设计文档
> 日期：2026-06-05
> 基线 commit：`c3d04ea93a00d6bf53132215370d395d6ac2d517`
> 基线信息：`feat: add web raw json warning`

---

## 1. 本轮目标与结论

**v1.9.15 是规划文档任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无部署逻辑变更
- ✅ 无 `install.sh` 变更
- ✅ 无 `bin/nanobk` 变更
- ✅ 无 tag/release
- ✅ 目的是定义未来高级诊断模式的完整设计

**结论：定义 Telegram Bot 和 Web Panel 的高级诊断模式——包括启用方式、权限模型、过期策略、警告文案、可见性规则、测试需求和分阶段实现路线。**

---

## 2. 当前状态

### 已完成

| 版本 | 内容 | 状态 |
|------|------|------|
| v1.9.6 | 共享脱敏 helper | ✅ |
| v1.9.7 | Bot 脱敏路径集成 | ✅ |
| v1.9.8 | Web 脱敏路径集成 | ✅ |
| v1.9.9 | 脱敏一致性检查点 | ✅ |
| v1.9.10 | Bot `/status` 安全摘要 | ✅ |
| v1.9.11 | Web Dashboard/Status 安全卡片 | ✅ |
| v1.9.12 | Raw JSON / 高级诊断策略规划 | ✅ |
| v1.9.13 | Bot `/status_json` 警告 + `/help` 分类 | ✅ |
| v1.9.14 | Web Raw JSON 警告文案 | ✅ |

### 当前残留

| 项 | 状态 | 说明 |
|----|------|------|
| Bot `/status_json` | 可用，有警告，分类在 Advanced diagnostics | 未门控 |
| Web Raw JSON details | 可见，折叠，有警告文案 | 未门控 |
| `/api/status` | 返回 redacted JSON | 未变更 |
| 高级模式 | 未实现 | 本规划定义 |
| 订阅交付 | 阻塞 | — |
| Production status wrapper | 阻塞 | — |

---

## 3. Advanced Diagnostics Mode 定义

### 是什么

高级诊断模式是一种**临时模式**，用于在需要调试或远程支持时查看更详细的脱敏诊断信息。

### 不是什么

| 不是 | 说明 |
|------|------|
| 不是秘密查看器 | 不解锁 raw secrets/env/private keys |
| 不是部署模式 | 不触发部署/重启/修复 |
| 不是暴露许可 | 不允许展示 raw IP/domain/URL |
| 不是修复功能 | 不包含 restart/repair/Cloudflare mutation |
| 不是订阅交付 | 不展示 raw subscription URL |
| 不是永久状态 | 临时启用，自动过期 |

### 核心原则

**高级模式改变的是诊断信息的可见性，而不是安全规则。**

即使在高级模式下：

- 所有输出仍然经过 shared redaction helper
- Raw IP/domain/URL/workers.dev/subscription path 仍然被脱敏
- Token/secret/private key 仍然被脱敏
- Raw env 内容仍然不可见
- 高风险操作仍然需要确认

---

## 4. 用户与权限模型

### L1 新手（默认）

**可见：**

- 安全状态摘要（Bot `/status`、Web Dashboard/Status 卡片）
- 恢复提示
- 下一步建议

**不可见：**

- Raw JSON
- 脱敏诊断详情
- 高级诊断命令

**启用高级模式：** 不可（或需要额外步骤）

### L2 高级诊断

**可见（在 L1 基础上）：**

- 脱敏后的 Raw JSON
- 脱敏后的诊断详情
- Schema keys 和状态词
- 警告文案

**仍不可见：**

- Raw IP/domain/URL
- Workers.dev
- Raw subscription URL/path
- Token/secret/private key
- Raw env 内容

**启用高级模式：** 显式启用（Bot: `/advanced on`、Web: toggle）

### L3 Owner / 维护者

**可见（在 L2 基础上）：**

- 触发高风险操作（需确认）
- 启用/禁用高级模式

**仍不可见：**

- Raw secrets
- Raw env
- Reality private key
- Raw Cloudflare token
- Raw Bot token

**重要：Owner 不等于有权泄露 secrets。Owner 权限仅用于操作触发，不用于信息泄露。**

---

## 5. Bot 高级模式选项

### 选项对比

| 方案 | 说明 | 优点 | 缺点 |
|------|------|------|------|
| A. `/advanced on` + `/advanced off` | 显式命令启用/禁用 | 简单明确，可审计 | 需要记住命令 |
| B. `/diagnostics on` + `/diagnostics off` | 更明确的语义 | 语义清晰 | 需要记住命令 |
| C. 命令级警告，无模式 | 每次都显示警告 | 最简单 | 每次都打扰高级用户 |
| D. 每命令确认提示 | 每次查看需确认 | 安全 | 交互繁琐 |
| E. Owner-only 临时 flag | 内存中存储 | 安全简单 | 需要实现状态管理 |

### 推荐设计

**方案 A + E 组合：**

| 特性 | 说明 |
|------|------|
| 启用命令 | `/advanced on`（owner-only） |
| 禁用命令 | `/advanced off`（owner-only） |
| 存储 | 仅内存，不持久化到磁盘 |
| 过期 | 自动过期（建议 10-15 分钟） |
| 重启 | Bot 重启后自动重置 |
| 警告 | 启用时显示警告文案 |
| 脱敏规则 | 不改变，仍通过 shared helper |
| `/status_json` | 高级模式下仍显示警告，但 `/help` 中可更突出 |
| `/doctor` | 高级模式下未来可显示 redacted details |
| Rotate | 不变，仍需两步确认 |

### 为什么选这个方案

1. **简单明确**：`/advanced on` + `/advanced off` 语义清晰
2. **安全**：仅内存存储，重启/过期自动重置
3. **可审计**：启用/禁用有明确命令
4. **最小改动**：不需要 session 管理、数据库、或前端变更
5. **渐进式**：先实现开关，后续再扩展功能

---

## 6. Web 高级模式选项

### 选项对比

| 方案 | 说明 | 优点 | 缺点 |
|------|------|------|------|
| A. Session flag toggle | 登录后设置 session flag | 简单 | session 过期后重置 |
| B. 警告弹窗确认 | 展开 Raw JSON 前弹窗确认 | 用户知情 | 增加交互 |
| C. 每页临时揭示 | 点击按钮临时显示 | 直观 | 需要前端变更 |
| D. Owner-only session toggle | 已有 token 登录 | 安全 | 已有安全基础 |
| E. Query parameter | URL 参数控制 | 简单 | 不推荐（安全风险） |

### 推荐设计

**方案 A + D 组合：**

| 特性 | 说明 |
|------|------|
| 启用方式 | 页面上的 "Enable advanced diagnostics" 按钮/链接 |
| 确认 | 点击后显示警告弹窗，需确认 |
| 存储 | Session 级 flag（`session["advanced_mode"] = True`） |
| 过期 | 随 session 过期自动重置 |
| 登出 | 登出后自动重置 |
| 持久化 | 不持久化到磁盘/数据库 |
| URL 参数 | 不支持（安全风险） |
| 警告 | 启用时显示警告文案 |
| 脱敏规则 | 不改变，仍通过 shared helper |
| Raw JSON | 高级模式下默认展开（或更易访问） |
| `/api/status` | 不变，仍返回 redacted JSON |
| Dashboard | 不变，仍显示安全卡片 |

### 为什么选这个方案

1. **安全**：已有 token 登录保护，session 级存储
2. **简单**：不需要数据库或持久化
3. **用户友好**：页面上的 toggle 比 URL 参数更直观
4. **自动清理**：session 过期/登出自动重置
5. **渐进式**：先实现 toggle，后续再扩展功能

---

## 7. 过期与持久化策略

### Bot 高级模式

| 特性 | 策略 |
|------|------|
| 过期时间 | 10-15 分钟自动过期 |
| 存储位置 | 仅内存（Python dict/变量） |
| 持久化 | 不持久化到磁盘 |
| 重启 | Bot 重启后自动重置 |
| 显式禁用 | `/advanced off` 立即禁用 |
| 多用户 | 当前单用户模型（owner-only） |

### Web 高级模式

| 特性 | 策略 |
|------|------|
| 过期时间 | 随 Flask session 过期 |
| 存储位置 | Flask session（服务端 session） |
| 持久化 | 不持久化到数据库 |
| 登出 | 登出后自动重置 |
| 显式禁用 | 点击 "Disable" 或登出 |
| 多用户 | 每个 session 独立 |

### 为什么不用持久化

- 高级模式是临时调试工具，不是用户偏好
- 持久化增加安全风险（重启后仍有高级权限）
- 内存/session 存储足够简单和安全
- 不需要数据库或配置文件变更

---

## 8. 警告文案

### Bot 启用高级模式

**中文：**

```
⚠️ 高级诊断模式已启用

输出已脱敏，但仍可能包含系统结构信息。
不要把完整输出转发给不可信的人。
敏感地址和密钥已隐藏。
模式将在 15 分钟后自动关闭，或使用 /advanced off 手动关闭。
```

**English：**

```
⚠️ Advanced diagnostics mode enabled

Output is redacted but may still contain system structure information.
Do not forward the full output to untrusted parties.
Sensitive addresses and secrets are hidden.
Mode will auto-expire in 15 minutes, or use /advanced off to disable.
```

### Web 启用高级模式

**中文：**

```
⚠️ 启用高级诊断模式？

启用后可以查看脱敏的 Raw JSON 和诊断详情。
输出已脱敏，但仍可能包含系统结构信息。
不要把完整输出转发给不可信的人。
模式将在 session 过期后自动关闭。

[启用]  [取消]
```

**English：**

```
⚠️ Enable advanced diagnostics mode?

Enabling will show redacted Raw JSON and diagnostic details.
Output is redacted but may still contain system structure information.
Do not forward the full output to untrusted parties.
Mode will auto-expire when your session expires.

[Enable]  [Cancel]
```

### 高级诊断输出头部

**中文：**

```
⚠️ 高级诊断输出已脱敏
敏感地址和密钥已隐藏。不要盲目分享。
```

**English：**

```
⚠️ Advanced diagnostic output is redacted
Sensitive addresses and secrets are hidden. Do not share blindly.
```

---

## 9. 高级模式可见性规则

### 允许（高级模式下可见）

| 内容 | 说明 |
|------|------|
| 脱敏后的 Raw JSON | 经过 shared helper 脱敏 |
| 脱敏后的诊断详情 | 经过 safe_output 处理 |
| Schema keys | JSON 字段名 |
| 服务名称 | hy2/tuic/reality/trojan |
| 布尔值和状态词 | true/false/active/failed/unknown |
| 脱敏占位符 | `[REDACTED]`、`[REDACTED_IPV4]` 等 |
| 失败类别 | failed/incomplete/missing |
| 安全恢复提示 | SSH 命令建议 |

### 仍然禁止（即使在高级模式下）

| 内容 | 原因 |
|------|------|
| Raw IP 地址 | 安全 |
| Raw 域名 | 安全 |
| Raw URL | 安全 |
| Workers.dev | 安全 |
| Raw subscription URL/path | 安全 |
| Token/secret/password | 安全 |
| Private key | 安全 |
| Raw env 内容 | 安全 |
| Raw profile JSON（含 secrets） | 安全 |
| Reality private key | 安全 |
| Cloudflare token | 安全 |
| Bot token | 安全 |
| Admin token | 安全 |

---

## 10. 与现有命令/页面的交互

### Bot

| 命令/页面 | 当前行为 | 高级模式下行为 |
|-----------|----------|---------------|
| `/status` | 安全摘要 | 不变 |
| `/status_json` | 警告 + redacted JSON | 不变（警告仍显示） |
| `/help` | Basic/Safe/Advanced 分类 | 高级模式下可更突出显示高级命令 |
| `/doctor` | Redacted 输出 | 未来可显示 redacted details |
| Rotate | 两步确认 | 不变 |
| `/start` | 欢迎信息 | 不变 |

### Web

| 页面 | 当前行为 | 高级模式下行为 |
|------|----------|---------------|
| Dashboard | 安全卡片 | 不变 |
| Status | 安全卡片 + 折叠 Raw JSON | Raw JSON 可默认展开或更易访问 |
| Raw JSON 警告 | 显示 | 仍显示 |
| `/api/status` | Redacted JSON | 不变 |
| Doctor | POST 触发 redacted 输出 | 未来可显示 redacted details |
| Rotate | 两步确认 + CSRF | 不变 |
| Login/Logout | Token + session | 不变 |

---

## 11. 测试策略

### Bot 测试

| 测试 | 说明 | 前置 |
|------|------|------|
| `/advanced on` owner-only | 非 owner 无法启用 | v1.9.16 |
| `/advanced off` | 正常禁用 | v1.9.16 |
| 自动过期 | N 分钟后自动禁用 | v1.9.16 |
| 重启重置 | Bot 重启后模式重置 | v1.9.16 |
| `/help` 行为变化 | 高级模式下 `/help` 更突出高级命令 | v1.9.16 |
| `/status_json` 仍脱敏 | 高级模式下输出仍经过 redaction | v1.9.16 |
| 无 raw IP/domain/URL | 输出不包含地址类值 | v1.9.16 |
| 无 raw env 读取 | 不读取 .env 文件 | v1.9.16 |
| Rotate 不变 | 确认流不受影响 | v1.9.16 |
| 启用警告 | 启用时显示警告文案 | v1.9.16 |

### Web 测试

| 测试 | 说明 | 前置 |
|------|------|------|
| 高级 toggle 需要登录 | 未登录无法启用 | v1.9.17 |
| 警告弹窗 | 启用前显示警告 | v1.9.17 |
| Session flag 有效 | 启用后 session 中有 flag | v1.9.17 |
| 登出重置 | 登出后模式重置 | v1.9.17 |
| Session 过期重置 | Session 过期后模式重置 | v1.9.17 |
| Raw JSON 仍脱敏 | 高级模式下 JSON 仍经过 redaction | v1.9.17 |
| 无 query-param 绕过 | URL 参数无法绕过高级模式 | v1.9.17 |
| 普通卡片不变 | Dashboard 卡片不受影响 | v1.9.17 |
| `/api/status` 不变 | API 仍返回 redacted JSON | v1.9.17 |
| CSRF/Login/Rotate 不变 | 安全机制不受影响 | v1.9.17 |

### 共享测试

| 测试 | 说明 | 前置 |
|------|------|------|
| v1.9.4–v1.9.14 测试通过 | 回归验证 | v1.9.16/v1.9.17 |
| 无直接写入 | Bot/Web 不直接写 configs/systemd/secrets | 持续 |
| 无 shell=True | subprocess 使用 list 形式 | 持续 |
| 无 raw 订阅交付 | 不展示 raw subscription URL | 持续 |

---

## 12. 推荐实现路线

### 分阶段路线

| 版本 | 内容 | 范围 | 前置 |
|------|------|------|------|
| **v1.9.15** | 高级诊断模式规划 | 本文档 | ✅ |
| **v1.9.16** | Bot 高级模式最小实现 | 小步 | ChatGPT 审核 |
| **v1.9.17** | Web 高级模式规划或最小实现 | 中步 | ChatGPT 审核 |
| **v1.9.18** | 高级诊断检查点 | 检查点 | — |

### v1.9.16 Bot 高级模式最小实现范围

- Owner-only `/advanced on`
- `/advanced off`
- 内存状态
- 10-15 分钟自动过期
- 启用时警告文案
- `/help` 行为微调（高级模式下更突出高级命令）
- 不改变 redaction 规则
- 不改变 rotate 行为
- 不改变 `/status_json` 输出（仍显示警告）
- 测试验证

### v1.9.17 Web 高级模式范围

- Session 级 toggle
- 警告弹窗确认
- Session 过期自动重置
- 登出重置
- 不支持 URL 参数绕过
- Raw JSON details 在高级模式下更易访问
- 不改变 `/api/status`
- 不改变 redaction 规则
- 测试验证

### 为什么分开 Bot 和 Web

- 减少每个版本的变更范围
- 更容易审核和测试
- Bot 更简单（无 session 管理），可以先实现
- Web 需要 session 管理变更，风险稍高
- 分开实现可以独立回滚

---

## 13. 仍然阻塞的事项

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
| Release/tag | 阻塞 | 未批准 |

---

## 14. 就绪决策

**A. READY FOR BOT ADVANCED MODE MINIMAL IMPLEMENTATION**

**范围限制：**

- ✅ 就绪于 Bot 端 owner-only `/advanced on/off` 最小实现（v1.9.16）
- ❌ 不就绪于 Web 高级模式（需 v1.9.17 单独规划）
- ❌ 不就绪于 Raw JSON 门控（需高级模式实现后再决定）
- ❌ 不就绪于 production status wrapper
- ❌ 不就绪于 raw subscription delivery
- ❌ 不就绪于 tag/release

---

## 15. 推荐下一步

**推荐：v1.9.16 — Bot Advanced Mode Minimal Implementation**

**理由：**

1. Bot 高级模式是更简单的实现（无 session 管理）
2. `/advanced on/off` 语义明确，实现直接
3. 内存状态 + 自动过期足够安全
4. 不改变 redaction 规则，风险低
5. 为 Web 高级模式铺路
6. v1.9.12–v1.9.14 已建立警告文案基础

**v1.9.16 应包含：**

- `/advanced on` 命令（owner-only）
- `/advanced off` 命令
- 内存状态管理
- 10-15 分钟自动过期
- 启用时警告文案
- `/help` 行为微调
- 测试验证所有行为

**不推荐：**

- 同时实现 Bot + Web 高级模式
- 改变 redaction 规则
- 改变 rotate 行为
- 实现 Raw JSON 门控

---

## 16. Guardrails

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
