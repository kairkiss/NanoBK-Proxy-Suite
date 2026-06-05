# v1.9.2 — Telegram Bot UX/Menu Spec

> 规格类型：UX/Menu 设计规格
> 日期：2026-06-05
> 基线 commit：`13a0918d8b4df93c5817124b402281f81c9bc54d`
> 基线信息：`docs: add v1.9.1 bot web safety audit`

---

## 1. 本轮目标与结论

**v1.9.2 是 Bot UX/Menu Spec 文档任务：**

- ✅ 无 Bot 代码变更
- ✅ 无 Web 代码变更
- ✅ 无部署逻辑变更
- ✅ 无 `install.sh` 变更
- ✅ 无 `bin/nanobk` 变更
- ✅ 无 tag/release
- ✅ 本规格用于指导未来实现，但不批准实现

**结论：本规格定义了 Telegram Bot 的用户体验、菜单结构、状态展示规则、命令分组、确认模型和安全边界。实现需等待后续版本审批。**

---

## 2. 设计原则

### 产品定位

Telegram Bot 是 **手机控制中心**，不是部署核心、不是配置编辑器、不是远程 shell。

### 核心原则

| 原则 | 说明 |
|------|------|
| 手机控制中心 | 让用户在手机上理解 VPS/CF/订阅状态，不是在手机上部署 |
| 小白优先 | 默认视图面向非技术用户，不展示 raw 输出 |
| 状态诚实 | unknown/skipped/dry-run/manual_pending 不显示为 success |
| 默认不展示 raw JSON | 新手视图绝不展示 raw JSON |
| 默认不展示地址类 | IP/domain/URL/workers.dev/subscription path 默认脱敏 |
| 所有输出先脱敏 | 任何展示给用户的文本必须先经过 redaction |
| CLI-backed | 所有操作通过 `nanobk` CLI，不直接写文件 |
| 高风险必须确认 | rotate/restart/repair 等操作必须两步确认 |
| 失败给恢复 | 失败消息必须包含安全的恢复建议 |
| 不泄露 secret | token/secret/private key/subscription URL 永远不展示 |

### 绝对禁止

- 禁止 Bot 直接写 configs/systemd/secrets/env
- 禁止 Bot 直接调用 `systemctl`
- 禁止 Bot 读取 env 文件内容
- 禁止 Bot 展示 raw VPS IP/IPv6
- 禁止 Bot 展示 raw domain
- 禁止 Bot 展示 raw URL/workers.dev
- 禁止 Bot 展示 raw subscription URL/path
- 禁止 Bot 展示 Reality private key
- 禁止 Bot 展示 raw token/secret
- 禁止 Bot 提供 raw command box
- 禁止 `shell=True`

---

## 3. 用户分层

### 三层模型

| 层级 | 名称 | 说明 | 默认 |
|------|------|------|------|
| L1 | 新手（Beginner） | 默认视图，卡片式摘要 | ✅ 默认 |
| L2 | 高级（Advanced） | 可查看 redacted 诊断详情 | 需手动切换 |
| L3 | 维护者（Owner） | 可触发操作，但仍然不看 raw secret | 始终为 owner |

### L1 新手视图

**可以看到：**

- 状态摘要卡片（healthy/failed/unknown 等）
- 服务状态（active/inactive/unknown）
- 配置存在性（present/missing）
- 恢复建议
- 下一步操作提示

**绝不可以看到：**

- raw JSON
- raw IP 地址
- raw 域名
- raw URL
- workers.dev
- subscription URL/path
- Reality private key
- token/secret/password
- raw CLI stdout/stderr
- raw port（产品决策待确认）

### L2 高级视图

**可以在 L1 基础上额外看到：**

- redacted 诊断详情（doctor 摘要）
- redacted 错误信息（exit code + 摘要）
- 协议配置详情（present/missing/active/inactive）
- 安全模式信息（secrets mode 600 等）
- redacted warnings 列表

**仍然不可以看到：**

- raw secret/token/private key
- raw IP/domain/URL（需经过地址类脱敏）
- raw env 内容

### L3 维护者视图

**可以在 L2 基础上额外执行：**

- 触发 rotate（需两步确认）
- 触发 doctor（中风险）
- 触发状态刷新

**仍然不可以看到：**

- raw secret/token/private key（即使 owner 也不能通过 Bot 看到）

### 视图切换机制

- 默认 L1（新手）
- 通过 `/advanced on` 或设置中的开关切换到 L2
- L3 始终为 owner，不需要切换
- Bot 重启后重置为 L1

---

## 4. `/start` 首页设计

### 目标

`/start` 应成为 Bot 的控制中心入口，不是简单的 "Bot online" 消息。

### `/start` 消息内容

```text
🏠 NanoBK 控制中心

你的 VPS 代理管理助手。
点击下方按钮查看状态或执行操作。

状态来自 nanobk CLI，敏感地址已隐藏。
```

### 按钮布局

**第一行：状态**

| 按钮 | 回调 | 说明 |
|------|------|------|
| 📊 状态总览 | `btn_overview` | 一键查看所有状态 |
| 🖥️ VPS 状态 | `btn_vps_status` | VPS 详细状态 |
| ☁️ Cloudflare | `btn_cf_status` | Cloudflare 状态 |
| 📱 订阅状态 | `btn_sub_status` | 订阅服务状态 |

**第二行：操作**

| 按钮 | 回调 | 说明 |
|------|------|------|
| 🩺 健康检查 | `btn_doctor` | 运行 doctor（中风险） |
| 🔄 轮换密钥 | `btn_rotate` | 进入 rotate 菜单（高风险） |
| 📋 最近操作 | `btn_recent` | 最近操作摘要（v1.9.x+） |

**第三行：帮助**

| 按钮 | 回调 | 说明 |
|------|------|------|
| 🆘 恢复帮助 | `btn_recovery` | 恢复命令和建议 |
| 🌐 Web Panel | `btn_web_panel` | Web Panel 访问说明 |
| ❓ 帮助 | `btn_help` | 帮助和安全说明 |

### 设计要求

- 按钮使用 InlineKeyboardButton
- 不需要用户记住任何命令
- 每个按钮点击后展示对应内容 + 返回按钮
- `/help` 仍然保留作为文字命令入口
- `/start` 每次发送都刷新按钮

---

## 5. 菜单结构

### 完整菜单树

```text
/start
├── 📊 状态总览          → 全局安全摘要卡片
├── 🖥️ VPS 状态          → VPS 状态卡片
├── ☁️ Cloudflare 状态    → CF 状态卡片
├── 📱 订阅状态           → 订阅状态卡片
├── 🩺 健康检查           → Doctor 结果（中风险）
├── 🔄 轮换密钥           → Rotate 子菜单
│   ├── 轮换全部协议       → 确认 → 执行
│   ├── 轮换 HY2          → 确认 → 执行
│   ├── 轮换 TUIC         → 确认 → 执行
│   ├── 轮换 Reality      → 确认 → 执行
│   ├── 轮换 Trojan       → 确认 → 执行
│   └── 取消              → 清除 pending
├── 📋 最近操作           → 最近操作摘要（v1.9.x+）
├── 🆘 恢复帮助           → 安全恢复命令
├── 🌐 Web Panel          → 访问说明
├── ❓ 帮助               → 帮助文本
│   ├── 安全说明          → 安全设计说明
│   └── 常见问题          → FAQ
└── /cancel               → 取消 pending 确认
```

### 保留的斜杠命令

以下命令保留为快捷方式，与按钮功能相同：

| 命令 | 等价按钮 | 说明 |
|------|----------|------|
| `/start` | — | 首页 |
| `/help` | ❓ 帮助 | 帮助文本 |
| `/status` | 📊 状态总览 | 状态摘要 |
| `/doctor` | 🩺 健康检查 | Doctor |
| `/cancel` | 取消 | 取消 pending |

### 废弃/隐藏的命令

| 命令 | 处理方式 | 原因 |
|------|----------|------|
| `/status_json` | 隐藏，不显示在 /help | raw JSON 不适合新手，见第 13 节 |
| `/rotate_*` | 被按钮菜单替代 | 按钮更友好 |
| `/confirm_rotate_*` | 保留但不显示在菜单 | 确认流内部使用 |

---

## 6. 命令映射表

| 当前命令 | 当前行为 | 未来菜单/按钮 | 风险级别 | 新手可见 | 高级可见 | 需要确认 | 备注 |
|----------|----------|---------------|----------|----------|----------|----------|------|
| `/start` | 返回 "Bot online" + /help | 🏠 控制中心首页 | 只读 | ✅ | ✅ | 无 | 改为按钮式首页 |
| `/help` | 列出所有命令 | ❓ 帮助 | 只读 | ✅ | ✅ | 无 | 改为帮助卡片 |
| `/status` | `nanobk --json status` → `format_status()` | 📊 状态总览 | 只读 | ✅ | ✅ | 无 | 改为安全摘要卡片 |
| `/status_json` | `nanobk --json status` → raw output | 隐藏/高级 | 中 | ❌ | ⚠️ | 无 | 默认隐藏，见第 13 节 |
| `/doctor` | `nanobk doctor` | 🩺 健康检查 | 中 | ✅ | ✅ | 无/简单 | 新手看摘要，高级看详情 |
| `/rotate_all` | 设置 pending confirmation | 🔄 轮换全部 | **高** | ✅ | ✅ | ✅ 两步 | 按钮 + 确认 |
| `/rotate_hy2` | 设置 pending confirmation | 🔄 轮换 HY2 | **高** | ✅ | ✅ | ✅ 两步 | 按钮 + 确认 |
| `/rotate_tuic` | 设置 pending confirmation | 🔄 轮换 TUIC | **高** | ✅ | ✅ | ✅ 两步 | 按钮 + 确认 |
| `/rotate_reality` | 设置 pending confirmation | 🔄 轮换 Reality | **高** | ✅ | ✅ | ✅ 两步 | 按钮 + 确认 |
| `/rotate_trojan` | 设置 pending confirmation | 🔄 轮换 Trojan | **高** | ✅ | ✅ | ✅ 两步 | 按钮 + 确认 |
| `/confirm_rotate_*` | 确认并执行 | 内部确认回调 | **高** | ❌ | ❌ | — | 按钮确认流内部使用 |
| `/cancel` | 清除 pending | 取消按钮 | 只读 | ✅ | ✅ | 无 | 保留斜杠命令 |

---

## 7. 状态总览卡片规范

### 目标

用户点击 "📊 状态总览" 或发送 `/status` 后看到的全局摘要。

### 卡片格式

```text
📊 NanoBK 状态总览

🖥️ VPS：healthy
  四协议：4/4 configured
  服务：3 active, 1 unknown

☁️ Cloudflare：verified
  nanok：configured
  nanob：configured

📱 订阅：manual_pending
  说明：需要验证订阅 URL 可访问性

🤖 Bot：active
🌐 Web：unknown

──────────────
状态来源：nanobk CLI
敏感地址已隐藏
更新时间：刚刚
```

### 状态类别

使用 v1.9.0-planning 定义的统一状态类别：

| 状态 | 含义 | 展示颜色 |
|------|------|----------|
| `healthy` | 本地服务健康 | 🟢 |
| `verified` | 已通过明确验证 | 🟢 |
| `installed` | 已安装，不代表健康 | 🟡 |
| `planned` | 规划中，未执行 | 🟡 |
| `dry-run` | 仅模拟，未写入 | 🟡 |
| `manual_pending` | 需用户手动完成 | 🟡 |
| `skipped` | 用户跳过 | ⚪ |
| `failed` | 失败 | 🔴 |
| `unknown` | 未检查/不可确认 | ⚪ |

### 展示规则

- `verified` 和 `healthy` 才使用绿色/🟢
- `installed` 不自动等同于 `healthy`
- `dry-run` 不自动等同于 `installed`
- `manual_pending` 必须给出下一步
- `skipped` 保持中性
- `failed` 必须展示 redacted 原因 + 恢复建议
- `unknown` 必须说明 "未检查/不可确认"，不能补写推测结果

### 禁止展示

- raw IP 地址
- raw 域名
- raw URL
- workers.dev
- subscription URL/path
- Reality private key
- token/secret

---

## 8. VPS 状态卡片规范

### 触发方式

用户点击 "🖥️ VPS 状态" 按钮。

### 卡片格式（新手视图）

```text
🖥️ VPS 状态

状态：healthy
区域：🇯🇵 JP

协议配置：
  HY2：✅ configured, active
  TUIC：✅ configured, active
  Reality：✅ configured, active
  Trojan：✅ configured, active

安全：
  密钥文件：✅ present
  权限模式：600

──────────────
状态来源：nanobk CLI
敏感地址已隐藏
```

### 卡片格式（高级视图）

在新手视图基础上额外显示：

```text
诊断详情：
  profile：present
  admin env：present
  last check：2 分钟前
  warnings：none
```

### 新手视图允许展示

| 字段 | 展示方式 | 说明 |
|------|----------|------|
| 协议存在性 | present/missing | 不展示具体端口 |
| 服务状态 | active/inactive/unknown | 不展示 PID |
| 配置存在性 | present/missing | 不展示文件路径 |
| 密钥存在性 | present/missing | 不展示密钥内容 |
| profile 存在性 | present/missing | 不展示 profile 内容 |
| 权限模式 | 600/other | 不展示完整 ls -l |
| 区域 | 国旗 + 代码 | 间接信息，可接受 |
| 状态类别 | healthy/failed/unknown 等 | 诚实展示 |

### 新手视图禁止展示

| 字段 | 原因 |
|------|------|
| 真实 IP 地址 | 安全 |
| IPv6 地址 | 安全 |
| raw 域名 | 安全 |
| raw 端口 | 产品决策待确认 |
| UUID/password | 安全 |
| Reality private key | 安全 |
| subscription URL | 安全 |
| raw profile.current.json | 安全 |
| raw CLI 输出 | 用户体验 |

### 端口展示决策

端口是否敏感是一个产品决策。当前建议：

- 新手视图：不展示端口
- 高级视图：可展示协议端口（如 HY2: UDP 443）
- 最终决策需在实现前确认

---

## 9. Cloudflare 状态卡片规范

### 触发方式

用户点击 "☁️ Cloudflare" 按钮。

### 卡片格式（新手视图）

```text
☁️ Cloudflare 状态

nanok Worker：✅ configured
nanob Worker：✅ configured
管理员环境：✅ present

验证状态：verified
同步状态：verified

──────────────
状态来源：nanobk CLI
```

### 新手视图允许展示

| 字段 | 展示方式 |
|------|----------|
| nanok 配置状态 | configured/missing/unknown |
| nanob 配置状态 | configured/missing/unknown |
| admin env 状态 | present/missing/unknown |
| 验证状态 | verified/failed/unknown/manual_pending |
| 同步状态 | verified/failed/unknown/manual_pending |

### 新手视图禁止展示

| 字段 | 原因 |
|------|------|
| Cloudflare API token | secret |
| Account ID | 敏感标识 |
| Worker 默认域名 | 安全 |
| workers.dev URL | 安全 |
| route URL | 安全 |
| subscription URL/path | 安全 |
| admin token | secret |

---

## 10. 订阅状态卡片规范

### 触发方式

用户点击 "📱 订阅状态" 按钮。

### 卡片格式（新手视图）

```text
📱 订阅状态

订阅服务：✅ configured
包含协议：4/4
最近验证：verified

导入说明：
  请在 Clash/Mihomo 中导入订阅链接。
  订阅地址可在 Web Panel 中查看，
  或在 SSH 中运行：nanobk status

──────────────
注意：Bot 不展示完整订阅 URL，以保护安全。
```

### 新手视图允许展示

| 字段 | 展示方式 |
|------|----------|
| 订阅服务状态 | configured/missing/unknown |
| 包含协议数量 | 4/4, 3/4 等 |
| 最近验证状态 | verified/failed/unknown |
| 导入说明 | 文字指引，不含 raw URL |

### 新手视图禁止展示

| 字段 | 原因 |
|------|------|
| 完整订阅 URL | 安全 |
| subscription token | secret |
| workers.dev 域名 | 安全 |
| route URL | 安全 |
| raw path | 安全 |
| QR code（含 raw secret） | 安全 |

### 订阅 URL 交付策略

**v1.9.2 不批准 Bot 直接交付 raw subscription URL。** 如果未来需要帮助用户导入订阅，需要：

1. 独立的安全设计
2. 考虑临时 URL + 过期机制
3. 考虑仅 Web Panel 展示（受保护环境）
4. 考虑指纹确认而非明文展示

---

## 11. Doctor / 健康检查 UX 规范

### 风险级别

**中风险** — Doctor 是只读诊断，但输出可能包含路径/IP/域名/URL。

### 触发方式

- 点击 "🩺 健康检查" 按钮
- 发送 `/doctor` 命令

### 新手视图

```text
🩺 健康检查

检查完成，未发现问题。

或：

🩺 健康检查

发现问题 2 项：
  ⚠️ HY2 服务未运行
  ⚠️ admin env 权限不正确

建议：在 SSH 中运行恢复命令（见 🆘 恢复帮助）
```

### 高级视图

在新手视图基础上，提供 "查看详情" 按钮：

```text
🩺 健康检查详情

[redacted 诊断输出]
exit code: 1

注意：详细输出已经过脱敏处理。
```

### 规则

- 新手视图：只显示摘要（通过/发现问题/需要 SSH）
- 新手视图：不显示 raw stdout/stderr
- 新手视图：失败时给出恢复提示
- 高级视图：显示 redacted 详情
- 高级视图：显示 exit code
- 仍然不展示 raw secret/IP/domain/URL

### 为什么是中风险

- Doctor 是只读命令，不修改任何配置
- 但其输出可能包含系统路径、IP 地址、域名等
- 因此不能无条件展示给新手
- 在证明 Doctor 输出完全安全之前，保持中风险

---

## 12. Rotate / 密钥轮换 UX 规范

### 风险级别

**高风险** — Rotate 会修改凭证并重启服务。

### 触发方式

- 点击 "🔄 轮换密钥" 按钮
- 进入 Rotate 子菜单

### Rotate 子菜单

```text
🔄 轮换密钥

选择要轮换的协议：

[全部协议]  [HY2]
[TUIC]      [Reality]
[Trojan]

⚠️ 轮换会重启服务并更新凭证。
需要二次确认。

[取消]
```

### 两步确认流程

**第一步：选择协议后**

```text
⚠️ 确认轮换 TUIC

即将执行：
  nanobk rotate tuic --yes

影响：
  - TUIC 服务将重启
  - TUIC 凭证将更新
  - 本地 profile 将更新
  - Cloudflare 同步取决于配置

请确认或取消。

[✅ 确认轮换]  [❌ 取消]
```

**第二步：确认后执行**

```text
🔄 正在轮换 TUIC...

执行结果：
  ✅ 轮换成功
  exit code: 0

状态：TUIC 服务已重启
敏感信息已隐藏

如需恢复，请在 SSH 中运行：
  nanobk rotate tuic
```

**失败情况：**

```text
🔄 TUIC 轮换失败

执行结果：
  ❌ 失败
  exit code: 1

可能原因：
  服务重启失败或配置错误

建议恢复：
  请在 SSH 中检查服务状态
  或运行：nanobk doctor
```

### 确认机制要求

| 要求 | 当前状态 | v1.9.2 要求 |
|------|----------|-------------|
| 两步确认 | ✅ 已有 | 保持 |
| 120 秒过期 | ✅ 已有 | 保持 |
| 协议白名单 | ✅ 已有 | 保持 |
| dry-run 支持 | ✅ 已有 | 保持 |
| 按钮确认 | ❌ 当前是文字命令 | 改为按钮 |
| 影响说明 | ⚠️ 简单 | 增强为详细说明 |
| 结果摘要 | ⚠️ raw output | 改为安全摘要 |

### 禁止

- 禁止无确认直接执行
- 禁止展示 raw CLI 输出
- 禁止展示更新后的凭证
- 禁止展示 secret/private key

---

## 13. Raw JSON / status_json 策略

### 当前问题

当前 `/status_json` 命令直接展示 `nanobk --json status` 的 redacted raw output，即使经过基础 redaction，仍可能包含 IP、域名、route URL 等非 token 类敏感字段。

### 策略决定

**`/status_json` 必须默认隐藏。**

| 决定 | 说明 |
|------|------|
| 默认隐藏 | `/status_json` 不出现在 `/help` 和按钮菜单中 |
| 高级可用 | L2 高级用户可通过 `/status_json` 调用 |
| 必须脱敏 | 即使高级视图，也必须经过地址类 redaction |
| 理想替代 | 用产品化状态卡片替代 raw JSON |
| 不展示给新手 | 新手视图绝不展示 raw JSON |

### 实现要求（未来）

1. `/status_json` 从 `/help` 中移除
2. `/status_json` 不出现在按钮菜单中
3. `/status_json` 仅对 L2 高级用户可用
4. `/status_json` 输出必须经过完整 redaction（包括地址类）
5. 理想情况下，用 `/status_debug` 替代，输出更安全的 debug 摘要
6. Web Panel 的 Raw JSON `<details>` 块也需要同步处理

### 为什么保留而不是删除

- 高级用户和维护者可能需要 raw JSON 用于调试
- 完全删除会降低可调试性
- 但默认隐藏可以保护新手

---

## 14. 未来 Redaction 要求

### v1.9.2 不实现 Redaction，只定义需求

以下为未来实现任务的 redaction 需求规格。

### 必须覆盖的类别

| 类别 | 当前覆盖 | 需要新增 | 替代展示 |
|------|----------|----------|----------|
| token-like keys | ✅ | — | `[REDACTED]` |
| secret-like keys | ✅ | — | `[REDACTED]` |
| password-like keys | ✅ | — | `[REDACTED]` |
| private_key-like keys | ✅ | — | `[REDACTED]` |
| 长 base64/hex 串 | ✅ | — | `[REDACTED_B64]` |
| Telegram bot token | ✅ | — | `[BOT_TOKEN_REDACTED]` |
| IPv4 地址 | ❌ | ✅ 需新增 | `[REDACTED_IP]` 或只显示区域 |
| IPv6 地址 | ❌ | ✅ 需新增 | `[REDACTED_IP]` |
| 域名 | ❌ | ✅ 需新增 | `[REDACTED_DOMAIN]` 或 "已配置" |
| URL | ❌ | ✅ 需新增 | `[REDACTED_URL]` |
| workers.dev | ❌ | ✅ 需新增 | `[REDACTED_WORKER]` |
| subscription URL/path | ❌ | ✅ 需新增 | `[REDACTED_SUB]` |
| route URL | ❌ | ✅ 需新增 | `[REDACTED_URL]` |
| Reality private key | ⚠️ 部分 | ✅ 需加强 | `present`/`missing` |
| Cloudflare token | ⚠️ 部分 | ✅ 需加强 | `present`/`missing` |
| Admin token | ⚠️ 部分 | ✅ 需加强 | `present`/`missing` |

### 实现优先级建议

1. **P0（v1.9.5）**：IPv4/IPv6、域名、URL、workers.dev、subscription URL/path
2. **P1**：route URL、Reality private key 加强
3. **P2**：Cloudflare token、Admin token 加强

---

## 15. 操作风险分级

### 三级风险模型

| 级别 | 定义 | 确认要求 | 示例 |
|------|------|----------|------|
| **只读** | 不修改任何状态 | 直接执行 | 帮助、状态摘要、恢复建议 |
| **中风险** | 只读但输出可能含敏感信息 | 简单确认或明确警告 | Doctor、状态刷新、高级诊断 |
| **高风险** | 修改凭证或服务状态 | 两步确认 | Rotate、restart、repair、CF 操作 |

### 当前操作分级

| 操作 | 风险级别 | 确认 | 实现状态 |
|------|----------|------|----------|
| 查看帮助 | 只读 | 无 | ✅ 已有 |
| 查看状态总览 | 只读 | 无 | 🔄 需改为卡片 |
| 查看 VPS 状态 | 只读 | 无 | 🔄 需改为卡片 |
| 查看 CF 状态 | 只读 | 无 | 🔄 需新增 |
| 查看订阅状态 | 只读 | 无 | 🔄 需新增 |
| 查看恢复建议 | 只读 | 无 | 🔄 需新增 |
| 查看 Web Panel 说明 | 只读 | 无 | 🔄 需新增 |
| 运行 Doctor | 中风险 | 简单警告 | 🔄 需改为摘要 |
| 查看 status_json | 中风险 | 隐藏/高级 | 🔄 需隐藏 |
| 轮换密钥 | 高风险 | 两步确认 | ✅ 已有，需增强 |
| 重启服务 | 高风险 | 两步确认 | ❌ 未实现 |
| Cloudflare 操作 | 高风险 | 两步确认 | ❌ 未实现 |
| Repair 操作 | 高风险 | 两步确认 | ❌ 未实现 |

### 新增高风险操作的规则

未来如果新增高风险操作（restart、repair、CF 操作），必须：

1. 第一步：说明 CLI 命令、影响范围、可能中断、预计耗时
2. 第二步：用户显式按钮确认
3. 执行后：展示 redacted 结果、exit code、状态、恢复建议
4. 确认过期：120 秒无确认自动清除

---

## 16. 文案规范

### 核心规则

| 规则 | 说明 |
|------|------|
| 简短 | 适合手机屏幕，每条消息不超过 2000 字符 |
| 小白友好 | 不使用技术术语，或解释技术术语 |
| 不假装成功 | unknown/skipped/dry-run 不显示为 success |
| 默认不展示 raw 日志 | 新手看摘要，高级看 redacted 详情 |
| 使用诚实状态 | healthy/failed/unknown/manual_pending/skipped |
| 解释下一步 | 每个结果都告诉用户可以做什么 |
| 说明何时需要 SSH | 有些操作 Bot 无法完成，需引导到 SSH |
| 说明秘密已隐藏 | 告诉用户敏感信息已脱敏 |
| 不指责用户 | 失败时不说 "你做错了"，说 "发生了问题" |
| 不展示 scary raw error | 新手视图不展示 raw stderr |

### 消息模板

**成功：**

```text
✅ 操作成功

{操作描述}已完成。
状态：healthy
敏感信息已隐藏。
```

**失败：**

```text
❌ 操作失败

{操作描述}未成功完成。
exit code: {code}

可能原因：
  {redacted 原因}

建议：
  {恢复建议}
```

**manual_pending：**

```text
⏳ 需要你的操作

{组件} 当前状态：manual_pending

需要你完成：
  {具体步骤}

完成后，Bot 会自动检测。
```

**unknown：**

```text
❓ 未检查

{组件} 当前状态：unknown
尚未检查或无法确认状态。

如需检查，请：
  {检查方法}
```

**skipped：**

```text
⏭️ 已跳过

{组件} 当前状态：skipped
此步骤已被跳过。

如需执行，请：
  {执行方法}
```

**dry-run：**

```text
🔍 模拟模式

此操作为 dry-run，未实际执行。
如需执行，请关闭 dry-run 模式。

模拟结果：
  {模拟结果}
```

**高风险确认：**

```text
⚠️ 确认{操作}

即将执行：
  nanobk {command}

影响：
  - {影响 1}
  - {影响 2}

请确认或取消。

[✅ 确认]  [❌ 取消]
```

**恢复提示：**

```text
💡 恢复建议

在 SSH 中运行：
  nanobk {command}

或查看帮助：
  nanobk doctor
```

---

## 17. 未来测试要求

### v1.9.2 不实现测试，只定义需求

以下为未来 Bot UX 实现时需要的测试。

### Tier 1 单元测试

| 测试 | 说明 |
|------|------|
| 菜单渲染测试 | 按钮布局与预期一致 |
| 命令到菜单映射测试 | 每个命令映射到正确的菜单项 |
| 新手视图不含 raw JSON | `/status` 输出不包含 JSON 语法 |
| 新手视图不含 IP/domain/URL | 输出不包含 IP 地址、域名、URL |
| 新手视图不含 workers.dev | 输出不包含 workers.dev |
| 新手视图不含 subscription URL | 输出不包含订阅 URL |
| `/status_json` 默认隐藏 | 不出现在 /help 输出中 |
| rotate 仍需确认 | 执行前需要两步确认 |
| doctor 输出已脱敏 | 输出不包含 raw secret |
| 失败输出已脱敏 | stderr 经过 redaction |
| unknown/skipped/dry-run 不显示为 success | 诚实状态展示 |
| 无直接写入 | 无 open(write) 调用 |
| 无 shell=True | subprocess 无 shell 参数 |
| 无 env cat 模式 | 不读取 .env 文件内容 |

### Tier 2 回归测试

| 测试 | 说明 |
|------|------|
| `tests/bot-cli-mock.sh` | 现有测试继续通过 |
| 菜单按钮回调测试 | 按钮回调正确处理 |
| 确认流端到端测试 | 选择 → 确认 → 执行 → 结果 |
| 高级视图切换测试 | /advanced on/off 正确切换 |
| 过期确认测试 | 120 秒后确认失效 |

### Tier 3 手动测试

| 测试 | 说明 |
|------|------|
| 手机端 UX 测试 | 在真实 Telegram 中测试布局 |
| 按钮可点击性测试 | 所有按钮可正常点击 |
| 长消息截断测试 | 长输出正确截断 |
| 错误场景测试 | 各种失败场景的展示 |

---

## 18. v1.9.3 推荐

### 推荐：v1.9.3 — Web Dashboard UX Spec

**理由：**

1. Bot 和 Web 是平行的控制面，应该有平行的 UX 规格
2. Web 的安全风险模型与 Bot 类似（地址类脱敏、raw JSON、确认流）
3. 先定义两个控制面的 UX 规格，再统一实现，可以保证一致性
4. Web 的 CSRF/Session/Auth 机制已经就位，UX spec 可以在此基础上设计
5. 避免 Bot 实现后 Web 不匹配的返工

**v1.9.3 应包含：**

- Dashboard card 设计
- Status 页面结构
- Doctor 页面 UX
- Rotate 确认流 UX
- Raw JSON 策略（与 Bot 一致）
- 地址类脱敏策略（与 Bot 一致）
- 响应式布局要求

**不推荐立即实现 Bot：**

- UX spec 需要人工审核
- Web spec 应同步完成
- Redaction 层（v1.9.5）应先就位
- Allowlist spec（v1.9.4）应先就位

---

## 19. Implementation Guardrails

### 硬性约束

以下约束适用于 v1.9.x 系列所有实现任务：

| # | 约束 | 说明 |
|---|------|------|
| 1 | 禁止 Bot 直接写 configs/systemd/secrets/env | 必须通过 nanobk CLI |
| 2 | 禁止新手视图展示 raw JSON | 使用安全摘要 |
| 3 | 禁止新手视图展示 raw IP/domain/URL/workers.dev/subscription path | 默认脱敏 |
| 4 | 禁止高风险操作无确认 | rotate/restart/repair 必须两步确认 |
| 5 | 禁止直接 systemctl | 必须通过 nanobk CLI |
| 6 | 禁止读取 env 内容 | 不 cat .env 文件 |
| 7 | 所有操作通过 nanobk CLI | 不绕过 CLI |
| 8 | 高风险操作两步确认 | 已有机制，保持并增强 |
| 9 | 禁止 production status wrapper | 未批准 |
| 10 | 禁止 dirty VPS status wrapping | 未批准 |
| 11 | 禁止 operation-log full rollout | 未批准 |
| 12 | 禁止修改 install.sh | 保护 v1.7.27 基线 |
| 13 | 禁止 tag/release | 未批准 |
| 14 | 所有输出经过 safe_output/redact_json | 包括失败输出 |
| 15 | Bot 命令必须检查 is_owner() | 已有机制 |
| 16 | 禁止 shell=True | subprocess 必须使用 list 形式 |

### 实现前必须完成

1. v1.9.2 Bot UX/Menu Spec（本文件）— ✅ 已完成
2. v1.9.3 Web Dashboard UX Spec — 待完成
3. v1.9.4 Command Allowlist Spec/Tests — 待完成
4. v1.9.5 Redaction Layer Audit/Tests — 待完成

### 实现顺序建议

1. v1.9.5 Redaction 层先就位（地址类脱敏）
2. v1.9.4 Allowlist 先定义（命令白名单）
3. 然后才能开始 Bot/Web UX 实现
4. 实现应小步、可 review、可回滚

---

## 附录 A：当前 Bot 命令列表

来自 `bot/nanobk_bot.py`：

```python
# 命令处理器
/start          → cmd_start()
/help           → cmd_help()
/status         → cmd_status()
/status_json    → cmd_status_json()
/doctor         → cmd_doctor()
/cancel         → cmd_cancel()
/rotate_all     → make_rotate_handler("rotate_all")
/rotate_hy2     → make_rotate_handler("rotate_hy2")
/rotate_tuic    → make_rotate_handler("rotate_tuic")
/rotate_reality → make_rotate_handler("rotate_reality")
/rotate_trojan  → make_rotate_handler("rotate_trojan")
/confirm_rotate_* → cmd_confirm_rotate()
```

## 附录 B：nanobk CLI 命令参考

Bot 可调用的 CLI 命令（allowlist）：

```bash
nanobk --version              # 版本信息
nanobk --help                 # 帮助
nanobk status                 # 文本状态
nanobk --json status          # JSON 状态
nanobk doctor                 # 环境诊断
nanobk rotate <proto> --yes   # 轮换密钥
```

## 附录 C：参考文档

| 文档 | 说明 |
|------|------|
| `docs/planning-v1.9.0-bot-web-control-plane-productization.md` | v1.9 范围提案 |
| `docs/audit-v1.9.1-bot-web-current-state-safety.md` | v1.9.1 安全审计 |
| `bot/README.md` | Bot 当前文档 |
| `bot/nanobk_bot.py` | Bot 当前代码 |
