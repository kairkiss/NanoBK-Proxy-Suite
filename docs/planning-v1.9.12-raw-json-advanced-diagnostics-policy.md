# v1.9.12 — Raw JSON / Advanced Diagnostics Policy Planning

> 规划类型：策略/政策规划文档
> 日期：2026-06-05
> 基线 commit：`8eb59f36d0e7155763d883012055f3bb569bc2ea`
> 基线信息：`feat: add web safe status cards`

---

## 1. 本轮目标与结论

**v1.9.12 是策略/规划文档任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无部署逻辑变更
- ✅ 无 `install.sh` 变更
- ✅ 无 `bin/nanobk` 变更
- ✅ 无 tag/release
- ✅ 目的是决定未来 Raw JSON / 高级诊断策略

**结论：定义 Bot `/status_json` 和 Web Raw JSON details 的可见性策略、高级诊断模式设计、警告文案、安全边界和推荐实现路线。**

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

### 当前残留

| 项 | 状态 | 风险 |
|----|------|------|
| Bot `/status_json` | 仍存在，仍显示在 `/help` 中 | 中 |
| Web Raw JSON details | 仍存在于 Status 页面 `<details>` 块 | 中 |
| `/api/status` | 仍返回 redacted JSON | 低 |
| 高级模式 | 未实现 | — |
| 订阅交付 | 阻塞 | — |
| Production status wrapper | 阻塞 | — |

---

## 3. 风险判断

### Raw JSON / 高级诊断的风险

| 风险 | 说明 | 严重度 |
|------|------|--------|
| 结构泄露 | 即使脱敏，JSON 字段名可能暗示部署拓扑 | 中 |
| 占位符计数 | 重复的 `[REDACTED]` 占位符可能暗示组件数量 | 低 |
| 路径泄露 | `profile.currentPath` 等字段可能泄露本地路径 | 中 |
| Geo/端口未决 | 产品决策未定 | 低 |
| 用户复制粘贴 | 用户可能将 debug JSON 转发给他人 | 中 |
| 误导新手 | 新手可能将 raw JSON 误认为最终状态 | 中 |
| 非默认视图 | Raw JSON 不应成为默认产品视图 | 高 |

### Raw JSON / 高级诊断的价值

| 价值 | 说明 |
|------|------|
| 调试 | 开发者需要查看完整状态结构 |
| 支持 | 远程支持需要诊断信息 |
| Schema 对比 | 需要验证 status JSON 结构演变 |
| 测试 Fixture | 测试需要参考真实输出格式 |
| 未知状态诊断 | `unknown`/`failed`/`manual_pending` 需要详细信息 |

---

## 4. 用户分层策略

### L1 新手 / 默认用户

**应看到：**

- 安全状态摘要（Bot `/status`）
- 安全状态卡片（Web Dashboard/Status）
- 恢复提示
- 下一步建议

**不应看到：**

- Raw JSON
- Raw CLI 输出
- 地址类值（IP/domain/URL/subscription path）
- 任何 `[REDACTED]` 占位符

### L2 高级 / 高级诊断

**可看到：**

- 脱敏后的 JSON
- 脱敏后的诊断详情
- 显示前的警告
- 警告说明输出已脱敏但仍含结构信息

**仍不可看到：**

- Raw secrets
- Raw IP/domain/URL/subscription path
- Raw env 内容

### L3 Owner / 维护者

**未来可触发：**

- 高风险操作（需确认）

**仍不可看到：**

- Raw secrets
- Raw env
- Reality private key
- Raw subscription token
- Raw Cloudflare token

**重要：** "owner" 不等于有权泄露 secrets。Owner 权限仅用于操作触发，不用于信息泄露。

---

## 5. Bot `/status_json` 策略

### 当前行为

- 命令仍存在
- 仍显示在 `/help` 中
- 输出经过 `safe_output()` 脱敏
- 调用 `nanobk --json status`

### 推荐方向

**保留命令可用，但不作为新手入口。**

### 实现选项

| 选项 | 说明 | 推荐 |
|------|------|------|
| A. 保留但添加警告文本 | 输出前显示警告 | ✅ 推荐 |
| B. 重命名为 `/debug_status_json` | 更明确的调试语义 | 可选 |
| C. 从 `/help` 隐藏，文档化为高级 | 减少新手可见性 | ✅ 推荐 |
| D. 门控于 `/advanced on` | 需要显式启用 | 未来考虑 |
| E. 保持当前命令但输出以警告开头 | 最小改动 | ✅ 推荐 |

### 推荐策略

**选项 A + C 组合：**

1. 从 `/help` 的主列表中移除 `/status_json`
2. 在 `/help` 底部添加"高级诊断"小节，列出 `/status_json`
3. `/status_json` 执行时先显示警告文本
4. 输出保持经过 shared helper 脱敏
5. 不实现完整高级模式

### 推荐理由

- 最小改动，不破坏现有调试工作流
- 减少新手误用风险
- 警告文本提醒用户不要盲目分享
- 为未来高级模式留出空间

---

## 6. Web Raw JSON Details 策略

### 当前行为

- Raw JSON details 存在于 Status 页面 `<details>` 块
- 默认折叠（需点击展开）
- 值经过 shared redaction 脱敏
- `/api/status` 返回 redacted JSON

### 推荐方向

**Raw JSON details 最终应为高级/Owner-only。**

### 实现选项

| 选项 | 说明 | 推荐 |
|------|------|------|
| A. 保持可见但添加更强警告 | 在 `<details>` 前添加警告 | ✅ 推荐 |
| B. 隐藏于高级切换 | 需要 session flag | 未来考虑 |
| C. Dashboard 隐藏，Status 保留 | 分页面处理 | 可选 |
| D. Owner-only 视图 | 登录后 session flag | 未来考虑 |
| E. 下载/导出阻塞 | 独立策略 | 未来考虑 |

### 推荐策略

**选项 A 为当前步骤：**

1. 在 `<details>` 块前添加警告文案
2. 保持 `<details>` 默认折叠
3. 值保持经过 shared redaction
4. 不实现高级切换

**选项 B/D 为未来步骤：**

1. 实现 session 级高级模式 toggle
2. Raw JSON details 默认隐藏
3. 需要显式启用才显示

### 推荐理由

- 当前步骤最小改动，不破坏调试
- 警告文案提醒用户不要盲目分享
- 为未来高级模式留出空间
- 不需要 session 管理变更

---

## 7. 高级模式设计选项

### Bot 高级模式

| 方案 | 说明 | 优点 | 缺点 |
|------|------|------|------|
| `/advanced on` | 显式命令启用 | 简单明确 | 需要记住命令 |
| `/advanced off` | 显式命令禁用 | 简单明确 | 需要记住命令 |
| Session 限制 | Bot 重启后重置 | 安全 | 需要重新启用 |
| Owner-only | 仅 owner 可启用 | 安全 | 已有 owner 检查 |
| 启用前警告 | 启用时显示警告 | 用户知情 | 增加交互 |
| 超时自动重置 | N 分钟后自动禁用 | 安全 | 可能意外中断 |

### Web 高级模式

| 方案 | 说明 | 优点 | 缺点 |
|------|------|------|------|
| Session flag | 登录后设置 | 简单 | session 过期后重置 |
| UI toggle | 页面上的开关 | 直观 | 需要前端变更 |
| 警告弹窗 | 启用前确认 | 用户知情 | 增加交互 |
| 自动过期 | N 分钟后自动禁用 | 安全 | 可能意外中断 |
| Owner-only | 已有 token 登录 | 安全 | 已有安全基础 |
| 持久化 toggle | 记住偏好 | 方便 | 安全风险 |

### 推荐最小设计

**Bot：**

- `/advanced on` 启用，`/advanced off` 禁用
- 启用时显示警告
- Bot 重启后自动重置
- 仅 owner 可用

**Web：**

- Session 级 flag
- 页面上的 toggle 开关
- 启用前显示警告弹窗
- Session 过期后自动重置
- 已有 token 登录保护

---

## 8. 警告文案

### Bot 警告文案

**中文：**

```
⚠️ 高级诊断输出已脱敏，但仍可能包含系统结构信息。
不要把完整输出转发给不可信的人。
敏感地址和密钥已隐藏。
```

**English：**

```
⚠️ Advanced diagnostic output is redacted but may still contain system structure information.
Do not forward the full output to untrusted parties.
Sensitive addresses and secrets are hidden.
```

### Web 警告文案

**中文：**

```
⚠️ Raw JSON 已脱敏，仅用于高级诊断。
它不是普通用户状态页，也不应作为订阅信息分享。
敏感地址和密钥已隐藏。
```

**English：**

```
⚠️ Raw JSON is redacted and intended for advanced diagnostics only.
It is not a normal user status page and should not be shared as subscription information.
Sensitive addresses and secrets are hidden.
```

### 要求

- 新手友好
- 不吓人
- 清晰明确
- 说明输出已脱敏但仍敏感
- 说明不要盲目分享
- 说明不应出现 secrets
- 说明优先使用安全状态摘要

---

## 9. Raw JSON 内容规则

### 必须

- 必须经过 shared redaction
- 必须不包含 raw IP/domain/URL/workers.dev/subscription path
- 必须不包含 token/secret/private key
- 必须不包含 raw env 内容
- 必须不用于订阅交付

### 允许

- 可保留 status 字段
- 可保留服务名称和布尔值
- 可保留 unknown/failed/manual_pending/planned/dry-run/skipped
- 可保留脱敏占位符

### 禁止

- 禁止 raw IP 地址
- 禁止 raw 域名
- 禁止 raw URL
- 禁止 workers.dev
- 禁止 subscription URL/path
- 禁止 token/secret/private key
- 禁止 raw env 内容
- 禁止用于订阅交付

---

## 10. 复制/粘贴支持策略

### 用户可安全粘贴到支持渠道的内容

**允许：**

- 安全状态摘要
- 安全状态卡片
- 脱敏后的诊断片段
- 不含 raw env 的测试输出
- 失败步骤名称

**禁止：**

- Raw env 文件
- Raw subscription URL
- Real workers.dev URL
- Real VPS IP/domain
- Tokens/secrets/private keys
- Reality private key
- Cloudflare token
- Bot token
- Admin token

---

## 11. 未来实现的测试策略

### Bot 测试

| 测试 | 说明 |
|------|------|
| `/help` 不在新手区域显示 `/status_json` | 如果策略选择隐藏 |
| `/status_json` 警告出现 | 警告文本测试 |
| `/advanced on/off` 行为 | 如果实现高级模式 |
| 高级模式过期 | 如果选择超时重置 |
| `/status_json` 输出保持脱敏 | 脱敏验证 |
| 无 raw IP/domain/URL/workers.dev/subscription path | 地址类验证 |

### Web 测试

| 测试 | 说明 |
|------|------|
| Raw JSON details 默认折叠 | 折叠状态测试 |
| 警告出现 | 警告文案测试 |
| 高级切换需要 | 如果实现高级模式 |
| Session 行为正常 | Session 管理测试 |
| Raw JSON 仍脱敏 | 脱敏验证 |
| 普通卡片不受影响 | 回归测试 |
| 无 raw IP/domain/URL/workers.dev/subscription path | 地址类验证 |

### 共享测试

| 测试 | 说明 |
|------|------|
| Bot/Web 高级诊断保持状态诚实 | 诚实性验证 |
| 无直接 env 读取 | 安全验证 |
| 无 raw 订阅交付 | 安全验证 |
| 现有 v1.9.4–v1.9.11 测试通过 | 回归验证 |

---

## 12. 推荐实现路线

### 分阶段路线

| 版本 | 内容 | 范围 |
|------|------|------|
| v1.9.13 | Bot `/status_json` 警告 + `/help` 分类 | 小步 |
| v1.9.14 | Web Raw JSON 警告文案 | 小步 |
| v1.9.15 | Bot 高级模式规划或最小实现 | 中步 |
| v1.9.16 | Web 高级模式规划或最小实现 | 中步 |
| v1.9.17 | 高级诊断检查点 | 检查点 |

### 推荐理由

- 不推荐立即隐藏一切（可能破坏现有调试工作流）
- 不推荐广泛实现
- 小步推进，每步可审核
- 警告文案先于高级模式
- 高级模式需要 session 管理变更

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

**A. READY FOR SMALL RAW JSON WARNING IMPLEMENTATION**

**范围限制：**

- ✅ 就绪于警告文案和 `/help` 分类
- ❌ 不就绪于高级模式实现
- ❌ 不就绪于隐藏 Raw JSON
- ❌ 不就绪于 `/status_json` 移除
- ❌ 不就绪于 tag/release

---

## 15. 推荐下一步

**推荐：v1.9.13 — Bot `/status_json` Warning and Help Classification**

**理由：**

1. Bot `/status_json` 是更直接的 raw 命令，用户通过 `/help` 发现
2. 从 `/help` 主列表移除 + 添加警告是最小改动
3. 不需要 session 管理变更
4. 不破坏现有调试工作流
5. 为 Web 警告和高级模式铺路

**v1.9.13 应包含：**

- 从 `/help` 主列表移除 `/status_json`
- 在 `/help` 底部添加"高级诊断"小节
- `/status_json` 执行时先显示警告文本
- 输出保持经过 shared helper 脱敏
- 测试验证警告出现和 `/help` 分类

**不推荐立即实现：**

- 高级模式（需要 session 管理）
- 隐藏 `/status_json`（可能破坏调试）
- Web 高级切换（需要前端变更）

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
