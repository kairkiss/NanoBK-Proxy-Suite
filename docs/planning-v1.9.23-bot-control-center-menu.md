# v1.9.23 — Bot Control Center Menu Planning

> 规划类型：Bot 控制中心菜单规划文档
> 日期：2026-06-05
> 基线 commit：`a501043a5e17d86cad7a4b7ec3fcbe291acfeb30`
> 基线信息：`test: add v1.9.22 raw json gating checkpoint`

---

## 1. 本轮目标与结论

**v1.9.23 是规划文档任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无部署逻辑变更
- ✅ 无 tag/release
- ✅ 目的是规划 Bot 控制中心菜单结构，在实现前确保安全和用户体验

**结论：定义 Telegram Bot 控制中心的产品化菜单结构——包括 /start 行为、主菜单按钮、命令分组、风险分级、回调策略、实现路线和测试需求。**

---

## 2. 当前 Bot 状态

| 项 | 状态 |
|----|------|
| `/status` | ✅ 安全新手摘要 |
| `/status_json` | ✅ 软门控于高级模式 |
| `/advanced on/off/status` | ✅ 已实现，owner-only，15 分钟 TTL |
| `/doctor` | ✅ 已实现 |
| Rotate 命令 | ✅ 已实现，需确认 |
| owner-only 授权 | ✅ 已实现 |
| redaction | ✅ 已集成共享 helper |
| UX 形态 | ⚠️ 仍是命令列表式，非产品化控制中心 |

---

## 3. Bot Control Center 定位

| 定位 | 说明 |
|------|------|
| 手机端 NanoBK 控制中心 | 让用户在手机上管理 VPS/CF/订阅状态 |
| 不是部署核心 | 不触发部署流程 |
| 不是 secret 查看器 | 不展示 raw secrets |
| 不是配置编辑器 | 不直接写 configs/systemd/secrets |
| 不是 Full Wizard 替代 | 不替代安装流程 |
| 应引导用户 | 状态、诊断、恢复、安全操作 |
| 必须调用 nanobk CLI | 不绕过 CLI |
| 必须安全 | 不暴露 raw IP/domain/token/subscription URL |

---

## 4. 用户层级与菜单原则

### 三层模型

| 层级 | 名称 | 默认 | 可见内容 |
|------|------|------|----------|
| L1 | 新手 | ✅ 默认 | 状态摘要、安全恢复提示、帮助 |
| L2 | 高级诊断 | 需手动启用 | `/advanced on/off/status`、门控 `/status_json`、redacted 诊断 |
| L3 | 维护者 | 始终为 owner | 高风险操作（需确认）、rotate 命令 |

### 菜单原则

| 原则 | 说明 |
|------|------|
| 默认菜单安全可读 | 新手不应看到危险操作 |
| 无 raw IP/domain/token/subscription URL | 永远不展示 |
| 无 fake success | honest status |
| 高风险操作需确认 | rotate/restart/repair |
| 高级诊断明确分离 | 不与普通状态混在一起 |

---

## 5. Proposed /start 行为

### 当前 /start

```
NanoBK Bot online.
Only the configured owner can use this bot.
Use /help to see commands.
```

### 未来 /start

```
🏠 NanoBK 控制中心

使用下方按钮快速操作，或输入 /help 查看所有命令。
敏感地址和密钥已隐藏。

[📊 状态总览] [🧭 恢复帮助]
[🩺 诊断检查] [🔐 高级模式]
[🔄 轮换密钥] [🌐 Web Panel]
[❓ 帮助]
```

**设计要点：**

- 产品名称：NanoBK 控制中心
- 简短问候
- 安全声明（敏感地址已隐藏）
- 主菜单按钮
- 保留 `/help` 作为文字命令入口

---

## 6. 主菜单按钮映射

### 状态组

| 按钮 | 标签 | 目标 | 风险 | 实现版本 |
|------|------|------|------|----------|
| 1 | 📊 状态总览 | `/status` | 只读 | v1.9.24 |
| 2 | 🧭 恢复帮助 | 静态安全恢复文本 | 只读 | v1.9.24 |

### 诊断组

| 按钮 | 标签 | 目标 | 风险 | 实现版本 |
|------|------|------|------|----------|
| 3 | 🩺 诊断检查 | `/doctor` | 中风险 | v1.9.24 |
| 4 | 🔐 高级模式 | `/advanced status` | 只读 | v1.9.24 |
| 5 | 📋 Raw JSON | `/status_json`（门控） | 中风险 | v1.9.24+ |

### 操作组

| 按钮 | 标签 | 目标 | 风险 | 实现版本 |
|------|------|------|------|----------|
| 6 | 🔄 轮换密钥 | 二级 rotate 菜单 | 高风险 | v1.9.24+ |
| 7 | 🌐 Web Panel | 安全引导文本 | 只读 | v1.9.24 |
| 8 | ❓ 帮助 | `/help` | 只读 | v1.9.24 |

### Rotate 二级菜单

| 按钮 | 标签 | 目标 | 风险 | 实现版本 |
|------|------|------|------|----------|
| 6a | 轮换全部 | `/rotate_all` | 高风险 | v1.9.24+ |
| 6b | 轮换 HY2 | `/rotate_hy2` | 高风险 | v1.9.24+ |
| 6c | 轮换 TUIC | `/rotate_tuic` | 高风险 | v1.9.24+ |
| 6d | 轮换 Reality | `/rotate_reality` | 高风险 | v1.9.24+ |
| 6e | 轮换 Trojan | `/rotate_trojan` | 高风险 | v1.9.24+ |
| 6f | 取消 | `/cancel` | 只读 | v1.9.24+ |

---

## 7. 风险分类

### 只读安全

| 操作 | 说明 |
|------|------|
| `/status` | 安全状态摘要 |
| `/help` | 帮助文本 |
| `/advanced status` | 高级模式状态 |
| 恢复帮助 | 静态安全提示 |
| Web Panel 引导 | 安全文本 |

### 中风险

| 操作 | 说明 |
|------|------|
| `/doctor` | 只读诊断，但输出可能含路径 |
| `/status_json` | 门控于高级模式，redacted |

### 高风险（需确认）

| 操作 | 说明 |
|------|------|
| `/rotate_all` | 两步确认 |
| `/rotate_hy2` | 两步确认 |
| `/rotate_tuic` | 两步确认 |
| `/rotate_reality` | 两步确认 |
| `/rotate_trojan` | 两步确认 |

### 阻塞

| 操作 | 状态 |
|------|------|
| repair/restart | 阻塞 |
| Cloudflare mutation | 阻塞 |
| subscription delivery | 阻塞 |
| raw URL display | 阻塞 |
| direct config/systemd/secrets writes | 阻塞 |

---

## 8. Callback vs Slash 命令策略

### 选项对比

| 方案 | 说明 | 优点 | 缺点 |
|------|------|------|------|
| A. 按钮调用现有命令处理器 | 回调内部调用现有 handler | 简单、无逻辑重复 | 需要 adapter |
| B. 按钮使用 callback query handler | 独立回调处理 | 灵活 | 可能重复逻辑 |
| C. 按钮发送 slash 命令提示 | 按钮只提示用户输入命令 | 最简单 | 用户体验差 |

### 推荐方案

**v1.9.24：静态菜单 + 回调调用现有处理器**

**理由：**

1. 不重复业务逻辑
2. 斜杠命令仍是规范快捷方式
3. 不绕过 owner 检查
4. 不绕过确认流
5. 实现简单

**实现方式：**

- 按钮使用 `InlineKeyboardButton`
- 回调处理器调用现有命令处理函数
- 斜杠命令仍注册为 `CommandHandler`
- 两者共享相同的安全检查

---

## 9. 消息文案和 UX 语调

### 主菜单文案

**中文：**

```
🏠 NanoBK 控制中心

使用下方按钮快速操作，或输入 /help 查看所有命令。
敏感地址和密钥已隐藏。
```

**English：**

```
🏠 NanoBK Control Center

Use the buttons below for quick actions, or type /help for all commands.
Sensitive addresses and secrets are hidden.
```

### 诊断菜单文案

**中文：**

```
🩺 诊断检查

运行诊断以检查 VPS 和服务状态。
诊断输出已脱敏。
```

**English：**

```
🩺 Diagnostics

Run diagnostics to check VPS and service status.
Diagnostic output is redacted.
```

### 高级模式提示

**中文：**

```
🔐 高级模式

高级诊断模式用于排障，会显示脱敏的 Raw JSON。
该模式会在 15 分钟后自动过期。
```

**English：**

```
🔐 Advanced Mode

Advanced diagnostics mode is for troubleshooting and shows redacted Raw JSON.
This mode expires automatically after 15 minutes.
```

### Rotate 菜单文案

**中文：**

```
🔄 轮换密钥

选择要轮换的协议。轮换会重启服务并更新凭证。
所有操作需要二次确认。
```

**English：**

```
🔄 Rotate Secrets

Select a protocol to rotate. Rotation restarts services and updates credentials.
All operations require confirmation.
```

### 恢复帮助文案

**中文：**

```
🧭 恢复帮助

如果服务异常，请尝试：
1. 运行 /status 查看状态
2. 运行 /doctor 检查诊断
3. 通过 SSH 连接 VPS 手动恢复

敏感地址和密钥已隐藏。
```

**English：**

```
🧭 Recovery Help

If services are abnormal, try:
1. Run /status to check status
2. Run /doctor for diagnostics
3. Connect to VPS via SSH for manual recovery

Sensitive addresses and secrets are hidden.
```

---

## 10. 实现路线

### 分阶段路线

| 版本 | 内容 | 范围 | 前置 |
|------|------|------|------|
| **v1.9.23** | Bot 控制中心菜单规划 | ✅ 本文档 | ChatGPT 审核 |
| **v1.9.24** | Bot 控制中心静态菜单最小实现 | 小步 | ChatGPT 审核 |
| **v1.9.25** | Bot 控制中心回调打磨 | 中步 | ChatGPT 审核 |
| **v1.9.26** | Bot 控制中心检查点 | 检查点 | — |

### v1.9.24 范围

- `/start` 显示主菜单按钮
- 按钮分组：状态、诊断、操作、帮助
- 回调调用现有安全处理器
- 斜杠命令仍可用
- 不添加新风险操作
- 不改变现有命令行为
- 测试验证按钮标签和回调

### 为什么不推荐一次实现所有

- 变更范围过大
- 难以审核
- 难以回滚
- 可能引入意外绕过

---

## 11. 测试策略

### 未来测试

| 测试 | 说明 |
|------|------|
| `/start` 包含主菜单标签 | 按钮存在 |
| `/help` 仍列出斜杠命令 | 兼容性 |
| 状态按钮路由到安全 `/status` | 安全 |
| 诊断按钮不显示 Raw JSON（除非高级模式） | 门控 |
| Raw JSON 按钮尊重软门控 | 安全 |
| Rotate 按钮使用现有确认流 | 安全 |
| owner-only 检查保持 | 安全 |
| 无回调绕过 | 安全 |
| 无 raw IP/domain/URL/subscription path | 安全 |
| 无 shell=True | 安全 |
| 无直接 env 读取 | 安全 |
| v1.9.4–v1.9.22 测试通过 | 回归 |

---

## 12. 真实 Bot/Web 冒烟测试时机

- 不运行完整真实 VPS 部署测试
- 第一个 Bot 控制中心最小实现后，规划有限真实 Bot session 冒烟测试
- 冒烟测试应仅使用 redacted 观察
- 用户不应粘贴真实 secrets/env/IP/subscription URL
- 冒烟测试项：
    - `/start` 菜单出现
    - `/status` 安全摘要
    - 诊断门控
    - rotate 确认打开但用户可取消
    - 无 raw secrets 出现

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

**A. READY FOR BOT CONTROL CENTER STATIC MENU MINIMAL IMPLEMENTATION**

**范围限制：**

- ✅ 就绪于静态/最小菜单实现（v1.9.24）
- ❌ 不就绪于广泛回调重写
- ❌ 不就绪于 repair/restart
- ❌ 不就绪于 raw subscription delivery
- ❌ 不就绪于 release/tag

---

## 15. 推荐下一步

**推荐：v1.9.24 — Bot Control Center Static Menu Minimal Implementation**

**理由：**

1. 安全基础已就位（status、advanced mode、gating）
2. 菜单结构明确
3. 回调可调用现有安全处理器
4. 不添加新风险操作
5. 为后续回调打磨铺路

**v1.9.24 应包含：**

- `/start` 显示主菜单按钮
- 按钮分组：状态、诊断、操作、帮助
- 回调调用现有处理器或显示命令提示
- 斜杠命令仍可用
- 测试验证

**不推荐：**

- 同时实现所有菜单和回调
- 添加新风险操作
- 改变现有命令行为

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
