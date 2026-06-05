# v1.9.19 — Raw JSON Gating Policy Planning

> 规划类型：Raw JSON 门控策略规划文档
> 日期：2026-06-05
> 基线 commit：`f7e8417bcc56da2a3da1151141a9c1c62cdc1c6e`
> 基线信息：`test: add v1.9.18 advanced diagnostics checkpoint`

---

## 1. 本轮目标与结论

**v1.9.19 是策略/规划文档任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无部署逻辑变更
- ✅ 无 `install.sh` 变更
- ✅ 无 `bin/nanobk` 变更
- ✅ 无 tag/release
- ✅ 目的是定义 Raw JSON 门控策略，在实现前确保安全和可用性

**结论：定义 Bot `/status_json` 和 Web Raw JSON details 的软门控策略——当高级诊断模式关闭时显示引导信息，当高级模式开启时显示脱敏 Raw JSON。**

---

## 2. 当前状态

### Bot

| 项 | 状态 |
|----|------|
| `/status` | ✅ 安全新手摘要 |
| `/status_json` | ✅ 可用，警告保护，脱敏 |
| `/advanced on/off/status` | ✅ 已实现 |
| 高级模式门控 `/status_json` | ❌ 未实现 |

### Web

| 项 | 状态 |
|----|------|
| Dashboard/Status 安全卡片 | ✅ 已实现 |
| Raw JSON details | ✅ 可见，警告保护，脱敏 |
| Web 高级模式 | ✅ 已实现 |
| 高级模式门控 Raw JSON | ❌ 未实现 |
| `/api/status` | ✅ 可用，返回 redacted JSON |

### 阻塞项

- Raw subscription delivery — 阻塞
- Production status wrapper — 阻塞
- Dirty VPS status wrapping — 阻塞
- Operation-log full rollout — 阻塞
- Release/tag — 阻塞

---

## 3. 为什么需要门控

### 门控的理由

| 理由 | 说明 |
|------|------|
| Raw JSON 不是新手 UI | 新手应使用安全状态卡片 |
| 即使脱敏也可能泄露结构 | JSON 字段名暗示部署拓扑 |
| 用户可能复制粘贴到不安全地方 | 诊断信息不应被盲目分享 |
| 高级诊断应该是有意的 | 不应默认暴露 |
| `/status` 和 Web 卡片已满足新手需求 | Raw JSON 是调试工具 |

### 门控必须谨慎的理由

| 理由 | 说明 |
|------|------|
| 诊断必须保持可用 | 支持工作流不能中断 |
| unknown/failed 状态可能需要 raw schema | 测试和维护需要可预测的调试路径 |
| 门控不等于 raw secrets 可用 | 高级模式不解锁 secrets |
| 门控不应破坏现有调试流程 | 支持人员需要访问 |

---

## 4. 总体门控原则

| 原则 | 说明 |
|------|------|
| 门控可见性，不门控 redaction | 高级模式不改变脱敏规则 |
| 高级模式永不关闭 redaction | 所有输出仍经过 shared helper |
| 高级模式永不揭示 raw secrets | token/secret/private key 仍被脱敏 |
| 新手路径仍是 `/status` 和 Web 卡片 | 门控不改变新手体验 |
| Raw 诊断需要显式高级模式 | 不应默认暴露 |
| failed/unknown 仍有安全下一步提示 | 不依赖 Raw JSON |
| 无 raw subscription delivery | 未批准 |
| 无 production status wrapper | 未批准 |
| 无 dirty VPS status wrapping | 未批准 |
| 无直接 env 读取 | 安全禁止 |

---

## 5. Bot `/status_json` 门控选项

### 选项对比

| 方案 | 说明 | 优点 | 缺点 |
|------|------|------|------|
| A. 软门控 | 命令仍可调用；高级模式关闭时显示引导信息，不输出 JSON | 保留命令、减少意外暴露、教导高级模式 | 需要实现逻辑 |
| B. 硬隐藏 | 从 `/help` 移除；命令仍存在但拒绝非高级模式 | 彻底隐藏 | 破坏可发现性 |
| C. 重命名 | 移到 `/debug_status_json` | 更明确的调试语义 | 命令名变更 |
| D. 仅保留警告 | 当前行为不变 | 最简单 | 不解决暴露问题 |
| E. 每次确认 | 每次查看需确认 | 安全 | 交互繁琐 |

### 推荐方案

**A. 软门控**

**理由：**

1. 保留命令，不破坏可发现性
2. 减少意外暴露
3. 教导用户使用高级模式
4. 避免命令名变更
5. 保持支持/调试可用

---

## 6. Bot 未来期望行为

### 高级模式关闭时用户运行 `/status_json`

**不输出 JSON，显示安全消息：**

```
高级诊断模式未启用。

/status_json 只用于排障，会显示脱敏后的 Raw JSON。
请先使用 /status 查看普通安全摘要。

如需继续，请运行 /advanced on。
高级模式会在 15 分钟后自动过期。
```

### 高级模式开启时用户运行 `/status_json`

- 显示警告头部
- 输出 redacted JSON（通过现有 `safe_output()`）
- 不揭示 raw IP/domain/URL/secrets
- 保持消息长度限制
- 不改变 `run_nanobk` 参数

### 高级模式过期

- 表现为关闭状态
- 告诉用户已过期
- 建议 `/advanced on`

---

## 7. Web Raw JSON details 门控选项

### 选项对比

| 方案 | 说明 | 优点 | 缺点 |
|------|------|------|------|
| A. Status 页面软门控 | Raw JSON 区域显示为锁定面板；高级模式关闭时显示说明 + 启用按钮；不渲染 raw_json 内容 | 保留可发现性、避免新手困惑、保持支持流 | 需要实现逻辑 |
| B. 完全隐藏 | 除非高级模式开启，否则完全隐藏 | 彻底隐藏 | 破坏可发现性 |
| C. 保持可见但折叠+仅警告 | 当前行为不变 | 最简单 | 不解决暴露问题 |
| D. 每次查看确认 | 每次展开需确认 | 安全 | 交互繁琐 |
| E. 下载/导出模型 | 不推荐 | — | — |

### 推荐方案

**A. Status 页面软门控**

**理由：**

1. 保留可发现性
2. 避免新手困惑
3. 保持支持/调试流清晰
4. 不需要广泛重设计
5. 与已实现的 session 高级模式配合

---

## 8. Web 未来期望行为

### 高级模式关闭时

- Status 页面仍显示安全卡片
- Raw JSON 区域显示锁定的高级诊断面板
- 说明需要高级模式
- 提供启用表单/按钮（使用现有 POST + CSRF）
- 不渲染 `status.raw_json`
- 不揭示 Raw JSON

### 高级模式开启时

- 显示现有警告
- 显示 Raw JSON `<details>` 块
- 渲染现有 redacted `status.raw_json`
- details 默认折叠
- 不改变 `/api/status`

### Session 过期或高级模式过期

- 表现为关闭状态
- 显示安全提示重新启用

---

## 9. `/api/status` 策略

### 推荐

**v1.9.x 不门控 `/api/status`。**

### 理由

| 理由 | 说明 |
|------|------|
| 已返回 redacted JSON | 已经过 shared helper 脱敏 |
| 现有 Web 测试和内部 UI 可能依赖 | 门控可能破坏集成 |
| API 门控需要独立的 auth/API 策略 | 当前任务是 UI 可见性，不是 API 安全重写 |
| 当前任务是 UI Raw JSON 可见性 | API 门控需要单独规划 |

### 规则

- `/api/status` 必须保持 redacted
- `/api/status` 不得暴露 raw IP/domain/URL/secrets
- `/api/status` 不得交付 subscription URL
- `/api/status` 可在 v2.0 或 API 策略规划中重新考虑

---

## 10. 警告和回退文案

### Bot 关闭文案

**中文：**

```
高级诊断模式未启用。
/status_json 只用于排障，会显示脱敏后的 Raw JSON。
请先使用 /status 查看普通安全摘要。
如需继续，请运行 /advanced on，高级模式会在 15 分钟后自动过期。
```

**English:**

```
Advanced diagnostics mode is not enabled.
/status_json is for troubleshooting only and shows redacted Raw JSON.
Use /status for the normal safe summary first.
To continue, run /advanced on. Advanced mode expires in 15 minutes.
```

### Bot 开启头部

**中文：**

```
⚠️ 高级诊断输出已脱敏，但仍可能包含系统结构信息。
不要把完整输出转发给不可信的人。
```

**English:**

```
⚠️ Advanced diagnostic output is redacted but may still contain system structure information.
Do not forward the full output to untrusted people.
```

### Web 关闭文案

**中文：**

```
Raw JSON 属于高级诊断信息。
请先使用上方状态卡片查看普通安全摘要。
启用高级诊断模式后，可查看脱敏 Raw JSON。该模式会在 15 分钟后自动过期。
```

**English:**

```
Raw JSON is advanced diagnostic information.
Use the status cards above for the normal safe summary first.
After enabling advanced diagnostics mode, you can view redacted Raw JSON. This mode expires in 15 minutes.
```

### Web 开启头部

**中文：**

```
Raw JSON 已脱敏，仅用于高级诊断。
它不是普通用户状态页，也不应作为订阅信息分享。
```

**English:**

```
Raw JSON is redacted and intended for advanced diagnostics only.
It is not a normal user status page and should not be shared as subscription information.
```

---

## 11. 未来实现的测试策略

### Bot 测试

| 测试 | 说明 |
|------|------|
| 高级模式关闭阻塞 `/status_json` JSON 输出 | 不输出 JSON |
| 关闭状态消息包含 `/advanced on` 和 `/status` | 引导信息 |
| 高级模式开启允许 redacted JSON 输出 | 正常输出 |
| 过期高级模式阻塞 JSON | 过期后表现关闭 |
| `/status_json` 仍注册 | 命令存在 |
| `/status` 不受影响 | 新手摘要不变 |
| redaction 不变 | 脱敏规则不变 |
| `run_nanobk` 参数不变 | CLI 调用不变 |
| 无 raw IP/domain/URL/workers.dev/subscription path | 安全 |
| 无 raw secrets | 安全 |
| rotate 不变 | 确认流不变 |

### Web 测试

| 测试 | 说明 |
|------|------|
| 高级模式关闭不渲染 `status.raw_json` | 不输出 JSON |
| 关闭状态显示锁定面板 + 启用表单 | 引导信息 |
| 启用表单使用 POST + CSRF | 安全 |
| 高级模式开启渲染 redacted Raw JSON details | 正常输出 |
| details 默认折叠 | 不自动展开 |
| 过期高级模式隐藏 Raw JSON | 过期后表现关闭 |
| `/api/status` 不变 | API 不门控 |
| 安全卡片不受影响 | 新手体验不变 |
| 无 query 参数绕过 | 安全 |
| redaction 不变 | 脱敏规则不变 |
| login/session/CSRF/rotate 不变 | 认证不变 |

### 共享测试

| 测试 | 说明 |
|------|------|
| v1.9.4–v1.9.18 测试通过 | 回归 |
| 无 env 读取 | 安全 |
| 无持久化高级状态 | 安全 |
| 无 raw subscription delivery | 安全 |
| 无直接写入 | 安全 |

---

## 12. 推荐实现路线

### 分阶段路线

| 版本 | 内容 | 范围 | 前置 |
|------|------|------|------|
| **v1.9.19** | Raw JSON 门控策略规划 | ✅ 本文档 | ChatGPT 审核 |
| **v1.9.20** | Bot `/status_json` 软门控最小实现 | 小步 | ChatGPT 审核 |
| **v1.9.21** | Web Raw JSON 软门控最小实现 | 小步 | ChatGPT 审核 |
| **v1.9.22** | Raw JSON 门控检查点 | 检查点 | — |

### 为什么分开 Bot 和 Web

- 减少每个版本的变更范围
- 更容易审核和测试
- Bot 更简单（无 session 管理），可以先实现
- Web 需要模板变更，风险稍高
- 分开实现可以独立回滚

### 为什么不推荐 Bot + Web 同版本

- 变更范围过大
- 难以定位问题
- 审核复杂度高
- 回滚困难

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

**A. READY FOR BOT RAW JSON SOFT GATE MINIMAL IMPLEMENTATION**

**范围限制：**

- ✅ 就绪于 Bot `/status_json` 软门控（v1.9.20）
- ❌ 不就绪于 Web 门控（需 v1.9.21 单独规划）
- ❌ 不就绪于 `/api/status` 门控
- ❌ 不就绪于 raw subscription delivery
- ❌ 不就绪于 production status wrapper
- ❌ 不就绪于 tag/release

---

## 15. 推荐下一步

**推荐：v1.9.20 — Bot `/status_json` Soft Gate Minimal Implementation**

**理由：**

1. Bot 门控是更简单的实现（无 session/template 变更）
2. 软门控策略明确，实现直接
3. 不改变 redaction 规则
4. 不改变 `run_nanobk` 行为
5. 为 Web 门控铺路
6. v1.9.16–v1.9.18 已建立高级模式基础

**v1.9.20 应包含：**

- 检查高级模式状态
- 关闭时显示引导信息（不输出 JSON）
- 开启时显示警告 + redacted JSON
- 过期时表现关闭
- `/status_json` 仍注册
- `/status` 不受影响
- 测试验证所有行为

**不推荐：**

- 同时实现 Bot + Web 门控
- 改变 redaction 规则
- 改变 `run_nanobk` 行为
- 门控 `/api/status`

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
