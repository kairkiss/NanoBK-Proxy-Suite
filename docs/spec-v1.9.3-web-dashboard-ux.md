# v1.9.3 — Web Dashboard UX Spec

> 规格类型：Dashboard/UX 设计规格
> 日期：2026-06-05
> 基线 commit：`f56c55808d4ff4255867c3d37df7d5f41ab8c78d`
> 基线信息：`docs: add v1.9.2 bot ux menu spec`

---

## 1. 本轮目标与结论

**v1.9.3 是 Web Dashboard UX Spec 文档任务：**

- ✅ 无 Web 代码变更
- ✅ 无 Bot 代码变更
- ✅ 无部署逻辑变更
- ✅ 无 `install.sh` 变更
- ✅ 无 `bin/nanobk` 变更
- ✅ 无 tag/release
- ✅ 本规格用于指导未来实现，但不批准实现

**结论：本规格定义了 Web Panel 的用户体验、Dashboard 布局、页面结构、状态卡片、Raw JSON 策略、确认模型、Redaction 需求和安全边界，与 v1.9.2 Bot UX/Menu Spec 保持一致。实现需等待后续版本审批。**

---

## 2. 设计原则

### 产品定位

Web Panel 是 **浏览器控制面板**，不是部署核心、不是配置编辑器、不是文件管理器。

### 核心原则

| 原则 | 说明 |
|------|------|
| 浏览器控制面板 | 让用户在浏览器中理解 VPS/CF/订阅状态，不是在浏览器中部署 |
| 小白优先 | 默认视图面向非技术用户，不展示 raw 输出 |
| 状态诚实 | unknown/skipped/dry-run/manual_pending 不显示为 success |
| 默认不展示 raw JSON | 新手视图绝不展示 raw JSON |
| 默认不展示地址类 | IP/domain/URL/workers.dev/subscription path 默认脱敏 |
| 所有显示先脱敏 | 任何展示给用户的文本必须先经过 redaction |
| CLI-backed | 所有操作通过 `nanobk` CLI，不直接写文件 |
| 高风险必须确认 | rotate/restart/repair 等操作必须两步确认 + CSRF |
| 失败给恢复 | 失败消息必须包含安全的恢复建议 |
| 不泄露 secret | token/secret/private key/subscription URL 永远不展示 |
| 与 Bot 一致 | 状态语义、风险分级、脱敏策略与 Telegram Bot 保持一致 |

### 绝对禁止

- 禁止 Web 直接写 configs/systemd/secrets/env
- 禁止 Web 直接调用 `systemctl`
- 禁止 Web 读取 env 文件内容
- 禁止 Web 展示 raw VPS IP/IPv6
- 禁止 Web 展示 raw domain
- 禁止 Web 展示 raw URL/workers.dev
- 禁止 Web 展示 raw subscription URL/path
- 禁止 Web 展示 Reality private key
- 禁止 Web 展示 raw token/secret
- 禁止 Web 提供 raw command box
- 禁止 `shell=True`

---

## 3. 用户分层

### 三层模型

与 v1.9.2 Bot spec 保持一致的三层模型：

| 层级 | 名称 | 说明 | 默认 |
|------|------|------|------|
| L1 | 新手（Beginner） | 默认视图，卡片式摘要 | ✅ 默认 |
| L2 | 高级（Advanced） | 可查看 redacted 诊断详情 | 需手动切换 |
| L3 | 维护者（Owner） | 可触发操作，但仍然不看 raw secret | 登录即为 owner |

### L1 新手视图

**可以看到：**

- 状态摘要卡片（healthy/failed/unknown 等）
- 服务状态（active/inactive/unknown）
- 配置存在性（present/missing）
- 恢复建议
- 下一步操作提示
- 快捷操作按钮（安全的只读操作）

**绝不可以看到：**

- raw JSON
- raw `<details>` / `<pre>` 中的 CLI 输出
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
- Redacted Raw JSON（折叠式，需点击展开）

**仍然不可以看到：**

- raw secret/token/private key
- raw IP/domain/URL（需经过地址类脱敏）
- raw env 内容

### L3 维护者视图

**可以在 L2 基础上额外执行：**

- 触发 rotate（需两步确认 + CSRF）
- 触发 doctor（中风险）
- 触发状态刷新
- 所有 POST 操作

**仍然不可以看到：**

- raw secret/token/private key（即使 owner 也不能通过 Web 看到）

### 视图切换机制

- 默认 L1（新手）
- 通过页面上的 "高级模式" 开关切换到 L2
- L3 始终为登录用户，不需要切换
- Session 过期后重置为 L1
- 视图状态存储在 session 中

---

## 4. Web 信息架构总览

### 目标导航结构

```text
NanoBK Web Panel
├── Dashboard (首页)          → 全局状态摘要 + 快捷操作
├── Status (状态)             → 详细状态卡片
├── Doctor (健康检查)         → 诊断结果
├── Rotate (密钥轮换)         → 协议选择 + 确认
├── Recovery (恢复)           → 恢复命令和建议
├── Help (帮助)               → 安全说明 + FAQ
└── Login / Logout            → 认证
```

### 页面与路由映射

| 页面 | 路由 | 说明 | 风险 |
|------|------|------|------|
| Dashboard | `GET /` | 首页，状态摘要 + 快捷操作 | 只读 |
| Status | `GET /status` | 详细状态卡片 | 只读 |
| API Status | `GET /api/status` | JSON API（redacted） | 中 |
| Doctor | `GET/POST /doctor` | 诊断页面 | 中 |
| Rotate | `GET /rotate` | 密钥轮换 | 高 |
| Rotate Request | `POST /rotate/request` | 请求确认 | 高 |
| Rotate Confirm | `POST /rotate/confirm` | 确认执行 | 高 |
| Rotate Cancel | `POST /rotate/cancel` | 取消 | 只读 |
| Login | `GET/POST /login` | 登录 | 只读 |
| Logout | `POST /logout` | 登出 | 只读 |
| Healthz | `GET /healthz` | 健康检查（无认证） | 只读 |

### 未来可扩展页面

| 页面 | 说明 | v1.9.3 状态 |
|------|------|-------------|
| Recovery | 恢复命令和建议 | 建议新增 |
| Recent Operations | 最近操作摘要 | 建议新增（需 v1.9.x+） |
| Help / About | 帮助和安全说明 | 建议新增 |
| Settings | 视图切换、偏好 | 建议新增 |

---

## 5. Dashboard 首页布局

### 目标

Dashboard 是用户登录后看到的第一个页面，应提供全局状态概览和快捷操作。

### 布局结构

```text
┌─────────────────────────────────────────────────┐
│  导航栏：Dashboard | Status | Doctor | Rotate   │
│  [高级模式: OFF]                    [Logout]    │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌─────────────────────────────────────────┐    │
│  │  Overall Status Card                    │    │
│  │  整体状态摘要                            │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  ┌──────────────┐  ┌──────────────┐             │
│  │  VPS Card    │  │  CF Card     │             │
│  │  VPS 状态     │  │  Cloudflare  │             │
│  └──────────────┘  └──────────────┘             │
│                                                 │
│  ┌──────────────┐  ┌──────────────┐             │
│  │  Sub Card    │  │  Bot/Web     │             │
│  │  订阅状态     │  │  控制面状态   │             │
│  └──────────────┘  └──────────────┘             │
│                                                 │
│  ┌─────────────────────────────────────────┐    │
│  │  Recent Operations Card                 │    │
│  │  最近操作摘要                            │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  ┌─────────────────────────────────────────┐    │
│  │  Recovery Tips Card                     │    │
│  │  恢复建议                                │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  Quick Actions                                  │
│  [Status] [Doctor] [Rotate] [Help]              │
│                                                 │
└─────────────────────────────────────────────────┘
```

### 响应式要求

- 桌面端：卡片两列布局
- 移动端：卡片单列堆叠
- 卡片宽度自适应
- 按钮全宽（移动端）
- 当前 `style.css` 已有基础响应式支持（`@media max-width: 600px`）

---

## 6. 状态颜色与语义规范

### 颜色映射

| 状态 | 颜色 | Badge 类 | 语义 |
|------|------|----------|------|
| `healthy` | 🟢 绿色 | `badge-ok` | 本地服务健康 |
| `verified` | 🟢 绿色 | `badge-ok` | 已通过明确验证 |
| `active` | 🟢 绿色 | `badge-ok` | 服务运行中 |
| `installed` | 🟡 黄色 | `badge-warn` | 已安装，不代表健康 |
| `planned` | 🟡 黄色 | `badge-warn` | 规划中，未执行 |
| `dry-run` | 🟡 黄色 | `badge-warn` | 仅模拟，未写入 |
| `manual_pending` | 🟡 黄色 | `badge-warn` | 需用户手动完成 |
| `warning` | 🟡 黄色 | `badge-warn` | 警告 |
| `skipped` | ⚪ 灰色 | `badge-muted` | 用户跳过 |
| `unknown` | ⚪ 灰色 | `badge-muted` | 未检查/不可确认 |
| `not configured` | ⚪ 灰色 | `badge-muted` | 未配置 |
| `failed` | 🔴 红色 | `badge-error` | 失败 |
| `unhealthy` | 🔴 火色 | `badge-error` | 不健康 |
| `missing` | 🔴 红色 | `badge-error` | 缺失（关键组件） |

### 展示规则

- `verified` 和 `healthy` 和 `active` 才使用绿色
- `installed` 不自动等同于 `healthy`
- `dry-run` 不自动等同于 `installed`
- `planned` 不自动等同于 `installed`
- `manual_pending` 必须给出下一步
- `skipped` 保持中性
- `failed` 必须展示 redacted 原因 + 恢复建议
- `unknown` 必须说明 "未检查/不可确认"，不能补写推测结果
- configured 不等于 verified（Bot/Web configured 不代表 VPS/CF verified）
- Subscription configured 不等于 subscription verified

---

## 7. Overall Status Card 规范

### 目的

Dashboard 顶部的全局摘要卡片，一眼看出整体状态。

### 卡片内容

```text
┌─────────────────────────────────────────┐
│  📊 NanoBK 状态总览                     │
│                                         │
│  整体状态：healthy                      │
│  最高风险问题：无                        │
│  部署验证：verified                     │
│  待处理操作：无                          │
│                                         │
│  建议：所有服务正常运行。                │
│  状态来源：nanobk CLI                    │
│  敏感地址已隐藏                          │
└─────────────────────────────────────────┘
```

### 允许字段

| 字段 | 展示方式 |
|------|----------|
| 整体状态 | healthy/failed/unknown/等 |
| 最高风险问题 | 无 / "HY2 服务未运行" / 等 |
| 部署验证状态 | verified/failed/unknown/manual_pending |
| 待处理操作 | 无 / "请完成 Cloudflare 验证" / 等 |
| 建议 | 安全文字建议 |
| 状态来源 | nanobk CLI / mock / not checked |

### 禁止字段

| 字段 | 原因 |
|------|------|
| raw IP/domain/URL | 安全 |
| raw tokens/secrets | 安全 |
| raw JSON | 用户体验 |
| raw stdout/stderr | 用户体验 |
| raw port | 产品决策待确认 |

### 整体状态计算逻辑（未来实现参考）

1. 如果任何关键组件 failed → 整体 failed
2. 如果所有关键组件 healthy/verified → 整体 healthy
3. 如果存在 manual_pending → 整体提示 manual_pending
4. 如果存在 unknown → 整体提示 unknown
5. 否则 → 取最低健康状态

---

## 8. VPS Card 规范

### 目的

Dashboard 和 Status 页面中的 VPS 状态卡片。

### 卡片内容（新手视图）

```text
┌─────────────────────────────────────────┐
│  🖥️ VPS 状态                            │
│                                         │
│  状态：healthy                          │
│  区域：🇯🇵 JP                            │
│                                         │
│  协议配置：                              │
│    HY2：✅ configured, active            │
│    TUIC：✅ configured, active           │
│    Reality：✅ configured, active        │
│    Trojan：✅ configured, active         │
│                                         │
│  安全：                                  │
│    密钥文件：✅ present                   │
│    权限模式：600                         │
│                                         │
│  状态来源：nanobk CLI                    │
│  敏感地址已隐藏                          │
└─────────────────────────────────────────┘
```

### 高级视图额外内容

```text
  诊断详情：
    profile：present
    admin env：present
    last check：2 分钟前
    warnings：none
```

### 允许字段（新手）

| 字段 | 展示方式 |
|------|----------|
| VPS 整体状态 | healthy/failed/unknown 等 |
| 区域 | 国旗 + 代码 |
| 协议存在性 | present/missing |
| 服务状态 | active/inactive/unknown |
| 配置存在性 | present/missing |
| 密钥存在性 | present/missing |
| 权限模式 | 600/other |

### 禁止字段（新手）

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
| 文件路径 | 安全 |

### 端口展示决策

与 v1.9.2 Bot spec 一致：

- 新手视图：不展示端口
- 高级视图：可展示协议端口（如 HY2: UDP 443）
- 最终决策需在实现前确认

---

## 9. Cloudflare Card 规范

### 目的

Dashboard 和 Status 页面中的 Cloudflare 状态卡片。

### 卡片内容（新手视图）

```text
┌─────────────────────────────────────────┐
│  ☁️ Cloudflare 状态                     │
│                                         │
│  nanok Worker：✅ configured             │
│  nanob Worker：✅ configured             │
│  管理员环境：✅ present                   │
│                                         │
│  验证状态：verified                      │
│  同步状态：verified                      │
│                                         │
│  状态来源：nanobk CLI                    │
└─────────────────────────────────────────┘
```

### 允许字段

| 字段 | 展示方式 |
|------|----------|
| nanok 配置状态 | configured/missing/unknown |
| nanob 配置状态 | configured/missing/unknown |
| admin env 状态 | present/missing/unknown |
| 验证状态 | verified/failed/unknown/manual_pending |
| 同步状态 | verified/failed/unknown/manual_pending |
| 安全下一步 | 文字建议 |

### 禁止字段

| 字段 | 原因 |
|------|------|
| Cloudflare API token | secret |
| Account ID | 敏感标识 |
| Worker 默认域名 | 安全 |
| workers.dev URL | 安全 |
| route URL | 安全 |
| subscription URL/path | 安全 |
| admin token | secret |
| raw env 内容 | 安全 |

---

## 10. Subscription Card 规范

### 目的

Dashboard 和 Status 页面中的订阅状态卡片。

### 卡片内容（新手视图）

```text
┌─────────────────────────────────────────┐
│  📱 订阅状态                            │
│                                         │
│  订阅服务：✅ configured                 │
│  包含协议：4/4                           │
│  最近验证：verified                      │
│                                         │
│  导入说明：                              │
│    请在 Clash/Mihomo 中导入订阅链接。    │
│    订阅地址可在 SSH 中运行：              │
│    nanobk status                         │
│                                         │
│  注意：Web Panel 不展示完整订阅 URL，    │
│  以保护安全。                            │
│                                         │
│  状态来源：nanobk CLI                    │
└─────────────────────────────────────────┘
```

### 允许字段

| 字段 | 展示方式 |
|------|----------|
| 订阅服务状态 | configured/missing/unknown |
| 包含协议数量 | 4/4, 3/4 等 |
| 最近验证状态 | verified/failed/unknown |
| 导入说明 | 文字指引，不含 raw URL |

### 禁止字段

| 字段 | 原因 |
|------|------|
| 完整订阅 URL | 安全 |
| subscription token | secret |
| workers.dev 域名 | 安全 |
| route URL | 安全 |
| raw path | 安全 |
| QR code（含 raw secret） | 安全 |

### 订阅 URL 交付策略

与 v1.9.2 Bot spec 一致：

**v1.9.3 不批准 Web Panel 直接交付 raw subscription URL。** 如果未来需要在 Web 中帮助用户导入订阅，需要：

1. 独立的安全设计
2. 考虑临时 URL + 过期机制
3. 考虑指纹确认而非明文展示
4. 考虑仅在受保护的本地访问环境中展示

---

## 11. Bot/Web Card 规范

### 目的

Dashboard 中展示控制面组件状态的卡片。

### 卡片内容（新手视图）

```text
┌─────────────────────────────────────────┐
│  🤖 控制面状态                          │
│                                         │
│  Telegram Bot：✅ active                 │
│  Web Panel：✅ active                    │
│  访问模式：local-only                    │
│                                         │
│  状态来源：nanobk CLI                    │
└─────────────────────────────────────────┘
```

### 允许字段

| 字段 | 展示方式 |
|------|----------|
| Bot 配置状态 | configured/missing/unknown |
| Bot 服务状态 | active/inactive/unknown |
| Web 配置状态 | configured/missing/unknown |
| Web 服务状态 | active/inactive/unknown |
| 访问模式 | local-only / public / unknown（安全可推导时） |
| 登录安全摘要 | 安全可推导时 |

### 禁止字段

| 字段 | 原因 |
|------|------|
| Bot token | secret |
| Web admin token | secret |
| raw bind address | 安全 |
| raw public URL | 安全 |
| raw tunnel URL | 安全 |
| raw env 内容 | 安全 |

---

## 12. Status 页面规范

### 目标

Status 页面展示比 Dashboard 更详细的状态信息。

### 新手 Status 页面

- 产品化卡片展示
- 无 raw JSON
- 无 raw stdout/stderr
- 无 raw IP/domain/URL/workers.dev/subscription path
- 每个卡片与 Dashboard 卡片一致，但可展示更多字段

### 高级 Status 页面

在新手基础上：

- Redacted 诊断详情
- 地址类 redaction 必须生效
- Redacted warnings 列表
- 协议配置详情
- 安全模式信息

### Raw JSON 区域（高级/Owner）

- 折叠式 `<details>` 块
- 默认折叠
- 需点击 "查看 Redacted 详情" 展开
- 展开前显示警告
- 内容必须经过完整 redaction（token + 地址类）
- 不展示 IP/domain/URL/workers.dev/subscription path

### 当前问题

当前 `status.html` 有一个 `<details>` 块直接展示 `status.raw_json`：

```html
<details>
  <summary>Raw JSON</summary>
  <pre>{{ status.raw_json }}</pre>
</details>
```

这是 v1.9.1 审计识别的中风险区域。未来实现必须：

1. 默认隐藏此块（高级模式才显示）
2. 展开前显示警告
3. 确保 `raw_json` 经过完整 redaction（包括地址类）

---

## 13. Raw JSON / details 策略

### 当前问题

- `status.html` 的 `<details>` 块展示 `status.raw_json`
- `format_status()` 返回的 `raw_json` 字段是 `json.dumps(redacted, indent=2)`
- 当前 `redact_json()` 覆盖 token/password/secret/private_key 类 key
- 当前 `redact_json()` 不覆盖 IP/domain/URL/workers.dev/subscription path
- 这是 v1.9.1 审计识别的已知中风险

### 策略决定

**Raw JSON 必须默认隐藏。**

| 决定 | 说明 |
|------|------|
| 默认隐藏 | Raw JSON `<details>` 块默认不在新手视图显示 |
| 高级可用 | L2 高级用户可点击展开 |
| 必须脱敏 | 必须经过 token + 地址类 redaction |
| 折叠默认 | 默认折叠，需显式点击展开 |
| 警告前置 | 展开前显示 "以下详情已脱敏，不替代日志" |
| 不展示敏感 | 不展示 IP/domain/URL/workers.dev/subscription path/private key/token |
| 理想替代 | 产品化状态卡片替代 raw JSON |

### 实现要求（未来）

1. `status.html` 的 `<details>` 块用高级模式条件包裹
2. 展开前显示警告文本
3. `format_status()` 的 `raw_json` 字段必须经过完整 redaction
4. `redact_json()` 必须增加地址类脱敏（IPv4/IPv6/domain/URL/workers.dev/subscription path）
5. Dashboard 的 `format_status()` 也需同步处理
6. API `/api/status` 的 `redact_json()` 也需同步处理

### 为什么保留而不是删除

- 高级用户和维护者可能需要 raw JSON 用于调试
- 完全删除会降低可调试性
- 但默认隐藏可以保护新手

---

## 14. Doctor 页面 UX 规范

### 风险级别

**中风险** — Doctor 是只读诊断，但输出可能包含路径/IP/域名/URL。

### 当前实现

- `GET /doctor`：展示 Doctor 页面
- `POST /doctor`：运行 `nanobk doctor`，展示 `safe_output()` 结果
- CSRF 保护：POST 需要 CSRF token

### 目标 UX

**新手视图：**

```text
┌─────────────────────────────────────────┐
│  🩺 健康检查                            │
│                                         │
│  [运行健康检查]  按钮                    │
│                                         │
│  检查完成，未发现问题。                  │
│                                         │
│  或：                                   │
│                                         │
│  ⚠️ 发现问题 2 项：                     │
│    - HY2 服务未运行                      │
│    - admin env 权限不正确                │
│                                         │
│  建议：在 SSH 中运行恢复命令             │
│  （见 Recovery 页面）                    │
└─────────────────────────────────────────┘
```

**高级视图：**

在新手基础上，提供 "查看详情" 折叠块：

```text
  [查看 Redacted 详情]  ← 点击展开

  ⚠️ 以下详情已脱敏，不替代 SSH 日志。

  [redacted 诊断输出]
  exit code: 1
```

### 规则

| 规则 | 说明 |
|------|------|
| 新手摘要 | 只显示通过/发现问题/需要 SSH |
| 新手无 raw | 不显示 raw stdout/stderr |
| 失败给恢复 | 失败时给出恢复提示 |
| 高级 redacted | 显示 redacted 详情 |
| 高级 exit code | 显示 exit code |
| 警告前置 | 展开前显示脱敏警告 |
| 无 raw secret | 仍然不展示 raw secret/IP/domain/URL |
| CSRF 保护 | POST 需要 CSRF token |

### 为什么是中风险

- Doctor 是只读命令，不修改任何配置
- 但其输出可能包含系统路径、IP 地址、域名等
- 因此不能无条件展示给新手
- 在证明 Doctor 输出完全安全之前，保持中风险

---

## 15. Rotate 页面 UX 规范

### 风险级别

**高风险** — Rotate 会修改凭证并重启服务。

### 当前实现

- `GET /rotate`：展示协议选择页面
- `POST /rotate/request`：请求确认（设置 session pending）
- `POST /rotate/confirm`：确认执行（CSRF + pending 验证）
- `POST /rotate/cancel`：取消
- 120 秒过期
- 默认 dry-run `true`

### 目标 UX

**第一步：协议选择**

```text
┌─────────────────────────────────────────┐
│  🔄 轮换密钥                            │
│                                         │
│  选择要轮换的协议：                      │
│                                         │
│  [全部协议]  [HY2]  [TUIC]              │
│  [Reality]  [Trojan]                    │
│                                         │
│  ⚠️ 轮换会重启服务并更新凭证。          │
│  需要二次确认。                          │
│                                         │
│  当前模式：DRY-RUN（仅模拟）            │
└─────────────────────────────────────────┘
```

**第二步：确认页面**

```text
┌─────────────────────────────────────────┐
│  ⚠️ 确认轮换 TUIC                       │
│                                         │
│  即将执行：                              │
│    nanobk rotate tuic --yes             │
│                                         │
│  影响：                                  │
│    - TUIC 服务将重启                     │
│    - TUIC 凭证将更新                     │
│    - 本地 profile 将更新                 │
│    - Cloudflare 同步取决于配置           │
│                                         │
│  [✅ 确认轮换]  [❌ 取消]               │
└─────────────────────────────────────────┘
```

**第三步：执行结果**

```text
┌─────────────────────────────────────────┐
│  🔄 TUIC 轮换结果                       │
│                                         │
│  ✅ 轮换成功                            │
│  exit code: 0                           │
│                                         │
│  状态：TUIC 服务已重启                   │
│  敏感信息已隐藏                          │
│                                         │
│  如需恢复，请在 SSH 中运行：             │
│    nanobk rotate tuic                    │
└─────────────────────────────────────────┘
```

### 确认机制要求

| 要求 | 当前状态 | v1.9.3 要求 |
|------|----------|-------------|
| 两步确认 | ✅ 已有 | 保持 |
| CSRF 保护 | ✅ 已有 | 保持 |
| 120 秒过期 | ✅ 已有 | 保持 |
| 协议白名单 | ✅ 已有 | 保持 |
| dry-run 支持 | ✅ 已有 | 保持 |
| 影响说明 | ⚠️ 简单 | 增强为详细说明 |
| 结果摘要 | ⚠️ raw output | 改为安全摘要 |
| 恢复建议 | ❌ 无 | 增加恢复建议 |

### 禁止

- 禁止无确认直接执行
- 禁止展示 raw CLI 输出
- 禁止展示更新后的凭证
- 禁止展示 secret/private key

---

## 16. Operations 页面规范

### 操作风险分组

#### 安全只读操作

| 操作 | 确认 | 说明 |
|------|------|------|
| 状态刷新 | 无 | 重新加载 Dashboard/Status |
| 查看帮助 | 无 | 帮助文本 |
| 查看恢复建议 | 无 | 恢复命令 |
| 查看版本 | 无 | 版本信息 |

#### 中风险操作

| 操作 | 确认 | 说明 |
|------|------|------|
| 运行 Doctor | CSRF + 简单警告 | 只读诊断 |
| 高级诊断详情 | 点击展开 + 警告 | Redacted 详情 |
| 查看 Redacted Raw JSON | 高级模式 + 点击展开 + 警告 | 调试用 |

#### 高风险操作

| 操作 | 确认 | 说明 |
|------|------|------|
| 轮换密钥 | CSRF + 两步确认 | 修改凭证 |
| 重启服务 | CSRF + 两步确认 | 未实现 |
| Cloudflare 操作 | CSRF + 两步确认 | 未实现 |
| Repair 操作 | CSRF + 两步确认 | 未实现 |
| 部署阶段重跑 | CSRF + 两步确认 | 未实现 |

### 新增高风险操作的规则

未来如果新增高风险操作，必须：

1. 第一步：说明 CLI 命令、影响范围、可能中断、预计耗时
2. 第二步：用户显式确认（CSRF 保护的 POST 表单）
3. 执行后：展示 redacted 结果、exit code、状态、恢复建议
4. 确认过期：120 秒无确认自动清除

---

## 17. Recovery 页面规范

### 目标

帮助用户在 Bot/Web 无法完成操作时，通过 SSH 恢复。

### 页面内容

```text
┌─────────────────────────────────────────┐
│  🆘 恢复帮助                            │
│                                         │
│  最近失败：                              │
│    HY2 服务重启失败                      │
│    时间：5 分钟前                        │
│                                         │
│  建议恢复命令：                          │
│    nanobk doctor                         │
│    nanobk rotate hy2                     │
│    nanobk status                         │
│                                         │
│  需要 SSH 访问：                         │
│    请通过 SSH 连接 VPS 执行以上命令。    │
│                                         │
│  安全提示：                              │
│    - 不要分享你的 token 或密钥           │
│    - 不要在公共频道粘贴完整命令输出      │
│    - 如需帮助，请描述问题而非粘贴日志    │
└─────────────────────────────────────────┘
```

### 允许字段

| 字段 | 展示方式 |
|------|----------|
| 最近失败步骤 | redacted 摘要 |
| 失败时间 | 相对时间 |
| 建议恢复命令 | 安全 CLI 命令 |
| 是否需要 SSH | 是/否 |
| 是否需要手动 CF 操作 | 是/否 |
| 安全提示 | 文字提示 |

### 禁止字段

| 字段 | 原因 |
|------|------|
| raw 日志 | 安全 |
| raw env 内容 | 安全 |
| raw tokens | 安全 |
| raw URLs | 安全 |
| raw 命令输出（含 secret） | 安全 |
| raw IP/domain | 安全 |

---

## 18. Recent Operations / Logs 规范

### 现状

v1.8 的 operation-log groundwork 未完全 rollout。v1.9.3 不批准 operation-log full rollout。

### 规则

| 规则 | 说明 |
|------|------|
| 仅展示安全摘要 | 只展示操作类型、时间、结果状态 |
| 不展示 raw 日志 | 新手视图不展示 raw operation-log 内容 |
| 日志路径安全 | 日志路径仅在安全且不泄露用户 home/repo 路径时展示 |
| 详细日志需审批 | Verbose/raw logs 需要单独审批 |
| 无 production wrapper | 不实现 production status wrapper |
| 无 dirty wrapping | 不做 dirty VPS status wrapping |
| 无 full rollout | 不做 operation-log full rollout |

### 卡片内容（安全摘要）

```text
┌─────────────────────────────────────────┐
│  📋 最近操作                            │
│                                         │
│  轮换 TUIC     ✅ 成功    2 分钟前      │
│  健康检查      ⚠️ 有问题  10 分钟前     │
│  状态刷新      ✅ 成功    30 分钟前     │
│                                         │
│  详细操作日志需要在 SSH 中查看。         │
└─────────────────────────────────────────┘
```

---

## 19. Auth / Session / CSRF UX 规范

### Token 登录

**当前实现：**

- `GET /login`：展示登录表单
- `POST /login`：验证 `NANOBK_WEB_TOKEN`
- 成功：设置 session，重定向到 Dashboard
- 失败：显示 "Invalid token."

**目标 UX：**

```text
┌─────────────────────────────────────────┐
│  🔐 NanoBK Web Panel                   │
│                                         │
│  请输入访问令牌：                        │
│  [________________________________]     │
│  [登录]                                 │
│                                         │
│  令牌在 bot/.env 或 web/.env 中配置。   │
└─────────────────────────────────────────┘
```

**安全规则：**

- 失败消息不区分 "token 不存在" 和 "token 错误"
- 不显示 token 长度或格式信息
- 不显示有效 token 列表
- 登录页面不泄露 Web Panel 版本

### Session 过期

- Session 过期后重定向到登录页
- 显示 "Session 已过期，请重新登录"
- 不泄露过期原因细节

### Logout

- POST 表单 + CSRF 验证
- 清除 session
- 重定向到登录页

### CSRF 失败

**当前实现：**

- `abort(403, "CSRF validation failed.")`

**目标 UX：**

```text
┌─────────────────────────────────────────┐
│  ❌ 请求被拒绝                          │
│                                         │
│  CSRF 验证失败。                        │
│  请返回主页重试。                        │
│                                         │
│  [返回主页]                             │
└─────────────────────────────────────────┘
```

**安全规则：**

- CSRF 失败消息不泄露 token 信息
- 不显示技术细节（如 "CSRF token mismatch"）
- 提供安全的恢复操作（返回主页）

### 未授权访问

- 重定向到登录页
- 不显示 "你没有权限" 的详细信息
- 不泄露有效用户信息

### 本地/公网绑定警告

如果 Web Panel 检测到绑定地址不是 `127.0.0.1`：

```text
⚠️ 安全警告

Web Panel 当前绑定到非本地地址。
请确保你了解安全风险。

建议：使用 SSH 隧道或 VPN 访问。
```

---

## 20. 文案规范

### 核心规则

| 规则 | 说明 |
|------|------|
| 简短 | 适合浏览器阅读，卡片内容精简 |
| 产品化 | 像产品 UI，不像脚本输出 |
| 小白友好 | 不使用技术术语，或解释技术术语 |
| 不假装成功 | unknown/skipped/dry-run 不显示为 success |
| 默认不展示 raw 日志 | 新手看摘要，高级看 redacted 详情 |
| 使用诚实状态 | healthy/failed/unknown/manual_pending/skipped |
| 解释下一步 | 每个结果都告诉用户可以做什么 |
| 说明何时需要 SSH | 有些操作 Web 无法完成，需引导到 SSH |
| 说明秘密已隐藏 | 告诉用户敏感信息已脱敏 |
| 不指责用户 | 失败时不说 "你做错了"，说 "发生了问题" |
| 不展示 scary raw error | 新手视图不展示 raw stderr/stack trace |

### UI 文本模板

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

完成后，Web Panel 会自动检测。
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

**Raw 详情警告：**

```text
⚠️ 以下详情已经过脱敏处理。
不替代 SSH 日志。敏感地址已隐藏。
```

---

## 21. 与 Bot UX 的一致性

### 映射表

| Bot 概念 | Web 等价 | 共享状态语义 | 共享 Redaction | 差异 |
|----------|----------|-------------|---------------|------|
| 📊 状态总览 | Dashboard Overall Card | ✅ 相同状态类别 | ✅ 相同脱敏 | Bot 用文字，Web 用卡片 |
| 🖥️ VPS 状态 | VPS Card | ✅ 相同字段 | ✅ 相同脱敏 | Bot 用文字，Web 用卡片 |
| ☁️ Cloudflare | CF Card | ✅ 相同字段 | ✅ 相同脱敏 | Bot 用文字，Web 用卡片 |
| 📱 订阅状态 | Sub Card | ✅ 相同字段 | ✅ 相同脱敏 | Bot 用文字，Web 用卡片 |
| 🤖 Bot 状态 | Bot/Web Card | ✅ 相同字段 | ✅ 相同脱敏 | Web 增加 Web 自身状态 |
| 🩺 健康检查 | Doctor 页面 | ✅ 相同风险级别 | ✅ 相同脱敏 | Web 用表单触发 |
| 🔄 轮换密钥 | Rotate 页面 | ✅ 相同风险级别 | ✅ 相同脱敏 | Web 用表单 + CSRF |
| 🆘 恢复帮助 | Recovery 页面 | ✅ 相同内容 | ✅ 相同脱敏 | Web 独立页面 |
| Raw JSON | `<details>` 块 | ✅ 相同策略 | ✅ 相同脱敏 | Web 用 HTML details |
| ❓ 帮助 | Help 页面 | ✅ 相同内容 | ✅ 相同脱敏 | Web 用页面 |
| 用户分层 L1/L2/L3 | 视图切换开关 | ✅ 相同三层模型 | ✅ 相同规则 | Bot 用命令，Web 用开关 |
| 确认流 | CSRF + 表单确认 | ✅ 相同两步模型 | ✅ 相同规则 | Web 增加 CSRF |

### 一致性规则

1. **状态类别完全一致**：Bot 和 Web 使用相同的 healthy/verified/failed/unknown 等类别
2. **Redaction 策略完全一致**：Bot 和 Web 使用相同的脱敏规则
3. **风险分级完全一致**：只读/中风险/高风险的定义和确认要求相同
4. **Raw JSON 策略完全一致**：默认隐藏，高级可用，必须脱敏
5. **禁止字段完全一致**：IP/domain/URL/workers.dev/subscription path/token/secret
6. **文案风格一致**：都使用诚实、友好、不指责的文案

### 差异

| 维度 | Bot | Web |
|------|-----|-----|
| 交互方式 | InlineKeyboardButton | HTML 表单 + 按钮 |
| 确认方式 | 按钮回调 | POST 表单 + CSRF |
| 视图切换 | `/advanced on` 命令 | 页面开关 |
| 布局 | 线性消息流 | 卡片网格 |
| 响应式 | Telegram 自适应 | CSS 响应式 |
| 认证 | Owner-only (Telegram ID) | Token 登录 |
| Session | 无（每次检查 owner） | Flask session |

---

## 22. 未来测试要求

### v1.9.3 不实现测试，只定义需求

### Tier 1 单元测试

| 测试 | 说明 |
|------|------|
| Dashboard 渲染测试 | 所有卡片正确渲染 |
| 卡片渲染测试 | 每个卡片类型正确展示 |
| 新手视图不含 raw JSON | 页面不包含 JSON 语法 |
| 新手视图不含 IP/domain/URL | 页面不包含 IP 地址、域名、URL |
| 新手视图不含 workers.dev | 页面不包含 workers.dev |
| 新手视图不含 subscription URL | 页面不包含订阅 URL |
| Raw JSON 默认隐藏 | `<details>` 块默认折叠 |
| Raw JSON 高级可用 | 高级模式下可展开 |
| Rotate 仍需 CSRF + 确认 | POST 需要 CSRF + pending |
| Doctor 输出已脱敏 | 输出不包含 raw secret |
| 失败输出已脱敏 | stderr 经过 redaction |
| unknown/skipped/dry-run 不显示为 success | 诚实状态展示 |
| 无直接写入 | 无 open(write) 调用 |
| 无 shell=True | subprocess 无 shell 参数 |
| 无 env cat 模式 | 不读取 .env 文件内容 |
| 无 raw stack trace | 新手视图不展示 stack trace |
| Auth/Session/CSRF 安全错误 | 错误消息不泄露 token |

### Tier 2 回归测试

| 测试 | 说明 |
|------|------|
| `tests/web-panel-mock.sh` | 现有测试继续通过 |
| CSRF 保护测试 | 所有 POST 需要 CSRF |
| 确认流端到端测试 | 选择 → 确认 → 执行 → 结果 |
| 高级视图切换测试 | 开关正确切换 |
| 过期确认测试 | 120 秒后确认失效 |
| Session 过期测试 | Session 过期后重定向登录 |
| 响应式布局测试 | 移动端正确堆叠 |

### Tier 3 手动测试

| 测试 | 说明 |
|------|------|
| 浏览器 UX 测试 | 在真实浏览器中测试布局 |
| 移动端 UX 测试 | 在手机浏览器中测试 |
| 按钮可点击性测试 | 所有按钮可正常点击 |
| 长内容截断测试 | 长输出正确处理 |
| 错误场景测试 | 各种失败场景的展示 |

---

## 23. v1.9.4 推荐

### 推荐：v1.9.4 — Bot/Web Command Allowlist Spec and Static Tests

**理由：**

1. Bot 和 Web 的 UX spec 现在都已完成
2. v1.9.1 审计已识别所有 CLI 调用路径
3. 实现不应在命令白名单和禁止类别编纂之前开始
4. Allowlist 测试可以防止直接写入和不安全的 shell 路径
5. 先定义允许的命令，再实现 UX，可以确保安全边界

**v1.9.4 应包含：**

- Bot/Web 允许调用的 `nanobk` CLI 命令白名单
- 禁止的命令类别（直接 shell、systemctl、文件写入等）
- 静态测试：Bot/Web 代码中不存在白名单外的 CLI 调用
- 静态测试：Bot/Web 代码中不存在 `shell=True`
- 静态测试：Bot/Web 代码中不存在直接文件写入
- Allowlist 测试可以集成到 CI

**不推荐立即实现 Web/Bot：**

- UX spec 需要人工审核
- Allowlist spec 应先完成
- Redaction 层（v1.9.5）应先就位
- 实现应小步、可 review、可回滚

---

## 24. Implementation Guardrails

### 硬性约束

以下约束适用于 v1.9.x 系列所有实现任务：

| # | 约束 | 说明 |
|---|------|------|
| 1 | 禁止 Web 直接写 configs/systemd/secrets/env | 必须通过 nanobk CLI |
| 2 | 禁止新手视图展示 raw JSON | 使用安全摘要 |
| 3 | 禁止新手视图展示 raw IP/domain/URL/workers.dev/subscription path | 默认脱敏 |
| 4 | 禁止高风险操作无确认 | rotate/restart/repair 必须两步确认 + CSRF |
| 5 | 禁止直接 systemctl | 必须通过 nanobk CLI |
| 6 | 禁止读取 env 内容 | 不读取 .env 文件 |
| 7 | 所有操作通过 nanobk CLI | 不绕过 CLI |
| 8 | 高风险操作两步确认 + CSRF | 已有机制，保持并增强 |
| 9 | 禁止 production status wrapper | 未批准 |
| 10 | 禁止 dirty VPS status wrapping | 未批准 |
| 11 | 禁止 operation-log full rollout | 未批准 |
| 12 | 禁止修改 install.sh | 保护 v1.7.27 基线 |
| 13 | 禁止 tag/release | 未批准 |
| 14 | 所有输出经过 safe_output/redact_json | 包括失败输出 |
| 15 | 所有 POST 需要 CSRF 验证 | 已有机制 |
| 16 | 禁止 shell=True | subprocess 必须使用 list 形式 |
| 17 | 禁止新手视图展示 raw stack trace | 错误消息友好化 |
| 18 | 错误消息不泄露 token/secret | 安全错误处理 |

### 实现前必须完成

1. v1.9.2 Bot UX/Menu Spec — ✅ 已完成
2. v1.9.3 Web Dashboard UX Spec（本文件）— ✅ 已完成
3. v1.9.4 Command Allowlist Spec/Tests — 待完成
4. v1.9.5 Redaction Layer Audit/Tests — 待完成

### 实现顺序建议

1. v1.9.4 Allowlist 定义 + 静态测试（命令白名单，执行安全边界）
2. v1.9.5 Redaction 层就位（地址类脱敏，显示安全边界）
3. 两者都通过后：Bot/Web UX 小步实现
4. 实现应小步、可 review、可回滚

---

## 附录 A：当前 Web 路由列表

来自 `web/app.py`：

```python
# 路由
GET  /                  → dashboard()
GET  /status            → status()
GET  /api/status        → api_status()
GET  /doctor            → doctor()         # 展示页面
POST /doctor            → doctor()         # 运行诊断
GET  /rotate            → rotate()         # 展示页面
POST /rotate/request    → rotate_request() # 请求确认
POST /rotate/confirm    → rotate_confirm() # 确认执行
POST /rotate/cancel     → rotate_cancel()  # 取消
GET  /login             → login()          # 展示页面
POST /login             → login()          # 登录
POST /logout            → logout()         # 登出
GET  /healthz           → healthz()        # 健康检查
```

## 附录 B：当前 Web 模板列表

```
web/templates/
├── layout.html      # 布局（导航栏 + CSRF logout）
├── login.html       # 登录表单
├── index.html       # Dashboard（status card + quick actions）
├── status.html      # 状态页（status card + Raw JSON details）
├── doctor.html      # Doctor 页（POST 触发 + output pre）
└── rotate.html      # Rotate 页（协议选择 + 确认流程）
```

## 附录 C：nanobk CLI 命令参考

Web 可调用的 CLI 命令（allowlist）：

```bash
nanobk --version              # 版本信息
nanobk --help                 # 帮助
nanobk status                 # 文本状态
nanobk --json status          # JSON 状态
nanobk doctor                 # 环境诊断
nanobk rotate <proto> --yes   # 轮换密钥
```

## 附录 D：参考文档

| 文档 | 说明 |
|------|------|
| `docs/planning-v1.9.0-bot-web-control-plane-productization.md` | v1.9 范围提案 |
| `docs/audit-v1.9.1-bot-web-current-state-safety.md` | v1.9.1 安全审计 |
| `docs/spec-v1.9.2-bot-ux-menu.md` | v1.9.2 Bot UX/Menu Spec |
| `web/README.md` | Web 当前文档 |
| `web/app.py` | Web 当前代码 |
